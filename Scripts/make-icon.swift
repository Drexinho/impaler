// Vygeneruje AppIcon.icns: `swift Scripts/make-icon.swift`
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // Mřížka ikon macOS: dlaždice 824 pt na plátně 1024 pt, zaoblení 185 pt.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 20 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(srgbRed: 1.00, green: 0.42, blue: 0.36, alpha: 1),
               ending: NSColor(srgbRed: 0.84, green: 0.13, blue: 0.20, alpha: 1))!.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: 440 * s, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    glyphShadow.shadowBlurRadius = 16 * s
    glyphShadow.set()
    pin.draw(in: NSRect(x: tile.midX - pin.size.width / 2, y: tile.midY - pin.size.height / 2,
                        width: pin.size.width, height: pin.size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: dir)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: dir.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: dir.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", dir.path, "-o", "AppIcon.icns"]
try tool.run()
tool.waitUntilExit()
exit(tool.terminationStatus)
