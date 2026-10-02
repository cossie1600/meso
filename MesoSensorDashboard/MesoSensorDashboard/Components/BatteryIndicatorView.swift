//
//  BatteryIndicatorView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct BatteryIndicatorView: View {
    let batteryPercentage: Int?
    var fontSize: CGFloat = 11
    var iconSize: CGFloat = 11

    init(batteryPercentage: Int?, fontSize: CGFloat = 11, iconSize: CGFloat = 11) {
        self.batteryPercentage = batteryPercentage
        self.fontSize = fontSize
        self.iconSize = iconSize
    }

    private var batteryIconName: String {
        guard let battery = batteryPercentage, battery > 0 else {
            return "battery.slash"
        }
        switch battery {
        case 1...15: return "battery.0"
        case 16...35: return "battery.25"
        case 36...65: return "battery.50"
        case 66...85: return "battery.75"
        default: return "battery.100"
        }
    }

    private var batteryText: String {
        guard let battery = batteryPercentage, battery > 0 else {
            return "--%"
        }
        return "\(battery)%"
    }

    private var batteryColor: Color {
        guard let battery = batteryPercentage, battery > 0 else {
            return Color.appSecondaryText
        }
        return battery <= 20 ? .red : Color.appPrimaryText
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: batteryIconName)
                .font(.system(size: iconSize, weight: .medium))

            Text(batteryText)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
        }
        .foregroundColor(batteryColor)
    }
}
