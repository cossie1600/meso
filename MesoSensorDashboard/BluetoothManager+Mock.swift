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
            // 🛑 GUARD: Do not inject background ambient mock packets while a
            // breath test sequence (warmup, blow now, or completed HUD) is active!
            guard self.breathTestState == .idle else { return }
            
            let temp = Double.random(in: 21.5...26.5)
            let humidity = Double.random(in: 40.0...65.0)
            let pressure = Double.random(in: 1008.0...1018.0)
            let baseGasRes = Int.random(in: 45000...120000)
            
            // Updated "temp" key so it matches standard MesoNoseSample decoding
            let mockAmbientJson = """
            {"temp":\(String(format: "%.1f", temp)),"rh":\(String(format: "%.1f", humidity)),"press":\(String(format: "%.1f", pressure)),"voc":\(baseGasRes)}
            """

            if self.breathTestState == .idle {
                self.handleMesoNosePacket(mockAmbientJson)
            }
        }
    }
    
    func handleMockPacket(_ text: String) {
        // Skip injecting background mock samples if user is actively doing a breath test
        guard breathTestState == .idle else { return }
        
        handleMesoNosePacket(text)
    }
    
    func mockTriggerBreathTest() {
        AppLogger.writeLog("🧪 [Mock] Starting Breath Sequence Simulation...")
        
        // 1. Kick off warmup phase
        handleMesoNosePacket("{\"status\":\"BREATH_TEST_STARTED\"}")
        handleMesoNosePacket("{\"state\":\"WARMING_UP\",\"seconds\":5}")
        
        // 2. Wait 8 seconds (5s warmup + 3s blowing phase), then inject the breath result
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self, self.breathTestState == .blowNow else { return }
            
            AppLogger.writeLog("🧪 [Mock] Simulating Breath Sample Receipt...")
            let mockBreathPayload = """
            {"temp":28.5,"rh":55.0,"press":1013.2,"voc":15200,"breath_drop_delta":42.5,"breath_min":8740,"ptc_result":"PTC_POSITIVE"}
            """
            self.handleMesoNosePacket(mockBreathPayload)
        }
    }
}
