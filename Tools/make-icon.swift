// Zeichnet das App-Icon von DrawThings Studio und erzeugt daraus AppIcon.icns.
// Aufruf: swift Tools/make-icon.swift <Zielordner>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build")
let iconset = output.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let s = size / 1024
        // macOS-Raster: Inhalt 824 × 824 mit 100 pt Rand, Eckenradius ≈ 185.
        let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let shape = CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

        // Schatten
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(shape)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Verlauf: tiefes Indigo → Violett → Magenta → Orange
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let colors = [
            NSColor(red: 0.13, green: 0.12, blue: 0.36, alpha: 1).cgColor,
            NSColor(red: 0.42, green: 0.25, blue: 0.86, alpha: 1).cgColor,
            NSColor(red: 0.90, green: 0.29, blue: 0.56, alpha: 1).cgColor,
            NSColor(red: 0.99, green: 0.58, blue: 0.27, alpha: 1).cgColor,
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.42, 0.75, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])

        // Weicher Glanz oben links
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            NSColor.white.withAlphaComponent(0.35).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: body.minX + 230 * s, y: body.maxY - 200 * s), startRadius: 0,
                               endCenter: CGPoint(x: body.minX + 230 * s, y: body.maxY - 200 * s), endRadius: 520 * s, options: [])

        // Bilderrahmen (Leinwand)
        let frame = CGRect(x: 262 * s, y: 270 * s, width: 500 * s, height: 430 * s)
        let framePath = CGPath(roundedRect: frame, cornerWidth: 54 * s, cornerHeight: 54 * s, transform: nil)
        ctx.addPath(framePath)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        ctx.fillPath()
        ctx.addPath(framePath)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(30 * s)
        ctx.strokePath()

        // Berge in der Leinwand
        ctx.saveGState()
        ctx.addPath(framePath)
        ctx.clip()
        let mountains = CGMutablePath()
        mountains.move(to: CGPoint(x: frame.minX, y: frame.minY + 60 * s))
        mountains.addLine(to: CGPoint(x: frame.minX + 150 * s, y: frame.minY + 210 * s))
        mountains.addLine(to: CGPoint(x: frame.minX + 250 * s, y: frame.minY + 120 * s))
        mountains.addLine(to: CGPoint(x: frame.minX + 360 * s, y: frame.minY + 250 * s))
        mountains.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + 90 * s))
        mountains.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        mountains.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
        mountains.closeSubpath()
        ctx.addPath(mountains)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Funkeln (KI) oben rechts
        func sparkle(center: CGPoint, radius: CGFloat) {
            let path = CGMutablePath()
            let inner = radius * 0.24
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4 + .pi / 2
                let r = i.isMultiple(of: 2) ? radius : inner
                let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 24 * s, color: NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }
        sparkle(center: CGPoint(x: 735 * s, y: 712 * s), radius: 128 * s)
        sparkle(center: CGPoint(x: 590 * s, y: 790 * s), radius: 52 * s)
        ctx.restoreGState()
        return true
    }
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    let image = drawIcon(size: pixels)
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG fehlgeschlagen") }
    try png.write(to: iconset.appending(path: "\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appending(path: "AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("AppIcon.icns erstellt")
