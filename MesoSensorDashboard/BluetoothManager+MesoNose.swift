//
//  BluetoothManager+MesoNose.swift
//  MesoSensorDashboard
//

import CoreBluetooth
import Foundation
import SwiftData

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
                "Cannot send '\(command.description)': Meso Nose device not found in connected peripherals."
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
                "Write characteristic for Meso Nose (\(peripheral.identifier)) not cached yet. Queueing command '\(command.description)'..."
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
                "Sent Meso Nose Command [\(command.payload)] to \(peripheral.name ?? "Meso Nose"): \(command.description)"
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
        statusText = "Device Unpaired"
        AppLogger.writeLog(
            "Meso Nose unpaired. Sitting quietly in unpaired state."
        )
    }

    func startPairingMesoNose() {
        savedMesoNoseUUID = nil
        ignoredMesoNoseUUID = nil
        isPairingModeActive = true
        statusText = "Searching for nearby Meso Nose..."
        AppLogger.writeLog(
            "Pairing Mode active: Searching for closest Meso Nose..."
        )
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

            // Immediately update both state and sampling mode
            self.breathTestState = .warmingUp
            self.currentSamplingMode = .active3s  // Prevent UI baseline state lock
            self.statusText = "Waking sensor & pre-heating..."

            self.setActiveSamplingMode()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.breathTestState == .warmingUp else {
                    return
                }

                self.statusText = "Heating sensor plate..."
                AppLogger.writeLog(
                    "Pre-heat complete. Triggering Breath Test command..."
                )
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

            // Cache battery whenever present and > 0
            if let sample = MesoNoseSample(jsonString: text),
                let bat = sample.battery, bat > 0
            {
                self.mesoNoseBattery = bat
            }

            if let state = jsonObj[AppConfig.MesoNoseKeys.state] as? String {
                switch state {
                case "WARMING_UP":
                    self.breathTestState = .warmingUp
                    self.statusText = "Heating sensor plate..."
                    return

                case "READY_PLEASE_BLOW":
                    AppLogger.writeLog(
                        "Received READY_PLEASE_BLOW from hardware. Transitioning to BLOW NOW!"
                    )
                    self.transitionToBlowNow()
                    return

                case "TESTING_SENSING_BREATH":
                    self.breathTestState = .processing
                    self.statusText = "Analyzing breath sample..."
                    return

                case "TIMEOUT":
                    self.statusText = "No Breath Detected"
                    self.handleBreathTestCompletion(didSucceed: false)
                    return

                // Reset purge timestamp when hardware transitions to ULP
                case "PROFILE_ULP":
                    AppLogger.writeLog(
                        "Ingestion: Hardware reported PROFILE_ULP. Clearing moisture purge state."
                    )
                    self.currentSamplingMode = .ulp5m
                    
                    return

                // Update app mode state when hardware confirms LP
                case "PROFILE_LP":
                    AppLogger.writeLog(
                        "Ingestion: Hardware reported PROFILE_LP."
                    )
                    self.currentSamplingMode = .active3s
                    return

                default:
                    break
                }
            }

            guard let sample = MesoNoseSample(jsonString: text) else { return }

            guard sample.temp > 0.0 && sample.humidity > 0.0 else { return }

            let hasValidBreathResult =
                sample.breathDropDelta > 0.0
                || (sample.ptcResult != "NONE" && !sample.ptcResult.isEmpty)
            let isTransientWarmupSpike =
                sample.voc > 2_000_000 && !hasValidBreathResult

            guard !isTransientWarmupSpike else { return }

            self.saveMesoNoseToDatabase(sample)

            if hasValidBreathResult {
                self.statusText = "Analysis Complete"
                self.mesoNoseSamples.insert(sample, at: 0)
                self.handleBreathTestCompletion(didSucceed: true)
            } else if self.breathTestState == .idle {
                self.mesoNoseSamples.insert(sample, at: 0)
            }
        }
    }

    private func transitionToBlowNow() {
        self.breathTestState = .blowNow
        self.statusText = "BLOW NOW"

        self.startBlowTimeoutGuard()
    }

    private func startBlowTimeoutGuard() {
        self.blowTimeoutTimer?.invalidate()

        AppLogger.writeLog(
            "BLOW NOW active. Starting \(Int(AppConfig.breathWaitTimeout))s hardware response timeout guard..."
        )

        self.blowTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: AppConfig.breathWaitTimeout,
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if self.breathTestState == .blowNow
                    || self.breathTestState == .processing
                {
                    AppLogger.writeLog(
                        "Blow window timed out with no hardware evaluation packet. Auto-recovering..."
                    )
                    self.statusText = "No Breath Detected"
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
            self.statusText = "Test Cancelled"

            self.sendMesoNoseCommand(.setUltraLowSamplingMode)
            AppLogger.writeLog(
                "Breath test explicitly cancelled by user. Hardware reset to ULP mode."
            )
        }
    }
}

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

        // Preserve timeout or completed state so Retry/Start buttons behave properly
        self.breathTestState = didSucceed ? .completed : .timeout

        AppLogger.writeLog(
            "Breath test finished (\(didSucceed ? "Success" : "Timeout")). Queueing \(Int(AppConfig.postTestPurgeDuration))s active moisture purge..."
        )

        let purgeWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            AppLogger.writeLog("Activating active purge...")
            self.sendMesoNoseCommand(.setActiveSamplingMode)

            let revertWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // Revert hardware mode to ULP without clearing the timeout/completed UI state
                self.sendMesoNoseCommand(.setUltraLowSamplingMode)
                AppLogger.writeLog(
                    "Post-test purge completed. Hardware reverted to ULP mode (5m)."
                )
            }

            self.postTestPurgeWorkItem = revertWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + AppConfig.postTestPurgeDuration,
                execute: revertWorkItem
            )
        }

        self.postTestPurgeWorkItem = purgeWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + AppConfig.firmwareTeardownDelay,
            execute: purgeWorkItem
        )
    }
}

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

        let validKeys: Set<String> = [
            "temp", "rh", "press", "voc", "ptc_result", "status",
            "state", "rx_cmd", "dH", "gDrop", "seconds",
        ]

        return !json.keys.filter { validKeys.contains($0) }.isEmpty
    }
}
