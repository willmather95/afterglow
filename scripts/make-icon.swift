import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Afterglow.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let gc = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Cannot create icon canvas") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
        gc.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let dark = NSColor(red: 0.145, green: 0.137, blue: 0.125, alpha: 1)
        dark.setFill()
        NSBezierPath(roundedRect: CGRect(x: 42, y: 42, width: 940, height: 940), xRadius: 210, yRadius: 210).fill()
        for index in 0..<7 {
            let radius = CGFloat(260 + index * 21)
            NSColor(red: 0.88, green: 0.61, blue: 0.33, alpha: 0.09).setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: 512 - radius, y: 520 - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = 3; ring.stroke()
        }
        let sun = NSBezierPath(ovalIn: CGRect(x: 274, y: 282, width: 476, height: 476))
        NSGradient(starting: NSColor(red: 0.84, green: 0.29, blue: 0.12, alpha: 1),
                   ending: NSColor(red: 1, green: 0.70, blue: 0.29, alpha: 1))!.draw(in: sun, angle: 90)
        dark.setFill()
        for stripe in 0..<9 {
            let y = CGFloat(490 - stripe * 25)
            NSBezierPath(rect: CGRect(x: 250, y: y, width: 524, height: CGFloat(7 + stripe * 2))).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
print(iconset.path)
