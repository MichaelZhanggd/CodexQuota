import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let n = size * scale
        let image = NSImage(size: NSSize(width: n, height: n))
        image.lockFocus()
        let unit = CGFloat(n) / 1024
        NSColor(white: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 45 * unit, y: 45 * unit, width: 934 * unit, height: 934 * unit), xRadius: 220 * unit, yRadius: 220 * unit).fill()
        NSColor(white: 0.9, alpha: 1).setStroke()
        let shell = NSBezierPath(roundedRect: NSRect(x: 210 * unit, y: 230 * unit, width: 604 * unit, height: 564 * unit), xRadius: 90 * unit, yRadius: 90 * unit)
        shell.lineWidth = 38 * unit; shell.stroke()
        let prompt = NSBezierPath()
        prompt.move(to: CGPoint(x: 315 * unit, y: 655 * unit))
        prompt.line(to: CGPoint(x: 405 * unit, y: 560 * unit))
        prompt.line(to: CGPoint(x: 315 * unit, y: 465 * unit))
        prompt.lineWidth = 42 * unit; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round; prompt.stroke()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: 490 * unit, y: 465 * unit)); line.line(to: CGPoint(x: 670 * unit, y: 465 * unit))
        line.lineWidth = 40 * unit; line.lineCapStyle = .round; line.stroke()
        NSColor(white: 0.9, alpha: 0.24).setFill()
        NSBezierPath(roundedRect: NSRect(x: 315 * unit, y: 340 * unit, width: 395 * unit, height: 34 * unit), xRadius: 17 * unit, yRadius: 17 * unit).fill()
        NSColor(white: 0.92, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 315 * unit, y: 340 * unit, width: 278 * unit, height: 34 * unit), xRadius: 17 * unit, yRadius: 17 * unit).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
