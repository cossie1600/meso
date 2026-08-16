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
    @Published var alertMessage: String? = nil
    @Published var alertTheme: AlertVisualTheme = .none
    
    // Multi-Device Management (Retains references to both Meso Pin and Meso Nose)
    @Published var connectedPeripherals: [UUID: CBPeripheral] = [:]
    @Published var writeCharacteristics: [UUID: CBCharacteristic] = [:]
    
    // Legacy single-peripheral accessors for existing protocol extensions
    var connectedPeripheral: CBPeripheral? {
        connectedPeripherals.values.first
    }
    
    var firmwarePeripheral: CBPeripheral? {
        get {
            return connectedPeripherals.values.first { $0.name?.hasPrefix(AppConfig.bluetoothDeviceName) == true }
                ?? connectedPeripherals.values.first
        }
        set {
            if let newValue = newValue {
                connectedPeripherals[newValue.identifier] = newValue
            }
        }
    }
    
    var writeCharacteristic: CBCharacteristic? {
        get {
            if let pin = firmwarePeripheral {
                return writeCharacteristics[pin.identifier]
            }
            return writeCharacteristics.values.first
        }
        set {
            if let pin = firmwarePeripheral, let newValue = newValue {
                writeCharacteristics[pin.identifier] = newValue
            }
        }
    }
    
    var mockDataTimer: Timer?
    var modelContainer: ModelContainer?
    var centralManager: CBCentralManager?
    
    // Meso Nose (BME688) Historical In-Memory Stream
    @Published var mesoNoseSamples: [MesoNoseSample] = []
    
    // Live UI State Properties
    @Published var statusText: String = "Initializing..."
    @Published var pm1Value: String = "--"
    @Published var pm25Value: String = "--"
    @Published var pm10Value: String = "--"
    
    // Per-device streaming chunk assembly buffers
    private var incomingBuffers: [UUID: String] = [:]
    
    // MARK: - Initializer
    init(modelContainer: ModelContainer? = nil) {
        if let container = modelContainer {
            self.modelContainer = container
        } else {
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                self.modelContainer = try ModelContainer(for: DB_PMSample.self, configurations: config)
                AppLogger.writeLog("🧠 In-Memory Test Database Container Initialized.")
            } catch {
                self.modelContainer = nil
                AppLogger.writeLog("❌ Failed to create temporary database container: \(error)")
            }
        }
        
        if AppConfig.forceInitialEmergencyState {
            self.currentStrategy = .emergency
            self.alertMessage = "DEBUG: Forced Emergency Active"
        } else {
            self.currentStrategy = .batterySaver
        }
        
        super.init()
        
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("Mock Simulator Bridge Active. Bypassing BLE Hardware.")
            self.statusText = "Connected (Mock Simulator)"
            startMockDataStream()
        } else {
            AppLogger.writeLog("Real BLE Hardware Mode Active. Instantiating Central Manager.")
            
#if !targetEnvironment(simulator)
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [
                CBCentralManagerOptionRestoreIdentifierKey: "MesoPinBackgroundRestoreKey"
            ])
#else
            AppLogger.writeLog("Execution stopped: Cannot run BLE hardware on an iOS Simulator window.")
            self.statusText = "Error: Use Simulator Bridge on Mac."
