// Run: swiftc -parse-as-library -O scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
// Draws the app icon (a chrome level knob on a brushed-silver tile) into the AppIcon asset.
import AppKit

@main struct MakeIcon {
    static func main() {
        let dir = "TurntableMixer/Assets.xcassets/AppIcon.appiconset"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let pixels = [16, 32, 64, 128, 256, 512, 1024]
        for p in pixels { write(render(p), "\(dir)/icon_\(p).png") }
        let slots: [(pt: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
        let images = slots.map { s in
            "    { \"filename\" : \"icon_\(s.pt * s.scale).png\", \"idiom\" : \"mac\", \"scale\" : \"\(s.scale)x\", \"size\" : \"\(s.pt)x\(s.pt)\" }"
        }.joined(separator: ",\n")
        let json = "{\n  \"images\" : [\n\(images)\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
        try! json.write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
    }

    static func write(_ rep: NSBitmapImageRep, _ path: String) {
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    static func render(_ px: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let c = NSGraphicsContext.current!.cgContext
        c.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024) // draw on a 1024 grid
        draw(c)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func draw(_ c: CGContext) {
        let space = CGColorSpaceCreateDeviceRGB()
        func grad(_ colors: [NSColor]) -> CGGradient {
            CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: nil)!
        }
        // Tile: 824 pt square with the standard macOS margin.
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        c.addPath(tilePath); c.setFillColor(NSColor(white: 0.8, alpha: 1).cgColor); c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(tilePath); c.clip()
        c.drawLinearGradient(grad([NSColor(white: 0.93, alpha: 1), NSColor(white: 0.74, alpha: 1)]),
                             start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
        // Horizontal brushing, fixed pattern.
        var seed: UInt64 = 7
        for y in stride(from: tile.minY, to: tile.maxY, by: 3) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let a = CGFloat(seed >> 33 & 0xff) / 255 * 0.07
            c.setFillColor(NSColor(white: seed & 1 == 0 ? 1 : 0, alpha: a).cgColor)
            c.fill(CGRect(x: tile.minX, y: y, width: tile.width, height: 1.5))
        }
        c.restoreGState()
        c.addPath(tilePath); c.setStrokeColor(NSColor(white: 1, alpha: 0.6).cgColor); c.setLineWidth(3); c.strokePath()

        // Knob.
        let mid = CGPoint(x: 512, y: 500)
        // Tick dots: 270 degree sweep from lower left, 11 dots, the first 7 lit orange.
        for i in 0..<11 {
            let ang = (225 - Double(i) * 27) * .pi / 180
            let r: CGFloat = 318
            let p = CGPoint(x: mid.x + r * CGFloat(cos(ang)), y: mid.y + r * CGFloat(sin(ang)))
            let rad: CGFloat = i == 0 ? 17 : 12
            c.setFillColor((i < 7 ? NSColor(red: 1, green: 0.55, blue: 0.1, alpha: 1) : NSColor(white: 0.25, alpha: 0.7)).cgColor)
            c.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
        }
        // Skirt.
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -14), blur: 22, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        c.setFillColor(NSColor(white: 0.08, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: mid.x - 255, y: mid.y - 255, width: 510, height: 510))
        c.restoreGState()
        // Cap: brushed aluminium, conic look via angled gradient plus a rim.
        let cap = CGRect(x: mid.x - 205, y: mid.y - 205, width: 410, height: 410)
        c.saveGState()
        c.addEllipse(in: cap); c.clip()
        c.drawLinearGradient(grad([NSColor(white: 0.97, alpha: 1), NSColor(white: 0.62, alpha: 1), NSColor(white: 0.88, alpha: 1)]),
                             start: CGPoint(x: cap.minX, y: cap.maxY), end: CGPoint(x: cap.maxX, y: cap.minY), options: [])
        for r in stride(from: 6.0, to: 205.0, by: 5.0) {
            c.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor); c.setLineWidth(1)
            c.strokeEllipse(in: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2))
        }
        c.restoreGState()
        c.setStrokeColor(NSColor(white: 0.35, alpha: 1).cgColor); c.setLineWidth(4); c.strokeEllipse(in: cap)
        // Pointer line, at the 7th dot's angle.
        let a = (225 - 6 * 27.0) * .pi / 180
        c.setStrokeColor(NSColor(white: 0.1, alpha: 1).cgColor); c.setLineWidth(18); c.setLineCap(.round)
        c.move(to: CGPoint(x: mid.x + 95 * CGFloat(cos(a)), y: mid.y + 95 * CGFloat(sin(a))))
        c.addLine(to: CGPoint(x: mid.x + 180 * CGFloat(cos(a)), y: mid.y + 180 * CGFloat(sin(a))))
        c.strokePath()
    }
}
