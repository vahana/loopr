// File: Loopr/LooprApp.swift
import SwiftUI

// This is the main entry point for the app
// The @main attribute tells Swift this is where to start

@main
struct LooprApp: App {
    // The body property defines the app's scene
    var body: some Scene {
        // WindowGroup is the main window for the app
        WindowGroup {
            // ContentView is the main view we created
            ContentView()
        }
    }
}

// In SwiftUI, this simple structure is all you need to define the app.
// The ContentView will be loaded automatically when the app starts.


