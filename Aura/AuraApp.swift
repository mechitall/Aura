//
//  AuraApp.swift
//  Aura
//
//  Created on 9/8/25.
//

import SwiftUI

@main
struct AuraApp: App {
    
    init() {
        // Load environment configuration on app startup
        Config.loadEnvironment()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}