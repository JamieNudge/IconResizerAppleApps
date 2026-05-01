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
    
    private var isAndroidIcons: Bool {
        resizer.operationMode == .icons && resizer.storeSelection == .android
    }
    
    /// Android in App Icons or Screenshot Resizer: wide min width, scroll, no fixed height (radio export + drop + footer are taller than 980pt).
    private var isAndroidIconsOrScreenshots: Bool {
        resizer.storeSelection == .android
            && (resizer.operationMode == .icons || resizer.operationMode == .screenshots)
    }
    
    private var phonePlayScreenshotFooter: String {
        let m: String
        switch resizer.androidScreenshotExportSizeMode {
        case .portrait: m = "Portrait: 1080×1920 per image."
        case .landscape: m = "Landscape: 1920×1080 per image."
        case .both: m = "Both: 1080×1920 and 1920×1080 per image."
        }
        return "Phone · \(m) Play: 320–3840px per side, 9:16|16:9, PNG/JPEG ≤8MB; pick 2–8. 24-bit RGB PNG."
    }
    
    private var tabletPlayScreenshotFooter: String {
        let m: String
        switch resizer.androidScreenshotExportSizeMode {
        case .portrait: m = "1080×1920 per image."
        case .landscape: m = "1920×1080 per image."
        case .both: m = "1080×1920 and 1920×1080 per image."
        }
        return "Tablet · \(m) Large-screen Play rules. 24-bit RGB PNG."
    }
    
    private static let imageLabHelpText = """
Single: yellow square = crop; drag inside or use orange handles. \
For blog body shots (e.g. full app window, landscape), choose “Blog / article” → “Article body — full image, max width … (native aspect)” and Save blog PNG (no square). \
Collage: drag layers; orange corners resize. Sliders set square crop for the selected image. \
“Also run on this image” uses the same engines as App Icons, Web headers, and Screenshots (choose Store and device). \
Save / Export + sizes for PNG packs. Subfolder toggle in the top bar controls BlogHeaders, ImageLabExports, store screenshot folders, etc. \
“Folder for lab exports”: choose an existing folder, or create a new one (parent + name), or use the default. \
Logs: left sidebar console.
"""
    
    var body: some View {
        Group {
            if resizer.operationMode == .imageLab {
                imageLabRoot
            } else if isAndroidIconsOrScreenshots {
                ScrollView {
                    standardModeRoot
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                standardModeRoot
            }
        }
        .frame(
            minWidth: resizer.operationMode == .imageLab ? 880 : (isAndroidIconsOrScreenshots ? 1000 : 520),
            minHeight: resizer.operationMode == .imageLab ? 520 : (isAndroidIconsOrScreenshots ? 600 : nil)
        )
        .frame(
            width: resizer.operationMode == .imageLab ? nil : (isAndroidIconsOrScreenshots ? 1000 : 520),
            height: resizer.operationMode == .imageLab ? nil : (isAndroidIconsOrScreenshots ? nil : 980)
        )
        .frame(
            maxWidth: resizer.operationMode == .imageLab ? .infinity : (isAndroidIconsOrScreenshots ? .infinity : nil),
            maxHeight: resizer.operationMode == .imageLab ? .infinity : (isAndroidIconsOrScreenshots ? .infinity : nil)
        )
    }
    
    /// Fills the window: thin chrome + full-height editor. Help lives in the toolbar menu.
    private var imageLabRoot: some View {
        VStack(spacing: 0) {
            imageLabTopBar
            
            if !resizer.statusMessage.isEmpty {
                Text(resizer.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(
                        resizer.isProcessing
                        ? .orange
                        : (resizer.statusMessage.contains("✅") ? .green : .red)
                    )
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
            }
            
            if resizer.isProcessing {
                ProgressView()
                    .scaleEffect(0.85)
                    .padding(.vertical, 4)
            }
            
            ImageCropLabView(vm: resizer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if resizer.lastOutputFolder != nil {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        if let folder = resizer.lastOutputFolder {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                    } label: {
                        Label("Open output folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Text(Self.imageLabHelpText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Label("Image lab tips", systemImage: "questionmark.circle")
                }
            }
        }
    }
    
    private var imageLabTopBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "square.dashed.inset.filled")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image lab")
                        .font(.title2.weight(.semibold))
                    Text(headerSubtitle(for: .imageLab))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .layoutPriority(1)
                
                Spacer(minLength: 8)
                
                Picker("", selection: $resizer.operationMode) {
                    ForEach(OperationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 440)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Batch folder")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Picker("", selection: $resizer.createExportSubfolder) {
                    Text("Direct").tag(false)
                    Text("+ Category").tag(true)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 300)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }
    
    // MARK: - Standard mode: export blocks (reused in single column or Android two-column)
    
    @ViewBuilder
    private var standardExportLocationBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export location")
                .font(.subheadline.weight(.medium))
            Picker("", selection: $resizer.createExportSubfolder) {
                Text("Put files directly in the export folder I choose (or default “Apple Icons”)")
                    .tag(false)
                Text("Create an extra category folder inside that place (e.g. AndroidIcons, BlogHeaders, …)")
                    .tag(true)
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            .fixedSize(horizontal: false, vertical: true)
            Text("“Direct” never adds another wrapper folder; you may still get res/, play-store/, or AppIcon.appiconset *inside* that folder for that format. “Category” adds one more level with that name so batches stay separate.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var standardExportDestinationBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export destination")
                .font(.subheadline.weight(.semibold))
            if let custom = resizer.labExportParentURL {
                Text(custom.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else {
                Text("Default: a folder “Apple Icons” inside Downloads (sandbox allows this). For Desktop or elsewhere, use Choose folder… so macOS grants access.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            HStack(alignment: .center, spacing: 8) {
                Button("Choose folder…") {
                    resizer.chooseLabExportParentExisting()
                }
                if resizer.labExportParentURL != nil {
                    Button("Use default location") {
                        resizer.useDefaultLabExportParent()
                    }
                }
                Button {
                    resizer.openExportOutputInFinder()
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                }
                .help("Show the last export in Finder, or the folder the next run will use for this mode.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
        }
    }
    
    @ViewBuilder
    private var standardModeRoot: some View {
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
            
            if resizer.operationMode != .blogHeaders && resizer.operationMode != .adsenseLogo && resizer.operationMode != .imageLab {
                labeledSegmentedGroup(title: "Store") {
                    Picker("", selection: $resizer.storeSelection) {
                        ForEach(StoreSelection.allCases, id: \.self) { store in
                            Text(store.rawValue).tag(store)
                        }
                    }
                }
            }
            
            // Platform / Android Play options (two columns on wide layout when Android + App Icons)
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
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Play & store listing")
                                .font(.subheadline.weight(.semibold))
                            PlayFeatureGraphicOptions(vm: resizer, horizontalPadding: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Save to disk")
                                .font(.subheadline.weight(.semibold))
                            standardExportLocationBlock
                            standardExportDestinationBlock
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
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
                    labeledSegmentedGroup(title: "Play export size") {
                        Picker("", selection: $resizer.androidScreenshotExportSizeMode) {
                            ForEach(AndroidScreenshotExportSizeMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }
                }
            }
            
            if !isAndroidIcons {
                standardExportLocationBlock
                    .padding(.horizontal, 40)
                standardExportDestinationBlock
                    .frame(maxWidth: isAndroidIconsOrScreenshots ? 920 : 560, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }
            
            // Drop zone — match Image lab: no Button inside the `onDrop` view (macOS hit-testing + drag delivery).
            VStack(spacing: 10) {
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
                        
                        Text(resizer.isTargeted ? "Drop image here" : "Drag image here")
                            .font(.title3)
                            .foregroundColor(resizer.isTargeted ? .blue : .secondary)
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onDrop(of: ImageDropImportTypes.utTypes, isTargeted: $resizer.isTargeted) { providers in
                    resizer.handleDrop(providers: providers)
                    return true
                }
                
                Button("Choose image…") {
                    resizer.openImageViaFilePickerForCurrentMode()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                Text("Same engines as Image lab; button is outside the drop surface so Finder drags aren’t eaten by hit-testing.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(.horizontal, 40)
            
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
            
            if !isAndroidIconsOrScreenshots {
                Spacer()
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                if resizer.operationMode == .blogHeaders {
                    Text("Generates (aspect-fill, no stretch):")
                        .font(.caption.bold())
                    Text("• 1200 × 630px — OG / share card")
                    Text("• 1600 × 900px — 16:9 retina")
                    Text("• 1024 × 576px — 16:9 lighter")
                    Text(resizer.createExportSubfolder
                         ? "• Saved to Downloads/Apple Icons/BlogHeaders/"
                         : "• Saved to Downloads/Apple Icons/")
                        .foregroundColor(.green)
                } else if resizer.operationMode == .adsenseLogo {
                    Text("Google AdSense — privacy message logo")
                        .font(.caption.bold())
                    Text("• 1000 × 200px (5:1) — aspect-fit on white, JPEG")
                    Text("• File size tuned to stay ≤150 KB when possible (Google upload limit)")
                    Text("• Google accepts PNG or JPG; this mode exports JPG")
                    Text(resizer.createExportSubfolder
                         ? "• Saved to Downloads/Apple Icons/AdSenseLogo/ as adsense-privacy-logo-1000x200.jpg"
                         : "• Saved to Downloads/Apple Icons/ as adsense-privacy-logo-1000x200.jpg")
                        .foregroundColor(.green)
                } else if resizer.operationMode == .icons {
                    Text("Generates:")
                        .font(.caption.bold())
                    
                    if resizer.storeSelection == .android {
                        Text("• res/mipmap-*/ic_launcher.png (square resize)")
                        Text("• play-store/ic_launcher-512.png (512×512, 32-bit PNG w/ alpha — aim ≤1MB)")
                        Text("• play-store/feature-graphic-1024x500 — always 1024×500 px, full-bleed fill + aspect-fit mark (see Feature graphic)")
                        Text(resizer.createExportSubfolder
                             ? "• Saved under Downloads/Apple Icons/AndroidIcons/"
                             : "• Saved under Downloads/Apple Icons/ (res/, play-store/)")
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
                        Text(phonePlayScreenshotFooter)
                    } else {
                        Text(tabletPlayScreenshotFooter)
                    }
                    
                    Text(resizer.createExportSubfolder
                         ? "• Auto-saves under Downloads/Apple Icons/<device>_Screenshots/"
                         : "• Auto-saves to Downloads/Apple Icons/")
                        .foregroundColor(.green)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
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
        case .adsenseLogo: return "rectangle.compress.vertical"
        case .imageLab: return "square.dashed.inset.filled"
        }
    }
    
    private func headerTitle(for mode: OperationMode) -> String {
        switch mode {
        case .icons: return "Icon Resizer"
        case .screenshots: return "Screenshot Resizer"
        case .blogHeaders: return "Web header export"
        case .adsenseLogo: return "AdSense privacy logo"
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
        case .adsenseLogo:
            return "Drop a logo — exports a 1000×200 (5:1) JPG on white, auto-tuned to stay under 150 KB"
        case .imageLab:
            return "Crop or collage, then save PNGs, app icons, web headers, or store screenshots"
        }
    }
}

// MARK: - Google Play 1024×500 feature graphic options (shared: main window + Image lab)

struct PlayFeatureGraphicOptions: View {
    @ObservedObject var vm: IconResizerViewModel
    var horizontalPadding: CGFloat = 32
    
    private var playFeatureBackgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: Double(vm.playFeatureGraphicColorRed),
                    green: Double(vm.playFeatureGraphicColorGreen),
                    blue: Double(vm.playFeatureGraphicColorBlue)
                )
            },
            set: { new in
                if let c = NSColor(new).usingColorSpace(.sRGB) {
                    vm.playFeatureGraphicColorRed = c.redComponent
                    vm.playFeatureGraphicColorGreen = c.greenComponent
                    vm.playFeatureGraphicColorBlue = c.blueComponent
                }
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launcher mipmaps (ldpi → xxxhdpi) + 512 for Play, plus feature graphic (Play requires a wide 1024×500 banner, PNG or JPEG on upload).")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Feature graphic (1024×500, Play spec)")
                .font(.subheadline.weight(.semibold))
            ColorPicker("Background", selection: playFeatureBackgroundColorBinding)
            Toggle("Branded gradient (darker toward bottom)", isOn: $vm.playFeatureGraphicUseGradient)
            Toggle("Trim extra transparent space (bigger mark)", isOn: $vm.playFeatureGraphicTrimTransparent)
            Toggle("Reserve ~bottom 24% (Play may overlay title)", isOn: $vm.playFeatureGraphicReserveBottomSafe)
            TextField("App name (optional, right column)", text: $vm.playFeatureGraphicAppName)
                .textFieldStyle(.roundedBorder)
            TextField("Tagline (optional, under name)", text: $vm.playFeatureGraphicTagline)
                .textFieldStyle(.roundedBorder)
            Text("The export is always a full 2.048:1 image (1024px × 500px) with a solid or gradient background edge-to-edge, then your mark scaled to fit inside that canvas—centered in the art area, or in the left column with text on the right. That matches the Play Console guidance (don’t give them a square asset to letterbox; give them a real 1024×500 file).")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
    }
}

