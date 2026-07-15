//
//  IncomingPacket.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/14/26.
//
import Foundation

struct IncomingPacket: Decodable {
    let t: UInt64
    let pm1: Double
    let pm25: Double
    let pm10: Double
    
    // MARK: - Decoders
    
    /// Parses raw JSON strings into an IncomingPacket
    static func decodeJSON(from jsonString: String) -> IncomingPacket? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let decodedPacket = try JSONDecoder().decode(IncomingPacket.self, from: jsonData)
            
            guard decodedPacket.pm1 >= 0.0 &&
                    decodedPacket.pm25 >= 0.0 &&
                    decodedPacket.pm10 >= 0.0 else {
                AppLogger.writeLog("Dropped JSON Packet: Hardware error code detected (\(decodedPacket.pm1), \(decodedPacket.pm25), \(decodedPacket.pm10))")
                return nil
            }
            
            return decodedPacket
        } catch {
            AppLogger.writeLog("JSON Parse failure: \(error). String raw trace: \(jsonString)")
            return nil
        }
    }
    
    /// Parses raw CSV strings ("1.2,4.5,8.1") into an IncomingPacket
    static func decodeCommaSeparatedString(from dataString: String) -> IncomingPacket? {
        let components = dataString.components(separatedBy: ",")
        
        guard components.count == 3 else {
            AppLogger.writeLog("Invalid packet structure. Expected 3 elements, got \(components.count)")
            return nil
        }
        
        guard let pm1 = Double(components[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let pm25 = Double(components[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              let pm10 = Double(components[2].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            AppLogger.writeLog("Failed to convert string components to Double values.")
            return nil
        }
        
        guard pm1 >= 0.0 && pm25 >= 0.0 && pm10 >= 0.0 else {
            AppLogger.writeLog("Dropped packet: Hardware reporting negative error codes (\(pm1), \(pm25), \(pm10))")
            return nil
        }
        
        return IncomingPacket(t: 0, pm1: pm1, pm25: pm25, pm10: pm10)
    }
    
    var isCoarseDustOrAllergenProfileActive: Bool {
        // Prevent division by zero if the sensor reads absolute zero for PM10
        guard pm10 > 0 else { return false }
        
        // 1. Calculate if coarse particles make up 70% or more of the PM10 mass
        let coarseRatio = (pm10 - pm25) / pm10
        let matchesCoarseRatio = coarseRatio >= AppConfig.coarseParticleAlertThreshold
        
        // 2. Check if ultra-fine particles are safely low
        let matchesFineLimit = pm1 < AppConfig.ultraFineParticleAlertThreshold
        
        // Both conditions must pass to match the profile signature
        return matchesCoarseRatio && matchesFineLimit
    }
}
