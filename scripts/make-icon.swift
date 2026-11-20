// Renders the MacMXSwitch app icon with CoreGraphics: a monitor showing swap arrows,
// with the keyboard and mouse in front of it, on a dark graphite tile.
// Usage: swift scripts/make-icon.swift <output.png>
// scripts/make-icns.sh builds Resources/AppIcon.icns from it.
import AppKit

let size: CGFloat = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
        ])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Fills `path` with a vertical gradient from `top` to `bottom`.
func fillVertical(_ ctx: CGContext, _ path: CGPath, top: UInt32, bottom: UInt32) {
    let box = path.boundingBox
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(top), color(bottom)], [0, 1]),
        start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY), options: [])
    ctx.restoreGState()
}

let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// MARK: Tile (macOS icon grid: an 824 pt body centered in the 1024 canvas)

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rounded(body, 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x15161B))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawRadialGradient(
    gradient([color(0x343846), color(0x1C1E25), color(0x101116)], [0, 0.6, 1]),
    startCenter: CGPoint(x: 512, y: 640), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 640), endRadius: 620, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// MARK: Monitor

let screen = CGRect(x: 236, y: 452, width: 552, height: 336)
let bezel = screen.insetBy(dx: -16, dy: -16)

// Stand.
fillVertical(ctx, rounded(CGRect(x: 482, y: 382, width: 60, height: 60), 8), top: 0x8E93A0, bottom: 0x5D616C)
fillVertical(ctx, rounded(CGRect(x: 392, y: 364, width: 240, height: 28), 14), top: 0xC9CDD6, bottom: 0x8E93A0)

// Bezel with a colored glow from the screen.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.setShadow(offset: .zero, blur: 90, color: color(0x2F7BFF, 0.55))
ctx.addPath(rounded(bezel, 34))
ctx.setFillColor(color(0x0B0C10))
ctx.fillPath()
ctx.restoreGState()

// Screen: blue to aqua.
ctx.saveGState()
ctx.addPath(rounded(screen, 20))
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0x3B5BFF), color(0x2F8BFF), color(0x18D8C4)], [0, 0.5, 1]),
    start: CGPoint(x: screen.minX, y: screen.maxY), end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
// Soft highlight across the top.
ctx.drawLinearGradient(
    gradient([color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)], [0, 1]),
    start: CGPoint(x: 0, y: screen.maxY), end: CGPoint(x: 0, y: screen.midY), options: [])
ctx.restoreGState()

// Swap arrows: top one points right, bottom one points left.
func arrow(_ ctx: CGContext, y: CGFloat, from x0: CGFloat, to x1: CGFloat) {
    let dir: CGFloat = x1 > x0 ? 1 : -1
    let head: CGFloat = 64
    let shaftEnd = x1 - dir * head * 0.6
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(38)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: x0, y: y))
    ctx.addLine(to: CGPoint(x: shaftEnd, y: y))
    ctx.strokePath()
    let tip = CGPoint(x: x1, y: y)
    let tri = CGMutablePath()
    tri.move(to: tip)
    tri.addLine(to: CGPoint(x: x1 - dir * head * 1.15, y: y + head))
    tri.addLine(to: CGPoint(x: x1 - dir * head * 1.15, y: y - head))
    tri.closeSubpath()
    // Rounded corners on the head.
    ctx.addPath(tri)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(18)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.drawPath(using: .fillStroke)
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: color(0x0A1A60, 0.35))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)  // one shadow for the whole arrow pair
arrow(ctx, y: screen.midY + 62, from: screen.minX + 120, to: screen.maxX - 104)
arrow(ctx, y: screen.midY - 62, from: screen.maxX - 120, to: screen.minX + 104)
ctx.endTransparencyLayer()
ctx.restoreGState()

// MARK: Keyboard and mouse

let keyboard = CGRect(x: 196, y: 176, width: 470, height: 140)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x000000, 0.5))
ctx.addPath(rounded(keyboard, 26))
ctx.setFillColor(color(0xB8BCC6))
ctx.fillPath()
ctx.restoreGState()
fillVertical(ctx, rounded(keyboard, 26), top: 0xD8DBE2, bottom: 0xA4A9B4)

// Keys: three rows, with a wide space bar in the bottom row.
let keyArea = keyboard.insetBy(dx: 22, dy: 18)
let gap: CGFloat = 8
let rows = 3
let cols = 10
let keyH = (keyArea.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
let keyW = (keyArea.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
ctx.setFillColor(color(0x2A2D35))
for r in 0..<rows {
    let y = keyArea.maxY - CGFloat(r + 1) * keyH - CGFloat(r) * gap
    if r == rows - 1 {
        // Two keys, space bar, two keys.
        let spans: [(Int, Int)] = [(0, 2), (2, 8), (8, 10)]
        for (i, (a, b)) in spans.enumerated() {
            if i == 1 {
                let x = keyArea.minX + CGFloat(a) * (keyW + gap)
                let w = CGFloat(b - a) * keyW + CGFloat(b - a - 1) * gap
                ctx.addPath(rounded(CGRect(x: x, y: y, width: w, height: keyH), 7))
            } else {
                for c in a..<b {
                    let x = keyArea.minX + CGFloat(c) * (keyW + gap)
                    ctx.addPath(rounded(CGRect(x: x, y: y, width: keyW, height: keyH), 7))
                }
            }
        }
    } else {
        for c in 0..<cols {
            let x = keyArea.minX + CGFloat(c) * (keyW + gap)
            ctx.addPath(rounded(CGRect(x: x, y: y, width: keyW, height: keyH), 7))
        }
    }
}
ctx.fillPath()

let mouse = CGRect(x: 704, y: 166, width: 118, height: 170)
let mousePath = rounded(mouse, 56)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x000000, 0.5))
ctx.addPath(mousePath)
ctx.setFillColor(color(0xB8BCC6))
ctx.fillPath()
ctx.restoreGState()
fillVertical(ctx, mousePath, top: 0xD8DBE2, bottom: 0xA4A9B4)
// Button split and scroll wheel.
ctx.saveGState()
ctx.addPath(mousePath)
ctx.clip()
ctx.setStrokeColor(color(0x6E7380))
ctx.setLineWidth(4)
ctx.move(to: CGPoint(x: mouse.midX, y: mouse.maxY))
ctx.addLine(to: CGPoint(x: mouse.midX, y: mouse.maxY - 62))
ctx.strokePath()
ctx.addPath(rounded(CGRect(x: mouse.midX - 9, y: mouse.maxY - 58, width: 18, height: 34), 9))
ctx.setFillColor(color(0x2A2D35))
ctx.fillPath()
ctx.restoreGState()

// Faint rim on the tile.
ctx.addPath(rounded(body.insetBy(dx: 1.5, dy: 1.5), 184))
ctx.setStrokeColor(color(0xFFFFFF, 0.08))
ctx.setLineWidth(3)
ctx.strokePath()

// MARK: Output

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
