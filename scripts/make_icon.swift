#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: make_icon.swift <output.icns>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
let workURL = fileManager.temporaryDirectory
    .appendingPathComponent("streetview-wander-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = workURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let images: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: Int) throws -> Data {
    let imageSize = NSSize(width: size, height: size)
    let image = NSImage(size: imageSize)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(origin: .zero, size: imageSize)
    NSColor.clear.setFill()
    rect.fill()

    let tileRect = rect.insetBy(dx: CGFloat(size) * 0.022, dy: CGFloat(size) * 0.022)
    let tile = NSBezierPath(
        roundedRect: tileRect,
        xRadius: CGFloat(size) * 0.20,
        yRadius: CGFloat(size) * 0.20
    )
    NSGradient(
        starting: NSColor(red: 0.02, green: 0.03, blue: 0.03, alpha: 1),
        ending: NSColor(red: 0.08, green: 0.10, blue: 0.10, alpha: 1)
    )?.draw(in: tile, angle: -70)

    let globeRect = NSRect(
        x: CGFloat(size) * 0.10,
        y: CGFloat(size) * 0.105,
        width: CGFloat(size) * 0.80,
        height: CGFloat(size) * 0.80
    )

    let shadowRect = globeRect.offsetBy(dx: 0, dy: -CGFloat(size) * 0.016)
    NSColor.black.withAlphaComponent(0.30).setFill()
    NSBezierPath(ovalIn: shadowRect).fill()

    let globe = NSBezierPath(ovalIn: globeRect)
    NSGraphicsContext.saveGraphicsState()
    globe.addClip()

    NSGradient(
        starting: NSColor(red: 0.05, green: 0.53, blue: 0.92, alpha: 1),
        ending: NSColor(red: 0.02, green: 0.22, blue: 0.58, alpha: 1)
    )?.draw(in: globe, angle: -35)

    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(
            x: globeRect.minX + globeRect.width * x,
            y: globeRect.minY + globeRect.height * y
        )
    }

    func fillLand(_ color: NSColor, _ draw: (NSBezierPath) -> Void) {
        let path = NSBezierPath()
        draw(path)
        path.close()
        color.setFill()
        path.fill()
    }

    let land = NSColor(red: 0.19, green: 0.70, blue: 0.36, alpha: 1)
    let landDark = NSColor(red: 0.09, green: 0.54, blue: 0.29, alpha: 1)

    fillLand(land) { path in
        path.move(to: point(0.27, 0.77))
        path.curve(to: point(0.16, 0.58), controlPoint1: point(0.17, 0.74), controlPoint2: point(0.11, 0.66))
        path.curve(to: point(0.27, 0.45), controlPoint1: point(0.18, 0.50), controlPoint2: point(0.23, 0.48))
        path.curve(to: point(0.38, 0.25), controlPoint1: point(0.33, 0.40), controlPoint2: point(0.31, 0.30))
        path.curve(to: point(0.45, 0.38), controlPoint1: point(0.47, 0.27), controlPoint2: point(0.47, 0.33))
        path.curve(to: point(0.39, 0.56), controlPoint1: point(0.44, 0.45), controlPoint2: point(0.36, 0.48))
        path.curve(to: point(0.48, 0.72), controlPoint1: point(0.43, 0.64), controlPoint2: point(0.47, 0.67))
        path.curve(to: point(0.27, 0.77), controlPoint1: point(0.40, 0.81), controlPoint2: point(0.33, 0.83))
    }

    fillLand(landDark) { path in
        path.move(to: point(0.56, 0.79))
        path.curve(to: point(0.80, 0.70), controlPoint1: point(0.64, 0.86), controlPoint2: point(0.73, 0.82))
        path.curve(to: point(0.89, 0.54), controlPoint1: point(0.88, 0.67), controlPoint2: point(0.94, 0.61))
        path.curve(to: point(0.74, 0.45), controlPoint1: point(0.84, 0.47), controlPoint2: point(0.79, 0.47))
        path.curve(to: point(0.66, 0.21), controlPoint1: point(0.73, 0.34), controlPoint2: point(0.69, 0.25))
        path.curve(to: point(0.53, 0.30), controlPoint1: point(0.58, 0.20), controlPoint2: point(0.52, 0.24))
        path.curve(to: point(0.58, 0.51), controlPoint1: point(0.54, 0.39), controlPoint2: point(0.61, 0.42))
        path.curve(to: point(0.48, 0.65), controlPoint1: point(0.55, 0.58), controlPoint2: point(0.47, 0.57))
        path.curve(to: point(0.56, 0.79), controlPoint1: point(0.49, 0.72), controlPoint2: point(0.52, 0.75))
    }

    fillLand(land) { path in
        path.move(to: point(0.76, 0.27))
        path.curve(to: point(0.87, 0.19), controlPoint1: point(0.82, 0.28), controlPoint2: point(0.87, 0.25))
        path.curve(to: point(0.73, 0.15), controlPoint1: point(0.84, 0.13), controlPoint2: point(0.78, 0.13))
        path.curve(to: point(0.76, 0.27), controlPoint1: point(0.70, 0.20), controlPoint2: point(0.72, 0.25))
    }

    let highlightRect = NSRect(
        x: globeRect.minX + globeRect.width * 0.12,
        y: globeRect.minY + globeRect.height * 0.58,
        width: globeRect.width * 0.36,
        height: globeRect.height * 0.26
    )
    NSColor.white.withAlphaComponent(0.16).setFill()
    NSBezierPath(ovalIn: highlightRect).fill()

    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.36).setStroke()
    globe.lineWidth = max(2, CGFloat(size) * 0.018)
    globe.stroke()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make_icon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not render icon."
        ])
    }

    return data
}

for item in images {
    let data = try drawIcon(size: item.size)
    try data.write(to: iconsetURL.appendingPathComponent(item.name))
}

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

try? fileManager.removeItem(at: workURL)

if process.terminationStatus != 0 {
    throw NSError(domain: "make_icon", code: Int(process.terminationStatus), userInfo: [
        NSLocalizedDescriptionKey: "iconutil failed."
    ])
}
