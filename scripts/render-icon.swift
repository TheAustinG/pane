// Renders the layered tvOS app icon and Top Shelf images for Pane.
// Usage: swift scripts/render-icon.swift <brandassets-dir>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

let indigo = RGB(0x1E2148)
let violet = RGB(0x4A3F7A)
let rose = RGB(0xB9708A)
let apricot = RGB(0xEFA06A)
let slate = RGB(0x31507E)
let sunCore = RGB(0xFFE6AA)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ w: Int, _ h: Int, opaque: Bool) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: info)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func write(_ ctx: CGContext, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(url.path)") }
    print("\(url.path) \(ctx.width)x\(ctx.height)")
}

func field(_ ctx: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat, color: RGB, alpha: CGFloat) {
    let steps = 16
    var colors: [CGColor] = []
    var locs: [CGFloat] = []
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let s = 1 - t * t * (3 - 2 * t)
        colors.append(color.cg(alpha * s))
        locs.append(t)
    }
    let g = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locs)!
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: rx / ry, y: 1)
    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: ry, options: [])
    ctx.restoreGState()
}

func drawSky(_ ctx: CGContext, w: CGFloat, h: CGFloat) {
    let base = CGGradient(colorsSpace: srgb,
                          colors: [indigo.cg(), violet.cg(), rose.cg(), apricot.cg()] as CFArray,
                          locations: [0, 0.45, 0.78, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [.drawsAfterEndLocation])

    field(ctx, center: CGPoint(x: 0.88 * w, y: 0.22 * h), rx: 0.55 * w, ry: 0.55 * h, color: slate, alpha: 0.75)
    field(ctx, center: CGPoint(x: 0.08 * w, y: 0.02 * h), rx: 0.75 * w, ry: 0.75 * h, color: indigo, alpha: 0.95)
    field(ctx, center: CGPoint(x: 0.38 * w, y: 0.50 * h), rx: 0.50 * w, ry: 0.38 * h, color: violet, alpha: 0.55)
    field(ctx, center: CGPoint(x: 0.22 * w, y: 0.86 * h), rx: 0.50 * w, ry: 0.42 * h, color: rose, alpha: 0.65)
    field(ctx, center: CGPoint(x: 0.62 * w, y: 1.02 * h), rx: 0.62 * w, ry: 0.50 * h, color: apricot, alpha: 0.95)
    field(ctx, center: CGPoint(x: 0.66 * w, y: 0.84 * h), rx: 0.30 * w, ry: 0.28 * h, color: apricot, alpha: 0.45)
}

func drawSun(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, glow: CGFloat) {
    field(ctx, center: c, rx: glow * 1.25, ry: glow, color: apricot, alpha: 0.55)
    field(ctx, center: c, rx: glow * 0.55, ry: glow * 0.55, color: sunCore, alpha: 0.60)
    field(ctx, center: c, rx: r * 1.9, ry: r * 1.9, color: sunCore, alpha: 0.85)
    let disc = CGGradient(colorsSpace: srgb,
                          colors: [sunCore.cg(), sunCore.cg(), sunCore.cg(0)] as CFArray,
                          locations: [0, 0.86, 1])!
    ctx.drawRadialGradient(disc, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}

func drawCloud(_ ctx: CGContext, center: CGPoint, length: CGFloat, thickness: CGFloat, alpha: CGFloat) {
    let white = RGB(0xFFF4EC)
    field(ctx, center: center, rx: length, ry: thickness, color: white, alpha: alpha)
    field(ctx, center: CGPoint(x: center.x + length * 0.28, y: center.y - thickness * 0.35),
          rx: length * 0.55, ry: thickness * 0.8, color: white, alpha: alpha * 0.7)
}

struct WindowGeometry {
    let outer: CGRect
    let bar: CGFloat
    let radius: CGFloat
    init(w: CGFloat, h: CGFloat) {
        let ww = 0.48 * w, wh = 0.68 * h
        outer = CGRect(x: (w - ww) / 2, y: (h - wh) / 2, width: ww, height: wh)
        bar = 0.075 * h
        radius = 0.085 * h
    }
    var lowerRightPaneCenter: CGPoint {
        CGPoint(x: outer.midX + outer.width / 4 - bar / 4, y: outer.midY + outer.height / 4 - bar / 4)
    }
    var path: CGPath {
        let p = CGMutablePath()
        p.addRoundedRect(in: outer, cornerWidth: radius, cornerHeight: radius)
        let pw = (outer.width - 3 * bar) / 2
        let ph = (outer.height - 3 * bar) / 2
        let inner = 0.022 * outer.height
        for (i, j) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let r = CGRect(x: outer.minX + bar + CGFloat(i) * (pw + bar),
                           y: outer.minY + bar + CGFloat(j) * (ph + bar), width: pw, height: ph)
            p.addRoundedRect(in: r, cornerWidth: inner, cornerHeight: inner)
        }
        return p
    }
}

func drawWindow(_ ctx: CGContext, w: CGFloat, h: CGFloat) {
    let geo = WindowGeometry(w: w, h: h)
    let path = geo.path

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -0.03 * h), blur: 0.07 * h,
                  color: CGColor(srgbRed: 0.06, green: 0.05, blue: 0.16, alpha: 0.55))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 0.88, alpha: 1))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip(using: .evenOdd)
    let frost = CGGradient(colorsSpace: srgb,
                           colors: [CGColor(gray: 0.97, alpha: 1), CGColor(gray: 0.89, alpha: 1),
                                    CGColor(gray: 0.84, alpha: 1)] as CFArray,
                           locations: [0, 0.35, 1])!
    ctx.drawLinearGradient(frost, start: CGPoint(x: 0, y: geo.outer.minY),
                           end: CGPoint(x: 0, y: geo.outer.maxY), options: [])
    let edge = CGMutablePath()
    edge.addRoundedRect(in: geo.outer.insetBy(dx: 0.006 * h, dy: 0.006 * h),
                        cornerWidth: geo.radius, cornerHeight: geo.radius)
    ctx.addPath(edge)
    ctx.setLineWidth(0.012 * h)
    let highlight = CGGradient(colorsSpace: srgb,
                               colors: [CGColor(gray: 1, alpha: 0.95), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(highlight, start: CGPoint(x: 0, y: geo.outer.minY),
                           end: CGPoint(x: 0, y: geo.outer.minY + 0.18 * h), options: [])
    ctx.restoreGState()
}

func iconSet(w: Int, h: Int, dir: URL, suffix: String) {
    let W = CGFloat(w), H = CGFloat(h)
    let geo = WindowGeometry(w: W, h: H)

    let back = makeContext(w, h, opaque: true)
    drawSky(back, w: W, h: H)
    write(back, to: dir.appendingPathComponent("Back.imagestacklayer/Content.imageset/back-\(suffix).png"))

    let middle = makeContext(w, h, opaque: false)
    drawCloud(middle, center: CGPoint(x: 0.42 * W, y: 0.36 * H), length: 0.26 * W, thickness: 0.06 * H, alpha: 0.20)
    drawSun(middle, at: geo.lowerRightPaneCenter, radius: 0.062 * H, glow: 0.40 * H)
    write(middle, to: dir.appendingPathComponent("Middle.imagestacklayer/Content.imageset/middle-\(suffix).png"))

    let front = makeContext(w, h, opaque: false)
    drawWindow(front, w: W, h: H)
    write(front, to: dir.appendingPathComponent("Front.imagestacklayer/Content.imageset/front-\(suffix).png"))
}

func topShelf(w: Int, h: Int, url: URL) {
    let W = CGFloat(w), H = CGFloat(h)
    let ctx = makeContext(w, h, opaque: true)
    drawSky(ctx, w: W, h: H)
    drawCloud(ctx, center: CGPoint(x: 0.40 * W, y: 0.46 * H), length: 0.24 * W, thickness: 0.06 * H, alpha: 0.16)
    drawSun(ctx, at: CGPoint(x: 0.64 * W, y: 0.80 * H), radius: 0.07 * H, glow: 0.48 * H)
    write(ctx, to: url)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift scripts/render-icon.swift <brandassets-dir>\n".data(using: .utf8)!)
    exit(64)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let small = root.appendingPathComponent("App Icon - Small.imagestack")
let large = root.appendingPathComponent("App Icon - Large.imagestack")

iconSet(w: 400, h: 240, dir: small, suffix: "1x")
iconSet(w: 800, h: 480, dir: small, suffix: "2x")
iconSet(w: 1280, h: 768, dir: large, suffix: "1x")
topShelf(w: 1920, h: 720, url: root.appendingPathComponent("Top Shelf Image.imageset/top-shelf-image-1x.png"))
topShelf(w: 3840, h: 1440, url: root.appendingPathComponent("Top Shelf Image.imageset/top-shelf-image-2x.png"))
topShelf(w: 2320, h: 720, url: root.appendingPathComponent("Top Shelf Image Wide.imageset/top-shelf-image-wide-1x.png"))
topShelf(w: 4640, h: 1440, url: root.appendingPathComponent("Top Shelf Image Wide.imageset/top-shelf-image-wide-2x.png"))
