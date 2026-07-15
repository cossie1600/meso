//
//  EmergencyAlertBanner.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/13/26.
//

import SwiftUI

struct EmergencyAlertBanner: View {
    let bleManager: BluetoothManager
    
    var body: some View {
        VStack(spacing: 0) {
            // 🚨 Dynamic Alert Banner
            if let activeAlert = bleManager.alertMessage {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Text(activeAlert)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
                .padding(.all, 16)
                .background(Color.orange) // Orange for airborne allergens/dust
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: bleManager.alertMessage)
            }
        }
                .padding()
                .background(Color.red)
                .cornerRadius(12)
                .foregroundColor(.white)
                .padding(.top)
        }
    }
