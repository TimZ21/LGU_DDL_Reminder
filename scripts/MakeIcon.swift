import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func draw(size: Int, path: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let plate = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 218, yRadius: 218)
    NSGradient(starting: NSColor(srgbRed: 0.56, green: 0.18, blue: 0.53, alpha: 1),
               ending: NSColor(srgbRed: 0.32, green: 0.06, blue: 0.31, alpha: 1))!.draw(in: plate, angle: -65)
    let page = NSBezierPath(roundedRect: NSRect(x: 220, y: 218, width: 584, height: 566), xRadius: 62, yRadius: 62)
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill(); page.fill()
    let purple = NSColor(srgbRed: 117 / 255, green: 15 / 255, blue: 109 / 255, alpha: 1)
    let gold = NSColor(srgbRed: 221 / 255, green: 163 / 255, blue: 0, alpha: 1)
    gold.setFill()
    NSBezierPath(rect: NSRect(x: 220, y: 640, width: 584, height: 14)).fill()
    for x in [340, 684] {
        let ring = NSBezierPath(roundedRect: NSRect(x: x - 18, y: 732, width: 36, height: 110), xRadius: 18, yRadius: 18)
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); ring.fill()
    }
    let check = NSBezierPath(); check.move(to: NSPoint(x: 339, y: 466)); check.line(to: NSPoint(x: 460, y: 349)); check.line(to: NSPoint(x: 678, y: 553))
    check.lineWidth = 54; check.lineCapStyle = .round; check.lineJoinStyle = .round; purple.setStroke(); check.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
for size in [16, 32, 128, 256, 512] {
    try draw(size: size, path: output + "/icon_\(size)x\(size).png")
    try draw(size: size * 2, path: output + "/icon_\(size)x\(size)@2x.png")
}
// ICNS is a container of big-endian length-prefixed PNG representations.
// Writing it directly avoids depending on iconutil's SDK-specific validation.
if CommandLine.arguments.count > 2 {
    func length(_ value: Int) -> Data {
        var number = UInt32(value).bigEndian
        return withUnsafeBytes(of: &number) { Data($0) }
    }
    let representations = [
        ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png")
    ]
    var contents = Data()
    for (type, filename) in representations {
        let png = try Data(contentsOf: URL(fileURLWithPath: output + "/" + filename))
        contents.append(Data(type.utf8)); contents.append(length(png.count + 8)); contents.append(png)
    }
    var icon = Data("icns".utf8); icon.append(length(contents.count + 8)); icon.append(contents)
    try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
