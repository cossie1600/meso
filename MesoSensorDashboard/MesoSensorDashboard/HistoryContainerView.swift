//
//  HistoryContainerView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct HistoryContainerView: View {
    @ObservedObject var bleManager: BluetoothManager
    @State private var selectedHistoryTab: HistoryTab = .mesoNose
    
    enum HistoryTab: String, CaseIterable, Identifiable {
        case mesoNose = "Microclimate"
        case airQuality = "Particulates"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tiffanyBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    Picker("History Type", selection: $selectedHistoryTab) {
                        ForEach(HistoryTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    switch selectedHistoryTab {
                    case .mesoNose:
                        MesoNoseHistoryView(bleManager: bleManager)
                    case .airQuality:
                        AirQualityHistoryView(bleManager: bleManager)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
