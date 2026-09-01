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
    @StateObject private var bluetoothManager: BluetoothManager

    init() {
        do {
            // Explicitly declare both database schemas
            let schema = Schema([
                DB_PMSample.self,
                DB_MesoNoseSample.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            
            let sharedContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.container = sharedContainer
            
            // Inject the created container into BluetoothManager
            _bluetoothManager = StateObject(wrappedValue: BluetoothManager(modelContainer: sharedContainer))
        } catch {
            // Prevent app crash on migration error by falling back to in-memory store
            print("⚠️ SwiftData initialization failed: \(error.localizedDescription). Falling back to temporary store.")
            
            let fallbackSchema = Schema([DB_PMSample.self, DB_MesoNoseSample.self])
            let fallbackConfig = ModelConfiguration(schema: fallbackSchema, isStoredInMemoryOnly: true)
            
            let fallbackContainer = (try? ModelContainer(for: fallbackSchema, configurations: [fallbackConfig]))
                ?? { fatalError("Critical failure: Unable to create SwiftData container.") }()
            
            self.container = fallbackContainer
            _bluetoothManager = StateObject(wrappedValue: BluetoothManager(modelContainer: fallbackContainer))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
        }
        .modelContainer(container)
    }
}
