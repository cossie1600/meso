//
//  BatteryNote.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/11/26.
//

import SwiftUI

struct BatteryNote: View {
    var body: some View {
        Text("Note: Sensor cycles every 25 seconds to preserve battery.")
            .font(.footnote)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }
}
