//
//  ImageCropLabView.swift
//  Icon Resizer
//
//  Single-image square crop, or multi-image collage with per-image crop and layout.
//

import SwiftUI
import UniformTypeIdentifiers

private enum LabResizeCorner: CaseIterable, Hashable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

/// SwiftUI `Slider` requires `step` ≤ span of `in:`; use 1 px when span ≥ 1, otherwise a fine fractional step.
private func labPixelSliderStep(lower: CGFloat, upper: CGFloat) -> CGFloat {
    let span = upper - lower
    if span <= 0 { return 0.001 }
    if span < 1 { return max(0.0001, span / 50) }
    return 1
}

private struct LabResizeSession {
    let corner: LabResizeCorner
    let startOx: CGFloat
    let startOy: CGFloat
    let startS: CGFloat
}

private struct BlogRectResizeSession {
    let corner: LabResizeCorner
    let start: CGRect
    let ar: CGFloat
}

struct ImageCropLabView: View {
    /// Finder file drops use `fileURL`; include common image UTIs so `onDrop` accepts the drag.
    private static let labImageDropTypes: [UTType] = [
        .fileURL,
        .image,
        .png,
        .jpeg,
        .tiff,
        .gif,
        .webP,
        .heic,
        .icns
    ]
    
    @ObservedObject var vm: IconResizerViewModel
    @State private var dragTranslation: CGSize = .zero
    @State private var isDropTargeted = false
    @State private var resizeSession: LabResizeSession?
    @State private var blogDragTranslation: CGSize = .zero
    @State private var blogRectResizeSession: BlogRectResizeSession?
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftControlScroll
            Divider()
            rightWorkArea
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private var leftControlScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                labLabeledRow(title: "Working mode") {
                    Picker("", selection: Binding(
                        get: { vm.labCompositingMode },
                        set: { vm.setLabCompositingMode($0) }
                    )) {
                        ForEach(LabCompositingMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                
                labLabeledRow(title: "Folder for lab exports") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let custom = vm.labExportParentURL {
                            Text(custom.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        } else {
                            Text("Default: Desktop/Apple Icons (use top bar for named subfolders)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            Button("Choose existing…") {
                                vm.chooseLabExportParentExisting()
                            }
                            .help("Pick a folder, or use New Folder in the panel to create and open one, then click Open")
                            Button("New folder…") {
                                vm.createAndUseLabExportParentFolder()
                            }
                            .help("Pick a parent, then name the new folder to create for exports")
                        }
                        if vm.labExportParentURL != nil {
                            Button("Use default location") {
                                vm.useDefaultLabExportParent()
                            }
                            .font(.caption)
                        }
                    }
                }
                
                if vm.labCompositingMode == .collage {
                    labLabeledRow(title: "Artboard (logical size)") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Width").font(.caption2).foregroundColor(.secondary)
                                Stepper(
                                    value: Binding(
                                        get: { vm.labCollageCanvasWidth },
                                        set: { vm.setCollageCanvasWidth($0) }
                                    ),
                                    in: 200...2400,
                                    step: 20
                                ) {
                                    Text("\(Int(vm.labCollageCanvasWidth)) pt")
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Height").font(.caption2).foregroundColor(.secondary)
                                Stepper(
                                    value: Binding(
                                        get: { vm.labCollageCanvasHeight },
                                        set: { vm.setCollageCanvasHeight($0) }
                                    ),
                                    in: 200...2000,
                                    step: 20
                                ) {
                                    Text("\(Int(vm.labCollageCanvasHeight)) pt")
                                }
                            }
                        }
                    }
                    
                    labLabeledRow(title: "Export (longest edge, px)") {
                        Picker("", selection: $vm.labCollageOutputSize) {
                            Text("512").tag(512.0)
                            Text("1024").tag(1024.0)
                            Text("2048").tag(2048.0)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    
                    labLabeledRow(title: "Export background") {
                        Toggle("White (else transparent gaps)", isOn: $vm.labCollageExportWhiteBackground)
                            .help("By default, empty artboard area is transparent in PNG exports. Turn on for an opaque white background (common for blog / social).")
                    }
                    
                    if !vm.labImageEntries.isEmpty {
                        labLabeledRow(title: "Layout") {
                            VStack(alignment: .leading, spacing: 6) {
                                Button("Equal gaps in row (side margins = gaps)") {
                                    vm.distributeCollageLayersHorizontallyEquidistant()
                                }
                                .controlSize(.small)
                                .help("Sorts layers left-to-right by their current x position, then re-spaces so margins and the gaps between boxes are all equal. Layer widths and vertical position stay the same. Fails if total layer width exceeds the artboard; widen the artboard or narrow frames first.")
                            }
                        }
                    }
                    
                    if !vm.labImageEntries.isEmpty {
                        labLabeledRow(title: "Quick blog (collage)") {
                            Button("Create 1200×630 blog content image") {
                                vm.layoutCollageForStandardBlogContent()
                            }
                            .controlSize(.small)
                            .help("Sets a 1200×630 artboard, tiles images in a 2-column grid with no gaps between cells, and fits the blog export frame to the full artboard. Add images first, then use Save blog PNG in Blog / article below.")
                        }
                    }
                }
                
                if !vm.labImageEntries.isEmpty {
                    labLabeledRow(title: "Blog / article (dashed frame on canvas)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("1200×630 — standard blog / OG") {
                                vm.applyStandardBlogHero()
                            }
                            .controlSize(.small)
                            .help("Places a 1200×630 blog or Open Graph style frame. Drag the dashed area, then save or apply.")
                            Picker("Blog frame size", selection: Binding(
                                get: { vm.labActiveBlogContentPreset?.id ?? "off" },
                                set: { id in
                                    if id == "off" { vm.setLabActiveBlogContentPreset(nil) }
                                    else if let p = LabBlogContentPreset.all.first(where: { $0.id == id }) { vm.setLabActiveBlogContentPreset(p) }
                                }
                            )) {
                                Text("Off").tag("off")
                                ForEach(LabBlogContentPreset.all) { p in
                                    Text(p.label).tag(p.id)
                                }
                            }
                            .controlSize(.small)
                            if vm.labActiveBlogContentPreset != nil {
                                HStack(spacing: 8) {
                                    Button("Save blog PNG…") { vm.saveLabBlogImageToFile() }
                                        .help("Saves a PNG at the exact preset size, e.g. 1200×630.")
                                    Button("Apply crop to workspace") { vm.applyLabBlogCropToWorkspace() }
                                        .help("Replaces the lab with a single image at the blog size for further editing.")
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
                
                HStack {
                    Group {
                        if vm.labCompositingMode == .single {
                            Button("Choose image…") {
                                vm.chooseLabImageFile(appendAsCollage: false)
                            }
                        } else {
                            Button("Add image…") {
                                vm.chooseLabImageFile(appendAsCollage: true)
                            }
                        }
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                    
                    if vm.labCompositingMode == .collage, !vm.labImageEntries.isEmpty {
                        Button("Duplicate selected") {
                            vm.duplicateSelectedLabImage()
                        }
                        if vm.labSelectedEntryId != nil {
                            Button("Delete", role: .destructive) {
                                vm.removeSelectedCollageEntry()
                            }
                        }
                    } else if vm.labSourceImage != nil {
                        Button("Reset square to center / max") {
                            vm.resetSelectedLabImageCrop()
                        }
                    }
                }
                
                if !vm.labImageEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Images in lab (tap to select)")
                            .font(.subheadline.weight(.medium))
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 8) {
                                ForEach(vm.labImageEntries) { e in
                                    let sel = (vm.labSelectedEntryId == e.id)
                                    VStack(spacing: 2) {
                                        if let t = thumbnail(for: e.image) {
                                            Image(nsImage: t)
                                                .interpolation(.high)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 56, height: 56)
                                                .clipped()
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .strokeBorder(sel ? Color.blue : Color.clear, lineWidth: 3)
                                                )
                                        }
                                        if let idx = vm.labImageEntries.firstIndex(where: { $0.id == e.id }) {
                                            Text("Image \(idx + 1)")
                                                .font(.caption2)
                                                .foregroundColor(sel ? .primary : .secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { vm.selectLabImage(id: e.id) }
                                }
                            }
                        }
                    }
                }
                
                if vm.labSourceImage != nil, vm.labSelectedEntryId != nil {
                    if vm.labCompositingMode == .single {
                        let (pw, ph) = vm.labBitmapPixelSize()
                        let minDim = max(1, min(pw, ph))
                        let sideUpper = CGFloat(minDim)
                        let sideLower = min(16, sideUpper)
                        let cropSizeV = vm.labSelectedEntry?.cropSize ?? 0
                        let xUpper = max(0, CGFloat(pw) - cropSizeV)
                        let yUpper = max(0, CGFloat(ph) - cropSizeV)
                        let sideSpan = sideUpper - sideLower
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Square crop (image pixels) — selected image")
                                .font(.caption.bold())
                            HStack {
                                Text("Side")
                                if sideSpan > 0 {
                                    Slider(
                                        value: cropBinding(
                                            get: { vm.labSelectedEntry?.cropSize ?? 0 },
                                            set: { vm.setLabCropSize($0) }
                                        ),
                                        in: sideLower...sideUpper,
                                        step: labPixelSliderStep(lower: sideLower, upper: sideUpper),
                                        onEditingChanged: { editing in
                                            collageCropSliderEditingChanged(editing)
                                        },
                                        label: { Text("") }
                                    )
                                    .labelsHidden()
                                } else {
                                    Text("matches image")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer(minLength: 0)
                                }
                                Text("\(Int(cropSizeV)) px")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 56, alignment: .trailing)
                            }
                            HStack {
                                Text("X")
                                if xUpper > 0 {
                                    Slider(
                                        value: cropBinding(
                                            get: { vm.labSelectedEntry?.cropOriginX ?? 0 },
                                            set: { vm.setLabCropOriginX($0) }
                                        ),
                                        in: 0...xUpper,
                                        step: labPixelSliderStep(lower: 0, upper: xUpper),
                                        onEditingChanged: { editing in
                                            collageCropSliderEditingChanged(editing)
                                        },
                                        label: { Text("") }
                                    )
                                    .labelsHidden()
                                } else {
                                    Text("locked (full width)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer(minLength: 0)
                                }
                                Text("\(Int(vm.labSelectedEntry?.cropOriginX ?? 0))")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 56, alignment: .trailing)
                            }
                            HStack {
                                Text("Y")
                                if yUpper > 0 {
                                    Slider(
                                        value: cropBinding(
                                            get: { vm.labSelectedEntry?.cropOriginY ?? 0 },
                                            set: { vm.setLabCropOriginY($0) }
                                        ),
                                        in: 0...yUpper,
                                        step: labPixelSliderStep(lower: 0, upper: yUpper),
                                        onEditingChanged: { editing in
                                            collageCropSliderEditingChanged(editing)
                                        },
                                        label: { Text("") }
                                    )
                                    .labelsHidden()
                                } else {
                                    Text("locked (full height)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer(minLength: 0)
                                }
                                Text("\(Int(vm.labSelectedEntry?.cropOriginY ?? 0))")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 56, alignment: .trailing)
                            }
                            Text("Image \(pw)×\(ph) px — crop \(Int(cropSizeV))×\(Int(cropSizeV)) @ (\(Int(vm.labSelectedEntry?.cropOriginX ?? 0)), \(Int(vm.labSelectedEntry?.cropOriginY ?? 0)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .onAppear { vm.clampSelectedLabEntryCrop() }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if vm.labSelectedEntryId != nil {
                                Toggle("Fill frame (crop edges)", isOn: Binding(
                                    get: { vm.labSelectedEntry?.collageFillsFrame ?? false },
                                    set: { vm.setSelectedCollageLayerFillsFrame($0) }
                                ))
                                .help("On: the image covers the layer box; pulling a side in crops (like object-fit: cover). Off: the full image stays visible in the box (letterbox, object-contain).")
                            }
                            Text("Resize the layer on the canvas; turn on Fill frame when you want to narrow the box without shrinking the whole photo. Use Single mode for the square crop pipeline.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text(vm.labCompositingMode == .collage ? "Save composite as PNG…" : "Save crop as PNG…")
                            Button("Save as PNG…") {
                                vm.saveLabCropToFile()
                            }
                            .keyboardShortcut("s", modifiers: [.command])
                        }
                        HStack(spacing: 12) {
                            Button("Export + sizes") {
                                vm.exportLabCropWithResizedPresets()
                            }
                            .help("Saves native (single) or composite (collage) size plus 128, 256, 512, and 1024 px to Desktop/Apple Icons or ImageLabExports if subfolder is on.")
                        }
                    }
                }
                
                if !vm.labImageEntries.isEmpty {
                    labOutputPipelineSection
                }
                
                labConsoleSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private var rightWorkArea: some View {
        Group {
            if vm.labCompositingMode == .collage {
                CollageCanvasEditorView(vm: vm, isDropTargeted: $isDropTargeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                singleModeEditorPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(12)
    }
    
    private var singleModeEditorPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTargeted ? Color.blue : Color.gray.opacity(0.5), lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
            if let img = vm.labSourceImage {
                previewWithOverlay(image: img)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.dashed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Drop an image file here or use Choose image…")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: Self.labImageDropTypes, isTargeted: $isDropTargeted) { providers in
            vm.handleDrop(providers: providers)
            return true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if vm.labSourceImage != nil {
                Text("Drag inside the square to move · drag orange corners to resize")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)
                    .allowsHitTesting(false)
            }
        }
    }
    
    /// Same export engines as the rest of the app, using the current square crop or collage composite.
    private var labOutputPipelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Also run on this image")
                .font(.subheadline.weight(.semibold))
            Text("Uses your current lab result (single crop or composite). Store and device match the other modes in this app (App Icons, Web headers, Screenshots).")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            labLabeledRow(title: "Store (icons + screenshots)") {
                Picker("", selection: $vm.storeSelection) {
                    ForEach(StoreSelection.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("App icons")
                    .font(.caption.weight(.semibold))
                if vm.storeSelection == .apple {
                    labLabeledRow(title: "Platform") {
                        Picker("", selection: $vm.selectedPlatform) {
                            ForEach(PlatformSelection.allCases, id: \.self) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }
                } else {
                    Text("Launcher mipmaps (ldpi → xxxhdpi) + 512 for Play")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Button("Generate app icon set from lab image") {
                    vm.runIconsFromLabCrop()
                }
                .controlSize(.regular)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Web & article headers")
                    .font(.caption.weight(.semibold))
                Text("OG / share cards and 16:9 headers (same as Web headers mode).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button("Generate web header images") {
                    vm.runBlogHeadersFromLabOutput()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("App Store & Play screenshots")
                    .font(.caption.weight(.semibold))
                if vm.storeSelection == .apple {
                    labLabeledRow(title: "Device") {
                        Picker("", selection: $vm.screenshotPlatform) {
                            ForEach(ScreenshotPlatform.allCases, id: \.self) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }
                } else {
                    labLabeledRow(title: "Device") {
                        Picker("", selection: $vm.androidScreenshotDevice) {
                            ForEach(AndroidScreenshotDevice.allCases, id: \.self) { d in
                                Text(d.rawValue).tag(d)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                    }
                }
                Text("One set of store sizes from the lab image; orientation is detected automatically.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button("Generate store screenshot set") {
                    vm.runStoreScreenshotsFromLabOutput()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
        .padding(.top, 4)
    }
    
    /// Appended in the same vertical scroll as the rest of the lab so the log never overlaps the crop view.
    private var labConsoleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Console")
                .font(.caption.bold())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(vm.labConsoleLines.indices, id: \.self) { i in
                        Text(vm.labConsoleLines[i])
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 200)
            .clipped()
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
        }
        .padding(.top, 4)
    }
    
    private func cropBinding(get: @escaping () -> CGFloat, set: @escaping (CGFloat) -> Void) -> Binding<CGFloat> {
        Binding(get: get, set: set)
    }
    
    private func collageCropSliderEditingChanged(_ editing: Bool) {
        if vm.labCompositingMode == .collage {
            if editing { vm.pushCollageCropSessionStartIfNeeded() }
            else { vm.pushCollageCropSessionEnded() }
        }
    }
    
    @ViewBuilder
    private func labLabeledRow(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func thumbnail(for image: NSImage) -> NSImage? {
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            let w = max(1, rep.pixelsWide)
            let h = max(1, rep.pixelsHigh)
            let s = 56.0
            let scale = min(s / CGFloat(w), s / CGFloat(h))
            let out = NSImage(size: NSSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale))
            out.lockFocus()
            image.draw(
                in: NSRect(x: 0, y: 0, width: out.size.width, height: out.size.height),
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0
            )
            out.unlockFocus()
            return out
        }
        return image
    }
    
    @ViewBuilder
    private func previewWithOverlay(image: NSImage) -> some View {
        let (pw, ph) = vm.labBitmapPixelSize()
        let ox0 = vm.labSelectedEntry?.cropOriginX ?? 0
        let oy0 = vm.labSelectedEntry?.cropOriginY ?? 0
        GeometryReader { geo in
            let fit = min(geo.size.width / CGFloat(pw), geo.size.height / CGFloat(ph))
            let dw = CGFloat(pw) * fit
            let dh = CGFloat(ph) * fit
            let padX = (geo.size.width - dw) / 2
            let padY = (geo.size.height - dh) / 2
            let ox = ox0 + dragTranslation.width / fit
            let oy = oy0 + dragTranslation.height / fit
            let box = (vm.labSelectedEntry?.cropSize ?? 0) * fit
            
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .frame(width: dw, height: dh)
                    .offset(x: padX, y: padY)
                
                if vm.labCompositingMode == .single, vm.labActiveBlogContentPreset != nil, vm.labSelectedEntry?.blogContentRect != nil {
                    singleBlogFrameOverlayBlock(fit: fit, padX: padX, padY: padY)
                        .zIndex(12)
                }
                
                ZStack {
                    Rectangle()
                        .strokeBorder(Color.yellow, lineWidth: 2)
                        .background(Rectangle().fill(Color.yellow.opacity(0.08)))
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    guard resizeSession == nil, blogRectResizeSession == nil else { return }
                                    dragTranslation = value.translation
                                }
                                .onEnded { value in
                                    guard resizeSession == nil, blogRectResizeSession == nil else { return }
                                    vm.addLabCropOriginTranslation(
                                        dx: value.translation.width / fit,
                                        dy: value.translation.height / fit
                                    )
                                    dragTranslation = .zero
                                }
                        )
                    
                    ForEach(LabResizeCorner.allCases, id: \.self) { corner in
                        resizeKnob(corner: corner, boxLen: box, fit: fit)
                    }
                }
                .frame(width: max(1, box), height: max(1, box))
                .offset(x: padX + ox * fit, y: padY + oy * fit)
                .zIndex(10)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
    
    @ViewBuilder
    private func singleBlogFrameOverlayBlock(fit: CGFloat, padX: CGFloat, padY: CGFloat) -> some View {
        if let p = vm.labActiveBlogContentPreset, let b = vm.labSelectedEntry?.blogContentRect {
            let ar = p.aspect
            let display = CGRect(
                x: b.minX + blogDragTranslation.width / fit,
                y: b.minY + blogDragTranslation.height / fit,
                width: b.width,
                height: b.height
            )
            let bw = display.width * fit
            let bh = display.height * fit
            let bx = padX + display.minX * fit
            let by = padY + display.minY * fit
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.cyan.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.cyan.opacity(0.04))
                    )
                    .contentShape(Rectangle())
                    .frame(width: max(1, bw), height: max(1, bh))
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { g in
                                guard resizeSession == nil, blogRectResizeSession == nil else { return }
                                blogDragTranslation = g.translation
                            }
                            .onEnded { g in
                                guard resizeSession == nil, blogRectResizeSession == nil else { return }
                                vm.translateSelectedEntryBlogContentRect(
                                    dx: g.translation.width / fit,
                                    dy: g.translation.height / fit
                                )
                                blogDragTranslation = .zero
                            }
                    )
                Text("\(p.targetWidth)×\(p.targetHeight)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.cyan)
                    .padding(4)
                    .background(Capsule().fill(Color(nsColor: .textBackgroundColor).opacity(0.9)))
                    .offset(x: 4, y: 4)
                ForEach(LabResizeCorner.allCases, id: \.self) { corner in
                    blogRectResizeKnob(corner: corner, br: display, ar: ar, fit: fit, bw: bw, bh: bh)
                }
            }
            .frame(width: max(1, bw), height: max(1, bh), alignment: .topLeading)
            .offset(x: bx, y: by)
        }
    }
    
    @ViewBuilder
    private func blogRectResizeKnob(
        corner: LabResizeCorner,
        br: CGRect,
        ar: CGFloat,
        fit: CGFloat,
        bw: CGFloat,
        bh: CGFloat
    ) -> some View {
        let knob: CGFloat = 20
        let alignment: Alignment = {
            switch corner {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }()
        Circle()
            .fill(Color.cyan.opacity(0.2))
            .overlay(Circle().strokeBorder(Color.cyan, lineWidth: 1.5))
            .frame(width: knob, height: knob)
            .contentShape(Circle())
            .frame(width: max(bw, knob), height: max(bh, knob), alignment: alignment)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if blogRectResizeSession == nil, resizeSession == nil {
                            blogDragTranslation = .zero
                            if let b0 = vm.labSelectedEntry?.blogContentRect {
                                blogRectResizeSession = BlogRectResizeSession(
                                    corner: corner,
                                    start: b0,
                                    ar: ar
                                )
                            }
                        }
                        guard blogRectResizeSession?.corner == corner else { return }
                        applyBlogRectResize(corner: corner, translation: g.translation, fit: fit)
                    }
                    .onEnded { _ in
                        if blogRectResizeSession?.corner == corner {
                            blogRectResizeSession = nil
                            vm.clampSelectedEntryBlogContentRect()
                        }
                    }
            )
    }
    
    private func applyBlogRectResize(corner: LabResizeCorner, translation: CGSize, fit: CGFloat) {
        guard let session = blogRectResizeSession else { return }
        let s = session.start
        let ar = session.ar
        let dx = translation.width / fit
        _ = translation.height / fit
        let nf: CGRect
        switch corner {
        case .bottomTrailing:
            let newW = s.width + dx
            let newH = newW / ar
            nf = CGRect(x: s.minX, y: s.minY, width: newW, height: newH)
        case .topLeading:
            let newW = s.width - dx
            let newH = newW / ar
            nf = CGRect(x: s.maxX - newW, y: s.maxY - newH, width: newW, height: newH)
        case .topTrailing:
            let newW = s.width + dx
            let newH = newW / ar
            nf = CGRect(x: s.minX, y: s.maxY - newH, width: newW, height: newH)
        case .bottomLeading:
            let newW = s.width - dx
            let newH = newW / ar
            nf = CGRect(x: s.maxX - newW, y: s.minY, width: newW, height: newH)
        }
        vm.updateSelectedEntryBlogContentRect(nf)
    }
    
    @ViewBuilder
    private func resizeKnob(corner: LabResizeCorner, boxLen: CGFloat, fit: CGFloat) -> some View {
        let knob: CGFloat = 22
        let alignment: Alignment = {
            switch corner {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }()
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(Circle().strokeBorder(Color.orange, lineWidth: 2))
            .frame(width: knob, height: knob)
            .contentShape(Circle())
            .frame(width: max(boxLen, knob), height: max(boxLen, knob), alignment: alignment)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard blogRectResizeSession == nil else { return }
                        if resizeSession == nil {
                            dragTranslation = .zero
                            if let s = vm.labSelectedEntry {
                                resizeSession = LabResizeSession(
                                    corner: corner,
                                    startOx: s.cropOriginX,
                                    startOy: s.cropOriginY,
                                    startS: s.cropSize
                                )
                            }
                        }
                        guard resizeSession?.corner == corner else { return }
                        applyResize(corner: corner, translation: value.translation, fit: fit)
                    }
                    .onEnded { _ in
                        if resizeSession?.corner == corner {
                            resizeSession = nil
                            vm.clampSelectedLabEntryCrop()
                        }
                    }
            )
    }
    
    private func applyResize(corner: LabResizeCorner, translation: CGSize, fit: CGFloat) {
        guard let session = resizeSession else { return }
        let ix = translation.width / fit
        let iy = translation.height / fit
        let sx = session.startOx
        let sy = session.startOy
        let ss = session.startS
        
        var newS: CGFloat = ss
        var newOx = sx
        var newOy = sy
        
        switch corner {
        case .bottomTrailing:
            let hx = sx + ss + ix
            let hy = sy + ss + iy
            newS = min(hx - sx, hy - sy)
            newOx = sx
            newOy = sy
        case .topLeading:
            let hx = sx + ix
            let hy = sy + iy
            newS = min(sx + ss - hx, sy + ss - hy)
            newOx = sx + ss - newS
            newOy = sy + ss - newS
        case .topTrailing:
            let bx = sx
            let by = sy + ss
            let hx = sx + ss + ix
            let hy = sy + iy
            newS = min(hx - bx, by - hy)
            newOx = sx
            newOy = by - newS
        case .bottomLeading:
            let tx = sx + ss
            let ty = sy
            let hx = sx + ix
            let hy = sy + ss + iy
            newS = min(tx - hx, hy - ty)
            newOx = tx - newS
            newOy = sy
        }
        
        vm.setLabCropFromResize(ox: newOx, oy: newOy, size: newS)
    }
}
