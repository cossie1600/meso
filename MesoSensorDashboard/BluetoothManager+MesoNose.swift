//
//  BluetoothManager+MesoNose.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/8/26.
//

import Foundation
import CoreBluetooth
import SwiftData

extension BluetoothManager {
    
    /// Returns the specific CBPeripheral instance connected for Meso Nose
    var mesoNosePeripheral: CBPeripheral? {
        return connectedPeripherals.values.first { $0.name?.hasPrefix(AppConfig.mesoNoseBluetoothName) == true }
    }
    
    /// Sends a command payload specifically to the Meso Nose peripheral
    func sendMesoNoseCommand(_ command: AppConfig.MesoNoseCommand) {
        self.lastSentCommand = command

        guard let peripheral = mesoNosePeripheral else {
            AppLogger.writeLog("Cannot send '\(command.description)': Meso Nose device not found in connected peripherals.")
            return
        }
        
        var targetChar = writeCharacteristics[peripheral.identifier]
        
        if targetChar == nil {
            targetChar = peripheral.services?
                .flatMap { $0.characteristics ?? [] }
                .first { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
            
            if let foundChar = targetChar {
                writeCharacteristics[peripheral.identifier] = foundChar
            }
        }
        
        guard let char = targetChar else {
            AppLogger.writeLog("Cannot send '\(command.description)': Write characteristic for Meso Nose (\(peripheral.identifier)) not cached.")
            return
        }
        
        if let data = command.payload.data(using: .utf8) {
            let writeType: CBCharacteristicWriteType = char.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(data, for: char, type: writeType)
            AppLogger.writeLog("Sent Meso Nose Command [\(command.payload)] to \(peripheral.name ?? "Meso Nose"): \(command.description)")
        }
    }

    // MARK: - Sampling Directives
    func stopSampling() {
        startSampling(mode: .stopped)
    }
    
    func setActiveSamplingMode() {
        startSampling(mode: .active3s)
    }

    func setUltraLowSamplingMode() {
        startSampling(mode: .ulp5m)
    }

    func isUltraLowSamplingMode() -> Bool {
        return currentSamplingMode == .ulp5m
    }

    // MARK: - Breath Test Trigger & Handling
    func triggerBreathTest() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Determine required warmup duration: 15s for ULP mode, 4s for active mode
            let warmupSeconds = self.isUltraLowSamplingMode() ? 15 : 4
            AppLogger.writeLog("Triggering Breath Test. Current Mode: \(self.currentSamplingMode.rawValue). Preheating for \(warmupSeconds)s...")
            
            self.startCountdownTimer(from: warmupSeconds)
        }
        
