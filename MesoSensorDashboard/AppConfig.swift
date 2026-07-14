//
//  AppConfig.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation

struct AppConfig {
    // this is the control for using real Bluetooth or Mock!!
    static let useMockSimulatorBridge: Bool = false
    
    static let companyName = "ClingGem"
    
    static let bluetoothDeviceName = "Meso Pin"
    static let applogFileName = "MesoSensorDashboard.csv"
    // 🛑 Toggle this to false to completely turn off logging to disk
    static let isLoggingEnabled = false
    
    static let metricPMOne = "PM1.0"
    static let metricPMTwoFive = "PM2.5"
    static let metricPMTen = "PM10.0"
    static let metricUnit = "µg/m³"

    static let checkMockPath: Void = {
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            print("\n-------------------------------------------------------------")
            print("📁 CURRENT RUN LOG PATH:\n\(docs.appendingPathComponent(applogFileName).path)")
            print("-------------------------------------------------------------\n")
        }
    }()
}
