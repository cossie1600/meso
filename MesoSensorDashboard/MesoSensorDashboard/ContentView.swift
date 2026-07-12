//
//  ContentView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject var bleManager = DynamicAirQualityManager()
    
    var body: some View {
        // 🏗️ Root container handles the navigation bar real estate globally
        NavigationStack {
            TabView {
                // 📍 TAB 1: LIVE DASHBOARD
                VStack {                    
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
                .tabItem {
                    Label("Live Dashboard", systemImage: "gauge.with.needle")
                }
                
                // 📍 TAB 2: STREAM HISTORY
                HistoryView(bleManager: bleManager)
                    .tabItem {
                        Label("Stream History", systemImage: "clock.arrow.2.circlepath")
                    }
            }
            // ✨ THE FIX: Attached to the root TabView so it displays seamlessly on ALL tabs!
            .clingGemWatermark()
        }
    }
}
