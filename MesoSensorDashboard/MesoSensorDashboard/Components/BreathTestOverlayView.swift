//
//  BreathTestOverlayView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct BreathTestOverlayView: View {
    @ObservedObject var bleManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 20) {
            switch bleManager.breathTestState {
            case .idle:
                EmptyView()
                
            case .warmingUp:
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.appPrimaryText)
                    
                    Text(bleManager.statusText)
                        .font(.headline)
                        .foregroundColor(Color.appPrimaryText)
                }
                .padding(.vertical, 8)
                
            case .blowNow:
                VStack(spacing: 12) {
                    Image(systemName: "wind")
                        .font(.system(size: 64))
                        .foregroundColor(Color.appPrimaryText)
                        .symbolEffect(.bounce, options: .repeating)
                    
                    Text("BLOW NOW")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color.appPrimaryText)
                    
                    Text("Blow directly into the sensor (1-2 inches away) for 3-5 seconds.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.appSecondaryText)
                }
                
            case .processing:
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 48))
                        .foregroundColor(Color.appPrimaryText)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    
                    Text(bleManager.statusText)
                        .font(.headline)
                        .foregroundColor(Color.appPrimaryText)
                    
                    Text("Capturing VOC nadir and gas resistance curve...")
                        .font(.caption)
                        .foregroundColor(Color.appSecondaryText)
                }
                
            case .completed:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("Analysis Complete")
                        .font(.headline)
                        .foregroundColor(Color.appPrimaryText)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if bleManager.breathTestState == .completed {
                            bleManager.breathTestState = .idle
                        }
                    }
                }
                
            case .timeout:
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("No Breath Detected")
                        .font(.headline)
                        .foregroundColor(Color.appPrimaryText)
                    
                    Text("Make sure to blow directly onto the sensor grid.")
                        .font(.caption)
                        .foregroundColor(Color.appSecondaryText)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            bleManager.triggerBreathTest()
                        }) {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .fontWeight(.bold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appPrimaryText)
                        
                        Button(action: {
                            bleManager.cancelBreathTest()
                        }) {
                            Text("Cancel")
                                .fontWeight(.bold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            
            // Cancel button during active testing phases (Warming Up, Blow Now, Processing)
            if bleManager.breathTestState == .warmingUp ||
               bleManager.breathTestState == .blowNow ||
               bleManager.breathTestState == .processing {
                Button(action: {
                    bleManager.cancelBreathTest()
                }) {
                    Text("Cancel Test")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .glassCardStyle()
        .padding(.horizontal, 4)
    }
}
