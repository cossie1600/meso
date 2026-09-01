//
//  AirQualityMath.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/13/26.
//

import Foundation

struct AirQualityMath {
    
        private static let secondsInAnHour: TimeInterval = 3600.0
        
        //Require a massive jump of 100 units to even consider it an anomaly
        private static let anomalyAbsoluteThreshold: Double = 100.0
        
        // The spike must be 5x higher than the ambient median
        private static let anomalyMultiplierThreshold: Double = 5.0
        
    
    /// Filters a list of samples to a specific time window, removes anomaly spikes, and returns the averages.
    static func calculateCleanAverage(from samples: [DB_PMSample], pastHours: TimeInterval = 1) -> (pm1: Double, pm25: Double, pm10: Double) {
        let timeWindowAgo = Date().addingTimeInterval(-(pastHours * secondsInAnHour))
        
        // 1. Filter local data to just the requested time window
        let filteredSamples = samples.filter { $0.timestamp >= timeWindowAgo }
        guard !filteredSamples.isEmpty else { return (0.0, 0.0, 0.0) }
        
        // 2. Extract channels
        let pm1Values = filteredSamples.map { $0.pm1 }
        let pm25Values = filteredSamples.map { $0.pm25 }
        let pm10Values = filteredSamples.map { $0.pm10 }
        
        // 3. Clean out anomalies and return as a tuple
        return (
            pm1: filterOutliersAndAverage(pm1Values),
            pm25: filterOutliersAndAverage(pm25Values),
            pm10: filterOutliersAndAverage(pm10Values)
        )
    }
    
    private static func filterOutliersAndAverage(_ values: [Double]) -> Double {
        // 1. Filter out invalid negative values first
        let cleanInput = values.filter { $0 >= 0.0 }
        guard !cleanInput.isEmpty else { return 0.0 }
        
        // 2. Safely compute the Median
        let sortedValues = cleanInput.sorted()
        let medianBaseline = sortedValues[sortedValues.count / 2]
        
        // 3. Discard sudden spikes relative to median
        let cleanValues = cleanInput.filter { value in
            let absoluteDelta = value - medianBaseline
            let isSuddenSpike = absoluteDelta > anomalyAbsoluteThreshold && value > (medianBaseline * anomalyMultiplierThreshold)
            return !isSuddenSpike
        }
        
        // 4. Safely check for empty array before performing division
        guard !cleanValues.isEmpty else { return 0.0 }
        
        let cleanSum = cleanValues.reduce(0, +)
        return cleanSum / Double(cleanValues.count)
    }
}
