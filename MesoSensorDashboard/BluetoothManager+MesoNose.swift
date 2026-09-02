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
    
    // MARK: - Breath Test Trigger & Handling
    func triggerBreathTest() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard self.breathTestState == .idle || self.breathTestState == .completed || self.breathTestState == .timeout else {
                AppLogger.writeLog("⚠️ Breath test trigger ignored: state is currently '\(self.breathTestState)'.")
                return
            }
            
            // Cancel initial startup burst timer so ULP mode is never forced mid-test
            self.cancelInitialBurstTimer()
            
            self.breathTestState = .warmingUp
            self.statusText = "Heating sensor plate..."
            
            AppLogger.writeLog("Triggering Breath Test. Awaiting firmware READY_PLEASE_BLOW event...")
            
            self.sendMesoNoseCommand(.triggerBreathTest)
        }
    }
    
    func handleMesoNosePacket(_ text: String) {
        guard let data = text.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Consume command acknowledgement receipts & status tokens
            if jsonObj["rx_cmd"] != nil || jsonObj["status"] != nil {
                return
            }
            
            // 2. Consume 1-second blow debug packets ({"dH": ..., "gDrop": ...})
            if jsonObj["dH"] != nil || jsonObj["gDrop"] != nil {
                return
            }
            
            // 3. Intercept Firmware State Transitions
            if let state = jsonObj[AppConfig.MesoNoseKeys.state] as? String {
                switch state {
                case "WARMING_UP":
                    self.breathTestState = .warmingUp
                    self.statusText = "Heating sensor plate..."
                    return
                    
                case "READY_PLEASE_BLOW":
                    AppLogger.writeLog("Received READY_PLEASE_BLOW from hardware. Transitioning to BLOW NOW!")
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
                    
                case "PROFILE_LP", "PROFILE_ULP":
                    // Safely consume profile state updates to prevent fallthrough
                    return
                    
                default:
                    return // Return on any unhandled state string
                }
            }
            
            // 4. Attempt parsing the final payload into a MesoNoseSample
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
            let isTransientWarmupSpike = sample.voc > 2_000_000 && sample.breathDropDelta == 0.0
            guard !isTransientWarmupSpike else {
                AppLogger.writeLog("🛡️ Ingestion Filter: Rejected MOX sensor thermal stabilization spike [VOC: \(sample.voc)].")
                return
            }
            
            // -------------------------------------------------------------------
            
            // 5. Save every valid incoming packet directly to SwiftData
            self.saveMesoNoseToDatabase(sample)
            
            // 6. Check UI state and update in-memory array for active subscribers
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
    
    private func transitionToBlowNow() {
        self.breathTestState = .blowNow
        self.statusText = "BLOW NOW"
        
        self.startBlowTimeoutGuard()
    }
    
    private func startBlowTimeoutGuard() {
        self.blowTimeoutTimer?.invalidate()
        
        AppLogger.writeLog("BLOW NOW active. Starting 10s hardware response timeout guard...")
        
        self.blowTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
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
        guard self.breathTestState != .completed && self.breathTestState != .timeout else { return }
        
        self.blowTimeoutTimer?.invalidate()
        self.blowTimeoutTimer = nil
        
        self.lastTestCompletedDate = Date()
        self.breathTestState = didSucceed ? .completed : .timeout
        
        AppLogger.writeLog("Breath test finished (\(didSucceed ? "Success" : "Timeout")). Starting 60s active purge...")
        
        self.setSamplingMode(mode: .active3s)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
            guard let self = self else { return }
            if self.breathTestState == .completed || self.breathTestState == .timeout {
                self.breathTestState = .idle
                self.setSamplingMode(mode: AppConfig.samplingMode)
                AppLogger.writeLog("Post-test purge completed. Reverted to \(AppConfig.samplingMode.rawValue).")
            }
        }
    }
}

extension String {
    var isMesoNosePayload: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else { return false }
        
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        // Define all valid keys directly or pull from AppConfig
        let validKeys: Set<String> = [
            "temp", "rh", "press", "voc", "ptc_result", "status",
            "state", "rx_cmd", "dH", "gDrop", "seconds"
        ]
        
        // Return true if the JSON object contains AT LEAST ONE valid key
        return !json.keys.filter { validKeys.contains($0) }.isEmpty
    }
}
