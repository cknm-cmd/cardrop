// Regenerates assets/AppIcon.icns. Run from the repo root:
//   swift tools/make-icon.swift && iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns && rm -r assets/AppIcon.iconset
import AppKit

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let tile = rect.insetBy(dx: size * 0.1, dy: size * 0.1)
    let path = NSBezierPath(roundedRect: tile, xRadius: size * 0.2, yRadius: size * 0.2)
    NSGradient(starting: NSColor(red: 0.20, green: 0.55, blue: 1.00, alpha: 1),
               ending: NSColor(red: 0.35, green: 0.25, blue: 0.95, alpha: 1))!.draw(in: path, angle: -90)

    let white = NSImage.SymbolConfiguration(paletteColors: [.white])
    func symbol(_ name: String, _ points: CGFloat, center: CGPoint) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: points, weight: .semibold).applying(white))
        else { return }
        let s = image.size
        image.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
    }
    symbol("sdcard.fill", size * 0.30, center: CGPoint(x: rect.midX, y: rect.midY - size * 0.08))
    symbol("arrow.up", size * 0.16, center: CGPoint(x: rect.midX, y: rect.midY + size * 0.22))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "assets/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
