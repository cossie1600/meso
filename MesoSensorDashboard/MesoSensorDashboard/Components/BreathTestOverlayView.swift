//
//  BreathTestOverlayView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/16/26.
//

import SwiftUI

struct BreathTestOverlayView: View {
    @ObservedObject var bleManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 20) {
            switch bleManager.breathTestState {
            case .idle:
                Button(action: { bleManager.triggerBreathTest() }) {
                    Label("Start Breath Test", systemImage: "lungs.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
            case .warmingUp:
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Warming up sensor...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(bleManager.countdownSeconds)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                }
                
            case .blowNow:
                VStack(spacing: 12) {
                    Image(systemName: "wind")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)
                        .symbolEffect(.bounce, options: .repeating)
                    
                    Text("BLOW NOW")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Text("Blow directly into the sensor (1-2 inches away) for 3-5 seconds.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                
            case .processing:
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 48))
                        .foregroundColor(.teal)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    
                    Text("Analyzing breath sample...")
                        .font(.headline)
                        .foregroundColor(.teal)
                    
                    Text("Capturing VOC nadir and gas resistance curve...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            case .completed:
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("Analysis Complete")
                        .font(.headline)
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
                    Text("Make sure to blow directly onto the sensor grid.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        bleManager.triggerBreathTest()
                    }) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
    }
}
