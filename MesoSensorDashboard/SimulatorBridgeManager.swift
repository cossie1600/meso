//
//  SimulatorBridgeManager.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation
import Combine

struct SensorDataPackage: Decodable, Sendable {
    let status: String
    let pm1: String
    let pm25: String
    let pm10: String
}

@MainActor
class SimulatorBridgeManager: AirQualityManagerProtocol {
    @Published var statusText: String = "Connecting to Python Bridge..."
    @Published var pm1Value: String = "--"
    @Published var pm25Value: String = "--"
    @Published var pm10Value: String = "--"
    
    private var networkTimer: Timer?
    
    init() {
        print("🚀 SimulatorBridgeManager Initialized. Starting loop...")
        startPollingPythonBridge()
    }
    
    private func startPollingPythonBridge() {
        networkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                print("📡 Attempting to fetch from Python bridge...")
                guard let url = URL(string: "http://127.0.0.1:8080/data") else {
                    print("❌ Bad URL string Configuration")
                    return
                }
                
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    print("✅ Data payload received! Size: \(data.count) bytes.")
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("ℹ️ HTTP Status Code: \(httpResponse.statusCode)")
                    }
                    
                    let decodedData = try JSONDecoder().decode(SensorDataPackage.self, from: data)
                    print("🎉 JSON Parsed Cleanly: Status message -> \(decodedData.status)")
                    
                    self.statusText = decodedData.status
                    self.pm1Value = decodedData.pm1
                    self.pm25Value = decodedData.pm25
                    self.pm10Value = decodedData.pm10
                } catch {
                    print("❌ Bridge Network Exception Caught: \(error)")
                    self.statusText = "Bridge offline. Is scan.py running?"
                }
            }
        }
    }
}
