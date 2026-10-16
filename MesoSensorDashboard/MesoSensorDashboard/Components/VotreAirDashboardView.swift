//
//  VotreAirDashboardView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct VotreAirDashboardView: View {
    @ObservedObject var bleManager: BluetoothManager

    @State private var visibleCardCount: Int = UIConstants.initialCardLimit

    private struct UIConstants {
        static let sectionTitle = "YOUR AIR INSIGHTS"
        static let loadMoreButtonText = "Load More Insights"
        static let initialCardLimit: Int = 10
        static let pageSizeIncrement: Int = 10

        static let sectionTitleFontSize: CGFloat = 12.0
        static let loadMoreFontSize: CGFloat = 13.0
        static let buttonHeight: CGFloat = 36.0
        static let buttonCornerRadius: CGFloat = 10.0
        static let outerPadding: CGFloat = 16.0
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

    /// All unique valid historical breath test evaluation samples in memory (sorted latest first)
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

    /// Paginated subset of unique diagnostic result cards currently displayed to the user
    private var visibleBreathSamples: [MesoNoseSample] {
        Array(allBreathSamples.prefix(visibleCardCount))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Bar
                    VotreAirHeaderView(
                        temperatureText: formattedTemperature,
                        humidityText: formattedHumidity,
                        batteryLevel: currentBatteryLevel,
                        batteryIconName: batteryIconName
                    )

                    // Integrated Breath Odor Insight Action Card
                    BreathOdorInsightCard(bleManager: bleManager)

                    // Your Air Insights Section (Paginated SQLite Cards)
                    if !allBreathSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(UIConstants.sectionTitle)
                                .font(.system(size: UIConstants.sectionTitleFontSize, weight: .bold, design: .rounded))
                                .foregroundColor(Color.appSecondaryText)
                                .padding(.horizontal, 4)

                            // Render strictly unique diagnostic result cards (Latest on top)
                            ForEach(visibleBreathSamples, id: \.timestamp) { sample in
                                MesoNoseResultCard(sample: sample)
                            }

                            // Lazy-loading trigger button when more historical records exist in memory
                            if visibleCardCount < allBreathSamples.count {
                                Button(action: {
                                    withAnimation(.smooth) {
                                        visibleCardCount += UIConstants.pageSizeIncrement
                                        bleManager.loadMoreHistoricalData()
                                    }
                                }) {
                                    Text(UIConstants.loadMoreButtonText)
                                        .font(.system(size: UIConstants.loadMoreFontSize, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.appPrimaryText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: UIConstants.buttonHeight)
                                        .background(Color.gray.opacity(0.15))
                                        .cornerRadius(UIConstants.buttonCornerRadius)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(UIConstants.outerPadding)
            }
            .globalAppBackground()
        }
    }
}
