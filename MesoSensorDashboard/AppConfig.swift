//
//  AppConfig.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation
import SwiftUI

struct AppConfig {
    // 🎛️ Environment-Specific Toggles
    static let useMockSimulatorBridge: Bool = false
    static let forceInitialEmergencyState: Bool = false
    static let simulatorSpeedSec: TimeInterval = 5.0
    enum MockFormat { case csv, json }
    static let activeMockFormat: MockFormat = .json
    
    // 📡 BLE Hardware Identification
    // Meso Pin (BMV080 Air Quality)
    static let firmwareServiceUUIDString: String = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
    static let bluetoothDeviceName = "Meso Pin"

    // Meso Nose (BME688 Breath/Gas)
    static let mesoNoseServiceUUIDString: String = "4FA215F0-0001-4B0E-B682-1A4C70F3A601"
    static let mesoNoseCharacteristicUUIDString: String = "4FA215F0-0002-4B0E-B682-1A4C70F3A601"
    static let mesoNoseBluetoothName = "Meso Nose"
    
    // app info
    static let companyName = "ClingGem"
    
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
    
    // 🎨 Shared Dashboard UI Tokens & Formatting
    enum DashboardUI {
        // Layout Spacing & Radius
        static let cardSpacing: CGFloat = 8
        static let metricGridSpacing: CGFloat = 12
        static let paddingVertical: CGFloat = 4
        static let badgePaddingHorizontal: CGFloat = 8
        static let badgePaddingVertical: CGFloat = 4
        static let badgeCornerRadius: CGFloat = 6
        static let backgroundOpacity: Double = 0.2
        
        // Formatter Specifiers
        enum Formats {
            static let temp = "%.1f°C"
            static let humidity = "%.1f%%"
            static let pressure = "%.1f hPa"
            static let gasRes = "%d Ω"
            static let deltaDrop = "%.1f%%"
            static let pm = "%.1f µg/m³"
        }
    }
    // 🔑 BME688 JSON Payload Discriminators
    enum MesoNoseKeys {
        static let temp = "\"rt\""
        static let voc = "\"voc\""
        static let ptcResult = "\"ptc_result\""
            
        static var allDiscriminators: [String] {
            [temp, voc, ptcResult]
        }
    }
    
    enum MesoNoseCommand: String {
        case startActiveSampling = "run"
        case stopSampling = "stop"
        case triggerBreathTest = "breath"
        case setUltraLowSamplingMode = "set_ultra_low_sampling_mode"
        case setActiveSamplingMode = "set_active_sampling_mode"
            
        var payload: String { rawValue }

        var description: String {
            switch self {
            case .startActiveSampling: return "Start Active Sampling (3s)"
            case .stopSampling: return "Stop Sampling (Heater Off)"
            case .triggerBreathTest: return "Trigger Active Breath Evaluation"
            case .setUltraLowSamplingMode: return "Set Ultra Low Sampling Mode (every 5 min)"
            case .setActiveSamplingMode: return "Set Active Sampling Mode (every 3 sec)"
            }
        }
    }
    
    static let checkMockPath: Void = {
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            print("\n-------------------------------------------------------------")
            print("📁 CURRENT RUN LOG PATH:\n\(docs.appendingPathComponent(applogFileName).path)")
            print("-------------------------------------------------------------\n")
        }
    }()
}
