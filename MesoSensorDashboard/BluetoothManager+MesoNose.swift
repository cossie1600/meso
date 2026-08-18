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
            if let status = jsonObj["status"] as? String, status == "BREATH_TEST_STARTED" {
                self.startCountdownTimer(from: 4)
                return
            }
            
            // 2. Intercept Firmware State Transitions
            if let state = jsonObj["state"] as? String {
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
                    // FIX: Immediately update UI from BLOW NOW to processing when blow is detected
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
                    return
                }
            }
            
            // 3. Ignore 1-second debug streaming packets (dH, gDrop)
            if jsonObj["dH"] != nil || jsonObj["gDrop"] != nil {
                return
            }
            
            // 4. Process Final Evaluation Result Payload
            if let sample = MesoNoseSample(jsonString: text) {
                let isFinalResult = sample.breathDropDelta > 0.0 || (sample.ptcResult != "NONE" && !sample.ptcResult.isEmpty)
                
                if isFinalResult {
                    self.mockDataTimer?.invalidate()
                    self.breathTestState = .completed
                    self.statusText = "Analysis Complete"
                }
                
                self.mesoNoseSamples.insert(sample, at: 0)
                
                if let context = self.modelContainer?.mainContext {
                    self.saveMesoNoseToDatabase(sample, context: context)
                }
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
        
    /// Inserts and saves the Meso Nose sample into SwiftData
    func saveMesoNoseToDatabase(_ sample: MesoNoseSample, context: ModelContext) {
        let dbRecord = DB_MesoNoseSample(
            timestamp: Date(),
            temp: sample.temp,
            humidity: sample.humidity,
            voc: sample.voc,
            breathDropDelta: sample.breathDropDelta,
            breathMin: sample.breathMin,
            ptcResult: sample.ptcResult
        )
        
        context.insert(dbRecord)
        
        do {
            try context.save()
            AppLogger.writeLog("Saved Meso Nose sample [VOC: \(sample.voc), PTC: \(sample.ptcResult)]")
        } catch {
            AppLogger.writeLog("SwiftData Save Error: \(error.localizedDescription)")
        }
    }
}

extension String {
    /// Inspects the raw text string to identify if it originates from the Meso Nose (BME688) firmware
    var isMesoNosePayload: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return trimmed.contains("{") && trimmed.contains("}") && (
            trimmed.contains("\"voc\"") ||
            trimmed.contains("\"temp\"") ||
            trimmed.contains("\"rt\"") ||
            trimmed.contains("\"rh\"") ||
            trimmed.contains("\"ptc_result\"") ||
            trimmed.contains("\"rx_cmd\"") ||
            trimmed.contains("\"status\"") ||
            trimmed.contains("\"state\"")
        )
    }
}
