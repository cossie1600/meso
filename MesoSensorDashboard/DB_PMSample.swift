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
    
    init(timestamp: Date, pm1: Double, pm25: Double, pm10: Double) {
        self.timestamp = timestamp
        self.pm1 = pm1
        self.pm25 = pm25
        self.pm10 = pm10
    }
}
