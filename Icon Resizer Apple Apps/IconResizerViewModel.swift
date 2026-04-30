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

/// Which 9:16 / 16:9 export(s) to produce for Google Play (phone or tablet slot).
enum AndroidScreenshotExportSizeMode: String, CaseIterable {
    /// 1080×1920 (9:16) only
    case portrait = "Portrait"
    /// 1920×1080 (16:9) only
    case landscape = "Landscape"
    /// One file of each per source image
    case both = "Both"
}

// MARK: - Image lab: single image or multi-image collage

struct LabImageEntry: Identifiable, Equatable {
    var id: UUID
    var image: NSImage
    var cropSize: CGFloat
    var cropOriginX: CGFloat
    var cropOriginY: CGFloat
    /// Collage only: where this layer is drawn, in **canvas coordinates** (origin top-left). Single mode ignores this.
    var canvasFrame: CGRect
    /// Collage: if `true`, the image **fills** the frame (crops; like CSS `object-cover`). If `false` (default), the **entire** image is visible (letterboxed; `object-contain`).
    var collageFillsFrame: Bool
    /// Collage, aspect-**fit** only: how the image sits in the layer box (e.g. **top** lines up with a tall neighbor). Defaults center/center.
    var collageFitAlignH: CollageLayerFitAlignmentHorizontal
    var collageFitAlignV: CollageLayerFitAlignmentVertical
    /// Single mode: optional blog / article crop in **image pixel** space (origin top-left, y increases downward), same convention as the square crop sliders. `nil` = not set.
    var blogContentRect: CGRect?
    
    static func == (lhs: LabImageEntry, rhs: LabImageEntry) -> Bool { lhs.id == rhs.id }
}

// MARK: - Image lab: blog / article (OG & header) presets

struct LabBlogContentPreset: Identifiable, Hashable, Equatable {
    var id: String
    var label: String
    var targetWidth: Int
    var targetHeight: Int
    /// When `true`, the export is the **entire** bitmap (single: full image; collage: full artboard) scaled down so width is at most `targetWidth`, keeping native aspect. Fixed-aspect hero/OG rules do not apply. `targetHeight` is ignored.
    var isFullImageBody: Bool = false
    var aspect: CGFloat {
        if isFullImageBody { return 1 }
        return CGFloat(targetWidth) / CGFloat(max(1, targetHeight))
    }
    
    /// 1200×630 — standard OG / share card; primary quick action in Image Lab.
    static let standardOG = LabBlogContentPreset(
        id: "1200x630",
        label: "1200×630 (OG / blog hero)",
        targetWidth: 1200,
        targetHeight: 630
    )
    
    /// In-article body: no square crop, no fixed 1.9:1 or 16:9 — same aspect as the screenshot, max width for the web.
    static let bodyMaxWidth1600 = LabBlogContentPreset(
        id: "body-1600w",
        label: "Article body — full image, max width 1600 (native aspect)",
        targetWidth: 1600,
        targetHeight: 0,
        isFullImageBody: true
    )
    static let bodyMaxWidth1200 = LabBlogContentPreset(
        id: "body-1200w",
        label: "Article body — full image, max width 1200 (native aspect)",
        targetWidth: 1200,
        targetHeight: 0,
        isFullImageBody: true
    )
    
    static let all: [LabBlogContentPreset] = [
        .bodyMaxWidth1600,
        .bodyMaxWidth1200,
        .standardOG,
        LabBlogContentPreset(id: "1600x900", label: "1600×900 (16:9)", targetWidth: 1600, targetHeight: 900),
        LabBlogContentPreset(id: "1024x576", label: "1024×576 (16:9)", targetWidth: 1024, targetHeight: 576)
    ]
}

enum LabCompositingMode: String, CaseIterable {
    case single = "Single"
    case collage = "Collage"
}

/// Horizontal placement of image content inside the layer box when using aspect-**fit** (letterbox). Like CSS `object-position` on the x axis. Ignored when the layer uses **fill** (crop).
enum CollageLayerFitAlignmentHorizontal: String, CaseIterable {
    case leading = "Left"
    case center = "Center"
    case trailing = "Right"
}

/// Vertical placement when aspect-fitting. Ignored when the layer uses **fill** (crop).
enum CollageLayerFitAlignmentVertical: String, CaseIterable {
    case top = "Top"
    case center = "Center"
    case bottom = "Bottom"
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
    /// Play phone/tablet screenshot exports: fixed portrait, fixed landscape, or both sizes per image.
    @Published var androidScreenshotExportSizeMode: AndroidScreenshotExportSizeMode = .portrait
    // MARK: - Play Console feature graphic (1024×500) — “movie poster” layout
    /// sRGB indigo-600 (Tailwind) — good default; adjust with Play feature color controls in the UI.
    @Published var playFeatureGraphicColorRed: CGFloat = 0.29
    @Published var playFeatureGraphicColorGreen: CGFloat = 0.27
    @Published var playFeatureGraphicColorBlue: CGFloat = 0.9
    @Published var playFeatureGraphicUseGradient: Bool = true
    @Published var playFeatureGraphicAppName: String = ""
    @Published var playFeatureGraphicTagline: String = ""
    @Published var playFeatureGraphicTrimTransparent: Bool = true
    /// Leave the bottom ~24% as solid brand only (Play may overlay title UI there).
    @Published var playFeatureGraphicReserveBottomSafe: Bool = true
    /// When true, exports go into `base/<subfolder>` (e.g. BlogHeaders, AndroidIcons). When false, files are written directly into `base` (no extra wrapper folder).
    @Published var createExportSubfolder: Bool = false
    /// When set, **all** default exports (Image lab, Web headers, icons, screenshots) use this folder as the base instead of `Desktop/Apple Icons` / the sandbox mirror. Choose via the open panel so macOS grants write access.
    @Published var labExportParentURL: URL? = nil
    
    // MARK: - Image lab (square crop in image pixels) + multi-image collage
    /// All loaded images; the selected one is edited with the crop tools.
    @Published var labImageEntries: [LabImageEntry] = []
    @Published var labSelectedEntryId: UUID?
    @Published var labCompositingMode: LabCompositingMode = .single
    /// Logical size of the collage artboard (layers are placed in this coordinate system).
    @Published var labCollageCanvasWidth: CGFloat = 800
    @Published var labCollageCanvasHeight: CGFloat = 500
    /// Longest edge in pixels of exported composite (and scale used when rendering the PNG).
    @Published var labCollageOutputSize: CGFloat = 1024
    /// When true, composite / blog exports use an opaque **white** artboard behind layers. When false (default), empty areas are **transparent** in the PNG.
    @Published var labCollageExportWhiteBackground: Bool = false
    /// When set, Image Lab shows a blog/OG frame (collage: on artboard; single: on full image) and enables blog export.
    @Published var labActiveBlogContentPreset: LabBlogContentPreset? = nil
    /// Collage: export region in artboard coordinates (top-left), aspect matches `labActiveBlogContentPreset`.
    @Published var labBlogContentFrame: CGRect = .zero
    @Published var labConsoleLines: [String] = []
    /// Retained while "Choose image…" is showing so we can dismiss it when the user drops a file into the lab instead.
    private var labChooseImageOpenPanel: NSOpenPanel?
    private let ciContext = CIContext(options: nil)
    
    // MARK: - Image lab: collage undo / redo
    private struct LabCollageState {
        var entries: [LabImageEntry]
        var canvasW: CGFloat
        var canvasH: CGFloat
        var selectedId: UUID?
        var blogPreset: LabBlogContentPreset?
        var blogContentFrame: CGRect
    }
    private var labCollageUndoStack: [LabCollageState] = []
    private var labCollageRedoStack: [LabCollageState] = []
    private var collageLayerGestureUndoRecorded = false
    private var blogFrameGestureUndoRecorded = false
    private var collageCropSliderPushed = false
    private static let maxCollageUndo = 50
    
    @Published private(set) var collageCanUndo = false
    @Published private(set) var collageCanRedo = false
    
    // MARK: - Image lab: single mode undo / redo
    private var labSingleUndoStack: [LabCollageState] = []
    private var labSingleRedoStack: [LabCollageState] = []
    private var singleCropSliderPushed = false
    private var singleSquareCropGestureRecorded = false
    private var singleBlogFrameGestureRecorded = false
    private static let maxSingleUndo = 50
    
    @Published private(set) var singleCanUndo = false
    @Published private(set) var singleCanRedo = false
    
    var labSelectedEntry: LabImageEntry? {
        guard let id = labSelectedEntryId else { return nil }
        return labImageEntries.first { $0.id == id }
    }
    
    /// Backward compat for views that need the current image for preview.
    var labSourceImage: NSImage? { labSelectedEntry?.image }
    
    private func takeCollageSnapshot() -> LabCollageState {
        LabCollageState(
            entries: labImageEntries.map { $0 },
            canvasW: labCollageCanvasWidth,
            canvasH: labCollageCanvasHeight,
            selectedId: labSelectedEntryId,
            blogPreset: labActiveBlogContentPreset,
            blogContentFrame: labBlogContentFrame
        )
    }
    
    private func applyCollageSnapshot(_ s: LabCollageState) {
        labImageEntries = s.entries
        labCollageCanvasWidth = s.canvasW
        labCollageCanvasHeight = s.canvasH
        labSelectedEntryId = s.selectedId
        labActiveBlogContentPreset = s.blogPreset
        labBlogContentFrame = s.blogContentFrame
        if let sid = labSelectedEntryId, !labImageEntries.contains(where: { $0.id == sid }) {
            labSelectedEntryId = labImageEntries.first?.id
        }
    }
    
    private func updateCollageUndoPublished() {
        collageCanUndo = !labCollageUndoStack.isEmpty
        collageCanRedo = !labCollageRedoStack.isEmpty
    }
    
    private func clearCollageUndoHistory() {
        labCollageUndoStack.removeAll()
        labCollageRedoStack.removeAll()
        collageLayerGestureUndoRecorded = false
        blogFrameGestureUndoRecorded = false
        collageCropSliderPushed = false
        updateCollageUndoPublished()
    }
    
    private func pushCollageUndoBeforeMutation() {
        guard labCompositingMode == .collage else { return }
        let snap = takeCollageSnapshot()
        labCollageUndoStack.append(snap)
        if labCollageUndoStack.count > Self.maxCollageUndo {
            labCollageUndoStack.removeFirst(labCollageUndoStack.count - Self.maxCollageUndo)
        }
        labCollageRedoStack.removeAll()
        updateCollageUndoPublished()
    }
    
