//
//  BluetoothManager+Mock.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/14/26.
//

import Foundation

extension BluetoothManager {
    
    func stopMockDataStream() {
        // No-op: Mock streaming disabled
    }
    
    func startMockDataStream() {
        // No-op: Real BLE hardware mode active
    }
    
    func handleMockPacket(_ text: String) {
        // No-op: Real BLE hardware mode active
    }
    
    func mockTriggerBreathTest() {
        // No-op: Real BLE hardware mode active
    }
}
