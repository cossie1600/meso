//
//  BluetoothManager.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//

import Foundation
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, AirQualityManagerProtocol, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    
    // This tells SwiftUI to update the screen whenever these change
    @Published var statusText: String = "Initializing..."
    @Published var pm1Value: String = "--"
    @Published var pm25Value: String = "--"
    @Published var pm10Value: String = "--"
    
    override init() {
        super.init()
        // Starts the iPhone's Bluetooth central system
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // Step 4A: Check if iPhone Bluetooth is turned on
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            statusText = "Scanning for ESP32..."
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            statusText = "Please enable Bluetooth"
        }
    }
    
    // Step 4B: Found a Bluetooth device! Let's check if it's our ESP32
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        // Change "ESP32-BMV080" to match whatever name your ESP32 code broadcasts
        if let name = peripheral.name, name == "Meso Pin" {
            statusText = "Connecting..."
            centralManager.stopScan()
            
            self.esp32Peripheral = peripheral
            self.esp32Peripheral?.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    // Step 4C: Connected! Now find the data channels (Services)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusText = "Connected!"
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
    
    // Step 4E: Catch the packet and split it by commas
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value, let dataString = String(data: data, encoding: .utf8) {
            
            // Split "12,15,30" into an array ["12", "15", "30"]
            let components = dataString.components(separatedBy: ",")
            
            DispatchQueue.main.async {
                if components.count == 3 {
                    self.pm1Value = components[0]
                    self.pm25Value = components[1]
                    self.pm10Value = components[2]
                    self.statusText = "Data Received!"
                } else {
                    // In case it catches a partial or bad packet
                    self.statusText = "Connected (Bad Packet)"
                }
            }
        }
    }
}
