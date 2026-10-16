//
//  BluetoothManager+Types.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/14/26.
//

import Combine
import CoreBluetooth
import Foundation

// MARK: - Constants & Log Messages (Zero Magic Values)

struct BMConstants {
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
    
    static let initialCardLimit: Int = 10
    static let pageSizeIncrement: Int = 10

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
    static let maxUnsaturatedVOC: Int = 100_000_000 // 100M Ohms to accommodate clean ambient baselines
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

struct BMLogMessages {
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
