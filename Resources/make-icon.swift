import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("MacFan.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let n = CGFloat(size)
    let rect = NSRect(x: n * 0.07, y: n * 0.07, width: n * 0.86, height: n * 0.86)
    let path = NSBezierPath(roundedRect: rect, xRadius: n * 0.20, yRadius: n * 0.20)
    NSGradient(starting: NSColor(red: 0.08, green: 0.23, blue: 0.25, alpha: 1), ending: NSColor(red: 0.04, green: 0.07, blue: 0.10, alpha: 1))!.draw(in: path, angle: 270)
    if let symbol = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: n * 0.59, weight: .regular)) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor(red: 0.34, green: 0.88, blue: 0.76, alpha: 1).setFill()
        NSRect(origin: .zero, size: symbol.size).fill()
        symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: n * 0.23, y: n * 0.23, width: n * 0.54, height: n * 0.54))
    }
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    if [16, 32, 128, 256, 512].contains(size) { try data.write(to: root.appendingPathComponent("icon_\(size)x\(size).png")) }
    if [32, 64, 256, 512, 1024].contains(size) { try data.write(to: root.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png")) }
}
