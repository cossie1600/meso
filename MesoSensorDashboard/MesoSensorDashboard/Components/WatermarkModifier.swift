//
//  WatermarkModifier.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//
import SwiftUI

// 1. Define the shared watermark layout rule
struct ClingGemWatermark: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(AppConfig.companyName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tracking(2.0)
                        .foregroundColor(.secondary)
                        .opacity(0.6)
                }
            }
    }
}

// 2. Wrap it in a clean, easy-to-read extension name
extension View {
    func clingGemWatermark() -> some View {
        self.modifier(ClingGemWatermark())
    }
}
