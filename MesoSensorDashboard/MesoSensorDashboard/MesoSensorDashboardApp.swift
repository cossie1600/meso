//
//  MesoSensorDashboardApp.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import SwiftUI
import SwiftData

@main
struct MesoSensorDashboardApp: App {
    let container: ModelContainer
    
    // 1. Declare the StateObject without giving it an immediate value yet
    @StateObject private var bleManager: BluetoothManager
    
    init() {
        do {
            // 2. Spin up your physical SwiftData database container
            let mainContainer = try ModelContainer(for: DB_PMSample.self)
            self.container = mainContainer
            
            // 3. Generate the active operational context
            let context = ModelContext(mainContainer)
            
            // 4. Inject the context right into the BluetoothManager initializer
            // Swift requires backing properties (_bleManager) to be assigned manually inside an init block
            self._bleManager = StateObject(wrappedValue: BluetoothManager(modelContainer: mainContainer))
            
            #if targetEnvironment(simulator)
            if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let logPath = docsURL.appendingPathComponent(AppConfig.applogFileName).path
                UIPasteboard.general.string = logPath
                AppLogger.writeLog("📋 Simulator CSV Log Path copied to Clipboard!")
            }
            #endif
            
        } catch {
            fatalError("CRITICAL: Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(bleManager)
                .modelContainer(container)
                .onAppear {
                    // Run the database pruning routine on launch!
                    let context = ModelContext(container)
                    deleteOldReadings(context: context)
                }
        }
    }
    
    // MARK: - Database Pruning Logic
    private func deleteOldReadings(context: ModelContext) {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(
            byAdding: .day,
            value: -AppConfig.databaseRetentionDays,
            to: Date()
        ) else {
            AppLogger.writeLog("❌ Error: Could not calculate database cutoff date.")
            return
        }
        
        do {
            try context.delete(
                model: DB_PMSample.self,
                where: #Predicate { $0.timestamp < cutoffDate }
            )
            try context.save()
            AppLogger.writeLog("🧹 Database cleanup complete. Kept only the last \(AppConfig.databaseRetentionDays) days of readings.")
        } catch {
            AppLogger.writeLog("❌ Failed to auto-prune database: \(error.localizedDescription)")
        }
    }
}
