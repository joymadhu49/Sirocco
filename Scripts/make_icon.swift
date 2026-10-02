// Renders Resources/AppIcon.icns: the menu bar fan on a dark squircle with a cool glow.
// Run from the project root: swift Scripts/make_icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size / 1024
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let squircle = NSBezierPath(roundedRect: bounds.insetBy(dx: 100 * s, dy: 100 * s), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(calibratedRed: 0.11, green: 0.115, blue: 0.135, alpha: 1),
               ending: NSColor(calibratedRed: 0.035, green: 0.037, blue: 0.05, alpha: 1))!.draw(in: squircle, angle: -90)

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.setClip()
    let center = NSPoint(x: size / 2, y: size / 2)
    NSGradient(colors: [NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 0.30),
                        NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: 360 * s, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()

    let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 104 * s, dy: 104 * s), xRadius: 181 * s, yRadius: 181 * s)
    edge.lineWidth = 6 * s
    NSColor.white.withAlphaComponent(0.10).setStroke()
    edge.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: 430 * s, weight: .medium)
        .applying(.init(paletteColors: [NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.98, alpha: 1)]))
    if let fan = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let r = NSRect(x: (size - fan.size.width) / 2, y: (size - fan.size.height) / 2,
                       width: fan.size.width, height: fan.size.height)
        fan.draw(in: r)
    }
    image.unlockFocus()
    return image
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let rep = NSBitmapImageRep(data: drawIcon(size: px).tiffRepresentation!)!
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
