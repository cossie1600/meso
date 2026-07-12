//
//  MesoSensorDashboardApp.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import SwiftUI

@main
struct MesoSensorDashboardApp: App {
    init() {
            // 1. Locate the secure document path (Same layout on Mac & iPhone)
            if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let logPath = docsURL.appendingPathComponent(AppConfig.applogFileName).path
                
                // 2. 🖥️ MAC SIMULATOR HARDCODED SHORTCUT
                #if targetEnvironment(simulator)
                UIPasteboard.general.string = logPath
                #endif
            }
            
            // 3. 📱 INITIAL WRITE ACTION FOR REAL IPHONE
            // Running a write command on boot guarantees the file structure initializes
            // inside the iOS directory tree right away.
            AppLogger.writeLog("System Initialized.")
        }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
