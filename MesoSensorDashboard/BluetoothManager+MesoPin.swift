//
//  BluetoothManager+MesoPin.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/19/26.
//

import Foundation
import CoreBluetooth
import SwiftData

extension BluetoothManager {
    
    /// Returns the specific CBPeripheral instance connected for Meso Pin
    var mesoPinPeripheral: CBPeripheral? {
        return connectedPeripherals.values.first { $0.name?.hasPrefix(AppConfig.bluetoothDeviceName) == true }
            ?? connectedPeripherals.values.first
    }
    
    /// Returns the cached write characteristic associated with the Meso Pin peripheral
    var mesoPinWriteCharacteristic: CBCharacteristic? {
        if let pin = mesoPinPeripheral {
            return writeCharacteristics[pin.identifier]
        }
        return writeCharacteristics.values.first
    }
    
    /// Sends operational directives specifically to the Meso Pin peripheral
    func sendSleepIntervalToPeripheral(_ peripheral: CBPeripheral?, factor: ConnectionStrategy) {
        self.currentStrategy = factor
        
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("Simulator adapting behavior to strategy: \(factor)")
            startMockDataStream()
        } else {
            guard let target = peripheral ?? mesoPinPeripheral,
                  let char = writeCharacteristics[target.identifier] ?? mesoPinWriteCharacteristic else { return }
            
            let sleepMinutes = (factor == .batterySaver) ? 15 : 1
            let payloadString = "SLEEP:\(sleepMinutes)"
            if let data = payloadString.data(using: .utf8) {
                target.writeValue(data, for: char, type: .withResponse)
                AppLogger.writeLog("Sent operational directive to \(target.name ?? "Meso Pin"): Sleep for \(sleepMinutes) min")
            }
        }
    }
    
    /// Parses line-delimited or JSON string payloads originating from the Meso Pin sensor
    func parseMesoPinPacket(_ line: String) {
        let packet: IncomingPacket? = line.hasPrefix("{") ?
            IncomingPacket.decodeJSON(from: line) :
            IncomingPacket.decodeCommaSeparatedString(from: line)
        
        guard let validPacket = packet else {
            updateStatusOnMainThread(to: "Connected (Bad Packet)")
            return
        }
        
        let captureTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let packetFootprint = "\(captureTimestamp)_\(validPacket.pm1)_\(validPacket.pm25)_\(validPacket.pm10)"
        
        if self.databaseAlreadyContains(footprint: packetFootprint) { return }
        
        saveToSQLite(validPacket)
        updateLiveState(with: validPacket)
        evaluateAirQualityThresholds(for: validPacket)
    }
}
