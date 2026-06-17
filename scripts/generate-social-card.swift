#!/usr/bin/env swift
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputPath = CommandLine.arguments.dropFirst().first ?? "website/og-image.png"
let outputURL = repoRoot.appendingPathComponent(outputPath)

let width: CGFloat = 1200
let height: CGFloat = 630
let scale: CGFloat = 1

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let blue = NSColor(calibratedRed: 0.08, green: 0.53, blue: 0.92, alpha: 1)
let deepBlue = NSColor(calibratedRed: 0.02, green: 0.30, blue: 0.72, alpha: 1)
let white = NSColor(calibratedWhite: 1, alpha: 1)
let softWhite = NSColor(calibratedWhite: 1, alpha: 0.82)

let backgroundGradient = NSGradient(colors: [blue, deepBlue])!
backgroundGradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -18)

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

func drawCenteredText(_ text: String, yFromTop: CGFloat, font: NSFont, color: NSColor, lineHeight: CGFloat? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
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
    let rect = attributed.boundingRect(
        with: NSSize(width: width - 160, height: 400),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    attributed.draw(in: NSRect(
        x: 80,
        y: height - yFromTop - rect.height.rounded(.up),
        width: width - 160,
        height: rect.height.rounded(.up) + 10
    ))
}

drawCenteredText(
    "~flowy",
    yFromTop: 220,
    font: .systemFont(ofSize: 116, weight: .heavy),
    color: white,
    lineHeight: 124
)

drawCenteredText(
    "your voice. your machine.",
    yFromTop: 358,
    font: .systemFont(ofSize: 34, weight: .medium),
    color: softWhite,
    lineHeight: 44
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
