//
//  SquareMetricCard.swift
//  MesoSensorDashboard
//

import SwiftUI

struct SquareMetricCard: View {
    let label: String
    let value: String
    let unit: String?
    var pmType: PMType? = nil
    var size: CGFloat = 120 // Pass any size needed
    
    enum PMType {
        case pm1_0, pm2_5, pm10
    }
    
    // Dynamic Scaled Properties based on Card Size
    private var padding: CGFloat { size * 0.083 }          // ~10pt at 120
    private var iconSize: CGFloat { size * 0.316 }         // ~38pt at 120
    private var iconFontSize: CGFloat { size * 0.20 }      // ~24pt at 120
    private var labelFontSize: CGFloat { size * 0.108 }    // ~13pt at 120
    private var valueFontSize: CGFloat { size * 0.15 }     // ~18pt at 120
    private var unitFontSize: CGFloat { size * 0.091 }     // ~11pt at 120
    private var spacing: CGFloat { size * 0.05 }           // ~6pt at 120

    var body: some View {
        VStack(spacing: spacing) {
            Spacer(minLength: 0)
            
            // Dynamic Icon Section
            if let pm = pmType {
                PMDotDensityIcon(type: pm, size: iconSize)
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: iconName(for: label))
                    .font(.system(size: iconFontSize, weight: .medium))
                    .foregroundColor(Color.appPrimaryText)
            }
            
            Spacer(minLength: 0)
            
            // Label
            Text(label)
                .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                .foregroundColor(Color.appPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            // Value + Unit Inline
            HStack(alignment: .firstTextBaseline, spacing: size * 0.025) {
                Text(value)
                    .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(Color.appPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                if let unit = unit {
                    Text(unit)
                        .font(.system(size: unitFontSize, weight: .medium, design: .rounded))
                        .foregroundColor(Color.appSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(padding)
        .frame(width: size, height: size)
        .glassCardStyle()
    }
    
    private func iconName(for label: String) -> String {
        switch label.lowercased() {
        case "temp": return "thermometer.medium"
        case "humidity": return "drop.fill"
        case "pressure": return "gauge.with.dots.needle.bottom.50percent"
        case "voc": return "capsule.portrait.fill"
        default: return "wind"
        }
    }
}

// MARK: - Scalable PM Micro Dot Density Vector Icons
struct PMDotDensityIcon: View {
    let type: SquareMetricCard.PMType
    var size: CGFloat = 38
    
    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let center = CGPoint(x: w / 2, y: h / 2)
            let scaleFactor = w / 38.0 // Reference standard size 38pt
            
            switch type {
            case .pm1_0:
                let rows = 7
                let cols = 7
                let dotRadius: CGFloat = 1.0 * scaleFactor
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = (w * 0.25) + CGFloat(c) * (w * 0.5 / CGFloat(cols - 1))
                        let y = (h * 0.25) + CGFloat(r) * (h * 0.5 / CGFloat(rows - 1))
                        let path = Path(ellipseIn: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                        context.fill(path, with: .color(Color.appPrimaryText))
                    }
                }
                
            case .pm2_5:
                let count = 12
                let dotRadius: CGFloat = 2.2 * scaleFactor
                for i in 0..<count {
                    let angle = Double(i) * (2 * .pi / Double(count))
                    let dist = (i % 2 == 0) ? w * 0.25 : w * 0.12
                    let x = center.x + CGFloat(cos(angle)) * dist
                    let y = center.y + CGFloat(sin(angle)) * dist
                    let path = Path(ellipseIn: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                    context.fill(path, with: .color(Color.appPrimaryText))
                }
                
            case .pm10:
                let count = 8
                let dotRadius: CGFloat = 3.8 * scaleFactor
                for i in 0..<count {
                    let angle = Double(i) * (2 * .pi / Double(count))
                    let dist = w * 0.22
                    let x = center.x + CGFloat(cos(angle)) * dist
                    let y = center.y + CGFloat(sin(angle)) * dist
                    let path = Path(ellipseIn: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                    context.fill(path, with: .color(Color.appPrimaryText))
                }
            }
        }
        .frame(width: size, height: size)
    }
}
