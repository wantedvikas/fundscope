// Draws FundScope's app icon (a lens over a rising NAV line) and writes every macOS size into AppIcon.appiconset.
// Run: swift scripts/make-app-icon.swift
import AppKit

let out = URL(filePath: "FundScope/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

func draw(_ ctx: CGContext) {
    // macOS icon grid: an 824 pt tile centred on a 1024 canvas, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0.07, 0.20, 0.52)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [rgb(0.05, 0.62, 0.66), rgb(0.09, 0.27, 0.68), rgb(0.06, 0.12, 0.40)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: [])

    // Faint chart grid.
    ctx.setStrokeColor(rgb(1, 1, 1, 0.08)); ctx.setLineWidth(6)
    for y in stride(from: 260.0, through: 780, by: 130) { ctx.move(to: CGPoint(x: 100, y: y)); ctx.addLine(to: CGPoint(x: 924, y: y)) }
    ctx.strokePath()

    // The lens, with the rising line seen through it.
    let center = CGPoint(x: 455, y: 575), radius: CGFloat = 225
    let lens = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: lens); ctx.clip()
    ctx.setFillColor(rgb(1, 1, 1, 0.12)); ctx.fill(lens)
    let points = [(150, 420), (290, 520), (390, 470), (500, 610), (600, 560), (760, 760)].map { CGPoint(x: $0.0, y: $0.1) }
    ctx.setStrokeColor(rgb(1, 1, 1)); ctx.setLineWidth(34); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addLines(between: points); ctx.strokePath()
    ctx.restoreGState()

    ctx.setStrokeColor(rgb(1, 1, 1)); ctx.setLineWidth(46); ctx.setLineCap(.round)
    ctx.strokeEllipse(in: lens)
    // Handle, down and to the right.
    ctx.setLineWidth(78)
    ctx.move(to: CGPoint(x: center.x + radius * 0.74, y: center.y - radius * 0.74))
    ctx.addLine(to: CGPoint(x: 790, y: 240)); ctx.strokePath()

    // Latest point, in the app's "up" green.
    let dot = CGPoint(x: 596, y: 562)
    ctx.setFillColor(rgb(0.30, 0.85, 0.52)); ctx.fillEllipse(in: CGRect(x: dot.x - 30, y: dot.y - 30, width: 60, height: 60))
    ctx.setStrokeColor(rgb(1, 1, 1)); ctx.setLineWidth(12); ctx.strokeEllipse(in: CGRect(x: dot.x - 30, y: dot.y - 30, width: 60, height: 60))
    ctx.restoreGState()
}

func png(_ px: Int) throws -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

var images: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png(size * scale).write(to: out.appending(path: name))
        images.append(#"{ "idiom": "mac", "size": "\#(size)x\#(size)", "scale": "\#(scale)x", "filename": "\#(name)" }"#)
    }
}
try #"{ "images": [\#n    \#(images.joined(separator: ",\n    "))\#n  ], "info": { "author": "xcode", "version": 1 } }"#
    .write(to: out.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
try #"{ "info": { "author": "xcode", "version": 1 } }"#
    .write(to: out.deletingLastPathComponent().appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons to \(out.path())")
