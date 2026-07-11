//
//  ContentView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import SwiftUI
import Combine

class DynamicAirQualityManager: ObservableObject {
    @Published var history: [HistoricalReading] = []
    @Published var statusText: String = "Initializing..."
    @Published var pm1Value: String = "--"
    @Published var pm25Value: String = "--"
    @Published var pm10Value: String = "--"
    
    private var cancellables = Set<AnyCancellable>()
    
    // ⚓️ THE ANCHOR: This permanent reference keeps the manager alive in memory!
    private var currentManager: AnyObject?
    
    init() {
        if AppConfig.useMockSimulatorBridge {
            let mockManager = SimulatorBridgeManager()
            self.currentManager = mockManager // 👈 Anchor it here!
            
            self.statusText = mockManager.statusText
            self.pm1Value = mockManager.pm1Value
            self.pm25Value = mockManager.pm25Value
            self.pm10Value = mockManager.pm10Value
            
            mockManager.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self, weak mockManager] _ in
                    guard let self = self, let mock = mockManager else { return }
                    self.statusText = mock.statusText
                    self.pm1Value = mock.pm1Value
                    self.pm25Value = mock.pm25Value
                    self.pm10Value = mock.pm10Value
                    self.history = mock.history
                }
                .store(in: &cancellables)
        } else {
            let realManager = BluetoothManager()
            self.currentManager = realManager // 👈 Anchor it here!
            
            self.statusText = realManager.statusText
            self.pm1Value = realManager.pm1Value
            self.pm25Value = realManager.pm25Value
            self.pm10Value = realManager.pm10Value
            
            realManager.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self, weak realManager] _ in
                    guard let self = self, let real = realManager else { return }
                    self.statusText = real.statusText
                    self.pm1Value = real.pm1Value
                    self.pm25Value = real.pm25Value
                    self.pm10Value = real.pm10Value
                    self.history = real.history
                }
                .store(in: &cancellables)
        }
    }
}

struct ContentView: View {
    @StateObject var bleManager = DynamicAirQualityManager()
    
    var body: some View {
            TabView {
                // 📍 TAB 1:
                NavigationStack {
                    VStack(spacing: 30) {
                                Text("Meso Sensor Dashboard")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .padding(.top, 40)
                                
                                // Connection Status Pill
                                Text(bleManager.statusText)
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(bleManager.statusText.contains("Data") || bleManager.statusText == "Connected!" ? .green : .secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(20)
                                
                                Spacer()
                                
                                // Main PM2.5 Hero Grid Box (The most critical walking metric)
                                VStack(spacing: 8) {
                                    Text("PARTICULATE MATTER (PM2.5)")
                                        .font(.caption)
                                        .tracking(1.5)
                                        .foregroundColor(.gray)
                                        .bold()
                                    
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text(bleManager.pm25Value)
                                            .font(.system(size: 64, weight: .black, design: .rounded))
                                        Text("µg/m³")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(24)
                                .frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(24)
                                
                                // Secondary PM1 and PM10 Side-by-Side Boxes
                                HStack(spacing: 16) {
                                    // PM1 Box
                                    VStack(spacing: 6) {
                                        Text("PM1.0")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.gray)
                                        Text("\(bleManager.pm1Value) µg/m³")
                                            .font(.title2)
                                            .bold()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(16)
                                    
                                    // PM10 Box
                                    VStack(spacing: 6) {
                                        Text("PM10")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(.gray)
                                        Text("\(bleManager.pm10Value) µg/m³")
                                            .font(.title2)
                                            .bold()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(16)
                                }
                                
                                Spacer()
                                
                                // Help note explaining your firmware's cycle behavior
                                Text("Note: Sensor cycles every 25 seconds to preserve battery.")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding()
                        
                    .navigationTitle("Meso Live")
                }
                .tabItem {
                    Label("Live Dashboard", systemImage: "gauge.with.needle")
                }
                
                // 📍 TAB 2: STREAM HISTORY
                HistoryView(bleManager: bleManager)
                    .tabItem {
                        Label("Stream History", systemImage: "clock.arrow.2.circlepath")
                    }
            }
        }
}

// Helper view for your dashboard blocks if you need it:
struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
            
            HStack(alignment: .lastTextBaseline) {
                Text(value)
                    .font(.system(.title, design: .rounded))
                    .bold()
                    .foregroundStyle(color)
                
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
