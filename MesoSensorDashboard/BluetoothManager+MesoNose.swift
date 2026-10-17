//
//  BluetoothManager+MesoNose.swift
//  MesoSensorDashboard
//

import CoreBluetooth
import Foundation
import SwiftData
import SwiftUI

// MARK: - Constants & Namespaces (Zero Magic Values)

struct MesoNoseConstants {
    static let zeroFloat: Float = 0.0
    static let zeroDouble: Double = 0.0
    static let zeroInt: Int = 0
    static let secondsPerMinute: Int = 60
    // Transient cold-boot heating floor (near-zero short circuits < 1000 ohms)
    static let transientWarmupVocFloor: Int = 1_000
    // Blow guard timeout: 30s firmware wait + 2s BLE notification transport buffer
    static let blowWindowTimeoutSeconds: TimeInterval = 32.0
}

struct MesoNosePayloadKeys {
    static let status = "status"
    static let state = "state"
    static let temp = "temp"
    static let rh = "rh"
    static let press = "press"
    static let voc = "voc"
    static let co2 = "co2"
    static let ptcResult = "ptc_result"
    static let rxCmd = "rx_cmd"
    static let dH = "dH"
    static let gDrop = "gDrop"
    static let breathDropDelta = "breath_drop_delta"
    static let selectivityRatio = "selectivity_ratio"
    static let recoveryLagSec = "recovery_lag_sec"
    static let breathMin = "breath_min"
    static let seconds = "seconds"
    static let remainingSec = "remaining_sec"
    static let battery = "battery"

    static let allValidKeys: Set<String> = [
        temp, rh, press, voc, co2, ptcResult, status,
        state, rxCmd, dH, gDrop, breathDropDelta, selectivityRatio,
        recoveryLagSec, breathMin, seconds, remainingSec, battery,
    ]
}

enum MesoNoseFirmwareStatus: String {
    case breathTestStarted = "BREATH_TEST_STARTED"
    case breathTestComplete = "BREATH_TEST_COMPLETE"
}

enum MesoNoseFirmwareState: String {
    case coldBootWarmingUp = "COLD_BOOT_WARMING_UP"
    case warmupComplete = "WARMUP_COMPLETE"
    case warmingUp = "WARMING_UP"
    case readyPleaseBlow = "READY_PLEASE_BLOW"
    case testingSensingBreath = "TESTING_SENSING_BREATH"
    case recoveringCalculatingT50 = "RECOVERING_CALCULATING_T50"
    case exhalationTooWeak = "EXHALATION_TOO_WEAK"
    case tryAgainLater = "TRY_AGAIN_LATER"
    case timeout = "TIMEOUT"
    case profileULP = "PROFILE_ULP"
    case profileLP = "PROFILE_LP"
}

/// Exact parity with C++ BreathResult enum in breath_kinetics_engine.h / .cpp
enum MesoNoseResult: String, CaseIterable, Sendable {
    case none = "NONE"
    case invalidExhalation = "INVALID_EXHALATION"
    case dryMouthHydrate = "DRY_MOUTH_HYDRATE"
    case dryMouthVscBuildup = "DRY_MOUTH_VSC_BUILDUP"
    case balancedBreath = "BALANCED_BREATH"
    case settleBreath = "SETTLE_BREATH"
    case settleBeverageFoodOdor = "SETTLE_BEVERAGE_FOOD_ODOR"
    case someBeverageFoodOdor = "SOME_BEVERAGE_FOOD_ODOR"
    case noticeableMalodor = "NOTICEABLE_MALODOR"
    case strongMalodor = "STRONG_MALODOR"

