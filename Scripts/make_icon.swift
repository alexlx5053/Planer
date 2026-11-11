#!/usr/bin/env swift
// Zeichnet das App-Icon (Blatt auf gruenem Verlauf) und baut daraus eine .icns.
// Aufruf: swift Scripts/make_icon.swift [ziel.icns]
import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func color(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

/// Blattform im Einheitsquadrat: zwei Boegen von der unteren zur oberen Spitze.
func leafPath(in rect: NSRect) -> NSBezierPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
    let path = NSBezierPath()
    path.move(to: p(0.16, 0.18))
    path.curve(to: p(0.84, 0.84), controlPoint1: p(0.06, 0.74), controlPoint2: p(0.40, 0.92))
    path.curve(to: p(0.16, 0.18), controlPoint1: p(0.92, 0.42), controlPoint2: p(0.32, 0.12))
    path.close()
    return path
}

func midribPath(in rect: NSRect) -> NSBezierPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
    let path = NSBezierPath()
    path.move(to: p(0.23, 0.25))
    path.curve(to: p(0.73, 0.74), controlPoint1: p(0.37, 0.35), controlPoint2: p(0.55, 0.53))
    path.lineWidth = rect.width * 0.038
    path.lineCapStyle = .round
    return path
}

/// macOS-Icons sitzen nicht randfuellend: das Motiv nutzt rund 80 % der Kantenlaenge.
func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.098
    let box = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: box, xRadius: box.width * 0.2237, yRadius: box.width * 0.2237)

    // Space Black: sehr dunkles Graphit mit einem Hauch Waerme. Der Verlauf
    // laeuft von oben leicht aufgehellt nach unten aus - wie eloxiertes
    // Aluminium unter Raumlicht.
    let gradient = NSGradient(starting: color(44, 44, 48), ending: color(16, 16, 18))
    gradient?.draw(in: squircle, angle: -90)

    // Feine Lichtkante oben, damit das Icon auf dunklem Grund nicht ausfranst.
    let edge = NSBezierPath(
        roundedRect: box.insetBy(dx: size * 0.004, dy: size * 0.004),
        xRadius: box.width * 0.2237, yRadius: box.width * 0.2237
    )
    edge.lineWidth = size * 0.008
    NSColor(white: 1, alpha: 0.10).setStroke()
    edge.stroke()

    let leafBox = box.insetBy(dx: box.width * 0.235, dy: box.height * 0.235)
    // Das Blatt traegt als einziges Element Farbe - das Gruen der App.
    color(124, 179, 66).setFill()
    leafPath(in: leafBox).fill()

    color(20, 24, 16).withAlphaComponent(0.34).setStroke()
    midribPath(in: leafBox).stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make_icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG-Kodierung fehlgeschlagen"])
    }
    try data.write(to: url)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (Pixelgroesse, Dateiname) - @2x-Varianten werden in doppelter Aufloesung gezeichnet.
let variants: [(CGFloat, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (size, name) in variants {
    try writePNG(drawIcon(size: size), to: iconset.appendingPathComponent(name))
}

let output = URL(fileURLWithPath: outputPath)
try? fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil fehlgeschlagen\n".utf8))
    exit(1)
}

try? fm.removeItem(at: iconset)
print("Icon geschrieben: \(output.path)")
