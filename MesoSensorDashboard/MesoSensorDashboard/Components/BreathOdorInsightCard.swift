//
//  BreathOdorInsightCard.swift
//  MesoSensorDashboard
//

import SwiftUI

struct BreathOdorInsightCard: View {
    @ObservedObject var bleManager: BluetoothManager

    private struct UIConstants {
        static let cardTitle = "Breath Odor Insight"
        static let startButtonText = "Start"
        static let cancelButtonText = "Cancel"

        static let titleFontSize: CGFloat = 18.0
        static let buttonFontSize: CGFloat = 15.0
        static let statusFontSize: CGFloat = 14.0
        static let buttonHeight: CGFloat = 40.0
        static let cornerRadius: CGFloat = 10.0
        static let cardPadding: CGFloat = 16.0
    }

    /// Derives active guidance text to render below action buttons matching BreathTestState
    private var activeGuidanceText: String? {
        switch bleManager.breathTestState {
        case .coldBootWarmup:
            return MesoNoseUIStrings.wakingAndPreheating
        case .warmingUp:
            return MesoNoseUIStrings.warmingUpBlocked
        case .blowNow:
            return MesoNoseUIStrings.blowNow
        case .processing:
            return MesoNoseUIStrings.analyzingBreath
        case .completed:
            return MesoNoseUIStrings.analysisComplete
        case .timeout:
            return MesoNoseUIStrings.noBreathDetected
        case .idle:
            return nil
        }
    }

    /// Color coding for dynamic guidance banner
    private var activeGuidanceColor: Color {
        switch bleManager.breathTestState {
        case .coldBootWarmup, .warmingUp, .processing:
            return Color.orange
        case .blowNow:
            return Color.blue
        case .completed:
            return Color.green
        case .timeout:
            return Color.red
        case .idle:
            return Color.appSecondaryText
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Bar
            Text(UIConstants.cardTitle)
                .font(.system(size: UIConstants.titleFontSize, weight: .bold, design: .rounded))
                .foregroundColor(Color.appPrimaryText)

            // Primary Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    bleManager.triggerBreathTest()
                }) {
                    Text(UIConstants.startButtonText)
                        .font(.system(size: UIConstants.buttonFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.buttonHeight)
                        .background(bleManager.isConnected ? Color.black.opacity(0.85) : Color.gray)
                        .cornerRadius(UIConstants.cornerRadius)
                }
                .disabled(!bleManager.isConnected || bleManager.breathTestState != .idle)

                Button(action: {
                    bleManager.cancelBreathTest()
                }) {
                    Text(UIConstants.cancelButtonText)
                        .font(.system(size: UIConstants.buttonFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.appPrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.buttonHeight)
                        .background(Color.gray.opacity(0.20))
                        .cornerRadius(UIConstants.cornerRadius)
                }
            }

            // Dynamic Live Guidance / Status Banner below buttons
            if let guidanceText = activeGuidanceText {
                HStack(spacing: 8) {
                    if bleManager.breathTestState == .coldBootWarmup ||
                       bleManager.breathTestState == .warmingUp ||
                       bleManager.breathTestState == .processing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(guidanceText)
                        .font(.system(size: UIConstants.statusFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(activeGuidanceColor)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(UIConstants.cardPadding)
        .glassCardStyle()
        .animation(.smooth(duration: 0.3), value: bleManager.breathTestState)
    }
}
