//
//  AirQualityManagerProtocol.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation
import Combine


struct HistoricalReading: Identifiable {
    let id = UUID()
    let timestamp: Date
    let pm1: String
    let pm25: String
    let pm10: String
}

// This forces both classes to provide the exact same variables to the UI
protocol AirQualityManagerProtocol: ObservableObject {
    var statusText: String { get set }
    var pm1Value: String { get set }
    var pm25Value: String { get set }
    var pm10Value: String { get set }
}
