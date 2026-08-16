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
    
    func sendMesoNoseCommand(_ command: AppConfig.MesoNoseCommand) {
        guard let char = writeCharacteristic else {
            AppLogger.writeLog("⚠️ Cannot send '\(command.description)': Write characteristic not cached.")
            return
        }
        
        guard let peripheral = connectedPeripheral else {
            AppLogger.writeLog("⚠️ Cannot send '\(command.description)': Device not connected.")
            return
        }
        
        if let data = command.payload.data(using: .utf8) {
            let writeType: CBCharacteristicWriteType = char.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(data, for: char, type: writeType)
            AppLogger.writeLog("📤 Sent Meso Nose Command [\(command.payload)]: \(command.description)")
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
            AppLogger.writeLog("🧪 [Mock] Set Active Sampling Mode (3s LP)")
        } else {
            sendMesoNoseCommand(.setActiveSamplingMode)
        }
    }

    func triggerBreathTest() {
        if AppConfig.useMockSimulatorBridge {
            mockTriggerBreathTest()
        } else {
            sendMesoNoseCommand(.triggerBreathTest)
        }
    }

    func setUltraLowSamplingMode() {
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("🧪 [Mock] Set Ultra Low Sampling Mode (5m ULP)")
        } else {
            sendMesoNoseCommand(.setUltraLowSamplingMode)
        }
    }

    func handleMesoNosePacket(_ text: String) {
            guard let sample = MesoNoseSample(jsonString: text) else { return }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 1. Update in-memory array for live UI telemetry
                self.mesoNoseSamples.insert(sample, at: 0)
                
                // 2. Persist to SwiftData
                if let context = self.modelContainer?.mainContext {
                    self.saveMesoNoseToDatabase(sample, context: context)
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
                AppLogger.writeLog("💾 Saved Meso Nose sample [VOC: \(sample.voc), PTC: \(sample.ptcResult)]")
            } catch {
                AppLogger.writeLog("❌ SwiftData Save Error: \(error.localizedDescription)")
            }
        }
}


extension String {
    /// Inspects the raw text string to identify if it originates from the Meso Nose (BME688) firmware
    var isMesoNosePayload: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Checks for valid JSON brackets and core BME688 telemetry keys
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}") && (
            trimmed.contains("\"voc\"") ||
            trimmed.contains("\"rt\"") ||
            trimmed.contains("\"rh\"") ||
            trimmed.contains("\"ptc_result\"") ||
            trimmed.contains("\"rx_cmd\"") ||
            trimmed.contains("\"status\"")
        )
    }
}
