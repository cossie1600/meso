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
                            MetricBadge(label: "PM1", value: reading.pm1)
                            MetricBadge(label: "PM2.5", value: reading.pm25)
                            MetricBadge(label: "PM10", value: reading.pm10)
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

// Simple layout helper for the mini rows
struct MetricBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack {
            Text(label).font(.caption2).bold().foregroundStyle(.secondary)
            Text(value).font(.footnote).monospacedDigit()
        }
        .frame(minWidth: 45)
        .padding(6)

        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}
