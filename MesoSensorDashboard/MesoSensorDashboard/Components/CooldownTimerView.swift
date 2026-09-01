//
//  CooldownTimerView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct CooldownTimerView: View {
    let lastTestDate: Date?
    var cooldownDuration: TimeInterval = 180.0 // 3 minutes default
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = remainingSeconds(at: context.date)
            
            if remaining > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                    Text("Sensor Recovering: \(formattedTime(remaining))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
    
    private func remainingSeconds(at currentDate: Date) -> TimeInterval {
        guard let lastDate = lastTestDate else { return 0 }
        let elapsed = currentDate.timeIntervalSince(lastDate)
        return max(0, cooldownDuration - elapsed)
    }
    
    private func formattedTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
