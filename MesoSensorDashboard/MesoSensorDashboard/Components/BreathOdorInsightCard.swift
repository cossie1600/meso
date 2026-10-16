//
//  BreathOdorInsightCard.swift
//  MesoSensorDashboard
//

import SwiftUI

struct BreathOdorInsightCard: View {
    @ObservedObject var bleManager: BluetoothManager

    private struct UIConstants {
        static let cardTitle = "Breath Odor Insight"
        static let statusPrefix = "Status:"
        static let stabilizationAdvisory = "Sensor heater plate is stabilizing. Tests taken now may be less accurate."
        static let startButtonText = "Start"
        static let warmingUpButtonText = "Warming Up..."
        static let disconnectedButtonText = "Disconnected"
        static let cancelButtonText = "Cancel"

        static let cardTitleFontSize: CGFloat = 17.0
        static let statusFontSize: CGFloat = 13.0
        static let advisoryFontSize: CGFloat = 11.0
        static let buttonHeight: CGFloat = 38.0
        static let buttonCornerRadius: CGFloat = 10.0
        static let cardPadding: CGFloat = 14.0
    }

    private var isStartButtonEnabled: Bool {
        return bleManager.isConnected && (bleManager.breathTestState == .idle || bleManager.breathTestState == .completed)
    }

    var startButtonTitle: String {
        if bleManager.breathTestState == .coldBootWarmup {
            return UIConstants.warmingUpButtonText
        } else if !bleManager.isConnected {
            return UIConstants.disconnectedButtonText
        } else {
            return UIConstants.startButtonText
        }
    }

    var breathStatusText: String {
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
            return MesoNoseUIStrings.noBreathDetected.lowercased()
        }
    }

    var statusBadgeColor: Color {
        switch bleManager.breathTestState {
        case .coldBootWarmup, .warmingUp:
            return .orange
        case .blowNow:
            return .green
        case .processing:
            return .blue
        case .timeout:
            return .red
        case .completed, .idle:
            return .green
        }
    }

    /// Advisory message remains visible until fresh live over-the-air BLE telemetry is ingested
    private var isStabilizingGuidanceVisible: Bool {
        guard bleManager.isConnected else { return false }
        return !bleManager.hasReceivedLiveTelemetry || bleManager.breathTestState == .coldBootWarmup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UIConstants.cardTitle)
                .font(.system(size: UIConstants.cardTitleFontSize, weight: .bold, design: .rounded))
                .foregroundColor(Color.appPrimaryText)

            // Dedicated Status Row
            HStack {
                Text(UIConstants.statusPrefix)
                    .font(.system(size: UIConstants.statusFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.appSecondaryText)

                Text(breathStatusText)
                    .font(.system(size: UIConstants.statusFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(statusBadgeColor)

                Spacer()
            }

            // Compact Side-by-Side Control Bar
            HStack(spacing: 10) {
                Button(action: {
                    bleManager.triggerBreathTest()
                }) {
                    Text(startButtonTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.buttonHeight)
                        .background(isStartButtonEnabled ? Color.appPrimaryText : Color.gray.opacity(0.5))
                        .cornerRadius(UIConstants.buttonCornerRadius)
                }
                .disabled(!isStartButtonEnabled)

                Button(action: {
                    bleManager.cancelBreathTest()
                }) {
                    Text(UIConstants.cancelButtonText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color.appPrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.buttonHeight)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(UIConstants.buttonCornerRadius)
                }
            }

            // Stabilization Advisory (Hides automatically upon live telemetry ingestion)
            if isStabilizingGuidanceVisible {
                Text(UIConstants.stabilizationAdvisory)
                    .font(.system(size: UIConstants.advisoryFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(UIConstants.cardPadding)
        .glassCardStyle()
    }
}
