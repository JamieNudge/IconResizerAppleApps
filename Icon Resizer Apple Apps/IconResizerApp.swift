//
//  IconResizerApp.swift
//  Icon Resizer
//
//  Automatically generates all required iOS and macOS app icon sizes
//

import SwiftUI

@main
struct IconResizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

