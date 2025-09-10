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
        // Load environment variables from .env file at startup
        Config.loadEnvironment()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}