#endif
        }
    }
    
    // MARK: - Directives & Commands
    func sendSleepIntervalToPeripheral(_ peripheral: CBPeripheral?, factor: ConnectionStrategy) {
        self.currentStrategy = factor
        
        if AppConfig.useMockSimulatorBridge {
            AppLogger.writeLog("🤖 Simulator adapting behavior to strategy: \(factor)")
            startMockDataStream()
        } else {
            guard let target = peripheral ?? firmwarePeripheral ?? connectedPeripherals.values.first,
                  let char = writeCharacteristics[target.identifier] ?? writeCharacteristic else { return }
            
            let sleepMinutes = (factor == .batterySaver) ? 15 : 1
            let payloadString = "SLEEP:\(sleepMinutes)"
            if let data = payloadString.data(using: .utf8) {
                target.writeValue(data, for: char, type: .withResponse)
                AppLogger.writeLog("📡 Sent operational directive to \(target.name ?? "Device"): Sleep for \(sleepMinutes) min")
            }
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            AppLogger.writeLog("Bluetooth hardware status: Powered On. Beginning dual-device scan...")
            self.statusText = "Scanning for Meso Sensors..."
            startScanning()
            
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
    
    /// Scans for all nearby BLE devices (withServices: nil) so firmware with non-advertised UUIDs is discovered.
    func startScanning() {
        guard centralManager?.state == .poweredOn else { return }
        
        AppLogger.writeLog("📡 Starting BLE peripheral scan for Meso Pin & Meso Nose...")
        centralManager?.scanForPeripherals(
            withServices: nil, // Discover all devices; filter by name/UUID in didDiscover
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        
        let deviceName = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unnamed Local Device"
        
        // Match names defined in AppConfig
        let isMesoPin = deviceName.hasPrefix(AppConfig.bluetoothDeviceName)
        let isMesoNose = deviceName.hasPrefix(AppConfig.mesoNoseBluetoothName)
        
        if isMesoPin || isMesoNose {
            let deviceID = peripheral.identifier
            
            // Connect only if not already tracked
            if connectedPeripherals[deviceID] == nil {
                AppLogger.writeLog("🎯 Target match found: \(deviceName) [ID: \(deviceID)] RSSI: \(RSSI)")
                
                connectedPeripherals[deviceID] = peripheral
                incomingBuffers[deviceID] = ""
                peripheral.delegate = self
                
                DispatchQueue.main.async {
                    self.statusText = "Connecting to \(deviceName)..."
                }
                
                self.centralManager?.connect(peripheral, options: nil)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let deviceName = peripheral.name ?? "Unknown Device"
        AppLogger.writeLog("✅ Swift BLE: Successfully connected to: \(deviceName)")
        
        peripheral.delegate = self
        incomingBuffers[peripheral.identifier] = ""
        
        // Discover services without filtering UUIDs upfront to guarantee discovery
        peripheral.discoverServices(nil)
        
        DispatchQueue.main.async {
            let count = self.connectedPeripherals.count
            self.statusText = "Connected (\(count) Device\(count > 1 ? "s" : ""))"
        }
        
        // Keep scanning so the second device can be discovered and connected
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let errorDescription = error?.localizedDescription ?? "Unknown error"
        let deviceName = peripheral.name ?? "Device"
        AppLogger.writeLog("Swift BLE ERROR: Failed to establish link to \(deviceName): \(errorDescription)")
        
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        writeCharacteristics.removeValue(forKey: peripheral.identifier)
        incomingBuffers.removeValue(forKey: peripheral.identifier)
        
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let deviceName = peripheral.name ?? "Device"
        AppLogger.writeLog("Swift BLE: Connection dropped for \(deviceName). Re-entering scan.")
        
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        writeCharacteristics.removeValue(forKey: peripheral.identifier)
        incomingBuffers.removeValue(forKey: peripheral.identifier)
        
        DispatchQueue.main.async {
            if self.connectedPeripherals.isEmpty {
                self.statusText = "Disconnected. Scanning..."
            } else {
                self.statusText = "Connected (\(self.connectedPeripherals.count) Active)"
            }
        }
        
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for restoredPeripheral in peripherals {
                AppLogger.writeLog("Swift BLE: Restoring peripheral session: \(restoredPeripheral.name ?? "Device")")
                connectedPeripherals[restoredPeripheral.identifier] = restoredPeripheral
                restoredPeripheral.delegate = self
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            AppLogger.writeLog("GATT Service Discovery Error: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services, !services.isEmpty else {
            AppLogger.writeLog("GATT Handshake Stalled: Zero services discovered for \(peripheral.name ?? "Device").")
            return
        }
        
        AppLogger.writeLog("Discovered \(services.count) services for \(peripheral.name ?? "Device"). Discovering characteristics...")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            AppLogger.writeLog("GATT Characteristic Discovery Error: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            let canNotify = characteristic.properties.contains(.notify)
            let canIndicate = characteristic.properties.contains(.indicate)
            let canWrite = characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
            
            if canWrite {
                self.writeCharacteristics[peripheral.identifier] = characteristic
                AppLogger.writeLog("  -> Cached Write Characteristic [\(peripheral.name ?? "Device")]: \(characteristic.uuid.uuidString)")
            }
            
            if canNotify || canIndicate {
                AppLogger.writeLog("  -> Subscribing to Notification Stream [\(peripheral.name ?? "Device")]: \(characteristic.uuid.uuidString)")
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
        
        let deviceID = peripheral.identifier
        incomingBuffers[deviceID, default: ""].append(chunk)
        
        while let buffer = incomingBuffers[deviceID], let newLineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newLineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            incomingBuffers[deviceID]?.removeSubrange(..<buffer.index(after: newLineIndex))
            
            if line.isEmpty { continue }
            
            // 1. Intercept Sync Token
            if line.contains("SYNC_COMPLETE") {
                AppLogger.writeLog("Ingestion: Sync complete token received.")
                DispatchQueue.main.async {
                    self.updateStatusOnMainThread(to: "Connected (Live)")
                }
                continue
            }
            
            // 2. Route Meso Nose (BME688) Telemetry JSON
            if line.isMesoNosePayload {
                AppLogger.writeLog("Ingestion: Meso Nose payload -> \(line)")
                handleMesoNosePacket(line)
                continue
            }
            
            // 3. Fallback: Meso Pin (BMV080 Air Quality) Parsing
            let packet: IncomingPacket? = line.hasPrefix("{") ?
            IncomingPacket.decodeJSON(from: line) :
            IncomingPacket.decodeCommaSeparatedString(from: line)
            
            guard let validPacket = packet else {
                updateStatusOnMainThread(to: "Connected (Bad Packet)")
                continue
            }
            
            let captureTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
            let packetFootprint = "\(captureTimestamp)_\(validPacket.pm1)_\(validPacket.pm25)_\(validPacket.pm10)"
            
            let isDuplicate = self.databaseAlreadyContains(footprint: packetFootprint)
            if isDuplicate { continue }
            
            saveToSQLite(validPacket)
            updateLiveState(with: validPacket)
            evaluateAirQualityThresholds(for: validPacket)
        }
    }
}
