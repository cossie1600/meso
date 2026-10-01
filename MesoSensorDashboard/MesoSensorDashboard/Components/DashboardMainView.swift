//
//  DashboardMainView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/1/26.
//
import SwiftUI
import SwiftData

struct DashboardMainView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    @Query(sort: \DB_MesoNoseSample.timestamp, order: .reverse) var allNoseDbSamples: [DB_MesoNoseSample]
    
    private var latestNose: MesoNoseSample? {
        bleManager.mesoNoseSamples.first
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
                    tempC: latestNose?.temp ?? 23.0,
                    humidity: latestNose?.humidity ?? 55.0,
                    pm25String: bleManager.pm25Value
                )
                
                // Scrollable Recommendation Card View
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        DashboardInsightCardView(
                            humidity: latestNose?.humidity ?? 55.0,
                            pressure: latestNose?.pressure ?? 1013.0,
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
