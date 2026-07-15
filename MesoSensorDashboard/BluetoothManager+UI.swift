//
//  BluetoothManager+UI.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/14/26.
//

import Foundation

// MARK: - UI Live Updates
extension BluetoothManager {
    
    func updateLiveState(with packet: IncomingPacket) {
        DispatchQueue.main.async {
            self.pm1Value = String(format: "%.1f", packet.pm1)
            self.pm25Value = String(format: "%.1f", packet.pm25)
            self.pm10Value = String(format: "%.1f", packet.pm10)
            self.statusText = "Syncing Data..."
            
            AppLogger.writeLog("Synced: PM1: \(self.pm1Value), PM2.5: \(self.pm25Value), PM10: \(self.pm10Value)")
        }
    }
    
    func updateStatusOnMainThread(to message: String) {
        DispatchQueue.main.async {
            self.statusText = message
        }
    }
}
