//
//  ContentView.swift
//  InTheZone
//
//  Created by Blair Campbell on 2025-08-10.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var bluetoothService: BluetoothService
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem { 
                    Label("Home", systemImage: "house.fill")
                }

            WorkoutView()
                .tabItem { 
                    Label("Workouts", systemImage: "bicycle")
                }

            TrainingProgressView()
                .tabItem { 
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem { 
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .accentColor(Color("PrimaryGreen"))
    }
}

#Preview {
    ContentView()
        .environmentObject(BluetoothService.shared)
        .environmentObject(SessionManager())
}
