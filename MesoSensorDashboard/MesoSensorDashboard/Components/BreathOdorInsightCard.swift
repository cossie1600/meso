//
//  BreathOdorInsightCard.swift
//  MesoSensorDashboard
//

import SwiftUI

struct BreathOdorInsightCard: View {
    @ObservedObject var bleManager: BluetoothManager

    private struct UIConstants {
        static let cardTitle = "Breath Odor Insight"
        static let titleFontSize: CGFloat = 18.0
        static let statusFontSize: CGFloat = 13.0
        static let buttonSize: CGFloat = 38.0
        static let buttonCornerRadius: CGFloat = 10.0
        static let cardPaddingHorizontal: CGFloat = 16.0
        static let cardPaddingVertical: CGFloat = 14.0
    }

    private var isTesting: Bool {
        bleManager.breathTestState != .idle && bleManager.breathTestState != .completed
    }

    /// Derives active guidance text matching BreathTestState
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

    /// Color coding for dynamic guidance text
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
        VStack(alignment: .leading, spacing: 8) {
            // Header Row: Title + Compact Square Toggle Button
            HStack(alignment: .center) {
                Text(UIConstants.cardTitle)
                    .font(.system(size: UIConstants.titleFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(Color.appPrimaryText)

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut) {
                        if isTesting {
                            bleManager.cancelBreathTest()
                        } else {
                            bleManager.triggerBreathTest()
                        }
                    }
                }) {
                    Image(systemName: isTesting ? "square.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(isTesting ? Color.white : Color.appPrimaryText)
                        .frame(width: UIConstants.buttonSize, height: UIConstants.buttonSize)
                        .background(
                            isTesting
                                ? Color.red.opacity(0.85)
                                : Color.white.opacity(0.60)
                        )
                        .cornerRadius(UIConstants.buttonCornerRadius)
                }
                .disabled(!bleManager.isConnected && !isTesting)
            }

            // Live Dynamic Guidance / Status Evaluation Text
            if let guidanceText = activeGuidanceText {
                HStack(spacing: 6) {
                    if bleManager.breathTestState == .coldBootWarmup ||
                       bleManager.breathTestState == .warmingUp ||
                       bleManager.breathTestState == .processing {
                        ProgressView()
                            .scaleEffect(0.7)
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
        .padding(.horizontal, UIConstants.cardPaddingHorizontal)
        .padding(.vertical, UIConstants.cardPaddingVertical)
        // Bright translucent white card background
        .background(Color.white.opacity(0.40))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.50), lineWidth: 1)
        )
        .animation(.smooth(duration: 0.3), value: bleManager.breathTestState)
    }
}
