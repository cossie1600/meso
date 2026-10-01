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
