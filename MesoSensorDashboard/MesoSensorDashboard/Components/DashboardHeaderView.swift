//
//  DashboardHeaderView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/1/26.
//

import SwiftUI

struct DashboardHeaderView: View {
    let title: String
    var showSymbol: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color.appPrimaryText)

            Spacer()

            if showSymbol {
                AlchemicalAirSymbol(size: 28)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}
