import AppKit

// Fork: a site's icon that drew as nothing — chatgpt.com's dark one came out
// fully transparent — was kept as if it were the icon, for a week, and the
// tab showed an empty square. An icon has to have something in it.

extension NSImage {
    /// Some pixel is visible. Checked on a small copy: a favicon is a mark,
    /// and 16 points of it say as much as 64.
    var hasInk: Bool {
        let side = 16
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4, bitsPerPixel: 32
        ) else { return true }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = rep.bitmapData else { return true }
        for i in stride(from: 3, to: side * side * 4, by: 4) where bytes[i] > 24 { return true }
        return false
    }
}
