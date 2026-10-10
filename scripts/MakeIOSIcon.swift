import AppKit

// The original Shiqi calendar mark; no university insignia or external assets.
let output = CommandLine.arguments[1]
// Core Graphics requires a supported 32-bit RGB layout for drawing. A packed
// 24-bit NSBitmapImageRep can produce an empty image instead of a drawing context.
let drawing = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 4096, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: drawing, flipped: false)
NSGradient(starting: NSColor(srgbRed: 0.56, green: 0.18, blue: 0.53, alpha: 1),
           ending: NSColor(srgbRed: 0.32, green: 0.06, blue: 0.31, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -65)
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 220, y: 218, width: 584, height: 566), xRadius: 62, yRadius: 62).fill()
NSColor(srgbRed: 221 / 255, green: 163 / 255, blue: 0, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 220, y: 640, width: 584, height: 14)).fill()
for x in [340, 684] {
    NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 18, y: 732, width: 36, height: 110), xRadius: 18, yRadius: 18).fill()
}
let check = NSBezierPath()
check.move(to: NSPoint(x: 339, y: 466)); check.line(to: NSPoint(x: 460, y: 349)); check.line(to: NSPoint(x: 678, y: 553))
check.lineWidth = 54; check.lineCapStyle = .round; check.lineJoinStyle = .round
NSColor(srgbRed: 117 / 255, green: 15 / 255, blue: 109 / 255, alpha: 1).setStroke(); check.stroke()
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: drawing.makeImage()!)
try FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
