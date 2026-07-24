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
    @MainActor
    func databaseAlreadyContains(footprint: String) -> Bool {
        guard let container = self.modelContainer else { return false }
        
        // Fetch the single most recent sample saved to check against
        var descriptor = FetchDescriptor<DB_PMSample>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        
        do {
            let context = container.mainContext
            let recentSamples = try context.fetch(descriptor)
            
            guard let latestSample = recentSamples.first else {
                return false // Database is completely empty
            }
            
            // Extract the core sensor readings from your latest saved sample
            let latestValuesOnly = "\(latestSample.pm1)_\(latestSample.pm25)_\(latestSample.pm10)"
            
            // Strip the timestamp off the incoming footprint to compare pure data values
            // Footprint format: "timestamp_pm1_pm25_pm10" -> split by "_" and drop the timestamp element
            let footprintcomponents = footprint.components(separatedBy: "_")
            if footprintcomponents.count >= 4 {
                let incomingValuesOnly = "\(footprintcomponents[1])_\(footprintcomponents[2])_\(footprintcomponents[3])"
                return latestValuesOnly == incomingValuesOnly
            }
            
            return false
        } catch {
            AppLogger.writeLog("⚠️ SwiftData fetch error during deduplication: \(error)")
            return false
        }
    }
    
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

