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
    
    @State private var cleanPM1: Double = 0.0
    @State private var cleanPM25: Double = 0.0
    @State private var cleanPM10: Double = 0.0
    @EnvironmentObject var bleManager: BluetoothManager
    
    
    var body: some View {
        VStack {
            if let alertText = bleManager.alertMessage {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Text(alertText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
                .padding()
                .background(bannerColor(for: bleManager.alertTheme))
                .cornerRadius(12)
                .padding([.horizontal, .top])
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
            
            HeroMetricBox(value: bleManager.pm25Value)
                .padding(.bottom, 8)
            
            HStack(spacing: 16) {
                SmallMetricCard(label: AppConfig.metricPMOne, value: bleManager.pm1Value)
                SmallMetricCard(label: AppConfig.metricPMTen, value: bleManager.pm10Value)
            }
            
            Spacer()
            
            BatteryNote()
            FacetedStatusLabel(text: bleManager.statusText)
                .padding(.bottom, 12)
        }
        .padding(.horizontal)
        .background(Color(.systemBackground))
        .animation(.easeInOut, value: bleManager.alertMessage) // Animates banner entry smoothly
        .onAppear {
            updateUI()
        }
        .onChange(of: allSamples) { _, _ in
            updateUI()
        }
    }
    
    // 3. This helper function bridges your view to your clean AirQualityMath file
    private func updateUI() {
        let metrics = AirQualityMath.calculateCleanAverage(from: allSamples, pastHours: 1)
        self.cleanPM1 = metrics.pm1
        self.cleanPM25 = metrics.pm25
        self.cleanPM10 = metrics.pm10
    }
    
    private func bannerColor(for theme: AlertVisualTheme) -> Color {
            switch theme {
            case .fineParticulates:
                return Color.blue
            case .allergenProfile, .generalCoarse:
                return Color.teal
            case .none:
                return Color.clear
            }
        }
    
}
