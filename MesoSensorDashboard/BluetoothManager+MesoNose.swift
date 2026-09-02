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
                .first { $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write) }
            
            if let foundChar = targetChar {
                writeCharacteristics[peripheral.identifier] = foundChar
            }
        }
        
        guard let char = targetChar else {
            AppLogger.writeLog("Cannot send '\(command.description)': Write characteristic for Meso Nose (\(peripheral.identifier)) not cached.")
            return
        }
        
        if let data = command.payload.data(using: .utf8) {
            let writeType: CBCharacteristicWriteType = char.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
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
            
            // Guard against duplicate rapid taps while already in a test sequence
            guard self.breathTestState == .idle || self.breathTestState == .completed || self.breathTestState == .timeout else {
                AppLogger.writeLog("⚠️ Breath test trigger ignored: state is currently '\(self.breathTestState)'.")
                return
            }
            
            let initialWarmupSeconds = self.isUltraLowSamplingMode() ? 15 : 4
            self.breathTestState = .warmingUp
            self.countdownSeconds = initialWarmupSeconds
            self.statusText = "Warming up sensor..."
            
            AppLogger.writeLog("Triggering Breath Test. Preheating (\(initialWarmupSeconds)s)...")
            
            self.sendMesoNoseCommand(.triggerBreathTest)
            self.startCountdownTimer(from: initialWarmupSeconds)
        }
    }
    
    func handleMesoNosePacket(_ text: String) {
        guard let data = text.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Intercept Firmware State Transitions
            if let state = jsonObj[AppConfig.MesoNoseKeys.state] as? String {
                switch state {
                case "WARMING_UP":
                    let seconds = jsonObj["seconds"] as? Int ?? (self.isUltraLowSamplingMode() ? 15 : 4)
                    self.startCountdownTimer(from: seconds)
                    return
                    
                case "READY_PLEASE_BLOW":
                    self.transitionToBlowNow()
                    return
                    
                case "TESTING_SENSING_BREATH":
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.breathTestState = .processing
                    self.statusText = "Analyzing breath sample..."
                    return
                    
                case "TIMEOUT":
                    self.statusText = "No Breath Detected"
                    self.handleBreathTestCompletion(didSucceed: false)
                    return
                    
                default:
                    break
                }
            }
            
            // 2. Ignore intermediate 1-second BLOW debug packets ({"dH": ..., "gDrop": ...})
            if jsonObj["dH"] != nil || jsonObj["gDrop"] != nil {
                return
            }
            
            // 3. Attempt parsing the final payload into a MesoNoseSample
            guard let sample = MesoNoseSample(jsonString: text) else {
                AppLogger.writeLog("⚠️ Failed to parse MesoNoseSample from JSON payload: \(text)")
                return
            }
            
            // -------------------------------------------------------------------
            // 🛡️ INGESTION SANITATION & OUTLIER FILTERING
            // -------------------------------------------------------------------
            
            // Filter 3a: Drop zeroed boot/uninitialized frames (temp == 0, rh == 0)
            guard sample.temp > 0.0 && sample.humidity > 0.0 else {
                AppLogger.writeLog("🛡️ Ingestion Filter: Dropped zeroed boot frame during hardware initialization.")
                return
            }
            
            // Filter 3b: Filter out MOX heater thermal stabilization spikes (e.g. 8M+ VOC)
            // High readings are allowed only if part of an active breath evaluation drop delta
            let isTransientWarmupSpike = sample.voc > 2_000_000 && sample.breathDropDelta == 0.0
            guard !isTransientWarmupSpike else {
                AppLogger.writeLog("🛡️ Ingestion Filter: Rejected MOX sensor thermal stabilization spike [VOC: \(sample.voc)].")
                return
            }
            
            // -------------------------------------------------------------------
            
            // 4. Save every valid incoming packet directly to SwiftData
            self.saveMesoNoseToDatabase(sample)
            
            // 5. Check UI state and update in-memory array for active subscribers
            let isFinalResult = sample.breathDropDelta > 0.0 || (sample.ptcResult != "NONE" && !sample.ptcResult.isEmpty)
            
            if isFinalResult {
                self.statusText = "Analysis Complete"
                self.mesoNoseSamples.insert(sample, at: 0)
                self.handleBreathTestCompletion(didSucceed: true)
            } else if self.breathTestState == .idle {
                self.mesoNoseSamples.insert(sample, at: 0)
            }
        }
    }
    
    // Updated countdown timer that strictly waits for firmware state events
    private func startCountdownTimer(from seconds: Int) {
        self.countdownTimer?.invalidate()
        self.countdownTimer = nil
        
        self.breathTestState = .warmingUp
        self.countdownSeconds = seconds
        self.statusText = "Warming up sensor..."
        
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else {
                t.invalidate()
                return
            }
            
            if self.countdownSeconds > 0 {
                self.countdownSeconds -= 1
            } else {
                t.invalidate()
                self.countdownTimer = nil
                
                if self.breathTestState == .warmingUp {
                    AppLogger.writeLog("⏱️ Local preheat complete. Transitioning to BLOW NOW...")
                    self.transitionToBlowNow()
                }
            }
        }
        
        RunLoop.main.add(timer, forMode: .common)
        self.countdownTimer = timer
    }
    
    private func transitionToBlowNow() {
        self.countdownTimer?.invalidate()
        self.countdownTimer = nil
        
        self.breathTestState = .blowNow
        self.statusText = "BLOW NOW"
        
        self.startBlowTimeoutGuard()
    }
    
    private func startBlowTimeoutGuard() {
        self.blowTimeoutTimer?.invalidate()
        
        AppLogger.writeLog("BLOW NOW active. Starting 10s hardware response timeout guard...")
        
        self.blowTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
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
        self.countdownTimer?.invalidate()
        self.countdownTimer = nil
        self.blowTimeoutTimer?.invalidate()
        self.blowTimeoutTimer = nil
        
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
