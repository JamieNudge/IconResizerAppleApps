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
        // `.contentSize` blocks user resize and full screen; use auto + default size for Image lab.
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.automatic)
    }
}

