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
        .globalAppBackground()
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
                    .fontWeight(.bold)
                    .foregroundColor(Color.appPrimaryText)
                Spacer()
                PtcBadgeView(result: resultStatus)
            }
            
            // Primary Environmental Telemetry Row
            HStack(spacing: AppConfig.DashboardUI.metricGridSpacing) {
                VStack(spacing: 2) {
                    Text("Temp")
                        .font(.caption2)
                        .foregroundColor(Color.appSecondaryText)
                    Text(String(format: AppConfig.DashboardUI.Formats.temp, sample.temp))
                        .font(.footnote)
                        .fontWeight(.bold)
                        .foregroundColor(Color.appPrimaryText)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 2) {
                    Text("Humidity")
                        .font(.caption2)
                        .foregroundColor(Color.appSecondaryText)
                    Text(String(format: AppConfig.DashboardUI.Formats.humidity, sample.humidity))
                        .font(.footnote)
                        .fontWeight(.bold)
                        .foregroundColor(Color.appPrimaryText)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 2) {
                    Text("Press")
                        .font(.caption2)
                        .foregroundColor(Color.appSecondaryText)
                    Text(String(format: AppConfig.DashboardUI.Formats.pressure, sample.pressure))
                        .font(.footnote)
                        .fontWeight(.bold)
                        .foregroundColor(Color.appPrimaryText)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 2) {
                    Text("VOC")
                        .font(.caption2)
                        .foregroundColor(Color.appSecondaryText)
                    Text(String(format: AppConfig.DashboardUI.Formats.gasRes, sample.voc))
                        .font(.footnote)
                        .fontWeight(.bold)
                        .foregroundColor(Color.appPrimaryText)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Breath Evaluation Metrics
            if resultStatus.isEvaluated || sample.breathDropDelta > 0 {
                Divider()
                HStack {
                    Text("Breath Drop Delta:")
                        .font(.footnote)
                        .foregroundColor(Color.appSecondaryText)
                    
                    Text(String(format: AppConfig.DashboardUI.Formats.deltaDrop, sample.breathDropDelta))
                        .font(.footnote)
                        .bold()
                        .foregroundColor(Color.appPrimaryText)
                    
                    Spacer()
                    
                    Text("Min VOC: \(String(format: AppConfig.DashboardUI.Formats.gasRes, sample.breathMin))")
                        .font(.footnote)
                        .foregroundColor(Color.appSecondaryText)
                }
            }
        }
        .padding(14)
        .glassCardStyle()
    }
}
