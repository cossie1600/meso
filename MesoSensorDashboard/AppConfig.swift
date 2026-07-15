//
//  AppConfig.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation

struct AppConfig {
    // 🎛️ Environment-Specific Toggles
#if DEBUG
    // 🧪 Testing Environment Settings
    static let useMockSimulatorBridge: Bool = true  // Set to false when you want to test real hardware locally
    static let forceInitialEmergencyState: Bool = false // Toggle true to force-test emergency states instantly
    static let simulatorSpeedSec: TimeInterval = 5.0
    enum MockFormat { case csv, json }
    static let activeMockFormat: MockFormat = .json
#else
    // 🚀 Production Environment Settings (Hard locked, safe from accidental changes)
    //    static let useMockSimulatorBridge: Bool = false
    //    static let forceInitialEmergencyState: Bool = false
    //    static let simulatorSpeedSec: TimeInterval = 5.0
#endif
    
    // app info
    static let companyName = "ClingGem"
    static let bluetoothDeviceName = "Meso Sensor"
    
    
    // 🧹 Database Cleanup Policy
    static let databaseRetentionDays: Int = 30
    
    // 🚨 Logging Properties
    static let isLoggingEnabled: Bool = true
    static let applogFileName: String = "meso_sensor_log.txt"
    
    // 🎯 Set your limit in clean, human-readable Megabytes!
    static let maxLogSizeInMB: Int = 5
    
    // ⚙️ Calculated helper that converts your MB choice into raw bytes for the system
    static var maxLogSizeInBytes: Int64 {
        return Int64(maxLogSizeInMB) * 1024 * 1024
    }
    
    // Reading constants
    static let metricPMOne = "PM1.0"
    static let metricPMTwoFive = "PM2.5"
    static let metricPMTen = "PM10.0"
    static let metricUnit = "µg/m³"
    
    // 🚨 Air Quality Spike Thresholds
    static let pm25AlertThreshold: Double = 35.0
    static let pm10AlertThreshold: Double = 75.0
    
    static let coarseParticleAlertThreshold: Double = 0.70
    static let ultraFineParticleAlertThreshold: Double = 5.0
    
    
    static let checkMockPath: Void = {
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            print("\n-------------------------------------------------------------")
            print("📁 CURRENT RUN LOG PATH:\n\(docs.appendingPathComponent(applogFileName).path)")
            print("-------------------------------------------------------------\n")
        }
    }()
}
