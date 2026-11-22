#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SceneSpec {
    let name: String
    let headline: String
}

let scenes: [SceneSpec] = [
    SceneSpec(name: "browse", headline: "Open and manage\nevery archive format"),
    SceneSpec(name: "archive", headline: "Inspect and extract\nexactly what you need"),
    SceneSpec(name: "create", headline: "Create ZIP, 7z, tar\nand more on device"),
    SceneSpec(name: "recent", headline: "Pick up recent archives\nwhere you left off"),
]

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let baseDir = scriptURL.deletingLastPathComponent()
let rawDir = baseDir.appendingPathComponent("raw")
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

func p3Color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(colorSpace: p3, components: [r, g, b, a])!
}

func hexP3(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return p3Color(r, g, b, alpha)
}

func makeContext(width: Int, height: Int) -> CGContext {
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: p3,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CGContext \(width)x\(height)")
    }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func loadHeadlineFont(size: CGFloat) -> NSFont {
    let fontPath = "/Applications/Pixelmator Pro.app/Contents/Frameworks/PXMPro.framework/Versions/A/Resources/Fonts/Archivo_SemiExpanded-Bold.ttf"
    let url = URL(fileURLWithPath: fontPath) as CFURL
    if FileManager.default.fileExists(atPath: fontPath),
       let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
       let first = descs.first {
        let ctFont = CTFontCreateWithFontDescriptor(first, size, nil)
        return ctFont as NSFont
    }
    if let sfDisplay = NSFont(name: "SFProDisplay-Bold", size: size) {
        return sfDisplay
    }
    return NSFont.systemFont(ofSize: size, weight: .bold)
}

