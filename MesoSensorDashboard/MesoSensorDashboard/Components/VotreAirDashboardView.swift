//
//  VotreAirDashboardView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct VotreAirDashboardView: View {
    @ObservedObject var bleManager: BluetoothManager
    @State private var highlightedSampleID: Date? = nil

    private struct UIConstants {
        static let sectionTitle = "YOUR AIR INSIGHTS"
        static let seeAllText = "See All"
        static let dashboardCardLimit: Int = 3

        static let sectionTitleFontSize: CGFloat = 12.0
        static let seeAllFontSize: CGFloat = 13.0
        
        static let mainVStackSpacing: CGFloat = 20.0
        static let cardsVStackSpacing: CGFloat = 14.0
        static let sectionVStackSpacing: CGFloat = 12.0
        
        static let outerPadding: CGFloat = 16.0
        static let bottomScrollViewPadding: CGFloat = 24.0
        
        static let newResultHighlightDuration: Double = 3.0
    }

    private var latestSample: MesoNoseSample? {
        bleManager.mesoNoseSamples.first
    }

    private var formattedTemperature: String {
        if let temp = latestSample?.temp, temp > MesoNoseConstants.zeroDouble {
            return String(format: "%.1f°C", temp)
        }
        return "--°C"
    }

    private var formattedHumidity: String {
        if let rh = latestSample?.humidity, rh > MesoNoseConstants.zeroDouble {
            return String(format: "%.1f%% RH", rh)
        }
        return "--% RH"
    }

    private var currentBatteryLevel: Int {
        if let liveBattery = bleManager.mesoNoseBattery {
            return liveBattery
        }
        return latestSample?.battery ?? 100
    }

    private var batteryIconName: String {
        switch currentBatteryLevel {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        default: return "battery.25"
        }
    }
    
    private var batteryState: BatteryDisplayState {
        guard bleManager.isConnected else {
            return .unknown
        }

        // Use live telemetry percentage if available, otherwise check stored samples
        let rawBattery = bleManager.mesoNoseBattery ?? latestSample?.battery

        guard let battery = rawBattery else {
            return .unknown
        }

        // 0% when plugged into USB indicates a floating or unpopulated cell terminal (0.63V bias)
        if battery == MesoNoseConstants.zeroInt && !bleManager.hasReceivedLiveTelemetry {
            return .externalPower
        }

        return .battery(level: battery)
    }

    private var allBreathSamples: [MesoNoseSample] {
        var uniqueSamples: [MesoNoseSample] = []

        for sample in bleManager.mesoNoseSamples where sample.breathDropDelta > MesoNoseConstants.zeroDouble {
            let isDuplicate = uniqueSamples.contains { existing in
                existing.voc == sample.voc &&
                existing.breathDropDelta == sample.breathDropDelta &&
                existing.ptcResult == sample.ptcResult
            }

            if !isDuplicate {
                uniqueSamples.append(sample)
            }
        }

        return uniqueSamples
    }

    private var recentBreathSamples: [MesoNoseSample] {
        Array(allBreathSamples.prefix(UIConstants.dashboardCardLimit))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UIConstants.mainVStackSpacing) {
                    // Header Bar with Top-Right Settings Gear Link
                    VotreAirHeaderView(
                        temperatureText: formattedTemperature,
                        humidityText: formattedHumidity,
                        batteryText: batteryState.text,
                        batteryIconName: batteryState.iconName,
                        batteryColor: batteryState.iconColor
                    )

                    // Translucent Action Card
                    BreathOdorInsightCard(bleManager: bleManager)

                    Spacer(minLength: 20)

                    // Your Air Insights Section
                    if !allBreathSamples.isEmpty {
                        VStack(alignment: .leading, spacing: UIConstants.sectionVStackSpacing) {
                            // Section Header with "See All"
                            HStack {
                                Text(UIConstants.sectionTitle)
                                    .font(.system(size: UIConstants.sectionTitleFontSize, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.appSecondaryText)

                                Spacer()

                                NavigationLink(destination: AirQualityHistoryView(bleManager: bleManager)) {
                                    Text(UIConstants.seeAllText)
                                        .font(.system(size: UIConstants.seeAllFontSize, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.appPrimaryText)
                                }
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: UIConstants.cardsVStackSpacing) {
                                ForEach(recentBreathSamples, id: \.timestamp) { sample in
                                    let isNewResult = (sample.timestamp == highlightedSampleID)
                                    
                                    MesoNoseResultCard(sample: sample)
                                        .scaleEffect(isNewResult ? 1.03 : 1.0)
                                        .shadow(color: isNewResult ? Color.green.opacity(0.40) : Color.clear, radius: 8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(isNewResult ? Color.green : Color.clear, lineWidth: 2)
                                        )
                                        .animation(.easeInOut(duration: 0.4), value: isNewResult)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, UIConstants.outerPadding)
                .padding(.top, UIConstants.outerPadding)
                .padding(.bottom, UIConstants.bottomScrollViewPadding)
            }
            .globalAppBackground()
            .onChange(of: bleManager.breathTestState) { _, newState in
                if newState == .completed, let newestSample = allBreathSamples.first {
                    withAnimation {
                        highlightedSampleID = newestSample.timestamp
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + UIConstants.newResultHighlightDuration) {
                        withAnimation {
                            highlightedSampleID = nil
                        }
                    }
                }
            }
        }
    }
}
// MARK: - Battery Presentation State
enum BatteryDisplayState {
    case battery(level: Int)
    case externalPower
    case unknown

    var text: String {
        switch self {
        case .battery(let level):
            return "\(level)%"
        case .externalPower:
            return "USB"
        case .unknown:
            return "--%"
        }
    }

    var iconName: String {
        switch self {
        case .externalPower:
            return "bolt.fill"
        case .unknown:
            return "battery.slash"
        case .battery(let level):
            switch level {
            case 75...100: return "battery.100"
            case 50..<75:  return "battery.75"
            case 25..<50:  return "battery.50"
            default:       return "battery.25"
            }
        }
    }

    var iconColor: Color {
        switch self {
        case .externalPower:
            return Color.yellow
        case .unknown:
            return Color.appSecondaryText
        case .battery(let level):
            if level <= 15 {
                return Color.red
            } else if level <= 30 {
                return Color.orange
            }
            return Color.appSecondaryText
        }
    }
}
