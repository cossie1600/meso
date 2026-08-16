//
//  StationaryDetector.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/8/26.
//

import Foundation
import CoreMotion
import Combine

class StationaryDetector: ObservableObject {
    private let activityManager = CMMotionActivityManager()
    @Published var isStationary: Bool = false
    
    var onStationaryChanged: ((Bool) -> Void)?

    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            
            // Requires stationary state with high/medium confidence
            let stationary = activity.stationary && (activity.confidence == .high || activity.confidence == .medium)
            
            if self.isStationary != stationary {
                self.isStationary = stationary
                self.onStationaryChanged?(stationary)
            }
        }
    }

    func stopMonitoring() {
        activityManager.stopActivityUpdates()
    }
}
