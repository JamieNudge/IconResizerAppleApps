//
//  ContentView.swift
//  Icon Resizer
//
//  Drag & drop PNG to generate all app icon sizes
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var resizer = IconResizerViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Group {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                    } else {
                        Image(systemName: headerSymbol(for: resizer.operationMode))
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                    }
                }
                
                Text(headerTitle(for: resizer.operationMode))
                    .font(.largeTitle.bold())
                
                Text(headerSubtitle(for: resizer.operationMode))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            
            // Mode selector (Icons vs Screenshots)
            labeledSegmentedGroup(title: "Mode") {
                Picker("", selection: $resizer.operationMode) {
                    ForEach(OperationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }
            
            if resizer.operationMode != .blogHeaders && resizer.operationMode != .imageLab {
                labeledSegmentedGroup(title: "Store") {
                    Picker("", selection: $resizer.storeSelection) {
                        ForEach(StoreSelection.allCases, id: \.self) { store in
                            Text(store.rawValue).tag(store)
                        }
                    }
                }
            }
            
            // Platform selector (conditional based on mode)
            if resizer.operationMode != .imageLab && resizer.operationMode == .icons {
                if resizer.storeSelection == .apple {
                    labeledSegmentedGroup(title: "Platform") {
                        Picker("", selection: $resizer.selectedPlatform) {
                            ForEach(PlatformSelection.allCases, id: \.self) { platform in
                                Text(platform.rawValue).tag(platform)
                            }
                        }
                    }
                } else {
                    Text("Launcher mipmaps (ldpi → xxxhdpi) + 512×512 for Play Console")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else if resizer.operationMode != .imageLab && resizer.operationMode == .screenshots {
                if resizer.storeSelection == .apple {
                    labeledSegmentedGroup(title: "Device") {
                        Picker("", selection: $resizer.screenshotPlatform) {
                            ForEach(ScreenshotPlatform.allCases, id: \.self) { platform in
                                Text(platform.rawValue).tag(platform)
                            }
                        }
                    }
                } else {
                    labeledSegmentedGroup(title: "Device") {
                        Picker("", selection: $resizer.androidScreenshotDevice) {
                            ForEach(AndroidScreenshotDevice.allCases, id: \.self) { device in
                                Text(device.rawValue).tag(device)
                            }
                        }
                    }
                }
            }
            
            Toggle(isOn: $resizer.createExportSubfolder) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create a named subfolder in the destination")
                    Text("When off, files go into the folder you pick or Apple Icons directly. When on, adds BlogHeaders, AndroidIcons, iPhone_Screenshots, ImageLabExports, etc.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 40)
            
            if resizer.operationMode == .imageLab {
                ImageCropLabView(vm: resizer)
            } else {
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
                if resizer.operationMode == .imageLab {
                    Text("Image lab")
                        .font(.caption.bold())
                    Text("• Yellow square = crop region in bitmap pixels")
                    Text("• Drag inside the square to move; drag orange corner handles to scale")
                    Text("• Sliders still adjust size and X/Y precisely")
                    Text("• Export crop + sizes writes native square plus 128 / 256 / 512 / 1024 px PNGs (same folder rules as above)")
                    Text("• Save crop as PNG, or run the same App Icons export using your crop (scaled to 1024×1024 when possible)")
                    Text("• Log output appears in the lab console at the bottom of that section")
                        .foregroundColor(.green)
                } else if resizer.operationMode == .blogHeaders {
                    Text("Generates (aspect-fill, no stretch):")
                        .font(.caption.bold())
                    Text("• 1200 × 630px — OG / share card")
                    Text("• 1600 × 900px — 16:9 retina")
                    Text("• 1024 × 576px — 16:9 lighter")
                    Text(resizer.createExportSubfolder
                         ? "• Saved to Desktop/Apple Icons/BlogHeaders/"
                         : "• Saved to Desktop/Apple Icons/")
                        .foregroundColor(.green)
                } else if resizer.operationMode == .icons {
                    Text("Generates:")
                        .font(.caption.bold())
                    
                    if resizer.storeSelection == .android {
                        Text("• res/mipmap-*/ic_launcher.png (square resize)")
                        Text("• play-store/ic_launcher-512.png")
                        Text(resizer.createExportSubfolder
                             ? "• Saved under Desktop/Apple Icons/AndroidIcons/"
                             : "• Saved under Desktop/Apple Icons/ (res/, play-store/)")
                            .foregroundColor(.green)
                    } else {
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
                    }
                } else {
                    Text(resizer.storeSelection == .apple ? "Generates App Store Screenshots:" : "Generates Play-style sizes:")
                        .font(.caption.bold())
                    
                    if resizer.storeSelection == .apple {
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
                    } else if resizer.androidScreenshotDevice == .phone {
                        Text("Portrait → 1080×1920, 1440×2560")
                        Text("Landscape → 1920×1080, 2560×1440")
                    } else {
                        Text("Portrait → 1200×1920, 1600×2560")
                        Text("Landscape → 1920×1200, 2560×1600")
                    }
                    
                    Text(resizer.createExportSubfolder
                         ? "• Auto-saves under Desktop/Apple Icons/<device>_Screenshots/"
                         : "• Auto-saves to Desktop/Apple Icons/")
                        .foregroundColor(.green)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .frame(width: 520, height: 920)
    }
    
    /// Segmented `Picker` titles are laid out beside the control; in a narrow window the label can wrap one letter per line. Keep the title as its own row.
    @ViewBuilder
    private func labeledSegmentedGroup(title: String, @ViewBuilder picker: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            picker()
                .labelsHidden()
                .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
    }
    
    private func headerSymbol(for mode: OperationMode) -> String {
        switch mode {
        case .icons: return "photo.on.rectangle.angled"
        case .screenshots: return "photo.stack"
        case .blogHeaders: return "rectangle.expand.vertical"
        case .imageLab: return "square.dashed.inset.filled"
        }
    }
    
    private func headerTitle(for mode: OperationMode) -> String {
        switch mode {
        case .icons: return "Icon Resizer"
        case .screenshots: return "Screenshot Resizer"
        case .blogHeaders: return "Web header export"
        case .imageLab: return "Image lab"
        }
    }
    
    private func headerSubtitle(for mode: OperationMode) -> String {
        switch mode {
        case .icons:
            return "Drag & drop a 1024x1024 PNG to generate all app icon sizes"
        case .screenshots:
            return "Drop multiple screenshots - orientation auto-detected"
        case .blogHeaders:
            return "Drop one PNG — images are scaled and center-cropped to each preset (like object-cover)"
        case .imageLab:
            return "Square crop in pixels, preview, then save or feed into App Icons export"
        }
    }
}

#Preview {
    ContentView()
}

