// Render the existing move.3d identity with native AppKit; build tool only.
import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let tile = NSBezierPath(roundedRect: NSRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84), xRadius: size * 0.19, yRadius: size * 0.19)
    NSGradient(starting: NSColor(calibratedRed: 0.14, green: 0.65, blue: 0.85, alpha: 1), ending: NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.78, alpha: 1))!.draw(in: tile, angle: -70)
    let symbol = NSImage(systemSymbolName: "move.3d", accessibilityDescription: "Axial")!.withSymbolConfiguration(.init(pointSize: size * 0.52, weight: .semibold))!
    let whiteSymbol = symbol.withSymbolConfiguration(.init(paletteColors: [.white]))!
    let bounds = whiteSymbol.size
    let scale = min(size * 0.57 / bounds.width, size * 0.57 / bounds.height)
    whiteSymbol.draw(in: NSRect(x: (size - bounds.width * scale) / 2, y: (size - bounds.height * scale) / 2, width: bounds.width * scale, height: bounds.height * scale))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}
