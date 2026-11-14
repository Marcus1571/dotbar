// Generates assets/paypal-qr.png — the PayPal donation QR shown on the About
// page (AboutView in Settings.swift). Committed to the repo: the PNG is the
// shipped asset, this script exists so it can be regenerated/changed without
// network access or new dependencies (CoreImage is system-provided).
//
// Usage: swift scripts/make-qr.swift [output.png] [url]
// Defaults: assets/paypal-qr.png, https://paypal.me/marcodalmoro
//
// Self-verifies: after writing, decodes the PNG back with CIDetector's QR
// reader and fails loudly unless the payload round-trips exactly.

import AppKit
import CoreImage

let payURL = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "https://paypal.me/marcodalmoro"
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/paypal-qr.png"
let scale = 12        // px per QR module (crisp, nearest-neighbor)
let quietModules = 4  // quiet zone around the code, in modules (spec suggests 4)

let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(Data(payURL.utf8), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
guard let qr = filter.outputImage else {
    fputs("make-qr: error: CIQRCodeGenerator produced no image\n", stderr)
    exit(1)
}
let modules = Int(qr.extent.width)
let px = (modules + quietModules * 2) * scale

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .none   // nearest-neighbor: module edges stay sharp
NSColor.white.setFill()          // white ground: scannable from phone cameras in both modes
NSRect(x: 0, y: 0, width: px, height: px).fill()
if let cg = CIContext().createCGImage(qr, from: qr.extent) {
    NSImage(cgImage: cg, size: NSSize(width: modules, height: modules))
        .draw(in: NSRect(x: quietModules * scale, y: quietModules * scale,
                         width: modules * scale, height: modules * scale))
}
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("make-qr: error: PNG encoding failed\n", stderr)
    exit(1)
}
if !FileManager.default.createFile(atPath: outPath, contents: png) {
    fputs("make-qr: error: could not write \(outPath)\n", stderr)
    exit(1)
}

// Self-verification: decode what we just wrote and compare payloads.
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                          options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
let features = detector.features(in: CIImage(cgImage: rep.cgImage!)) as! [CIQRCodeFeature]
if let decoded = features.first?.messageString, decoded == payURL {
    print("make-qr: wrote \(outPath) (\(px)x\(px)), self-verified payload: \(decoded)")
} else {
    fputs("make-qr: error: generated QR failed self-verification (decodes as: \(features.first?.messageString ?? "nothing"))\n", stderr)
    exit(1)
}
