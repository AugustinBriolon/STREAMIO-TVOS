#!/usr/bin/env swift
// Generates the tvOS brand assets (layered app icon, App Store icon, Top Shelf images) into
// Sources/Assets.xcassets. Usage: swift scripts/generate-brand-assets.swift
// One drawing description, rendered at every size the asset catalog needs (ADR 0013).
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: Palette (matches Theme.swift)
let accent = CGColor(red: 229 / 255, green: 9 / 255, blue: 20 / 255, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

// MARK: Rendering helpers
func render(width: Int, height: Int, opaque: Bool, draw: (CGContext, CGSize) -> Void) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    draw(context, CGSize(width: width, height: height))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

// MARK: Drawing pieces, all in a 1280x768 design space then scaled
let ink = CGColor(red: 11 / 255, green: 11 / 255, blue: 12 / 255, alpha: 1)

/// Back layer: flat near-black. No glow, no vignette: the mark carries the identity.
func drawBackground(_ c: CGContext, _ size: CGSize) {
    c.setFillColor(ink)
    c.fill(CGRect(origin: .zero, size: size))
}

/// Middle layer: the "V", one white stroke with round ends. `height` is the letter's height.
func drawMark(_ c: CGContext, center: CGPoint, height: CGFloat) {
    let halfWidth = height * 0.5
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x - halfWidth, y: center.y + height / 2))
    path.addLine(to: CGPoint(x: center.x, y: center.y - height / 2))
    path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y + height / 2))
    c.setStrokeColor(white)
    c.setLineWidth(height * 0.24)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.addPath(path)
    c.strokePath()
}

/// Front layer: the single red dot held between the arms of the V.
func drawDot(_ c: CGContext, center: CGPoint, height: CGFloat) {
    let radius = height * 0.13
    let dot = CGPoint(x: center.x, y: center.y + height * 0.42)
    c.setFillColor(accent)
    c.fillEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
}

func drawText(_ c: CGContext, _ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern,
    ]
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    NSAttributedString(string: string, attributes: attributes).draw(at: point)
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: Asset catalog writing
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/Assets.xcassets")
let brand = root.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
let info: [String: Any] = ["author": "xcode", "version": 1]

func write(_ object: Any, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

/// An imageset with one file per scale. `sizes` maps scale to pixel size.
func writeImageSet(_ url: URL, filename: String, sizes: [(scale: Int, width: Int, height: Int)], opaque: Bool,
                   draw: @escaping (CGContext, CGSize) -> Void) {
    var images: [[String: String]] = []
    for size in sizes {
        let name = "\(filename)@\(size.scale)x.png"
        let data = render(width: size.width, height: size.height, opaque: opaque, draw: draw)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try! data.write(to: url.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "tv", "scale": "\(size.scale)x"])
    }
    write(["images": images, "info": info], to: url.appendingPathComponent("Contents.json"))
}

/// A layered image stack (back to front) at the given point size, 1x and 2x.
func writeStack(_ url: URL, width: Int, height: Int, scales: [Int], layers: [(name: String, opaque: Bool, draw: (CGContext, CGSize) -> Void)]) {
    // Xcode lists layers front to back.
    write(["layers": layers.reversed().map { ["filename": "\($0.name).imagestacklayer"] }, "info": info],
          to: url.appendingPathComponent("Contents.json"))
    for layer in layers {
        let layerURL = url.appendingPathComponent("\(layer.name).imagestacklayer")
        write(["info": info], to: layerURL.appendingPathComponent("Contents.json"))
        writeImageSet(layerURL.appendingPathComponent("Content.imageset"), filename: layer.name.lowercased(),
                      sizes: scales.map { ($0, width * $0, height * $0) }, opaque: layer.opaque) { context, size in
            // Design space is 1280x768; scale to the target.
            context.scaleBy(x: size.width / 1280, y: size.height / 768)
            layer.draw(context, CGSize(width: 1280, height: 768))
        }
    }
}

// MARK: Icon layers
let iconCenter = CGPoint(x: 640, y: 384)
let iconLayers: [(name: String, opaque: Bool, draw: (CGContext, CGSize) -> Void)] = [
    ("Back", true, { c, s in drawBackground(c, s) }),
    ("Middle", false, { c, _ in drawMark(c, center: iconCenter, height: 340) }),
    ("Front", false, { c, _ in drawDot(c, center: iconCenter, height: 340) }),
]

// Only the generated brand assets: the catalog can hold hand-made images the script does not generate.
try? FileManager.default.removeItem(at: brand)
write(["info": info], to: root.appendingPathComponent("Contents.json"))

writeStack(brand.appendingPathComponent("App Icon.imagestack"), width: 400, height: 240, scales: [1, 2], layers: iconLayers)
writeStack(brand.appendingPathComponent("App Icon - App Store.imagestack"), width: 1280, height: 768, scales: [1], layers: iconLayers)

// MARK: Top Shelf: logo on the left, wordmark on the right, centred as a group.
func drawTopShelf(_ c: CGContext, _ size: CGSize) {
    drawBackground(c, size)
    let ringRadius = size.height * 0.17
    let wordmark = "StremioTV"
    let font = NSFont.systemFont(ofSize: size.height * 0.2, weight: .semibold)
    let textWidth = (wordmark as NSString).size(withAttributes: [.font: font, .kern: -2]).width
    let gap = size.height * 0.14
    let groupWidth = ringRadius * 2 + gap + textWidth
    let startX = (size.width - groupWidth) / 2
    let center = CGPoint(x: startX + ringRadius, y: size.height / 2)
    drawMark(c, center: center, height: ringRadius * 2)
    drawDot(c, center: center, height: ringRadius * 2)
    let textX = center.x + ringRadius + gap
    drawText(c, wordmark, at: CGPoint(x: textX, y: size.height / 2 - size.height * 0.02), size: size.height * 0.2, weight: .semibold,
             color: .white, kern: -2)
    drawText(c, "Films et séries sur Apple TV", at: CGPoint(x: textX + 4, y: size.height / 2 - size.height * 0.17), size: size.height * 0.062,
             weight: .medium, color: NSColor(white: 1, alpha: 0.7), kern: 1)
}

writeImageSet(brand.appendingPathComponent("Top Shelf Image.imageset"), filename: "topshelf",
              sizes: [(1, 1920, 720), (2, 3840, 1440)], opaque: true, draw: drawTopShelf)
writeImageSet(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), filename: "topshelf-wide",
              sizes: [(1, 2320, 720), (2, 4640, 1440)], opaque: true, draw: drawTopShelf)

write([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], to: brand.appendingPathComponent("Contents.json"))

print("Brand assets written to \(root.path)")
