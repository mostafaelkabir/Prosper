import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Prosper app icon master (REL-3), built from the approved Aurora palette in
// Prosper/DesignSystem/ProsperColor.swift. Deep Aurora night field, a ring
// sweeping violet -> cyan -> mint (the brand accent and two of the four time
// classes), and a lock at the centre: the ring is the time, the lock is the
// promise. No alpha, sRGB, square — App Store Connect rejects anything else.

let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255, a,
    ])!
}

// Aurora tokens
let night      = rgb(0x090D18)   // background (dark)
let nightLift  = rgb(0x1C2740)   // surface2 (dark)
let accent     = rgb(0xA58AFF)   // accent (dark)
let rest       = rgb(0x64CBE6)   // rest (dark)
let productive = rgb(0x58E4B3)   // productive (dark)
let inkLight   = rgb(0xF0F3FF)   // ink (dark)

guard let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
    bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("context") }

let full = CGRect(x: 0, y: 0, width: S, height: S)
let centre = CGPoint(x: S / 2, y: S / 2)

// 1. Field: a soft radial lift so the square is not flat black.
ctx.setFillColor(night)
ctx.fill(full)
if let bg = CGGradient(colorsSpace: space, colors: [nightLift, night] as CFArray,
                       locations: [0, 1]) {
    ctx.drawRadialGradient(
        bg,
        startCenter: CGPoint(x: S * 0.5, y: S * 0.62), startRadius: 0,
        endCenter: centre, endRadius: S * 0.72,
        options: [.drawsAfterEndLocation]
    )
}

// 2. The ring, drawn as short arc segments so the colour can sweep between the
//    three stops the way a conic gradient would.
func lerp(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    let ac = a.components!, bc = b.components!
    return CGColor(colorSpace: space, components: (0..<4).map { ac[$0] + (bc[$0] - ac[$0]) * t })!
}

let stops: [CGColor] = [accent, rest, productive, accent]
let radius = S * 0.30
let ringWidth = S * 0.085
// Leave a gap at the bottom: the ring is time still running, not a closed loop.
let gap: CGFloat = 52 * .pi / 180
let start = -.pi / 2 + gap / 2
let sweep = 2 * .pi - gap
let segments = 360

ctx.setLineCap(.round)
ctx.setLineWidth(ringWidth)
for i in 0..<segments {
    let t0 = CGFloat(i) / CGFloat(segments)
    let t1 = CGFloat(i + 1) / CGFloat(segments)
    let scaled = t0 * CGFloat(stops.count - 1)
    let index = min(Int(scaled), stops.count - 2)
    ctx.setStrokeColor(lerp(stops[index], stops[index + 1], scaled - CGFloat(index)))
    ctx.beginPath()
    ctx.addArc(center: centre, radius: radius,
               startAngle: start + sweep * t0,
               endAngle: start + sweep * t1 + 0.004,
               clockwise: false)
    ctx.strokePath()
}

// 3. The lock, centred inside the ring.
let bodyW = S * 0.235
let bodyH = S * 0.185
let bodyRect = CGRect(x: centre.x - bodyW / 2, y: centre.y - bodyH / 2 - S * 0.035,
                      width: bodyW, height: bodyH)
ctx.setFillColor(inkLight)
ctx.addPath(CGPath(roundedRect: bodyRect, cornerWidth: S * 0.045, cornerHeight: S * 0.045,
                   transform: nil))
ctx.fillPath()

// Shackle: a half-circle rising out of the body.
let shackleR = bodyW * 0.32
let shackleY = bodyRect.maxY
ctx.setStrokeColor(inkLight)
ctx.setLineWidth(S * 0.043)
ctx.setLineCap(.butt)
ctx.beginPath()
ctx.addArc(center: CGPoint(x: centre.x, y: shackleY), radius: shackleR,
           startAngle: 0, endAngle: .pi, clockwise: false)
ctx.strokePath()

// Keyhole, punched in the field colour so the lock reads as solid.
ctx.setFillColor(night)
let keyR = S * 0.026
ctx.fillEllipse(in: CGRect(x: centre.x - keyR, y: bodyRect.midY - keyR * 0.2,
                           width: keyR * 2, height: keyR * 2))
ctx.fill(CGRect(x: centre.x - keyR * 0.46, y: bodyRect.midY - S * 0.042,
                width: keyR * 0.92, height: S * 0.05))

guard let image = ctx.makeImage() else { fatalError("image") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("dest") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("wrote \(out.path)")
