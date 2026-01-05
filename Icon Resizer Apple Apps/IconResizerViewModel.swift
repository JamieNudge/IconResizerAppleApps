//
//  IconResizerViewModel.swift
//  Icon Resizer
//
//  Handles PNG resizing for all Apple platform icon sizes and App Store screenshots
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

enum OperationMode: String, CaseIterable {
    case icons = "App Icons"
    case screenshots = "App Screenshots"
}

enum PlatformSelection: String, CaseIterable {
    case both = "iOS + macOS"
    case iOS = "iOS Only"
    case iOSUniversal = "iOS Universal"
    case macOS = "macOS Only"
}

enum ScreenshotPlatform: String, CaseIterable {
    case iPhone = "iPhone"
    case iPad = "iPad"
    case appleWatch = "Apple Watch"
}

class IconResizerViewModel: ObservableObject {
    @Published var isTargeted = false
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var lastOutputFolder: URL?
    @Published var selectedPlatform: PlatformSelection = .both
    @Published var operationMode: OperationMode = .icons
    @Published var screenshotPlatform: ScreenshotPlatform = .iPhone
    
    // Fixed output directory
    private let outputDirectory = "/Users/Jamie/Desktop/Apple Icons"
    
    // iOS AppIcon sizes with proper Xcode asset catalog structure
    struct IOSIconConfig {
        let filename: String
        let idiom: String
        let size: String
        let scale: String
        let pixelSize: CGFloat
    }
    
    let iosSizes: [IOSIconConfig] = [
        // iPhone Notification
        IOSIconConfig(filename: "Icon-20@2x.png", idiom: "iphone", size: "20x20", scale: "2x", pixelSize: 40),
        IOSIconConfig(filename: "Icon-20@3x.png", idiom: "iphone", size: "20x20", scale: "3x", pixelSize: 60),
        // iPhone Settings
        IOSIconConfig(filename: "Icon-29@2x.png", idiom: "iphone", size: "29x29", scale: "2x", pixelSize: 58),
        IOSIconConfig(filename: "Icon-29@3x.png", idiom: "iphone", size: "29x29", scale: "3x", pixelSize: 87),
        // iPhone Spotlight
        IOSIconConfig(filename: "Icon-40@2x.png", idiom: "iphone", size: "40x40", scale: "2x", pixelSize: 80),
        IOSIconConfig(filename: "Icon-40@3x.png", idiom: "iphone", size: "40x40", scale: "3x", pixelSize: 120),
        // iPhone App
        IOSIconConfig(filename: "Icon-60@2x.png", idiom: "iphone", size: "60x60", scale: "2x", pixelSize: 120),
        IOSIconConfig(filename: "Icon-60@3x.png", idiom: "iphone", size: "60x60", scale: "3x", pixelSize: 180),
        // iPad Notification
        IOSIconConfig(filename: "Icon-iPad-20.png", idiom: "ipad", size: "20x20", scale: "1x", pixelSize: 20),
        IOSIconConfig(filename: "Icon-iPad-20@2x.png", idiom: "ipad", size: "20x20", scale: "2x", pixelSize: 40),
        // iPad Settings
        IOSIconConfig(filename: "Icon-iPad-29.png", idiom: "ipad", size: "29x29", scale: "1x", pixelSize: 29),
        IOSIconConfig(filename: "Icon-iPad-29@2x.png", idiom: "ipad", size: "29x29", scale: "2x", pixelSize: 58),
        // iPad Spotlight
        IOSIconConfig(filename: "Icon-iPad-40.png", idiom: "ipad", size: "40x40", scale: "1x", pixelSize: 40),
        IOSIconConfig(filename: "Icon-iPad-40@2x.png", idiom: "ipad", size: "40x40", scale: "2x", pixelSize: 80),
        // iPad App
        IOSIconConfig(filename: "Icon-76.png", idiom: "ipad", size: "76x76", scale: "1x", pixelSize: 76),
        IOSIconConfig(filename: "Icon-76@2x.png", idiom: "ipad", size: "76x76", scale: "2x", pixelSize: 152),
        // iPad Pro
        IOSIconConfig(filename: "Icon-83.5@2x.png", idiom: "ipad", size: "83.5x83.5", scale: "2x", pixelSize: 167),
        // App Store
        IOSIconConfig(filename: "Icon-1024.png", idiom: "ios-marketing", size: "1024x1024", scale: "1x", pixelSize: 1024)
    ]
    
