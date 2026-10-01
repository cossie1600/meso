//
//  ContentView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import SwiftUI
import Combine
import SwiftData
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    
    var body: some View {
        TabView {
            DashboardMainView()
                .tabItem {
                    Label("Votre Air", systemImage: "square.grid.2x2.fill")
                }
            
            // Unified History View (includes both Air Quality & Meso Nose logs)
            HistoryContainerView(bleManager: bleManager)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            
            BreathTestSheetView(
                sample: bleManager.mesoNoseSamples.first,
                result: .none
            )
            .tabItem {
                Label("Breath Test", systemImage: "wind")
            }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Color.appPrimaryText)
    }
}

// MARK: - Main Live Dashboard View
private struct DashboardMainView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    @Query(sort: \DB_MesoNoseSample.timestamp, order: .reverse) var allNoseDbSamples: [DB_MesoNoseSample]
    
    private var latestNose: MesoNoseSample? {
        bleManager.mesoNoseSamples.first
    }
    
    var body: some View {
        ZStack {
            // Background: Light Tiffany Blue / Green
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: 1. Custom Header Bar
                HStack {
                    Text("Votre Air")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color.appPrimaryText)
                    
                    Spacer()
                    
                    AlchemicalAirSymbol(size: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        
                        // MARK: Top Insight / Recommendation Card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Moderate Comfort: Low Pressure and High Humidity may trigger joint or muscle aches. Stay hydrated and apply eye drops.")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .lineSpacing(4)
                                .foregroundColor(Color.appPrimaryText)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCardStyle()
                        
                        // MARK: 2x2 Environmental Grid
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                SquareMetricCard(
                                    label: "Temp",
                                    value: String(format: AppConfig.DashboardUI.Formats.temp, latestNose?.temp ?? 23.5),
                                    unit: "°C"
                                )
                                SquareMetricCard(
                                    label: "Humidity",
                                    value: String(format: AppConfig.DashboardUI.Formats.humidity, latestNose?.humidity ?? 55.0),
                                    unit: "% RH"
                                )
                            }
                            
                            HStack(spacing: 12) {
                                SquareMetricCard(
                                    label: "Pressure",
                                    value: String(format: AppConfig.DashboardUI.Formats.pressure, latestNose?.pressure ?? 1013.0),
                                    unit: "hPa"
                                )
                                SquareMetricCard(
                                    label: "VOC",
                                    value: String(format: AppConfig.DashboardUI.Formats.gasRes, latestNose?.voc ?? 210.0),
                                    unit: nil
                                )
                            }
                        }
                        
                        // MARK: Particulates Section (PM1.0, PM2.5, PM10)
                        if bleManager.firmwarePeripheral?.state == .connected || true {
                            HStack(spacing: 12) {
                                SquareMetricCard(
                                    label: "PM1.0",
                                    value: bleManager.pm1Value.isEmpty ? "12" : bleManager.pm1Value,
                                    unit: "µg/m³",
                                    pmType: .pm1_0
                                )
                                SquareMetricCard(
                                    label: "PM2.5",
                                    value: bleManager.pm25Value.isEmpty ? "25" : bleManager.pm25Value,
                                    unit: "µg/m³",
                                    pmType: .pm2_5
                                )
                                SquareMetricCard(
                                    label: "PM10",
                                    value: bleManager.pm10Value.isEmpty ? "38" : bleManager.pm10Value,
                                    unit: "µg/m³",
                                    pmType: .pm10
                                )
                            }
                        } else {
                            // Disconnected State Prompt
                            Button(action: { bleManager.startScanning() }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.title2)
                                        .foregroundColor(Color.appPrimaryText)
                                    Text("No Particulate Sensor Connected")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.appPrimaryText)
                                    Text("Tap to search & pair device")
                                        .font(.caption)
                                        .foregroundColor(Color.appSecondaryText)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.tiffanyTranslucent)
                                .cornerRadius(18)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
