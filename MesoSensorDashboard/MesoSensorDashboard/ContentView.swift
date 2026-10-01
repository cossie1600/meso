//
//  ContentView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    
    var body: some View {
        TabView {
            DashboardMainView()
                .tabItem {
                    Label("Votre Air", systemImage: "square.grid.2x2.fill")
                }
            
            HistoryContainerView(bleManager: bleManager)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            
            BreathTestSheetView(
                sample: bleManager.mesoNoseSamples.first,
                result: .none
            )
            .tabItem {
                Label("Breath Test", systemImage: "wind")
            }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Color.appPrimaryText)
    }
}