    // iOS Universal sizes (iOS 11+, simplified single icon set for all devices)
    // All use 1024x1024 source, but labeled for different device scales
    let iosUniversalSizes: [IOSIconConfig] = [
        IOSIconConfig(filename: "AppIcon-1x.png", idiom: "universal", size: "1024x1024", scale: "1x", pixelSize: 1024),
        IOSIconConfig(filename: "AppIcon-2x.png", idiom: "universal", size: "1024x1024", scale: "2x", pixelSize: 1024),
        IOSIconConfig(filename: "AppIcon-3x.png", idiom: "universal", size: "1024x1024", scale: "3x", pixelSize: 1024)
    ]
    
    // macOS AppIcon sizes with proper Xcode asset catalog structure
    struct MacIconConfig {
        let filename: String
        let size: String
        let scale: String
        let pixelSize: CGFloat
    }
    
    let macOSSizes: [MacIconConfig] = [
        MacIconConfig(filename: "icon_16x16.png", size: "16x16", scale: "1x", pixelSize: 16),
        MacIconConfig(filename: "icon_16x16@2x.png", size: "16x16", scale: "2x", pixelSize: 32),
        MacIconConfig(filename: "icon_32x32.png", size: "32x32", scale: "1x", pixelSize: 32),
        MacIconConfig(filename: "icon_32x32@2x.png", size: "32x32", scale: "2x", pixelSize: 64),
        MacIconConfig(filename: "icon_128x128.png", size: "128x128", scale: "1x", pixelSize: 128),
        MacIconConfig(filename: "icon_128x128@2x.png", size: "128x128", scale: "2x", pixelSize: 256),
        MacIconConfig(filename: "icon_256x256.png", size: "256x256", scale: "1x", pixelSize: 256),
        MacIconConfig(filename: "icon_256x256@2x.png", size: "256x256", scale: "2x", pixelSize: 512),
        MacIconConfig(filename: "icon_512x512.png", size: "512x512", scale: "1x", pixelSize: 512),
        MacIconConfig(filename: "icon_512x512@2x.png", size: "512x512", scale: "2x", pixelSize: 1024)
    ]
    
    // App Store Screenshot sizes
    struct ScreenshotConfig {
        let filename: String
        let width: CGFloat
        let height: CGFloat
        let description: String
    }
    
