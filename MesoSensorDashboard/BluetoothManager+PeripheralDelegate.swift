//
//  BluetoothManager+PeripheralDelegate.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/14/26.
//

import CoreBluetooth
import Foundation

// MARK: - CBPeripheralDelegate Implementation

extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName
        if let error = error {
            AppLogger.writeLog(BMLogMessages.gattServiceDiscoveryError(error.localizedDescription))
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            AppLogger.writeLog(BMLogMessages.gattHandshakeStalled(deviceName))
            return
        }

        AppLogger.writeLog(BMLogMessages.discoveredServices(services.count, deviceName))
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            AppLogger.writeLog(BMLogMessages.gattCharDiscoveryError(error.localizedDescription))
            return
        }

        guard let characteristics = service.characteristics else { return }

        let targetNoseCharUUID = AppConfig.mesoNoseCharacteristicUUIDString.lowercased()
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName

        for characteristic in characteristics {
            let uuidStr = characteristic.uuid.uuidString.lowercased()
            let canNotify = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
            let canWrite = characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)

            if canWrite {
                if uuidStr == targetNoseCharUUID || writeCharacteristics[peripheral.identifier] == nil {
                    self.writeCharacteristics[peripheral.identifier] = characteristic
                    AppLogger.writeLog(BMLogMessages.cachedWriteChar(deviceName, characteristic.uuid.uuidString))

                    if let pendingCmd = self.pendingMesoNoseCommand {
                        AppLogger.writeLog(BMLogMessages.executingQueuedCommand(pendingCmd.rawValue))
                        self.sendMesoNoseCommand(pendingCmd)
                        self.pendingMesoNoseCommand = nil
                    }
                }
            }

            if canNotify {
                AppLogger.writeLog(BMLogMessages.subscribingNotification(deviceName, characteristic.uuid.uuidString))
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }


    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let deviceName = peripheral.name ?? BMConstants.defaultDeviceName
        if let error = error {
            AppLogger.writeLog(BMLogMessages.notificationStateError(deviceName, error.localizedDescription))
            return
        }

        AppLogger.writeLog(BMLogMessages.notificationStateUpdated(characteristic.isNotifying, deviceName))

        if characteristic.isNotifying && peripheral.name?.hasPrefix(AppConfig.mesoNoseBluetoothName) == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + BMConstants.notificationStateDelaySeconds) { [weak self] in
                guard let self = self else { return }

                // If no ambient telemetry exists in memory yet, initialize state to warm-up
                if self.breathTestState == .idle && self.mesoNoseSamples.isEmpty {
                    self.breathTestState = .coldBootWarmup
                    self.statusText = MesoNoseUIStrings.sensorWarmingUpColdBoot
                }

                AppLogger.writeLog(BMLogMessages.handshakeTriggeringBurst)
                self.sendMesoNoseCommand(.setActiveSamplingMode)
                self.cancelInitialBurstTimer()

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, self.mesoNosePeripheral?.state == .connected else { return }
                    guard self.breathTestState == .idle || self.breathTestState == .coldBootWarmup else {
                        AppLogger.writeLog(BMLogMessages.initialBurstTestActive)
                        return
                    }

                    let targetMode = AppConfig.samplingMode
                    AppLogger.writeLog(BMLogMessages.initialBurstCompleteTransitioning(targetMode.rawValue))
                    self.setSamplingMode(mode: targetMode)
                }

                self.initialBurstWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + BMConstants.initialBurstDurationSeconds, execute: workItem)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            AppLogger.writeLog(BMLogMessages.bluetoothNotificationError(error.localizedDescription))
            return
        }

        guard let data = characteristic.value,
              let chunk = String(data: data, encoding: .utf8) else { return }

        let deviceID = peripheral.identifier
        incomingBuffers[deviceID, default: BMConstants.emptyString].append(chunk)

        guard var currentBuffer = incomingBuffers[deviceID], !currentBuffer.isEmpty else { return }

        while let newLineIndex = currentBuffer.firstIndex(of: "\n") {
            let line = String(currentBuffer[..<newLineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            currentBuffer.removeSubrange(..<currentBuffer.index(after: newLineIndex))
            incomingBuffers[deviceID] = currentBuffer

            if line.isEmpty { continue }

            if line.contains(BMConstants.syncCompleteToken) {
                AppLogger.writeLog(BMLogMessages.syncCompleteReceived)
                DispatchQueue.main.async {
                    self.updateStatusOnMainThread(to: BMConstants.statusConnectedLive)
                }
                continue
            }

            if line.hasPrefix(BMConstants.jsonObjectStart) {
                if line.isMesoNosePayload {
                    AppLogger.writeLog(BMLogMessages.mesoNosePayloadIngestion(line))
                    handleMesoNosePacket(line)
                } else {
                    AppLogger.writeLog(BMLogMessages.unrecognizedPayloadSkipped(line))
                }
                continue
            }

            parseMesoPinPacket(line)
        }

        let jsonObjects = extractJSONObjects(from: &currentBuffer)
        incomingBuffers[deviceID] = currentBuffer

        for jsonCandidate in jsonObjects {
            if jsonCandidate.isMesoNosePayload {
                AppLogger.writeLog(BMLogMessages.extractedMesoNosePayload(jsonCandidate))
                handleMesoNosePacket(jsonCandidate)
            }
        }
    }

    func extractJSONObjects(from buffer: inout String) -> [String] {
        var results: [String] = []
        var depth = BMConstants.zeroInt
        var startIndex: String.Index? = nil
        var lastParsedEndIndex: String.Index? = nil

        for index in buffer.indices {
            let char = buffer[index]
            if String(char) == BMConstants.jsonObjectStart {
                if depth == BMConstants.zeroInt {
                    startIndex = index
                }
                depth += BMConstants.singleCount
            } else if String(char) == BMConstants.jsonObjectEnd {
                if depth > BMConstants.zeroInt {
                    depth -= BMConstants.singleCount
                    if depth == BMConstants.zeroInt, let start = startIndex {
                        let jsonString = String(buffer[start...index])
                        results.append(jsonString)
                        lastParsedEndIndex = index
                        startIndex = nil
                    }
                }
            }
        }

        if let lastEnd = lastParsedEndIndex {
            let nextIndex = buffer.index(after: lastEnd)
            buffer = (nextIndex < buffer.endIndex) ? String(buffer[nextIndex...]) : BMConstants.emptyString
        }

        return results
    }
}
