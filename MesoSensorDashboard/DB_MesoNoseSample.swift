//
//  DB_MesoNoseSample.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/15/26.
//

import Foundation
import SwiftData

@Model
class DB_MesoNoseSample {
    var timestamp: Date
    var temp: Double
    var humidity: Double
    var voc: Int
    var breathDropDelta: Double
    var breathMin: Int
    var ptcResult: String
    
    init(
        timestamp: Date = Date(),
        temp: Double,
        humidity: Double,
        voc: Int,
        breathDropDelta: Double = 0.0,
        breathMin: Int = 0,
        ptcResult: String = "NONE"
    ) {
        self.timestamp = timestamp
        self.temp = temp
        self.humidity = humidity
        self.voc = voc
        self.breathDropDelta = breathDropDelta
        self.breathMin = breathMin
        self.ptcResult = ptcResult
    }
}
