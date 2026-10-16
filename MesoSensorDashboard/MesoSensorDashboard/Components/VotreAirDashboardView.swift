//
//  VotreAirDashboardView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct VotreAirDashboardView: View {
    @ObservedObject var bleManager: BluetoothManager

    @State private var visibleCardCount: Int = UIConstants.initialCardLimit
    @State private var highlightedSampleID: Date? = nil

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

    /// All unique valid historical breath test evaluation samples in memory
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

    /// Paginated subset of unique diagnostic result cards currently displayed
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

                    // Integrated Breath Odor Insight Action Card (Without status row)
                    BreathOdorInsightCard(bleManager: bleManager)

                    // Your Air Insights Section
                    if !allBreathSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(UIConstants.sectionTitle)
                                .font(.system(size: UIConstants.sectionTitleFontSize, weight: .bold, design: .rounded))
                                .foregroundColor(Color.appSecondaryText)
                                .padding(.horizontal, 4)

                            // Render unique diagnostic cards
                            ForEach(visibleBreathSamples, id: \.timestamp) { sample in
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

                            // Lazy-loading pagination button
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
            .onChange(of: bleManager.breathTestState) { _, newState in
                if newState == .completed, let newestSample = allBreathSamples.first {
                    // Highlight the brand new result card for exactly 3 seconds
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
