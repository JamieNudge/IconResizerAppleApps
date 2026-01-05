//
//  ContentView.swift
//  Icon Resizer
//
//  Drag & drop PNG to generate all app icon sizes
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var resizer = IconResizerViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: resizer.operationMode == .icons ? "photo.on.rectangle.angled" : "photo.stack")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text(resizer.operationMode == .icons ? "Icon Resizer" : "Screenshot Resizer")
                    .font(.largeTitle.bold())
                
                Text(resizer.operationMode == .icons ? 
                     "Drag & drop a 1024x1024 PNG to generate all app icon sizes" :
                     "Drop multiple screenshots - orientation auto-detected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            
            // Mode selector (Icons vs Screenshots)
            Picker("Mode", selection: $resizer.operationMode) {
                ForEach(OperationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 120)
            
            // Platform selector (conditional based on mode)
            if resizer.operationMode == .icons {
                Picker("Platform", selection: $resizer.selectedPlatform) {
                    ForEach(PlatformSelection.allCases, id: \.self) { platform in
                        Text(platform.rawValue).tag(platform)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 80)
            } else {
                Picker("Device", selection: $resizer.screenshotPlatform) {
                    ForEach(ScreenshotPlatform.allCases, id: \.self) { platform in
                        Text(platform.rawValue).tag(platform)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 120)
            }
            
            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .foregroundColor(resizer.isTargeted ? .blue : .gray)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(resizer.isTargeted ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    )
                
                VStack(spacing: 16) {
                    Image(systemName: resizer.isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 50))
                        .foregroundColor(resizer.isTargeted ? .blue : .gray)
                    
                    Text(resizer.isTargeted ? "Drop PNG here" : "Drag PNG here")
                        .font(.title3)
                        .foregroundColor(resizer.isTargeted ? .blue : .secondary)
                }
            }
            .frame(height: 200)
            .padding(.horizontal, 40)
            .onDrop(of: [.png, .image], isTargeted: $resizer.isTargeted) { providers in
                resizer.handleDrop(providers: providers)
                return true
            }
            
            // Status
            if !resizer.statusMessage.isEmpty {
                Text(resizer.statusMessage)
                    .font(.body)
                    .foregroundColor(resizer.isProcessing ? .orange : (resizer.statusMessage.contains("✅") ? .green : .red))
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
            }
            
            // Progress
            if resizer.isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            }
            
            // Open button
            if resizer.lastOutputFolder != nil {
                Button(action: {
                    if let folder = resizer.lastOutputFolder {
                        // Use activateFileViewerSelecting to reveal folder in Finder
                        // This doesn't require special permissions like open() does
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                }) {
                    Label("Open Output Folder", systemImage: "folder")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                if resizer.operationMode == .icons {
                    Text("Generates:")
                        .font(.caption.bold())
                    
                    if resizer.selectedPlatform == .iOSUniversal {
                        Text("• iOS Universal: 1x, 2x, 3x (all 1024x1024)")
                        Text("  (Single icon for all iOS devices)")
                            .font(.caption2)
                    }
                    
                    if resizer.selectedPlatform == .iOS || resizer.selectedPlatform == .both {
                        Text("• iOS: AppIcon.appiconset with 18 sizes")
                        Text("  (iPhone, iPad, and App Store)")
                            .font(.caption2)
                    }
                    
                    if resizer.selectedPlatform == .macOS || resizer.selectedPlatform == .both {
                        Text("• macOS: AppIcon.appiconset with 10 sizes")
                        Text("  (16x16 to 1024x1024 at 1x and 2x)")
                            .font(.caption2)
                    }
                    
                    Text("• Ready to drag into Xcode Assets.xcassets")
                        .foregroundColor(.green)
                } else {
                    Text("Generates App Store Screenshots:")
                        .font(.caption.bold())
                    
                    if resizer.screenshotPlatform == .iPhone {
                        Text("Portrait screenshots →")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("• 1242 × 2688px + 1284 × 2778px")
                        Text("Landscape screenshots →")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("• 2688 × 1242px + 2778 × 1284px")
                    } else if resizer.screenshotPlatform == .iPad {
                        Text("Portrait screenshots →")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("• 2064 × 2752px + 2048 × 2732px")
                        Text("Landscape screenshots →")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("• 2752 × 2064px + 2732 × 2048px")
                    } else {
                        Text("• 422 × 514px (Ultra 3)")
                        Text("• 410 × 502px (Ultra 1/2)")
                        Text("• 416 × 496px (Series 11)")
                        Text("• 396 × 484px (Series 9/10)")
                        Text("• 368 × 448px (Series 6/7/8)")
                        Text("• 312 × 390px (Series 3/4/5)")
                    }
                    
                    Text("• Auto-saves to Desktop/Apple Icons/")
                        .foregroundColor(.green)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 680)
    }
}

#Preview {
    ContentView()
}

