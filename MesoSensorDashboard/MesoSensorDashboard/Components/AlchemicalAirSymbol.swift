//
//  AlchemicalAirSymbol.swift
//  MesoSensorDashboard
//

import SwiftUI

struct AlchemicalAirSymbol: View {
    var size: CGFloat = 28
    
    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            
            // Triangle Path
            var triangle = Path()
            triangle.move(to: CGPoint(x: w / 2, y: h * 0.08))
            triangle.addLine(to: CGPoint(x: w * 0.9, y: h * 0.88))
            triangle.addLine(to: CGPoint(x: w * 0.1, y: h * 0.88))
            triangle.closeSubpath()
            
            // Horizontal Bar Path
            var bar = Path()
            bar.move(to: CGPoint(x: 0, y: h * 0.48))
            bar.addLine(to: CGPoint(x: w, y: h * 0.48))
            
            let strokeStyle = StrokeStyle(lineWidth: w * 0.12, lineCap: .round, lineJoin: .miter)
            
            context.stroke(triangle, with: .color(Color.appPrimaryText), style: strokeStyle)
            context.stroke(bar, with: .color(Color.appPrimaryText), style: strokeStyle)
        }
        .frame(width: size, height: size)
    }
}