func drawStudioBackground(in ctx: CGContext, width: CGFloat, height: CGFloat) {
    // Base diagonal gradient sampled from Pixelmator Pro's "1-App Screenshot" template
    let baseGradient = CGGradient(
        colorsSpace: p3,
        colors: [
            hexP3(0xF7EFEE),
            hexP3(0xEEE8EC),
            hexP3(0xDFDFE9),
            hexP3(0xC6C7D5),
        ] as CFArray,
        locations: [0.0, 0.34, 0.72, 1.0]
    )!
    // In unflipped CGContext: top-left is (0, height), bottom-right is (width, 0)
    ctx.drawLinearGradient(
        baseGradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: width, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Subtle warm studio key light top-left
    let warmGlow = CGGradient(
        colorsSpace: p3,
        colors: [hexP3(0xFAF0EE, alpha: 0.55), hexP3(0xFAF0EE, alpha: 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(
        warmGlow,
        startCenter: CGPoint(x: width * 0.14, y: height * 0.92),
        startRadius: 0,
        endCenter: CGPoint(x: width * 0.14, y: height * 0.92),
        endRadius: width * 0.72,
        options: []
    )

    // Subtle cool lavender depth bottom-center/right
    let coolWash = CGGradient(
        colorsSpace: p3,
        colors: [hexP3(0xB8BAC9, alpha: 0.42), hexP3(0xB8BAC9, alpha: 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(
        coolWash,
        startCenter: CGPoint(x: width * 0.78, y: height * 0.10),
        startRadius: 0,
        endCenter: CGPoint(x: width * 0.78, y: height * 0.10),
        endRadius: width * 0.85,
        options: []
    )
}

func drawHeadline(_ text: String, in ctx: CGContext, canvasWidth: CGFloat, canvasHeight: CGFloat, topY: CGFloat, bottomY: CGFloat, preferredSize: CGFloat, maxLineWidth: CGFloat) {
    var fontSize = preferredSize
    var font = loadHeadlineFont(size: fontSize)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 1.06
    paragraph.paragraphSpacing = 0

    func makeAttributed(_ sz: CGFloat, _ f: NSFont) -> NSAttributedString {
        let color = NSColor(cgColor: hexP3(0x1B1B1F)) ?? .black
        return NSAttributedString(string: text, attributes: [
            .font: f,
            .foregroundColor: color,
            .kern: -0.015 * sz,
            .paragraphStyle: paragraph,
        ])
    }

    var attr = makeAttributed(fontSize, font)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    while fontSize > 48 {
        let widest = lines.map { line -> CGFloat in
            let s = NSAttributedString(string: line, attributes: attr.attributes(at: 0, effectiveRange: nil))
            return s.size().width
        }.max() ?? 0
        if widest <= maxLineWidth { break }
        fontSize -= 2
        font = loadHeadlineFont(size: fontSize)
        attr = makeAttributed(fontSize, font)
    }

    let bounds = attr.boundingRect(
        with: CGSize(width: canvasWidth - 120, height: bottomY - topY),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let bandCenterTop = (topY + bottomY) * 0.5
    let drawTopY = bandCenterTop - bounds.height * 0.5
    let drawRect = CGRect(
        x: 60,
        y: canvasHeight - drawTopY - bounds.height,
        width: canvasWidth - 120,
        height: bounds.height + 8
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    attr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.restoreGraphicsState()
}

func rectFromTop(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, canvasH: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasH - y - h, width: w, height: h)
}

func loadCGImage(at url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("Missing or unreadable raw screenshot: \(url.path)")
    }
    return img
}

func savePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "render", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create destination \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "render", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG \(url.path)"])
    }
}

func drawSideButton(in ctx: CGContext, rect: CGRect, radius: CGFloat, isLeft: Bool) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let grad = CGGradient(
        colorsSpace: p3,
        colors: [hexP3(0x3D4047), hexP3(0x1D1E23), hexP3(0x2D3036)] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    let start = CGPoint(x: rect.minX, y: rect.maxY)
    let end = CGPoint(x: rect.minX, y: rect.minY)
    ctx.drawLinearGradient(grad, start: start, end: end, options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setStrokeColor(p3Color(1, 1, 1, isLeft ? 0.14 : 0.12))
    ctx.setLineWidth(1)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()
}

func renderIPhone(rawURL: URL, outURL: URL, headline: String) throws {
    let W: CGFloat = 1284
    let H: CGFloat = 2778
    let ctx = makeContext(width: Int(W), height: Int(H))

    drawStudioBackground(in: ctx, width: W, height: H)
    drawHeadline(headline, in: ctx, canvasWidth: W, canvasHeight: H, topY: 96, bottomY: 396, preferredSize: 82, maxLineWidth: W - 180)

    let outerRect = rectFromTop(111, 438, 1062, 2238, canvasH: H)
    let outerRadius: CGFloat = 154
    let outerPath = CGPath(roundedRect: outerRect, cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)

    // Side hardware buttons
    drawSideButton(in: ctx, rect: rectFromTop(105, 785, 8, 76, canvasH: H), radius: 3, isLeft: true)
    drawSideButton(in: ctx, rect: rectFromTop(105, 920, 8, 148, canvasH: H), radius: 3, isLeft: true)
    drawSideButton(in: ctx, rect: rectFromTop(105, 1104, 8, 148, canvasH: H), radius: 3, isLeft: true)
    drawSideButton(in: ctx, rect: rectFromTop(1171, 980, 8, 220, canvasH: H), radius: 3, isLeft: false)

    // Soft ambient shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 10, height: -28), blur: 80, color: p3Color(0.06, 0.07, 0.12, 0.24))
    ctx.setFillColor(hexP3(0x18191E))
    ctx.addPath(outerPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Closer contact shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 4, height: -10), blur: 24, color: p3Color(0.04, 0.05, 0.10, 0.20))
    ctx.setFillColor(hexP3(0x18191E))
    ctx.addPath(outerPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Outer titanium metallic band
    ctx.saveGState()
    ctx.addPath(outerPath)
    ctx.clip()
    let titaniumGrad = CGGradient(
        colorsSpace: p3,
        colors: [hexP3(0x36383F), hexP3(0x1B1C21), hexP3(0x2B2D33), hexP3(0x16171B)] as CFArray,
        locations: [0.0, 0.35, 0.72, 1.0]
    )!
    ctx.drawLinearGradient(
        titaniumGrad,
        start: CGPoint(x: outerRect.minX, y: outerRect.maxY),
        end: CGPoint(x: outerRect.maxX, y: outerRect.minY),
        options: []
    )
    ctx.restoreGState()

    // Outer titanium subtle highlight rim
    ctx.saveGState()
    ctx.setStrokeColor(p3Color(1, 1, 1, 0.18))
    ctx.setLineWidth(1.5)
    ctx.addPath(outerPath)
    ctx.strokePath()
    ctx.restoreGState()

    // Pure black glass bezel
    let bezelRect = outerRect.insetBy(dx: 7, dy: 7)
    let bezelPath = CGPath(roundedRect: bezelRect, cornerWidth: outerRadius - 7, cornerHeight: outerRadius - 7, transform: nil)
    ctx.saveGState()
    ctx.setFillColor(hexP3(0x050507))
    ctx.addPath(bezelPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle earpiece slit at top bezel
    let earRect = rectFromTop(642 - 58, 449, 116, 6, canvasH: H)
    let earPath = CGPath(roundedRect: earRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
    ctx.saveGState()
    ctx.setFillColor(hexP3(0x16171B))
    ctx.addPath(earPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Screen screenshot clipped to display corners
    let screenRect = rectFromTop(141, 468, 1002, 2178, canvasH: H)
    let screenRadius: CGFloat = 124
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil)
    let rawImage = loadCGImage(at: rawURL)

    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()
    ctx.draw(rawImage, in: screenRect)
    ctx.restoreGState()

    // Ultra-fine inner specular rim around screen glass
    ctx.saveGState()
    ctx.setStrokeColor(p3Color(1, 1, 1, 0.10))
    ctx.setLineWidth(1.5)
    ctx.addPath(screenPath)
    ctx.strokePath()
    ctx.restoreGState()

    // Dynamic Island capsule aligned with iPhone 17 Pro Max status bar (126x37pt @3x scaled to screen)
    let islandW: CGFloat = 287
    let islandH: CGFloat = 84
    let islandRect = rectFromTop((W - islandW) * 0.5, 468 + 72 - islandH * 0.5, islandW, islandH, canvasH: H)
    let islandPath = CGPath(roundedRect: islandRect, cornerWidth: islandH * 0.5, cornerHeight: islandH * 0.5, transform: nil)

    ctx.saveGState()
    ctx.setFillColor(hexP3(0x040406))
    ctx.addPath(islandPath)
    ctx.fillPath()
    ctx.setStrokeColor(p3Color(1, 1, 1, 0.08))
    ctx.setLineWidth(1.0)
    ctx.addPath(islandPath)
    ctx.strokePath()
    ctx.restoreGState()

    // Subtle front camera lens inside Dynamic Island
    let lensD: CGFloat = 26
    let lensCenterX = islandRect.midX + 84
    let lensCenterY = islandRect.midY
    let lensRect = CGRect(x: lensCenterX - lensD * 0.5, y: lensCenterY - lensD * 0.5, width: lensD, height: lensD)
    ctx.saveGState()
    ctx.addEllipse(in: lensRect)
    ctx.clip()
    let lensGrad = CGGradient(
        colorsSpace: p3,
        colors: [hexP3(0x202A46), hexP3(0x0A0E1B), hexP3(0x05060A)] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawRadialGradient(
        lensGrad,
        startCenter: CGPoint(x: lensCenterX - 4, y: lensCenterY + 4),
        startRadius: 1,
        endCenter: CGPoint(x: lensCenterX, y: lensCenterY),
        endRadius: lensD * 0.55,
        options: []
    )
    ctx.restoreGState()

    guard let outImage = ctx.makeImage() else { fatalError("Failed to create output image") }
    try savePNG(outImage, to: outURL)
}

func renderIPad(rawURL: URL, outURL: URL, headline: String) throws {
    let W: CGFloat = 2048
    let H: CGFloat = 2732
    let ctx = makeContext(width: Int(W), height: Int(H))

    drawStudioBackground(in: ctx, width: W, height: H)
    drawHeadline(headline, in: ctx, canvasWidth: W, canvasHeight: H, topY: 78, bottomY: 318, preferredSize: 96, maxLineWidth: W - 260)

    let outerRect = rectFromTop(142, 342, 1764, 2304, canvasH: H)
    let outerRadius: CGFloat = 96
    let outerPath = CGPath(roundedRect: outerRect, cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)

    // Subtle hardware buttons (top power button + upper right volume buttons)
    drawSideButton(in: ctx, rect: rectFromTop(1692, 336, 102, 8, canvasH: H), radius: 3, isLeft: false)
    drawSideButton(in: ctx, rect: rectFromTop(1904, 492, 8, 92, canvasH: H), radius: 3, isLeft: false)
    drawSideButton(in: ctx, rect: rectFromTop(1904, 602, 8, 92, canvasH: H), radius: 3, isLeft: false)

    // Multi-layer chassis shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 14, height: -34), blur: 96, color: p3Color(0.06, 0.07, 0.12, 0.22))
    ctx.setFillColor(hexP3(0x16171B))
    ctx.addPath(outerPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 6, height: -12), blur: 28, color: p3Color(0.04, 0.05, 0.10, 0.16))
    ctx.setFillColor(hexP3(0x16171B))
    ctx.addPath(outerPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Outer Space Black aluminum rim
    ctx.saveGState()
    ctx.addPath(outerPath)
    ctx.clip()
    let aluGrad = CGGradient(
        colorsSpace: p3,
        colors: [hexP3(0x2D2F35), hexP3(0x15161A), hexP3(0x24262B), hexP3(0x121317)] as CFArray,
        locations: [0.0, 0.35, 0.7, 1.0]
    )!
    ctx.drawLinearGradient(
        aluGrad,
        start: CGPoint(x: outerRect.minX, y: outerRect.maxY),
        end: CGPoint(x: outerRect.maxX, y: outerRect.minY),
        options: []
    )
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setStrokeColor(p3Color(1, 1, 1, 0.14))
    ctx.setLineWidth(1.5)
    ctx.addPath(outerPath)
    ctx.strokePath()
    ctx.restoreGState()

    // Black glass bezel
    let bezelRect = outerRect.insetBy(dx: 10, dy: 10)
    let bezelPath = CGPath(roundedRect: bezelRect, cornerWidth: outerRadius - 10, cornerHeight: outerRadius - 10, transform: nil)
    ctx.saveGState()
    ctx.setFillColor(hexP3(0x050507))
    ctx.addPath(bezelPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Front-facing landscape camera dot centered vertically on right black bezel
    let camD: CGFloat = 18
    let camCenterX: CGFloat = 1868
    let camCenterY: CGFloat = H - 1494
    let camRect = CGRect(x: camCenterX - camD * 0.5, y: camCenterY - camD * 0.5, width: camD, height: camD)
    ctx.saveGState()
    ctx.addEllipse(in: camRect)
    ctx.clip()
    let camGrad = CGGradient(
        colorsSpace: p3,
        colors: [hexP3(0x222D4A), hexP3(0x090D18), hexP3(0x040508)] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawRadialGradient(
        camGrad,
        startCenter: CGPoint(x: camCenterX - 3, y: camCenterY + 3),
        startRadius: 1,
        endCenter: CGPoint(x: camCenterX, y: camCenterY),
        endRadius: camD * 0.55,
        options: []
    )
    ctx.restoreGState()

    // Screen screenshot
    let screenRect = rectFromTop(214, 414, 1620, 2160, canvasH: H)
    let screenRadius: CGFloat = 34
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil)
    let rawImage = loadCGImage(at: rawURL)

    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()
    ctx.draw(rawImage, in: screenRect)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setStrokeColor(p3Color(0, 0, 0, 0.12))
    ctx.setLineWidth(1.0)
    ctx.addPath(screenPath)
    ctx.strokePath()
    ctx.restoreGState()

    guard let outImage = ctx.makeImage() else { fatalError("Failed to create iPad output image") }
    try savePNG(outImage, to: outURL)
}

for scene in scenes {
    let iPhoneRaw = rawDir.appendingPathComponent("\(scene.name)-iphone.png")
    let iPhoneOut = baseDir.appendingPathComponent("\(scene.name).png")
    if FileManager.default.fileExists(atPath: iPhoneRaw.path) {
        try renderIPhone(rawURL: iPhoneRaw, outURL: iPhoneOut, headline: scene.headline)
        print("Rendered \(iPhoneOut.lastPathComponent)")
    }

    let iPadRaw = rawDir.appendingPathComponent("\(scene.name)-ipad.png")
    let iPadOut = baseDir.appendingPathComponent("\(scene.name)iPad.png")
    if FileManager.default.fileExists(atPath: iPadRaw.path) {
        try renderIPad(rawURL: iPadRaw, outURL: iPadOut, headline: scene.headline)
        print("Rendered \(iPadOut.lastPathComponent)")
    }
}
