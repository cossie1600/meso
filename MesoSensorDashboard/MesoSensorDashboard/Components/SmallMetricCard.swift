//
//  SmallMetricCard.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/11/26.
//

import SwiftUI

struct SmallMetricCard: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).bold().foregroundColor(.gray)
            Text("\(value) \(AppConfig.metricUnit)").font(.title2).bold()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}