    var title: String {
        switch self {
        case .none, .invalidExhalation:
            return MesoNoseUIStrings.ResultTitles.none
        case .dryMouthHydrate:
            return MesoNoseUIStrings.ResultTitles.dryMouthHydrate
        case .dryMouthVscBuildup:
            return MesoNoseUIStrings.ResultTitles.dryMouthVscBuildup
        case .settleBreath:
            return MesoNoseUIStrings.ResultTitles.settleBreath
        case .settleBeverageFoodOdor:
            return MesoNoseUIStrings.ResultTitles.settleBeverageFoodOdor
        case .balancedBreath:
            return MesoNoseUIStrings.ResultTitles.freshBalancedBreath
        case .someBeverageFoodOdor:
            return MesoNoseUIStrings.ResultTitles.someBeverageFoodOdor
        case .noticeableMalodor:
            return MesoNoseUIStrings.ResultTitles.noticeableMalodor
        case .strongMalodor:
            return MesoNoseUIStrings.ResultTitles.strongMalodor
        }
    }

    var description: String {
        switch self {
        case .none, .invalidExhalation:
            return MesoNoseUIStrings.ResultDescriptions.none
        case .dryMouthHydrate:
            return MesoNoseUIStrings.ResultDescriptions.dryMouthHydrate
        case .dryMouthVscBuildup:
            return MesoNoseUIStrings.ResultDescriptions.dryMouthVscBuildup
        case .settleBreath:
            return MesoNoseUIStrings.ResultDescriptions.settleBreath
        case .settleBeverageFoodOdor:
            return MesoNoseUIStrings.ResultDescriptions.settleBeverageFoodOdor
        case .balancedBreath:
            return MesoNoseUIStrings.ResultDescriptions.freshBalancedBreath
        case .someBeverageFoodOdor:
            return MesoNoseUIStrings.ResultDescriptions.someBeverageFoodOdor
        case .noticeableMalodor:
            return MesoNoseUIStrings.ResultDescriptions.noticeableMalodor
        case .strongMalodor:
            return MesoNoseUIStrings.ResultDescriptions.strongMalodor
        }
    }

    var themeColor: Color {
        switch self {
        case .balancedBreath, .settleBreath:
            return .green
        case .someBeverageFoodOdor, .settleBeverageFoodOdor, .dryMouthHydrate:
            return .blue
        case .dryMouthVscBuildup, .noticeableMalodor:
            return .orange
        case .strongMalodor:
            return .purple
        case .none, .invalidExhalation:
            return .gray
        }
    }
}

struct MesoNoseUIStrings {
    static let deviceUnpaired = "Pendant Unpaired"
    static let searchingNearby = "Searching for nearby pendant..."
    static let warmingUpBlocked = "Warming Up... Please wait before blowing."
    static let wakingAndPreheating = "Waking up... Please wait..."
    static let heatingSensorPlate = "Waking up the pendant..."
    static let breathTestInitiated = "Breath Odor Test Initiated"
    static let analysisComplete = "Breath Odor Analysis Completed"
    static let blowNow = "Blow at the bottom of the pendant now as if you are blowing out birthday candles."
    static let analyzingBreath = "Good Job! Breath is captured."
    static let calculatingT50 = "Analyzing the sample..."
    static let exhalationTooWeak = "Please try blow at the bottom of the pendant a little harder. No breath was captured."
    static let tryAgainLater = "The pendant needs a little time, please try again shortly."
    static let noBreathDetected = "No Breath is detected."
    static let testCancelled = "Action Cancelled."
    static let connectedReady = "Pendant is Ready."
    static let sensorWarmingUpColdBoot = "Waking up the pendent and warming it up..."

    static let statusSensorStabilizing = "Pendant Stabilizing..."
    static let statusSensorDisconnected = "Pendant Disconnected"
    static let promptConnectSensor =
        "Please make sure your Pendant is charged and paired in Settings."
    // need to remove when remove Breath Overlay View
    static let promptSensorStabilizing =
        "Test trigger unlocks automatically once ready."
    static let actionSearchAndConnect = "Search & Connect"

    static func warmingUpFormatted(mins: Int, secs: Int) -> String {
        return String(format: "Pendant Warming Up (%dm %02ds)...", mins, secs)
    }

    struct ResultTitles {
        static let none = "No Reading Detected"
        static let dryMouthHydrate = "A Little Hydration Could Help"
        static let dryMouthVscBuildup = "A Bit Dry Right Now"
        static let freshBalancedBreath = "Fresh & Balanced Breath"
        static let settleBreath = "Delicate Flavor Notes"
        static let settleBeverageFoodOdor = "Settling Food Scents"
        static let someBeverageFoodOdor = "Lingering Food & Drink Scents"
        static let noticeableMalodor = "Time for a Quick Refresh"
        static let strongMalodor = "A Little Extra Care May Help"
    }

