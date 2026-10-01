//
//  MainTabView.swift
//  MesoSensorDashboard
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var bleManager: BluetoothManager
    
    init() {
        let navBar = UINavigationBarAppearance()
        navBar.configureWithTransparentBackground()
        navBar.backgroundColor = UIColor(Color.appBackground.opacity(0.85))
        navBar.titleTextAttributes = [.foregroundColor: UIColor(Color.appPrimaryText)]
        navBar.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.appPrimaryText)]
        
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        
        let tabBar = UITabBarAppearance()
        tabBar.configureWithTransparentBackground()
        tabBar.backgroundColor = UIColor(Color.appBackground.opacity(0.90))
        
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }
    
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            TabView {
                ContentView()
                    .tabItem {
                        Label("Votre Air", systemImage: "square.grid.2x2.fill")
                    }
                
                // Combined History View
                HistoryContainerView(bleManager: bleManager)
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                
                BreathTestSheetView(
                    sample: bleManager.mesoNoseSamples.first,
                    result: .none
                )
                .tabItem {
                    Label("Breath Test", systemImage: "wind")
                }
                
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .tint(Color.appPrimaryText)
        }
    }
}
