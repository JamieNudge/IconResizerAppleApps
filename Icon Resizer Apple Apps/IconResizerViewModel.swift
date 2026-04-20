//
//  IconResizerViewModel.swift
//  Icon Resizer
//
//  Handles PNG resizing for all Apple platform icon sizes and App Store screenshots
//

import SwiftUI
import AppKit
import Combine
import CoreImage
import UniformTypeIdentifiers

enum OperationMode: String, CaseIterable {
    case icons = "App Icons"
    case screenshots = "App Screenshots"
    case blogHeaders = "Web headers"
    case imageLab = "Image lab"
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

enum StoreSelection: String, CaseIterable {
    case apple = "Apple"
    case android = "Android"
}

/// Google Play–style screenshot buckets when Store is Android.
enum AndroidScreenshotDevice: String, CaseIterable {
    case phone = "Phone"
    case tablet = "Tablet"
}

class IconResizerViewModel: ObservableObject {
    @Published var isTargeted = false
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var lastOutputFolder: URL?
    @Published var selectedPlatform: PlatformSelection = .both
    @Published var operationMode: OperationMode = .icons
    @Published var screenshotPlatform: ScreenshotPlatform = .iPhone
    @Published var storeSelection: StoreSelection = .apple
    @Published var androidScreenshotDevice: AndroidScreenshotDevice = .phone
    /// When true, exports go into `base/<subfolder>` (e.g. BlogHeaders, AndroidIcons). When false, files are written directly into `base` (no extra nesting from the picker).
    @Published var createExportSubfolder: Bool = false
    
    // MARK: - Image lab (square crop in image pixels)
    @Published var labSourceImage: NSImage?
    /// Square crop side length in **bitmap pixels**.
    @Published var labCropSize: CGFloat = 256
    /// Top-left of the crop square in **bitmap pixels** (origin at top-left of image).
    @Published var labCropOriginX: CGFloat = 0
    @Published var labCropOriginY: CGFloat = 0
    @Published var labConsoleLines: [String] = []
    /// Retained while "Choose image…" is showing so we can dismiss it when the user drops a file into the lab instead.
    private var labChooseImageOpenPanel: NSOpenPanel?
    private let ciContext = CIContext(options: nil)
    
    /// `~/Desktop/Apple Icons` for the current user (must match a non-sandboxed build, or exports need the folder picker).
    private var defaultExportBaseFolder: URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        return desktop.appendingPathComponent("Apple Icons", isDirectory: true)
    }
    
    /// Resolves the folder that receives export files for a given base (default `Apple Icons` or a folder chosen in the open panel).
    private func resolvedExportFolder(base: URL, subfolder: String) -> URL {
        if createExportSubfolder {
            return base.appendingPathComponent(subfolder, isDirectory: true)
        }
        return base
    }
    
    /// Finder often supplies file URLs or `public.image` instead of raw PNG bytes; try several representations.
    private func loadImageFromItemProvider(_ provider: NSItemProvider, completion: @escaping (NSImage?) -> Void) {
        let dataTypes: [UTType] = [.png, .jpeg, .tiff, .gif, .webP, .image]
        
        func tryDataTypes(at index: Int) {
            if index >= dataTypes.count {
                tryLoadFileURL()
                return
            }
            let type = dataTypes[index]
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                DispatchQueue.main.async {
                    if let data = data, let img = NSImage(data: data) {
                        completion(img)
                    } else {
                        tryDataTypes(at: index + 1)
                    }
                }
            }
        }
        
