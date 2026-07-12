//
//  HeroMetricBox.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/11/26.
//

import SwiftUI

struct HeroMetricBox: View {
    let value: String
    var body: some View {
        VStack(spacing: 8) {
            Text("PARTICULATE MATTER (\(AppConfig.metricPMTwoFive)").font(.caption).tracking(1.5).foregroundColor(.gray).bold()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 64, weight: .black, design: .rounded))
                Text(AppConfig.metricUnit).font(.headline).foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(24)
    }
}
