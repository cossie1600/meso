//
//  BluetoothManager+Mock.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/14/26.
//

import Foundation

extension BluetoothManager {
    
    func startMockDataStream() {
        var timeTick = 0
        
        mockDataTimer?.invalidate()
        mockDataTimer = Timer.scheduledTimer(withTimeInterval: AppConfig.simulatorSpeedSec, repeats: true) { [weak self] _ in
            timeTick += 1
            
            // 1. Generate base raw data points based on weather states
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
            
            // 2. Route data execution layout depending on your AppConfig choice
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
            
            // 3. Forward the dynamically verified packet down the operational pipeline
            if let packet = parsedPacket {
                DispatchQueue.main.async {
                    self?.saveToSQLite(packet)
                    self?.updateLiveState(with: packet)
                    self?.evaluateAirQualityThresholds(for: packet)
                }
            }
        }
    }
}
