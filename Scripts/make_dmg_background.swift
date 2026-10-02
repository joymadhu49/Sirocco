// Renders the installer window's background: a soft sky that is cool weather on the Sirocco
// side (pale blue, a cloud, a few snowflakes) and hot weather on the Applications side (warm
// peach under a hazy sun), with a breeze and an arrow from one to the other, so the drag reads
// as "bring the cool to the heat". Run from the project root through
// Scripts/make-dmg-background.sh.
//
// The layout matches Scripts/make-dmg.sh: a 560x440 pt window, Sirocco at (150, 190) and the
// Applications link at (410, 190), 112 pt icons. The window's title bar, and the path bar if
// the user has it on, cover the bottom 30 to 60 pt, so nothing that matters is drawn there.
//
// Finder draws icon labels in black over a background picture, so the artwork stays light.
import AppKit

let width: CGFloat = 560
let height: CGFloat = 440
let app = CGPoint(x: 150, y: 190)
let folder = CGPoint(x: 410, y: 190)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

func glow(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, _ inner: CGColor) {
    ctx.drawRadialGradient(gradient([(0, inner), (1, inner.copy(alpha: 0)!)]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// A stroke that fades in and out along its length, drawn as short segments.
func streak(_ ctx: CGContext, width lineWidth: CGFloat, alpha: CGFloat, steps: Int = 80,
            point: (CGFloat) -> CGPoint) {
    // Butt caps: round ones would overlap at every joint and bead the translucent line.
    ctx.setLineCap(.butt)
    ctx.setLineWidth(lineWidth)
    for i in 0..<steps {
        let t0 = CGFloat(i) / CGFloat(steps)
        let t1 = CGFloat(i + 1) / CGFloat(steps)
        ctx.setStrokeColor(color(1, 1, 1, alpha * sin(.pi * (t0 + t1) / 2)))
        ctx.move(to: point(t0))
        ctx.addLine(to: point(t1))
        ctx.strokePath()
    }
}

func draw(_ ctx: CGContext) {
    // Cool sky on the left, warm sky on the right, meeting in a near white haze.
    ctx.drawLinearGradient(gradient([(0, color(0.78, 0.89, 0.99)),
                                     (0.30, color(0.86, 0.93, 0.99)),
                                     (0.50, color(0.97, 0.96, 0.96)),
                                     (0.70, color(1.0, 0.91, 0.84)),
                                     (1, color(1.0, 0.82, 0.71))]),
                           start: .zero, end: CGPoint(x: width, y: 0), options: [])
    // Lighter toward the bottom, like a sky near the horizon.
    ctx.drawLinearGradient(gradient([(0, color(1, 1, 1, 0)), (1, color(1, 1, 1, 0.38))]),
                           start: CGPoint(x: 0, y: 150), end: CGPoint(x: 0, y: height), options: [])

    // Cool side: a deeper blue aloft and a cloud drifting in.
    glow(ctx, at: CGPoint(x: 30, y: 10), radius: 260, color(0.60, 0.80, 0.99, 0.55))
    for (x, y, r) in [(58, 78, 30), (92, 64, 38), (132, 76, 30), (164, 84, 22), (30, 86, 20)] as [(CGFloat, CGFloat, CGFloat)] {
        glow(ctx, at: CGPoint(x: x, y: y), radius: r * 1.5, color(1, 1, 1, 0.75))
    }
    // A few snowflakes, small and out of the way of the icon and its label.
    for (x, y, r, a) in [(36, 150, 2.2, 0.9), (70, 214, 1.6, 0.8), (44, 286, 2.4, 0.9), (98, 330, 1.6, 0.7),
                         (232, 132, 1.8, 0.8), (252, 300, 2.0, 0.8), (190, 22, 1.5, 0.7), (150, 352, 2.0, 0.8),
                         (20, 368, 1.6, 0.7), (228, 372, 1.5, 0.6)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        glow(ctx, at: CGPoint(x: x, y: y), radius: r * 2.2, color(1, 1, 1, a))
    }

    // Hot side: a hazy sun and the warmth it throws.
    let sun = CGPoint(x: 492, y: 66)
    glow(ctx, at: sun, radius: 250, color(1.0, 0.70, 0.45, 0.42))
    glow(ctx, at: sun, radius: 120, color(1.0, 0.84, 0.55, 0.55))
    ctx.setFillColor(color(1.0, 0.93, 0.74, 0.95))
    ctx.fillEllipse(in: CGRect(x: sun.x - 30, y: sun.y - 30, width: 60, height: 60))

    // The breeze from Sirocco toward the heat.
    let from = app.x + 74
    let to = folder.x - 72
    for (offset, alpha) in [(-16, 0.9), (0, 1.0), (16, 0.9)] as [(CGFloat, CGFloat)] {
        streak(ctx, width: 2, alpha: alpha) { t in
            CGPoint(x: from + t * (to - from), y: app.y + offset + 4 * sin(t * 2 * .pi + offset / 8))
        }
    }
    let tip = CGPoint(x: (from + to) / 2 + 9, y: app.y)
    ctx.setStrokeColor(color(0.36, 0.42, 0.52, 0.55))
    ctx.setLineWidth(2.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: tip.x - 9, y: tip.y - 9))
    ctx.addLine(to: tip)
    ctx.addLine(to: CGPoint(x: tip.x - 9, y: tip.y + 9))
    ctx.strokePath()

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, tracking: CGFloat = 0,
              centerX: CGFloat, y: CGFloat) {
        let attributed = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(srgbRed: 0.16, green: 0.19, blue: 0.25, alpha: alpha),
            .kern: tracking
        ])
        let textSize = attributed.size()
        attributed.draw(at: CGPoint(x: centerX - textSize.width / 2, y: y))
    }
    // What it is, above the icons; what to do, below them.
    text("Sirocco", size: 30, weight: .bold, alpha: 0.94, tracking: -0.6, centerX: width / 2, y: 40)
    text("A cool breeze for a hot Mac", size: 13.5, weight: .medium, alpha: 0.66, centerX: width / 2, y: 79)
    text("Drag Sirocco to Applications", size: 15, weight: .semibold, alpha: 0.92, centerX: width / 2, y: 298)
    text("Then open it and click Turn On. Your fans do the rest.", size: 12, weight: .regular, alpha: 0.62,
         centerX: width / 2, y: 321)
}

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    let base = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    // Top left origin, the way Finder positions the icons. The context is already in points.
    base.translateBy(x: 0, y: height)
    base.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: base, flipped: true)
    draw(base)
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

try! FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
try! render(scale: 1).write(to: URL(fileURLWithPath: "build/dmg-background.png"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "build/dmg-background@2x.png"))
