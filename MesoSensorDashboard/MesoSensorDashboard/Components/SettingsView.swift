//
//  SettingsView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/22/26.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    @State private var showConfirmWipeAlert = false

    var body: some View {
        Form {
            // MARK: - Sampling Operations
            Section(header: Text("Sampling Controls")) {
                HStack(spacing: 12) {
                    Button(action: { bleManager.setUltraLowSamplingMode() }) {
                        Label("Start", systemImage: "play.fill")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    
                    Button(action: { bleManager.stopSampling() }) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Mode Configurations
            Section(
                header: Text("Sampling Mode"),
                footer: Text("Ultra-low mode samples every 5 minutes to conserve power.")
            ) {
                HStack(spacing: 12) {
                    // Fast Mode Button
                    Button(action: { bleManager.setActiveSamplingMode() }) {
                        Label("Fast (3s)", systemImage: "bolt.fill")
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .prominentIf(!bleManager.isUltraLowSamplingMode())
                    .tint(.teal)
                    
                    // Default Sampling Button
                    Button(action: { bleManager.setUltraLowSamplingMode() }) {
                        Label("Default (5m)", systemImage: "leaf.fill")
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .prominentIf(bleManager.isUltraLowSamplingMode())
                    .tint(.indigo)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Reusable Style Extension
private extension View {
    @ViewBuilder
    func prominentIf(_ condition: Bool) -> some View {
        if condition {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
