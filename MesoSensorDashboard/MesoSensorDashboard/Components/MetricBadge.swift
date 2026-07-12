//
//  MetricBadge.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/11/26.
//

import SwiftUI

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
