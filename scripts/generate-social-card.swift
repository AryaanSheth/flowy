#!/usr/bin/env swift
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputPath = CommandLine.arguments.dropFirst().first ?? "website/og-image.png"
let outputURL = repoRoot.appendingPathComponent(outputPath)
let iconURL = repoRoot.appendingPathComponent("icons/icon.png")

let width: CGFloat = 1200
let height: CGFloat = 630
let scale: CGFloat = 1

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.08, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let backgroundGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.10, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.13, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.07, alpha: 1),
])!
backgroundGradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -22)

let teal = NSColor(calibratedRed: 0.10, green: 0.69, blue: 0.68, alpha: 1)
let pale = NSColor(calibratedRed: 0.91, green: 0.96, blue: 0.95, alpha: 1)
let muted = NSColor(calibratedRed: 0.62, green: 0.70, blue: 0.70, alpha: 1)
let rule = NSColor(calibratedRed: 0.25, green: 0.36, blue: 0.36, alpha: 0.35)

let orbPath = NSBezierPath(ovalIn: NSRect(x: 760, y: 120, width: 520, height: 520))
NSColor(calibratedRed: 0.10, green: 0.69, blue: 0.68, alpha: 0.13).setFill()
orbPath.fill()

let panelRect = NSRect(x: 64, y: 64, width: width - 128, height: height - 128)
let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 32, yRadius: 32)
NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.12, alpha: 0.78).setFill()
panelPath.fill()
rule.setStroke()
panelPath.lineWidth = 1.5
panelPath.stroke()

if let icon = NSImage(contentsOf: iconURL) {
    let iconRect = NSRect(x: 104, y: 398, width: 112, height: 112)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSShadow().set()
}

func drawText(_ text: String, x: CGFloat, yFromTop: CGFloat, width: CGFloat, font: NSFont, color: NSColor, lineHeight: CGFloat? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let heightNeeded = attributed.boundingRect(
        with: NSSize(width: width, height: 1000),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height.rounded(.up) + 8
    attributed.draw(in: NSRect(x: x, y: height - yFromTop - heightNeeded, width: width, height: heightNeeded))
}

drawText(
    "Flowy",
    x: 250,
    yFromTop: 92,
    width: 820,
    font: .systemFont(ofSize: 86, weight: .heavy),
    color: pale,
    lineHeight: 92
)

drawText(
    "Your voice. Your machine.",
    x: 104,
    yFromTop: 235,
    width: 930,
    font: .systemFont(ofSize: 58, weight: .bold),
    color: pale,
    lineHeight: 66
)

drawText(
    "Hold a hotkey. Speak. Your words appear live — and never leave your machine.",
    x: 106,
    yFromTop: 332,
    width: 875,
    font: .systemFont(ofSize: 32, weight: .regular),
    color: muted,
    lineHeight: 42
)

let pillRect = NSRect(x: 104, y: 104, width: 344, height: 54)
let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 27, yRadius: 27)
NSColor(calibratedRed: 0.10, green: 0.69, blue: 0.68, alpha: 0.15).setFill()
pillPath.fill()
teal.withAlphaComponent(0.45).setStroke()
pillPath.lineWidth = 1
pillPath.stroke()

drawText(
    "Free local dictation for macOS",
    x: 128,
    yFromTop: 477,
    width: 310,
    font: .systemFont(ofSize: 22, weight: .semibold),
    color: teal,
    lineHeight: 28
)

drawText(
    "tryflowy.co",
    x: 878,
    yFromTop: 484,
    width: 220,
    font: .monospacedSystemFont(ofSize: 24, weight: .medium),
    color: muted,
    lineHeight: 30
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render social card\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
print("Generated \(outputPath) (\(Int(width * scale))x\(Int(height * scale)))")
