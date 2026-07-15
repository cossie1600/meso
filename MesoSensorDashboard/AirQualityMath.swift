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
        let nonNegativeValues = values.filter { $0 >= 0.0 }
        guard !values.isEmpty && !nonNegativeValues.isEmpty else { return 0.0 }
        
        // 1. Find the Median (The middle value when sorted)
        let sortedValues = values.sorted()
        let medianBaseline = sortedValues[sortedValues.count / 2]
        
        // 2. Discard sudden spikes relative to our rock-solid median
        let cleanValues = values.filter { value in
            let absoluteDelta = value - medianBaseline
            let isSuddenSpike = absoluteDelta > anomalyAbsoluteThreshold && value > (medianBaseline * anomalyMultiplierThreshold)
            
            return !isSuddenSpike
        }
        
        // 3. Compute final clean average
        let cleanSum = cleanValues.reduce(0, +)
        return cleanValues.isEmpty ? 0.0 : (cleanSum / Double(cleanValues.count))
    }
}
