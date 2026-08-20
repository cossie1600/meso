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
        guard let peripheral = mesoNosePeripheral else {
            AppLogger.writeLog("Cannot send '\(command.description)': Meso Nose device not found in connected peripherals.")
            return
        }
        
        let targetChar = writeCharacteristics[peripheral.identifier] ?? peripheral.services?
            .flatMap { $0.characteristics ?? [] }
            .first { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
        
        guard let char = targetChar else {
            AppLogger.writeLog("Cannot send '\(command.description)': Write characteristic for Meso Nose (\(peripheral.identifier)) not found.")
            return
        }
        
        if let data = command.payload.data(using: .utf8) {
            let writeType: CBCharacteristicWriteType = char.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(data, for: char, type: writeType)
            AppLogger.writeLog("Sent Meso Nose Command [\(command.payload)] to \(peripheral.name ?? "Meso Nose"): \(command.description)")
        }
    }

    func startActiveSampling() {
        if AppConfig.useMockSimulatorBridge {
            startMockDataStream()
        } else {
            sendMesoNoseCommand(.startActiveSampling)
        }
    }

    func stopSampling() {
        if AppConfig.useMockSimulatorBridge {
            stopMockDataStream()
        } else {
            sendMesoNoseCommand(.stopSampling)
        }
    }
    
    func setActiveSamplingMode() {
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("[Mock] Set Active Sampling Mode (3s LP)")
        } else {
            sendMesoNoseCommand(.setActiveSamplingMode)
        }
    }

    func setUltraLowSamplingMode() {
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("[Mock] Set Ultra Low Sampling Mode (5m ULP)")
        } else {
            sendMesoNoseCommand(.setUltraLowSamplingMode)
        }
    }

    func triggerBreathTest() {
        self.mockDataTimer?.invalidate()
        
        DispatchQueue.main.async { [weak self] in
            self?.breathTestState = .warmingUp
            self?.countdownSeconds = 4
            self?.statusText = "Warming up sensor..."
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
                
                // 1. Intercept Status Tokens
                if let status = jsonObj[MesoNoseKeys.status] as? String, status == "BREATH_TEST_STARTED" {
                    self.startCountdownTimer(from: 4)
                    return
                }
                
                // 2. Intercept Firmware State Transitions
                if let state = jsonObj[MesoNoseKeys.state] as? String {
                    switch state {
                    case "WARMING_UP":
                        let seconds = jsonObj["seconds"] as? Int ?? 4
                        self.startCountdownTimer(from: seconds)
                        return
                        
                    case "READY_PLEASE_BLOW":
                        self.mockDataTimer?.invalidate()
                        self.breathTestState = .blowNow
                        self.statusText = "BLOW NOW"
                        return

                    case "TESTING_SENSING_BREATH":
                        self.mockDataTimer?.invalidate()
                        self.breathTestState = .processing
                        self.statusText = "Analyzing breath sample..."
                        return
                        
                    case "TIMEOUT":
                        self.mockDataTimer?.invalidate()
                        self.breathTestState = .timeout
                        self.statusText = "No Breath Detected"
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
                
                // 4. Check if this is a completed breath test evaluation result
                let isFinalResult = sample.breathDropDelta > 0.0 || (sample.ptcResult != "NONE" && !sample.ptcResult.isEmpty)
                
                if isFinalResult {
                    self.mockDataTimer?.invalidate()
                    self.breathTestState = .completed
                    self.statusText = "Analysis Complete"
                    
                    // Prepend to array so SwiftUI views observing mesoNoseSamples.first pick up the completed result immediately
                    self.mesoNoseSamples.insert(sample, at: 0)
                    self.saveMesoNoseToDatabase(sample)
                } else if self.breathTestState == .idle {
                    // Only overwrite telemetry array for routine background ambient samples if no active completion state is showing
                    self.mesoNoseSamples.insert(sample, at: 0)
                }
            }
        }

    private func startCountdownTimer(from seconds: Int) {
        self.mockDataTimer?.invalidate()
        self.breathTestState = .warmingUp
        self.countdownSeconds = seconds > 0 ? seconds : 4
        
        self.mockDataTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                if self.countdownSeconds > 1 {
                    self.countdownSeconds -= 1
                } else {
                    timer.invalidate()
                    if self.breathTestState == .warmingUp {
                        self.breathTestState = .blowNow
                        self.statusText = "BLOW NOW"
                    }
                }
            }
        }
    }
}

extension String {
    /// Inspects the raw text string to identify if it originates from the Meso Nose (BME688) firmware
    var isMesoNosePayload: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else { return false }
        
        return MesoNoseKeys.allKeys.contains { key in
            trimmed.contains("\"\(key)\"")
        }
    }
}
