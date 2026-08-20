//
//  MesoNoseSample.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/8/26.
//

import Foundation

// MARK: - Global Keys Constant
enum MesoNoseKeys {
    static let rt = "rt"
    static let rh = "rh"
    static let press = "press"
    static let voc = "voc"
    static let breathDropDelta = "breath_drop_delta"
    static let breathMin = "breath_min"
    static let ptcResult = "ptc_result"
    
    // Command & Status Keys
    static let rxCmd = "rx_cmd"
    static let status = "status"
    static let state = "state"

    /// List of key names to identify Meso Nose raw payload strings
    static let allKeys: Set<String> = [
        rt, rh, press, voc, breathDropDelta, breathMin, ptcResult, rxCmd, status, state
    ]
}

// MARK: - Model
struct MesoNoseSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let temp: Double            // "rt" aka relative temperature
    let humidity: Double        // "rh" aka relative humidity
    let pressure: Double        // "press" aka pressure
    let voc: Int                // "voc"
    let breathDropDelta: Double // "breath_drop_delta"
    let breathMin: Int          // "breath_min"
    let ptcResult: String       // "ptc_result"

    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        self.id = UUID()
        self.timestamp = Date()
        
        self.temp = MesoNoseSample.extractDouble(dict[MesoNoseKeys.rt])
        self.humidity = MesoNoseSample.extractDouble(dict[MesoNoseKeys.rh])
        self.pressure = MesoNoseSample.extractDouble(dict[MesoNoseKeys.press])
        self.voc = MesoNoseSample.extractInt(dict[MesoNoseKeys.voc])
        self.breathDropDelta = MesoNoseSample.extractDouble(dict[MesoNoseKeys.breathDropDelta])
        self.breathMin = MesoNoseSample.extractInt(dict[MesoNoseKeys.breathMin])
        self.ptcResult = dict[MesoNoseKeys.ptcResult] as? String ?? "NONE"
    }

    private static func extractDouble(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String, let parsed = Double(s) { return parsed }
        return 0.0
    }

    private static func extractInt(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String, let parsed = Int(s) { return parsed }
        return 0
    }
}
