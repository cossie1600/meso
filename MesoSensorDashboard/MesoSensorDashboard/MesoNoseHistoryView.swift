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
    
    private var batteryIconName: String {
        guard let battery = sample.battery else { return "battery.slash" }
        switch battery {
        case 0...15: return "battery.0"
        case 16...35: return "battery.25"
        case 36...65: return "battery.50"
        case 66...85: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private var batteryText: String {
        if let battery = sample.battery { return "\(battery)%" }
        return "--%"
    }
    
    private var batteryColor: Color {
        guard let battery = sample.battery else { return Color.appSecondaryText }
        return battery <= 20 ? .red : Color.appSecondaryText
    }
    
    private let miniGridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .center, spacing: 6) {
                Text(sample.timestamp, style: .time)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color.appPrimaryText)
                
                HStack(spacing: 3) {
                    Image(systemName: batteryIconName)
                        .font(.caption2)
                    Text(batteryText)
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(batteryColor)
                .padding(.leading, 4)

                Spacer()
                
                PtcBadgeView(result: resultStatus)
            }
            
            // 2x2 Grid using the global SquareMetricCard from SquareMetricCard.swift
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
            
            // Breath Evaluation Footer Row
            if resultStatus.isEvaluated || sample.breathDropDelta > 0 {
                Divider()
                    .padding(.vertical, 2)
                
                HStack {
                    Text("Breath Drop Delta:")
                        .font(.caption)
                        .foregroundColor(Color.appSecondaryText)
                    
                    Text(String(format: AppConfig.DashboardUI.Formats.deltaDrop, sample.breathDropDelta))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color.appPrimaryText)
                    
                    Spacer()
                    
                    Text("Min VOC: \(String(format: AppConfig.DashboardUI.Formats.gasRes, sample.breathMin))")
                        .font(.caption)
                        .foregroundColor(Color.appSecondaryText)
                }
            }
        }
        .padding(14)
        .glassCardStyle()
    }
}
