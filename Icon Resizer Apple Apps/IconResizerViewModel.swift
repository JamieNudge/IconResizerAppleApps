//
//  IconResizerViewModel.swift
//  Icon Resizer
//
//  Handles PNG resizing for all Apple platform icon sizes
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

enum PlatformSelection: String, CaseIterable {
    case both = "iOS + macOS"
    case iOS = "iOS Only"
    case macOS = "macOS Only"
}

class IconResizerViewModel: ObservableObject {
    @Published var isTargeted = false
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var lastOutputFolder: URL?
    @Published var selectedPlatform: PlatformSelection = .both
    
    // All required icon sizes
    let iosSizes: [(name: String, size: CGFloat)] = [
        // iPhone Notification
        ("Icon-20@2x", 40),
        ("Icon-20@3x", 60),
        // iPhone Settings
        ("Icon-29@2x", 58),
        ("Icon-29@3x", 87),
        // iPhone Spotlight
        ("Icon-40@2x", 80),
        ("Icon-40@3x", 120),
        // iPhone App
        ("Icon-60@2x", 120),
        ("Icon-60@3x", 180),
        // iPad Notification
        ("Icon-20", 20),
        // iPad Settings
        ("Icon-29", 29),
        // iPad Spotlight
        ("Icon-40", 40),
        // iPad App
        ("Icon-76", 76),
        ("Icon-76@2x", 152),
        // iPad Pro
        ("Icon-83.5@2x", 167),
        // App Store
        ("Icon-1024", 1024)
    ]
    
    let macOSSizes: [(name: String, size: CGFloat)] = [
        ("icon_16x16", 16),
        ("icon_16x16@2x", 32),
        ("icon_32x32", 32),
        ("icon_32x32@2x", 64),
        ("icon_128x128", 128),
        ("icon_128x128@2x", 256),
        ("icon_256x256", 256),
        ("icon_256x256@2x", 512),
        ("icon_512x512", 512),
        ("icon_512x512@2x", 1024)
    ]
    
    func handleDrop(providers: [NSItemProvider]) {
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
    }
    
    private func resizeAndSaveIcons(sourceImage: NSImage) {
        // Ask user where to save
        let savePanel = NSSavePanel()
        savePanel.title = "Choose where to save app icons"
        savePanel.message = "Select a folder to save the generated icons"
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "AppIcons"
        savePanel.showsTagField = false
        
        savePanel.begin { response in
            guard response == .OK, let outputFolderURL = savePanel.url else {
                self.statusMessage = "❌ Cancelled"
                return
            }
            
            self.isProcessing = true
            self.statusMessage = "🔄 Resizing icons..."
            
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                
                do {
                    var totalGenerated = 0
                    
                    // Generate iOS icons if selected
                    if self.selectedPlatform == .iOS || self.selectedPlatform == .both {
                        let iosFolderURL = self.selectedPlatform == .both 
                            ? outputFolderURL.appendingPathComponent("iOS")
                            : outputFolderURL
                        
                        try fileManager.createDirectory(at: iosFolderURL, withIntermediateDirectories: true)
                        
                        for (name, size) in self.iosSizes {
                            if let resizedImage = self.resize(image: sourceImage, to: size) {
                                let fileURL = iosFolderURL.appendingPathComponent("\(name).png")
                                if self.savePNG(image: resizedImage, to: fileURL) {
                                    totalGenerated += 1
                                }
                            }
                        }
                    }
                    
                    // Generate macOS icons if selected
                    if self.selectedPlatform == .macOS || self.selectedPlatform == .both {
                        let macFolderURL = self.selectedPlatform == .both
                            ? outputFolderURL.appendingPathComponent("macOS")
                            : outputFolderURL
                        
                        try fileManager.createDirectory(at: macFolderURL, withIntermediateDirectories: true)
                        
                        for (name, size) in self.macOSSizes {
                            if let resizedImage = self.resize(image: sourceImage, to: size) {
                                let fileURL = macFolderURL.appendingPathComponent("\(name).png")
                                if self.savePNG(image: resizedImage, to: fileURL) {
                                    totalGenerated += 1
                                }
                            }
                        }
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
    
    private func savePNG(image: NSImage, to url: URL) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try pngData.write(to: url)
            return true
        } catch {
            print("❌ Failed to save \(url.lastPathComponent): \(error)")
            return false
        }
    }
}

