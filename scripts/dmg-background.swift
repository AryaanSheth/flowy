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

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func strokeWave(y: CGFloat, amplitude: CGFloat, alpha: CGFloat, lineWidth: CGFloat) {
    let wave = NSBezierPath()
    wave.lineWidth = lineWidth
    wave.lineCapStyle = .round
    wave.move(to: NSPoint(x: -20, y: y))
    wave.curve(
        to: NSPoint(x: size.width + 20, y: y - 4),
        controlPoint1: NSPoint(x: 170, y: y + amplitude),
        controlPoint2: NSPoint(x: 450, y: y - amplitude)
    )
    color(26, 175, 173, alpha).setStroke()
    wave.stroke()
}

color(9, 17, 22).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let vignette = NSGradient(colors: [
    color(20, 35, 43, 0.98),
    color(8, 15, 20, 1.0)
])!
vignette.draw(in: NSRect(origin: .zero, size: size), angle: -90)

let topBand = NSGradient(colors: [
    color(26, 175, 173, 0.18),
    color(26, 175, 173, 0.00)
])!
topBand.draw(in: NSRect(x: 0, y: 270, width: size.width, height: 150), angle: -90)

strokeWave(y: 78, amplitude: 54, alpha: 0.16, lineWidth: 2.5)
strokeWave(y: 54, amplitude: 36, alpha: 0.08, lineWidth: 1.5)
strokeWave(y: 370, amplitude: 24, alpha: 0.05, lineWidth: 1)

color(255, 255, 255, 0.035).setStroke()
let frame = roundedRect(NSRect(x: 18, y: 18, width: size.width - 36, height: size.height - 36), radius: 18)
frame.lineWidth = 1
frame.stroke()

let wordmarkAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 16, weight: .bold),
    .foregroundColor: color(236, 244, 243, 0.76)
]
let wordWave = NSBezierPath()
wordWave.lineWidth = 2
wordWave.lineCapStyle = .round
wordWave.move(to: NSPoint(x: 42, y: 354))
wordWave.curve(
    to: NSPoint(x: 72, y: 354),
    controlPoint1: NSPoint(x: 50, y: 362),
    controlPoint2: NSPoint(x: 64, y: 346)
)
color(26, 175, 173, 0.90).setStroke()
wordWave.stroke()
"flowy".draw(at: NSPoint(x: 80, y: 344), withAttributes: wordmarkAttributes)

let title = "Drag Flowy to Applications"
let subtitle = "Install once. Launch from Applications whenever you need it."
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .bold),
    .foregroundColor: color(239, 247, 247)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: color(169, 191, 193)
]

let titleSize = title.size(withAttributes: titleAttributes)
title.draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: 314),
    withAttributes: titleAttributes
)

let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
subtitle.draw(
    at: NSPoint(x: (size.width - subtitleSize.width) / 2, y: 286),
    withAttributes: subtitleAttributes
)

let appLabelPad = roundedRect(NSRect(x: 148, y: 103, width: 84, height: 30), radius: 15)
color(232, 242, 241, 0.86).setFill()
appLabelPad.fill()

let applicationsLabelPad = roundedRect(NSRect(x: 438, y: 103, width: 106, height: 30), radius: 15)
color(232, 242, 241, 0.86).setFill()
applicationsLabelPad.fill()

let appHalo = NSGradient(colors: [
    color(26, 175, 173, 0.14),
    color(26, 175, 173, 0.00)
])!
appHalo.draw(in: NSRect(x: 106, y: 112, width: 168, height: 168), relativeCenterPosition: NSPoint(x: 0, y: 0))

let folderHalo = NSGradient(colors: [
    color(26, 175, 173, 0.10),
    color(26, 175, 173, 0.00)
])!
folderHalo.draw(in: NSRect(x: 392, y: 112, width: 190, height: 168), relativeCenterPosition: NSPoint(x: 0, y: 0))

let arrowY: CGFloat = 207
let arrowShadow = NSBezierPath()
arrowShadow.lineWidth = 13
arrowShadow.lineCapStyle = .round
arrowShadow.move(to: NSPoint(x: 276, y: arrowY - 1))
arrowShadow.line(to: NSPoint(x: 384, y: arrowY - 1))
color(0, 0, 0, 0.18).setStroke()
arrowShadow.stroke()

let arrow = NSBezierPath()
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 276, y: arrowY))
arrow.line(to: NSPoint(x: 384, y: arrowY))
color(26, 175, 173, 0.95).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 386, y: arrowY))
arrowHead.line(to: NSPoint(x: 362, y: arrowY + 22))
arrowHead.move(to: NSPoint(x: 386, y: arrowY))
arrowHead.line(to: NSPoint(x: 362, y: arrowY - 22))
arrowHead.lineWidth = 8
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.stroke()

let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
    .foregroundColor: color(124, 151, 154, 0.72)
]
let footer = "Private dictation for macOS"
footer.draw(at: NSPoint(x: 42, y: 40), withAttributes: footerAttributes)

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render DMG background\n", stderr)
    exit(1)
}

try data.write(to: outputURL, options: [.atomic])
