//
//  BluetoothManager+Mock.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/14/26.
//

import Foundation

extension BluetoothManager {
    
    func stopMockDataStream() {
            mockDataTimer?.invalidate()
            mockDataTimer = nil
            AppLogger.writeLog("🧪 [Mock] Data stream stopped")
        }
    
    func startMockDataStream() {
        var timeTick = 0
        
        mockDataTimer?.invalidate()
        mockDataTimer = Timer.scheduledTimer(withTimeInterval: AppConfig.simulatorSpeedSec, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            timeTick += 1
            
            // ----------------------------------------------------------------
            // 1. Meso Pin (BMV080) Particle Data Generation
            // ----------------------------------------------------------------
            let pm1: Double
            let pm25: Double
            let pm10: Double
            
            if timeTick % 30 < 10 {
                // State 1: 🟢 Clean Air Zone
                pm1 = Double.random(in: 0.5...2.0)
                pm25 = Double.random(in: 4.0...12.0)
                pm10 = Double.random(in: 8.0...20.0)
            } else if timeTick % 30 < 20 {
                // State 2: 🔵 Smoke/Smog Fine Particle Spike
                pm1 = Double.random(in: 15.0...25.0)
                pm25 = Double.random(in: 38.0...45.0)
                pm10 = Double.random(in: 48.0...60.0)
            } else {
                // State 3: 🟢 Coarse Dust/Allergen Wave
                pm1 = Double.random(in: 0.5...1.5)
                pm25 = Double.random(in: 10.0...14.0)
                pm10 = Double.random(in: 110.0...130.0)
            }
            
            // Route PM data execution layout depending on AppConfig choice
            var parsedPacket: IncomingPacket? = nil
            
            switch AppConfig.activeMockFormat {
            case .csv:
                let csvString = "\(pm1),\(pm25),\(pm10)"
                parsedPacket = IncomingPacket.decodeCommaSeparatedString(from: csvString)
                
            case .json:
                let currentTimestamp = UInt64(Date().timeIntervalSince1970 * 1000)
                let mockDict: [String: Any] = [
                    "t": currentTimestamp,
                    "pm1": pm1,
                    "pm25": pm25,
                    "pm10": pm10
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: mockDict, options: []),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    parsedPacket = IncomingPacket.decodeJSON(from: jsonString)
                }
            }
            
            // Forward PM packet down operational pipeline
            if let packet = parsedPacket {
                DispatchQueue.main.async {
                    self.saveToSQLite(packet)
                    self.updateLiveState(with: packet)
                    self.evaluateAirQualityThresholds(for: packet)
                }
            }
            
            // ----------------------------------------------------------------
            // 2. Meso Nose (BME688) Telemetry JSON Generation
            // ----------------------------------------------------------------
            let temp = Double.random(in: 21.5...26.5)
            let humidity = Double.random(in: 40.0...65.0)
            let pressure = Double.random(in: 1008.0...1018.0)
            let baseGasRes = Int.random(in: 45000...120000)
            
            let mockAmbientJson = """
            {"rt":\(String(format: "%.1f", temp)),"rh":\(String(format: "%.1f", humidity)),"press":\(String(format: "%.1f", pressure)),"voc":\(baseGasRes),"breath_drop_delta":0.0,"breath_min":0,"ptc_result":"NONE"}
            """
                        
            self.handleMesoNosePacket(mockAmbientJson)
        }
    }
    
    func mockTriggerBreathTest() {
            let temp = Double.random(in: 22.0...25.0)
            let humidity = Double.random(in: 55.0...75.0)
            let pressure = Double.random(in: 1010.0...1015.0)
            let baseGasRes = Int.random(in: 60000...110000)
            
            let deltaDrop = Double.random(in: 10.0...65.0)
            let minRes = Int(Double(baseGasRes) * (1.0 - (deltaDrop / 100.0)))
            
            let ptcResult: String
            if deltaDrop < 15.0 {
                ptcResult = "FRESH"
            } else if deltaDrop < 35.0 {
                ptcResult = "MILD"
            } else if deltaDrop < 55.0 {
                ptcResult = "SIGNIFICANT"
            } else {
                ptcResult = "SEVERE"
            }
            
            let mockEvaluationJson = """
            {"rt":\(String(format: "%.1f", temp)),"rh":\(String(format: "%.1f", humidity)),"press":\(String(format: "%.1f", pressure)),"voc":\(baseGasRes),"breath_drop_delta":\(String(format: "%.1f", deltaDrop)),"breath_min":\(minRes),"ptc_result":"\(ptcResult)"}
            """
            
            AppLogger.writeLog("🧪 [Mock] Manual Breath Test Evaluation Triggered -> \(ptcResult) (\(String(format: "%.1f", deltaDrop))%)")
            self.handleMesoNosePacket(mockEvaluationJson)
        }
}