    struct ResultDescriptions {
        static let none =
            "We couldn't quite catch a breath sample. Taking a slow, deep breath and blowing steadily may help us get a clear reading."
        
        static let dryMouthHydrate =
            "Your mouth may feel a little dry right now. Enjoying a glass of water could be a wonderful way to refresh and hydrate."
        
        static let dryMouthVscBuildup =
            "A gentle touch of dryness can sometimes affect breath freshness. Sipping water or taking a quick rinse could help restore your natural balance."
        
        static let freshBalancedBreath =
            "Your breath feels clean, fresh, and perfectly balanced! You're good to go."
        
        static let settleBreath =
            "There may just be a delicate hint of recent food or drink on your breath—it's very subtle and nothing to worry about at all."
        
        static let settleBeverageFoodOdor =
            "A few gentle notes from recent food or drinks may still be lingering. A soft rinse or quick brush could help clear them away comfortably."
        
        static let someBeverageFoodOdor =
            "You may notice some lingering flavors from recent food or drinks. A gentle brush or quick rinse could be a great way to refresh your breath."
        
        static let noticeableMalodor =
            "Your breath could benefit from a quick refresh right now. A gentle brush, floss, or rinse may help bring back your natural balance."
        
        static let strongMalodor =
            "Your breath may need a little extra care today. Brushing, flossing, or using mouthwash right away could help you feel your best. If this continues for a few days despite your usual hygiene routine, you might also consider speaking with a dental care provider for extra guidance."
    }
}

struct MesoNoseLogMessages {
    static func cannotSendCommand(_ cmd: String) -> String {
        "Cannot send '\(cmd)': Meso Nose device not found in connected peripherals."
    }
    static func writeCharNotCached(_ cmd: String, uuid: String) -> String {
        "Write characteristic for Meso Nose (\(uuid)) not cached yet. Queueing command '\(cmd)'..."
    }
    static func sentCommand(_ payload: String, name: String, desc: String)
        -> String
    {
        "Sent Meso Nose Command [\(payload)] to \(name): \(desc)"
    }
    static let unpaired =
        "Meso Nose unpaired. Sitting quietly in unpaired state."
    static let pairingModeActive =
        "Pairing Mode active: Searching for closest Meso Nose..."
    static let warmupBlocked =
        "Breath test blocked: Pendant is currently in 5-minute cold boot warmup."
    static let preheatComplete =
        "Pre-heat complete. Triggering Breath Test command..."
    static let testStarted = "Ingestion: Firmware reported BREATH_TEST_STARTED."
    static let testCompleted =
        "Ingestion: Firmware reported BREATH_TEST_COMPLETE."
    static let warmupComplete =
        "Firmware reported WARMUP_COMPLETE. Enabling Breath Test capability."
    static let readyBlow =
        "Received READY_PLEASE_BLOW from hardware. Transitioning to BLOW NOW!"
    static let exhalationTooWeak = "Received EXHALATION_TOO_WEAK from hardware."
    static let tryAgainLater = "Received TRY_AGAIN_LATER from hardware."
    static let timeout = "Received TIMEOUT from hardware."
    static let blowTimeoutStarted =
        "BLOW NOW active. Starting hardware response timeout guard..."
    static let blowWindowTimedOut =
        "Blow window timed out with no hardware evaluation packet. Auto-recovering..."
    static let testCancelledUser =
        "Breath test explicitly cancelled by user. Hardware reset to ULP mode."
    static func testFinished(succeeded: Bool) -> String {
        "Breath test finished (\(succeeded ? "Success" : "Timeout/Weak")). Queueing active moisture purge..."
    }
    static let activatingPurge = "Activating active purge..."
    static let purgeCompleted =
        "Post-test purge completed. Hardware reverted to ULP mode (5m)."
}

// MARK: - BluetoothManager MesoNose Extension

extension BluetoothManager {

