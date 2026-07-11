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
    @Published var history: [HistoricalReading] = [] // 👈 1. Added property to fulfill protocol
    
    private var networkTimer: Timer?
    
    init() {
        startPollingPythonBridge()
    }
    
    private func startPollingPythonBridge() {
        networkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                guard let url = URL(string: "http://127.0.0.1:8080/data") else { return }
                
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let decodedData = try JSONDecoder().decode(SensorDataPackage.self, from: data)
                    
                    self.statusText = decodedData.status
                    self.pm1Value = decodedData.pm1
                    self.pm25Value = decodedData.pm25
                    self.pm10Value = decodedData.pm10
                    
                    // 👈 2. Log the incoming data packet into the history stream array
                    let newReading = HistoricalReading(
                        timestamp: Date(),
                        pm1: decodedData.pm1,
                        pm25: decodedData.pm25,
                        pm10: decodedData.pm10
                    )
                    self.history.insert(newReading, at: 0)
                    
                } catch {
                    self.statusText = "Bridge offline. Is scan.py running?"
                }
            }
        }
    }
}
