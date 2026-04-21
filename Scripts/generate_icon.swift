#!/usr/bin/env swift
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

func drawIcon(size: CGFloat) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius: CGFloat = size * 0.225

    // Background with rounded rect + vertical gradient
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let gradColors: [CGFloat] = [
        0.384, 0.400, 0.945, 1.0,   // #6266F1 indigo-500
        0.055, 0.647, 0.914, 1.0,   // #0EA5E9 sky-500
    ]
    let locations: [CGFloat] = [0, 1]
    let gradient = CGGradient(colorSpace: cs, colorComponents: gradColors, locations: locations, count: 2)!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )

    // Subtle inner top highlight
    let highlightPath = CGPath(
        roundedRect: rect.insetBy(dx: size * 0.03, dy: size * 0.03),
        cornerWidth: cornerRadius * 0.85,
        cornerHeight: cornerRadius * 0.85,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(highlightPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.setLineWidth(size * 0.012)
    ctx.strokePath()
    ctx.restoreGState()

    // Bar chart — 4 rounded white bars
    let barCount = 4
    let barHeights: [CGFloat] = [0.34, 0.58, 0.82, 0.46]
    let plotInset: CGFloat = size * 0.20
    let plotWidth = size - plotInset * 2
    let plotBottom = size * 0.22
    let plotTop = size * 0.82
    let plotHeight = plotTop - plotBottom
    let spacing: CGFloat = size * 0.04
    let totalSpacing = spacing * CGFloat(barCount - 1)
    let barWidth = (plotWidth - totalSpacing) / CGFloat(barCount)
    let barCorner = barWidth * 0.28

    for i in 0..<barCount {
        let h = plotHeight * barHeights[i]
        let x = plotInset + CGFloat(i) * (barWidth + spacing)
        let y = plotBottom
        let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
        let path = CGPath(
            roundedRect: barRect,
            cornerWidth: barCorner,
            cornerHeight: barCorner,
            transform: nil
        )
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Accent token dot above the tallest (3rd) bar
    let tallIdx = 2
    let tallX = plotInset + CGFloat(tallIdx) * (barWidth + spacing) + barWidth / 2
    let tallY = plotBottom + plotHeight * barHeights[tallIdx] + size * 0.06
    let dotRadius = size * 0.055
    ctx.setFillColor(CGColor(red: 1.0, green: 0.78, blue: 0.18, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(
        x: tallX - dotRadius,
        y: tallY - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    ))

    // Baseline
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.setLineWidth(size * 0.012)
    ctx.move(to: CGPoint(x: plotInset - size * 0.02, y: plotBottom - size * 0.015))
    ctx.addLine(to: CGPoint(x: size - plotInset + size * 0.02, y: plotBottom - size * 0.015))
    ctx.strokePath()

    return ctx.makeImage()!
}

func writePNG(image: CGImage, to url: URL) throws {
    guard let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 1)
    }
    CGImageDestinationAddImage(dst, image, nil)
    guard CGImageDestinationFinalize(dst) else { throw NSError(domain: "icon", code: 2) }
}

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let outDir = cwd.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
try? fm.removeItem(at: outDir)
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, dim) in specs {
    let img = drawIcon(size: CGFloat(dim))
    let url = outDir.appendingPathComponent(name)
    try writePNG(image: img, to: url)
    print("wrote \(name) @ \(dim)px")
}

print("iconset at \(outDir.path)")
