//
//  HistoryCardView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/13/26.
//

import SwiftUI

struct HistoryCardView: View {
    let reading: HistoricalReading
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 🕐 Top Row: Just the Timestamp
            HStack {
                Text(timeFormatter.string(from: reading.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                
                Spacer(minLength: 8)
            }
            
            //  Bottom Row: The Three Badges auto-scaled and distributed evenly
            HStack(spacing: 8) {
                MetricBadge(label: AppConfig.metricPMOne, value: reading.pm1)
                MetricBadge(label: AppConfig.metricPMTwoFive, value: reading.pm25)
                MetricBadge(label: AppConfig.metricPMTen, value: reading.pm10)
            }
            .frame(maxWidth: .infinity) // Ensures they expand to fill the container width
        }
        .padding(.all, 14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

}
