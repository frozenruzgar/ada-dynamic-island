import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels)
        NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92),
                     xRadius: s * 0.22, yRadius: s * 0.22).fill()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.15, y: s * 0.33, width: s * 0.70, height: s * 0.34),
                     xRadius: s * 0.17, yRadius: s * 0.17).fill()
        NSColor(calibratedRed: 0.62, green: 0.96, blue: 0.79, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: s * 0.25, y: s * 0.445, width: s * 0.11, height: s * 0.11)).fill()
        let ring = NSBezierPath(ovalIn: NSRect(x: s * 0.60, y: s * 0.42, width: s * 0.16, height: s * 0.16))
        NSColor(calibratedRed: 0.62, green: 0.96, blue: 0.79, alpha: 1).setStroke()
        ring.lineWidth = max(1, s * 0.018)
        ring.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to:
            URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
