//
//  VotreAirHeaderView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct VotreAirHeaderView: View {
    let temperatureText: String
    let humidityText: String
    let batteryLevel: Int
    let batteryIconName: String

    private struct UIConstants {
        static let titleText = "Votre Air"
        static let separatorText = "•"
        
        static let titleFontSize: CGFloat = 26.0
        static let telemetryFontSize: CGFloat = 11.0
        static let emblemSize: CGFloat = 28.0
        
        static let headerVStackSpacing: CGFloat = 2.0
        static let telemetryHStackSpacing: CGFloat = 5.0
        static let minimumScaleFactorRatio: CGFloat = 0.80
        static let singleLineLimit: Int = 1

        static func formattedBatteryText(_ level: Int) -> String {
            "\(level)%"
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: UIConstants.headerVStackSpacing) {
                // Primary Dashboard Title
                Text(UIConstants.titleText)
                    .font(.system(size: UIConstants.titleFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(Color.appPrimaryText)

                // Scaled Single-Line Telemetry Sub-Header Row: Temp • RH • Battery
                HStack(spacing: UIConstants.telemetryHStackSpacing) {
                    Label(temperatureText, systemImage: "thermometer.medium")
                    
                    Text(UIConstants.separatorText)
                        .foregroundColor(Color.appSecondaryText)
                    
                    Label(humidityText, systemImage: "humidity")
                    
                    Text(UIConstants.separatorText)
                        .foregroundColor(Color.appSecondaryText)
                    
                    Label(UIConstants.formattedBatteryText(batteryLevel), systemImage: batteryIconName)
                }
                .font(.system(size: UIConstants.telemetryFontSize, weight: .semibold, design: .rounded))
                .foregroundColor(Color.appSecondaryText)
                .lineLimit(UIConstants.singleLineLimit)
                .minimumScaleFactor(UIConstants.minimumScaleFactorRatio)
            }

            Spacer()

            // Alchemical Air Symbol Brand Emblem Logo
            AlchemicalAirSymbol()
                .frame(width: UIConstants.emblemSize, height: UIConstants.emblemSize)
                .foregroundColor(Color.appPrimaryText)
        }
    }
}
