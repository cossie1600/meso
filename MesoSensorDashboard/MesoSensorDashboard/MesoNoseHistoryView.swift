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
                        "No History Logs Yet",
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
    
    private let miniGridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Timestamp & Battery Level
            HStack(alignment: .center, spacing: 6) {
                Text(sample.timestamp, style: .time)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color.appPrimaryText)
                
                Spacer()
                
                BatteryIndicatorView(
                    batteryPercentage: sample.battery,
                    fontSize: 11,
                    iconSize: 11
                )
            }
            
            // 2x2 Telemetry Grid
            LazyVGrid(columns: miniGridColumns, spacing: 10) {
                SquareMetricCard(
                    label: "Temp",
                    value: String(format: "%.1f", sample.temp),
                    unit: "°C",
                    size: 80
                )
                
                SquareMetricCard(
                    label: "Humidity",
                    value: String(format: "%.1f", sample.humidity),
                    unit: "%",
                    size: 80
                )
                
                SquareMetricCard(
                    label: "Pressure",
                    value: String(format: "%.1f", sample.pressure),
                    unit: "hPa",
                    size: 80
                )
                
                SquareMetricCard(
                    label: "VOC",
                    value: "\(sample.voc)",
                    unit: "Ω",
                    size: 80
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .glassCardStyle()
    }
}
