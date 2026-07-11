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
                        SmallMetricCard(label: "PM1.0", value: bleManager.pm1Value)
                        SmallMetricCard(label: "PM10", value: bleManager.pm10Value)
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

// MARK: - Modular UI Components
struct FacetedStatusLabel: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .opacity(0.5)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}

struct SmallMetricCard: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).bold().foregroundColor(.gray)
            Text("\(value) µg/m³").font(.title2).bold()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct HeroMetricBox: View {
    let value: String
    var body: some View {
        VStack(spacing: 8) {
            Text("PARTICULATE MATTER (PM2.5)").font(.caption).tracking(1.5).foregroundColor(.gray).bold()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 64, weight: .black, design: .rounded))
                Text("µg/m³").font(.headline).foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(24)
    }
}

struct BatteryNote: View {
    var body: some View {
        Text("Note: Sensor cycles every 25 seconds to preserve battery.")
            .font(.footnote)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }
}
