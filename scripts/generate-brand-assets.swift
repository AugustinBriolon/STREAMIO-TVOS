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
let canvas = CGColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1)
let accent = CGColor(red: 229 / 255, green: 9 / 255, blue: 20 / 255, alpha: 1)
let deepRed = CGColor(red: 56 / 255, green: 6 / 255, blue: 12 / 255, alpha: 1)
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

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locations)!
}

// MARK: Drawing pieces, all in a 1280x768 design space then scaled
/// Back layer: opaque dark background with a deep red glow from the lower right.
func drawBackground(_ c: CGContext, _ size: CGSize) {
    c.setFillColor(canvas)
    c.fill(CGRect(origin: .zero, size: size))
    let glow = gradient([accent.copy(alpha: 0.55)!, deepRed.copy(alpha: 0.35)!, canvas.copy(alpha: 0)!], [0, 0.45, 1])
    c.drawRadialGradient(glow, startCenter: CGPoint(x: size.width * 0.78, y: size.height * 0.12), startRadius: 0,
                         endCenter: CGPoint(x: size.width * 0.78, y: size.height * 0.12), endRadius: size.width * 0.85, options: [])
    let vignette = gradient([CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.55)], [0.5, 1])
    c.drawRadialGradient(vignette, startCenter: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
                         endCenter: CGPoint(x: size.width / 2, y: size.height / 2), endRadius: size.width * 0.75, options: .drawsAfterEndLocation)
}

/// Middle layer: the red ring over a dark disc.
func drawRing(_ c: CGContext, center: CGPoint, radius: CGFloat) {
    c.setFillColor(CGColor(red: 14 / 255, green: 14 / 255, blue: 15 / 255, alpha: 0.92))
    c.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    c.saveGState()
    c.setShadow(offset: .zero, blur: radius * 0.22, color: accent.copy(alpha: 0.7))
    c.setStrokeColor(accent)
    c.setLineWidth(radius * 0.16)
    c.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    c.restoreGState()
}

/// Front layer: a white play triangle with rounded corners, optically centred.
func drawPlay(_ c: CGContext, center: CGPoint, height: CGFloat) {
    let h = height / 2
    let path = CGMutablePath()
    // Slightly right of centre: a triangle's visual centre is its centroid, not its bounding box.
    let origin = CGPoint(x: center.x + h * 0.12, y: center.y)
    path.move(to: CGPoint(x: origin.x - h * 0.62, y: origin.y + h))
    path.addLine(to: CGPoint(x: origin.x - h * 0.62, y: origin.y - h))
    path.addLine(to: CGPoint(x: origin.x + h * 0.92, y: origin.y))
    path.closeSubpath()
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -height * 0.05), blur: height * 0.12, color: CGColor(gray: 0, alpha: 0.5))
    // One transparency layer: the shadow is cast once by the finished shape. Drawing fill and stroke
    // separately cast the stroke's shadow onto the fill and greyed the inside of the triangle.
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    c.setFillColor(white)
    c.setStrokeColor(white)
    c.setLineJoin(.round)
    c.setLineWidth(height * 0.14)
    c.addPath(path)
    c.drawPath(using: .fillStroke)
    c.endTransparencyLayer()
    c.restoreGState()
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
    ("Middle", false, { c, _ in drawRing(c, center: iconCenter, radius: 232) }),
    ("Front", false, { c, _ in drawPlay(c, center: iconCenter, height: 230) }),
]

try? FileManager.default.removeItem(at: root)
write(["info": info], to: root.appendingPathComponent("Contents.json"))

writeStack(brand.appendingPathComponent("App Icon.imagestack"), width: 400, height: 240, scales: [1, 2], layers: iconLayers)
writeStack(brand.appendingPathComponent("App Icon - App Store.imagestack"), width: 1280, height: 768, scales: [1], layers: iconLayers)

// MARK: Top Shelf: logo on the left, wordmark on the right, centred as a group.
func drawTopShelf(_ c: CGContext, _ size: CGSize) {
    drawBackground(c, size)
    let ringRadius = size.height * 0.30
    let wordmark = "StremioTV"
    let font = NSFont.systemFont(ofSize: size.height * 0.2, weight: .heavy)
    let textWidth = (wordmark as NSString).size(withAttributes: [.font: font, .kern: -2]).width
    let gap = size.height * 0.14
    let groupWidth = ringRadius * 2 + gap + textWidth
    let startX = (size.width - groupWidth) / 2
    let center = CGPoint(x: startX + ringRadius, y: size.height / 2)
    drawRing(c, center: center, radius: ringRadius)
    drawPlay(c, center: center, height: ringRadius * 0.95)
    let textX = center.x + ringRadius + gap
    drawText(c, wordmark, at: CGPoint(x: textX, y: size.height / 2 - size.height * 0.02), size: size.height * 0.2, weight: .heavy,
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
