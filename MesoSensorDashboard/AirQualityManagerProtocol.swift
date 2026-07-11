//
//  AirQualityManagerProtocol.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation
import Combine

// This forces both classes to provide the exact same variables to the UI
protocol AirQualityManagerProtocol: ObservableObject {
    var statusText: String { get set }
    var pm1Value: String { get set }
    var pm25Value: String { get set }
    var pm10Value: String { get set }
}
