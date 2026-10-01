//
//  AirQualityHistoryView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import SwiftUI
import SwiftData

struct AirQualityHistoryView: View {
    @ObservedObject var bleManager: BluetoothManager
    
    @Query(sort: \DB_PMSample.timestamp, order: .reverse)
    private var databaseHistory: [DB_PMSample]
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: AppConfig.DashboardUI.metricGridSpacing) {
                if databaseHistory.isEmpty {
                    ContentUnavailableView(
                        "No Particulate Logs Yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Waiting for data stream...")
                    )
                    .padding(.top, 40)
                } else {
                    if let firstReading = databaseHistory.first {
                        HStack {
                            Text(dateFormatter.string(from: firstReading.timestamp).uppercased())
                                .font(.caption)
                                .fontWeight(.bold)
                                .tracking(1.5)
                                .foregroundStyle(.secondary.opacity(0.7))
                            Spacer()
                        }
                        .padding(.bottom, AppConfig.DashboardUI.paddingVertical)
                    }
                    
                    ForEach(databaseHistory) { reading in
                        AirQualitySampleCard(reading: reading)
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

// MARK: - Air Quality History Card Row with Battery Indicator
struct AirQualitySampleCard: View {
    let reading: DB_PMSample
    
    private var batteryIconName: String {
        guard let battery = reading.battery else { return "battery.slash" }
        switch battery {
        case 0...15: return "battery.0"
        case 16...35: return "battery.25"
        case 36...65: return "battery.50"
        case 66...85: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private var batteryText: String {
        if let battery = reading.battery { return "\(battery)%" }
        return "--%"
    }
    
    private var batteryColor: Color {
        guard let battery = reading.battery else { return Color.appSecondaryText }
        return battery <= 20 ? .red : Color.appSecondaryText
    }
    
    private let pmGridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Timestamp & Battery Status
            HStack(alignment: .center, spacing: 6) {
                Text(reading.timestamp, style: .time)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color.appPrimaryText)
                
                // Battery Indicator for Particulate Sensor
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
            }
            
            // 3-Column Grid using 80x80 SquareMetricCard with PM Vector Icons
            LazyVGrid(columns: pmGridColumns, spacing: 8) {
                SquareMetricCard(
                    label: "PM1.0",
                    value: String(format: "%.1f", reading.pm1),
                    unit: "µg/m³",
                    pmType: .pm1_0,
                    size: 80
                )
                
                SquareMetricCard(
                    label: "PM2.5",
                    value: String(format: "%.1f", reading.pm25),
                    unit: "µg/m³",
                    pmType: .pm2_5,
                    size: 80
                )
                
                SquareMetricCard(
                    label: "PM10",
                    value: String(format: "%.1f", reading.pm10),
                    unit: "µg/m³",
                    pmType: .pm10,
                    size: 80
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .glassCardStyle()
    }
}
