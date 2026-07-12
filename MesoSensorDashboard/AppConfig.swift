//
//  AppConfig.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation

struct AppConfig {
    static let companyName = "ClingGem"
    
    static let bluetoothDeviceName = "Meso Pin"
    static let applogFileName = "MesoSensorDashboard.csv"
    
    static let useMockSimulatorBridge: Bool = true
    static let metricPMOne = "PM1.0"
    static let metricPMTwoFive = "PM2.5"
    static let metricPMTen = "PM10.0"
    static let metricUnit = "µg/m³"

    static let checkMockPath: Void = {
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            print("\n-------------------------------------------------------------")
            print("📁 CURRENT RUN LOG PATH:\n\(docs.appendingPathComponent("air_quality_log.csv").path)")
            print("-------------------------------------------------------------\n")
        }
    }()
}
