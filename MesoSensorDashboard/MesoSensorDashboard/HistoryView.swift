//
//  HistoryView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//
import SwiftUI
import Combine

struct HistoryView: View {
    @ObservedObject var bleManager: DynamicAirQualityManager
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .short
        return formatter
    }
    
    var body: some View {
        // 📜 The ScrollView must be explicitly told to fill its parent TabView container
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 12) {
                ForEach(bleManager.history) { reading in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(timeFormatter.string(from: reading.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("Status: Streaming Normal")
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            MetricBadge(label: AppConfig.metricPMOne, value: reading.pm1)
                            MetricBadge(label: AppConfig.metricPMTwoFive, value: reading.pm25)
                            MetricBadge(label: AppConfig.metricPMTen, value: reading.pm10)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            // 📐 Ensure the inner stack expands sideways to catch gestures perfectly
            .frame(maxWidth: .infinity)
        }
        // 🚀 THE FIX: Forces the ScrollView to balloon up and claim every pixel of vertical screen space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
