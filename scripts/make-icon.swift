// Renders Resources/AppIcon.icns: dark rounded square with a stack of three clip cards fanned upward,
// the front card lit with an accent edge and two text lines.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    let s = size / 1024
    let small = size <= 32

    let inset = 100 * s
    let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = 185 * s
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    if !small {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        color(0.08, 0.09, 0.11).setFill(); bodyPath.fill()
        ctx.restoreGState()
    }
    NSGradient(colors: [color(0.17, 0.18, 0.21), color(0.07, 0.075, 0.09)])!.draw(in: bodyPath, angle: -90)
    if !small {
        let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5 * s, dy: 1.5 * s), xRadius: radius - 1.5 * s, yRadius: radius - 1.5 * s)
        rim.lineWidth = 3 * s; color(1, 1, 1, 0.09).setStroke(); rim.stroke()
    }

    // Card stack: back cards narrower and higher, front card full width.
    let cw = 520 * s, ch = 300 * s, cr = 56 * s
    let cx = size / 2
    let frontY = 300 * s
    let cards: [(CGFloat, CGFloat, CGFloat)] = [(0.72, 150, 0.16), (0.86, 75, 0.28), (1.0, 0, 1.0)]   // width scale, y offset, opacity
    for (i, (ws, dy, op)) in cards.enumerated() {
        let w = cw * ws
        let r = NSRect(x: cx - w / 2, y: frontY + dy * s, width: w, height: ch)
        let p = NSBezierPath(roundedRect: r, xRadius: cr, yRadius: cr)
        if i == 2 {
            if !small {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 40 * s, color: color(0, 0, 0, 0.55).cgColor)
                color(0.2, 0.21, 0.25).setFill(); p.fill()
                ctx.restoreGState()
            }
            NSGradient(colors: [color(0.27, 0.29, 0.34), color(0.19, 0.2, 0.24)])!.draw(in: p, angle: -90)
            // Accent bar on the left edge.
            ctx.saveGState(); p.addClip()
            let bar = NSRect(x: r.minX, y: r.minY, width: 34 * s, height: r.height)
            NSGradient(colors: [color(0.47, 0.70, 1.0), color(0.38, 0.45, 1.0)])!.draw(in: bar, angle: -90)
            ctx.restoreGState()
            // Text lines.
            let lx = r.minX + 92 * s
            let l1 = NSBezierPath(roundedRect: NSRect(x: lx, y: r.midY + 22 * s, width: 300 * s, height: 40 * s), xRadius: 20 * s, yRadius: 20 * s)
            color(0.92, 0.94, 1.0, 0.92).setFill(); l1.fill()
            let l2 = NSBezierPath(roundedRect: NSRect(x: lx, y: r.midY - 62 * s, width: 200 * s, height: 40 * s), xRadius: 20 * s, yRadius: 20 * s)
            color(0.92, 0.94, 1.0, 0.40).setFill(); l2.fill()
            if !small {
                let rim = NSBezierPath(roundedRect: r.insetBy(dx: 1.5 * s, dy: 1.5 * s), xRadius: cr, yRadius: cr)
                rim.lineWidth = 3 * s; color(1, 1, 1, 0.12).setStroke(); rim.stroke()
            }
        } else {
            color(0.55, 0.62, 0.85, op).setFill(); p.fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Kopi.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: root + "/Resources/icon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root + "/Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print("wrote Resources/AppIcon.icns")
