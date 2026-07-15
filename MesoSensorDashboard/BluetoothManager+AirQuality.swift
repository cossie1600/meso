//
//  BluetoothManager+AirQuality.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/14/26.
//

import Foundation


// MARK: - Air Quality Evaluation
extension BluetoothManager {
    
    func evaluateAirQualityThresholds(for packet: IncomingPacket) {
        AppLogger.writeLog("🔬 [Threshold Debug] Evaluating: PM1: \(packet.pm1), PM2.5: \(packet.pm25), PM10: \(packet.pm10)")
        
        let pm25Threshold = AppConfig.pm25AlertThreshold
        let pm10Threshold = AppConfig.pm10AlertThreshold
        
        // 1. Evaluate your specific conditions
        let isFineParticulateSpike = packet.pm25 > AppConfig.pm25AlertThreshold // evaluates if PM2.5 > 35.0
        
        let isCoarseDustSpike = packet.pm10 > AppConfig.pm10AlertThreshold     // evaluates if PM10 > 75.0
        let isDustAllergenRatioSpike = packet.isCoarseDustOrAllergenProfileActive
        
        let shouldBeInEmergency = isFineParticulateSpike || isCoarseDustSpike || isDustAllergenRatioSpike
        let targetStrategy: ConnectionStrategy = shouldBeInEmergency ? .emergency : .batterySaver
        
        AppLogger.writeLog("🔬 [Threshold Debug] Match Result -> Target Strategy: \(targetStrategy), Current Strategy: \(self.currentStrategy)")
        
        // 2. Safely update UI flags on the Main Thread every tick
        DispatchQueue.main.async {
            if isFineParticulateSpike {
                
                self.alertMessage = "Notice a drop in air clarity? Consider limiting outdoor exposure or heading to a space with active air filtration for a bit."
                self.alertTheme = .fineParticulates
                
            } else if isDustAllergenRatioSpike {
                self.alertMessage = "It looks like there is some loose pollen or dust drifting nearby. If you are sensitive to allergies, consider wearing a mask or taking an alternate path."
                self.alertTheme = .allergenProfile
                
            } else if isCoarseDustSpike {
                self.alertMessage = "We're detecting a bit of airborne dust right now. A simple face cover will keep your nose and throat feeling completely comfortable."
                self.alertTheme = .generalCoarse
                
            } else {
                self.alertMessage = nil
                self.alertTheme = .none
            }
        }
        AppLogger.writeLog("alertMessage: \(self.alertMessage ?? "No Alert")")
        
        // 3. Prevent BLE radio flooding by managing the state transition explicitly
        if self.currentStrategy != targetStrategy {
            AppLogger.writeLog("🚨 [Threshold Debug] Strategic Delta! Transitioning hardware to \(targetStrategy)")
            
            // 🛑 FIXED: Update local state tracking so this 'if' block doesn't loop forever!
            DispatchQueue.main.async {
                self.currentStrategy = targetStrategy
            }
            
            let activePeripheral = self.connectedPeripheral ?? self.esp32Peripheral
            self.sendSleepIntervalToPeripheral(activePeripheral, factor: targetStrategy)
        }
    }
}
