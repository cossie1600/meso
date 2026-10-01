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
    
    enum PMType {
        case pm1_0, pm2_5, pm10
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            
            // Icon section
            if let pm = pmType {
                PMDotDensityIcon(type: pm)
                    .frame(height: 38)
            } else {
                Image(systemName: iconName(for: label))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color.appPrimaryText)
            }
            
            Spacer(minLength: 0)
            
            // Label in Dark Gray
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color.appPrimaryText)
            
            // Value + Unit in Dark Gray
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color.appPrimaryText)
                
                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color.appSecondaryText)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .aspectRatio(1.0, contentMode: .fit)
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

// MARK: - PM Micro Dot Density Vector Icons
struct PMDotDensityIcon: View {
    let type: SquareMetricCard.PMType
    
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            
            switch type {
            case .pm1_0:
                let rows = 7
                let cols = 7
                let dotRadius: CGFloat = 1.0
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
                let dotRadius: CGFloat = 2.2
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
                let dotRadius: CGFloat = 3.8
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
        .frame(width: 38, height: 38)
    }
}
