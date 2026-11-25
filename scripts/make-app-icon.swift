import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Stolen Glance app icon (DS-10; replaces the REL-3 ring and padlock). The mark
// comes from Prosper/DesignSystem/GlanceGeometry.swift, compiled alongside, so
// the icon is the exact mark the app draws: Aurora night field, a soft violet
// glow, the eye with its lowered lid and the keyhole pupil.
//
//   swiftc -parse-as-library scripts/make-app-icon.swift \
//     Prosper/DesignSystem/GlanceGeometry.swift -o "$TMPDIR/make-app-icon"
//   "$TMPDIR/make-app-icon" ios Prosper/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//   "$TMPDIR/make-app-icon" mac "$TMPDIR/mac.png"
//   for s in 16 32 64 128 256 512 1024; do
//     sips -z $s $s "$TMPDIR/mac.png" --out ProsperMac/Assets.xcassets/AppIcon.appiconset/icon_$s.png
//   done
//
// ios: full-bleed square, no alpha, sRGB (App Store Connect rejects anything
// else; iOS rounds the corners). mac: the same art on the macOS rounded tile,
// 824 of 1024 with transparent margins.

@main
struct MakeAppIcon {
    static let S: CGFloat = 1024
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func rgb(_ hex: UInt, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255, a,
        ])!
    }

    // Aurora tokens (dark), from ProsperColor.swift
    static let night = rgb(0x090D18)
    static let nightMid = rgb(0x0E1424)
    static let nightLift = rgb(0x1F2A48)
    static let accent = rgb(0xA58AFF)
    static let rest = rgb(0x64CBE6)
    static let productive = rgb(0x58E4B3)
    static let ink = rgb(0xF0F3FF)

    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3, ["ios", "mac"].contains(args[1]) else {
            print("usage: make-app-icon ios|mac <out.png>"); exit(2)
        }
        let mac = args[1] == "mac"
        let alpha: CGImageAlphaInfo = mac ? .premultipliedLast : .noneSkipLast
        guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue)
        else { fatalError("context") }

        // Top-left origin, like the mark's geometry.
        ctx.translateBy(x: 0, y: S)
        ctx.scaleBy(x: 1, y: -1)

        if mac {
            // macOS tile: 824 pt square with 100 pt margins.
            let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
            ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
            ctx.clip()
            ctx.translateBy(x: 100, y: 100)
            ctx.scaleBy(x: 824 / S, y: 824 / S)
        }
        drawArt(ctx)

        guard let image = ctx.makeImage() else { fatalError("image") }
        let out = URL(fileURLWithPath: args[2])
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { fatalError("dest") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("write") }
        print("wrote \(out.path)")
    }

    static func drawArt(_ ctx: CGContext) {
        let full = CGRect(x: 0, y: 0, width: S, height: S)

        // 1. Night field with a lift above centre, so the square is not flat.
        ctx.setFillColor(night)
        ctx.fill(full)
        let field = CGGradient(colorsSpace: space, colors: [nightLift, nightMid, night] as CFArray,
                               locations: [0, 0.62, 1])!
        ctx.drawRadialGradient(field, startCenter: CGPoint(x: 512, y: 430), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 430), endRadius: 760,
                               options: [.drawsAfterEndLocation])

        // 2. A soft violet glow behind the iris.
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0xA58AFF, 0.28), rgb(0xA58AFF, 0)] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 540), endRadius: 320, options: [])

        // 3. The mark: its 200-unit box at 870 pt, centred.
        ctx.saveGState()
        ctx.translateBy(x: 77, y: 72)
        ctx.scaleBy(x: 870 / GlanceGeometry.box, y: 870 / GlanceGeometry.box)
        drawMark(ctx, GlanceState.rest)
        ctx.restoreGState()
    }

    static func drawMark(_ ctx: CGContext, _ s: GlanceState) {
        // Iris, clipped to the opening, with the keyhole cleared out of it.
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(GlanceGeometry.opening(s.lid))
        ctx.clip()
        var ball = GlanceGeometry.eyeball(s)
        let r = GlanceGeometry.irisRadius
        ctx.setFillColor(ink)
        ctx.addPath(CGPath(ellipseIn: CGRect(x: 100 - r, y: 100 - r, width: r * 2, height: r * 2), transform: &ball))
        ctx.fillPath()
        ctx.setBlendMode(.clear)
        ctx.addPath(CGPath(ellipseIn: GlanceGeometry.pupil(key: s.key), transform: &ball))
        ctx.addPath(GlanceGeometry.stem(key: s.key).copy(using: &ball)!)
        ctx.fillPath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        // Lids, filled with the violet -> cyan -> mint gradient.
        ctx.saveGState()
        ctx.addPath(GlanceGeometry.lowerLid)
        ctx.addPath(GlanceGeometry.upperLid(s.lid))
        ctx.clip()
        let lids = CGGradient(colorsSpace: space, colors: [accent, rest, productive] as CFArray,
                              locations: GlanceGeometry.gradientStops)!
        ctx.drawLinearGradient(lids, start: GlanceGeometry.gradientStart, end: GlanceGeometry.gradientEnd,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
}
