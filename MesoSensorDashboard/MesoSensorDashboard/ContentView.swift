//
//  ContentView.swift
//  MesoSensorDashboard
//

import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    @State private var selectedTab: Int = 0

    private struct UIConstants {
        static let tabTitleDashboard = "Votre Air"
        static let tabTitleSettings = "Settings"
    }

    private var breathStatusText: String {
        switch bleManager.breathTestState {
        case .coldBootWarmup:
            return bleManager.statusText.lowercased()
        case .warmingUp:
            return MesoNoseUIStrings.heatingSensorPlate.lowercased()
        case .blowNow:
            return MesoNoseUIStrings.blowNow.lowercased()
        case .processing:
            return MesoNoseUIStrings.analyzingBreath.lowercased()
        case .completed, .idle:
            return MesoNoseUIStrings.connectedReady.lowercased()
        case .timeout:
            return bleManager.statusText.lowercased()
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Votre Air (Primary Dashboard)
            VotreAirDashboardView(bleManager: bleManager)
                .tabItem {
                    Label(
                        UIConstants.tabTitleDashboard,
                        systemImage: "square.grid.2x2.fill"
                    )
                }
                .tag(0)

            // Tab 2: Settings View
            SettingsView()
                .tabItem {
                    Label(
                        UIConstants.tabTitleSettings,
                        systemImage: "gearshape.fill"
                    )
                }
                .tag(1)
        }
        .tint(Color.appPrimaryText)
    }
}
