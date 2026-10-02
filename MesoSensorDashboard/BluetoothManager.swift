//
//  BluetoothManager.swift
//  MesoSensorDashboard
//

import Combine
import CoreBluetooth
import Foundation
import SwiftData

enum BreathTestState: Equatable, Sendable {
    case idle
    case warmingUp
    case blowNow
    case processing
    case completed
    case timeout

    nonisolated static func == (lhs: BreathTestState, rhs: BreathTestState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.warmingUp, .warmingUp),
             (.blowNow, .blowNow),
             (.processing, .processing),
             (.completed, .completed),
             (.timeout, .timeout):
            return true
        default:
            return false
        }
    }
}

enum ConnectionStrategy: Sendable {
    case batterySaver
    case emergency
}

enum AlertVisualTheme: Sendable {
    case none
    case fineParticulates
    case allergenProfile
    case generalCoarse
}

class BluetoothManager: NSObject, AirQualityManagerProtocol, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var breathTestState: BreathTestState = .idle
    @Published var countdownSeconds: Int = 0
    @Published var lastSentCommand: AppConfig.MesoNoseCommand?
    @Published var currentStrategy: ConnectionStrategy
    @Published var currentSamplingMode: SamplingMode = AppConfig.samplingMode
    @Published var lastTestCompletedDate: Date? = nil
    @Published var alertMessage: String? = nil
    @Published var alertTheme: AlertVisualTheme = .none

    @Published var connectedPeripherals: [UUID: CBPeripheral] = [:]
    @Published var writeCharacteristics: [UUID: CBCharacteristic] = [:]

    private let savedMesoNoseUUIDKey = "SavedMesoNosePeripheralUUID"
    private let savedMesoPinUUIDKey = "SavedMesoPinPeripheralUUID"
    
    @Published var mesoNoseBattery: Int? = nil
    @Published var ignoredMesoNoseUUID: UUID? = nil
    @Published var isPairingModeActive: Bool = false

    var initialBurstWorkItem: DispatchWorkItem?
    var preheatWorkItem: DispatchWorkItem?
    var postTestPurgeWorkItem: DispatchWorkItem?
    var pendingMesoNoseCommand: AppConfig.MesoNoseCommand?

    @Published var savedMesoNoseUUID: UUID? {
        didSet {
            if let uuid = savedMesoNoseUUID {
                UserDefaults.standard.set(uuid.uuidString, forKey: savedMesoNoseUUIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: savedMesoNoseUUIDKey)
            }
        }
    }

    @Published var savedMesoPinUUID: UUID? {
        didSet {
            if let uuid = savedMesoPinUUID {
                UserDefaults.standard.set(uuid.uuidString, forKey: savedMesoPinUUIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: savedMesoPinUUIDKey)
            }
        }
    }

    var connectedPeripheral: CBPeripheral? {
        connectedPeripherals.values.first
    }

    var firmwarePeripheral: CBPeripheral? {
        get {
            return connectedPeripherals.values.first {
                $0.name?.hasPrefix(AppConfig.bluetoothDeviceName) == true
            } ?? connectedPeripherals.values.first
        }
        set {
            if let newValue = newValue {
                connectedPeripherals[newValue.identifier] = newValue
            }
        }
    }

    var writeCharacteristic: CBCharacteristic? {
        get {
            if let pin = firmwarePeripheral {
                return writeCharacteristics[pin.identifier]
            }
            return writeCharacteristics.values.first
        }
        set {
            if let pin = firmwarePeripheral, let newValue = newValue {
                writeCharacteristics[pin.identifier] = newValue
            }
        }
    }

    var blowTimeoutTimer: Timer?
    var modelContainer: ModelContainer?
    var centralManager: CBCentralManager?

    @Published var mesoNoseSamples: [MesoNoseSample] = []

    @Published var statusText: String = "Initializing..."
    @Published var pm1Value: String = "--"
    @Published var pm25Value: String = "--"
    @Published var pm10Value: String = "--"

    private var incomingBuffers: [UUID: String] = [:]

    var purgeRemainingSeconds: TimeInterval {
        guard let lastDate = lastTestCompletedDate else { return 0 }
        let elapsed = Date().timeIntervalSince(lastDate)
        return max(0, 180.0 - elapsed)
    }

    var isPurgingMoisture: Bool {
        purgeRemainingSeconds > 0
    }

    var isRoomBaselineReady: Bool {
        guard mesoNosePeripheral?.state == .connected else { return false }
        guard breathTestState == .idle else { return false }
        if isPurgingMoisture { return false }

        if let latestAmbient = mesoNoseSamples.first(where: { $0.breathDropDelta == 0.0 }) {
            let validSensors = latestAmbient.temp > 0 && latestAmbient.humidity > 0 && latestAmbient.voc > 0
            let isUnsaturated = latestAmbient.voc > 5000 && latestAmbient.voc < 2_000_000
            return validSensors && isUnsaturated
        }

        return true
    }

    init(modelContainer: ModelContainer? = nil) {
        if let uuidString = UserDefaults.standard.string(forKey: savedMesoNoseUUIDKey),
           let uuid = UUID(uuidString: uuidString) {
            self.savedMesoNoseUUID = uuid
        }

        if let container = modelContainer {
            self.modelContainer = container
        } else {
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                self.modelContainer = try ModelContainer(
                    for: DB_PMSample.self,
                    DB_MesoNoseSample.self,
                    configurations: config
                )
                AppLogger.writeLog("In-Memory Test Database Container Initialized.")
            } catch {
                self.modelContainer = nil
                AppLogger.writeLog("Failed to create temporary database container: \(error)")
            }
        }

        if AppConfig.forceInitialEmergencyState {
            self.currentStrategy = .emergency
            self.alertMessage = "DEBUG: Forced Emergency Active"
        } else {
            self.currentStrategy = .batterySaver
        }

        super.init()

        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("Mock Simulator Bridge Active. Bypassing BLE Hardware.")
            self.statusText = "Connected (Mock Simulator)"
            startMockDataStream()
        } else {
            AppLogger.writeLog("Real BLE Hardware Mode Active. Instantiating Central Manager.")

            #if !targetEnvironment(simulator)
                let options: [String: Any] = [
                    CBCentralManagerOptionRestoreIdentifierKey: "MesoSensorDashboardCentralRestoreID",
                    CBCentralManagerOptionShowPowerAlertKey: true
                ]
                centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
            #else
                AppLogger.writeLog("Execution stopped: Cannot run BLE hardware on an iOS Simulator window.")
                self.statusText = "Error: Use Simulator Bridge on Mac."
            #endif
        }

        Task { @MainActor in
            self.fetchHistoricalMesoNoseData()
        }
    }

    func cancelInitialBurstTimer() {
        initialBurstWorkItem?.cancel()
        initialBurstWorkItem = nil
    }

    func setSamplingMode(mode: SamplingMode = AppConfig.samplingMode) {
        if mode == .ulp5m && breathTestState != .idle {
            AppLogger.writeLog("Blocked transition to ULP mode because breath test is active (\(breathTestState)).")
            return
        }

        AppConfig.samplingMode = mode
        DispatchQueue.main.async {
            self.currentSamplingMode = mode
        }

        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("Mock Simulator bridge setting sampling mode to: \(mode.rawValue)")
            startMockDataStream()
        } else {
            switch mode {
            case .active3s:
                sendMesoNoseCommand(.setActiveSamplingMode)
            case .ulp5m:
                sendMesoNoseCommand(.setUltraLowSamplingMode)
            case .stopped:
                sendMesoNoseCommand(.stopSampling)
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            AppLogger.writeLog("Bluetooth hardware status: Powered On. Beginning dual-device scan...")
            self.statusText = "Scanning for Meso Sensors..."
            startScanning()

        case .poweredOff:
            AppLogger.writeLog("Bluetooth hardware status: Powered Off.")
            self.statusText = "Bluetooth is turned off"

        case .unauthorized:
            AppLogger.writeLog("Bluetooth hardware status: Unauthorized. Check Info.plist keys.")
            self.statusText = "Permissions denied"

        default:
            AppLogger.writeLog("Bluetooth hardware status: Transitioning state \(central.state.rawValue)")
        }
    }

    func startScanning() {
        guard centralManager?.state == .poweredOn else { return }

        AppLogger.writeLog("Starting BLE peripheral scan for Meso Pin & Meso Nose...")
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let deviceName = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unnamed Local Device"
        let isMesoPin = deviceName.hasPrefix(AppConfig.bluetoothDeviceName)
        let isMesoNose = deviceName.hasPrefix(AppConfig.mesoNoseBluetoothName)

        guard isMesoPin || isMesoNose else { return }
        let deviceID = peripheral.identifier

        guard connectedPeripherals[deviceID] == nil else { return }

        if let savedUUID = savedMesoNoseUUID, isMesoNose {
            if deviceID == savedUUID {
                AppLogger.writeLog("Target Match Found via Saved UUID: \(deviceName) [\(deviceID)]")
                connectToPeripheral(peripheral, deviceName: deviceName)
                return
            } else {
                return
            }
        }

        guard savedMesoNoseUUID == nil && isPairingModeActive else { return }

        let proximityRSSIThreshold = -65
        guard RSSI.intValue != 127 && RSSI.intValue >= proximityRSSIThreshold else { return }

        AppLogger.writeLog("Pairing mode match found: \(deviceName) [ID: \(deviceID)] RSSI: \(RSSI)")

        if isMesoNose {
            self.savedMesoNoseUUID = deviceID
            self.isPairingModeActive = false
        }

        connectToPeripheral(peripheral, deviceName: deviceName)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let deviceName = peripheral.name ?? "Unknown Device"
        AppLogger.writeLog("Swift BLE: Successfully connected to: \(deviceName)")

        peripheral.delegate = self
        incomingBuffers[peripheral.identifier] = ""
        peripheral.discoverServices(nil)

        DispatchQueue.main.async {
            let count = self.connectedPeripherals.count
            self.statusText = "Connected (\(count) Device\(count > 1 ? "s" : ""))"
        }

        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let errorDescription = error?.localizedDescription ?? "Unknown error"
        let deviceName = peripheral.name ?? "Device"
        AppLogger.writeLog("Swift BLE ERROR: Failed to establish link to \(deviceName): \(errorDescription)")

        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        writeCharacteristics.removeValue(forKey: peripheral.identifier)
        incomingBuffers.removeValue(forKey: peripheral.identifier)

        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let deviceName = peripheral.name ?? "Device"
        AppLogger.writeLog("Swift BLE: Connection dropped for \(deviceName). Re-entering scan.")

        if peripheral.identifier == self.mesoPinPeripheral?.identifier {
            DispatchQueue.main.async {
                self.pm1Value = ""
                self.pm25Value = ""
                self.pm10Value = ""
            }
        }

        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        writeCharacteristics.removeValue(forKey: peripheral.identifier)
        incomingBuffers.removeValue(forKey: peripheral.identifier)

        DispatchQueue.main.async {
            if self.connectedPeripherals.isEmpty {
                self.statusText = "Disconnected. Scanning..."
            } else {
                self.statusText = "Connected (\(self.connectedPeripherals.count) Active)"
            }
        }

        startScanning()
    }

    // Single Consolidated Restoration Handler
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for restoredPeripheral in peripherals {
                AppLogger.writeLog("Swift BLE: Restoring peripheral session: \(restoredPeripheral.name ?? "Device")")
                connectedPeripherals[restoredPeripheral.identifier] = restoredPeripheral
                restoredPeripheral.delegate = self

                if restoredPeripheral.state == .connected {
                    restoredPeripheral.discoverServices(nil)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            AppLogger.writeLog("GATT Service Discovery Error: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            AppLogger.writeLog("GATT Handshake Stalled: Zero services discovered for \(peripheral.name ?? "Device").")
            return
        }

        AppLogger.writeLog("Discovered \(services.count) services for \(peripheral.name ?? "Device"). Discovering characteristics...")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            AppLogger.writeLog("GATT Characteristic Discovery Error: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        let targetNoseCharUUID = AppConfig.mesoNoseCharacteristicUUIDString.lowercased()

        for characteristic in characteristics {
            let uuidStr = characteristic.uuid.uuidString.lowercased()
            let canNotify = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
            let canWrite = characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)

            if canWrite {
                if uuidStr == targetNoseCharUUID || writeCharacteristics[peripheral.identifier] == nil {
                    self.writeCharacteristics[peripheral.identifier] = characteristic
                    AppLogger.writeLog("  -> Cached Write Characteristic [\(peripheral.name ?? "Device")]: \(characteristic.uuid.uuidString)")

                    if let pendingCmd = self.pendingMesoNoseCommand {
                        AppLogger.writeLog("Executing queued command [\(pendingCmd.rawValue)] after characteristic discovery.")
                        self.sendMesoNoseCommand(pendingCmd)
                        self.pendingMesoNoseCommand = nil
                    }
                }
            }

            if canNotify {
                AppLogger.writeLog("  -> Subscribing to Notification Stream [\(peripheral.name ?? "Device")]: \(characteristic.uuid.uuidString)")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            AppLogger.writeLog("Notification State Error [\(peripheral.name ?? "Device")]: \(error.localizedDescription)")
            return
        }

        AppLogger.writeLog("Notification state updated to \(characteristic.isNotifying) for \(peripheral.name ?? "Device")")

        if characteristic.isNotifying && peripheral.name?.hasPrefix(AppConfig.mesoNoseBluetoothName) == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }

                guard self.breathTestState == .idle else {
                    AppLogger.writeLog("Handshake established while test active (\(self.breathTestState)). Skipping initial burst timer override.")
                    return
                }

                AppLogger.writeLog("Handshake Established: Triggering 15s initial sampling burst for valid baseline...")
                self.sendMesoNoseCommand(.setActiveSamplingMode)
                self.cancelInitialBurstTimer()

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, self.mesoNosePeripheral?.state == .connected else { return }
                    guard self.breathTestState == .idle else {
                        AppLogger.writeLog("Initial burst complete, but breath test is active. Skipping background mode override.")
                        return
                    }

                    let targetMode = AppConfig.samplingMode
                    AppLogger.writeLog("Initial burst capture complete. Transitioning to configured mode: \(targetMode.rawValue)")
                    self.setSamplingMode(mode: targetMode)
                }

                self.initialBurstWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: workItem)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            AppLogger.writeLog("Bluetooth notification error: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value,
              let chunk = String(data: data, encoding: .utf8) else { return }

        let deviceID = peripheral.identifier
        incomingBuffers[deviceID, default: ""].append(chunk)

        guard var currentBuffer = incomingBuffers[deviceID], !currentBuffer.isEmpty else { return }

        while let newLineIndex = currentBuffer.firstIndex(of: "\n") {
            let line = String(currentBuffer[..<newLineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            currentBuffer.removeSubrange(..<currentBuffer.index(after: newLineIndex))
            incomingBuffers[deviceID] = currentBuffer

            if line.isEmpty { continue }

            if line.contains("SYNC_COMPLETE") {
                AppLogger.writeLog("Ingestion: Sync complete token received.")
                DispatchQueue.main.async {
                    self.updateStatusOnMainThread(to: "Connected (Live)")
                }
                continue
            }

            if line.hasPrefix("{") {
                if line.isMesoNosePayload {
                    AppLogger.writeLog("Ingestion: Meso Nose payload -> \(line)")
                    handleMesoNosePacket(line)
                } else {
                    AppLogger.writeLog("Unrecognized JSON payload skipped: \(line)")
                }
                continue
            }

            parseMesoPinPacket(line)
        }

        let jsonObjects = extractJSONObjects(from: &currentBuffer)
        incomingBuffers[deviceID] = currentBuffer

        for jsonCandidate in jsonObjects {
            if jsonCandidate.isMesoNosePayload {
                AppLogger.writeLog("Ingestion (Extracted JSON): Meso Nose -> \(jsonCandidate)")
                handleMesoNosePacket(jsonCandidate)
            }
        }
    }

    private func connectToPeripheral(_ peripheral: CBPeripheral, deviceName: String) {
        connectedPeripherals[peripheral.identifier] = peripheral
        incomingBuffers[peripheral.identifier] = ""
        peripheral.delegate = self

        DispatchQueue.main.async {
            self.statusText = "Connecting to \(deviceName)..."
        }

        self.centralManager?.connect(peripheral, options: nil)
    }

    private func extractJSONObjects(from buffer: inout String) -> [String] {
        var results: [String] = []
        var depth = 0
        var startIndex: String.Index? = nil
        var lastParsedEndIndex: String.Index? = nil

        for index in buffer.indices {
            let char = buffer[index]
            if char == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if char == "}" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        let jsonString = String(buffer[start...index])
                        results.append(jsonString)
                        lastParsedEndIndex = index
                        startIndex = nil
                    }
                }
            }
        }

        if let lastEnd = lastParsedEndIndex {
            let nextIndex = buffer.index(after: lastEnd)
            buffer = (nextIndex < buffer.endIndex) ? String(buffer[nextIndex...]) : ""
        }

        return results
    }
}
