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
        
        static let emblemSize: CGFloat = 35.0

        static let headerVStackSpacing: CGFloat = 6.0
        static let titleHStackSpacing: CGFloat = 8.0
        static let telemetryHStackSpacing: CGFloat = 5.0
        static let minimumScaleFactorRatio: CGFloat = 0.80
        static let singleLineLimit: Int = 1

        static func formattedBatteryText(_ level: Int) -> String {
            "\(level)%"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.headerVStackSpacing) {
            // Title Row: [Icon] + [Votre Air] + [Spacer] + [Settings Icon]
            HStack(alignment: .center, spacing: UIConstants.titleHStackSpacing) {
                // Alchemist A Emblem on Left Side of Title
                Image("alchemistA")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: UIConstants.emblemSize,
                        height: UIConstants.emblemSize
                    )

                Text(UIConstants.titleText)
                    .font(
                        .system(
                            size: UIConstants.titleFontSize,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundColor(Color.appPrimaryText)

                Spacer()

                // Top-Right Settings Gear Link
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.appPrimaryText)
                }
            }

            // Full-Width Telemetry Sub-Header Row: Temp • RH • Battery
            HStack(spacing: UIConstants.telemetryHStackSpacing) {
                Label(temperatureText, systemImage: "thermometer.medium")

                Text(UIConstants.separatorText)
                    .foregroundColor(Color.appSecondaryText)

                Label(humidityText, systemImage: "humidity")

                Text(UIConstants.separatorText)
                    .foregroundColor(Color.appSecondaryText)

                Label(
                    UIConstants.formattedBatteryText(batteryLevel),
                    systemImage: batteryIconName
                )
            }
            .font(
                .system(
                    size: UIConstants.telemetryFontSize,
                    weight: .semibold,
                    design: .rounded
                )
            )
            .foregroundColor(Color.appSecondaryText)
            .lineLimit(UIConstants.singleLineLimit)
            .minimumScaleFactor(UIConstants.minimumScaleFactorRatio)
        }
    }
}
