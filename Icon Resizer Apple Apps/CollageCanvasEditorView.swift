//
//  CollageCanvasEditorView.swift
//  Icon Resizer
//
//  Draggable, resizable layers; canvas uses top-left origin in logical `labCollage*`.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum CanvasFrameCorner: CaseIterable, Hashable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

private enum CanvasFrameEdge: CaseIterable, Hashable {
    case top, bottom, leading, trailing
}

/// Layer: corner or side-center resize.
private enum LayerResizeHandle: Hashable {
    case corner(CanvasFrameCorner)
    case edge(CanvasFrameEdge)
}

private enum BlogFrameCorner: CaseIterable, Hashable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

private enum BlogFrameEdge: CaseIterable, Hashable {
    case top, bottom, leading, trailing
}

private enum BlogResizeHandle: Hashable {
    case corner(BlogFrameCorner)
    case edge(BlogFrameEdge)
}

struct CollageCanvasEditorView: View {
    /// Must match `ImageCropLabView` / Finder-acceptable types (including `fileURL` for files dragged from a folder).
    private static let imageDropUTTypes: [UTType] = [
        .fileURL, .image, .png, .jpeg, .tiff, .gif, .webP, .heic, .icns
    ]
    
    @ObservedObject var vm: IconResizerViewModel
    @Binding var isDropTargeted: Bool
    @State private var lastMoveDeltaCarry: CGSize = .zero
    @State private var lastBlogMoveCarry: CGSize = .zero
    @State private var layerResizeInfo: (layerId: UUID, start: CGRect, handle: LayerResizeHandle)?
    @State private var blogResizeInfo: (start: CGRect, handle: BlogResizeHandle)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Button(role: .destructive) {
                    vm.removeSelectedCollageEntry()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Remove selected layer (Forward Delete)")
                .disabled(vm.labSelectedEntryId == nil || vm.labImageEntries.isEmpty)
                .keyboardShortcut(.delete, modifiers: [])
                Button {
                    vm.collageUndo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .help("Undo (⌘Z)")
                .disabled(!vm.collageCanUndo)
                .keyboardShortcut("z", modifiers: .command)
                Button {
                    vm.collageRedo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .help("Redo (⌘⇧Z)")
                .disabled(!vm.collageCanRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                Spacer(minLength: 8)
                Text("Each layer: drag to move; drag edges or corners to resize.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            canvasContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onDrop(of: Self.imageDropUTTypes, isTargeted: $isDropTargeted) { providers in
            vm.handleDrop(providers: providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .onDeleteCommand {
            vm.removeSelectedCollageEntry()
        }
    }
    
    private var canvasContent: some View {
        GeometryReader { geo in
            let cw = max(1, Double(vm.labCollageCanvasWidth))
            let ch = max(1, Double(vm.labCollageCanvasHeight))
            let sc = min(geo.size.width / CGFloat(cw), geo.size.height / CGFloat(ch), 1)
            let dw = CGFloat(cw) * sc
            let dh = CGFloat(ch) * sc
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.28))
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        layerStack(sc: sc, dw: dw, dh: dh)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    
    @ViewBuilder
    private func layerStack(sc: CGFloat, dw: CGFloat, dh: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(vm.labImageEntries.enumerated()), id: \.element.id) { index, e in
                if let img = vm.labCollageLayerFullImage(for: e) {
                    let r = e.canvasFrame
                    let sel = vm.labSelectedEntryId == e.id
                    ZStack(alignment: .topLeading) {
                        Group {
                            if e.collageFillsFrame {
                                Image(nsImage: img)
                                    .interpolation(.high)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: r.width * sc, height: r.height * sc)
                            } else {
                                Image(nsImage: img)
                                    .interpolation(.high)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: r.width * sc, height: r.height * sc)
                            }
                        }
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.2))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(sel ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: sel ? 2 : 1)
                            }
                            .contentShape(Rectangle())
                        if sel {
                            ForEach(CanvasFrameCorner.allCases, id: \.self) { corner in
                                layerResizeControl(
                                    handle: .corner(corner),
                                    layer: e,
                                    sc: sc,
                                    r: r
                                )
                            }
                            ForEach(CanvasFrameEdge.allCases, id: \.self) { edge in
                                layerResizeControl(
                                    handle: .edge(edge),
                                    layer: e,
                                    sc: sc,
                                    r: r
                                )
                            }
                        }
                    }
                    .offset(x: r.minX * sc, y: r.minY * sc)
                    .zIndex(sel ? 200 : Double(index))
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { g in
                                if layerResizeInfo != nil { return }
                                vm.collageRecordUndoForLayerDragIfNeeded()
                                let d = CGSize(
                                    width: g.translation.width - lastMoveDeltaCarry.width,
                                    height: g.translation.height - lastMoveDeltaCarry.height
                                )
                                lastMoveDeltaCarry = g.translation
                                vm.translateEntryCanvasFrame(
                                    id: e.id,
                                    dx: d.width / sc,
                                    dy: d.height / sc
                                )
                            }
                            .onEnded { _ in
                                if layerResizeInfo == nil {
                                    lastMoveDeltaCarry = .zero
                                    vm.collageRecordLayerDragEnded()
                                }
                            }
                    )
                    .onTapGesture { vm.selectLabImage(id: e.id) }
                }
            }
            if vm.labActiveBlogContentPreset != nil {
                blogContentFrameOverlay(sc: sc)
            }
        }
        .frame(width: dw, height: dh, alignment: .topLeading)
    }
    
    @ViewBuilder
    private func blogContentFrameOverlay(sc: CGFloat) -> some View {
        let br = vm.labBlogContentFrame
        if let p = vm.labActiveBlogContentPreset, br.width >= 1, br.height >= 1 {
            let ar = p.aspect
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.cyan.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.cyan.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { g in
                                if blogResizeInfo != nil { return }
                                vm.collageRecordUndoForBlogFrameDragIfNeeded()
                                let d = CGSize(
                                    width: g.translation.width - lastBlogMoveCarry.width,
                                    height: g.translation.height - lastBlogMoveCarry.height
                                )
                                lastBlogMoveCarry = g.translation
                                vm.translateLabBlogContentFrame(
                                    dx: d.width / sc,
                                    dy: d.height / sc
                                )
                            }
                            .onEnded { _ in
                                if blogResizeInfo == nil {
                                    lastBlogMoveCarry = .zero
                                    vm.collageRecordBlogFrameDragEnded()
                                }
                            }
                    )
                Text("\(p.targetWidth)×\(p.targetHeight)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.cyan)
                    .padding(4)
                    .background(Capsule().fill(Color(nsColor: .textBackgroundColor).opacity(0.9)))
                    .offset(x: 4, y: 4)
                ForEach(BlogFrameCorner.allCases, id: \.self) { corner in
                    blogResizeControl(handle: .corner(corner), ar: ar, sc: sc)
                }
                ForEach(BlogFrameEdge.allCases, id: \.self) { edge in
                    blogResizeControl(handle: .edge(edge), ar: ar, sc: sc)
                }
            }
            .frame(width: br.width * sc, height: br.height * sc, alignment: .topLeading)
            .offset(x: br.minX * sc, y: br.minY * sc)
            .zIndex(500)
        }
    }
    
    @ViewBuilder
    private func blogResizeControl(handle: BlogResizeHandle, ar: CGFloat, sc: CGFloat) -> some View {
        let br = vm.labBlogContentFrame
        let knob: CGFloat = 14
        switch handle {
        case .corner(let corner):
            let a: Alignment = {
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
                .frame(
                    maxWidth: max(br.width * sc, knob),
                    maxHeight: max(br.height * sc, knob),
                    alignment: a
                )
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            if blogResizeInfo == nil {
                                vm.collageRecordUndoForBlogFrameDragIfNeeded()
                                blogResizeInfo = (start: vm.labBlogContentFrame, handle: .corner(corner))
                                lastBlogMoveCarry = .zero
                            }
                            guard let info = blogResizeInfo, info.handle == .corner(corner) else { return }
                            let s = info.start
                            let dx = g.translation.width / sc
                            let dy = g.translation.height / sc
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
                            _ = dy
                            vm.updateLabBlogContentFrame(nf)
                        }
                        .onEnded { _ in
                            blogResizeInfo = nil
                            vm.collageRecordBlogFrameDragEnded()
                        }
                )
        case .edge(let edge):
            let wide: CGFloat = 22
            let thick: CGFloat = 9
            let fill = RoundedRectangle(cornerRadius: 3)
                .fill(Color.cyan.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.cyan, lineWidth: 1.2))
            Group {
                switch edge {
                case .top:
                    fill
                        .frame(width: wide, height: thick)
                        .contentShape(Capsule())
                case .bottom:
                    fill
                        .frame(width: wide, height: thick)
                        .contentShape(Capsule())
                case .leading:
                    fill
                        .frame(width: thick, height: wide)
                        .contentShape(Capsule())
                case .trailing:
                    fill
                        .frame(width: thick, height: wide)
                        .contentShape(Capsule())
                }
            }
            .frame(
                maxWidth: max(br.width * sc, wide),
                maxHeight: max(br.height * sc, wide),
                alignment: {
                    switch edge {
                    case .top: return .top
                    case .bottom: return .bottom
                    case .leading: return .leading
                    case .trailing: return .trailing
                    }
                }()
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        if blogResizeInfo == nil {
                            vm.collageRecordUndoForBlogFrameDragIfNeeded()
                            blogResizeInfo = (start: vm.labBlogContentFrame, handle: .edge(edge))
                            lastBlogMoveCarry = .zero
                        }
                        guard let info = blogResizeInfo, info.handle == .edge(edge) else { return }
                        let s = info.start
                        let dx = g.translation.width / sc
                        let dy = g.translation.height / sc
                        let nf: CGRect
                        let sw = s.width
                        let sh = s.height
                        let miX = s.minX
                        let miY = s.minY
                        let mxX = s.maxX
                        let myY = s.maxY
                        let midX = s.midX
                        let midY = s.midY
                        switch edge {
                        case .top:
                            let newH = sh - dy
                            let newW = newH * ar
                            let nx = midX - newW / 2.0
                            let ny = myY - newH
                            nf = CGRect(x: nx, y: ny, width: newW, height: newH)
                        case .bottom:
                            let newH = sh + dy
                            let newW = newH * ar
                            let nx = midX - newW / 2.0
                            nf = CGRect(x: nx, y: miY, width: newW, height: newH)
                        case .leading:
                            let newW = sw - dx
                            let newH = newW / ar
                            let nx = mxX - newW
                            let ny = midY - newH / 2.0
                            nf = CGRect(x: nx, y: ny, width: newW, height: newH)
                        case .trailing:
                            let newW = sw + dx
                            let newH = newW / ar
                            let ny = midY - newH / 2.0
                            nf = CGRect(x: miX, y: ny, width: newW, height: newH)
                        }
                        vm.updateLabBlogContentFrame(nf)
                    }
                    .onEnded { _ in
                        blogResizeInfo = nil
                        vm.collageRecordBlogFrameDragEnded()
                    }
            )
        }
    }
    
    @ViewBuilder
    private func layerResizeControl(
        handle: LayerResizeHandle,
        layer: LabImageEntry,
        sc: CGFloat,
        r: CGRect
    ) -> some View {
        let cornerKnob: CGFloat = 16
        let wide: CGFloat = 22
        let thick: CGFloat = 8
        switch handle {
        case .corner(let corner):
            let a: Alignment = {
                switch corner {
                case .topLeading: return .topLeading
                case .topTrailing: return .topTrailing
                case .bottomLeading: return .bottomLeading
                case .bottomTrailing: return .bottomTrailing
                }
            }()
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(Circle().strokeBorder(Color.orange, lineWidth: 1.5))
                .frame(width: cornerKnob, height: cornerKnob)
                .contentShape(Circle())
                .frame(
                    maxWidth: max(r.width * sc, cornerKnob),
                    maxHeight: max(r.height * sc, cornerKnob),
                    alignment: a
                )
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            if layerResizeInfo == nil {
                                vm.collageRecordUndoForLayerDragIfNeeded()
                                layerResizeInfo = (layerId: layer.id, start: r, handle: .corner(corner))
                                lastMoveDeltaCarry = .zero
                            }
                            guard let info = layerResizeInfo, info.layerId == layer.id, info.handle == .corner(corner) else { return }
                            let s = info.start
                            let dx = g.translation.width / sc
                            let dy = g.translation.height / sc
                            let sx = s.minX, sy = s.minY, sw = s.width, sh = s.height
                            let nf: CGRect
                            switch corner {
                            case .bottomTrailing: nf = CGRect(x: sx, y: sy, width: sw + dx, height: sh + dy)
                            case .topLeading: nf = CGRect(x: sx + dx, y: sy + dy, width: sw - dx, height: sh - dy)
                            case .bottomLeading: nf = CGRect(x: sx + dx, y: sy, width: sw - dx, height: sh + dy)
                            case .topTrailing: nf = CGRect(x: sx, y: sy + dy, width: sw + dx, height: sh - dy)
                            }
                            vm.updateEntryCanvasFrame(id: layer.id, frame: nf)
                        }
                        .onEnded { _ in
                            if layerResizeInfo?.layerId == layer.id {
                                layerResizeInfo = nil
                                vm.collageRecordLayerDragEnded()
                            }
                        }
                )
        case .edge(let edge):
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.orange, lineWidth: 1.2))
                .frame(
                    width: (edge == .top || edge == .bottom) ? min(wide, r.width * sc) : thick,
                    height: (edge == .leading || edge == .trailing) ? min(wide, r.height * sc) : thick
                )
                .contentShape(RoundedRectangle(cornerRadius: 2))
                .frame(
                    maxWidth: (edge == .leading || edge == .trailing) ? max(r.width * sc, thick) : max(r.width * sc, wide),
                    maxHeight: (edge == .top || edge == .bottom) ? max(r.height * sc, thick) : max(r.height * sc, wide),
                    alignment: {
                        switch edge {
                        case .top: return .top
                        case .bottom: return .bottom
                        case .leading: return .leading
                        case .trailing: return .trailing
                        }
                    }()
                )
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            if layerResizeInfo == nil {
                                vm.collageRecordUndoForLayerDragIfNeeded()
                                layerResizeInfo = (layerId: layer.id, start: r, handle: .edge(edge))
                                lastMoveDeltaCarry = .zero
                            }
                            guard let info = layerResizeInfo, info.layerId == layer.id, info.handle == .edge(edge) else { return }
                            let s = info.start
                            let dx = g.translation.width / sc
                            let dy = g.translation.height / sc
                            let sx = s.minX, sy = s.minY, sw = s.width, sh = s.height
                            let nf: CGRect
                            switch edge {
                            case .top: nf = CGRect(x: sx, y: sy + dy, width: sw, height: sh - dy)
                            case .bottom: nf = CGRect(x: sx, y: sy, width: sw, height: sh + dy)
                            case .leading: nf = CGRect(x: sx + dx, y: sy, width: sw - dx, height: sh)
                            case .trailing: nf = CGRect(x: sx, y: sy, width: sw + dx, height: sh)
                            }
                            vm.updateEntryCanvasFrame(id: layer.id, frame: nf)
                        }
                        .onEnded { _ in
                            if layerResizeInfo?.layerId == layer.id {
                                layerResizeInfo = nil
                                vm.collageRecordLayerDragEnded()
                            }
                        }
                )
        }
    }
}
