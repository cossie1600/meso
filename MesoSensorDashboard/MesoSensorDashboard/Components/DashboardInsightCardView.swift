//
//  DashboardInsightCardView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct DashboardInsightCardView: View {
    let humidity: Double?
    let pressure: Double?
    let pm25String: String
    
    private var statusRecommendation: String {
        guard let humidity = humidity, let pressure = pressure else {
            return "Awaiting environmental telemetry..."
        }
        
        let pm25 = Double(pm25String) ?? 0.0
        
        if pressure < 1005.0 && humidity > 65.0 {
            return "Low atmospheric pressure and high humidity detected. This combination may induce joint stiffness or fatigue. Keep hydration levels up and consider taking a light break."
        } else if humidity > 70.0 {
            return "High indoor humidity levels detected. Open a window or use a dehumidifier to refresh indoor air circulation."
        } else if pm25 > 35.4 {
            return "Elevated particulate levels detected. Keep windows closed and turn on an air purifier if available."
        } else {
            return "Optimal ambient conditions. Temperature and air purity are balanced—ideal for deep breathing exercises."
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.appPrimaryText)
                
                Text("ENVIRONMENTAL INSIGHT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(Color.appSecondaryText)
            }
            
            Text(statusRecommendation)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineSpacing(5)
                .foregroundColor(Color.appPrimaryText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle()
    }
}
