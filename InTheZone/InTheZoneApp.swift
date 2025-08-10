//
//  InTheZoneApp.swift
//  InTheZone
//
//  Created by Blair Campbell on 2025-08-10.
//

import SwiftUI

@main
struct InTheZoneApp: App {
    @StateObject private var bluetoothService = BluetoothService.shared
    @StateObject private var sessionManager = SessionManager()
    @State private var isLoading = true

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoading {
                    LoadingView()
                } else {
                    ContentView()
                        .environmentObject(bluetoothService)
                        .environmentObject(sessionManager)
                }
            }
            .preferredColorScheme(.light)
            .onAppear {
                initializeApp()
            }
        }
    }
    
    private func initializeApp() {
        // Set up session manager proxy
        TrainingConstants.SessionManagerProxy.shared.manager = sessionManager
        
        // Simulate app initialization time and show loading screen
        // In a real app, this would wait for actual initialization tasks to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isLoading = false
            }
        }
    }
}
