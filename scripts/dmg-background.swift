import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: dmg-background.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 660, height: 420)
let scale = 2
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width) * scale,
    pixelsHigh: Int(size.height) * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

color(24, 24, 23).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let vignette = NSGradient(colors: [
    color(34, 34, 32, 0.96),
    color(20, 20, 19, 1.0)
])!
vignette.draw(in: NSRect(origin: .zero, size: size), angle: -90)

color(77, 214, 199, 0.10).setStroke()
let accent = NSBezierPath()
accent.lineWidth = 2
accent.move(to: NSPoint(x: 0, y: 78))
accent.curve(
    to: NSPoint(x: size.width, y: 82),
    controlPoint1: NSPoint(x: 170, y: 140),
    controlPoint2: NSPoint(x: 420, y: 18)
)
accent.stroke()

let title = "Drag Flowy to Applications"
let subtitle = "Install once. Then launch it from your Applications folder."
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    .foregroundColor: color(244, 244, 241)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
    .foregroundColor: color(178, 178, 170)
]

let titleSize = title.size(withAttributes: titleAttributes)
title.draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: 322),
    withAttributes: titleAttributes
)

let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
subtitle.draw(
    at: NSPoint(x: (size.width - subtitleSize.width) / 2, y: 294),
    withAttributes: subtitleAttributes
)

let arrowY: CGFloat = 207
let arrow = NSBezierPath()
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 274, y: arrowY))
arrow.line(to: NSPoint(x: 386, y: arrowY))
color(77, 214, 199, 0.88).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 386, y: arrowY))
arrowHead.line(to: NSPoint(x: 366, y: arrowY + 17))
arrowHead.move(to: NSPoint(x: 386, y: arrowY))
arrowHead.line(to: NSPoint(x: 366, y: arrowY - 17))
arrowHead.lineWidth = 7
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render DMG background\n", stderr)
    exit(1)
}

try data.write(to: outputURL, options: [.atomic])
