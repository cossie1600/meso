//
//  DashboardTelemetryBarView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct DashboardTelemetryBarView: View {
    let isMesoNoseConnected: Bool
    let isPMConnected: Bool
    let tempC: Double?
    let humidity: Double?
    let mesoNoseBattery: Int?
    let mesoPinBattery: Int?
    let pm1Value: String
    let pm25Value: String
    let pm10Value: String
    
    private var tempText: String {
        guard let temp = tempC else { return "__°F" }
        let tempInFahrenheit = (temp * 9.0 / 5.0) + 32.0
        return String(format: "%.1f°F", tempInFahrenheit)
    }
    
    private var humidityText: String {
        guard let rh = humidity else { return "__% RH" }
        return String(format: "%.0f%% RH", rh)
    }
    
    private var particulateSummaryText: String {
        guard let pm25 = Double(pm25Value), !pm25Value.isEmpty else { return "PM --" }
        return "PM2.5: \(pm25Value)"
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if !isMesoNoseConnected && !isPMConnected {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 11, weight: .medium))
                    Text("No Sensors Connected")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color.appSecondaryText)
            } else {
                // 1. Microclimate Telemetry (Meso Nose)
                if isMesoNoseConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 11, weight: .medium))
                        Text(tempText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(Color.appSecondaryText)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text(humidityText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(Color.appSecondaryText)
                    
                    BatteryIndicatorView(
                        batteryPercentage: mesoNoseBattery,
                        fontSize: 12,
                        iconSize: 11
                    )
                }
                
                if isMesoNoseConnected && isPMConnected {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(Color.appSecondaryText)
                }
                
                // 2. Particulate Telemetry (Meso Pin)
                if isPMConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "aqi.medium")
                            .font(.system(size: 11, weight: .medium))
                        Text(particulateSummaryText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(Color.appSecondaryText)

                    BatteryIndicatorView(
                        batteryPercentage: mesoPinBattery,
                        fontSize: 12,
                        iconSize: 11
                    )
                }
            }
            
            Spacer(minLength: 0)
        }
        .foregroundColor(Color.appPrimaryText)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
