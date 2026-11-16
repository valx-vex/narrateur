import AppKit
let output = CommandLine.arguments.dropFirst().first ?? "assets/AppIcon.png"
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(red: r/255, green: g/255, blue: b/255, alpha: 1) }
let plate = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 190, yRadius: 190)
NSGradient(starting: color(12, 13, 18), ending: color(31, 35, 48))!.draw(in: plate, angle: 90)
color(68, 77, 94).setStroke(); plate.lineWidth = 2; plate.stroke()
let inset = NSBezierPath(roundedRect: NSRect(x: 103, y: 103, width: 818, height: 818), xRadius: 154, yRadius: 154)
NSColor.white.withAlphaComponent(0.05).setStroke(); inset.lineWidth = 2; inset.stroke()
// Open pages: restrained silver; the voice is the cyan signal through their center.
let book = NSBezierPath()
book.move(to: NSPoint(x: 220, y: 325)); book.line(to: NSPoint(x: 220, y: 692))
book.curve(to: NSPoint(x: 512, y: 648), controlPoint1: NSPoint(x: 332, y: 715), controlPoint2: NSPoint(x: 449, y: 676))
book.curve(to: NSPoint(x: 804, y: 692), controlPoint1: NSPoint(x: 575, y: 676), controlPoint2: NSPoint(x: 692, y: 715))
book.line(to: NSPoint(x: 804, y: 325))
book.curve(to: NSPoint(x: 512, y: 290), controlPoint1: NSPoint(x: 692, y: 348), controlPoint2: NSPoint(x: 575, y: 318))
book.curve(to: NSPoint(x: 220, y: 325), controlPoint1: NSPoint(x: 449, y: 318), controlPoint2: NSPoint(x: 332, y: 348))
book.lineWidth = 9; book.lineJoinStyle = .round; color(195, 201, 212).setStroke(); book.stroke()
let cyan = color(122, 215, 255)
let heights: [CGFloat] = [76, 145, 220, 290, 220, 145, 76]
for (index, h) in heights.enumerated() {
    let bar = NSBezierPath(roundedRect: NSRect(x: 336 + CGFloat(index) * 54, y: 480-h/2, width: 28, height: h), xRadius: 14, yRadius: 14)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = cyan.withAlphaComponent(0.4); shadow.shadowBlurRadius = 20; shadow.set()
    cyan.setFill(); bar.fill(); NSGraphicsContext.restoreGraphicsState()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
