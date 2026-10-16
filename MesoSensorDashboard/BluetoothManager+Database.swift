//
//  BluetoothManager+Database.swift
//  MesoSensorDashboard
//

import Foundation
import SwiftData

// MARK: - SwiftData Persistence Helpers

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

            let footprintComponents = footprint.components(separatedBy: "_")
            if footprintComponents.count >= 4 {
                let incomingValuesOnly = "\(footprintComponents[1])_\(footprintComponents[2])_\(footprintComponents[3])"
                return latestValuesOnly == incomingValuesOnly
            }

            return false
        } catch {
            AppLogger.writeLog("SwiftData fetch error during deduplication: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    func saveToSQLite(_ packet: IncomingPacket) {
        guard let container = self.modelContainer else {
            AppLogger.writeLog(BMLogMessages.inMemoryDbFailed("ModelContainer not injected"))
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
            AppLogger.writeLog("Failed to save PM context: \(error.localizedDescription)")
        }
    }

    // BluetoothManager+Database.swift

    @MainActor
    func saveMesoNoseToDatabase(_ sample: MesoNoseSample) {
        guard let container = self.modelContainer else {
            AppLogger.writeLog(BMLogMessages.inMemoryDbFailed("ModelContainer not injected"))
            return
        }
        
        let context = container.mainContext

        // Deduplication Guard: Consider result classification, breath drop delta, and timestamp proximity (within 60 seconds)
        if sample.breathDropDelta > MesoNoseConstants.zeroDouble {
            var descriptor = FetchDescriptor<DB_MesoNoseSample>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 1

            if let latestDBRecord = try? context.fetch(descriptor).first {
                let timeInterval = abs(sample.timestamp.timeIntervalSince(latestDBRecord.timestamp))
                let isDuplicateResult = latestDBRecord.ptcResult == sample.ptcResult &&
                                       abs(latestDBRecord.breathDropDelta - sample.breathDropDelta) < 0.1 &&
                                       timeInterval < 60.0 // Ignore duplicate result re-broadcasts within 60s
                
                if isDuplicateResult {
                    AppLogger.writeLog("Skipped duplicate Meso Nose result save [PTC: \(sample.ptcResult), Delta Time: \(timeInterval)s]")
                    return
                }
            }
        }

        let dbRecord = DB_MesoNoseSample(
            timestamp: sample.timestamp, // Preserves exact historical sample timestamp
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
            AppLogger.writeLog("Successfully saved Meso Nose sample to disk [VOC: \(sample.voc), PTC: \(sample.ptcResult)]")
        } catch {
            AppLogger.writeLog("SwiftData Meso Nose Save Error: \(error.localizedDescription)")
        }
    }
}

extension BluetoothManager {

    @MainActor
    func fetchHistoricalMesoNoseData(limit: Int? = nil) {
        guard let container = self.modelContainer else { return }

        // Default to initial batch limit of 10
        let targetLimit = limit ?? currentFetchLimit
        self.currentFetchLimit = targetLimit

        var descriptor = FetchDescriptor<DB_MesoNoseSample>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = targetLimit // Executes limit = 10 on boot

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
            AppLogger.writeLog("Fetched \(self.mesoNoseSamples.count) historical records from SQLite (Limit: \(targetLimit)).")
        } catch {
            AppLogger.writeLog("Failed to fetch Meso Nose samples: \(error.localizedDescription)")
        }
    }

    /// Fetches the next 10 historical records directly from SQLite
    @MainActor
    func loadMoreHistoricalData() {
        let newLimit = currentFetchLimit + BMConstants.pageSizeIncrement
        fetchHistoricalMesoNoseData(limit: newLimit)
    }
}
