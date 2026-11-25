#!/usr/bin/env swift
// Composes the App Store screenshots (REL-14): a caption over a simulator
// capture, on a 1320 x 2868 canvas (the 6.9-inch slot, which App Store Connect
// scales down for smaller iPhones).
//
//   swift scripts/make-store-screenshots.swift
//
// Reads docs/release/screenshots/raw/*.png (captures from the simulator, which
// only ever shows built-in sample data) and writes docs/release/screenshots/.
// To retake a capture: `xcrun simctl status_bar booted override --time 9:41`,
// open the screen, then `xcrun simctl io booted screenshot <file>`.
import AppKit

let shots: [(raw: String, out: String, caption: String)] = [
    ("03-lock.png", "1-lock.png", "Locks with no\ncancel button."),
    ("01-today.png", "2-today.png", "See where your day\nreally went."),
    ("02-insights.png", "3-insights.png", "Find the hour\nyou slip."),
    ("04-guard.png", "4-guard.png", "An adult-content block\nwith no off switch."),
    ("05-settings.png", "5-settings.png", "Decide once,\nwith a clear head."),
]

let canvas = CGSize(width: 1320, height: 2868)
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("docs/release/screenshots")
let ink = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.23, alpha: 1)
let top = NSColor(srgbRed: 0.95, green: 0.94, blue: 0.99, alpha: 1)
let bottom = NSColor(srgbRed: 0.84, green: 0.81, blue: 0.98, alpha: 1)

for shot in shots {
    let source = root.appendingPathComponent("raw/\(shot.raw)")
    guard let image = NSImage(contentsOf: source),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Missing capture: \(source.path)")
    }
    // No alpha channel: App Store Connect refuses screenshots that have one.
    guard let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("No drawing context") }

    let gradient = CGGradient(colorsSpace: nil, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: .zero, options: [])

    // The phone: the capture inside a dark bezel, resting on the bottom edge.
    let width: CGFloat = 1060
    let height = width * CGFloat(cg.height) / CGFloat(cg.width)
    let screen = CGRect(x: (canvas.width - width) / 2, y: 70, width: width, height: height)
    let bezel = screen.insetBy(dx: -18, dy: -18)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 70,
                      color: NSColor(srgbRed: 0.2, green: 0.15, blue: 0.5, alpha: 0.35).cgColor)
    context.addPath(CGPath(roundedRect: bezel, cornerWidth: 168, cornerHeight: 168, transform: nil))
    context.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(CGPath(roundedRect: screen, cornerWidth: 150, cornerHeight: 150, transform: nil))
    context.clip()
    context.interpolationQuality = .high
    context.draw(cg, in: screen)
    context.restoreGState()

    // The caption, centred in the space above the phone.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 6
    let text = NSAttributedString(string: shot.caption, attributes: [
        .font: NSFont.systemFont(ofSize: 96, weight: .bold),
        .foregroundColor: ink,
        .paragraphStyle: paragraph,
        .kern: -1.5,
    ])
    let space = CGRect(x: 80, y: bezel.maxY, width: canvas.width - 160, height: canvas.height - bezel.maxY)
    let size = text.boundingRect(with: space.size, options: [.usesLineFragmentOrigin])
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    text.draw(with: CGRect(x: space.minX, y: space.midY - size.height / 2, width: space.width, height: size.height),
              options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()

    let output = root.appendingPathComponent(shot.out)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try! bitmap.representation(using: .png, properties: [:])!.write(to: output)
    print("wrote \(output.lastPathComponent)")
}
