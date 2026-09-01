//
//  SettingsView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var selectedMode: SamplingMode = AppConfig.samplingMode

    var body: some View {
        NavigationStack {
            Form {
                // 📡 Active State Display
                Section("Live Hardware State") {
                    HStack {
                        Text("Current Mode")
                        Spacer()
                        Text(bluetoothManager.currentSamplingMode.rawValue)
                            .font(.subheadline)
                            .bold()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                    }
                }

                // 🎛️ Mode Selector
                Section("Select Sampling Mode") {
                    Picker("Sampling Mode", selection: $selectedMode) {
                        ForEach(SamplingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 🚀 Command Submission Button
                Section {
                    Button(action: {
                        bluetoothManager.startSampling(mode: selectedMode)
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                            Text("Start Sampling")
                                .bold()
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                selectedMode = bluetoothManager.currentSamplingMode
            }
        }
    }
}