    // iPhone screenshot sizes - PORTRAIT
    let iPhonePortraitSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "iPhone-1242x2688.png", width: 1242, height: 2688, description: "iPhone 6.5\" Portrait"),
        ScreenshotConfig(filename: "iPhone-1284x2778.png", width: 1284, height: 2778, description: "iPhone 6.7\" Portrait")
    ]
    
    // iPhone screenshot sizes - LANDSCAPE
    let iPhoneLandscapeSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "iPhone-2688x1242.png", width: 2688, height: 1242, description: "iPhone 6.5\" Landscape"),
        ScreenshotConfig(filename: "iPhone-2778x1284.png", width: 2778, height: 1284, description: "iPhone 6.7\" Landscape")
    ]
    
    // iPad screenshot sizes - PORTRAIT
    let iPadPortraitSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "iPad-2064x2752.png", width: 2064, height: 2752, description: "iPad 13\" Portrait"),
        ScreenshotConfig(filename: "iPad-2048x2732.png", width: 2048, height: 2732, description: "iPad 12.9\" Portrait")
    ]
    
    // iPad screenshot sizes - LANDSCAPE
    let iPadLandscapeSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "iPad-2752x2064.png", width: 2752, height: 2064, description: "iPad 13\" Landscape"),
        ScreenshotConfig(filename: "iPad-2732x2048.png", width: 2732, height: 2048, description: "iPad 12.9\" Landscape")
    ]
    
    // Apple Watch screenshot sizes
    let appleWatchScreenshotSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "Watch-Ultra3-422x514.png", width: 422, height: 514, description: "Ultra 3"),
        ScreenshotConfig(filename: "Watch-Ultra-410x502.png", width: 410, height: 502, description: "Ultra 1/2"),
        ScreenshotConfig(filename: "Watch-Series11-416x496.png", width: 416, height: 496, description: "Series 11"),
        ScreenshotConfig(filename: "Watch-Series9-396x484.png", width: 396, height: 484, description: "Series 9/10"),
        ScreenshotConfig(filename: "Watch-Series6-368x448.png", width: 368, height: 448, description: "Series 6/7/8"),
        ScreenshotConfig(filename: "Watch-Series3-312x390.png", width: 312, height: 390, description: "Series 3/4/5")
    ]
    
    func handleDrop(providers: [NSItemProvider]) {
        if operationMode == .icons {
            // Icons: use first image only
            guard let provider = providers.first else { return }
            
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.statusMessage = "❌ Error: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let data = data, let nsImage = NSImage(data: data) else {
                        self.statusMessage = "❌ Could not load image"
                        return
                    }
                    
                    self.resizeAndSaveIcons(sourceImage: nsImage)
                }
            }
        } else {
            // Screenshots: process ALL dropped images
            self.resizeAndSaveMultipleScreenshots(providers: providers)
        }
    }
    
    private func resizeAndSaveIcons(sourceImage: NSImage) {
        self.isProcessing = true
        self.statusMessage = "🔄 Resizing icons..."
        
        // Try default location first, fallback to save panel if permission denied
        let outputFolderURL = URL(fileURLWithPath: self.outputDirectory)
        let fileManager = FileManager.default
        
        do {
            try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
            // Success - proceed with default location
            self.performIconProcessing(sourceImage: sourceImage, outputFolderURL: outputFolderURL)
        } catch {
            // Permission denied - use save panel
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showSavePanelForIcons(sourceImage: sourceImage)
            }
        }
    }
    
    private func showSavePanelForIcons(sourceImage: NSImage) {
        let savePanel = NSOpenPanel()
        savePanel.title = "Choose Output Folder"
        savePanel.message = "Select where to save the app icons"
        savePanel.canChooseFiles = false
        savePanel.canChooseDirectories = true
        savePanel.canCreateDirectories = true
        savePanel.allowsMultipleSelection = false
        
        // Default to Desktop
        savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        
        savePanel.begin { response in
            guard response == .OK, let selectedURL = savePanel.url else {
                self.statusMessage = "❌ Cancelled"
                return
            }
            
            self.isProcessing = true
            self.statusMessage = "🔄 Resizing icons..."
            self.performIconProcessing(sourceImage: sourceImage, outputFolderURL: selectedURL)
        }
    }
    
    private func performIconProcessing(sourceImage: NSImage, outputFolderURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            
            do {
                // Ensure output directory exists
                try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
                
                var totalGenerated = 0
                    
                    // Generate iOS Universal icons if selected
                    if self.selectedPlatform == .iOSUniversal {
                        let appiconsetURL = outputFolderURL.appendingPathComponent("AppIcon.appiconset")
                        try fileManager.createDirectory(at: appiconsetURL, withIntermediateDirectories: true)
                        
                        // Generate universal icons (all 1024x1024)
                        for config in self.iosUniversalSizes {
                            if let resizedImage = self.resize(image: sourceImage, to: config.pixelSize) {
                                let fileURL = appiconsetURL.appendingPathComponent(config.filename)
                                if self.savePNG(image: resizedImage, to: fileURL) {
                                    totalGenerated += 1
                                }
                            }
                        }
                        
                        // Generate Contents.json for iOS Universal
                        self.generateIOSUniversalContentsJSON(at: appiconsetURL)
                    }
                    
                    // Generate iOS icons if selected
                    if self.selectedPlatform == .iOS || self.selectedPlatform == .both {
                        let iosFolderURL = self.selectedPlatform == .both 
                            ? outputFolderURL.appendingPathComponent("iOS")
                            : outputFolderURL
                        
                        // Create AppIcon.appiconset folder
                        let appiconsetURL = iosFolderURL.appendingPathComponent("AppIcon.appiconset")
                        try fileManager.createDirectory(at: appiconsetURL, withIntermediateDirectories: true)
                        
                        // Generate icons
                        for config in self.iosSizes {
                            if let resizedImage = self.resize(image: sourceImage, to: config.pixelSize) {
                                let fileURL = appiconsetURL.appendingPathComponent(config.filename)
                                if self.savePNG(image: resizedImage, to: fileURL) {
                                    totalGenerated += 1
                                }
                            }
                        }
                        
                        // Generate Contents.json for iOS
                        self.generateIOSContentsJSON(at: appiconsetURL)
                    }
                    
                    // Generate macOS icons if selected
                    if self.selectedPlatform == .macOS || self.selectedPlatform == .both {
                        let macFolderURL = self.selectedPlatform == .both
                            ? outputFolderURL.appendingPathComponent("macOS")
                            : outputFolderURL
                        
                        // Create AppIcon.appiconset folder
                        let appiconsetURL = macFolderURL.appendingPathComponent("AppIcon.appiconset")
                        try fileManager.createDirectory(at: appiconsetURL, withIntermediateDirectories: true)
                        
                        // Generate icons
                        for config in self.macOSSizes {
                            if let resizedImage = self.resize(image: sourceImage, to: config.pixelSize) {
                                let fileURL = appiconsetURL.appendingPathComponent(config.filename)
                                if self.savePNG(image: resizedImage, to: fileURL) {
                                    totalGenerated += 1
                                }
                            }
                        }
                        
                        // Generate Contents.json for macOS
                        self.generateMacOSContentsJSON(at: appiconsetURL)
                    }
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    let platformText = self.selectedPlatform == .both ? "iOS + macOS" : self.selectedPlatform.rawValue
                    self.statusMessage = "✅ Generated \(totalGenerated) \(platformText) icons!"
                    self.lastOutputFolder = outputFolderURL
                    print("✅ Generated \(totalGenerated) \(platformText) app icons")
                    print("📂 Location: \(outputFolderURL.path)")
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.statusMessage = "❌ Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func resizeAndSaveMultipleScreenshots(providers: [NSItemProvider]) {
        self.isProcessing = true
        self.statusMessage = "🔄 Loading \(providers.count) images..."
        
        // Load all images first
        var loadedImages: [NSImage] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
                if let data = data, let image = NSImage(data: data) {
                    DispatchQueue.main.async {
                        loadedImages.append(image)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if loadedImages.isEmpty {
                self.isProcessing = false
                self.statusMessage = "❌ No valid images found"
                return
            }
            
            self.statusMessage = "🔄 Loaded \(loadedImages.count) images, choose save location..."
            self.processMultipleScreenshots(images: loadedImages)
        }
    }
    
    private func processMultipleScreenshots(images: [NSImage]) {
        self.isProcessing = true
        self.statusMessage = "🔄 Resizing \(images.count) screenshots..."
        
        // Try default location first, fallback to save panel if permission denied
        let baseFolder = URL(fileURLWithPath: self.outputDirectory)
        let defaultOutputURL = baseFolder.appendingPathComponent("\(self.screenshotPlatform.rawValue)_Screenshots")
        let fileManager = FileManager.default
        
        // Test if we can write to the default location
        do {
            try fileManager.createDirectory(at: defaultOutputURL, withIntermediateDirectories: true)
            // Success - proceed with default location
            self.performScreenshotProcessing(images: images, outputFolderURL: defaultOutputURL)
        } catch {
            // Permission denied - use save panel to let user choose location
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showSavePanelForScreenshots(images: images)
            }
        }
    }
    
    private func showSavePanelForScreenshots(images: [NSImage]) {
        let savePanel = NSOpenPanel()
        savePanel.title = "Choose Output Folder"
        savePanel.message = "Select where to save the \(images.count) screenshots"
        savePanel.canChooseFiles = false
        savePanel.canChooseDirectories = true
        savePanel.canCreateDirectories = true
        savePanel.allowsMultipleSelection = false
        
        // Default to Desktop
        savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        
        savePanel.begin { response in
            guard response == .OK, let selectedURL = savePanel.url else {
                self.statusMessage = "❌ Cancelled"
                return
            }
            
            let outputFolderURL = selectedURL.appendingPathComponent("\(self.screenshotPlatform.rawValue)_Screenshots")
            self.isProcessing = true
            self.statusMessage = "🔄 Resizing \(images.count) screenshots..."
            self.performScreenshotProcessing(images: images, outputFolderURL: outputFolderURL)
        }
    }
    
    private func performScreenshotProcessing(images: [NSImage], outputFolderURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            
            do {
                try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
                
                var totalGenerated = 0
                var permissionErrorOccurred = false
                let platformName: String
                
                switch self.screenshotPlatform {
                case .iPhone:
                    platformName = "iPhone"
                case .iPad:
                    platformName = "iPad"
                case .appleWatch:
                    platformName = "Watch"
                }
                
                // Process each image
                for (index, sourceImage) in images.enumerated() {
                    let imageNumber = index + 1
                    let isPortrait = sourceImage.size.height > sourceImage.size.width
                    
                    let configs: [ScreenshotConfig]
                    switch self.screenshotPlatform {
                    case .iPhone:
                        configs = isPortrait ? self.iPhonePortraitSizes : self.iPhoneLandscapeSizes
                    case .iPad:
                        configs = isPortrait ? self.iPadPortraitSizes : self.iPadLandscapeSizes
                    case .appleWatch:
                        configs = self.appleWatchScreenshotSizes
                    }
                    
                    // Generate each size for this image
                    for config in configs {
                        if let resizedImage = self.resizeScreenshot(image: sourceImage,
                                                                     width: config.width,
                                                                     height: config.height) {
                            // Include image number in filename: Screenshot_01_1242x2688.png
                            let filename = "Screenshot_\(String(format: "%02d", imageNumber))_\(Int(config.width))x\(Int(config.height)).png"
                            let fileURL = outputFolderURL.appendingPathComponent(filename)
                            
                            // Check for permission errors
                            if let error = self.savePNGWithError(image: resizedImage, to: fileURL) {
                                // Check if it's a permission error
                                let nsError = error as NSError
                                if nsError.domain == NSCocoaErrorDomain && nsError.code == 513 {
                                    permissionErrorOccurred = true
                                    break // Exit inner loop
                                }
                            } else {
                                totalGenerated += 1
                                print("✅ Screenshot \(imageNumber): \(filename)")
                            }
                        }
                    }
                    
                    // Exit outer loop if permission error occurred
                    if permissionErrorOccurred {
                        break
                    }
                }
                
                // If permission error occurred, show save panel
                if permissionErrorOccurred {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.showSavePanelForScreenshots(images: images)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.statusMessage = "✅ Generated \(totalGenerated) screenshots from \(images.count) images!"
                    self.lastOutputFolder = outputFolderURL
                    print("✅ Generated \(totalGenerated) \(platformName) screenshots from \(images.count) images")
                    print("📂 Location: \(outputFolderURL.path)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.showSavePanelForScreenshots(images: images)
                }
            }
        }
    }
    
    // Single image version - not used but kept for reference
    private func resizeAndSaveSingleScreenshot(sourceImage: NSImage) {
        // Use save panel but default to Apple Icons folder
        let savePanel = NSSavePanel()
        savePanel.title = "Save Screenshots"
        savePanel.message = "Choose where to save the generated screenshots"
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = self.screenshotPlatform.rawValue + "_Screenshots"
        savePanel.showsTagField = false
        
        // Default to Apple Icons folder if it exists
        let defaultFolder = URL(fileURLWithPath: self.outputDirectory)
        if FileManager.default.fileExists(atPath: defaultFolder.path) {
            savePanel.directoryURL = defaultFolder
        }
        
        savePanel.begin { response in
            guard response == .OK, let outputFolderURL = savePanel.url else {
                self.statusMessage = "❌ Cancelled"
                return
            }
            
            self.isProcessing = true
            self.statusMessage = "🔄 Resizing screenshots..."
            
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                
                do {
                    // Ensure output directory exists
                    try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
                    
                    var totalGenerated = 0
                    let configs: [ScreenshotConfig]
                    let platformName: String
                    let orientationName: String
                    
                    // Detect orientation from source image
                    let isPortrait = sourceImage.size.height > sourceImage.size.width
                    
                    // Select screenshot sizes based on platform AND orientation
                    switch self.screenshotPlatform {
                    case .iPhone:
                        configs = isPortrait ? self.iPhonePortraitSizes : self.iPhoneLandscapeSizes
                        platformName = "iPhone"
                        orientationName = isPortrait ? "Portrait" : "Landscape"
                    case .iPad:
                        configs = isPortrait ? self.iPadPortraitSizes : self.iPadLandscapeSizes
                        platformName = "iPad"
                        orientationName = isPortrait ? "Portrait" : "Landscape"
                    case .appleWatch:
                        configs = self.appleWatchScreenshotSizes
                        platformName = "Watch"
                        orientationName = ""
                    }
                    
                    // Generate screenshots directly to output folder
                    for config in configs {
                        if let resizedImage = self.resizeScreenshot(image: sourceImage,
                                                                     width: config.width,
                                                                     height: config.height) {
                            let fileURL = outputFolderURL.appendingPathComponent(config.filename)
                            if self.savePNG(image: resizedImage, to: fileURL) {
                                totalGenerated += 1
                                print("✅ Generated \(config.description): \(config.filename)")
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        let orientationText = orientationName.isEmpty ? "" : " \(orientationName)"
                        self.statusMessage = "✅ Generated \(totalGenerated) \(platformName)\(orientationText) screenshots!"
                        self.lastOutputFolder = outputFolderURL
                        print("✅ Generated \(totalGenerated) \(platformName)\(orientationText) screenshots")
                        print("📂 Location: \(outputFolderURL.path)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.statusMessage = "❌ Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func resize(image: NSImage, to size: CGFloat) -> NSImage? {
        let newSize = NSSize(width: size, height: size)
        
        // Create bitmap with exact pixel dimensions (not points)
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        
        bitmapRep.size = newSize
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.addRepresentation(bitmapRep)
        
        return resizedImage
    }
    
    private func resizeScreenshot(image: NSImage, width: CGFloat, height: CGFloat) -> NSImage? {
        let newSize = NSSize(width: width, height: height)
        
        // Create bitmap with exact pixel dimensions (not points)
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        
        bitmapRep.size = newSize
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        
        // Draw image scaled to fit the exact dimensions
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.addRepresentation(bitmapRep)
        
        return resizedImage
    }
    
    private func savePNG(image: NSImage, to url: URL) -> Bool {
        return savePNGWithError(image: image, to: url) == nil
    }
    
    private func savePNGWithError(image: NSImage, to url: URL) -> Error? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return NSError(domain: "IconResizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"])
        }
        
        do {
            try pngData.write(to: url)
            return nil
        } catch {
            print("❌ Failed to save \(url.lastPathComponent): \(error)")
            return error
        }
    }
    
    private func generateIOSContentsJSON(at folderURL: URL) {
        var images: [[String: Any]] = []
        
        for config in iosSizes {
            images.append([
                "filename": config.filename,
                "idiom": config.idiom,
                "scale": config.scale,
                "size": config.size
            ])
        }
        
        let contentsJSON: [String: Any] = [
            "images": images,
            "info": [
                "author": "xcode",
                "version": 1
            ]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: contentsJSON, options: [.prettyPrinted, .sortedKeys])
            let contentsURL = folderURL.appendingPathComponent("Contents.json")
            try jsonData.write(to: contentsURL)
            print("✅ Generated iOS Contents.json")
        } catch {
            print("❌ Failed to generate iOS Contents.json: \(error)")
        }
    }
    
    private func generateIOSUniversalContentsJSON(at folderURL: URL) {
        var images: [[String: Any]] = []
        
        for config in iosUniversalSizes {
            images.append([
                "filename": config.filename,
                "idiom": config.idiom,
                "scale": config.scale,
                "size": config.size
            ])
        }
        
        let contentsJSON: [String: Any] = [
            "images": images,
            "info": [
                "author": "xcode",
                "version": 1
            ]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: contentsJSON, options: [.prettyPrinted, .sortedKeys])
            let contentsURL = folderURL.appendingPathComponent("Contents.json")
            try jsonData.write(to: contentsURL)
            print("✅ Generated iOS Universal Contents.json")
        } catch {
            print("❌ Failed to generate iOS Universal Contents.json: \(error)")
        }
    }
    
    private func generateMacOSContentsJSON(at folderURL: URL) {
        var images: [[String: Any]] = []
        
        for config in macOSSizes {
            images.append([
                "filename": config.filename,
                "idiom": "mac",
                "scale": config.scale,
                "size": config.size
            ])
        }
        
        let contentsJSON: [String: Any] = [
            "images": images,
            "info": [
                "author": "xcode",
                "version": 1
            ]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: contentsJSON, options: [.prettyPrinted, .sortedKeys])
            let contentsURL = folderURL.appendingPathComponent("Contents.json")
            try jsonData.write(to: contentsURL)
            print("✅ Generated macOS Contents.json")
        } catch {
            print("❌ Failed to generate macOS Contents.json: \(error)")
        }
    }
}

