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
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Icon Resizer")
                    .font(.largeTitle.bold())
                
                Text("Drag & drop a 1024x1024 PNG to generate all app icon sizes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            
            // Platform selector
            Picker("Platform", selection: $resizer.selectedPlatform) {
                ForEach(PlatformSelection.allCases, id: \.self) { platform in
                    Text(platform.rawValue).tag(platform)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 80)
            
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
                        NSWorkspace.shared.open(folder)
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
                Text("Generates:")
                    .font(.caption.bold())
                
                if resizer.selectedPlatform == .iOS || resizer.selectedPlatform == .both {
                    Text("• iOS: 16 sizes (20x20 to 1024x1024)")
                }
                
                if resizer.selectedPlatform == .macOS || resizer.selectedPlatform == .both {
                    Text("• macOS: 10 sizes (16x16 to 1024x1024)")
                }
                
                Text("• You choose where to save")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 600)
    }
}

#Preview {
    ContentView()
}

