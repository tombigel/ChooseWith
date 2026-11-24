// Draws the app icon and writes Resources/AppIcon.icns.
// Run: swift tools/make_icon.swift   (from the repo root)

import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    // Squircle body on the standard macOS icon grid (824pt body inside 1024 canvas).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bodyPath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.36, green: 0.55, blue: 1.00, alpha: 1).cgColor,
        NSColor(srgbRed: 0.33, green: 0.22, blue: 0.86, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft top sheen.
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    ctx.fillEllipse(in: CGRect(x: -100, y: 560, width: 1224, height: 700))
    ctx.restoreGState()

    // Popup menu card.
    let card = CGRect(x: 230, y: 250, width: 520, height: 520)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 56, cornerHeight: 56, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(cardPath); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()

    // Three app rows; the middle one highlighted like a selected menu item.
    let dots: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: 1),
        NSColor.white,
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.47, alpha: 1),
    ]
    let rowH: CGFloat = 132
    let firstRowY = card.maxY - 60 - rowH
    for i in 0..<3 {
        let y = firstRowY - CGFloat(i) * (rowH + 8)
        let row = CGRect(x: card.minX + 30, y: y, width: card.width - 60, height: rowH)
        if i == 1 {
            ctx.addPath(CGPath(roundedRect: row, cornerWidth: 30, cornerHeight: 30, transform: nil))
            ctx.setFillColor(NSColor(srgbRed: 0.30, green: 0.45, blue: 1.0, alpha: 1).cgColor)
            ctx.fillPath()
        }
        // App "icon" tile.
        let tile = CGRect(x: row.minX + 28, y: row.midY - 38, width: 76, height: 76)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 20, cornerHeight: 20, transform: nil))
        ctx.setFillColor(dots[i].cgColor); ctx.fillPath()
        // App name bar.
        let bar = CGRect(x: tile.maxX + 32, y: row.midY - 17, width: i == 1 ? 250 : (i == 0 ? 220 : 180), height: 34)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 17, cornerHeight: 17, transform: nil))
        ctx.setFillColor(i == 1 ? NSColor.white.withAlphaComponent(0.9).cgColor
                                : NSColor(srgbRed: 0.80, green: 0.82, blue: 0.88, alpha: 1).cgColor)
        ctx.fillPath()
    }

    // Mouse pointer over the highlighted row.
    let p = CGMutablePath()
    let tip = CGPoint(x: 640, y: 470)
    p.move(to: tip)
    p.addLine(to: CGPoint(x: tip.x, y: tip.y - 250))
    p.addLine(to: CGPoint(x: tip.x + 58, y: tip.y - 192))
    p.addLine(to: CGPoint(x: tip.x + 100, y: tip.y - 285))
    p.addLine(to: CGPoint(x: tip.x + 140, y: tip.y - 267))
    p.addLine(to: CGPoint(x: tip.x + 98, y: tip.y - 176))
    p.addLine(to: CGPoint(x: tip.x + 180, y: tip.y - 176))
    p.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    ctx.addPath(p); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(p); ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(22); ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.addPath(p); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()

    img.unlockFocus()
    return img
}

func writePNG(_ img: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try! fm.createDirectory(at: URL(fileURLWithPath: "Resources"), withIntermediateDirectories: true)

let master = drawIcon(size: 1024)
for base in [16, 32, 128, 256, 512] {
    writePNG(master, pixels: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(master, pixels: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
writePNG(master, pixels: 1024, to: URL(fileURLWithPath: "build/AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
