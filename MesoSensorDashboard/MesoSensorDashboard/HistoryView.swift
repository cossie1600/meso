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
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long // Displays "July 13, 2026"
        formatter.timeStyle = .none // No time here
        return formatter
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 12) {
                if let firstReading = bleManager.history.first {
                    HStack {
                        Text(dateFormatter.string(from: firstReading.timestamp).uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(1.5) // Adds nice letter spacing
                            .foregroundStyle(.secondary.opacity(0.7)) // Elegant faded look
                        Spacer()
                    }
                    .padding(.bottom, 4)
                }
                ForEach(bleManager.history) { reading in
                    HistoryCardView(reading: reading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
