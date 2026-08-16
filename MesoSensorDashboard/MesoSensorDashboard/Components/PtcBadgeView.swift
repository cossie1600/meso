//
//  PtcBadgeView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 8/9/26.
//

import SwiftUI

struct PtcBadgeView: View {
    let result: PtcResult
    
    var body: some View {
        Text(result.displayName)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, AppConfig.DashboardUI.badgePaddingHorizontal)
            .padding(.vertical, AppConfig.DashboardUI.badgePaddingVertical)
            .background(result.themeColor.opacity(AppConfig.DashboardUI.backgroundOpacity))
            .foregroundColor(result.themeColor)
            .cornerRadius(AppConfig.DashboardUI.badgeCornerRadius)
    }
}
