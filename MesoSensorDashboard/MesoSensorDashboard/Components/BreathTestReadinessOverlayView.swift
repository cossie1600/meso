//
//  BreathTestReadinessOverlayView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/13/26.
//
import CoreBluetooth
import SwiftUI

struct BreathTestReadinessOverlayView: View {
    @ObservedObject var bleManager: BluetoothManager

    private var isConnected: Bool {
        bleManager.mesoNosePeripheral?.state == .connected
    }

    var body: some View {
        VStack(spacing: 16) {
            if !isConnected {
                // State 1: Sensor Disconnected
                VStack(spacing: 12) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color.appSecondaryText)

                    Text(MesoNoseUIStrings.statusSensorDisconnected)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color.appPrimaryText)

                    Text(MesoNoseUIStrings.promptConnectSensor)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.appSecondaryText)

                    Button(action: {
                        bleManager.startPairingMesoNose()
                    }) {
                        Text(MesoNoseUIStrings.actionSearchAndConnect)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.appPrimaryText)
                            .cornerRadius(12)
                    }
                }
                .padding(20)
                .glassCardStyle()

            } else if !bleManager.isSensorReadyForTest {
                // State 2: Warming Up / Waiting for Fresh Baseline Sample
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color.appPrimaryText)

                    Text(bleManager.breathTestState == .coldBootWarmup ? bleManager.statusText : MesoNoseUIStrings.statusSensorStabilizing)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color.appPrimaryText)

                    Text(MesoNoseUIStrings.promptSensorStabilizing)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.appSecondaryText)
                }
                .padding(20)
                .glassCardStyle()
            }
        }
        .padding(.horizontal, 20)
    }
}
