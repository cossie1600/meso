//
//  MotherOfPearlStyle.swift
//  MesoSensorDashboard
//

import SwiftUI

// MARK: - App Color Palette
extension Color {
    static let tiffanyBackground = Color(red: 0.84, green: 0.94, blue: 0.89) // #D6F0E3
    static let appBackground = tiffanyBackground
    
    static let tiffanyTranslucent = Color(red: 0.90, green: 0.97, blue: 0.93).opacity(0.75)
    static let glassCardBackground = tiffanyTranslucent
    
    /// High-contrast Charcoal Gray for sharp text legibility
    static let appPrimaryText = Color(white: 0.18)
    static let appSecondaryText = Color(white: 0.38)
}

// MARK: - Translucent Glass Card Container
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.tiffanyTranslucent
                    
                    LinearGradient(
                        colors: [
                            Color(white: 0.98),
                            Color(red: 0.95, green: 0.88, blue: 0.92),
                            Color(red: 0.86, green: 0.95, blue: 0.92),
                            Color(red: 0.90, green: 0.89, blue: 0.95),
                            Color(white: 0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.20)
                    
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func glassCardStyle() -> some View {
        self.modifier(GlassCardModifier())
    }
    
    func globalAppBackground() -> some View {
        self.background(Color.tiffanyBackground.ignoresSafeArea())
    }
}
