//
//  SettingsView.swift
//  MesoSensorDashboard
//

import SwiftUI
import CoreBluetooth

struct SettingsView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var selectedMode: SamplingMode = AppConfig.samplingMode

    // Onboarding & Device Customization Storage
    @AppStorage("MesoNoseCustomNickname") private var customNickname: String = ""
    @AppStorage("MesoNosePairedUUID") private var pairedUUIDString: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Device Onboarding and Proximity Pairing
                Section("Device Pairing & Onboarding") {
                    if let connectedNose = bluetoothManager.mesoNosePeripheral {
                        // Connected State
                        HStack {
                            Text("Status")
                            Spacer()
                            Text("Connected")
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.green)
                        }

                        HStack {
                            Text("Device ID")
                            Spacer()
                            Text(connectedNose.identifier.uuidString.prefix(8) + "...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Custom Device Nickname Input
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Device Nickname")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                        // Unpaired or Searching State
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Proximity Auto-Pairing")
                                .font(.headline)
                            Text("Hold your phone within 2 inches of your Meso Nose device to auto-pair.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)

                        HStack {
                            Text("Scan Status")
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
                        .tint(.blue)
                    }
                }

                // Active State Display
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

                // Mode Selector
                Section("Select Sampling Mode") {
                    Picker("Sampling Mode", selection: $selectedMode) {
                        ForEach(SamplingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

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
                    .tint(.blue)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                selectedMode = bluetoothManager.currentSamplingMode
            }
            .onChange(of: bluetoothManager.mesoNosePeripheral) { _, newPeripheral in
                if let peripheral = newPeripheral {
                    pairedUUIDString = peripheral.identifier.uuidString
                    if customNickname.isEmpty {
                        customNickname = peripheral.name ?? "My Meso Nose"
                    }
                }
            }
        }
    }
}
