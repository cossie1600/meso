//
//  SensorSegmentedPickerView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 10/1/26.
//

import SwiftUI

enum SensorCategory: String, CaseIterable, Identifiable {
    case microclimate = "Microclimate"
    case particulates = "Particulates"
    
    var id: String { self.rawValue }
}

struct SensorSegmentedPickerView: View {
    @Binding var selectedCategory: SensorCategory
    var availableCategories: [SensorCategory] = SensorCategory.allCases
    
    var body: some View {
        Picker("Sensor Category", selection: $selectedCategory) {
            ForEach(availableCategories) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .pickerStyle(.segmented)
    }
}
