// Renders the dotbar app icon as a macOS iconset directory.
//
// Usage: swift scripts/make-icon.swift <iconset-dir>
// Design: dark rounded plate, a white dot above a light bar — the menu-bar dot
// and the second bar below it. Generated at build time; no binary assets live
// in the repo. Same plate proportions as the diskled-plus icon (one family).

import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
let base = 1024

func draw(_ s: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    ctx.saveGState()
    ctx.scaleBy(x: CGFloat(s) / CGFloat(base), y: CGFloat(s) / CGFloat(base))
    let face = CGPath(roundedRect: CGRect(x: 104, y: 104, width: 816, height: 816), cornerWidth: 184, cornerHeight: 184, transform: nil)

    // Plate with a soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44, color: CGColor(colorSpace: space, components: [0, 0, 0, 0.35])!)
    ctx.setFillColor(CGColor(colorSpace: space, components: [0.070, 0.067, 0.063, 1.0])!)
    ctx.addPath(face)
    ctx.fillPath()
    ctx.restoreGState()

    // Sheen on the top of the plate
    ctx.saveGState()
    ctx.addPath(face)
    ctx.clip()
    let sheen = CGGradient(colorsSpace: space, colors: [CGColor(colorSpace: space, components: [1, 1, 1, 0.10])!,
                                                        CGColor(colorSpace: space, components: [1, 1, 1, 0.0])!] as CFArray,
                           locations: [0, 0.5])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: CGFloat(base)), end: CGPoint(x: 0, y: 0), options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // The dot, with a soft glow
    func glow(_ rect: CGRect, core: [CGFloat], halo: [CGFloat]) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 30, color: CGColor(colorSpace: space, components: halo)!)
        ctx.setFillColor(CGColor(colorSpace: space, components: core)!)
        ctx.addPath(CGPath(ellipseIn: rect, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }
    glow(CGRect(x: 382, y: 470, width: 260, height: 260), core: [1, 1, 1, 1], halo: [1, 1, 1, 0.4])

    // The bar below the dot
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22, color: CGColor(colorSpace: space, components: [1, 1, 1, 0.25])!)
    ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.92])!)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 292, y: 268, width: 440, height: 104), cornerWidth: 52, cornerHeight: 52, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()
    return ctx.makeImage()!
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, s) in [("icon_512x512@2x.png", 1024), ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32),
                  ("icon_32x32@2x.png", 64), ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
                  ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512)] {
    let rep = NSBitmapImageRep(cgImage: draw(s))
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("iconset written: \(outDir)")
