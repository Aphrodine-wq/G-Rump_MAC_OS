#!/usr/bin/env swift

import Foundation
import AppKit
import SwiftUI

// Import the FrownyFaceLogo from the main app
// We'll recreate a minimal version here for icon generation

// MARK: - Logo Mood
enum LogoMood {
    case neutral
}

// MARK: - Mouth Shapes
struct FrownArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY + rect.height * 0.18
        let radius = rect.width * 0.22
        path.addArc(
            center: CGPoint(x: cx, y: cy + radius * 0.6),
            radius: radius,
            startAngle: .degrees(-160),
            endAngle: .degrees(-20),
            clockwise: false
        )
        return path
    }
}

// MARK: - FrownyFaceLogo (simplified for icon generation)
struct FrownyFaceLogo: View {
    var size: CGFloat = 1024
    let mood: LogoMood = .neutral
    
    private let brandColor = Color(red: 0.2, green: 0.6, blue: 1.0) // G-Rump blue
    
    var body: some View {
        ZStack {
            faceCircle
            eyesView
            mouthView
        }
        .frame(width: size, height: size)
        .background(Color.clear)
    }
    
    @ViewBuilder
    private var faceCircle: some View {
        let borderGradient = LinearGradient(
            colors: [brandColor, brandColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        Circle()
            .fill(Color.white)
            .overlay(
                Circle()
                    .stroke(borderGradient, lineWidth: size * 0.05)
            )
            .shadow(color: brandColor.opacity(0.18), radius: size * 0.18, y: size * 0.06)
    }
    
    @ViewBuilder
    private var eyesView: some View {
        Circle()
            .fill(brandColor)
            .frame(width: size * 0.15, height: size * 0.15)
            .offset(x: -size * 0.17, y: -size * 0.1)
        Circle()
            .fill(brandColor)
            .frame(width: size * 0.15, height: size * 0.15)
            .offset(x: size * 0.17, y: -size * 0.1)
    }
    
    @ViewBuilder
    private var mouthView: some View {
        FrownArc()
            .stroke(brandColor, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
            .frame(width: size, height: size)
    }
}

// MARK: - Icon Generator
class IconGenerator {
    
    static func generateIcon(size: CGFloat) -> NSImage? {
        let logo = FrownyFaceLogo(size: size)
        
        let hostingView = NSHostingView(rootView: logo)
        hostingView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        
        let rep = bitmapImageRepFromView(hostingView)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        
        return image
    }
    
    static func bitmapImageRepFromView(_ view: NSView) -> NSBitmapImageRep {
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layoutSubtreeIfNeeded()
        
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        
        return rep
    }
    
    static func saveImage(_ image: NSImage, to path: String) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try pngData.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            print("Failed to save image to \(path): \(error)")
            return false
        }
    }
}

// MARK: - Main Execution
let iconSizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = "Sources/GRump/Resources/Assets.xcassets/AppIcon.appiconset"

print("Generating G-Rump app icons...")

for size in iconSizes {
    print("Generating \(Int(size))x\(Int(size)) icon...")
    
    if let image = IconGenerator.generateIcon(size: size) {
        let filename = "\(Int(size)).png"
        let path = "\(outputDir)/\(filename)"
        
        if IconGenerator.saveImage(image, to: path) {
            print("✅ Saved \(filename)")
        } else {
            print("❌ Failed to save \(filename)")
        }
    } else {
        print("❌ Failed to generate \(Int(size))x\(Int(size)) icon")
    }
}

print("Icon generation complete!")
