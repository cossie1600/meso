//
//  SettingsView.swift
//  MesoSensorDashboard
//

import SwiftUI
import CoreBluetooth

struct SettingsView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var selectedCategory: SensorCategory = .microclimate

    @AppStorage("MesoNosePairedUUID") private var pairedUUIDString: String = ""

    private var settingsStatusText: String {
        if let connectedNose = bluetoothManager.mesoNosePeripheral, connectedNose.state == .connected {
            return "Connected"
        } else if bluetoothManager.isPairingModeActive {
            return "Ready For Pairing"
        } else {
            return "Disconnected"
        }
    }

    private var settingsStatusColor: Color {
        switch settingsStatusText {
        case "Connected": return .green
        case "Ready For Pairing": return .blue
        default: return .secondary
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                DashboardHeaderView(title: "Settings")

                SensorSegmentedPickerView(selectedCategory: $selectedCategory)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 20) {
                        switch selectedCategory {
                        case .microclimate:
                            // 1. Microclimate Pairing Card
                            VStack(alignment: .leading, spacing: 14) {
                                Text("MICROCLIMATE DEVICE")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.appSecondaryText)

                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Status")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.appPrimaryText)
                                        Spacer()
                                        Text(settingsStatusText)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundColor(settingsStatusColor)
                                    }

                                    if bluetoothManager.savedMesoNoseUUID != nil || bluetoothManager.mesoNosePeripheral?.state == .connected {
                                        Divider()

                                        HStack {
                                            Text("Device ID")
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundColor(Color.appPrimaryText)
                                            Spacer()
                                            Text((bluetoothManager.savedMesoNoseUUID?.uuidString ?? bluetoothManager.mesoNosePeripheral?.identifier.uuidString ?? "").prefix(8) + "...")
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundColor(Color.appSecondaryText)
                                        }

                                        Divider()

                                        HStack {
                                            Text("Microclimate Battery")
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundColor(Color.appPrimaryText)
                                            Spacer()
                                            BatteryIndicatorView(
                                                batteryPercentage: bluetoothManager.mesoNoseBattery,
                                                fontSize: 13,
                                                iconSize: 13
                                            )
                                        }

                                        Divider()

                                        Button(action: {
                                            bluetoothManager.disconnectMesoNose()
                                            bluetoothManager.savedMesoNoseUUID = nil
                                            pairedUUIDString = ""
                                        }) {
                                            Text("Unpair Device")
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(.red)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 48)
                                                .background(Color.red.opacity(0.12))
                                                .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Button(action: {
                                            bluetoothManager.startPairingMesoNose()
                                        }) {
                                            Text("Start Pairing")
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 48)
                                                .background(Color.appPrimaryText)
                                                .cornerRadius(12)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(16)
                                .background(Color.jadeiteTranslucent)
                                .cornerRadius(16)
                            }

                            // 2. Sampling Mode Selection Cards
                            VStack(alignment: .leading, spacing: 14) {
                                Text("SELECT SAMPLING MODE")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.appSecondaryText)

                                VStack(spacing: 10) {
                                    SamplingModeRow(
                                        title: "Active Sampling (3s)",
                                        subtitle: "Continuous live telemetry stream every 3 seconds.",
                                        isSelected: bluetoothManager.currentSamplingMode == .active3s
                                    ) {
                                        bluetoothManager.setSamplingMode(mode: .active3s)
                                    }

                                    SamplingModeRow(
                                        title: "Ultra Low Power (5m)",
                                        subtitle: "Saves battery by taking readings every 5 minutes.",
                                        isSelected: bluetoothManager.currentSamplingMode == .ulp5m
                                    ) {
                                        bluetoothManager.setSamplingMode(mode: .ulp5m)
                                    }

                                    SamplingModeRow(
                                        title: "Stopped",
                                        subtitle: "Pause all background telemetry sampling.",
                                        isSelected: bluetoothManager.currentSamplingMode == .stopped
                                    ) {
                                        bluetoothManager.setSamplingMode(mode: .stopped)
                                    }
                                }
                            }

                        case .particulates:
                            VStack(alignment: .leading, spacing: 14) {
                                Text("PARTICULATE SENSOR")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.appSecondaryText)

                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Status")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.appPrimaryText)
                                        Spacer()
                                        Text(bluetoothManager.mesoPinPeripheral?.state == .connected ? "Connected" : "Disconnected")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundColor(bluetoothManager.mesoPinPeripheral?.state == .connected ? .green : .secondary)
                                    }

                                    if bluetoothManager.mesoPinPeripheral?.state == .connected {
                                        Divider()

                                        HStack {
                                            Text("Particulates Battery")
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundColor(Color.appPrimaryText)
                                            Spacer()
                                            BatteryIndicatorView(
                                                batteryPercentage: bluetoothManager.pm25Value.isEmpty ? nil : 100,
                                                fontSize: 13,
                                                iconSize: 13
                                            )
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Color.jadeiteTranslucent)
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

struct SamplingModeRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isSelected ? Color.appPrimaryText : Color.appSecondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color.appPrimaryText)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color.appSecondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(14)
            .background(isSelected ? Color.jadeiteTranslucent : Color.white.opacity(0.3))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.appPrimaryText.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
