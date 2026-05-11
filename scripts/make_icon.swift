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

    let rect = NSRect(origin: .zero, size: imageSize)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22).fill()

    let globeRect = NSRect(
        x: CGFloat(size) * 0.18,
        y: CGFloat(size) * 0.18,
        width: CGFloat(size) * 0.64,
        height: CGFloat(size) * 0.64
    )
    let globe = NSBezierPath(ovalIn: globeRect)
    NSColor(red: 0.10, green: 0.42, blue: 0.88, alpha: 1).setFill()
    globe.fill()

    NSColor(red: 0.23, green: 0.77, blue: 0.48, alpha: 1).setFill()

    let leftLand = NSBezierPath()
    leftLand.move(to: NSPoint(x: CGFloat(size) * 0.32, y: CGFloat(size) * 0.62))
    leftLand.curve(
        to: NSPoint(x: CGFloat(size) * 0.43, y: CGFloat(size) * 0.42),
        controlPoint1: NSPoint(x: CGFloat(size) * 0.23, y: CGFloat(size) * 0.56),
        controlPoint2: NSPoint(x: CGFloat(size) * 0.30, y: CGFloat(size) * 0.45)
    )
    leftLand.curve(
        to: NSPoint(x: CGFloat(size) * 0.47, y: CGFloat(size) * 0.68),
        controlPoint1: NSPoint(x: CGFloat(size) * 0.55, y: CGFloat(size) * 0.47),
        controlPoint2: NSPoint(x: CGFloat(size) * 0.55, y: CGFloat(size) * 0.63)
    )
    leftLand.curve(
        to: NSPoint(x: CGFloat(size) * 0.32, y: CGFloat(size) * 0.62),
        controlPoint1: NSPoint(x: CGFloat(size) * 0.42, y: CGFloat(size) * 0.72),
        controlPoint2: NSPoint(x: CGFloat(size) * 0.36, y: CGFloat(size) * 0.70)
    )
    leftLand.fill()

    let rightLand = NSBezierPath()
    rightLand.move(to: NSPoint(x: CGFloat(size) * 0.61, y: CGFloat(size) * 0.70))
    rightLand.curve(
        to: NSPoint(x: CGFloat(size) * 0.72, y: CGFloat(size) * 0.52),
        controlPoint1: NSPoint(x: CGFloat(size) * 0.72, y: CGFloat(size) * 0.69),
        controlPoint2: NSPoint(x: CGFloat(size) * 0.78, y: CGFloat(size) * 0.60)
    )
    rightLand.curve(
        to: NSPoint(x: CGFloat(size) * 0.57, y: CGFloat(size) * 0.33),
        controlPoint1: NSPoint(x: CGFloat(size) * 0.66, y: CGFloat(size) * 0.44),
        controlPoint2: NSPoint(x: CGFloat(size) * 0.66, y: CGFloat(size) * 0.35)
    )
    rightLand.curve(
        to: NSPoint(x: CGFloat(size) * 0.61, y: CGFloat(size) * 0.70),
        controlPoint1: NSPoint(x: CGFloat(size) * 0.49, y: CGFloat(size) * 0.40),
        controlPoint2: NSPoint(x: CGFloat(size) * 0.51, y: CGFloat(size) * 0.63)
    )
    rightLand.fill()

    globe.addClip()
    NSColor.white.withAlphaComponent(0.22).setStroke()
    for ratio in [0.36, 0.50, 0.64] {
        let y = CGFloat(size) * ratio
        let line = NSBezierPath()
        line.move(to: NSPoint(x: globeRect.minX + CGFloat(size) * 0.05, y: y))
        line.line(to: NSPoint(x: globeRect.maxX - CGFloat(size) * 0.05, y: y))
        line.lineWidth = max(1, CGFloat(size) * 0.012)
        line.stroke()
    }

    NSColor.white.withAlphaComponent(0.30).setStroke()
    globe.lineWidth = max(2, CGFloat(size) * 0.025)
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
