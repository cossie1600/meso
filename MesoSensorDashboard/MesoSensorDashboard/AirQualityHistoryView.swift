//
//  AirQualityHistoryView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct AirQualityHistoryView: View {
    @ObservedObject var bleManager: BluetoothManager

    /// All unique valid historical breath test evaluation samples
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

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if allBreathSamples.isEmpty {
                    VStack(spacing: 8) {
                        Text("No Insights Recorded Yet")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.appPrimaryText)
                        
                        Text("Take a breath test to start building your history.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Color.appSecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(allBreathSamples, id: \.timestamp) { sample in
                        MesoNoseResultCard(sample: sample)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("All Insights")
        .navigationBarTitleDisplayMode(.inline)
        .globalAppBackground()
    }
}
