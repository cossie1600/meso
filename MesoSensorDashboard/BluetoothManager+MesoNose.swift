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
    static let transientWarmupVocThreshold: Int = 2_000_000
}

struct MesoNosePayloadKeys {
    static let status = "status"
    static let state = "state"
    static let temp = "temp"
    static let rh = "rh"
    static let press = "press"
    static let voc = "voc"
    static let ptcResult = "ptc_result"
    static let rxCmd = "rx_cmd"
    static let dH = "dH"
    static let gDrop = "gDrop"
    static let seconds = "seconds"
    static let remainingSec = "remaining_sec"
    static let battery = "battery"

    static let allValidKeys: Set<String> = [
        temp, rh, press, voc, ptcResult, status,
        state, rxCmd, dH, gDrop, seconds, remainingSec, battery,
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

enum MesoNoseResult: String, CaseIterable, Sendable {
    case none = "NONE"
    case dryMouthHydrate = "DRY_MOUTH_HYDRATE"
    case dryMouthVscBuildup = "DRY_MOUTH_VSC_BUILDUP"
    case settleBeverageFoodOdor = "SETTLE_BEVERAGE_FOOD_ODOR"
    case balancedBreath = "BALANCED_BREATH"
    case someBeverageFoodOdor = "SOME_BEVERAGE_FOOD_ODOR"
    case noticeableMalodor = "NOTICEABLE_MALODOR"
    case strongMalodor = "STRONG_MALODOR"

    var title: String {
        switch self {
        case .none:
            return MesoNoseUIStrings.ResultTitles.none
        case .dryMouthHydrate:
            return MesoNoseUIStrings.ResultTitles.dryMouthHydrate
        case .dryMouthVscBuildup:
            return MesoNoseUIStrings.ResultTitles.dryMouthVscBuildup
        case .settleBeverageFoodOdor:
            return MesoNoseUIStrings.ResultTitles.settleBeverageFoodOdor
        case .balancedBreath:
            return MesoNoseUIStrings.ResultTitles.balancedBreath
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
        case .none:
            return MesoNoseUIStrings.ResultDescriptions.none
        case .dryMouthHydrate:
            return MesoNoseUIStrings.ResultDescriptions.dryMouthHydrate
        case .dryMouthVscBuildup:
            return MesoNoseUIStrings.ResultDescriptions.dryMouthVscBuildup
        case .settleBeverageFoodOdor:
            return MesoNoseUIStrings.ResultDescriptions.settleBeverageFoodOdor
        case .balancedBreath:
            return MesoNoseUIStrings.ResultDescriptions.balancedBreath
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
        case .balancedBreath:
            return .green
        case .someBeverageFoodOdor, .settleBeverageFoodOdor, .dryMouthHydrate:
            return .blue
        case .dryMouthVscBuildup, .noticeableMalodor:
            return .orange
        case .strongMalodor:
            return .purple
        case .none:
            return .gray
        }
    }
}

struct MesoNoseUIStrings {
    static let deviceUnpaired = "Device Unpaired"
    static let searchingNearby = "Searching for nearby Meso Nose..."
    static let warmingUpBlocked = "Warming Up... Please wait before blowing."
    static let wakingAndPreheating = "Waking sensor & pre-heating..."
    static let heatingSensorPlate = "Heating sensor plate..."
    static let breathTestInitiated = "Breath Test Initiated"
    static let analysisComplete = "Analysis Complete"
    static let blowNow = "BLOW NOW"
    static let analyzingBreath = "Analyzing breath sample..."
    static let calculatingT50 = "Calculating Desorption Recovery (T50)..."
    static let exhalationTooWeak = "Exhalation Too Weak. Please blow harder!"
    static let tryAgainLater = "Sensor Busy / Warming Up. Try again shortly."
    static let noBreathDetected = "No Breath Detected"
    static let testCancelled = "Test Cancelled"
    static let connectedReady = "Connected (Ready)"
    static let sensorWarmingUpColdBoot = "Sensor Warming Up (Cold Boot)..."

    static let statusSensorStabilizing = "Sensor Stabilizing..."
    static let statusSensorDisconnected = "Sensor Disconnected"
    static let promptConnectSensor =
        "Please make sure your Meso Nose sensor is powered on and paired in Settings."
    static let promptSensorStabilizing =
        "Test trigger unlocks automatically once ready."
    static let actionSearchAndConnect = "Search & Connect"

    static func warmingUpFormatted(mins: Int, secs: Int) -> String {
        return String(format: "Sensor Warming Up (%dm %02ds)...", mins, secs)
    }

    struct ResultTitles {
        static let none = "Neutral Reading"
        static let dryMouthHydrate = "Hydration Boost Needed"
        static let dryMouthVscBuildup = "Low Moisture & Natural Shift"
        static let settleBeverageFoodOdor = "Settling Flavor Notes"
        static let balancedBreath = "Fresh & Balanced Breath"
        static let someBeverageFoodOdor = "Food & Drink Aftertaste"
        static let noticeableMalodor = "Freshness Boost Recommended"
        static let strongMalodor = "Oral Hydration & Care Alert"
    }

    struct ResultDescriptions {
        static let none =
            "Sample wasn't quite strong enough. Try taking a deep breath and blowing steadily."
        static let dryMouthHydrate =
            "Breath humidity is a bit low. A glass of water will help refresh your mouth and restore balance."
        static let dryMouthVscBuildup =
            "Natural dryness can temporarily affect freshness. Hydrating and rinsing will clear natural buildup."
        static let settleBeverageFoodOdor =
            "Residual notes from recent food or drinks are settling and should clear naturally soon."
        static let balancedBreath =
            "Your breath profile is clean, light, and well-balanced!"
        static let someBeverageFoodOdor =
            "Noticeable flavor notes from recent meals or beverages detected. A quick water rinse helps reset."
        static let noticeableMalodor =
            "A slight shift in breath freshness detected. Rinsing or brushing will quickly restore your baseline."
        static let strongMalodor =
            "A distinct shift in breath notes detected. Hydrate, brush, or use mouthwash to reset your balance."
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
        "Breath test blocked: Sensor is currently in 5-minute cold boot warmup."
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
        savedMesoNoseUUID = nil
        ignoredMesoNoseUUID = nil
        isPairingModeActive = true
        statusText = MesoNoseUIStrings.searchingNearby
        AppLogger.writeLog(MesoNoseLogMessages.pairingModeActive)
        startScanning()
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

    func handleMesoNosePacket(_ text: String) {
        guard let data = text.data(using: .utf8),
            let jsonObj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let sample = MesoNoseSample(jsonString: text),
                let bat = sample.battery, bat > MesoNoseConstants.zeroInt
            {
                self.mesoNoseBattery = bat
            }

            // 1. Handle status flags using MesoNoseFirmwareStatus
            if let statusStr = jsonObj[MesoNosePayloadKeys.status] as? String,
                let status = MesoNoseFirmwareStatus(rawValue: statusStr)
            {
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
                let state = MesoNoseFirmwareState(rawValue: stateStr)
            {
                switch state {
                case .coldBootWarmingUp:
                    self.breathTestState = .coldBootWarmup
                    if let remainingSec = jsonObj[
                        MesoNosePayloadKeys.remainingSec
                    ] as? Int {
                        let mins =
                            remainingSec / MesoNoseConstants.secondsPerMinute
                        let secs =
                            remainingSec % MesoNoseConstants.secondsPerMinute
                        self.statusText = MesoNoseUIStrings.warmingUpFormatted(
                            mins: mins,
                            secs: secs
                        )
                    } else {
                        self.statusText =
                            MesoNoseUIStrings.sensorWarmingUpColdBoot
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
                    self.breathTestState = .processing
                    self.statusText = MesoNoseUIStrings.analyzingBreath
                    return

                case .recoveringCalculatingT50:
                    self.breathTestState = .processing
                    self.statusText = MesoNoseUIStrings.calculatingT50
                    return

                case .exhalationTooWeak:
                    AppLogger.writeLog(MesoNoseLogMessages.exhalationTooWeak)
                    self.statusText = MesoNoseUIStrings.exhalationTooWeak
                    self.handleBreathTestCompletion(didSucceed: false)
                    return

                case .tryAgainLater:
                    AppLogger.writeLog(MesoNoseLogMessages.tryAgainLater)
                    self.statusText = MesoNoseUIStrings.tryAgainLater
                    self.handleBreathTestCompletion(didSucceed: false)
                    return

                case .timeout:
                    AppLogger.writeLog(MesoNoseLogMessages.timeout)
                    self.statusText = MesoNoseUIStrings.noBreathDetected
                    self.handleBreathTestCompletion(didSucceed: false)
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

            guard
                sample.temp > MesoNoseConstants.zeroDouble
                    && sample.humidity > MesoNoseConstants.zeroDouble
            else { return }

            let hasValidBreathResult =
                sample.breathDropDelta > MesoNoseConstants.zeroDouble
                || (sample.ptcResult != MesoNoseResult.none.rawValue
                    && !sample.ptcResult.isEmpty)
            let isTransientWarmupSpike =
                sample.voc > MesoNoseConstants.transientWarmupVocThreshold
                && !hasValidBreathResult

            guard !isTransientWarmupSpike else { return }

            self.saveMesoNoseToDatabase(sample)

            if hasValidBreathResult {
                self.statusText = MesoNoseUIStrings.analysisComplete
                self.mesoNoseSamples.insert(
                    sample,
                    at: MesoNoseConstants.zeroInt
                )
                self.handleBreathTestCompletion(didSucceed: true)
            } else if self.breathTestState != .blowNow
                && self.breathTestState != .processing
            {
                self.mesoNoseSamples.insert(
                    sample,
                    at: MesoNoseConstants.zeroInt
                )
                if self.breathTestState == .coldBootWarmup
                    || self.breathTestState == .warmingUp
                {
                    self.breathTestState = .idle
                    self.statusText = MesoNoseUIStrings.connectedReady
                    AppLogger.writeLog(MesoNoseLogMessages.warmupComplete)
                }
            }
        }
    }

    private func transitionToBlowNow() {
        self.breathTestState = .blowNow
        self.statusText = MesoNoseUIStrings.blowNow
        self.startBlowTimeoutGuard()
    }

    private func startBlowTimeoutGuard() {
        self.blowTimeoutTimer?.invalidate()

        AppLogger.writeLog(MesoNoseLogMessages.blowTimeoutStarted)

        self.blowTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: AppConfig.breathWaitTimeout,
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if self.breathTestState == .blowNow
                    || self.breathTestState == .processing
                {
                    AppLogger.writeLog(MesoNoseLogMessages.blowWindowTimedOut)
                    self.statusText = MesoNoseUIStrings.noBreathDetected
                    self.handleBreathTestCompletion(didSucceed: false)
                }
            }
        }
    }

    func cancelBreathTest() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

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
    func handleBreathTestCompletion(didSucceed: Bool) {
        guard
            self.breathTestState != .completed
                && self.breathTestState != .timeout
        else { return }

        self.preheatWorkItem?.cancel()
        self.preheatWorkItem = nil
        self.postTestPurgeWorkItem?.cancel()
        self.postTestPurgeWorkItem = nil
        self.blowTimeoutTimer?.invalidate()
        self.blowTimeoutTimer = nil

        self.lastTestCompletedDate = Date()
        self.breathTestState = didSucceed ? .completed : .timeout

        AppLogger.writeLog(
            MesoNoseLogMessages.testFinished(succeeded: didSucceed)
        )

        //        let purgeWorkItem = DispatchWorkItem { [weak self] in
        //            guard let self = self else { return }
        //
        //            AppLogger.writeLog(MesoNoseLogMessages.activatingPurge)
        //            self.sendMesoNoseCommand(.setActiveSamplingMode)
        //
        //            let revertWorkItem = DispatchWorkItem { [weak self] in
        //                guard let self = self else { return }
        //                self.sendMesoNoseCommand(.setUltraLowSamplingMode)
        //                AppLogger.writeLog(MesoNoseLogMessages.purgeCompleted)
        //            }
        //
        //            self.postTestPurgeWorkItem = revertWorkItem
        //            DispatchQueue.main.asyncAfter(
        //                deadline: .now() + AppConfig.postTestPurgeDuration,
        //                execute: revertWorkItem
        //            )
        //        }
        //
        //        self.postTestPurgeWorkItem = purgeWorkItem
        //        DispatchQueue.main.asyncAfter(
        //            deadline: .now() + AppConfig.firmwareTeardownDelay,
        //            execute: purgeWorkItem
        //        )

        DispatchQueue.main.asyncAfter(
            deadline: .now() + AppConfig.firmwareTeardownDelay
        ) { [weak self] in
            guard let self = self else { return }
            self.sendMesoNoseCommand(.setUltraLowSamplingMode)
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
            let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            return false
        }

        return !json.keys.filter {
            MesoNosePayloadKeys.allValidKeys.contains($0)
        }.isEmpty
    }
}
