//
//  HistoryContainerView.swift
//  MesoSensorDashboard
//

import SwiftUI
import CoreBluetooth

struct HistoryContainerView: View {
    @ObservedObject var bleManager: BluetoothManager
    @State private var selectedCategory: SensorCategory = .microclimate
    
    private var isMesoNoseConnected: Bool {
        bleManager.mesoNosePeripheral != nil
    }
    
    private var isPMConnected: Bool {
        bleManager.mesoPinPeripheral?.state == .connected
    }
    
    private var connectedCategories: [SensorCategory] {
        var categories: [SensorCategory] = []
        if isMesoNoseConnected { categories.append(.microclimate) }
        if isPMConnected { categories.append(.particulates) }
        return categories
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.jadeiteBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    DashboardHeaderView(title: "History")
                    
                    if connectedCategories.isEmpty {
                        ContentUnavailableView(
                            "No Active Sensors",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("Connect a sensor in Settings to view history logs.")
                        )
                        .padding(.top, 60)
                    } else {
                        if connectedCategories.count > 1 {
                            SensorSegmentedPickerView(
                                selectedCategory: $selectedCategory,
                                availableCategories: connectedCategories
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        }
                        
                        switch selectedCategory {
                        case .microclimate where isMesoNoseConnected:
                            MesoNoseHistoryView(bleManager: bleManager)
                        case .particulates where isPMConnected:
                            AirQualityHistoryView(bleManager: bleManager)
                        default:
                            EmptyView()
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: connectedCategories) { _, newCategories in
                if let first = newCategories.first, !newCategories.contains(selectedCategory) {
                    selectedCategory = first
                }
            }
            .onAppear {
                if let first = connectedCategories.first, !connectedCategories.contains(selectedCategory) {
                    selectedCategory = first
                }
            }
        }
    }
}
