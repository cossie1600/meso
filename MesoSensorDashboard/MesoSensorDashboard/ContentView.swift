//
//  ContentView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bleManager: BluetoothManager

    var body: some View {
        VotreAirDashboardView(bleManager: bleManager)
            .tint(Color.appPrimaryText)
    }
}
