//
//  SettingsView.swift
//  MesoSensorDashboard
//

import SwiftUI
import CoreBluetooth

struct SettingsView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var selectedMode: SamplingMode = AppConfig.samplingMode

    @AppStorage("MesoNoseCustomNickname") private var customNickname: String = ""
    @AppStorage("MesoNosePairedUUID") private var pairedUUIDString: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Device Onboarding and Proximity Pairing
                Section("Device Pairing & Onboarding") {
                    if let connectedNose = bluetoothManager.mesoNosePeripheral {
                        HStack {
                            Text("Status")
                                .foregroundColor(Color.appPrimaryText)
                            Spacer()
                            Text("Connected")
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.green)
                        }

                        HStack {
                            Text("Device ID")
                                .foregroundColor(Color.appPrimaryText)
                            Spacer()
                            Text(connectedNose.identifier.uuidString.prefix(8) + "...")
                                .font(.caption)
                                .foregroundColor(Color.appSecondaryText)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Device Nickname")
                                .font(.caption)
                                .foregroundColor(Color.appSecondaryText)
                            TextField("Enter nickname (e.g. Tom's Nose)", text: $customNickname)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)

                        Button(role: .destructive, action: {
                            bluetoothManager.disconnectMesoNose()
                            pairedUUIDString = ""
                            customNickname = ""
                        }) {
                            HStack {
                                Spacer()
                                Text("Unpair Device")
                                Spacer()
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Proximity Auto-Pairing")
                                .font(.headline)
                                .foregroundColor(Color.appPrimaryText)
                            Text("Hold your phone within 2 inches of your Meso Nose device to auto-pair.")
                                .font(.footnote)
                                .foregroundColor(Color.appSecondaryText)
                        }
                        .padding(.vertical, 4)

                        HStack {
                            Text("Scan Status")
                                .foregroundColor(Color.appPrimaryText)
                            Spacer()
                            Text(bluetoothManager.statusText)
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }

                        Button(action: {
                            bluetoothManager.startScanning()
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Scan for Nearby Device")
                                    .bold()
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appPrimaryText)
                    }
                }
                .listRowBackground(Color.jadeiteTranslucent)

                // Active State Display
                Section("Live Hardware State") {
                    HStack {
                        Text("Current Mode")
                            .foregroundColor(Color.appPrimaryText)
                        Spacer()
                        Text(bluetoothManager.currentSamplingMode.rawValue)
                            .font(.subheadline)
                            .bold()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.appPrimaryText.opacity(0.12))
                            .foregroundColor(Color.appPrimaryText)
                            .cornerRadius(6)
                    }
                }
                .listRowBackground(Color.jadeiteTranslucent)

                // Mode Selector
                Section("Select Sampling Mode") {
                    Picker("Sampling Mode", selection: $selectedMode) {
                        ForEach(SamplingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.jadeiteTranslucent)

                // Command Submission Button
                Section {
                    Button(action: {
                        bluetoothManager.setSamplingMode(mode: selectedMode)
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                            Text("Set Sampling Mode")
                                .bold()
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appPrimaryText)
                }
                .listRowBackground(Color.jadeiteTranslucent)
            }
            .scrollContentBackground(.hidden)
            .background(Color.jadeiteBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .onAppear {
                selectedMode = bluetoothManager.currentSamplingMode
            }
        }
    }
}
