//
//  MesoNoseResultCard.swift
//  MesoSensorDashboard
//

import SwiftUI

struct MesoNoseResultCard: View {
    let sample: MesoNoseSample

    private var resultEnum: MesoNoseResult {
        MesoNoseResult(rawValue: sample.ptcResult) ?? .none
    }

    /// Renders the exact historical Date + Time recorded in SQLite/SwiftData at test evaluation time
    private var formattedTestDateAndTime: String {
        let dateStr = sample.timestamp.formatted(date: .abbreviated, time: .omitted)
        let timeStr = sample.timestamp.formatted(date: .omitted, time: .shortened)
        return "\(dateStr), \(timeStr)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(resultEnum.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color.appPrimaryText)

                Spacer()

                Text(formattedTestDateAndTime)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.appSecondaryText)
            }

            // Display consumer Result Description
            Text(resultEnum.description)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassCardStyle()
    }
}
