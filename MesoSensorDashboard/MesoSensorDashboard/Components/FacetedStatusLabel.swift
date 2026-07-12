//
//  FacetedStatusLabel.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/11/26.
//

import SwiftUI

struct FacetedStatusLabel: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .opacity(0.5)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}
