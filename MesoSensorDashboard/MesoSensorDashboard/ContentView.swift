//
//  ContentView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import SwiftUI
import Combine
import SwiftData

struct ContentView: View {
    @Query(sort: \DB_PMSample.timestamp, order: .reverse) var allSamples: [DB_PMSample]
    @Query(sort: \DB_MesoNoseSample.timestamp, order: .reverse) var allNoseDbSamples: [DB_MesoNoseSample]
    @EnvironmentObject var bleManager: BluetoothManager
    
    @State private var cleanPM1: Double = 0.0
    @State private var cleanPM25: Double = 0.0
    @State private var cleanPM10: Double = 0.0
    
    /// The latest telemetry sample (ambient or evaluated)
    private var latestNoseSample: MesoNoseSample? {
        bleManager.mesoNoseSamples.first
    }
    
    /// Finds the most recent completed breath test evaluation result
    private var latestBreathResult: PtcResult {
        // 1. Search in-memory array for the newest sample with an active evaluation result
        if let evaluatedSample = bleManager.mesoNoseSamples.first(where: {
            $0.ptcResult != "NONE" && !$0.ptcResult.isEmpty
        }) {
            return PtcResult(rawValue: evaluatedSample.ptcResult) ?? .none
        }
        
        // 2. Fallback to persisted database records if in-memory list is fresh/empty
        if let dbEvaluated = allNoseDbSamples.first(where: {
            $0.ptcResult != "NONE" && !$0.ptcResult.isEmpty
        }) {
            return PtcResult(rawValue: dbEvaluated.ptcResult) ?? .none
        }
        
        return .none
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Meso Nose Controls & Telemetry (Includes Breath Test Overlay)
                MesoNoseSectionView(
                    sample: latestNoseSample,
                    result: latestBreathResult
                )
                .padding(.top, 8)
                
                Divider()
                    .padding(.vertical, 4)
                
                // 2. Meso Pin PM Metrics
                MesoPinMetricsView(
                    pm1: bleManager.pm1Value,
                    pm25: bleManager.pm25Value,
                    pm10: bleManager.pm10Value
                )
                
                Spacer(minLength: 16)
                
                // 3. Alert Banner
                if let alertText = bleManager.alertMessage {
                    AlertBannerView(text: alertText, theme: bleManager.alertTheme)
                }
                
                // 4. Status Footer
                FacetedStatusLabel(text: bleManager.statusText)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal)
        }
        .background(Color(.systemBackground))
        .animation(.easeInOut, value: bleManager.alertMessage)
        .animation(.easeInOut, value: bleManager.breathTestState)
        .onAppear { updateUI() }
        .onChange(of: allSamples) { _, _ in updateUI() }
    }
    
    private func updateUI() {
        let metrics = AirQualityMath.calculateCleanAverage(from: allSamples, pastHours: 1)
        self.cleanPM1 = metrics.pm1
        self.cleanPM25 = metrics.pm25
        self.cleanPM10 = metrics.pm10
    }
}

// MARK: - Subview 1: Meso Nose Section
private struct MesoNoseSectionView: View {
    let sample: MesoNoseSample?
    let result: PtcResult
    @EnvironmentObject var bleManager: BluetoothManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppConfig.DashboardUI.cardSpacing) {
            HStack {
                Label("Meso Nose Telemetry", systemImage: "wind")
                    .font(.headline)
                Spacer()
                
                // 🟢 Baseline Readiness Status Badge
                if bleManager.isRoomBaselineReady {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Baseline Ready")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
                }
                
                PtcBadgeView(result: result)
            }
            
            // -------------------------------------------------------------
            // BREATH TEST HUD OVERLAY (Renders when sequence is active)
            // -------------------------------------------------------------
            if bleManager.breathTestState != .idle {
                BreathTestOverlayView(bleManager: bleManager)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.vertical, 4)
            }
            
            if let nose = sample {
                HStack(spacing: AppConfig.DashboardUI.metricGridSpacing) {
                    MetricCell(label: "Temp", value: String(format: AppConfig.DashboardUI.Formats.temp, nose.temp))
                    MetricCell(label: "Humidity", value: String(format: AppConfig.DashboardUI.Formats.humidity, nose.humidity))
                    MetricCell(label: "VOC", value: String(format: AppConfig.DashboardUI.Formats.gasRes, nose.voc))
                }
                
                if result.isEvaluated || nose.breathDropDelta > 0 {
                    HStack {
                        Text("Breath Drop Delta:")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(String(format: AppConfig.DashboardUI.Formats.deltaDrop, nose.breathDropDelta))
                            .font(.footnote)
                            .bold()
                        Spacer()
                        Text("Min VOC: \(String(format: AppConfig.DashboardUI.Formats.gasRes, nose.breathMin))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("No Meso Nose reading received yet...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            
            // Command Triggers Grid
            VStack(spacing: 10) {
                // 1. Main Operations Row
                HStack(spacing: 10) {
                    Button(action: { bleManager.startActiveSampling() }) {
                        Label("Start Sampling", systemImage: "play.fill")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    
                    Button(action: { bleManager.stopSampling() }) {
                        Label("Stop Sampling", systemImage: "stop.fill")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                
                // 2. Mode Configurations Row
                HStack(spacing: 8) {
                    Button(action: { bleManager.setActiveSamplingMode() }) {
                        Label("LP Mode (3s)", systemImage: "bolt.fill")
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                    
                    Button(action: { bleManager.setUltraLowSamplingMode() }) {
                        Label("5m Sampling", systemImage: "leaf.fill")
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                }
                
                // 3. Breath Sequence Trigger (Only visible when state is idle)
                if bleManager.breathTestState == .idle {
                    Button(action: { bleManager.triggerBreathTest() }) {
                        Label("Breath Test", systemImage: "waveform.and.mic")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(.top, 6)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Subview 2: Meso Pin Metrics Section
private struct MesoPinMetricsView: View {
    let pm1: String
    let pm25: String
    let pm10: String
    
    var body: some View {
        VStack(spacing: 16) {
            HeroMetricBox(value: pm25)
            
            HStack(spacing: 16) {
                SmallMetricCard(label: AppConfig.metricPMOne, value: pm1)
                SmallMetricCard(label: AppConfig.metricPMTen, value: pm10)
            }
        }
    }
}

// MARK: - Subview 3: Alert Banner
private struct AlertBannerView: View {
    let text: String
    let theme: AlertVisualTheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
            
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding()
        .background(bannerColor(for: theme))
        .cornerRadius(12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private func bannerColor(for theme: AlertVisualTheme) -> Color {
        switch theme {
        case .fineParticulates: return .blue
        case .allergenProfile, .generalCoarse: return .teal
        case .none: return .clear
        }
    }
}
