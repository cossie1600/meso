//
//  MainTableView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/13/26.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    
    var body: some View {
        TabView {
            NavigationStack {
                ContentView() // Subviews will automatically have access to this environment object!
            }
            .tabItem {
                Label("Dashboard", systemImage: "waveform.path.ecg")
            }
            
            NavigationStack {
                // Now passing the unified, shared environment manager instance safely
                HistoryView(bleManager: bleManager)
            }
            .tabItem {
                Label("Raw History", systemImage: "clock.arrow.circlepath")
            }
        }
        .clingGemWatermark()
    }
}

// MARK: - Updated Preview
#Preview {
    MainTabView()
        .environmentObject(BluetoothManager()) // Supplies a quick instance for preview rendering canvas cycles
}
