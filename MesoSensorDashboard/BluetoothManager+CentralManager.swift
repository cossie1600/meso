//
//  BluetoothManager+CentralManager.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/14/26.
//

import CoreBluetooth
import Foundation

// MARK: - CBCentralManagerDelegate Implementation

extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            AppLogger.writeLog(BMLogMessages.bluetoothPoweredOn)
            self.statusText = BMConstants.statusScanning
            startScanning()

        case .poweredOff:
            AppLogger.writeLog(BMLogMessages.bluetoothPoweredOff)
            self.statusText = BMConstants.statusPowerOff

        case .unauthorized:
            AppLogger.writeLog(BMLogMessages.bluetoothUnauthorized)
            self.statusText = BMConstants.statusPermissionsDenied

        default:
            AppLogger.writeLog(
                BMLogMessages.bluetoothTransitioningState(
                    central.state.rawValue
                )
            )
        }
    }

    func startScanning() {
        guard centralManager?.state == .poweredOn else { return }

        AppLogger.writeLog(BMLogMessages.startingScan)
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    // BluetoothManager+CentralManager.swift

    func centralManager(
            _ central: CBCentralManager,
            didDiscover peripheral: CBPeripheral,
            advertisementData: [String: Any],
            rssi RSSI: NSNumber
        ) {
            let deviceName = peripheral.name
                ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                ?? BMConstants.defaultUnnamedLocalDevice
            let deviceID = peripheral.identifier
            
            guard RSSI.intValue != BMConstants.invalidRSSI && RSSI.intValue >= BMConstants.proximityRSSIThreshold else {
                AppLogger.writeLog("[BLE SCAN]: Spotted \(deviceName) (\(deviceID)) with weak RSSI \(RSSI) dBm.")
                return
            }
            
            let advertisedServiceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString.lowercased() } ?? []
            let targetServiceUUID = AppConfig.mesoNoseServiceUUIDString.lowercased()
            let hasTargetService = advertisedServiceUUIDs.contains(targetServiceUUID)

            let isMesoPin = deviceName.hasPrefix(AppConfig.bluetoothDeviceName)
            let isMesoNoseName = deviceName.hasPrefix(AppConfig.mesoNoseBluetoothName) || hasTargetService
            let isSavedMesoNose = (savedMesoNoseUUID == deviceID)

            guard isMesoPin || isMesoNoseName || isSavedMesoNose else { return }

            if let existing = connectedPeripherals[deviceID], existing.state == .connected || existing.state == .connecting {
                return
            }

            // 1. Sticky Reconnect to previously saved peripheral
            if isSavedMesoNose {
                AppLogger.writeLog(BMLogMessages.targetMatchFound(deviceName, deviceID))
                connectToPeripheral(peripheral, deviceName: deviceName)
                return
            }

            // 2. Active Pairing OR Automatic First-Time Proximity Pairing
            if isMesoNoseName && (isPairingModeActive || savedMesoNoseUUID == nil) {
                guard RSSI.intValue != BMConstants.invalidRSSI && RSSI.intValue >= BMConstants.proximityRSSIThreshold else { return }

                if savedMesoNoseUUID != deviceID {
                    AppLogger.writeLog(BMLogMessages.updatedSavedMesoNoseUUID(deviceID))
                    self.savedMesoNoseUUID = deviceID
                }

                AppLogger.writeLog(BMLogMessages.pairingMatchFound(deviceName, deviceID, RSSI))
                connectToPeripheral(peripheral, deviceName: deviceName)
                return
            }
            
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            connectionTimeoutTimer?.invalidate()
            connectionTimeoutTimer = nil

            let deviceName = peripheral.name ?? BMConstants.defaultUnknownDevice
            AppLogger.writeLog(BMLogMessages.connectedTo(deviceName))

            self.isPairingModeActive = false
            peripheral.delegate = self
            incomingBuffers[peripheral.identifier] = BMConstants.emptyString
            peripheral.discoverServices(nil)

            DispatchQueue.main.async {
                let count = self.connectedPeripherals.count
                self.statusText = BMConstants.statusConnectedDevicesCount(count)
            }

            startScanning()
        }

        func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            connectionTimeoutTimer?.invalidate()
            connectionTimeoutTimer = nil

            let errorDescription = error?.localizedDescription ?? BMConstants.defaultUnknownDevice
            let deviceName = peripheral.name ?? BMConstants.defaultDeviceName
            AppLogger.writeLog(BMLogMessages.failedToConnect(deviceName, errorDescription))

            connectedPeripherals.removeValue(forKey: peripheral.identifier)
            writeCharacteristics.removeValue(forKey: peripheral.identifier)
            incomingBuffers.removeValue(forKey: peripheral.identifier)

            startScanning()
        }

        func connectToPeripheral(_ peripheral: CBPeripheral, deviceName: String) {
            connectedPeripherals[peripheral.identifier] = peripheral
            incomingBuffers[peripheral.identifier] = BMConstants.emptyString
            peripheral.delegate = self

            DispatchQueue.main.async {
                self.statusText = BMConstants.statusConnectingTo(deviceName)
            }

            connectionTimeoutTimer?.invalidate()
            connectionTimeoutTimer = Timer.scheduledTimer(
                withTimeInterval: BMConstants.connectionTimeoutSeconds,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                if peripheral.state == .connecting {
                    AppLogger.writeLog(BMLogMessages.connectionTimedOut(deviceName, BMConstants.connectionTimeoutSeconds))
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                    self.connectedPeripherals.removeValue(forKey: peripheral.identifier)
                    self.writeCharacteristics.removeValue(forKey: peripheral.identifier)

                    DispatchQueue.main.async {
                        self.statusText = BMConstants.statusDisconnectedScanning
                    }
                    self.startScanning()
                }
            }

            self.centralManager?.connect(peripheral, options: nil)
        }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName
        AppLogger.writeLog(BMLogMessages.connectionDropped(deviceName))

        if peripheral.identifier == self.mesoPinPeripheral?.identifier {
            DispatchQueue.main.async {
                self.pm1Value = BMConstants.emptyString
                self.pm25Value = BMConstants.emptyString
                self.pm10Value = BMConstants.emptyString
            }
        }
        if peripheral.identifier == self.mesoNosePeripheral?.identifier {
            DispatchQueue.main.async {
                self.mesoNoseBattery = nil
                self.isExternalPower = false
            }                   
        }

        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        writeCharacteristics.removeValue(forKey: peripheral.identifier)
        incomingBuffers.removeValue(forKey: peripheral.identifier)

        DispatchQueue.main.async {
            if self.connectedPeripherals.isEmpty {
                self.mesoNoseBattery = nil
                self.isExternalPower = false
                self.statusText = BMConstants.statusDisconnectedScanning
            } else {
                self.statusText = BMConstants.statusConnectedActiveCount(
                    self.connectedPeripherals.count
                )
            }
        }

        // Resume BLE scanning immediately to auto-reconnect as soon as target returns to range
        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey]
            as? [CBPeripheral]
        {
            for restoredPeripheral in peripherals {
                let name =
                    restoredPeripheral.name ?? BMConstants.defaultDeviceName
                AppLogger.writeLog(BMLogMessages.restoringSession(name))
                connectedPeripherals[restoredPeripheral.identifier] =
                    restoredPeripheral
                restoredPeripheral.delegate = self

                if restoredPeripheral.state == .connected {
                    restoredPeripheral.discoverServices(nil)
                }
            }
        }
    }
}
