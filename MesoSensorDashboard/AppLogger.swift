//
//  AppLogger.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/11/26.
//

import Foundation

struct AppLogger {
    
    /// Dynamically switches the destination directory depending on the environment
    private static var logFileURL: URL? {
        // Prevent resolving URLs if logging is turned off
        guard isLoggingEnabled else { return nil }
        
        if AppConfig.useMockSimulatorBridge {
            let userName = NSUserName()
            let macDownloadsPath = "/Users/\(userName)/Downloads"
            return URL(fileURLWithPath: macDownloadsPath).appendingPathComponent(AppConfig.applogFileName)
        }
        else {
            // 📱 PHYSICAL IPHONE RUN: Standard secure sandbox documents folder
            let fileManager = FileManager.default
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return documentsDirectory.appendingPathComponent(AppConfig.applogFileName)
        }
    }
    
    /// Appends a new line of text data to the file on disk
    static func writeLog(_ message: String) {
        // 🛑 EARLY RETURN: If logging is disabled, do absolutely nothing
        guard isLoggingEnabled else { return }
        
        guard let url = logFileURL else { return }
        
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logLine = "\(timestamp), \(message)\n"
        guard let data = logLine.data(using: .utf8) else { return }
        
        if FileManager.default.fileExists(atPath: url.path) {
            if let fileHandle = try? FileHandle(forWritingTo: url) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            let header = "Timestamp, Message\n"
            let initialContent = header + logLine
            if let initialData = initialContent.data(using: .utf8) {
                try? initialData.write(to: url, options: .atomic)
            }
        }
    }
}
