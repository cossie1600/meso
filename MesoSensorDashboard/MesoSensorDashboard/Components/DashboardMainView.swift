//
//  DashboardMainView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/1/26.
//

import SwiftUI
import CoreBluetooth

struct DashboardMainView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    
    private var isMesoNoseConnected: Bool {
        bleManager.mesoNosePeripheral?.state == .connected
    }
    
    private var isPMConnected: Bool {
        bleManager.mesoPinPeripheral?.state == .connected
    }
    
    private var latestTemp: Double? {
        bleManager.mesoNoseSamples.first?.temp
    }
    
    private var latestHumidity: Double? {
        bleManager.mesoNoseSamples.first?.humidity
    }
    
    private var latestPressure: Double? {
        bleManager.mesoNoseSamples.first?.pressure
    }
    
    private var latestBattery: Int? {
        bleManager.mesoNoseSamples.first?.battery
    }
    
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Bar (Title + Emblem)
                HStack {
                    Text("Votre Air")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color.appPrimaryText)
                    
                    Spacer()
                    
                    AlchemicalAirSymbol(size: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 6)
                
                // Micro Telemetry Bar
                DashboardTelemetryBarView(
                    isMesoNoseConnected: bleManager.mesoNosePeripheral?.state == .connected,
                    isPMConnected: bleManager.mesoPinPeripheral?.state == .connected,
                    tempC: bleManager.mesoNoseSamples.first?.temp,
                    humidity: bleManager.mesoNoseSamples.first?.humidity,
                    mesoNoseBattery: bleManager.mesoNoseSamples.first?.battery,
                    mesoPinBattery: bleManager.pm25Value.isEmpty ? nil : 100,
                    pm1Value: bleManager.pm1Value,
                    pm25Value: bleManager.pm25Value,
                    pm10Value: bleManager.pm10Value
                )
                
                // Scrollable Recommendation Card View
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        DashboardInsightCardView(
                            humidity: latestHumidity,
                            pressure: latestPressure,
                            pm25String: bleManager.pm25Value
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