    var mesoNosePeripheral: CBPeripheral? {
        return connectedPeripherals.values.first {
            $0.name?.hasPrefix(AppConfig.mesoNoseBluetoothName) == true
        }
    }

    func sendMesoNoseCommand(_ command: AppConfig.MesoNoseCommand) {
        self.lastSentCommand = command

        guard let peripheral = mesoNosePeripheral else {
            AppLogger.writeLog(
                MesoNoseLogMessages.cannotSendCommand(command.description)
            )
            return
        }

        var targetChar = writeCharacteristics[peripheral.identifier]

        if targetChar == nil {
            targetChar = peripheral.services?
                .flatMap { $0.characteristics ?? [] }
                .first {
                    $0.properties.contains(.writeWithoutResponse)
                        || $0.properties.contains(.write)
                }

            if let foundChar = targetChar {
                writeCharacteristics[peripheral.identifier] = foundChar
            }
        }

        guard let char = targetChar else {
            AppLogger.writeLog(
                MesoNoseLogMessages.writeCharNotCached(
                    command.description,
                    uuid: peripheral.identifier.uuidString
                )
            )
            self.pendingMesoNoseCommand = command
            return
        }

        if let data = command.payload.data(using: .utf8) {
            let writeType: CBCharacteristicWriteType =
                char.properties.contains(.writeWithoutResponse)
                ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: char, type: writeType)
            AppLogger.writeLog(
                MesoNoseLogMessages.sentCommand(
                    command.payload,
                    name: peripheral.name ?? AppConfig.mesoNoseBluetoothName,
                    desc: command.description
                )
            )
        }
    }

    func disconnectMesoNose() {
        guard let peripheral = mesoNosePeripheral else { return }
        ignoredMesoNoseUUID = peripheral.identifier
        savedMesoNoseUUID = nil
        isPairingModeActive = false
        centralManager?.cancelPeripheralConnection(peripheral)
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        writeCharacteristics.removeValue(forKey: peripheral.identifier)
        statusText = MesoNoseUIStrings.deviceUnpaired
        AppLogger.writeLog(MesoNoseLogMessages.unpaired)
    }

    func startPairingMesoNose() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.savedMesoNoseUUID = nil
            self.ignoredMesoNoseUUID = nil
            self.isPairingModeActive = true
            self.statusText = MesoNoseUIStrings.searchingNearby
            AppLogger.writeLog(MesoNoseLogMessages.pairingModeActive)

            self.startScanning()
        }
    }

    func stopSampling() {
        setSamplingMode(mode: .stopped)
    }

    func setActiveSamplingMode() {
        setSamplingMode(mode: .active3s)
    }

    func setUltraLowSamplingMode() {
        setSamplingMode(mode: .ulp5m)
    }

    func isUltraLowSamplingMode() -> Bool {
        return currentSamplingMode == .ulp5m
    }

    func triggerBreathTest() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            AppLogger.writeLog("[TRACE]: triggerBreathTest invoked. Current State: \(self.breathTestState)")

            if self.breathTestState == .coldBootWarmup {
                AppLogger.writeLog(MesoNoseLogMessages.warmupBlocked)
                self.statusText = MesoNoseUIStrings.warmingUpBlocked
                return
            }

            guard
                self.breathTestState == .idle
                    || self.breathTestState == .completed
                    || self.breathTestState == .timeout
            else {
                AppLogger.writeLog("[TRACE]: triggerBreathTest blocked because state is \(self.breathTestState)")
                return
            }

            self.cancelInitialBurstTimer()
            self.preheatWorkItem?.cancel()
            self.preheatWorkItem = nil
            self.postTestPurgeWorkItem?.cancel()
            self.postTestPurgeWorkItem = nil
            self.blowTimeoutTimer?.invalidate()
            self.blowTimeoutTimer = nil

            self.breathTestState = .warmingUp
            self.currentSamplingMode = .active3s
            self.statusText = MesoNoseUIStrings.wakingAndPreheating

            self.setActiveSamplingMode()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.breathTestState == .warmingUp else {
                    AppLogger.writeLog("[TRACE]: Preheat work item aborted. State changed.")
                    return
                }

                self.statusText = MesoNoseUIStrings.heatingSensorPlate
                AppLogger.writeLog(MesoNoseLogMessages.preheatComplete)
                self.sendMesoNoseCommand(.triggerBreathTest)
            }

            self.preheatWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + AppConfig.preheatDuration,
                execute: workItem
            )
        }
    }

    func processFirmwareStateTransition(_ stateString: String) {
        AppLogger.writeLog("[TRACE]: Detected Firmware State Transition -> \(stateString)")

        switch stateString {
        case MesoNoseFirmwareState.readyPleaseBlow.rawValue:
            transitionToBlowNow()

        case MesoNoseFirmwareState.testingSensingBreath.rawValue:
            guard breathTestState == .blowNow || breathTestState == .warmingUp else {
                AppLogger.writeLog("[TRACE]: Ignored TESTING_SENSING_BREATH because local test is no longer active (\(breathTestState)).")
                return
            }
            self.blowTimeoutTimer?.invalidate()
            self.breathTestState = .processing

        case MesoNoseFirmwareState.recoveringCalculatingT50.rawValue:
            guard breathTestState == .processing else {
                AppLogger.writeLog("[TRACE]: Ignored RECOVERING_CALCULATING_T50 because state is \(breathTestState).")
                return
            }
            self.breathTestState = .processing

        case MesoNoseFirmwareState.timeout.rawValue, MesoNoseFirmwareState.exhalationTooWeak.rawValue:
            handleBreathTestCompletion(didSucceed: false, failureReason: stateString)

        default:
            break
        }
    }

    func handleMesoNosePacket(_ text: String) {
        guard let data = text.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            AppLogger.writeLog("[TRACE]: Ingesting MesoNose Packet -> \(text)")

            if let sample = MesoNoseSample(jsonString: text),
               let bat = sample.battery, bat > MesoNoseConstants.zeroInt {
                self.mesoNoseBattery = bat
            }

            // 1. Handle status flags using MesoNoseFirmwareStatus
            if let statusStr = jsonObj[MesoNosePayloadKeys.status] as? String,
               let status = MesoNoseFirmwareStatus(rawValue: statusStr) {
                AppLogger.writeLog("[TRACE]: Detected Firmware Status Flag -> \(status.rawValue)")
                switch status {
                case .breathTestStarted:
                    AppLogger.writeLog(MesoNoseLogMessages.testStarted)
                    self.statusText = MesoNoseUIStrings.breathTestInitiated
                    return

                case .breathTestComplete:
                    AppLogger.writeLog(MesoNoseLogMessages.testCompleted)
                    self.statusText = MesoNoseUIStrings.analysisComplete
                    break
                }
            }

            // 2. Handle state transitions using MesoNoseFirmwareState
            if let stateStr = jsonObj[MesoNosePayloadKeys.state] as? String,
               let state = MesoNoseFirmwareState(rawValue: stateStr) {
                AppLogger.writeLog("[TRACE]: Detected Firmware State Transition -> \(state.rawValue)")
                switch state {
                case .coldBootWarmingUp:
                    self.breathTestState = .coldBootWarmup
                    if let remainingSec = jsonObj[MesoNosePayloadKeys.remainingSec] as? Int {
                        let mins = remainingSec / MesoNoseConstants.secondsPerMinute
                        let secs = remainingSec % MesoNoseConstants.secondsPerMinute
                        self.statusText = MesoNoseUIStrings.warmingUpFormatted(mins: mins, secs: secs)
                    } else {
                        self.statusText = MesoNoseUIStrings.sensorWarmingUpColdBoot
                    }
                    return

                case .warmupComplete:
                    AppLogger.writeLog(MesoNoseLogMessages.warmupComplete)
                    self.breathTestState = .idle
                    self.statusText = MesoNoseUIStrings.connectedReady
                    return

                case .warmingUp:
                    self.breathTestState = .warmingUp
                    self.statusText = MesoNoseUIStrings.heatingSensorPlate
                    return

                case .readyPleaseBlow:
                    AppLogger.writeLog(MesoNoseLogMessages.readyBlow)
                    self.transitionToBlowNow()
                    return

                case .testingSensingBreath:
                    self.blowTimeoutTimer?.invalidate()
                    self.blowTimeoutTimer = nil
                    self.breathTestState = .processing
                    self.statusText = MesoNoseUIStrings.analyzingBreath
                    return

                case .recoveringCalculatingT50:
                    self.blowTimeoutTimer?.invalidate()
                    self.blowTimeoutTimer = nil
                    self.breathTestState = .processing
                    self.statusText = MesoNoseUIStrings.calculatingT50
                    return

                case .exhalationTooWeak:
                    AppLogger.writeLog(MesoNoseLogMessages.exhalationTooWeak)
                    self.statusText = MesoNoseUIStrings.exhalationTooWeak
                    self.handleBreathTestCompletion(didSucceed: false, failureReason: state.rawValue)
                    return

                case .tryAgainLater:
                    AppLogger.writeLog(MesoNoseLogMessages.tryAgainLater)
                    self.statusText = MesoNoseUIStrings.tryAgainLater
                    self.handleBreathTestCompletion(didSucceed: false, failureReason: state.rawValue)
                    return

                case .timeout:
                    AppLogger.writeLog(MesoNoseLogMessages.timeout)
                    self.statusText = MesoNoseUIStrings.noBreathDetected
                    self.handleBreathTestCompletion(didSucceed: false, failureReason: state.rawValue)
                    return

                case .profileULP:
                    self.currentSamplingMode = .ulp5m
                    return

                case .profileLP:
                    self.currentSamplingMode = .active3s
                    return
                }
            }

            // 3. Handle Sample Payload & PTC Results
            guard let sample = MesoNoseSample(jsonString: text) else { return }

            guard sample.temp > MesoNoseConstants.zeroDouble && sample.humidity > MesoNoseConstants.zeroDouble else { return }

            let hasValidBreathResult = sample.breathDropDelta > MesoNoseConstants.zeroDouble ||
                (sample.ptcResult != MesoNoseResult.none.rawValue && !sample.ptcResult.isEmpty)

            let isTransientWarmupSpike = sample.voc < MesoNoseConstants.transientWarmupVocFloor && !hasValidBreathResult

            if isTransientWarmupSpike {
                AppLogger.writeLog("[TRACE]: Dropped transient warmup spike [VOC: \(sample.voc)]")
                return
            }

            // Mark live telemetry as received over BLE
            self.hasReceivedLiveTelemetry = true
            self.saveMesoNoseToDatabase(sample)

            if hasValidBreathResult {
                // Check if the top sample in memory is identical to avoid UI duplicates
                let isDuplicateInMemory = self.mesoNoseSamples.first.map {
                    $0.voc == sample.voc && $0.breathDropDelta == sample.breathDropDelta && $0.ptcResult == sample.ptcResult
                } ?? false

                if !isDuplicateInMemory {
                    self.statusText = MesoNoseUIStrings.analysisComplete
                    self.mesoNoseSamples.insert(sample, at: MesoNoseConstants.zeroInt)
                    self.handleBreathTestCompletion(didSucceed: true)
                } else {
                    AppLogger.writeLog("[TRACE]: Skipped in-memory duplicate result insertion.")
                }
            } else if self.breathTestState != .blowNow && self.breathTestState != .processing {
                AppLogger.writeLog("[TRACE]: Ingested Ambient Telemetry Sample [Temp: \(sample.temp), RH: \(sample.humidity), VOC: \(sample.voc)]")
                self.mesoNoseSamples.insert(sample, at: MesoNoseConstants.zeroInt)

                if self.breathTestState == .coldBootWarmup || self.breathTestState == .warmingUp {
                    self.breathTestState = .idle
                    self.statusText = MesoNoseUIStrings.connectedReady
                    AppLogger.writeLog(MesoNoseLogMessages.warmupComplete)
                }
            }
        }
    }

    private func transitionToBlowNow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            AppLogger.writeLog("[TRACE]: Executing transitionToBlowNow(). Setting state = .blowNow")
            self.breathTestState = .blowNow
            self.statusText = MesoNoseUIStrings.blowNow
            self.startBlowTimeoutGuard()
        }
    }

    private func startBlowTimeoutGuard() {
        self.blowTimeoutTimer?.invalidate()

        AppLogger.writeLog(MesoNoseLogMessages.blowTimeoutStarted)

        self.blowTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: MesoNoseConstants.blowWindowTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if self.breathTestState == .blowNow || self.breathTestState == .processing {
                    AppLogger.writeLog(MesoNoseLogMessages.blowWindowTimedOut)
                    self.statusText = MesoNoseUIStrings.noBreathDetected
                    self.handleBreathTestCompletion(didSucceed: false, failureReason: MesoNoseFirmwareState.timeout.rawValue)
                }
            }
        }
    }

    func cancelBreathTest() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            AppLogger.writeLog("[TRACE]: Executing cancelBreathTest(). Setting state = .idle")

            self.preheatWorkItem?.cancel()
            self.preheatWorkItem = nil
            self.postTestPurgeWorkItem?.cancel()
            self.postTestPurgeWorkItem = nil
            self.blowTimeoutTimer?.invalidate()
            self.blowTimeoutTimer = nil
            self.cancelInitialBurstTimer()

            self.breathTestState = .idle
            self.statusText = MesoNoseUIStrings.testCancelled

            self.sendMesoNoseCommand(.setUltraLowSamplingMode)
            AppLogger.writeLog(MesoNoseLogMessages.testCancelledUser)
        }
    }
}