        if AppConfig.useMockSimulatorBridge {
            mockTriggerBreathTest()
        } else {
            sendMesoNoseCommand(.triggerBreathTest)
        }
    }

    func handleMesoNosePacket(_ text: String) {
        guard let data = text.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let defaultWarmup = self.isUltraLowSamplingMode() ? 15 : 4
            
            // 1. Intercept Status Tokens
            if let status = jsonObj[AppConfig.MesoNoseKeys.status] as? String, status == "BREATH_TEST_STARTED" {
                if self.breathTestState != .warmingUp {
                    self.startCountdownTimer(from: defaultWarmup)
                }
                return
            }
            
            // 2. Intercept Firmware State Transitions
            if let state = jsonObj[AppConfig.MesoNoseKeys.state] as? String {
                switch state {
                case "WARMING_UP":
                    let seconds = jsonObj["seconds"] as? Int ?? defaultWarmup
                    if self.breathTestState != .warmingUp {
                        self.startCountdownTimer(from: seconds)
                    }
                    return
                    
                case "READY_PLEASE_BLOW":
                    self.mockDataTimer?.invalidate()
                    self.mockDataTimer = nil
                    self.breathTestState = .blowNow
                    self.statusText = "BLOW NOW"
                    return

                case "TESTING_SENSING_BREATH":
                    self.mockDataTimer?.invalidate()
                    self.mockDataTimer = nil
                    self.breathTestState = .processing
                    self.statusText = "Analyzing breath sample..."
                    return
                    
                case "TIMEOUT":
                    self.mockDataTimer?.invalidate()
                    self.mockDataTimer = nil
                    self.statusText = "No Breath Detected"
                    self.handleBreathTestCompletion(didSucceed: false)
                    return
                    
                default:
                    break
                }
            }
            
            // 3. Attempt parsing the payload into a MesoNoseSample
            guard let sample = MesoNoseSample(jsonString: text) else {
                if jsonObj["dH"] == nil && jsonObj["gDrop"] == nil {
                    AppLogger.writeLog("⚠️ Failed to parse MesoNoseSample from JSON payload: \(text)")
                }
                return
            }
            
            // 4. Save every valid incoming packet directly to SwiftData
            self.saveMesoNoseToDatabase(sample)
            
            // 5. Check UI state and update in-memory array for active subscribers
            let isFinalResult = sample.breathDropDelta > 0.0 || (sample.ptcResult != "NONE" && !sample.ptcResult.isEmpty)
            
            if isFinalResult {
                self.mockDataTimer?.invalidate()
                self.mockDataTimer = nil
                self.statusText = "Analysis Complete"
                self.mesoNoseSamples.insert(sample, at: 0)
                self.handleBreathTestCompletion(didSucceed: true)
            } else if self.breathTestState == .idle {
                self.mesoNoseSamples.insert(sample, at: 0)
            }
        }
    }

    private func startCountdownTimer(from seconds: Int) {
            self.mockDataTimer?.invalidate()
            self.mockDataTimer = nil
            
            self.breathTestState = .warmingUp
            self.countdownSeconds = seconds
            self.statusText = "Warming up sensor..."
            
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] t in
                guard let self = self else {
                    t.invalidate()
                    return
                }
                
                if self.countdownSeconds > 1 {
                    self.countdownSeconds -= 1
                } else {
                    t.invalidate()
                    self.mockDataTimer = nil
                    
                    // 1. Transition to BLOW NOW when warmup finishes
                    if self.breathTestState == .warmingUp {
                        self.breathTestState = .blowNow
                        self.statusText = "BLOW NOW"
                        
                        // 2. Start a 10-second timeout safety guard for the BLOW phase
                        self.startBlowTimeoutGuard()
                    }
                }
            }
            
            RunLoop.main.add(timer, forMode: .common)
            self.mockDataTimer = timer
        }

        private func startBlowTimeoutGuard() {
            // Prevent stacking duplicate timeout timers
            self.mockDataTimer?.invalidate()
            
            AppLogger.writeLog("BLOW NOW active. Starting 10s hardware response timeout guard...")
            
            self.mockDataTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    // If still stuck in blowNow or processing when timeout fires, recover gracefully
                    if self.breathTestState == .blowNow || self.breathTestState == .processing {
                        AppLogger.writeLog("⚠️ Blow window timed out with no hardware evaluation packet. Auto-recovering...")
                        self.statusText = "No Breath Detected"
                        self.handleBreathTestCompletion(didSucceed: false)
                    }
                }
            }
        }
}

// MARK: - Breath Test Lifecycle Recovery
extension BluetoothManager {
    
    @MainActor
    func handleBreathTestCompletion(didSucceed: Bool) {
        self.lastTestCompletedDate = Date()
        self.breathTestState = didSucceed ? .completed : .timeout
        
        AppLogger.writeLog("Breath test finished (\(didSucceed ? "Success" : "Timeout")). Starting 60s active purge...")
        
        // 1. Force active 3s sampling to heat the sensor and flush residual VOCs faster
        self.startSampling(mode: .active3s)
        
        // 2. Revert to configured background mode (e.g., ULP 5m) after 60 seconds of active purging
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
            guard let self = self else { return }
            if self.breathTestState == .completed || self.breathTestState == .timeout {
                self.breathTestState = .idle
                self.startSampling(mode: AppConfig.samplingMode)
                AppLogger.writeLog("Post-test purge completed. Reverted to \(AppConfig.samplingMode.rawValue).")
            }
        }
    }
}

extension String {
    var isMesoNosePayload: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else { return false }
        
        return AppConfig.MesoNoseKeys.allDiscriminators.contains { discriminator in
            trimmed.contains(discriminator)
        }
    }
}
