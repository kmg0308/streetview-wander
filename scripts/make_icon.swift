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
    NSColor(red: 0.07, green: 0.22, blue: 0.19, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22).fill()

    let horizon = NSBezierPath()
    horizon.move(to: NSPoint(x: CGFloat(size) * 0.14, y: CGFloat(size) * 0.60))
    horizon.line(to: NSPoint(x: CGFloat(size) * 0.86, y: CGFloat(size) * 0.60))
    horizon.lineWidth = max(2, CGFloat(size) * 0.035)
    NSColor(red: 0.86, green: 0.91, blue: 0.87, alpha: 1).setStroke()
    horizon.stroke()

    let road = NSBezierPath()
    road.move(to: NSPoint(x: CGFloat(size) * 0.46, y: CGFloat(size) * 0.16))
    road.curve(
        to: NSPoint(x: CGFloat(size) * 0.58, y: CGFloat(size) * 0.82),
        controlPoint1: NSPoint(x: CGFloat(size) * 0.34, y: CGFloat(size) * 0.36),
        controlPoint2: NSPoint(x: CGFloat(size) * 0.72, y: CGFloat(size) * 0.55)
    )
    road.lineWidth = max(5, CGFloat(size) * 0.09)
    NSColor(red: 0.96, green: 0.70, blue: 0.31, alpha: 1).setStroke()
    road.stroke()

    let pin = NSBezierPath(ovalIn: NSRect(
        x: CGFloat(size) * 0.60,
        y: CGFloat(size) * 0.62,
        width: CGFloat(size) * 0.16,
        height: CGFloat(size) * 0.16
    ))
    NSColor.white.setFill()
    pin.fill()

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

