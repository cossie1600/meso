//
//  MesoNoseHistoryView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/8/26.
//

import SwiftUI

struct MesoNoseHistoryView: View {
    @ObservedObject var bleManager: BluetoothManager
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: AppConfig.DashboardUI.metricGridSpacing) {
                if bleManager.mesoNoseSamples.isEmpty {
                    ContentUnavailableView(
                        "No Breath Logs Yet",
                        systemImage: "wind",
                        description: Text("Waiting for data stream...")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(bleManager.mesoNoseSamples) { sample in
                        MesoNoseSampleCard(sample: sample)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        //.navigationTitle("VOC & Humidity History")
    }
}

struct MesoNoseSampleCard: View {
    let sample: MesoNoseSample
    
    private var resultStatus: PtcResult {
        PtcResult(rawValue: sample.ptcResult) ?? .none
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppConfig.DashboardUI.cardSpacing) {
            // Header Row
            HStack {
                Text(sample.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                PtcBadgeView(result: resultStatus)
            }
            
            // Primary Environmental Telemetry
            HStack(spacing: AppConfig.DashboardUI.metricGridSpacing) {
                MetricCell(label: "Temp", value: String(format: AppConfig.DashboardUI.Formats.temp, sample.temp))
                MetricCell(label: "Humidity", value: String(format: AppConfig.DashboardUI.Formats.humidity, sample.humidity))
                MetricCell(label: "Press", value: String(format: AppConfig.DashboardUI.Formats.pressure, sample.pressure))
                MetricCell(label: "VOC", value: String(format: AppConfig.DashboardUI.Formats.gasRes, sample.voc))
            }
            
            // Breath Evaluation Metrics
            if resultStatus.isEvaluated || sample.breathDropDelta > 0 {
                Divider()
                HStack {
                    Text("Breath Drop Delta:")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: AppConfig.DashboardUI.Formats.deltaDrop, sample.breathDropDelta))
                        .font(.footnote)
                        .bold()
                    
                    Spacer()
                    
                    Text("Min VOC: \(String(format: AppConfig.DashboardUI.Formats.gasRes, sample.breathMin))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, AppConfig.DashboardUI.paddingVertical)
    }
}
