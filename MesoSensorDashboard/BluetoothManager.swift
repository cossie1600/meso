//
//  BluetoothManager.swift
//  MesoSensorDashboard
//

import Combine
import CoreBluetooth
import Foundation
import SwiftData

// MARK: - Constants & Log Messages (Zero Magic Values)

private struct BMConstants {
    static let savedMesoNoseUUIDKey = "SavedMesoNosePeripheralUUID"
    static let savedMesoPinUUIDKey = "SavedMesoPinPeripheralUUID"
    static let restoreIdentifier = "MesoSensorDashboardCentralRestoreID"

    static let defaultStatusInitializing = "Initializing..."
    static let placeholderValue = "--"
    static let emptyString = ""
    static let newlineString = "\n"
    static let syncCompleteToken = "SYNC_COMPLETE"
    static let jsonObjectStart = "{"
    static let jsonObjectEnd = "}"

    static let purgeWindowSeconds: TimeInterval = 180.0
    static let notificationStateDelaySeconds: Double = 0.3
    static let initialBurstDurationSeconds: Double = 15.0
    static let proximityRSSIThreshold: Int = -65
    static let invalidRSSI: Int = 127

    static let zeroInt: Int = 0
    static let zeroValue: Double = 0.0
    static let zeroVOC: Int = 0
    static let singleCount: Int = 1
    static let minUnsaturatedVOC: Int = 5000
    static let maxUnsaturatedVOC: Int = 2_000_000
    static let maxAmbientSampleAgeSeconds: TimeInterval = 300.0 // 5 minutes freshness window
    

    static let statusScanning = "Scanning for Meso Sensors..."
    static let statusPowerOff = "Bluetooth is turned off"
    static let statusPermissionsDenied = "Permissions denied"
    static let statusDisconnectedScanning = "Disconnected. Scanning..."
    static let statusConnectedMock = "Connected (Mock Simulator)"
    static let statusConnectedLive = "Connected (Live)"
    static let statusSimulatorError = "Error: Use Simulator Bridge on Mac."
    static let defaultDeviceName = "Device"
    static let defaultUnknownDevice = "Unknown Device"
    static let defaultUnnamedLocalDevice = "Unnamed Local Device"
    static let debugEmergencyActive = "DEBUG: Forced Emergency Active"

    static func statusConnectingTo(_ deviceName: String) -> String {
        "Connecting to \(deviceName)..."
    }

    static func statusConnectedDevicesCount(_ count: Int) -> String {
        "Connected (\(count) Device\(count > singleCount ? "s" : ""))"
    }

    static func statusConnectedActiveCount(_ count: Int) -> String {
        "Connected (\(count) Active)"
    }
}

private struct BMLogMessages {
    static let inMemoryDbInitialized = "In-Memory Test Database Container Initialized."
    static let mockBridgeActive = "Mock Simulator Bridge Active. Bypassing BLE Hardware."
    static let realHardwareActive = "Real BLE Hardware Mode Active. Instantiating Central Manager."
    static let simulatorExecutionStopped = "Execution stopped: Cannot run BLE hardware on an iOS Simulator window."
    static let bluetoothPoweredOn = "Bluetooth hardware status: Powered On. Beginning dual-device scan..."
    static let bluetoothPoweredOff = "Bluetooth hardware status: Powered Off."
    static let bluetoothUnauthorized = "Bluetooth hardware status: Unauthorized. Check Info.plist keys."
    static let startingScan = "Starting BLE peripheral scan for Meso Pin & Meso Nose..."
    static let syncCompleteReceived = "Ingestion: Sync complete token received."
    static let purgeCancelled = "Moisture purge timer cancelled and state cleared."

    static func inMemoryDbFailed(_ error: String) -> String {
        "Failed to create temporary database container: \(error)"
    }

    static func blockedUlpTransition(_ state: BreathTestState) -> String {
        "Blocked transition to ULP mode because breath test is active (\(state))."
    }

