//
//  HistoryView.swift
//  MesoSensorDashboard
//
//  Created by Thomas Ai Mak on 7/10/26.
//
import SwiftUI
import SwiftData

struct HistoryView: View {
    @ObservedObject var bleManager: BluetoothManager
    
    @Query(sort: \DB_PMSample.timestamp, order: .reverse)
    private var databaseHistory: [DB_PMSample]
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long // Displays "July 13, 2026"
        formatter.timeStyle = .none
        return formatter
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 12) {
                // If there are no readings in the DB, show an empty state
                if databaseHistory.isEmpty {
                    ContentUnavailableView(
                        "No Readings Yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Waiting for data stream...")
                    )
                    .padding(.top, 40)
                } else {
                    // 2. Use the first reading from our SwiftData query for the header date
                    if let firstReading = databaseHistory.first {
                        HStack {
                            Text(dateFormatter.string(from: firstReading.timestamp).uppercased())
                                .font(.caption)
                                .fontWeight(.bold)
                                .tracking(1.5)
                                .foregroundStyle(.secondary.opacity(0.7))
                            Spacer()
                        }
                        .padding(.bottom, 4)
                    }
                    
                    // 3. Loop through the real database items!
                    ForEach(databaseHistory) { reading in
                        HistoryCardView(reading: reading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
