//
//  PtcResult.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/8/26.
//

import SwiftUI

enum PtcResult: String, Codable {
    case fresh = "FRESH"
    case mild = "MILD"
    case significant = "SIGNIFICANT"
    case severe = "SEVERE"
    case none = "NONE"
    
    var displayName: String {
        switch self {
        case .fresh: return "Fresh"
        case .mild: return "Mild"
        case .significant: return "Significant"
        case .severe: return "Severe"
        case .none: return "Slow Sampling"
        }
    }
    
    var themeColor: Color {
        switch self {
        case .fresh: return .green
        case .mild: return .yellow
        case .significant: return .orange
        case .severe: return .red
        case .none: return .blue
        }
    }
    
    var isEvaluated: Bool {
        return self != .none
    }
}
