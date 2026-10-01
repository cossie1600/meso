//
//  DB_PMSample.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/13/26.
//

import Foundation
import SwiftData

@Model
class DB_PMSample {
    var timestamp: Date
    var pm1: Double
    var pm25: Double
    var pm10: Double
    var battery: Int? // Optional battery percentage (nil = unknown / disconnected)
    
    init(timestamp: Date = Date(), pm1: Double, pm25: Double, pm10: Double, battery: Int? = nil) {
        self.timestamp = timestamp
        self.pm1 = pm1
        self.pm25 = pm25
        self.pm10 = pm10
        self.battery = battery
    }
}