    /// Call once at the start of a layer move/resize gesture (collage canvas).
    func collageRecordUndoForLayerDragIfNeeded() {
        guard labCompositingMode == .collage, !collageLayerGestureUndoRecorded else { return }
        pushCollageUndoBeforeMutation()
        collageLayerGestureUndoRecorded = true
    }
    
    func collageRecordLayerDragEnded() {
        collageLayerGestureUndoRecorded = false
    }
    
    func collageRecordUndoForBlogFrameDragIfNeeded() {
        guard labCompositingMode == .collage, !blogFrameGestureUndoRecorded else { return }
        pushCollageUndoBeforeMutation()
        blogFrameGestureUndoRecorded = true
    }
    
    func collageRecordBlogFrameDragEnded() {
        blogFrameGestureUndoRecorded = false
    }
    
    /// Square-crop sliders: one undo step per drag session.
    func pushCollageCropSessionStartIfNeeded() {
        guard labCompositingMode == .collage, !collageCropSliderPushed else { return }
        pushCollageUndoBeforeMutation()
        collageCropSliderPushed = true
    }
    
    func pushCollageCropSessionEnded() {
        collageCropSliderPushed = false
    }
    
    func collageUndo() {
        guard labCompositingMode == .collage, let previous = labCollageUndoStack.popLast() else { return }
        let current = takeCollageSnapshot()
        labCollageRedoStack.append(current)
        applyCollageSnapshot(previous)
        updateCollageUndoPublished()
        labLog("Collage: Undo")
    }
    
    func collageRedo() {
        guard labCompositingMode == .collage, let next = labCollageRedoStack.popLast() else { return }
        let current = takeCollageSnapshot()
        labCollageUndoStack.append(current)
        applyCollageSnapshot(next)
        updateCollageUndoPublished()
        labLog("Collage: Redo")
    }
    
    private func updateSingleUndoPublished() {
        singleCanUndo = !labSingleUndoStack.isEmpty
        singleCanRedo = !labSingleRedoStack.isEmpty
    }
    
    private func clearSingleUndoHistory() {
        labSingleUndoStack.removeAll()
        labSingleRedoStack.removeAll()
        singleCropSliderPushed = false
        singleSquareCropGestureRecorded = false
        singleBlogFrameGestureRecorded = false
        updateSingleUndoPublished()
    }
    
    private func pushSingleUndoBeforeMutation() {
        guard labCompositingMode == .single else { return }
        let snap = takeCollageSnapshot()
        labSingleUndoStack.append(snap)
        if labSingleUndoStack.count > Self.maxSingleUndo {
            labSingleUndoStack.removeFirst(labSingleUndoStack.count - Self.maxSingleUndo)
        }
        labSingleRedoStack.removeAll()
        updateSingleUndoPublished()
    }
    
    /// Square-crop sliders (single): one undo step per drag session.
    func pushSingleCropSessionStartIfNeeded() {
        guard labCompositingMode == .single, !singleCropSliderPushed else { return }
        pushSingleUndoBeforeMutation()
        singleCropSliderPushed = true
    }
    
    func pushSingleCropSessionEnded() {
        singleCropSliderPushed = false
    }
    
    /// Yellow square pan or orange corner resize: one undo step per gesture.
    func singleRecordSquareCropGestureIfNeeded() {
        guard labCompositingMode == .single, !singleSquareCropGestureRecorded else { return }
        pushSingleUndoBeforeMutation()
        singleSquareCropGestureRecorded = true
    }
    
    func singleRecordSquareCropGestureEnded() {
        singleSquareCropGestureRecorded = false
    }
    
    /// Cyan blog frame move or corner resize (single).
    func singleRecordBlogFrameGestureIfNeeded() {
        guard labCompositingMode == .single, !singleBlogFrameGestureRecorded else { return }
        pushSingleUndoBeforeMutation()
        singleBlogFrameGestureRecorded = true
    }
    
    func singleRecordBlogFrameGestureEnded() {
        singleBlogFrameGestureRecorded = false
    }
    
    func singleUndo() {
        guard labCompositingMode == .single, let previous = labSingleUndoStack.popLast() else { return }
        let current = takeCollageSnapshot()
        labSingleRedoStack.append(current)
        applyCollageSnapshot(previous)
        updateSingleUndoPublished()
        labLog("Single: Undo")
    }
    
    func singleRedo() {
        guard labCompositingMode == .single, let next = labSingleRedoStack.popLast() else { return }
        let current = takeCollageSnapshot()
        labSingleUndoStack.append(current)
        applyCollageSnapshot(next)
        updateSingleUndoPublished()
        labLog("Single: Redo")
    }
    
    func setCollageCanvasWidth(_ new: CGFloat) {
        let clamped = min(2400, max(200, new))
        guard clamped != labCollageCanvasWidth else { return }
        if labCompositingMode == .collage { pushCollageUndoBeforeMutation() }
        labCollageCanvasWidth = clamped
        userChangedCollageCanvasSize()
    }
    
    func setCollageCanvasHeight(_ new: CGFloat) {
        let clamped = min(2000, max(200, new))
        guard clamped != labCollageCanvasHeight else { return }
        if labCompositingMode == .collage { pushCollageUndoBeforeMutation() }
        labCollageCanvasHeight = clamped
        userChangedCollageCanvasSize()
    }
    
    /// Removes the selected collage layer (same as the sidebar Remove). Caller should use when `labCompositingMode == .collage`.
    func removeSelectedCollageEntry() {
        guard labCompositingMode == .collage, let id = labSelectedEntryId else { return }
        removeLabImage(id: id)
    }
    
    private func labPixelSize(of image: NSImage) -> (Int, Int) {
        if let bmp = largestBitmapRep(in: image) {
            return (bmp.pixelsWide, bmp.pixelsHigh)
        }
        return (max(1, Int(image.size.width)), max(1, Int(image.size.height)))
    }
    
    private func makeLabEntry(from image: NSImage, canvasFrame: CGRect) -> LabImageEntry {
        let img = canonicalSingleLayerImage(image) ?? image
        let (w, h) = labPixelSize(of: img)
        let side = CGFloat(max(1, min(w, h)))
        return LabImageEntry(
            id: UUID(),
            image: img,
            cropSize: side,
            cropOriginX: (CGFloat(w) - side) / 2,
            cropOriginY: (CGFloat(h) - side) / 2,
            canvasFrame: canvasFrame,
            collageFillsFrame: false,
            collageFitAlignH: .center,
            collageFitAlignV: .center,
            blogContentRect: nil
        )
    }
    
    /// Suggested non-overlapping position for the next layer (index = count before append).
    private func nextDefaultCollageFrame(countBefore: Int) -> CGRect {
        let W = labCollageCanvasWidth
        let H = labCollageCanvasHeight
        let f: CGRect
        switch countBefore {
        case 0: f = CGRect(x: 0, y: 0, width: W * 0.5, height: H)
        case 1: f = CGRect(x: W * 0.5, y: 0, width: W * 0.5, height: H)
        default:
            let i = countBefore
            let col = CGFloat(i % 2)
            let row = CGFloat(i / 2)
            f = CGRect(x: col * (W / 2), y: row * (H / 2), width: W / 2, height: H / 2)
        }
        return clampCanvasFrame(f)
    }
    
    /// Clamps a layer frame to the current canvas and minimum size.
    func clampCanvasFrame(_ r: CGRect) -> CGRect {
        let W = max(1, labCollageCanvasWidth)
        let H = max(1, labCollageCanvasHeight)
        let m: CGFloat = 16
        var f = r
        f.size.width = min(max(f.size.width, m), W)
        f.size.height = min(max(f.size.height, m), H)
        f.origin.x = min(max(0, f.origin.x), W - f.size.width)
        f.origin.y = min(max(0, f.origin.y), H - f.size.height)
        if f.size.width < m { f.size.width = m; f.origin.x = min(f.origin.x, W - m) }
        if f.size.height < m { f.size.height = m; f.origin.y = min(f.origin.y, H - m) }
        return f
    }
    
    func clampAllCollageCanvasFrames() {
        for i in labImageEntries.indices {
            labImageEntries[i].canvasFrame = clampCanvasFrame(labImageEntries[i].canvasFrame)
        }
    }
    
