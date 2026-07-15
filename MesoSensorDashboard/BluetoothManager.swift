//
//  BluetoothManager.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation
import CoreBluetooth
import Combine
import SwiftData

enum ConnectionStrategy {
    case batterySaver // 15-minute intervals
    case emergency    // 1-minute tracking interval
}

enum AlertVisualTheme {
    case none
    case fineParticulates  // Smog/Smoke (Blue)
    case allergenProfile   // Pollen/Dust signature (Teal)
    case generalCoarse     // Generic heavy dust (Teal/Slate)
}

class BluetoothManager: NSObject, AirQualityManagerProtocol, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var currentStrategy: ConnectionStrategy
    @Published var connectedPeripheral: CBPeripheral?
    @Published var alertMessage: String? = nil
    @Published var alertTheme: AlertVisualTheme = .none
    var mockDataTimer: Timer?
    var modelContainer: ModelContainer?
    var esp32Peripheral: CBPeripheral?
    var centralManager: CBCentralManager?
    
    // This tells SwiftUI to update the screen whenever these change
    @Published var statusText: String = "Initializing..."
    @Published var pm1Value: String = "--"
    @Published var pm25Value: String = "--"
    @Published var pm10Value: String = "--"
    
    // MARK: - 2. The Initializer (PUT IT RIGHT HERE)
    init(modelContainer: ModelContainer? = nil) {
        if let container = modelContainer {
            self.modelContainer = container
        } else {
            do {
                // Fallback: Safe, temporary in-memory container for Previews/Simulators
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                self.modelContainer = try ModelContainer(for: DB_PMSample.self, configurations: config)
                AppLogger.writeLog("🧠 In-Memory Test Database Container Initialized.")
            } catch {
                self.modelContainer = nil
                AppLogger.writeLog("❌ Failed to create temporary database container: \(error)")
            }
        }
        
        // 1. Decouple initial state selection
        if AppConfig.forceInitialEmergencyState {
            self.currentStrategy = .emergency
            self.alertMessage = "DEBUG: Forced Emergency Active"
        } else {
            self.currentStrategy = .batterySaver
        }
        
        super.init()
        
        // 2. Decouple execution pipeline
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("🤖 Mock Simulator Bridge Active. Bypassing BLE Hardware.")
            self.statusText = "Connected (Mock Simulator)"
            startMockDataStream()
        } else {
            AppLogger.writeLog("📡 Real BLE Hardware Mode Active. Starting Central Manager.")
#if !targetEnvironment(simulator)
            centralManager = CBCentralManager(delegate: self, queue: nil)
#else
            self.statusText = "Error: Cannot run BLE hardware on iOS Simulator."
#endif
        }
    }
    
    func sendSleepIntervalToPeripheral(_ peripheral: CBPeripheral?, factor: ConnectionStrategy) {
        self.currentStrategy = factor
        
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("🤖 Simulator adapting behavior to strategy: \(factor)")
            // Restart the timer with the updated speed (1-minute vs 15-minute emulation pace)
            startMockDataStream()
        } else {
            // Real hardware path
            guard let actualPeripheral = peripheral else { return }
            let sleepMinutes = (factor == .batterySaver) ? 15 : 1
            let payloadString = "SLEEP:\(sleepMinutes)"
            if let data = payloadString.data(using: .utf8) {
                //actualPeripheral.writeValue(data, for: writeCharacteristic, type: .withResponse)
                AppLogger.writeLog("📡 Sent operational directive to ESP32: Sleep for \(sleepMinutes) min")
            }
        }
    }
    
    // Step 4A: Check if iPhone Bluetooth is turned on
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            statusText = "Scanning for ESP32..."
            centralManager?.scanForPeripherals(withServices: nil, options: nil)
        } else {
            statusText = "Please enable Bluetooth"
        }
    }
    
    // Step 4B: Found a Bluetooth device! Let's check if it's our ESP32
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        // Change "ESP32-BMV080" to match whatever name your ESP32 code broadcasts
        if let name = peripheral.name, name == AppConfig.bluetoothDeviceName {
            statusText = "Connecting..."
            centralManager?.stopScan()
            
            self.esp32Peripheral = peripheral
            self.esp32Peripheral?.delegate = self
            centralManager?.connect(peripheral, options: nil)
        }
    }
    
    // Step 4C: Connected! Now find the data channels (Services)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusText = "Connected!"
        self.connectedPeripheral = peripheral
        peripheral.discoverServices(nil)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    // Step 4D: Find the specific text stream (Characteristic) and listen to it
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            // Subscribe to notifications so the ESP32 pushes live dust data automatically
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    // Step 4E: Catch the JSON packet, parse it, and commit it to SQLite
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            AppLogger.writeLog("Bluetooth notification error: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value,
              let dataString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        
        // Create an optional packet reference to hold whichever format resolves
        let packet: IncomingPacket?
        
        // 1. Check the prefix to detect JSON vs. Comma-Separated Values (CSV)
        if dataString.hasPrefix("{") {
            packet = IncomingPacket.decodeJSON(from: dataString)
        } else {
            packet = IncomingPacket.decodeCommaSeparatedString(from: dataString)
        }
        
        // 2. Fallback if both parsing frameworks fail
        guard let validPacket = packet else {
            updateStatusOnMainThread(to: "Connected (Bad Packet)")
            return
        }
        
        // 3. Commit the clean records to SQLite
        saveToSQLite(validPacket)
        
        // 4. Update the live UI strings
        updateLiveState(with: validPacket)
        evaluateAirQualityThresholds(for: validPacket)
        
    }
    
}
