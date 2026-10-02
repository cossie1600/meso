//
//  BreathTestSheetView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct BreathTestSheetView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    let sample: MesoNoseSample?
    let result: String?

    private var breathStatusText: String {
        switch bleManager.breathTestState {
        case .warmingUp:
            return "warming up..."
        case .blowNow:
            return "blow now"
        case .processing:
            return "analyzing..."
        case .completed:
            return bleManager.isPurgingMoisture ? "purging moisture..." : "ready"
        case .timeout:
            return "no breath detected"
        case .idle:
            if bleManager.isPurgingMoisture {
                return "purging moisture..."
            }
            return "ready"
        }
    }

    private var statusBadgeColor: Color {
        switch bleManager.breathTestState {
        case .blowNow:
            return .green
        case .processing:
            return .blue
        case .timeout:
            return .red
        case .warmingUp:
            return .orange
        case .completed, .idle:
            return bleManager.isPurgingMoisture ? .orange : .green
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                DashboardHeaderView(title: "Breath Test")

                // Top Control Bar: Dynamically switches Start -> Retry on Failure
                HStack(spacing: 12) {
                    if bleManager.breathTestState == .timeout {
                        Button(action: {
                            bleManager.triggerBreathTest()
                        }) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                                .background(Color.appPrimaryText)
                                .cornerRadius(16)
                        }
                    } else {
                        Button(action: {
                            bleManager.triggerBreathTest()
                        }) {
                            Text("Start")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                                .background(bleManager.isRoomBaselineReady ? Color.appPrimaryText : Color.gray.opacity(0.5))
                                .cornerRadius(16)
                        }
                        .disabled(!bleManager.isRoomBaselineReady || bleManager.breathTestState != .idle)
                    }

                    Button(action: {
                        bleManager.cancelBreathTest()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(Color.gray.opacity(0.4))
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)

                // Dedicated Status Display Card
                HStack {
                    Text("Status")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color.appSecondaryText)
                    Spacer()
                    Text(breathStatusText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(statusBadgeColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.jadeiteTranslucent)
                .cornerRadius(12)
                .padding(.horizontal, 20)

                // Past Results List
                VStack(alignment: .leading, spacing: 12) {
                    Text("PAST RESULTS")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color.appSecondaryText)
                        .padding(.horizontal, 20)

                    if let sample = bleManager.mesoNoseSamples.first(where: { $0.breathDropDelta > 0.0 }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sample.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.appPrimaryText)
                                Text(sample.timestamp.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.appSecondaryText)
                            }
                            Spacer()
                            Text(sample.ptcResult.capitalized)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.yellow.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(8)
                        }
                        .padding(16)
                        .background(Color.jadeiteTranslucent)
                        .cornerRadius(16)
                        .padding(.horizontal, 20)
                    }
                }

                Spacer()
            }
        }
    }
}
