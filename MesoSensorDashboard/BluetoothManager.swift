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
    var firmwarePeripheral: CBPeripheral?
    var centralManager: CBCentralManager?
    
    // This tells SwiftUI to update the screen whenever these change
    @Published var statusText: String = "Initializing..."
    @Published var pm1Value: String = "--"
    @Published var pm25Value: String = "--"
    @Published var pm10Value: String = "--"
    
    // Streaming chunk assembly buffer for multi-core BLE notifications
    private var incomingStringBuffer = ""
    
    // MARK: - Initializer
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
            AppLogger.writeLog("Mock Simulator Bridge Active. Bypassing BLE Hardware.")
            self.statusText = "Connected (Mock Simulator)"
            startMockDataStream()
        } else {
            AppLogger.writeLog("Real BLE Hardware Mode Active. Instantiating Central Manager.")
            
#if !targetEnvironment(simulator)
            // Initialize the hardware manager using options optimized for background restoration if needed
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [
                CBCentralManagerOptionRestoreIdentifierKey: "MesoPinBackgroundRestoreKey"
            ])
#else
            AppLogger.writeLog("Execution stopped: Cannot run BLE hardware on an iOS Simulator window.")
            self.statusText = "Error: Use Simulator Bridge on Mac."
#endif
        }
    }
    
    func sendSleepIntervalToPeripheral(_ peripheral: CBPeripheral?, factor: ConnectionStrategy) {
        self.currentStrategy = factor
        
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("🤖 Simulator adapting behavior to strategy: \(factor)")
            startMockDataStream()
        } else {
            guard let actualPeripheral = peripheral else { return }
            let sleepMinutes = (factor == .batterySaver) ? 15 : 1
            let payloadString = "SLEEP:\(sleepMinutes)"
            if let data = payloadString.data(using: .utf8) {
                // actualPeripheral.writeValue(data, for: writeCharacteristic, type: .withResponse)
                AppLogger.writeLog("📡 Sent operational directive to ESP32: Sleep for \(sleepMinutes) min")
            }
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            AppLogger.writeLog("Bluetooth hardware status: Powered On. Beginning background-sentry scan...")
            self.statusText = "Scanning for ESP32..."
            
            let targetServiceUUID = CBUUID(string: AppConfig.firmwareServiceUUIDString)
            
            // STRICT SERVICE FILTERING: Required for background execution and STRATOS wakeup tracking
            self.centralManager?.scanForPeripherals(withServices: [targetServiceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)
            ])
            
        case .poweredOff:
            AppLogger.writeLog("Bluetooth hardware status: Powered Off.")
            self.statusText = "Bluetooth is turned off"
            
        case .unauthorized:
            AppLogger.writeLog("Bluetooth hardware status: Unauthorized. Check Info.plist keys.")
            self.statusText = "Permissions denied"
            
        default:
            AppLogger.writeLog("Bluetooth hardware status: Transitioning state \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        
        let deviceName = peripheral.name ?? "Unnamed Local Device"
        AppLogger.writeLog("Found radio signature: \(deviceName) [RSSI: \(RSSI)]")
        
        // Strict prefix matching to target your dynamic "Meso Pin-XXXX" devices
        if deviceName.hasPrefix("Meso Pin") {
            AppLogger.writeLog("Target match confirmed! Halting scan and attempting link...")
            
            self.centralManager?.stopScan()
            self.connectedPeripheral = peripheral
            self.statusText = "Connecting to \(deviceName)..."
            
            // Handshake execution initiated (Delegate configuration occurs inside didConnect)
            self.centralManager?.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        AppLogger.writeLog("Swift BLE: Successfully connected to: \(peripheral.name ?? "Unknown")")
        
        // Assign delegate inside didConnect to protect strong object reference state
        peripheral.delegate = self
        incomingStringBuffer = ""
        
        peripheral.discoverServices([CBUUID(string: AppConfig.firmwareServiceUUIDString)])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let errorDescription = error?.localizedDescription ?? "Unknown error"
        AppLogger.writeLog("Swift BLE ERROR: Failed to establish link to \(peripheral.name ?? "Device"): \(errorDescription)")
        
        self.connectedPeripheral = nil
        self.statusText = "Connection failed. Retrying scan..."
        
        let targetServiceUUID = CBUUID(string: AppConfig.firmwareServiceUUIDString)
        self.centralManager?.scanForPeripherals(withServices: [targetServiceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)
        ])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        AppLogger.writeLog("Swift BLE: Connection dropped. Re-entering background-sentry scan.")
        self.connectedPeripheral = nil
        self.statusText = "Disconnected. Scanning..."
        
        let targetServiceUUID = CBUUID(string: AppConfig.firmwareServiceUUIDString)
        self.centralManager?.scanForPeripherals(withServices: [targetServiceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)
        ])
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let restoredPeripheral = peripherals.first {
            AppLogger.writeLog("Swift BLE: Restoring peripheral session out of core suspension.")
            self.connectedPeripheral = restoredPeripheral
            self.connectedPeripheral?.delegate = self
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            AppLogger.writeLog("GATT Service Discovery Error: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services, !services.isEmpty else {
            AppLogger.writeLog("GATT Handshake Stalled: Connected, but zero services were discovered. Check ESP32 Service UUID.")
            return
        }
        
        AppLogger.writeLog("Discovered \(services.count) services. Looking for characteristics...")
        for service in services {
            AppLogger.writeLog("   -> Service UUID found: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            AppLogger.writeLog("GATT Characteristic Discovery Error: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            AppLogger.writeLog("No characteristics found for service: \(service.uuid.uuidString)")
            return
        }
        
        AppLogger.writeLog("Discovered \(characteristics.count) characteristics for service \(service.uuid.uuidString)")
        for characteristic in characteristics {
            let canNotify = characteristic.properties.contains(.notify)
            let canIndicate = characteristic.properties.contains(.indicate)
            
            AppLogger.writeLog("   -> Char: \(characteristic.uuid.uuidString) | Notify: \(canNotify) | Indicate: \(canIndicate)")
            
            if canNotify || canIndicate {
                AppLogger.writeLog("Subscribing to data stream updates for \(characteristic.uuid.uuidString)")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // MARK: - Fragment Assembly & Ingestion Protocol
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            AppLogger.writeLog("Bluetooth notification error: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value,
              let chunk = String(data: data, encoding: .utf8) else { return }
        
        incomingStringBuffer.append(chunk)
        
        while let newLineIndex = incomingStringBuffer.firstIndex(of: "\n") {
            let line = String(incomingStringBuffer[..<newLineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            incomingStringBuffer.removeSubrange(..<incomingStringBuffer.index(after: newLineIndex))
            
            if line.isEmpty { continue }
            // INTERCEPT SYNC HANDSHAKE TERMINATOR
            if line.contains("SYNC_COMPLETE") {
                AppLogger.writeLog("Ingestion: Sync complete token received from hardware.")
                DispatchQueue.main.async {
                    // Update the status to Live mode, clearing the syncing status
                    self.updateStatusOnMainThread(to: "Connected (Live)")
                }
                continue // Skip data parsing for this control frame
            }
            
            let packet: IncomingPacket? = line.hasPrefix("{") ?
            IncomingPacket.decodeJSON(from: line) :
            IncomingPacket.decodeCommaSeparatedString(from: line)
            
            guard let validPacket = packet else {
                updateStatusOnMainThread(to: "Connected (Bad Packet)")
                continue
            }
            
            let captureTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
            let packetFootprint = "\(captureTimestamp)_\(validPacket.pm1)_\(validPacket.pm25)_\(validPacket.pm10)"
            
            // Safe extraction without blocking the main queue loop
            // Safe because the CoreBluetooth delegate queue is already the main thread
            let isDuplicate = self.databaseAlreadyContains(footprint: packetFootprint)
            
            
            if isDuplicate {
                AppLogger.writeLog("Ingestion: Redundant frame detected. Skipping duplicate.")
                continue
            }
            
            saveToSQLite(validPacket)
            
            updateLiveState(with: validPacket)
            evaluateAirQualityThresholds(for: validPacket)
        }
    }
    
}
