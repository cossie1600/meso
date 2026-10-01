//
//  BreathTestSheetView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct BreathTestSheetView: View {
    let sample: MesoNoseSample?
    let result: PtcResult
    @EnvironmentObject var bleManager: BluetoothManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tiffanyBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Status Header & Result Badge
                        HStack {
                            let statusColor: Color = bleManager.isRoomBaselineReady ? .green : .orange
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 8, height: 8)
                                Text(bleManager.isRoomBaselineReady ? "Baseline Ready" : "Baseline Not Ready")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(statusColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.tiffanyTranslucent)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
                            
                            Spacer()
                            
                            PtcBadgeView(result: result)
                        }
                        
                        // 2. Cooldown Timer Pill
                        if bleManager.isCoolingDown {
                            CooldownTimerView(lastTestDate: bleManager.lastTestCompletedDate)
                        }
                        
                        // 3. Stabilization Banner
                        if !bleManager.isRoomBaselineReady && bleManager.breathTestState == .idle {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.orange)
                                
                                Text(bleManager.isCoolingDown ? "Sensor Purging... Please wait" : "Stabilizing Sensor Baseline... Please wait")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.appPrimaryText)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.tiffanyTranslucent)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.8), lineWidth: 1))
                        }
                        
                        // 4. Interactive Test Progress Overlay
                        if bleManager.breathTestState != .idle {
                            BreathTestOverlayView(bleManager: bleManager)
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        // 5. Square Diagnostic Metric Cards
                        if let nose = sample {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("BREATH DIAGNOSTICS")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.appPrimaryText)
                                    .tracking(1.0)
                                
                                HStack(spacing: AppConfig.DashboardUI.metricGridSpacing) {
                                    SquareMetricCard(
                                        label: "Drop Delta",
                                        value: String(format: AppConfig.DashboardUI.Formats.deltaDrop, nose.breathDropDelta),
                                        unit: "%"
                                    )
                                    
                                    SquareMetricCard(
                                        label: "Min VOC",
                                        value: nose.breathMin > 0 ? String(format: AppConfig.DashboardUI.Formats.gasRes, nose.breathMin) : "--",
                                        unit: "Ω"
                                    )
                                }
                            }
                        }
                        
                        Spacer(minLength: 16)
                        
                        // 6. Primary Action Button
                        if bleManager.breathTestState == .idle {
                            Button(action: { bleManager.triggerBreathTest() }) {
                                Label("Start Breath Test", systemImage: "waveform.and.mic")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .background(bleManager.isRoomBaselineReady ? Color.appPrimaryText : Color.gray.opacity(0.5))
                            .cornerRadius(14)
                            .disabled(!bleManager.isRoomBaselineReady)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Breath Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                        .foregroundColor(Color.appPrimaryText)
                }
            }
        }
    }
}