// MARK: - Breath Test Completion Pipeline

extension BluetoothManager {

    @MainActor
    func handleBreathTestCompletion(didSucceed: Bool, failureReason: String? = nil) {
        AppLogger.writeLog("[TRACE]: handleBreathTestCompletion called (Success: \(didSucceed)). Current state = \(self.breathTestState)")

        // Guard against re-entrant calls if already in a terminal state
        guard self.breathTestState != .completed && self.breathTestState != .timeout else {
            AppLogger.writeLog("[TRACE]: handleBreathTestCompletion skipped - already completed/timed out.")
            return
        }

        // 1. Cancel pending timers and work items
        self.preheatWorkItem?.cancel()
        self.preheatWorkItem = nil
        self.postTestPurgeWorkItem?.cancel()
        self.postTestPurgeWorkItem = nil
        self.blowTimeoutTimer?.invalidate()
        self.blowTimeoutTimer = nil

        self.lastTestCompletedDate = nil
        self.breathTestState = didSucceed ? .completed : .timeout

        // 2. Log completion or specific failure reason
        if didSucceed {
            AppLogger.writeLog(MesoNoseLogMessages.testFinished(succeeded: true))
        } else {
            let reason = failureReason ?? BMConstants.defaultFailureReason
            AppLogger.writeLog("[TRACE]: Breath evaluation failed with reason: \(reason)")
            AppLogger.writeLog(MesoNoseLogMessages.testFinished(succeeded: false))
        }

        // 3. Queue firmware teardown delay (Ultra Low Power mode switch)
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.firmwareTeardownDelay) { [weak self] in
            guard let self = self else { return }
            AppLogger.writeLog("[TRACE]: Teardown delay elapsed. Dispatching set_ultra_low_sampling_mode.")
            self.sendMesoNoseCommand(.setUltraLowSamplingMode)

            // 4. Reset state back to .idle after UI display hold window
            DispatchQueue.main.asyncAfter(deadline: .now() + BMConstants.uiDisplayHoldDurationSeconds) { [weak self] in
                guard let self = self else { return }
                if self.breathTestState == .completed || self.breathTestState == .timeout {
                    AppLogger.writeLog("[TRACE]: Auto-resetting breathTestState back to .idle.")
                    self.breathTestState = .idle
                    self.statusText = MesoNoseUIStrings.connectedReady
                }
            }
        }
    }
}

// MARK: - JSON Validation Helper Extension

extension String {
    var isMesoNosePayload: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else {
            return false
        }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        return !json.keys.filter {
            MesoNosePayloadKeys.allValidKeys.contains($0)
        }.isEmpty
    }
}
