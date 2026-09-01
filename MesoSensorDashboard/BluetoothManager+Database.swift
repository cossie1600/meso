//
//  BluetoothManager+Database.swift
//  MesoSensorDashboard
//

import Foundation
import SwiftData

// MARK: - Database Helpers
extension BluetoothManager {
    @MainActor
    func databaseAlreadyContains(footprint: String) -> Bool {
        guard let container = self.modelContainer else { return false }
        
        var descriptor = FetchDescriptor<DB_PMSample>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        
        do {
            let context = container.mainContext
            let recentSamples = try context.fetch(descriptor)
            
            guard let latestSample = recentSamples.first else {
                return false
            }
            
            let latestValuesOnly = "\(latestSample.pm1)_\(latestSample.pm25)_\(latestSample.pm10)"
            
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
    
    @MainActor
    func saveToSQLite(_ packet: IncomingPacket) {
        guard let container = self.modelContainer else {
            AppLogger.writeLog("Error: ModelContainer not injected into BluetoothManager.")
            return
        }
        
        let context = container.mainContext
        let newSample = DB_PMSample(
            timestamp: Date(),
            pm1: packet.pm1,
            pm25: packet.pm25,
            pm10: packet.pm10
        )
        
        context.insert(newSample)
        
        do {
            try context.save()
            AppLogger.writeLog("Successfully saved PM sample to Main Context! (PM2.5: \(packet.pm25))")
        } catch {
            AppLogger.writeLog("Failed to save PM context: \(error)")
        }
    }
    
    @MainActor
    func saveMesoNoseToDatabase(_ sample: MesoNoseSample) {
        guard let container = self.modelContainer else {
            AppLogger.writeLog("Error: ModelContainer not injected into BluetoothManager for Meso Nose save.")
            return
        }
        
        let context = container.mainContext
        let dbRecord = DB_MesoNoseSample(
            timestamp: Date(),
            temp: sample.temp,
            humidity: sample.humidity,
            pressure: sample.pressure,
            voc: sample.voc,
            breathDropDelta: sample.breathDropDelta,
            breathMin: sample.breathMin,
            ptcResult: sample.ptcResult
        )
        
        context.insert(dbRecord)
        
        do {
            try context.save()
            AppLogger.writeLog("✅ Successfully saved Meso Nose sample to disk [VOC: \(sample.voc), PTC: \(sample.ptcResult)]")
        } catch {
            AppLogger.writeLog("❌ SwiftData Meso Nose Save Error: \(error.localizedDescription)")
        }
    }

    @MainActor
    func fetchHistoricalMesoNoseData() {
        guard let container = self.modelContainer else { return }
        
        var descriptor = FetchDescriptor<DB_MesoNoseSample>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        
        do {
            let context = container.mainContext
            let dbRecords = try context.fetch(descriptor)
            
            self.mesoNoseSamples = dbRecords.map { db in
                MesoNoseSample(
                    timestamp: db.timestamp,
                    temp: db.temp,
                    humidity: db.humidity,
                    pressure: db.pressure,
                    voc: db.voc,
                    breathDropDelta: db.breathDropDelta,
                    breathMin: db.breathMin,
                    ptcResult: db.ptcResult
                )
            }
            AppLogger.writeLog("Hydrated \(self.mesoNoseSamples.count) historical Meso Nose samples with exact timestamps from disk.")
        } catch {
            AppLogger.writeLog("❌ Failed to fetch Meso Nose samples: \(error)")
        }
    }
}
