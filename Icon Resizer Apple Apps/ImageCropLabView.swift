//
//  ImageCropLabView.swift
//  Icon Resizer
//
//  Simple square crop in bitmap pixels with preview, console log, save & icon export.
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

struct ImageCropLabView: View {
    @ObservedObject var vm: IconResizerViewModel
    @State private var dragTranslation: CGSize = .zero
    @State private var isDropTargeted = false
    @State private var resizeSession: LabResizeSession?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choose image…") {
                    vm.chooseLabImageFile()
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                if vm.labSourceImage != nil {
                    Button("Reset square to center / max") {
                        if let img = vm.labSourceImage {
                            vm.loadLabImage(img)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            
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
                        Text("Drop a PNG here or use Choose image…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 320)
            .overlay(alignment: .bottom) {
                if vm.labSourceImage != nil {
                    Text("Drag inside the square to move · drag orange corners to resize")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 40)
            .onDrop(of: [.png, .image], isTargeted: $isDropTargeted) { providers in
                vm.handleDrop(providers: providers)
                return true
            }
            
            if vm.labSourceImage != nil {
                let (pw, ph) = vm.labBitmapPixelSize()
                let minDim = max(1, min(pw, ph))
                let sideUpper = CGFloat(minDim)
                let sideLower = min(16, sideUpper)
                let xUpper = max(0, CGFloat(pw) - vm.labCropSize)
                let yUpper = max(0, CGFloat(ph) - vm.labCropSize)
                let sideSpan = sideUpper - sideLower
                VStack(alignment: .leading, spacing: 8) {
                    Text("Square crop (image pixels)")
                        .font(.caption.bold())
                    HStack {
                        Text("Side")
                        if sideSpan > 0 {
                            Slider(value: Binding(
                                get: { vm.labCropSize },
                                set: {
                                    vm.labCropSize = $0
                                    vm.clampLabCrop()
                                }
                            ), in: sideLower...sideUpper, step: labPixelSliderStep(lower: sideLower, upper: sideUpper))
                        } else {
                            Text("matches image")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        Text("\(Int(vm.labCropSize)) px")
                            .font(.caption.monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                    }
                    HStack {
                        Text("X")
                        if xUpper > 0 {
                            Slider(value: Binding(
                                get: { vm.labCropOriginX },
                                set: {
                                    vm.labCropOriginX = $0
                                    vm.clampLabCrop()
                                }
                            ), in: 0...xUpper, step: labPixelSliderStep(lower: 0, upper: xUpper))
                        } else {
                            Text("locked (full width)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        Text("\(Int(vm.labCropOriginX))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                    }
                    HStack {
                        Text("Y")
                        if yUpper > 0 {
                            Slider(value: Binding(
                                get: { vm.labCropOriginY },
                                set: {
                                    vm.labCropOriginY = $0
                                    vm.clampLabCrop()
                                }
                            ), in: 0...yUpper, step: labPixelSliderStep(lower: 0, upper: yUpper))
                        } else {
                            Text("locked (full height)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        Text("\(Int(vm.labCropOriginY))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                    }
                    Text("Image \(pw)×\(ph) px — crop \(Int(vm.labCropSize))×\(Int(vm.labCropSize)) @ (\(Int(vm.labCropOriginX)), \(Int(vm.labCropOriginY)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 40)
                .onAppear { vm.clampLabCrop() }
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button("Save crop as PNG…") {
                            vm.saveLabCropToFile()
                        }
                        Button("Export crop + sizes") {
                            vm.exportLabCropWithResizedPresets()
                        }
                        .help("Saves native square plus 128, 256, 512, and 1024 px PNGs to Desktop/Apple Icons (or ImageLabExports if subfolder is on).")
                    }
                    Button("Use crop → App Icons export") {
                        vm.runIconsFromLabCrop()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 40)
            }
            
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
                .frame(height: 100)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
            }
            .padding(.horizontal, 40)
        }
    }
    
    @ViewBuilder
    private func previewWithOverlay(image: NSImage) -> some View {
        let (pw, ph) = vm.labBitmapPixelSize()
        GeometryReader { geo in
            let fit = min(geo.size.width / CGFloat(pw), geo.size.height / CGFloat(ph))
            let dw = CGFloat(pw) * fit
            let dh = CGFloat(ph) * fit
            let padX = (geo.size.width - dw) / 2
            let padY = (geo.size.height - dh) / 2
            let ox = vm.labCropOriginX + dragTranslation.width / fit
            let oy = vm.labCropOriginY + dragTranslation.height / fit
            let box = vm.labCropSize * fit
            
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .frame(width: dw, height: dh)
                    .offset(x: padX, y: padY)
                
                ZStack {
                    Rectangle()
                        .strokeBorder(Color.yellow, lineWidth: 2)
                        .background(Rectangle().fill(Color.yellow.opacity(0.08)))
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    guard resizeSession == nil else { return }
                                    dragTranslation = value.translation
                                }
                                .onEnded { value in
                                    guard resizeSession == nil else { return }
                                    vm.labCropOriginX += value.translation.width / fit
                                    vm.labCropOriginY += value.translation.height / fit
                                    vm.clampLabCrop()
                                    dragTranslation = .zero
                                }
                        )
                    
                    ForEach(LabResizeCorner.allCases, id: \.self) { corner in
                        resizeKnob(corner: corner, boxLen: box, fit: fit)
                    }
                }
                .frame(width: max(1, box), height: max(1, box))
                .offset(x: padX + ox * fit, y: padY + oy * fit)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
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
                        if resizeSession == nil {
                            dragTranslation = .zero
                            resizeSession = LabResizeSession(
                                corner: corner,
                                startOx: vm.labCropOriginX,
                                startOy: vm.labCropOriginY,
                                startS: vm.labCropSize
                            )
                        }
                        guard resizeSession?.corner == corner else { return }
                        applyResize(corner: corner, translation: value.translation, fit: fit)
                    }
                    .onEnded { _ in
                        if resizeSession?.corner == corner {
                            resizeSession = nil
                            vm.clampLabCrop()
                        }
                    }
            )
    }
    
    /// Resize square from a corner; opposite corner stays fixed in image space (L∞ / axis-aligned square).
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
        
        vm.labCropOriginX = newOx
        vm.labCropOriginY = newOy
        vm.labCropSize = newS
        vm.clampLabCrop()
    }
}
