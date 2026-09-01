//
//  DB_MesoNoseSample.swift
//  MesoSensorDashboard
//

import Foundation
import SwiftData

@Model
class DB_MesoNoseSample {
    var timestamp: Date
    var temp: Double
    var humidity: Double
    var pressure: Double
    var voc: Int
    var breathDropDelta: Double
    var breathMin: Int
    var ptcResult: String
    
    init(
        timestamp: Date = Date(),
        temp: Double,
        humidity: Double,
        pressure: Double = 0.0,
        voc: Int,
        breathDropDelta: Double = 0.0,
        breathMin: Int = 0,
        ptcResult: String = "NONE"
    ) {
        self.timestamp = timestamp
        self.temp = temp
        self.humidity = humidity
        self.pressure = pressure
        self.voc = voc
        self.breathDropDelta = breathDropDelta
        self.breathMin = breathMin
        self.ptcResult = ptcResult
    }
}