        func tryLoadFileURL() {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                completion(nil)
                return
            }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                DispatchQueue.main.async {
                    let fileURL: URL? = {
                        if let u = item as? URL { return u }
                        if let ns = item as? NSURL { return ns as URL }
                        return nil
                    }()
                    guard let fileURL = fileURL else {
                        completion(nil)
                        return
                    }
                    let scoped = fileURL.startAccessingSecurityScopedResource()
                    defer {
                        if scoped { fileURL.stopAccessingSecurityScopedResource() }
                    }
                    completion(NSImage(contentsOf: fileURL))
                }
            }
        }
        
        tryDataTypes(at: 0)
    }
    
    /// `NSImage` can list a small thumbnail `NSBitmapImageRep` before the full-size one; always pick the largest by pixel area.
    private func largestBitmapRep(in image: NSImage) -> NSBitmapImageRep? {
        var best: NSBitmapImageRep?
        var bestArea = 0
        for rep in image.representations {
            guard let bmp = rep as? NSBitmapImageRep else { continue }
            let w = bmp.pixelsWide
            let h = bmp.pixelsHigh
            guard w > 0, h > 0 else { continue }
            let area = w * h
            if area > bestArea {
                bestArea = area
                best = bmp
            }
        }
        return best
    }
    
    /// Single-layer image from the highest-resolution bitmap (Finder / `NSImage` multi-rep drops no longer upscale a tiny first rep).
    private func canonicalSingleLayerImage(_ image: NSImage) -> NSImage? {
        guard let best = largestBitmapRep(in: image) else { return nil }
        let rw = CGFloat(best.pixelsWide)
        let rh = CGFloat(best.pixelsHigh)
        if let cg = best.cgImage {
            return NSImage(cgImage: cg, size: NSSize(width: rw, height: rh))
        }
        if let tiff = best.tiffRepresentation, let dup = NSBitmapImageRep(data: tiff) {
            let img = NSImage(size: NSSize(width: rw, height: rh))
            img.addRepresentation(dup)
            return img
        }
        return nil
    }
    
    /// Draw into one 8-bit RGBA bitmap so `resize(_:to:)` / AppKit drawing always has real pixels (fixes “0 icons” from some PNGs / Finder drops).
    private func flattenImageForIconPipeline(_ image: NSImage) -> NSImage? {
        let base = canonicalSingleLayerImage(image) ?? image
        var pixelW = Int(base.size.width.rounded())
        var pixelH = Int(base.size.height.rounded())
        if let bmp = largestBitmapRep(in: base) {
            pixelW = bmp.pixelsWide
            pixelH = bmp.pixelsHigh
        }
        guard pixelW >= 1, pixelH >= 1 else { return nil }
        let wi = CGFloat(pixelW)
        let hi = CGFloat(pixelH)
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
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
        bitmapRep.size = NSSize(width: wi, height: hi)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current?.imageInterpolation = .high
        base.draw(
            in: NSRect(x: 0, y: 0, width: wi, height: hi),
            from: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        let flat = NSImage(size: NSSize(width: wi, height: hi))
        flat.addRepresentation(bitmapRep)
        return flat
    }
    
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
    
    /// Blog / web header exports (aspect-fill crop, no stretch). Written under `BlogHeaders/`.
    let blogHeaderSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "header-1200x630.png", width: 1200, height: 630, description: "OG / share card"),
        ScreenshotConfig(filename: "header-1600x900.png", width: 1600, height: 900, description: "16:9 retina"),
        ScreenshotConfig(filename: "header-1024x576.png", width: 1024, height: 576, description: "16:9 lighter")
    ]
    
    // Android launcher legacy mipmaps (same artwork in each folder; typical Play / Studio layout).
    struct AndroidLauncherIconConfig {
        let mipmapFolder: String
        let pixelSize: CGFloat
    }
    
    let androidLauncherIcons: [AndroidLauncherIconConfig] = [
        AndroidLauncherIconConfig(mipmapFolder: "mipmap-ldpi", pixelSize: 36),
        AndroidLauncherIconConfig(mipmapFolder: "mipmap-mdpi", pixelSize: 48),
        AndroidLauncherIconConfig(mipmapFolder: "mipmap-hdpi", pixelSize: 72),
        AndroidLauncherIconConfig(mipmapFolder: "mipmap-xhdpi", pixelSize: 96),
        AndroidLauncherIconConfig(mipmapFolder: "mipmap-xxhdpi", pixelSize: 144),
        AndroidLauncherIconConfig(mipmapFolder: "mipmap-xxxhdpi", pixelSize: 192)
    ]
    
    let androidPhonePortraitSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "Android-1080x1920.png", width: 1080, height: 1920, description: "Phone FHD portrait"),
        ScreenshotConfig(filename: "Android-1440x2560.png", width: 1440, height: 2560, description: "Phone QHD portrait")
    ]
    let androidPhoneLandscapeSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "Android-1920x1080.png", width: 1920, height: 1080, description: "Phone FHD landscape"),
        ScreenshotConfig(filename: "Android-2560x1440.png", width: 2560, height: 1440, description: "Phone QHD landscape")
    ]
    let androidTabletPortraitSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "Android-1200x1920.png", width: 1200, height: 1920, description: "10\" tablet portrait"),
        ScreenshotConfig(filename: "Android-1600x2560.png", width: 1600, height: 2560, description: "Tablet portrait")
    ]
    let androidTabletLandscapeSizes: [ScreenshotConfig] = [
        ScreenshotConfig(filename: "Android-1920x1200.png", width: 1920, height: 1200, description: "10\" tablet landscape"),
        ScreenshotConfig(filename: "Android-2560x1600.png", width: 2560, height: 1600, description: "Tablet landscape")
    ]
    
    /// Subfolder name under the output base for screenshot batches.
    private func screenshotOutputFolderComponent() -> String {
        if storeSelection == .android {
            switch androidScreenshotDevice {
            case .phone: return "AndroidPhone_Screenshots"
            case .tablet: return "AndroidTablet_Screenshots"
            }
        }
        return "\(screenshotPlatform.rawValue)_Screenshots"
    }
    
    func handleDrop(providers: [NSItemProvider]) {
        let mode = operationMode
        switch mode {
        case .imageLab:
            guard let provider = providers.first else { return }
            loadImageFromItemProvider(provider) { img in
                guard let img = img else {
                    self.statusMessage = "❌ Could not load image from drop (try PNG/JPEG or drag the file again)"
                    self.labLog("Drop: no image from provider")
                    return
                }
                self.loadLabImage(img)
                self.statusMessage = "✅ Image loaded in Image lab"
            }
        case .icons, .blogHeaders:
            guard let provider = providers.first else { return }
            loadImageFromItemProvider(provider) { img in
                guard let nsImage = img else {
                    self.statusMessage = "❌ Could not load image from drop. Exported PNGs from Finder: try dropping again, or use File ▸ Open in Preview then copy."
                    return
                }
                switch mode {
                case .icons:
                    self.resizeAndSaveIcons(sourceImage: nsImage)
                case .blogHeaders:
                    self.resizeAndSaveBlogHeaders(sourceImage: nsImage)
                case .screenshots, .imageLab:
                    break
                }
            }
        case .screenshots:
            resizeAndSaveMultipleScreenshots(providers: providers)
        }
    }
    
    private func resizeAndSaveBlogHeaders(sourceImage: NSImage) {
        self.isProcessing = true
        self.statusMessage = "🔄 Generating web headers..."
        
        let baseFolder = self.defaultExportBaseFolder
        let outputFolderURL = resolvedExportFolder(base: baseFolder, subfolder: "BlogHeaders")
        let fileManager = FileManager.default
        
        do {
            try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
            self.performBlogHeaderProcessing(sourceImage: sourceImage, outputFolderURL: outputFolderURL)
        } catch {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showSavePanelForBlogHeaders(sourceImage: sourceImage)
            }
        }
    }
    
    private func showSavePanelForBlogHeaders(sourceImage: NSImage) {
        let savePanel = NSOpenPanel()
        savePanel.title = "Choose Output Folder"
        savePanel.message = "Select where to save the BlogHeaders folder"
        savePanel.canChooseFiles = false
        savePanel.canChooseDirectories = true
        savePanel.canCreateDirectories = true
        savePanel.allowsMultipleSelection = false
        savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        
        savePanel.begin { response in
            guard response == .OK, let selectedURL = savePanel.url else {
                self.statusMessage = "❌ Cancelled"
                return
            }
            let outputFolderURL = self.resolvedExportFolder(base: selectedURL, subfolder: "BlogHeaders")
            self.isProcessing = true
            self.statusMessage = "🔄 Generating web headers..."
            self.performBlogHeaderProcessing(sourceImage: sourceImage, outputFolderURL: outputFolderURL)
        }
    }
    
    private func performBlogHeaderProcessing(sourceImage: NSImage, outputFolderURL: URL) {
        // AppKit drawing (NSImage / NSBitmapImageRep) must run on the main thread; background queues often yield empty bitmaps and 0 writes.
        DispatchQueue.main.async {
            let workImage = self.flattenImageForIconPipeline(sourceImage) ?? sourceImage
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
                var totalGenerated = 0
                var firstSaveError: String?
                for config in self.blogHeaderSizes {
                    if let resized = self.resizeAspectFill(image: workImage, width: config.width, height: config.height) {
                        let fileURL = outputFolderURL.appendingPathComponent(config.filename)
                        if let err = self.savePNGWithError(image: resized, to: fileURL) {
                            if firstSaveError == nil { firstSaveError = err.localizedDescription }
                        } else {
                            totalGenerated += 1
                            print("✅ Web header: \(config.filename)")
                        }
                    }
                }
                self.isProcessing = false
                if totalGenerated == 0 {
                    let hint = firstSaveError.map { " (\($0))" } ?? ""
                    self.statusMessage = "❌ No web header files were written (0)\(hint). Try choosing another folder or check permissions for \(outputFolderURL.path)."
                } else {
                    self.statusMessage = "✅ Generated \(totalGenerated) web header images (aspect-fill crop)"
                }
                self.lastOutputFolder = outputFolderURL
                print("📂 Blog headers: \(outputFolderURL.path)")
            } catch {
                self.isProcessing = false
                self.statusMessage = "❌ Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func resizeAndSaveIcons(sourceImage: NSImage) {
        self.isProcessing = true
        self.statusMessage = "🔄 Resizing icons..."
        
        let baseFolder = self.defaultExportBaseFolder
        let outputFolderURL: URL = (self.storeSelection == .android)
            ? resolvedExportFolder(base: baseFolder, subfolder: "AndroidIcons")
            : baseFolder
        let fileManager = FileManager.default
        
        do {
            try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
            if self.storeSelection == .android {
                self.performAndroidIconProcessing(sourceImage: sourceImage, outputFolderURL: outputFolderURL)
            } else {
                self.performIconProcessing(sourceImage: sourceImage, outputFolderURL: outputFolderURL)
            }
        } catch {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showSavePanelForIcons(sourceImage: sourceImage)
            }
        }
    }
    
    private func showSavePanelForIcons(sourceImage: NSImage) {
        let savePanel = NSOpenPanel()
        savePanel.title = "Choose Output Folder"
        savePanel.message = self.storeSelection == .android
            ? "Select where to save the AndroidIcons folder (res + Play 512)"
            : "Select where to save the app icons"
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
            if self.storeSelection == .android {
                let outputFolderURL = self.resolvedExportFolder(base: selectedURL, subfolder: "AndroidIcons")
                self.performAndroidIconProcessing(sourceImage: sourceImage, outputFolderURL: outputFolderURL)
            } else {
                self.performIconProcessing(sourceImage: sourceImage, outputFolderURL: selectedURL)
            }
        }
    }
    
    private func performIconProcessing(sourceImage: NSImage, outputFolderURL: URL) {
        DispatchQueue.main.async {
            let workImage = self.flattenImageForIconPipeline(sourceImage) ?? sourceImage
            let fileManager = FileManager.default
            
            do {
                // Ensure output directory exists
                try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
                
                var totalGenerated = 0
                var firstSaveError: String?
                    
                    // Generate iOS Universal icons if selected
                    if self.selectedPlatform == .iOSUniversal {
                        let appiconsetURL = outputFolderURL.appendingPathComponent("AppIcon.appiconset")
                        try fileManager.createDirectory(at: appiconsetURL, withIntermediateDirectories: true)
                        
                        // Generate universal icons (all 1024x1024)
                        for config in self.iosUniversalSizes {
                            if let resizedImage = self.resize(image: workImage, to: config.pixelSize) {
                                let fileURL = appiconsetURL.appendingPathComponent(config.filename)
                                if let err = self.savePNGWithError(image: resizedImage, to: fileURL) {
                                    if firstSaveError == nil { firstSaveError = err.localizedDescription }
                                } else {
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
                            if let resizedImage = self.resize(image: workImage, to: config.pixelSize) {
                                let fileURL = appiconsetURL.appendingPathComponent(config.filename)
                                if let err = self.savePNGWithError(image: resizedImage, to: fileURL) {
                                    if firstSaveError == nil { firstSaveError = err.localizedDescription }
                                } else {
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
                            if let resizedImage = self.resize(image: workImage, to: config.pixelSize) {
                                let fileURL = appiconsetURL.appendingPathComponent(config.filename)
                                if let err = self.savePNGWithError(image: resizedImage, to: fileURL) {
                                    if firstSaveError == nil { firstSaveError = err.localizedDescription }
                                } else {
                                    totalGenerated += 1
                                }
                            }
                        }
                        
                        // Generate Contents.json for macOS
                        self.generateMacOSContentsJSON(at: appiconsetURL)
                    }
                
                self.isProcessing = false
                let platformText = self.selectedPlatform == .both ? "iOS + macOS" : self.selectedPlatform.rawValue
                if totalGenerated == 0 {
                    let errHint = firstSaveError.map { " Save error: \($0)." } ?? ""
                    self.statusMessage = "❌ No icon files were written (0).\(errHint) Check folder permissions for \(outputFolderURL.path), or try flattening the PNG in Preview and save again."
                } else {
                    self.statusMessage = "✅ Generated \(totalGenerated) \(platformText) icons!"
                }
                self.lastOutputFolder = outputFolderURL
                print("✅ Generated \(totalGenerated) \(platformText) app icons")
                print("📂 Location: \(outputFolderURL.path)")
                
            } catch {
                self.isProcessing = false
                self.statusMessage = "❌ Error: \(error.localizedDescription)"
            }
        }
    }
    
    /// Writes `res/mipmap-*/ic_launcher.png` plus `play-store/ic_launcher-512.png` under `outputFolderURL`.
    private func performAndroidIconProcessing(sourceImage: NSImage, outputFolderURL: URL) {
        DispatchQueue.main.async {
            let workImage = self.flattenImageForIconPipeline(sourceImage) ?? sourceImage
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
                let resRoot = outputFolderURL.appendingPathComponent("res", isDirectory: true)
                let playStoreRoot = outputFolderURL.appendingPathComponent("play-store", isDirectory: true)
                try fileManager.createDirectory(at: playStoreRoot, withIntermediateDirectories: true)
                
                var totalGenerated = 0
                for config in self.androidLauncherIcons {
                    let mipmapURL = resRoot.appendingPathComponent(config.mipmapFolder, isDirectory: true)
                    try fileManager.createDirectory(at: mipmapURL, withIntermediateDirectories: true)
                    if let resizedImage = self.resize(image: workImage, to: config.pixelSize) {
                        let fileURL = mipmapURL.appendingPathComponent("ic_launcher.png")
                        if self.savePNG(image: resizedImage, to: fileURL) {
                            totalGenerated += 1
                        }
                    }
                }
                if let listing = self.resize(image: workImage, to: 512) {
                    let file512 = playStoreRoot.appendingPathComponent("ic_launcher-512.png")
                    if self.savePNG(image: listing, to: file512) {
                        totalGenerated += 1
                    }
                }
                self.isProcessing = false
                self.statusMessage = "✅ Generated \(totalGenerated) Android launcher assets (mipmaps + 512)!"
                self.lastOutputFolder = outputFolderURL
                print("✅ Generated \(totalGenerated) Android launcher assets")
                print("📂 Location: \(outputFolderURL.path)")
            } catch {
                self.isProcessing = false
                self.statusMessage = "❌ Error: \(error.localizedDescription)"
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
        let baseFolder = self.defaultExportBaseFolder
        let defaultOutputURL = resolvedExportFolder(base: baseFolder, subfolder: self.screenshotOutputFolderComponent())
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
            
            let outputFolderURL = self.resolvedExportFolder(base: selectedURL, subfolder: self.screenshotOutputFolderComponent())
            self.isProcessing = true
            self.statusMessage = "🔄 Resizing \(images.count) screenshots..."
            self.performScreenshotProcessing(images: images, outputFolderURL: outputFolderURL)
        }
    }
    
    private func performScreenshotProcessing(images: [NSImage], outputFolderURL: URL) {
        DispatchQueue.main.async {
            let fileManager = FileManager.default
            
            do {
                try fileManager.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
                
                var totalGenerated = 0
                var permissionErrorOccurred = false
                let platformName: String = {
                    if self.storeSelection == .android {
                        switch self.androidScreenshotDevice {
                        case .phone: return "Android Phone"
                        case .tablet: return "Android Tablet"
                        }
                    }
                    switch self.screenshotPlatform {
                    case .iPhone: return "iPhone"
                    case .iPad: return "iPad"
                    case .appleWatch: return "Watch"
                    }
                }()
                
                // Process each image
                for (index, sourceImage) in images.enumerated() {
                    let imageNumber = index + 1
                    let isPortrait = sourceImage.size.height > sourceImage.size.width
                    
                    let configs: [ScreenshotConfig]
                    if self.storeSelection == .android {
                        switch self.androidScreenshotDevice {
                        case .phone:
                            configs = isPortrait ? self.androidPhonePortraitSizes : self.androidPhoneLandscapeSizes
                        case .tablet:
                            configs = isPortrait ? self.androidTabletPortraitSizes : self.androidTabletLandscapeSizes
                        }
                    } else {
                        switch self.screenshotPlatform {
                        case .iPhone:
                            configs = isPortrait ? self.iPhonePortraitSizes : self.iPhoneLandscapeSizes
                        case .iPad:
                            configs = isPortrait ? self.iPadPortraitSizes : self.iPadLandscapeSizes
                        case .appleWatch:
                            configs = self.appleWatchScreenshotSizes
                        }
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
                    self.isProcessing = false
                    self.showSavePanelForScreenshots(images: images)
                    return
                }
                
                self.isProcessing = false
                self.statusMessage = "✅ Generated \(totalGenerated) screenshots from \(images.count) images!"
                self.lastOutputFolder = outputFolderURL
                print("✅ Generated \(totalGenerated) \(platformName) screenshots from \(images.count) images")
                print("📂 Location: \(outputFolderURL.path)")
            } catch {
                self.isProcessing = false
                self.showSavePanelForScreenshots(images: images)
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
        savePanel.nameFieldStringValue = self.screenshotOutputFolderComponent()
        savePanel.showsTagField = false
        
        // Default to Apple Icons folder if it exists
        let defaultFolder = self.defaultExportBaseFolder
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
            
            DispatchQueue.main.async {
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
                    
                    if self.storeSelection == .android {
                        switch self.androidScreenshotDevice {
                        case .phone:
                            configs = isPortrait ? self.androidPhonePortraitSizes : self.androidPhoneLandscapeSizes
                            platformName = "Android Phone"
                            orientationName = isPortrait ? "Portrait" : "Landscape"
                        case .tablet:
                            configs = isPortrait ? self.androidTabletPortraitSizes : self.androidTabletLandscapeSizes
                            platformName = "Android Tablet"
                            orientationName = isPortrait ? "Portrait" : "Landscape"
                        }
                    } else {
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
                    
                    self.isProcessing = false
                    let orientationText = orientationName.isEmpty ? "" : " \(orientationName)"
                    self.statusMessage = "✅ Generated \(totalGenerated) \(platformName)\(orientationText) screenshots!"
                    self.lastOutputFolder = outputFolderURL
                    print("✅ Generated \(totalGenerated) \(platformName)\(orientationText) screenshots")
                    print("📂 Location: \(outputFolderURL.path)")
                } catch {
                    self.isProcessing = false
                    self.statusMessage = "❌ Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// One draw into a square bitmap. Used by `resize` and the extra pass for tiny outputs.
    private func resizeSingleStep(image: NSImage, to size: CGFloat) -> NSImage? {
        let newSize = NSSize(width: size, height: size)
        
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
        NSGraphicsContext.current?.imageInterpolation = .high
        
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.addRepresentation(bitmapRep)
        
        return resizedImage
    }
    
    /// Tiny slots benefit from Lanczos plus a touch of post-sharpening; plain AppKit draw still leaves the 16px output a little mushy.
    private func resizeTinyIcon(image: NSImage, to size: CGFloat) -> NSImage? {
        guard let bestRep = largestBitmapRep(in: image), let cg = bestRep.cgImage else {
            return nil
        }
        let srcW = CGFloat(cg.width)
        let srcH = CGFloat(cg.height)
        guard srcW > 0, srcH > 0 else { return nil }
        
        let scale = size / srcW
        guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        lanczos.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
        lanczos.setValue(scale, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
        
        var output = lanczos.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        if size <= 16, let sharpen = CIFilter(name: "CISharpenLuminance"), let scaled = output {
            sharpen.setValue(scaled, forKey: kCIInputImageKey)
            sharpen.setValue(0.45, forKey: kCIInputSharpnessKey)
            output = sharpen.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        }
        guard let finalImage = output,
              let outCG = ciContext.createCGImage(finalImage, from: CGRect(x: 0, y: 0, width: size, height: size))
        else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: outCG)
        rep.size = NSSize(width: size, height: size)
        let out = NSImage(size: NSSize(width: size, height: size))
        out.addRepresentation(rep)
        return out
    }
    
    /// Square resize. Very small targets (≤32) use a dedicated tiny-icon path first, then a 64px intermediate fallback.
    private func resize(image: NSImage, to size: CGFloat) -> NSImage? {
        guard size >= 1 else { return nil }
        if size <= 32, let tiny = resizeTinyIcon(image: image, to: size) {
            return tiny
        }
        let minSrc = min(image.size.width, image.size.height)
        let mid: CGFloat = 64
        if size <= 32, minSrc > mid + 0.5 {
            if let pass1 = resizeSingleStep(image: image, to: mid) {
                return resizeSingleStep(image: pass1, to: size)
            }
        }
        return resizeSingleStep(image: image, to: size)
    }
    
    /// Uniform scale to cover `width`×`height`, center-cropped (like CSS `object-cover`). No non-uniform stretch.
    private func resizeAspectFill(image: NSImage, width: CGFloat, height: CGFloat) -> NSImage? {
        let srcSize = image.size
        guard srcSize.width > 0, srcSize.height > 0 else { return nil }
        
        let w = width
        let h = height
        let scale = max(w / srcSize.width, h / srcSize.height)
        let drawW = srcSize.width * scale
        let drawH = srcSize.height * scale
        let originX = (w - drawW) / 2
        let originY = (h - drawH) / 2
        
        let newSize = NSSize(width: w, height: h)
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(w),
            pixelsHigh: Int(h),
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
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current?.imageInterpolation = .high
        
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).addClip()
        
        image.draw(
            in: NSRect(x: originX, y: originY, width: drawW, height: drawH),
            from: NSRect(origin: .zero, size: srcSize),
            operation: .copy,
            fraction: 1.0
        )
        
        let out = NSImage(size: newSize)
        out.addRepresentation(bitmapRep)
        return out
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
        NSGraphicsContext.current?.imageInterpolation = .high
        
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
        // Prefer the image's bitmap rep(s) — round-tripping full-image TIFF can fail for some decoded/dropped PNGs.
        let pngData: Data? = {
            for rep in image.representations {
                guard let bmp = rep as? NSBitmapImageRep else { continue }
                if let data = bmp.representation(using: .png, properties: [:]) {
                    return data
                }
            }
            guard let tiffData = image.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let data = bitmapImage.representation(using: .png, properties: [:]) else {
                return nil
            }
            return data
        }()
        
        guard let pngData = pngData else {
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
    
    // MARK: - Image lab helpers
    
    func labBitmapPixelSize() -> (Int, Int) {
        guard let img = labSourceImage else { return (1, 1) }
        if let bmp = largestBitmapRep(in: img) {
            return (bmp.pixelsWide, bmp.pixelsHigh)
        }
        return (max(1, Int(img.size.width)), max(1, Int(img.size.height)))
    }
    
    func labLog(_ message: String) {
        let df = DateFormatter()
        df.timeStyle = .medium
        df.dateStyle = .none
        let stamp = df.string(from: Date())
        labConsoleLines.append("[\(stamp)] \(message)")
        if labConsoleLines.count > 150 {
            labConsoleLines.removeFirst(labConsoleLines.count - 150)
        }
    }
    
    private func dismissLabChooseImagePanelIfNeeded() {
        guard let panel = labChooseImageOpenPanel else { return }
        labChooseImageOpenPanel = nil
        panel.orderOut(nil)
        panel.close()
    }
    
    func loadLabImage(_ image: NSImage) {
        dismissLabChooseImagePanelIfNeeded()
        labSourceImage = canonicalSingleLayerImage(image) ?? image
        let (w, h) = labBitmapPixelSize()
        let side = CGFloat(max(1, min(w, h)))
        // Start with largest square that fits (may be < 16 px for tiny bitmaps).
        labCropSize = side
        labCropOriginX = (CGFloat(w) - labCropSize) / 2
        labCropOriginY = (CGFloat(h) - labCropSize) / 2
        clampLabCrop()
        labLog("Loaded \(w)×\(h) px — square crop \(Int(labCropSize)) px centered")
    }
    
    func clampLabCrop() {
        let (w, h) = labBitmapPixelSize()
        let maxSide = CGFloat(max(1, min(w, h)))
        let minSide = min(16, maxSide)
        // Integer pixel geometry (corner drags can leave sub-pixel floats and break Sliders with step 1).
        labCropSize = CGFloat(Int(labCropSize.rounded()))
        labCropSize = min(max(minSide, labCropSize), maxSide)
        labCropOriginX = CGFloat(Int(labCropOriginX.rounded()))
        labCropOriginY = CGFloat(Int(labCropOriginY.rounded()))
        let maxOriginX = max(0, CGFloat(w) - labCropSize)
        let maxOriginY = max(0, CGFloat(h) - labCropSize)
        labCropOriginX = min(max(0, labCropOriginX), maxOriginX)
        labCropOriginY = min(max(0, labCropOriginY), maxOriginY)
    }
    
    /// Crops the square defined in top-left pixel coordinates to a new bitmap-backed `NSImage`.
    func croppedLabImage() -> NSImage? {
        guard let source = labSourceImage else {
            labLog("Crop: no source image")
            return nil
        }
        let (pw, ph) = labBitmapPixelSize()
        clampLabCrop()
        let side = labCropSize
        let ox = labCropOriginX
        let oyTop = labCropOriginY
        let yBottom = CGFloat(ph) - oyTop - side
        let fromRect = NSRect(x: ox, y: yBottom, width: side, height: side)
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: out.size),
            from: fromRect,
            operation: .copy,
            fraction: 1.0
        )
        out.unlockFocus()
        labLog("Cropped square \(Int(side)) px from origin (\(Int(ox)),\(Int(oyTop))) top-left")
        return out
    }
    
    func chooseLabImageFile() {
        dismissLabChooseImagePanelIfNeeded()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image for the lab"
        labChooseImageOpenPanel = panel
        panel.begin { response in
            DispatchQueue.main.async {
                switch response {
                case .OK:
                    guard let url = panel.url else {
                        self.dismissLabChooseImagePanelIfNeeded()
                        self.labLog("Open panel: no URL")
                        return
                    }
                    guard let img = NSImage(contentsOf: url) else {
                        self.dismissLabChooseImagePanelIfNeeded()
                        self.labLog("Failed to read image at \(url.lastPathComponent)")
                        return
                    }
                    self.loadLabImage(img)
                    self.statusMessage = "✅ Loaded \(url.lastPathComponent)"
                default:
                    self.dismissLabChooseImagePanelIfNeeded()
                    self.labLog("Open panel cancelled")
                }
            }
        }
    }
    
    func saveLabCropToFile() {
        guard let cropped = croppedLabImage() else {
            statusMessage = "❌ Nothing to save"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "lab-crop.png"
        panel.title = "Save square crop"
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                DispatchQueue.main.async {
                    self.labLog("Save crop cancelled")
                }
                return
            }
            DispatchQueue.main.async {
                if self.savePNG(image: cropped, to: url) {
                    self.statusMessage = "✅ Saved crop to \(url.lastPathComponent)"
                    self.labLog("Saved crop → \(url.path)")
                    self.lastOutputFolder = url.deletingLastPathComponent()
                } else {
                    self.statusMessage = "❌ Could not save PNG"
                    self.labLog("Save PNG failed")
                }
            }
        }
    }
    
    /// Writes native square crop plus 128 / 256 / 512 / 1024 px PNGs using the same default folder + subfolder rules as other exports.
    func exportLabCropWithResizedPresets() {
        guard let cropped = croppedLabImage() else {
            statusMessage = "❌ Nothing to export"
            labLog("Export pack: no crop")
            return
        }
        let baseFolder = self.defaultExportBaseFolder
        let destDir = resolvedExportFolder(base: baseFolder, subfolder: "ImageLabExports")
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            let count = self.writeLabExportPNGPackage(cropped: cropped, to: destDir)
            guard count > 0 else {
                self.statusMessage = "❌ Could not write export files"
                self.labLog("Export pack: write failed")
                return
            }
            self.lastOutputFolder = destDir
            self.statusMessage = "✅ Exported \(count) PNGs (native + resized)"
            self.labLog("Export pack (\(count) files) → \(destDir.path)")
        } catch {
            self.labLog("Default export folder error: \(error.localizedDescription)")
            self.showOpenPanelForLabExportPack(cropped: cropped)
        }
    }
    
    /// Returns number of files written.
    private func writeLabExportPNGPackage(cropped: NSImage, to destDir: URL) -> Int {
        var count = 0
        let side = min(cropped.size.width, cropped.size.height)
        let nativeURL = destDir.appendingPathComponent("imagelab-crop-native-\(Int(side))px.png")
        if savePNG(image: cropped, to: nativeURL) {
            count += 1
        }
        for px in [128, 256, 512, 1024] {
            guard let img = resize(image: cropped, to: CGFloat(px)) else { continue }
            let url = destDir.appendingPathComponent("imagelab-crop-\(px).png")
            if savePNG(image: img, to: url) {
                count += 1
            }
        }
        return count
    }
    
    private func showOpenPanelForLabExportPack(cropped: NSImage) {
        let panel = NSOpenPanel()
        panel.title = "Choose folder for lab exports"
        panel.message = "Select a folder. Files go inside it or in ImageLabExports when the subfolder option is on."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        panel.begin { response in
            guard response == .OK, let selected = panel.url else {
                DispatchQueue.main.async {
                    self.statusMessage = "❌ Export cancelled"
                    self.labLog("Export pack: folder picker cancelled")
                }
                return
            }
            let destDir = self.resolvedExportFolder(base: selected, subfolder: "ImageLabExports")
            DispatchQueue.main.async {
                do {
                    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let count = self.writeLabExportPNGPackage(cropped: cropped, to: destDir)
                    guard count > 0 else {
                        self.statusMessage = "❌ Could not write export files"
                        return
                    }
                    self.lastOutputFolder = destDir
                    self.statusMessage = "✅ Exported \(count) PNGs (native + resized)"
                    self.labLog("Export pack (\(count) files) → \(destDir.path)")
                } catch {
                    self.statusMessage = "❌ \(error.localizedDescription)"
                    self.labLog("Export pack mkdir failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Normalizes crop to 1024×1024 when possible, then runs the same icon export as App Icons mode.
    func runIconsFromLabCrop() {
        guard let cropped = croppedLabImage() else {
            statusMessage = "❌ Crop failed"
            return
        }
        let scaled = resize(image: cropped, to: 1024)
        let toRun = scaled ?? cropped
        if scaled != nil {
            labLog("Normalized crop to 1024×1024 for icon export")
        } else {
            labLog("Using crop at native pixel size (1024 resize unavailable)")
        }
        labLog("Starting App Icons export from lab (current mode unchanged)")
        resizeAndSaveIcons(sourceImage: toRun)
    }
}