    static func mockSettingSamplingMode(_ mode: String) -> String {
        "Mock Simulator bridge setting sampling mode to: \(mode)"
    }

    static func bluetoothTransitioningState(_ stateRaw: Int) -> String {
        "Bluetooth hardware status: Transitioning state \(stateRaw)"
    }

    static func updatedSavedMesoNoseUUID(_ deviceID: UUID) -> String {
        "Updated saved Meso Nose UUID to: \(deviceID)"
    }

    static func targetMatchFound(_ deviceName: String, _ deviceID: UUID) -> String {
        "Target Match Found via Name: \(deviceName) [\(deviceID)]"
    }

    static func pairingMatchFound(_ deviceName: String, _ deviceID: UUID, _ rssi: NSNumber) -> String {
        "Pairing mode match found: \(deviceName) [ID: \(deviceID)] RSSI: \(rssi)"
    }

    static func connectedTo(_ deviceName: String) -> String {
        "Swift BLE: Successfully connected to: \(deviceName)"
    }

    static func failedToConnect(_ deviceName: String, _ errorDesc: String) -> String {
        "Swift BLE ERROR: Failed to establish link to \(deviceName): \(errorDesc)"
    }

    static func connectionDropped(_ deviceName: String) -> String {
        "Swift BLE: Connection dropped for \(deviceName). Re-entering scan."
    }

    static func restoringSession(_ deviceName: String) -> String {
        "Swift BLE: Restoring peripheral session: \(deviceName)"
    }

    static func gattServiceDiscoveryError(_ errorDesc: String) -> String {
        "GATT Service Discovery Error: \(errorDesc)"
    }

    static func gattHandshakeStalled(_ deviceName: String) -> String {
        "GATT Handshake Stalled: Zero services discovered for \(deviceName)."
    }

    static func discoveredServices(_ count: Int, _ deviceName: String) -> String {
        "Discovered \(count) services for \(deviceName). Discovering characteristics..."
    }

    static func gattCharDiscoveryError(_ errorDesc: String) -> String {
        "GATT Characteristic Discovery Error: \(errorDesc)"
    }

    static func cachedWriteChar(_ deviceName: String, _ uuidStr: String) -> String {
        "  -> Cached Write Characteristic [\(deviceName)]: \(uuidStr)"
    }

    static func executingQueuedCommand(_ rawValue: String) -> String {
        "Executing queued command [\(rawValue)] after characteristic discovery."
    }

    static func subscribingNotification(_ deviceName: String, _ uuidStr: String) -> String {
        "  -> Subscribing to Notification Stream [\(deviceName)]: \(uuidStr)"
    }

    static func notificationStateError(_ deviceName: String, _ errorDesc: String) -> String {
        "Notification State Error [\(deviceName)]: \(errorDesc)"
    }

    static func notificationStateUpdated(_ isNotifying: Bool, _ deviceName: String) -> String {
        "Notification state updated to \(isNotifying) for \(deviceName)"
    }

    static func handshakeTestActive(_ state: BreathTestState) -> String {
        "Handshake established while test active (\(state)). Skipping initial burst timer override."
    }

    static let handshakeTriggeringBurst = "Handshake Established: Triggering 15s initial sampling burst for valid baseline..."

    static let initialBurstTestActive = "Initial burst complete, but breath test is active. Skipping background mode override."

    static func initialBurstCompleteTransitioning(_ mode: String) -> String {
        "Initial burst capture complete. Transitioning to configured mode: \(mode)"
    }

    static func bluetoothNotificationError(_ errorDesc: String) -> String {
        "Bluetooth notification error: \(errorDesc)"
    }

    static func mesoNosePayloadIngestion(_ line: String) -> String {
        "Ingestion: Meso Nose payload -> \(line)"
    }

    static func unrecognizedPayloadSkipped(_ line: String) -> String {
        "Unrecognized JSON payload skipped: \(line)"
    }

