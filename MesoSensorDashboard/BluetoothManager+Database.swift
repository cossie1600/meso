//
//  BluetoothManager+Database.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/14/26.
//
import Foundation
import SwiftData

// MARK: - Database Helpers
extension BluetoothManager {
    
    func saveToSQLite(_ packet: IncomingPacket) {
        guard let container = self.modelContainer else {
            AppLogger.writeLog("Error: ModelContainer not injected into BluetoothManager.")
            return
        }
        
        DispatchQueue.main.async {
            let context = ModelContext(container)
            let newSample = DB_PMSample(
                timestamp: Date(),
                pm1: packet.pm1,
                pm25: packet.pm25,
                pm10: packet.pm10
            )
            
            context.insert(newSample)
            
            do {
                try context.save()
                AppLogger.writeLog("💾 Successfully saved sample to Main Database Context! (PM2.5: \(packet.pm25))")
            } catch {
                AppLogger.writeLog("❌ Failed to save context: \(error)")
            }
        }
    }
}

