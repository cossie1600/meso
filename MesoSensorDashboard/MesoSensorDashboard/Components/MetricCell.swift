//
//  MetricCell.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/9/26.
//

import SwiftUI

struct MetricCell: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.footnote)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    HStack(spacing: AppConfig.DashboardUI.metricGridSpacing) {
        MetricCell(label: "Temp", value: "24.5°C")
        MetricCell(label: "Humidity", value: "45.0%")
        MetricCell(label: "PM2.5", value: "12.0 µg/m³")
    }
    .padding()
}