    static func extractedMesoNosePayload(_ candidate: String) -> String {
        "Ingestion (Extracted JSON): Meso Nose -> \(candidate)"
    }
}

// MARK: - Enums

enum BreathTestState: Equatable, Sendable {
    case idle
    case coldBootWarmup
    case warmingUp
    case blowNow
    case processing
    case completed
    case timeout

    nonisolated static func == (lhs: BreathTestState, rhs: BreathTestState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.coldBootWarmup, .coldBootWarmup),
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

// MARK: - BluetoothManager Implementation

class BluetoothManager: NSObject, AirQualityManagerProtocol, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var breathTestState: BreathTestState = .idle
    @Published var countdownSeconds: Int = BMConstants.zeroInt
    @Published var lastSentCommand: AppConfig.MesoNoseCommand?
    @Published var currentStrategy: ConnectionStrategy
    @Published var currentSamplingMode: SamplingMode = AppConfig.samplingMode
    @Published var lastTestCompletedDate: Date? = nil
    @Published var alertMessage: String? = nil
    @Published var alertTheme: AlertVisualTheme = .none

    @Published var connectedPeripherals: [UUID: CBPeripheral] = [:]
    @Published var writeCharacteristics: [UUID: CBCharacteristic] = [:]

    private let savedMesoNoseUUIDKey = BMConstants.savedMesoNoseUUIDKey
    private let savedMesoPinUUIDKey = BMConstants.savedMesoPinUUIDKey
    
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

    @Published var statusText: String = BMConstants.defaultStatusInitializing
    @Published var pm1Value: String = BMConstants.placeholderValue
    @Published var pm25Value: String = BMConstants.placeholderValue
    @Published var pm10Value: String = BMConstants.placeholderValue

    private var incomingBuffers: [UUID: String] = [:]

    var purgeRemainingSeconds: TimeInterval {
        guard let lastDate = lastTestCompletedDate else { return BMConstants.zeroValue }
        let elapsed = Date().timeIntervalSince(lastDate)
        return max(BMConstants.zeroValue, BMConstants.purgeWindowSeconds - elapsed)
    }

    var isPurgingMoisture: Bool {
        guard currentSamplingMode != .ulp5m else { return false }
        return purgeRemainingSeconds > BMConstants.zeroValue
    }

    /// Evaluates whether a valid ambient baseline sample has been received within the last 5 minutes (300 seconds).
    var isAmbientSampleFresh: Bool {
        guard let latestAmbient = mesoNoseSamples.first(where: { $0.breathDropDelta == BMConstants.zeroValue }) else {
            return false
        }
        let elapsed = Date().timeIntervalSince(latestAmbient.timestamp)
        return elapsed <= BMConstants.maxAmbientSampleAgeSeconds
    }

    /// Helper property for overall breath test readiness overlay
    var isSensorReadyForTest: Bool {
        return mesoNosePeripheral?.state == .connected
            && breathTestState == .idle
            && isRoomBaselineReady
    }

    var isRoomBaselineReady: Bool {
        guard mesoNosePeripheral?.state == .connected else { return false }
        if isPurgingMoisture { return false }

        // Must have at least one clean ambient reading in memory
        guard let latestAmbient = mesoNoseSamples.first(where: { $0.breathDropDelta == BMConstants.zeroValue }) else {
            return false // Block Start until the first baseline sample actually arrives
        }

        let validSensors = latestAmbient.temp > BMConstants.zeroValue
                        && latestAmbient.humidity > BMConstants.zeroValue
                        && latestAmbient.voc > BMConstants.zeroVOC
        let isUnsaturated = latestAmbient.voc > BMConstants.minUnsaturatedVOC
                         && latestAmbient.voc < BMConstants.maxUnsaturatedVOC

        return validSensors && isUnsaturated && isAmbientSampleFresh
    }
    
