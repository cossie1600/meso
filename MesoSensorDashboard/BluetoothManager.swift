//
//  BluetoothManager.swift
//  MesoSensorDashboard
//

import Combine
import CoreBluetooth
import Foundation
import SwiftData

// MARK: - BluetoothManager Main Class

class BluetoothManager: NSObject, AirQualityManagerProtocol {

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
    @Published var hasReceivedLiveTelemetry: Bool = false
    
    @MainActor var currentFetchLimit: Int = BMConstants.initialCardLimit
    
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

    var incomingBuffers: [UUID: String] = [:]

    var purgeRemainingSeconds: TimeInterval {
        guard let lastDate = lastTestCompletedDate else { return BMConstants.zeroValue }
        let elapsed = Date().timeIntervalSince(lastDate)
        return max(BMConstants.zeroValue, BMConstants.purgeWindowSeconds - elapsed)
    }

    var isPurgingMoisture: Bool {
        // If sampling mode is ULP, moisture purge is strictly inactive
        guard currentSamplingMode != .ulp5m else { return false }
        guard let lastDate = lastTestCompletedDate else { return false }
        let elapsed = Date().timeIntervalSince(lastDate)
        return elapsed < BMConstants.purgeWindowSeconds
    }

    /// Evaluates whether a valid ambient baseline sample has been received within the last 5 minutes (300 seconds).
    var isAmbientSampleFresh: Bool {
        guard let latestAmbient = mesoNoseSamples.first(where: { $0.breathDropDelta == BMConstants.zeroValue }) else {
            return false
        }
        let elapsed = Date().timeIntervalSince(latestAmbient.timestamp)
        return elapsed <= BMConstants.maxAmbientSampleAgeSeconds
    }

    var isConnected: Bool {
        return mesoNosePeripheral?.state == .connected
    }
    /// Helper property for overall breath test readiness overlay
    var isSensorReadyForTest: Bool {
        return mesoNosePeripheral?.state == .connected
            && breathTestState == .idle
            && isRoomBaselineReady
    }

    var isRoomBaselineReady: Bool {
        guard mesoNosePeripheral?.state == .connected else { return false }

        // Unblocks as soon as at least one valid baseline reading exists in memory
        guard let latestAmbient = mesoNoseSamples.first(where: { $0.breathDropDelta == BMConstants.zeroValue }) else {
            return false
        }

        let validSensors = latestAmbient.temp > BMConstants.zeroValue
                        && latestAmbient.humidity > BMConstants.zeroValue
                        && latestAmbient.voc > BMConstants.zeroVOC
        let isUnsaturated = latestAmbient.voc > BMConstants.minUnsaturatedVOC
                         && latestAmbient.voc < BMConstants.maxUnsaturatedVOC

        return validSensors && isUnsaturated
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

    func cancelPurgeTimer() {
        postTestPurgeWorkItem?.cancel()
        postTestPurgeWorkItem = nil
        
        DispatchQueue.main.async {
            self.lastTestCompletedDate = nil
            AppLogger.writeLog(BMLogMessages.purgeCancelled)
        }
    }
}
