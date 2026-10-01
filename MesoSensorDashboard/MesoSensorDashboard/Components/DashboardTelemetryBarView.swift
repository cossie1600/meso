//
//  DashboardTelemetryBarView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/1/26.
//

import SwiftUI

struct DashboardTelemetryBarView: View {
    let tempC: Double
    let humidity: Double
    let pm25String: String
    
    /// Converts Celsius to Fahrenheit
    private var tempInFahrenheit: Double {
        (tempC * 9.0 / 5.0) + 32.0
    }
    
    /// Maps PM2.5 readings to standard AQI Level of Concern categories
    private var aqiLevelOfConcern: String {
        guard let pm25 = Double(pm25String) else {
            return "Good"
        }
        
        switch pm25 {
        case 0.0...12.0:
            return "Good"
        case 12.1...35.4:
            return "Moderate"
        case 35.5...55.4:
            return "Unhealthy for Sensitive Groups"
        case 55.5...150.4:
            return "Unhealthy"
        case 150.5...250.4:
            return "Very Unhealthy"
        default:
            return "Hazardous"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Temperature in Fahrenheit
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 11, weight: .medium))
                Text(String(format: "%.1f°F", tempInFahrenheit))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            
            Text("•")
                .font(.system(size: 10))
                .foregroundColor(Color.appSecondaryText)
            
            // Relative Humidity
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 11, weight: .medium))
                Text(String(format: "%.0f%% RH", humidity))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            
            Text("•")
                .font(.system(size: 10))
                .foregroundColor(Color.appSecondaryText)
            
            // AQI Level of Concern (No Raw Numbers)
            HStack(spacing: 4) {
                Image(systemName: "aqi.medium")
                    .font(.system(size: 11, weight: .medium))
                Text(aqiLevelOfConcern)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            
            Spacer(minLength: 0)
        }
        .foregroundColor(Color.appPrimaryText)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
