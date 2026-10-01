//
//  HistoryCardView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/13/26.
//

import SwiftUI

struct HistoryCardView: View {
    let reading: DB_PMSample
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Top Row: Timestamp
            HStack {
                Text(timeFormatter.string(from: reading.timestamp))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color.appPrimaryText)
                    .layoutPriority(1)
                
                Spacer(minLength: 8)
            }
            
            // 2. Bottom Row: Environmental Metric Badges
            HStack(spacing: 8) {
                MetricBadge(label: AppConfig.metricPMOne, value: String(format: "%.1f", reading.pm1))
                MetricBadge(label: AppConfig.metricPMTwoFive, value: String(format: "%.1f", reading.pm25))
                MetricBadge(label: AppConfig.metricPMTen, value: String(format: "%.1f", reading.pm10))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .glassCardStyle()
    }
}