    init(modelContainer: ModelContainer? = nil) {
        if let uuidString = UserDefaults.standard.string(forKey: BMConstants.savedMesoNoseUUIDKey),
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
                AppLogger.writeLog(BMLogMessages.inMemoryDbInitialized)
            } catch {
                self.modelContainer = nil
                AppLogger.writeLog(BMLogMessages.inMemoryDbFailed(error.localizedDescription))
            }
        }

        if AppConfig.forceInitialEmergencyState {
            self.currentStrategy = .emergency
            self.alertMessage = BMConstants.debugEmergencyActive
        } else {
            self.currentStrategy = .batterySaver
        }

        super.init()

        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog(BMLogMessages.mockBridgeActive)
            self.statusText = BMConstants.statusConnectedMock
            startMockDataStream()
        } else {
            AppLogger.writeLog(BMLogMessages.realHardwareActive)

            #if !targetEnvironment(simulator)
                let options: [String: Any] = [
                    CBCentralManagerOptionRestoreIdentifierKey: BMConstants.restoreIdentifier,
                    CBCentralManagerOptionShowPowerAlertKey: true
                ]
                centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
            #else
                AppLogger.writeLog(BMLogMessages.simulatorExecutionStopped)
                self.statusText = BMConstants.statusSimulatorError
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
            AppLogger.writeLog(BMLogMessages.blockedUlpTransition(breathTestState))
            return
        }

        cancelPurgeTimer()
        AppConfig.samplingMode = mode
        DispatchQueue.main.async {
            self.currentSamplingMode = mode
        }

        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog(BMLogMessages.mockSettingSamplingMode(mode.rawValue))
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
            AppLogger.writeLog(BMLogMessages.bluetoothPoweredOn)
            self.statusText = BMConstants.statusScanning
            startScanning()

        case .poweredOff:
            AppLogger.writeLog(BMLogMessages.bluetoothPoweredOff)
            self.statusText = BMConstants.statusPowerOff

        case .unauthorized:
            AppLogger.writeLog(BMLogMessages.bluetoothUnauthorized)
            self.statusText = BMConstants.statusPermissionsDenied

        default:
            AppLogger.writeLog(BMLogMessages.bluetoothTransitioningState(central.state.rawValue))
        }
    }

    func startScanning() {
        guard centralManager?.state == .poweredOn else { return }

        AppLogger.writeLog(BMLogMessages.startingScan)
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
            ?? BMConstants.defaultUnnamedLocalDevice
        let isMesoPin = deviceName.hasPrefix(AppConfig.bluetoothDeviceName)
        let isMesoNose = deviceName.hasPrefix(AppConfig.mesoNoseBluetoothName)

        guard isMesoPin || isMesoNose else { return }
        let deviceID = peripheral.identifier

        guard connectedPeripherals[deviceID] == nil else { return }

        if isMesoNose {
            if savedMesoNoseUUID != deviceID {
                AppLogger.writeLog(BMLogMessages.updatedSavedMesoNoseUUID(deviceID))
                self.savedMesoNoseUUID = deviceID
            }
            AppLogger.writeLog(BMLogMessages.targetMatchFound(deviceName, deviceID))
            connectToPeripheral(peripheral, deviceName: deviceName)
            return
        }

        guard savedMesoNoseUUID == nil && isPairingModeActive else { return }

        guard RSSI.intValue != BMConstants.invalidRSSI && RSSI.intValue >= BMConstants.proximityRSSIThreshold else { return }

        AppLogger.writeLog(BMLogMessages.pairingMatchFound(deviceName, deviceID, RSSI))

        connectToPeripheral(peripheral, deviceName: deviceName)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let deviceName = peripheral.name ?? BMConstants.defaultUnknownDevice
        AppLogger.writeLog(BMLogMessages.connectedTo(deviceName))

        peripheral.delegate = self
        incomingBuffers[peripheral.identifier] = BMConstants.emptyString
        peripheral.discoverServices(nil)

        DispatchQueue.main.async {
            let count = self.connectedPeripherals.count
            self.statusText = BMConstants.statusConnectedDevicesCount(count)
        }

        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let errorDescription = error?.localizedDescription ?? BMConstants.defaultUnknownDevice
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName
        AppLogger.writeLog(BMLogMessages.failedToConnect(deviceName, errorDescription))

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
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName
        AppLogger.writeLog(BMLogMessages.connectionDropped(deviceName))

        if peripheral.identifier == self.mesoPinPeripheral?.identifier {
            DispatchQueue.main.async {
                self.pm1Value = BMConstants.emptyString
                self.pm25Value = BMConstants.emptyString
                self.pm10Value = BMConstants.emptyString
            }
        }

        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        writeCharacteristics.removeValue(forKey: peripheral.identifier)
        incomingBuffers.removeValue(forKey: peripheral.identifier)

        DispatchQueue.main.async {
            if self.connectedPeripherals.isEmpty {
                self.statusText = BMConstants.statusDisconnectedScanning
            } else {
                self.statusText = BMConstants.statusConnectedActiveCount(self.connectedPeripherals.count)
            }
        }

        startScanning()
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for restoredPeripheral in peripherals {
                let name = restoredPeripheral.name ?? BMConstants.defaultDeviceName
                AppLogger.writeLog(BMLogMessages.restoringSession(name))
                connectedPeripherals[restoredPeripheral.identifier] = restoredPeripheral
                restoredPeripheral.delegate = self

                if restoredPeripheral.state == .connected {
                    restoredPeripheral.discoverServices(nil)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName
        if let error = error {
            AppLogger.writeLog(BMLogMessages.gattServiceDiscoveryError(error.localizedDescription))
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            AppLogger.writeLog(BMLogMessages.gattHandshakeStalled(deviceName))
            return
        }

        AppLogger.writeLog(BMLogMessages.discoveredServices(services.count, deviceName))
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
            AppLogger.writeLog(BMLogMessages.gattCharDiscoveryError(error.localizedDescription))
            return
        }

        guard let characteristics = service.characteristics else { return }

        let targetNoseCharUUID = AppConfig.mesoNoseCharacteristicUUIDString.lowercased()
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName

        for characteristic in characteristics {
            let uuidStr = characteristic.uuid.uuidString.lowercased()
            let canNotify = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
            let canWrite = characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)

            if canWrite {
                if uuidStr == targetNoseCharUUID || writeCharacteristics[peripheral.identifier] == nil {
                    self.writeCharacteristics[peripheral.identifier] = characteristic
                    AppLogger.writeLog(BMLogMessages.cachedWriteChar(deviceName, characteristic.uuid.uuidString))

                    if let pendingCmd = self.pendingMesoNoseCommand {
                        AppLogger.writeLog(BMLogMessages.executingQueuedCommand(pendingCmd.rawValue))
                        self.sendMesoNoseCommand(pendingCmd)
                        self.pendingMesoNoseCommand = nil
                    }
                }
            }

            if canNotify {
                AppLogger.writeLog(BMLogMessages.subscribingNotification(deviceName, characteristic.uuid.uuidString))
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName
        if let error = error {
            AppLogger.writeLog(BMLogMessages.notificationStateError(deviceName, error.localizedDescription))
            return
        }

        AppLogger.writeLog(BMLogMessages.notificationStateUpdated(characteristic.isNotifying, deviceName))

        if characteristic.isNotifying && peripheral.name?.hasPrefix(AppConfig.mesoNoseBluetoothName) == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + BMConstants.notificationStateDelaySeconds) { [weak self] in
                guard let self = self else { return }

                guard self.breathTestState == .idle else {
                    AppLogger.writeLog(BMLogMessages.handshakeTestActive(self.breathTestState))
                    return
                }

                AppLogger.writeLog(BMLogMessages.handshakeTriggeringBurst)
                self.sendMesoNoseCommand(.setActiveSamplingMode)
                self.cancelInitialBurstTimer()

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, self.mesoNosePeripheral?.state == .connected else { return }
                    guard self.breathTestState == .idle else {
                        AppLogger.writeLog(BMLogMessages.initialBurstTestActive)
                        return
                    }

                    let targetMode = AppConfig.samplingMode
                    AppLogger.writeLog(BMLogMessages.initialBurstCompleteTransitioning(targetMode.rawValue))
                    self.setSamplingMode(mode: targetMode)
                }

                self.initialBurstWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + BMConstants.initialBurstDurationSeconds, execute: workItem)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            AppLogger.writeLog(BMLogMessages.bluetoothNotificationError(error.localizedDescription))
            return
        }

        guard let data = characteristic.value,
              let chunk = String(data: data, encoding: .utf8) else { return }

        let deviceID = peripheral.identifier
        incomingBuffers[deviceID, default: BMConstants.emptyString].append(chunk)

        guard var currentBuffer = incomingBuffers[deviceID], !currentBuffer.isEmpty else { return }

        while let newLineIndex = currentBuffer.firstIndex(of: "\n") {
            let line = String(currentBuffer[..<newLineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            currentBuffer.removeSubrange(..<currentBuffer.index(after: newLineIndex))
            incomingBuffers[deviceID] = currentBuffer

            if line.isEmpty { continue }

            if line.contains(BMConstants.syncCompleteToken) {
                AppLogger.writeLog(BMLogMessages.syncCompleteReceived)
                DispatchQueue.main.async {
                    self.updateStatusOnMainThread(to: BMConstants.statusConnectedLive)
                }
                continue
            }

            if line.hasPrefix(BMConstants.jsonObjectStart) {
                if line.isMesoNosePayload {
                    AppLogger.writeLog(BMLogMessages.mesoNosePayloadIngestion(line))
                    handleMesoNosePacket(line)
                } else {
                    AppLogger.writeLog(BMLogMessages.unrecognizedPayloadSkipped(line))
                }
                continue
            }

            parseMesoPinPacket(line)
        }

        let jsonObjects = extractJSONObjects(from: &currentBuffer)
        incomingBuffers[deviceID] = currentBuffer

        for jsonCandidate in jsonObjects {
            if jsonCandidate.isMesoNosePayload {
                AppLogger.writeLog(BMLogMessages.extractedMesoNosePayload(jsonCandidate))
                handleMesoNosePacket(jsonCandidate)
            }
        }
    }

    func cancelPurgeTimer() {
        postTestPurgeWorkItem?.cancel()
        postTestPurgeWorkItem = nil
        
        DispatchQueue.main.async {
            self.lastTestCompletedDate = nil
            AppLogger.writeLog(BMLogMessages.purgeCancelled)
        }
    }

    private func connectToPeripheral(_ peripheral: CBPeripheral, deviceName: String) {
        connectedPeripherals[peripheral.identifier] = peripheral
        incomingBuffers[peripheral.identifier] = BMConstants.emptyString
        peripheral.delegate = self

        DispatchQueue.main.async {
            self.statusText = BMConstants.statusConnectingTo(deviceName)
        }

        self.centralManager?.connect(peripheral, options: nil)
    }

    private func extractJSONObjects(from buffer: inout String) -> [String] {
        var results: [String] = []
        var depth = BMConstants.zeroInt
        var startIndex: String.Index? = nil
        var lastParsedEndIndex: String.Index? = nil

        for index in buffer.indices {
            let char = buffer[index]
            if String(char) == BMConstants.jsonObjectStart {
                if depth == BMConstants.zeroInt {
                    startIndex = index
                }
                depth += BMConstants.singleCount
            } else if String(char) == BMConstants.jsonObjectEnd {
                if depth > BMConstants.zeroInt {
                    depth -= BMConstants.singleCount
                    if depth == BMConstants.zeroInt, let start = startIndex {
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
            buffer = (nextIndex < buffer.endIndex) ? String(buffer[nextIndex...]) : BMConstants.emptyString
        }

        return results
    }
}