    /// Collage: update layer position/size on the artboard. Coordinates = canvas space, top-left origin.
    func updateEntryCanvasFrame(id: UUID, frame: CGRect) {
        guard let i = labImageEntries.firstIndex(where: { $0.id == id }) else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            labImageEntries[i].canvasFrame = clampCanvasFrame(frame)
        }
    }
    
    func translateEntryCanvasFrame(id: UUID, dx: CGFloat, dy: CGFloat) {
        guard let i = labImageEntries.firstIndex(where: { $0.id == id }) else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            var f = labImageEntries[i].canvasFrame
            f.origin.x += dx
            f.origin.y += dy
            labImageEntries[i].canvasFrame = clampCanvasFrame(f)
        }
    }
    
    /// Collage: per-layer `object-fit` — full image visible vs crop to frame.
    func setSelectedCollageLayerFillsFrame(_ fills: Bool) {
        guard labCompositingMode == .collage, let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        guard labImageEntries[i].collageFillsFrame != fills else { return }
        pushCollageUndoBeforeMutation()
        labImageEntries[i].collageFillsFrame = fills
    }
    
    /// Collage, aspect-**fit** only: where the image sits in the layer (letterbox); export matches. Ignored when **Fill frame** is on.
    func setSelectedCollageLayerFitAlignment(horizontal: CollageLayerFitAlignmentHorizontal, vertical: CollageLayerFitAlignmentVertical) {
        guard labCompositingMode == .collage, let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        guard labImageEntries[i].collageFitAlignH != horizontal || labImageEntries[i].collageFitAlignV != vertical else { return }
        pushCollageUndoBeforeMutation()
        labImageEntries[i].collageFitAlignH = horizontal
        labImageEntries[i].collageFitAlignV = vertical
    }
    
    private static func fitAnchorFractions(for entry: LabImageEntry) -> (x: CGFloat, y: CGFloat) {
        let ax: CGFloat
        switch entry.collageFitAlignH {
        case .leading: ax = 0
        case .center: ax = 0.5
        case .trailing: ax = 1
        }
        // AppKit bitmap: y=0 at bottom; “top” pins content to the top of the box.
        let ay: CGFloat
        switch entry.collageFitAlignV {
        case .bottom: ay = 0
        case .center: ay = 0.5
        case .top: ay = 1
        }
        return (ax, ay)
    }
    
    private func setSingleLabImage(_ image: NSImage) {
        clearSingleUndoHistory()
        let full = CGRect(
            x: 0, y: 0,
            width: labCollageCanvasWidth,
            height: labCollageCanvasHeight
        )
        var e = makeLabEntry(from: image, canvasFrame: full)
        clampLabCrop(&e)
        labImageEntries = [e]
        labSelectedEntryId = e.id
        let (w, h) = labPixelSize(of: e.image)
        labLog("Single: loaded \(w)×\(h) px — square crop \(Int(e.cropSize)) px centered")
    }
    
    private func appendLabImage(_ image: NSImage, recordUndo: Bool = true) {
        if recordUndo, labCompositingMode == .collage { pushCollageUndoBeforeMutation() }
        let cf = nextDefaultCollageFrame(countBefore: labImageEntries.count)
        var e = makeLabEntry(from: image, canvasFrame: cf)
        clampLabCrop(&e)
        labImageEntries.append(e)
        labSelectedEntryId = e.id
        let (w, h) = labPixelSize(of: e.image)
        labLog("Collage: added image \(w)×\(h) px (total \(labImageEntries.count)) @ canvas \(Int(cf.width))×\(Int(cf.height))")
    }
    
    func removeLabImage(id: UUID) {
        if labCompositingMode == .collage { pushCollageUndoBeforeMutation() }
        labImageEntries.removeAll { $0.id == id }
        if labSelectedEntryId == id {
            labSelectedEntryId = labImageEntries.first?.id
        }
        if labCompositingMode == .single, labImageEntries.count > 1, let first = labImageEntries.first {
            labImageEntries = [first]
            labSelectedEntryId = first.id
        }
    }
    
    /// Copy image + independent crop; offset on canvas.
    func duplicateSelectedLabImage() {
        if labCompositingMode == .collage { pushCollageUndoBeforeMutation() }
        guard let e0 = labSelectedEntry else { return }
        var e = e0
        e.id = UUID()
        e.canvasFrame = clampCanvasFrame(e0.canvasFrame.offsetBy(dx: 32, dy: 32))
        labImageEntries.append(e)
        labSelectedEntryId = e.id
        labLog("Duplicated image as new entry")
    }
    
    func selectLabImage(id: UUID) {
        labSelectedEntryId = id
    }
    
    private func applyCompositingModeIfNeeded() {
        if labCompositingMode == .single, labImageEntries.count > 1 {
            if let first = labImageEntries.first {
                labImageEntries = [first]
                labSelectedEntryId = first.id
            }
        }
    }
    
    private func loadAllLabImagesFromProviders(_ providers: [NSItemProvider], done: @escaping (Int) -> Void) {
        let n = providers.count
        guard n > 0 else {
            done(0)
            return
        }
        var slot: [NSImage?] = Array(repeating: nil, count: n)
        let group = DispatchGroup()
        for (i, provider) in providers.enumerated() {
            group.enter()
            loadImageFromItemProvider(provider) { img in
                slot[i] = img
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let images = slot.compactMap { $0 }
            guard !images.isEmpty else {
                done(0)
                return
            }
            if self.labCompositingMode == .collage {
                self.pushCollageUndoBeforeMutation()
            }
            var added = 0
            for img in images {
                self.appendLabImage(img, recordUndo: false)
                added += 1
            }
            done(added)
        }
    }
    
    /// `~/Desktop/Apple Icons` for the current user (must match a non-sandboxed build, or exports need the folder picker).
    private var defaultExportBaseFolder: URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        return desktop.appendingPathComponent("Apple Icons", isDirectory: true)
    }
    
    /// Resolves the folder that receives export files for a given base (default `Apple Icons` or a folder chosen in the open panel).
    /// If the user already opened a folder whose name matches `subfolder` (e.g. they navigated into `BlogHeaders` and the option is on), do not add a second `BlogHeaders/BlogHeaders` level.
    private func resolvedExportFolder(base: URL, subfolder: String) -> URL {
        guard createExportSubfolder else { return base }
        if base.lastPathComponent.compare(subfolder, options: .caseInsensitive) == .orderedSame {
            return base
        }
        return base.appendingPathComponent(subfolder, isDirectory: true)
    }
    
    /// Base directory for Image lab pack exports and lab-triggered blog/icons/screenshot runs (`nil` → `defaultExportBaseFolder`).
    private var effectiveLabExportBase: URL {
        labExportParentURL ?? defaultExportBaseFolder
    }
    
    /// Pick an **existing** folder. Use New Folder in the lower-left to create and enter one, then select Open.
    func chooseLabExportParentExisting() {
        let panel = NSOpenPanel()
        panel.title = "Choose export folder"
        panel.message = "Select an **existing** folder, or use **New Folder** to create a new one, open it, then click Open."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = labExportParentURL ?? defaultExportBaseFolder
        panel.begin { response in
            guard response == .OK, let u = panel.url else {
                return
            }
            DispatchQueue.main.async {
                self.labExportParentURL = u
                self.labLog("Custom export base: \(u.path)")
                self.statusMessage = "✅ Exports will save under: \(u.path)"
            }
        }
    }
    
    /// Asks for a new folder name under a parent the user picks.
    func createAndUseLabExportParentFolder() {
        let parentPanel = NSOpenPanel()
        parentPanel.title = "Where to create the folder"
        parentPanel.message = "Choose the **parent** location, then you’ll be asked for the new folder’s name."
        parentPanel.canChooseFiles = false
        parentPanel.canChooseDirectories = true
        parentPanel.canCreateDirectories = true
        parentPanel.allowsMultipleSelection = false
        parentPanel.directoryURL = labExportParentURL?.deletingLastPathComponent() ?? defaultExportBaseFolder.deletingLastPathComponent()
        parentPanel.begin { response in
            guard response == .OK, let parent = parentPanel.url else { return }
            DispatchQueue.main.async {
                self.presentNewFolderNameSheet(parentURL: parent)
            }
        }
    }
    
    private func presentNewFolderNameSheet(parentURL: URL) {
        let alert = NSAlert()
        alert.messageText = "New export folder"
        alert.informativeText = "A new folder will be created inside:\n\(parentURL.path)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = "Image lab exports"
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard let self = self else { return }
            if result == .alertFirstButtonReturn {
                var name = field.stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { name = "Image lab exports" }
                let newURL = parentURL.appendingPathComponent(name, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true, attributes: nil)
                    self.labExportParentURL = newURL
                    self.labLog("Created export base: \(newURL.path)")
                    self.statusMessage = "✅ Exports will use new folder: \(name)"
                } catch {
                    self.statusMessage = "❌ Couldn’t create folder: \(error.localizedDescription)"
                    self.labLog("Create folder failed: \(error.localizedDescription)")
                }
            }
        }
        if let win = NSApp.keyWindow {
            alert.beginSheetModal(for: win, completionHandler: apply)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            apply(alert.runModal())
        }
    }
    
    /// Clears a custom base so exports use the default `Desktop/Apple Icons` path again.
    func useDefaultLabExportParent() {
        labExportParentURL = nil
        labLog("Export base: default (Desktop/Apple Icons)")
        statusMessage = "Using default export location (Desktop/Apple Icons)"
    }
    
    /// Reveals the most recent successful export in Finder, or the folder the current mode would use next (creates it if needed).
    func openExportOutputInFinder() {
        let target: URL
        if let last = lastOutputFolder, FileManager.default.fileExists(atPath: last.path) {
            target = last
        } else {
            target = urlForOpenInFinderResolvingCurrentMode()
        }
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: nil)
        } catch {
            statusMessage = "❌ Couldn’t open export folder: \(error.localizedDescription)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
    
    private func urlForOpenInFinderResolvingCurrentMode() -> URL {
        let base = effectiveLabExportBase
        switch operationMode {
        case .screenshots:
            return resolvedExportFolder(base: base, subfolder: screenshotOutputFolderComponent())
        case .icons:
            if storeSelection == .android {
                return resolvedExportFolder(base: base, subfolder: "AndroidIcons")
            }
            return base
        case .blogHeaders:
            return resolvedExportFolder(base: base, subfolder: "BlogHeaders")
        case .imageLab:
            return resolvedExportFolder(base: base, subfolder: "ImageLabExports")
        }
    }
    
    /// Finder often supplies file URLs or `public.image` instead of raw PNG bytes; try several representations.
    private func loadImageFromItemProvider(_ provider: NSItemProvider, completion: @escaping (NSImage?) -> Void) {
        let dataTypes: [UTType] = [.png, .jpeg, .tiff, .gif, .webP, .heic, .image]
        
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
    
    /// Pixels, Display P3, and multi-rep `NSImage` sources often draw as **all black** when scaled with `NSImage.draw` into a 3-ch `deviceRGB` bitmap. Flatten to one 8bpc RGBA layer, then scale.
    private func imageNormalizedForScaling(_ image: NSImage) -> NSImage {
        if let f = flattenImageForIconPipeline(image) { return f }
        if let c = canonicalSingleLayerImage(image) { return c }
        return image
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
    
    // MARK: - Google Play screenshot sizes (phone + tablet)
    // One export per source image, matching Play’s phone rule: 9:16 or 16:9, each side 320–3840px, PNG/JPEG ≤8MB.
    // We use 1080×1920 (portrait) and 1920×1080 (landscape) — same as Google’s “promotion” minimums; upload 2–8 of these to the phone slot.
    private static let playStorePortrait9x16: [ScreenshotConfig] = [
        ScreenshotConfig(
            filename: "Android-1080x1920.png",
            width: 1080, height: 1920,
            description: "9:16 portrait (1080×1920) — Play phone screenshots"
        )
    ]
    private static let playStoreLandscape16x9: [ScreenshotConfig] = [
        ScreenshotConfig(
            filename: "Android-1920x1080.png",
            width: 1920, height: 1080,
            description: "16:9 landscape (1920×1080) — Play phone screenshots"
        )
    ]
    /// Phone listing: one 9:16 or one 16:9 file per dropped image (orientation auto-detected).
    let androidPhonePortraitSizes: [ScreenshotConfig] = IconResizerViewModel.playStorePortrait9x16
    let androidPhoneLandscapeSizes: [ScreenshotConfig] = IconResizerViewModel.playStoreLandscape16x9
    /// 7" / 10" / Chromebook: same 9:16 and 16:9 sizes as in Play’s large-screen / tablet guidance.
    let androidTabletPortraitSizes: [ScreenshotConfig] = IconResizerViewModel.playStorePortrait9x16
    let androidTabletLandscapeSizes: [ScreenshotConfig] = IconResizerViewModel.playStoreLandscape16x9
    
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
    
    /// Play: portrait (1080×1920), landscape (1920×1080), or both — ignores source aspect unless you rely on a single size.
    private func androidPlayScreenshotConfigs() -> [ScreenshotConfig] {
        let portrait: [ScreenshotConfig]
        let landscape: [ScreenshotConfig]
        switch androidScreenshotDevice {
        case .phone:
            portrait = androidPhonePortraitSizes
            landscape = androidPhoneLandscapeSizes
        case .tablet:
            portrait = androidTabletPortraitSizes
            landscape = androidTabletLandscapeSizes
        }
        switch androidScreenshotExportSizeMode {
        case .portrait: return portrait
        case .landscape: return landscape
        case .both: return portrait + landscape
        }
    }
    
    func handleDrop(providers: [NSItemProvider]) {
        let mode = operationMode
        switch mode {
        case .imageLab:
            if self.labCompositingMode == .collage, !providers.isEmpty {
                self.loadAllLabImagesFromProviders(providers) { n in
                    if n == 0 {
                        self.statusMessage = "❌ Could not load images from drop (try PNG/JPEG)"
                    } else {
                        self.statusMessage = n == 1
                            ? "✅ 1 image — add more for a collage, or set Mode to Collage to edit"
                            : "✅ Loaded \(n) image(s) in Image lab (collage)"
                    }
                }
            } else {
                guard let provider = providers.first else { return }
                loadImageFromItemProvider(provider) { img in
                    guard let img = img else {
                        self.statusMessage = "❌ Could not load image from drop (try PNG/JPEG or drag the file again)"
                        self.labLog("Drop: no image from provider")
                        return
                    }
                    self.setSingleLabImage(img)
                    self.statusMessage = "✅ Image loaded in Image lab"
                }
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
    
    private func resizeAndSaveBlogHeaders(sourceImage: NSImage, exportBase: URL? = nil) {
        self.isProcessing = true
        self.statusMessage = "🔄 Generating web headers..."
        
        let baseFolder = exportBase ?? self.effectiveLabExportBase
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
        savePanel.message = "Choose the folder to write into. With “category subfolder” on in the app, a BlogHeaders folder is added inside; with direct export, files go right in the folder you pick."
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
    
    private func resizeAndSaveIcons(sourceImage: NSImage, exportBase: URL? = nil) {
        self.isProcessing = true
        self.statusMessage = "🔄 Resizing icons..."
        
        let baseFolder = exportBase ?? self.effectiveLabExportBase
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
            ? "Choose the export folder. Direct mode: res/ and play-store/ go here. With category subfolder: an AndroidIcons folder is created inside the folder you pick."
            : "Choose the folder. Direct mode: icons go here. With category subfolder on, a named folder is added (see the export location setting)."
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
    
    /// Writes `res/mipmap-*/ic_launcher.png`, `play-store/ic_launcher-512.png` (32-bit RGBA), and `play-store/feature-graphic-1024x500.png` (pixel-exact 1024×500, full-bleed background, aspect-fit mark) under `outputFolderURL`.
    private func performAndroidIconProcessing(sourceImage: NSImage, outputFolderURL: URL) {
        DispatchQueue.main.async {
            let workImage = self.flattenImageForIconPipeline(sourceImage) ?? sourceImage
            let fileManager = FileManager.default
            let playStoreIconMaxBytes: UInt64 = 1_000_000
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
                var storeIconSizeWarning: String?
                if let listing = self.resize(image: workImage, to: 512) {
                    let file512 = playStoreRoot.appendingPathComponent("ic_launcher-512.png")
                    if self.savePNG(image: listing, to: file512) {
                        totalGenerated += 1
                        if let attrs = try? fileManager.attributesOfItem(atPath: file512.path),
                           let fsize = attrs[.size] as? NSNumber {
                            let bytes = fsize.uint64Value
                            if bytes > playStoreIconMaxBytes {
                                let kb = max(1, Int(bytes / 1000))
                                storeIconSizeWarning = "ic_launcher-512.png is \(kb)KB — Google Play wants ≤1MB. Simplify artwork or recompress the PNG in another tool."
                                print("⚠️ Play store icon exceeds 1MB: \(file512.path) (\(bytes) bytes)")
                            }
                        }
                    }
                }
                if let feature = self.renderPlayStoreFeatureGraphic1024x500(source: workImage) {
                    let fgURL = playStoreRoot.appendingPathComponent("feature-graphic-1024x500.png")
                    if self.savePNG(image: feature, to: fgURL) {
                        totalGenerated += 1
                    }
                }
                self.isProcessing = false
                var msg = "✅ Generated \(totalGenerated) Android launcher assets (mipmaps + Play store 512 + feature graphic)!"
                if let w = storeIconSizeWarning {
                    msg += " \(w)"
                }
                self.statusMessage = msg
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
        let baseFolder = self.effectiveLabExportBase
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
        savePanel.message = "Choose the folder. Direct: screenshots are saved there. With category subfolder: a device subfolder (e.g. iPhone_Screenshots) is added inside."
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
                    let configs: [ScreenshotConfig]
                    if self.storeSelection == .android {
                        configs = self.androidPlayScreenshotConfigs()
                    } else {
                        let isPortrait = sourceImage.size.height > sourceImage.size.width
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
                    let useOpaquePlay = self.storeSelection == .android
                    for config in configs {
                        let resizedImage: NSImage? = useOpaquePlay
                            ? self.resizeScreenshotOpaque(image: sourceImage, width: config.width, height: config.height)
                            : self.resizeScreenshot(image: sourceImage, width: config.width, height: config.height)
                        if let resizedImage = resizedImage {
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
                        configs = self.androidPlayScreenshotConfigs()
                        platformName = self.androidScreenshotDevice == .phone ? "Android Phone" : "Android Tablet"
                        switch self.androidScreenshotExportSizeMode {
                        case .portrait: orientationName = "Portrait 1080×1920"
                        case .landscape: orientationName = "Landscape 1920×1080"
                        case .both: orientationName = "Portrait + landscape"
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
                    let useOpaquePlay = self.storeSelection == .android
                    for config in configs {
                        let resizedImage: NSImage? = useOpaquePlay
                            ? self.resizeScreenshotOpaque(image: sourceImage, width: config.width, height: config.height)
                            : self.resizeScreenshot(image: sourceImage, width: config.width, height: config.height)
                        if let resizedImage = resizedImage {
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
    
    /// `object-contain` — entire image visible, letterboxed if aspect ratios differ.
    /// - Parameters `anchorX` / `anchorY`: 0…1 position of the fitted image in the box (AppKit bottom-left; y=0 bottom, y=1 top).
    /// - Parameter background: fill behind letterboxing (default clear). Use white for Play feature graphics.
    private func resizeAspectFit(
        image: NSImage,
        width: CGFloat,
        height: CGFloat,
        anchorX: CGFloat = 0.5,
        anchorY: CGFloat = 0.5,
        background: NSColor = .clear
    ) -> NSImage? {
        let srcSize = image.size
        guard srcSize.width > 0, srcSize.height > 0, width > 0, height > 0 else { return nil }
        let w = width
        let h = height
        let scale = min(w / srcSize.width, h / srcSize.height)
        let drawW = srcSize.width * scale
        let drawH = srcSize.height * scale
        let ax = min(1, max(0, anchorX))
        let ay = min(1, max(0, anchorY))
        let originX = (w - drawW) * ax
        let originY = (h - drawH) * ay
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
        background.set()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).fill()
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
    
    // MARK: - Google Play: feature graphic composition
    
    private func playFeatureBaseNSColor() -> NSColor {
        NSColor(
            srgbRed: min(1, max(0, playFeatureGraphicColorRed)),
            green: min(1, max(0, playFeatureGraphicColorGreen)),
            blue: min(1, max(0, playFeatureGraphicColorBlue)),
            alpha: 1
        )
    }
    
    /// Removes fully transparent border so `resizeAspectFit` can scale the mark larger (ignores source canvas padding).
    private func imageByTrimmingTransparentMargins(_ image: NSImage) -> NSImage? {
        let flat = flattenImageForIconPipeline(image) ?? image
        guard let best = largestBitmapRep(in: flat) else { return image }
        let w = best.pixelsWide, h = best.pixelsHigh
        guard w >= 1, h >= 1, best.hasAlpha, best.bitsPerPixel == 32, best.samplesPerPixel == 4 else { return image }
        guard let src = best.bitmapData else { return image }
        let bpr = best.bytesPerRow
        let srcBytes = bpr * h
        var minX = w, minY = h
        var maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let o = y * bpr + x * 4
                if o + 3 >= srcBytes { continue }
                let a = Int(src[o + 3])
                if a > 8 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        if maxX < minX { return image }
        let rw = maxX - minX + 1, rh = maxY - minY + 1
        guard let dst = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: rw,
            pixelsHigh: rh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }
        dst.size = NSSize(width: rw, height: rh)
        guard let dstData = dst.bitmapData, dst.bitsPerPixel == 32, dst.bytesPerRow > 0 else { return image }
        let dstByteCount = dst.bytesPerRow * rh
        for y in 0..<rh {
            for x in 0..<rw {
                let s = (y + minY) * bpr + (x + minX) * 4
                let d = y * dst.bytesPerRow + x * 4
                for k in 0..<4 {
                    if s + k < srcBytes, d + k < dstByteCount { dstData[d + k] = src[s + k] }
                }
            }
        }
        let out = NSImage(size: dst.size)
        out.addRepresentation(dst)
        return out
    }
    
    /// Draws `image` in `box` (AppKit bottom-left) with the same “aspect fit + centered” rules as a hand-made 1024×500 artboard — no sub-bitmap with transparent side padding.
    private func drawImageAspectFitCenteredInBox(
        _ image: NSImage,
        source: NSRect,
        box: NSRect
    ) {
        let sw = source.width, sh = source.height
        guard sw > 0, sh > 0, box.width > 0, box.height > 0 else { return }
        let scale = min(box.width / sw, box.height / sh)
        let outW = sw * scale, outH = sh * scale
        let ox = box.minX + (box.width - outW) / 2
        let oy = box.minY + (box.height - outH) / 2
        image.draw(
            in: NSRect(x: ox, y: oy, width: outW, height: outH),
            from: source,
            operation: .sourceOver,
            fraction: 1.0
        )
    }
    
    /// 1024×500 Play feature graphic: **pixel-exact** wide banner (2.048:1), full-bleed brand fill, then mark drawn with aspect fit so the file matches Play’s spec (avoids a square-aspect upload with letterbox preview).
    private func renderPlayStoreFeatureGraphic1024x500(source workImage: NSImage) -> NSImage? {
        let canvasW: CGFloat = 1024, canvasH: CGFloat = 500
        var hero = workImage
        if playFeatureGraphicTrimTransparent, let t = imageByTrimmingTransparentMargins(hero) {
            hero = t
        }
        if let canonical = canonicalSingleLayerImage(hero) { hero = canonical }
        let base = playFeatureBaseNSColor()
        let darker: NSColor = (base.blended(withFraction: 0.4, of: .black) ?? base).usingColorSpace(.sRGB) ?? base
        let name = playFeatureGraphicAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sub = playFeatureGraphicTagline.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !name.isEmpty || !sub.isEmpty
        let bottomPad: CGFloat = playFeatureGraphicReserveBottomSafe ? min(150, max(0, round(canvasH * 0.24))) : 20
        let heroH: CGFloat = canvasH - bottomPad
        let margin: CGFloat = 20
        let textColumnX: CGFloat = 520
        let iconFieldW: CGFloat = hasText ? (textColumnX - margin) : (canvasW - 2 * margin)
        let iconFieldH: CGFloat = max(80, heroH - 2 * margin)
        let fromRect = NSRect(
            x: 0, y: 0,
            width: hero.size.width, height: hero.size.height
        )
        let iconFieldRect = NSRect(
            x: margin, y: bottomPad + margin,
            width: iconFieldW, height: iconFieldH
        )
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1024,
            pixelsHigh: 500,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        canvas.size = NSSize(width: canvasW, height: canvasH)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        NSGraphicsContext.current?.imageInterpolation = .high
        let full = NSRect(x: 0, y: 0, width: canvasW, height: canvasH)
        if playFeatureGraphicUseGradient,
           let g = NSGradient(
            colors: [base, darker],
            atLocations: [0, 1],
            colorSpace: .sRGB
           ) {
            g.draw(in: full, angle: 90)
        } else {
            base.set()
            full.fill()
        }
        drawImageAspectFitCenteredInBox(hero, source: fromRect, box: iconFieldRect)
        if hasText {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 3
            shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            let pStyle = NSMutableParagraphStyle()
            pStyle.lineBreakMode = .byWordWrapping
            pStyle.alignment = .left
            pStyle.paragraphSpacing = 4
            let textRect = NSRect(
                x: textColumnX + 8,
                y: bottomPad + margin,
                width: canvasW - textColumnX - 24,
                height: max(0, heroH - 2 * margin)
            )
            let m = NSMutableAttributedString()
            if !name.isEmpty {
                m.append(NSAttributedString(string: name, attributes: [
                    .font: NSFont.systemFont(ofSize: 32, weight: .bold),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: pStyle,
                    .shadow: shadow
                ]))
            }
            if !name.isEmpty && !sub.isEmpty { m.append(NSAttributedString(string: "\n", attributes: [:])) }
            if !sub.isEmpty {
                m.append(NSAttributedString(string: sub, attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .regular),
                    .foregroundColor: NSColor(white: 0.95, alpha: 1),
                    .paragraphStyle: pStyle,
                    .shadow: shadow
                ]))
            }
            let b = m.boundingRect(
                with: NSSize(width: textRect.width, height: 10_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let drawH = min(b.height, textRect.height)
            let drawY = textRect.minY + max(0, (textRect.height - b.height) / 2)
            m.draw(
                in: NSRect(
                    x: textRect.minX,
                    y: drawY,
                    width: textRect.width,
                    height: drawH
                )
            )
        }
        let out = NSImage(size: NSSize(width: canvasW, height: canvasH))
        out.addRepresentation(canvas)
        return out
    }
    
    private func resizeScreenshot(image: NSImage, width: CGFloat, height: CGFloat) -> NSImage? {
        let src = imageNormalizedForScaling(image)
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
        
        // Draw image scaled to the exact store dimensions
        let from = NSRect(origin: .zero, size: src.size)
        src.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: from,
            operation: .copy,
            fraction: 1.0
        )
        
        NSGraphicsContext.restoreGraphicsState()
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.addRepresentation(bitmapRep)
        
        return resizedImage
    }
    
    /// Google Play: opaque-looking PNGs on a white letterbox. Uses RGBA 8bpc (not 3-ch RGB) + sourceOver so P3 / odd reps don’t draw black on macOS.
    private func resizeScreenshotOpaque(image: NSImage, width: CGFloat, height: CGFloat) -> NSImage? {
        let src = imageNormalizedForScaling(image)
        let newSize = NSSize(width: width, height: height)
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
        NSColor.white.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: newSize)).fill()
        let from = NSRect(origin: .zero, size: src.size)
        src.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: from,
            operation: .sourceOver,
            fraction: 1.0
        )
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
    
    /// Pixel size of the **selected** source image.
    func labBitmapPixelSize() -> (Int, Int) {
        guard let entry = labSelectedEntry else { return (1, 1) }
        return labPixelSize(of: entry.image)
    }
    
    func setLabCompositingMode(_ mode: LabCompositingMode) {
        if mode != labCompositingMode {
            clearCollageUndoHistory()
            clearSingleUndoHistory()
        }
        labCompositingMode = mode
        applyCompositingModeIfNeeded()
        if mode == .collage {
            clampAllCollageCanvasFrames()
            if let p = labActiveBlogContentPreset {
                labBlogContentFrame = defaultBlogFrameInArtboard(for: p)
            }
        } else if let p = labActiveBlogContentPreset,
                  let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) {
            labImageEntries[i].blogContentRect = defaultBlogContentRectInImage(for: p, entry: labImageEntries[i])
        }
    }
    
    /// Call after changing artboard size so layers stay inside.
    func userChangedCollageCanvasSize() {
        clampAllCollageCanvasFrames()
        if labCompositingMode == .collage, labActiveBlogContentPreset != nil {
            labBlogContentFrame = clampBlogContentFrameInArtboard(labBlogContentFrame)
        }
    }
    
    private func mutateSelectedLabEntry(_ update: (inout LabImageEntry) -> Void) {
        guard let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        update(&labImageEntries[i])
        clampLabCrop(&labImageEntries[i])
    }
    
    func setLabCropSize(_ v: CGFloat) { mutateSelectedLabEntry { $0.cropSize = v } }
    func setLabCropOriginX(_ v: CGFloat) { mutateSelectedLabEntry { $0.cropOriginX = v } }
    func setLabCropOriginY(_ v: CGFloat) { mutateSelectedLabEntry { $0.cropOriginY = v } }
    
    /// Used by drag-to-pan the crop region in the lab overlay.
    func addLabCropOriginTranslation(dx: CGFloat, dy: CGFloat) {
        guard let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        labImageEntries[i].cropOriginX += dx
        labImageEntries[i].cropOriginY += dy
        clampLabCrop(&labImageEntries[i])
    }
    
    /// Used by corner resize in the lab; sets O and side then clamps.
    func setLabCropFromResize(ox: CGFloat, oy: CGFloat, size: CGFloat) {
        guard let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        labImageEntries[i].cropOriginX = ox
        labImageEntries[i].cropOriginY = oy
        labImageEntries[i].cropSize = size
        clampLabCrop(&labImageEntries[i])
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
    
    /// Re-decodes the image and re-centers the square crop for the **selected** entry, or sets a single image when nothing is selected.
    func loadLabImage(_ image: NSImage) {
        dismissLabChooseImagePanelIfNeeded()
        if let sid = labSelectedEntryId, let i = labImageEntries.firstIndex(where: { $0.id == sid }) {
            if labCompositingMode == .collage { pushCollageUndoBeforeMutation() }
            if labCompositingMode == .single { pushSingleUndoBeforeMutation() }
            let keepFrame = labCompositingMode == .collage
            let cf = keepFrame
                ? labImageEntries[i].canvasFrame
                : CGRect(x: 0, y: 0, width: labCollageCanvasWidth, height: labCollageCanvasHeight)
            var e = makeLabEntry(from: image, canvasFrame: cf)
            e.id = sid
            clampLabCrop(&e)
            labImageEntries[i] = e
            if labCompositingMode == .single, let p = labActiveBlogContentPreset {
                labImageEntries[i].blogContentRect = defaultBlogContentRectInImage(for: p, entry: labImageEntries[i])
            }
            let (w, h) = labPixelSize(of: e.image)
            labLog("Re-centered crop on \(w)×\(h) px image for selected entry")
        } else {
            setSingleLabImage(image)
        }
    }
    
    /// Recenter the largest square on the current bitmap (no re-decode) — e.g. Reset.
    func resetSelectedLabImageCrop() {
        if labCompositingMode == .collage { pushCollageUndoBeforeMutation() }
        if labCompositingMode == .single { pushSingleUndoBeforeMutation() }
        guard let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        var e = labImageEntries[i]
        let (w, h) = labPixelSize(of: e.image)
        let side = CGFloat(max(1, min(w, h)))
        e.cropSize = side
        e.cropOriginX = (CGFloat(w) - side) / 2
        e.cropOriginY = (CGFloat(h) - side) / 2
        clampLabCrop(&e)
        labImageEntries[i] = e
        labLog("Reset square to center / max for selected")
    }
    
    private func clampLabCrop(_ e: inout LabImageEntry) {
        let (w, h) = labPixelSize(of: e.image)
        let maxSide = CGFloat(max(1, min(w, h)))
        let minSide = min(16, maxSide)
        e.cropSize = CGFloat(Int(e.cropSize.rounded()))
        e.cropSize = min(max(minSide, e.cropSize), maxSide)
        e.cropOriginX = CGFloat(Int(e.cropOriginX.rounded()))
        e.cropOriginY = CGFloat(Int(e.cropOriginY.rounded()))
        let maxOriginX = max(0, CGFloat(w) - e.cropSize)
        let maxOriginY = max(0, CGFloat(h) - e.cropSize)
        e.cropOriginX = min(max(0, e.cropOriginX), maxOriginX)
        e.cropOriginY = min(max(0, e.cropOriginY), maxOriginY)
    }
    
    /// Clamps the selected live entry (e.g. aftergesture) — public for the crop overlay.
    func clampSelectedLabEntryCrop() {
        guard let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        clampLabCrop(&labImageEntries[i])
    }
    
    /// Thumbnail of the current square crop for a layer (for canvas view).
    func labPreviewCroppedTile(for e: LabImageEntry) -> NSImage? {
        croppedSquare(from: e, log: false)
    }
    
    /// **Collage editor** — full source image (so layers aren’t limited to the single-mode square crop).
    func labCollageLayerFullImage(for e: LabImageEntry) -> NSImage? {
        let raw = e.image
        return flattenImageForIconPipeline(raw) ?? raw
    }
    
    private func croppedSquare(from entry: LabImageEntry, log: Bool) -> NSImage? {
        var e = entry
        clampLabCrop(&e)
        let source = e.image
        let (_, ph) = labPixelSize(of: source)
        let side = e.cropSize
        let ox = e.cropOriginX
        let oyTop = e.cropOriginY
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
        if log {
            labLog("Cropped square \(Int(side)) px from origin (\(Int(ox)),\(Int(oyTop))) top-left")
        }
        return out
    }
    
    /// Freeform collage: each entry’s **full** image is aspect-fitted into that entry’s `canvasFrame` (matches editor: entire image visible in the frame, letterboxed if needed).
    /// - Parameters:
    ///   - exportMaxLongEdge: If `nil`, uses `labCollageOutputSize` as the longest output edge in points/pixels.
    ///   - artboardClip: If non-`nil`, only this rectangle of the artboard (in canvas coordinates) is rendered; use for blog / article exports.
    private func renderCollageComposite(exportMaxLongEdge: CGFloat? = nil, artboardClip: CGRect? = nil) -> NSImage? {
        if labImageEntries.isEmpty { return nil }
        let fullW = max(1, labCollageCanvasWidth)
        let fullH = max(1, labCollageCanvasHeight)
        let fullArt = CGRect(x: 0, y: 0, width: fullW, height: fullH)
        let clip = (artboardClip.map { $0.intersection(fullArt) }) ?? fullArt
        guard !clip.isNull, clip.width >= 1, clip.height >= 1 else { return nil }
        let CW = clip.width
        let CH = clip.height
        let maxE = max(1, exportMaxLongEdge ?? labCollageOutputSize)
        let s = maxE / max(CW, CH)
        let W = CW * s
        let H = CH * s
        let Wi = max(1, Int(ceil(W)))
        let Hi = max(1, Int(ceil(H)))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Wi,
            pixelsHigh: Hi,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: W, height: H)
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        if labCollageExportWhiteBackground {
            NSColor.white.set()
        } else {
            NSColor.clear.set()
        }
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
        for entry in labImageEntries {
            let r = entry.canvasFrame
            if !r.intersects(clip) { continue }
            let rClip = r.offsetBy(dx: -clip.minX, dy: -clip.minY)
            let rDraw = r.intersection(clip).offsetBy(dx: -clip.minX, dy: -clip.minY)
            if rDraw.isNull || rDraw.width < 0.5 || rDraw.height < 0.5 { continue }
            let source = labCollageLayerFullImage(for: entry) ?? entry.image
            let destW = r.size.width * s
            let destH = r.size.height * s
            let destX = rClip.origin.x * s
            let destY = (CH - rClip.origin.y - rClip.size.height) * s
            NSGraphicsContext.saveGraphicsState()
            let clipPath = NSBezierPath(
                rect: NSRect(
                    x: rDraw.minX * s,
                    y: (CH - rDraw.maxY) * s,
                    width: rDraw.width * s,
                    height: rDraw.height * s
                )
            )
            clipPath.addClip()
            let anchors = Self.fitAnchorFractions(for: entry)
            let layerBitmap: NSImage? = entry.collageFillsFrame
                ? resizeAspectFill(image: source, width: destW, height: destH)
                : resizeAspectFit(image: source, width: destW, height: destH, anchorX: anchors.x, anchorY: anchors.y)
            guard let fitted = layerBitmap else {
                NSGraphicsContext.restoreGraphicsState()
                continue
            }
            fitted.draw(
                in: NSRect(x: destX, y: destY, width: destW, height: destH),
                from: NSRect(origin: .zero, size: fitted.size),
                operation: .copy,
                fraction: 1.0
            )
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: W, height: H))
        out.addRepresentation(bitmap)
        return out
    }
    
    // MARK: - Image lab: blog / article frame & export
    
    private func defaultBlogFrameInArtboard(for preset: LabBlogContentPreset) -> CGRect {
        let W = max(1, labCollageCanvasWidth)
        let H = max(1, labCollageCanvasHeight)
        let ar = preset.aspect
        let w: CGFloat
        let h: CGFloat
        if W / H > ar {
            h = H
            w = h * ar
        } else {
            w = W
            h = w / ar
        }
        let x = (W - w) / 2
        let y = (H - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    private func defaultBlogContentRectInImage(for preset: LabBlogContentPreset, entry: LabImageEntry) -> CGRect {
        let (iw, ih) = labPixelSize(of: entry.image)
        let W = CGFloat(max(1, iw))
        let H = CGFloat(max(1, ih))
        if preset.isFullImageBody {
            return CGRect(x: 0, y: 0, width: W, height: H)
        }
        let ar = preset.aspect
        let w: CGFloat
        let h: CGFloat
        if W / H > ar {
            h = H
            w = h * ar
        } else {
            w = W
            h = w / ar
        }
        let x = (W - w) / 2
        let y = (H - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    private func clampBlogContentFrameInArtboard(_ proposed: CGRect) -> CGRect {
        guard let p = labActiveBlogContentPreset else { return proposed }
        if p.isFullImageBody {
            let W = max(1, labCollageCanvasWidth)
            let H = max(1, labCollageCanvasHeight)
            return CGRect(x: 0, y: 0, width: W, height: H)
        }
        let W = max(1, labCollageCanvasWidth)
        let H = max(1, labCollageCanvasHeight)
        let ar = p.aspect
        var w = max(1, proposed.width)
        var h = w / ar
        if h > H { h = H; w = h * ar }
        if w > W { w = W; h = w / ar }
        w = min(w, W)
        h = w / ar
        if h > H { h = H; w = h * ar }
        if w < 1 { w = 1; h = w / ar }
        var x = proposed.minX
        var y = proposed.minY
        x = min(max(0, x), W - w)
        y = min(max(0, y), H - h)
        if x < 0 { x = 0 }
        if y < 0 { y = 0 }
        if w > W { w = W; h = w / ar }
        if h > H { h = H; w = h * ar }
        x = min(max(0, x), W - w)
        y = min(max(0, y), H - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    private func clampBlogContentRectInImage(_ e: inout LabImageEntry) {
        guard let p = labActiveBlogContentPreset else { return }
        if p.isFullImageBody {
            let (iw, ih) = labPixelSize(of: e.image)
            let W = CGFloat(max(1, iw))
            let H = CGFloat(max(1, ih))
            e.blogContentRect = CGRect(x: 0, y: 0, width: W, height: H)
            return
        }
        var r = e.blogContentRect ?? defaultBlogContentRectInImage(for: p, entry: e)
        let (iw, ih) = labPixelSize(of: e.image)
        let W = CGFloat(max(1, iw))
        let H = CGFloat(max(1, ih))
        let ar = p.aspect
        var w = max(1, r.width)
        var h = w / ar
        if h > H { h = H; w = h * ar }
        if w > W { w = W; h = w / ar }
        w = min(w, W)
        h = w / ar
        if h > H { h = H; w = h * ar }
        r.origin.x = min(max(0, r.minX), W - w)
        r.origin.y = min(max(0, r.minY), H - h)
        r.size = CGSize(width: w, height: h)
        e.blogContentRect = r
    }
    
    /// Blog preset for Image Lab (dashed frame + export / apply). Passing `nil` clears the frame on all images.
    func setLabActiveBlogContentPreset(_ preset: LabBlogContentPreset?) {
        let was = labActiveBlogContentPreset
        if preset != was {
            if labCompositingMode == .collage { pushCollageUndoBeforeMutation() }
            if labCompositingMode == .single { pushSingleUndoBeforeMutation() }
        }
        labActiveBlogContentPreset = preset
        if preset == nil {
            labBlogContentFrame = .zero
            for i in labImageEntries.indices {
                labImageEntries[i].blogContentRect = nil
            }
            return
        }
        guard let p = preset else { return }
        if p != was {
            if labCompositingMode == .collage {
                if p.isFullImageBody {
                    let W = max(1, labCollageCanvasWidth)
                    let H = max(1, labCollageCanvasHeight)
                    labBlogContentFrame = CGRect(x: 0, y: 0, width: W, height: H)
                } else {
                    labBlogContentFrame = defaultBlogFrameInArtboard(for: p)
                }
            } else if let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) {
                labImageEntries[i].blogContentRect = defaultBlogContentRectInImage(for: p, entry: labImageEntries[i])
            }
        }
    }
    
    /// One-tap: standard OG / blog-hero 1200×630 frame (re-centers the dashed region even if this preset is already on).
    func applyStandardBlogHero() {
        setLabActiveBlogContentPreset(LabBlogContentPreset.standardOG)
        repositionDefaultBlogFrameForCurrentPreset()
        labLog("Blog / article: 1200×630 (OG) — position the dashed frame, then export or apply crop")
    }
    
    /// Collage: set each layer’s **x** so left-to-right order is preserved and the **gaps** between layers and the **side margins** are all equal (like `space-evenly` for box widths). Y and size are unchanged.
    func distributeCollageLayersHorizontallyEquidistant() {
        guard labCompositingMode == .collage, !labImageEntries.isEmpty else {
            statusMessage = "Add images in Collage mode first"
            return
        }
        let W = max(1, labCollageCanvasWidth)
        let n = labImageEntries.count
        let order = labImageEntries.enumerated()
            .sorted { $0.element.canvasFrame.minX < $1.element.canvasFrame.minX }
            .map { $0.offset }
        var totalW: CGFloat = 0
        for i in order {
            totalW += labImageEntries[i].canvasFrame.width
        }
        let slack = W - totalW
        guard slack >= 0 else {
            statusMessage = "Layers are wider than the artboard — narrow frames, or widen the artboard"
            return
        }
        pushCollageUndoBeforeMutation()
        let g = slack / CGFloat(n + 1)
        var x = g
        for i in order {
            var r = labImageEntries[i].canvasFrame
            r.origin.x = x
            let clamped = clampCanvasFrame(r)
            labImageEntries[i].canvasFrame = clamped
            x += clamped.width + g
        }
        statusMessage = "✅ Spaced \(n) layer(s) with equal gaps (side margins match gaps)"
        labLog("Distribute H: n=\(n), gap+margin=\(g), slack=\(slack)")
    }
    
    /// **Collage:** resizes the artboard to a standard blog aspect (e.g. 1200×630) and arranges images in a 2×N grid (no gaps between cells).
    /// Resets each layer’s **frame**; sets **letterbox alignment** to top + center so short/tall images align at the top (change in sidebar if needed). **Undo** restores the previous layout.
    func layoutCollageForStandardBlogContent(preset: LabBlogContentPreset = .standardOG) {
        guard labCompositingMode == .collage, !labImageEntries.isEmpty else {
            statusMessage = "Add at least one image in Collage mode first"
            return
        }
        pushCollageUndoBeforeMutation()
        let W = CGFloat(preset.targetWidth)
        let H = CGFloat(preset.targetHeight)
        labCollageCanvasWidth = W
        labCollageCanvasHeight = H
        let n = labImageEntries.count
        if n == 1 {
            labImageEntries[0].canvasFrame = CGRect(x: 0, y: 0, width: W, height: H)
        } else {
            let cols = 2
            let rowCount = max(1, Int(ceil(Double(n) / Double(cols))))
            let cellW = W / 2.0
            let cellH = H / CGFloat(rowCount)
            for i in 0..<n {
                let col = i % cols
                let row = i / cols
                let x = CGFloat(col) * cellW
                let y = CGFloat(row) * cellH
                labImageEntries[i].canvasFrame = clampCanvasFrame(CGRect(x: x, y: y, width: cellW, height: cellH))
            }
        }
        // Blog grid: align image *content* to the top of each cell (not vertically centered letterboxing), so a short and tall photo line up. User can change H/V in the sidebar.
        for i in labImageEntries.indices {
            labImageEntries[i].collageFitAlignV = .top
            labImageEntries[i].collageFitAlignH = .center
        }
        labActiveBlogContentPreset = preset
        labBlogContentFrame = CGRect(x: 0, y: 0, width: W, height: H)
        for i in labImageEntries.indices { labImageEntries[i].blogContentRect = nil }
        labSelectedEntryId = labImageEntries.first?.id
        let blogRows = n > 1 ? max(1, Int(ceil(Double(n) / 2.0))) : 1
        let gridNote = n > 1 ? "— \(n) images, \(blogRows) row(s)" : ""
        statusMessage = "✅ Artboard \(Int(W))×\(Int(H)) \(gridNote) — use Save blog PNG"
        labLog("Blog quick layout: \(n) image(s) on \(Int(W))×\(Int(H)) artboard; fit align top+center per layer; full-frame export")
    }
    
    private func repositionDefaultBlogFrameForCurrentPreset() {
        guard let p = labActiveBlogContentPreset else { return }
        if labCompositingMode == .collage {
            if p.isFullImageBody {
                let W = max(1, labCollageCanvasWidth)
                let H = max(1, labCollageCanvasHeight)
                labBlogContentFrame = CGRect(x: 0, y: 0, width: W, height: H)
            } else {
                labBlogContentFrame = defaultBlogFrameInArtboard(for: p)
            }
        } else if let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) {
            labImageEntries[i].blogContentRect = defaultBlogContentRectInImage(for: p, entry: labImageEntries[i])
        }
    }
    
    func updateLabBlogContentFrame(_ frame: CGRect) {
        if labCompositingMode == .collage, let p = labActiveBlogContentPreset, !p.isFullImageBody {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                labBlogContentFrame = clampBlogContentFrameInArtboard(frame)
            }
        }
    }
    
    func translateLabBlogContentFrame(dx: CGFloat, dy: CGFloat) {
        if labCompositingMode == .collage, let p = labActiveBlogContentPreset, !p.isFullImageBody {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                var f = labBlogContentFrame
                f.origin.x += dx
                f.origin.y += dy
                labBlogContentFrame = clampBlogContentFrameInArtboard(f)
            }
        }
    }
    
    func updateSelectedEntryBlogContentRect(_ rect: CGRect) {
        guard let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        if labActiveBlogContentPreset?.isFullImageBody == true {
            clampBlogContentRectInImage(&labImageEntries[i])
            return
        }
        labImageEntries[i].blogContentRect = rect
        clampBlogContentRectInImage(&labImageEntries[i])
    }
    
    func translateSelectedEntryBlogContentRect(dx: CGFloat, dy: CGFloat) {
        guard let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        if labActiveBlogContentPreset?.isFullImageBody == true { return }
        var r = labImageEntries[i].blogContentRect ?? (labActiveBlogContentPreset.map { defaultBlogContentRectInImage(for: $0, entry: labImageEntries[i]) } ?? .zero)
        r.origin.x += dx
        r.origin.y += dy
        labImageEntries[i].blogContentRect = r
        clampBlogContentRectInImage(&labImageEntries[i])
    }
    
    /// Pixels at exact `preset` size (e.g. 1200×630 from the current blog frame).
    func imageForLabBlogExport() -> NSImage? {
        guard let preset = labActiveBlogContentPreset else { return nil }
        if labCompositingMode == .collage {
            return imageForLabBlogExportFromCollage(preset: preset)
        }
        return imageForLabBlogExportFromSingle(preset: preset)
    }
    
    private func imageForLabBlogExportFromCollage(preset: LabBlogContentPreset) -> NSImage? {
        if preset.isFullImageBody {
            let W = max(1, labCollageCanvasWidth)
            let H = max(1, labCollageCanvasHeight)
            let maxE = max(
                labCollageOutputSize,
                CGFloat(preset.targetWidth),
                W,
                H
            )
            let clip = CGRect(x: 0, y: 0, width: W, height: H)
            guard let raw = renderCollageComposite(exportMaxLongEdge: maxE, artboardClip: clip) else { return nil }
            return scaleImageToMaxOutputWidth(image: raw, maxWidth: preset.targetWidth)
        }
        let clip = labBlogContentFrame
        guard clip.width >= 1, clip.height >= 1 else { return nil }
        let maxE = max(
            labCollageOutputSize,
            CGFloat(preset.targetWidth),
            CGFloat(preset.targetHeight)
        )
        guard let raw = renderCollageComposite(exportMaxLongEdge: maxE, artboardClip: clip) else { return nil }
        return resizeScreenshot(
            image: raw,
            width: CGFloat(preset.targetWidth),
            height: CGFloat(preset.targetHeight)
        )
    }
    
    private func imageForLabBlogExportFromSingle(preset: LabBlogContentPreset) -> NSImage? {
        guard var e = labSelectedEntry, e.blogContentRect != nil else { return nil }
        clampBlogContentRectInImage(&e)
        guard let r = e.blogContentRect, let region = croppedImageFromTopLeftRect(image: e.image, topLeft: r) else { return nil }
        if preset.isFullImageBody {
            return scaleImageToMaxOutputWidth(image: region, maxWidth: preset.targetWidth)
        }
        return resizeScreenshot(
            image: region,
            width: CGFloat(preset.targetWidth),
            height: CGFloat(preset.targetHeight)
        )
    }
    
    /// Downscales if wider than `maxWidth`; if already narrower, keeps native width (no upscale).
    private func scaleImageToMaxOutputWidth(image: NSImage, maxWidth: Int) -> NSImage? {
        let (iw, ih) = labPixelSize(of: image)
        let W = CGFloat(max(1, iw))
        let H = CGFloat(max(1, ih))
        let cap = CGFloat(max(1, maxWidth))
        let outW = min(W, cap)
        let outH = H * (outW / W)
        return resizeScreenshot(image: image, width: outW, height: outH)
    }
    
    private func croppedImageFromTopLeftRect(image: NSImage, topLeft: CGRect) -> NSImage? {
        let (_, ph) = labPixelSize(of: image)
        let w = topLeft.width
        let h = topLeft.height
        guard w >= 1, h >= 1 else { return nil }
        let yBottom = CGFloat(ph) - topLeft.minY - h
        let fromRect = NSRect(x: topLeft.minX, y: yBottom, width: w, height: h)
        let out = NSImage(size: NSSize(width: w, height: h))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: out.size),
            from: fromRect,
            operation: .copy,
            fraction: 1.0
        )
        out.unlockFocus()
        return out
    }
    
    /// Save a PNG of the current blog frame at the preset’s pixel size (e.g. 1200×630).
    func saveLabBlogImageToFile() {
        guard let out = imageForLabBlogExport() else {
            statusMessage = "❌ Choose a blog size and show the blog frame, then try again"
            return
        }
        guard let preset = labActiveBlogContentPreset else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = preset.isFullImageBody
            ? "blog-body-\(preset.targetWidth)w.png"
            : "blog-\(preset.targetWidth)x\(preset.targetHeight).png"
        panel.title = "Save blog / article image"
        panel.begin { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else {
                DispatchQueue.main.async { self.labLog("Save blog image: cancelled") }
                return
            }
            DispatchQueue.main.async {
                if self.savePNG(image: out, to: url) {
                    self.statusMessage = "✅ Saved blog image: \(url.lastPathComponent)"
                    self.labLog("Saved blog / article image → \(url.path)")
                    self.lastOutputFolder = url.deletingLastPathComponent()
                } else {
                    self.statusMessage = "❌ Could not save blog image"
                }
            }
        }
    }
    
    /// Replaces the lab with a **single** image: the current blog frame scaled to the preset, for continued editing.
    func applyLabBlogCropToWorkspace() {
        guard let out = imageForLabBlogExport() else {
            statusMessage = "❌ Nothing to apply (enable a blog size and frame first)"
            return
        }
        let (pw, ph) = labPixelSize(of: out)
        labLog("Applied blog crop to workspace: \(pw)×\(ph) px")
        clearCollageUndoHistory()
        clearSingleUndoHistory()
        labCompositingMode = .single
        labActiveBlogContentPreset = nil
        var e = makeLabEntry(from: out, canvasFrame: CGRect(x: 0, y: 0, width: labCollageCanvasWidth, height: labCollageCanvasHeight))
        e.blogContentRect = nil
        labImageEntries = [e]
        labSelectedEntryId = e.id
        labBlogContentFrame = .zero
        statusMessage = "✅ Image is now \(pw)×\(ph) px (blog crop). Use Single mode to keep editing or export again."
    }
    
    /// After gestures on the single-image blog overlay.
    func clampSelectedEntryBlogContentRect() {
        guard let i = labImageEntries.firstIndex(where: { $0.id == labSelectedEntryId }) else { return }
        guard labActiveBlogContentPreset != nil else { return }
        clampBlogContentRectInImage(&labImageEntries[i])
    }
    
    /// Thumbnail of the final collage for the UI.
    func renderCollagePreviewImage(maxPixelSide: CGFloat = 400) -> NSImage? {
        return renderCollageComposite(exportMaxLongEdge: min(maxPixelSide, 600))
    }
    
    /// Single: square crop of selected. Collage: full bitmap composite. Used for **app icon** “Also run” so the yellow square (or composite) is the source when a blog frame is also visible.
    func croppedLabImage() -> NSImage? {
        if labCompositingMode == .collage {
            if let c = renderCollageComposite() {
                let ow = c.size.width
                let oh = c.size.height
                labLog("Composed collage at export \(Int(ow))×\(Int(oh)) (long edge \(Int(labCollageOutputSize)))")
                return c
            }
            labLog("Collage: nothing to render")
            return nil
        }
        guard let entry = labSelectedEntry else {
            labLog("Crop: no source image")
            return nil
        }
        return croppedSquare(from: entry, log: true)
    }
    
    /// **Save as PNG** / **Export + sizes** / web & screenshot “Also run” (except App Icons): uses the **blog / article frame** (cyan) when a blog preset is on; otherwise the square crop (single) or composite (collage). App icon export still uses `croppedLabImage()`.
    func labPrimaryOutputImage() -> NSImage? {
        if let out = imageForLabBlogExport() {
            if labCompositingMode == .collage {
                let (w, h) = labPixelSize(of: out)
                labLog("Primary lab output: blog frame \(w)×\(h) px (collage)")
            } else {
                let (w, h) = labPixelSize(of: out)
                labLog("Primary lab output: blog / article frame \(w)×\(h) px (not the yellow square)")
            }
            return out
        }
        return croppedLabImage()
    }
    
    func chooseLabImageFile(appendAsCollage: Bool = false) {
        dismissLabChooseImagePanelIfNeeded()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.canChooseDirectories = false
        let multi = appendAsCollage && labCompositingMode == .collage
        panel.allowsMultipleSelection = multi
        panel.message = multi
            ? "Choose one or more images to add to the lab"
            : (labCompositingMode == .collage ? "Choose an image to add" : "Choose an image for the lab")
        labChooseImageOpenPanel = panel
        panel.begin { response in
            DispatchQueue.main.async {
                switch response {
                case .OK:
                    if multi, !panel.urls.isEmpty {
                        if self.labCompositingMode == .collage {
                            self.pushCollageUndoBeforeMutation()
                        }
                        for url in panel.urls {
                            if let img = NSImage(contentsOf: url) {
                                self.appendLabImage(img, recordUndo: false)
                            } else {
                                self.labLog("Failed to read \(url.lastPathComponent)")
                            }
                        }
                        self.statusMessage = "✅ Added \(panel.urls.count) image(s)"
                    } else if let url = panel.url {
                        guard let img = NSImage(contentsOf: url) else {
                            self.dismissLabChooseImagePanelIfNeeded()
                            self.labLog("Failed to read image at \(url.lastPathComponent)")
                            return
                        }
                        if self.labCompositingMode == .collage {
                            self.appendLabImage(img)
                            self.statusMessage = "✅ Added \(url.lastPathComponent)"
                        } else {
                            self.setSingleLabImage(img)
                            self.statusMessage = "✅ Loaded \(url.lastPathComponent)"
                        }
                    } else {
                        self.dismissLabChooseImagePanelIfNeeded()
                        self.labLog("Open panel: no URL")
                        return
                    }
                default:
                    self.dismissLabChooseImagePanelIfNeeded()
                    self.labLog("Open panel cancelled")
                }
                self.dismissLabChooseImagePanelIfNeeded()
            }
        }
    }
    
    
    func saveLabCropToFile() {
        guard let cropped = labPrimaryOutputImage() else {
            statusMessage = "❌ Nothing to save"
            return
        }
        let usingBlog = labActiveBlogContentPreset != nil && imageForLabBlogExport() != nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        if labCompositingMode == .collage {
            panel.nameFieldStringValue = usingBlog ? "lab-blog-export.png" : "lab-composite.png"
            panel.title = usingBlog ? "Save blog frame (collage)" : "Save composite PNG"
        } else {
            if usingBlog, let p = labActiveBlogContentPreset {
                panel.nameFieldStringValue = p.isFullImageBody
                    ? "lab-blog-body-\(p.targetWidth)w.png"
                    : "lab-blog-\(p.targetWidth)x\(p.targetHeight).png"
                panel.title = "Save blog / article frame (not the yellow square)"
            } else {
                panel.nameFieldStringValue = "lab-crop.png"
                panel.title = "Save square crop"
            }
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                DispatchQueue.main.async {
                    self.labLog("Save crop cancelled")
                }
                return
            }
            DispatchQueue.main.async {
                if self.savePNG(image: cropped, to: url) {
                    let what = (self.labActiveBlogContentPreset != nil && self.imageForLabBlogExport() != nil)
                        ? "blog / article frame"
                        : (self.labCompositingMode == .collage ? "composite" : "square crop")
                    self.statusMessage = "✅ Saved \(what) to \(url.lastPathComponent)"
                    self.labLog("Saved \(what) → \(url.path)")
                    self.lastOutputFolder = url.deletingLastPathComponent()
                } else {
                    self.statusMessage = "❌ Could not save PNG"
                    self.labLog("Save PNG failed")
                }
            }
        }
    }
    
    /// Writes the current **primary** lab image (blog frame if active, else square or collage) plus 128 / 256 / 512 / 1024 px PNGs.
    func exportLabCropWithResizedPresets() {
        guard let cropped = labPrimaryOutputImage() else {
            statusMessage = "❌ Nothing to export"
            labLog("Export pack: no crop")
            return
        }
        let baseFolder = self.effectiveLabExportBase
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
        let w = max(1, Int(cropped.size.width.rounded()))
        let h = max(1, Int(cropped.size.height.rounded()))
        let isSquare = abs(Double(w - h)) < 2
        let nativeName = isSquare
            ? "imagelab-crop-native-\(w)px.png"
            : "imagelab-composite-\(w)x\(h).png"
        let nativeURL = destDir.appendingPathComponent(nativeName)
        if savePNG(image: cropped, to: nativeURL) {
            count += 1
        }
        for px in [128, 256, 512, 1024] {
            let img: NSImage? = isSquare
                ? resize(image: cropped, to: CGFloat(px))
                : resizeToMaxLongEdge(cropped, maxLongEdge: CGFloat(px))
            guard let img = img else { continue }
            let url = destDir.appendingPathComponent("imagelab-\(px).png")
            if savePNG(image: img, to: url) {
                count += 1
            }
        }
        return count
    }
    
    /// Proportionally scale so the longest side equals `maxLongEdge` (keeps aspect).
    private func resizeToMaxLongEdge(_ image: NSImage, maxLongEdge: CGFloat) -> NSImage? {
        let w = image.size.width
        let h = image.size.height
        let m = max(w, h, 1)
        let s = maxLongEdge / m
        let nw = max(1, w * s)
        let nh = max(1, h * s)
        return resizeScreenshot(image: image, width: nw, height: nh)
    }
    
    private func showOpenPanelForLabExportPack(cropped: NSImage) {
        let panel = NSOpenPanel()
        panel.title = "Choose folder for lab exports"
        panel.message = "Choose a folder. Direct: pack files go straight into that folder. + Category: an ImageLabExports subfolder is created inside it. (Matches the image lab toolbar setting.)"
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
        let toRun: NSImage = {
            if labCompositingMode == .collage, let a = resizeAspectFill(image: cropped, width: 1024, height: 1024) {
                labLog("Fitted composite to 1024×1024 (aspect-fill) for App Icons")
                return a
            }
            if let s = resize(image: cropped, to: 1024) {
                labLog("Normalized to 1024×1024 for icon export")
                return s
            }
            labLog("Using output at native size (1024 step unavailable)")
            return cropped
        }()
        labLog("Starting App Icons export from lab (current mode unchanged)")
        resizeAndSaveIcons(sourceImage: toRun, exportBase: effectiveLabExportBase)
    }
    
    /// Web headers / OG cards: uses the same source as **Save as PNG** (blog frame if active, else square or composite).
    func runBlogHeadersFromLabOutput() {
        guard let img = labPrimaryOutputImage() else {
            statusMessage = "❌ Nothing in the lab to use as source"
            labLog("Web headers: no lab output")
            return
        }
        labLog("Web headers export from lab output (aspect-fill to each preset size)")
        resizeAndSaveBlogHeaders(sourceImage: img, exportBase: effectiveLabExportBase)
    }
    
    /// App Store or Play-style screenshot buckets: uses the same source as **Save as PNG** (blog frame if active, else square or composite).
    func runStoreScreenshotsFromLabOutput() {
        guard let img = labPrimaryOutputImage() else {
            statusMessage = "❌ Nothing in the lab to use as source"
            labLog("Screenshots: no lab output")
            return
        }
        labLog("Store screenshots from lab output (Store + device: same as Screenshot mode)")
        let baseFolder = self.effectiveLabExportBase
        let defaultOutputURL = resolvedExportFolder(base: baseFolder, subfolder: screenshotOutputFolderComponent())
        let fileManager = FileManager.default
        isProcessing = true
        statusMessage = "🔄 Generating store screenshots from lab output..."
        do {
            try fileManager.createDirectory(at: defaultOutputURL, withIntermediateDirectories: true)
            performScreenshotProcessing(images: [img], outputFolderURL: defaultOutputURL)
        } catch {
            isProcessing = false
            showSavePanelForScreenshots(images: [img])
        }
    }
}

