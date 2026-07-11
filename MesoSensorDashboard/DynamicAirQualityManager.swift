//
//  DynamicAirQualityManager.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//
import Foundation
import Combine

class DynamicAirQualityManager: ObservableObject {
    @Published var history: [HistoricalReading] = []
    @Published var statusText: String = "Initializing..."
    @Published var pm1Value: String = "--"
    @Published var pm25Value: String = "--"
    @Published var pm10Value: String = "--"
    
    private var cancellables = Set<AnyCancellable>()
    
    // ⚓️ THE ANCHOR: Keeps the chosen manager alive in memory!
    private var currentManager: AnyObject?
    
    init() {
        if AppConfig.useMockSimulatorBridge {
            let mockManager = SimulatorBridgeManager()
            self.currentManager = mockManager
            
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
            self.currentManager = realManager
            
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
