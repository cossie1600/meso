//
//  MesoNoseSample.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/8/26.
//

import Foundation

struct MesoNoseSample: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let temp: Double          // "rt" aka relative temperature
    let humidity: Double      // "rh" aka relative humidity
    let pressure: Double      // "press" aka pressure
    let voc: Int             // "voc"
    let breathDropDelta: Double // "breath_drop_delta"
    let breathMin: Int       // "breath_min"
    let ptcResult: String    // "ptc_result"

    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        self.id = UUID()
        self.timestamp = Date()
        self.temp = dict["rt"] as? Double ?? 0.0
        self.humidity = dict["rh"] as? Double ?? 0.0
        self.pressure = dict["press"] as? Double ?? 0.0
        self.voc = dict["voc"] as? Int ?? 0
        self.breathDropDelta = dict["breath_drop_delta"] as? Double ?? 0.0
        self.breathMin = dict["breath_min"] as? Int ?? 0
        self.ptcResult = dict["ptc_result"] as? String ?? "NONE"
    }
}
