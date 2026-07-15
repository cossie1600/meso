//
//  AppLogger.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/11/26.
//

import Foundation

struct AppLogger {
    
    private static var logFileURL: URL? {
        guard AppConfig.isLoggingEnabled else { return nil }
        
        if AppConfig.useMockSimulatorBridge {
            let userName = NSUserName()
            let macDownloadsPath = "/Users/\(userName)/Downloads"
            return URL(fileURLWithPath: macDownloadsPath).appendingPathComponent(AppConfig.applogFileName)
        } else {
            let fileManager = FileManager.default
            guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return documentsDirectory.appendingPathComponent(AppConfig.applogFileName)
        }
    }
    
    static func writeLog(_ message: String) {
        print("📝 [Log] \(message)")
        guard AppConfig.isLoggingEnabled else { return }
        guard let url = logFileURL else { return }
        
        // 🧼 AUTO-PRUNE: Reads directly from AppConfig now!
        if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = fileAttributes[.size] as? Int64 {
            if fileSize > AppConfig.maxLogSizeInBytes {
                print("🧹 [Logger] Log file exceeded limit. Rotating and clearing slate...")
                try? FileManager.default.removeItem(at: url)
            }
        }
        
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
