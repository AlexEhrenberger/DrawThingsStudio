import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

enum ImageTools {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let grayColorSpace = CGColorSpaceCreateDeviceGray()

    // MARK: Laden & Speichern

    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ]
        // Über den Thumbnail-Weg wird die EXIF-Ausrichtung gleich mit angewendet.
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func image(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return image(from: data)
    }

    /// Pixelgröße aus den Metadaten – ohne das Bild zu dekodieren.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // Hochkant fotografiert (EXIF 5–8): Breite und Höhe tauschen.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 { swap(&width, &height) }
        return CGSize(width: width, height: height)
    }

    static func image(from nsImage: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func pngData(_ image: CGImage, description: String? = nil, comment: String? = nil) -> Data? {
        encode(image, type: .png, properties: pngProperties(description: description, comment: comment))
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.9) -> Data? {
        encode(image, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    private static func pngProperties(description: String?, comment: String?) -> [CFString: Any] {
        var png: [CFString: Any] = [kCGImagePropertyPNGSoftware: "DrawThings Studio"]
        if let description { png[kCGImagePropertyPNGDescription] = description }
        if let comment { png[kCGImagePropertyPNGComment] = comment }
        return [kCGImagePropertyPNGDictionary: png]
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Verkleinertes JPEG als data:-URL für Gemma (Vision).
    static func dataURL(_ image: CGImage, maxSide: Int = 1024) -> String? {
        let small = scaled(image, maxSide: maxSide)
        guard let data = jpegData(small, quality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }

    static func render(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace)
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    // MARK: Größe & Geometrie

    static func scaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let factor = Double(maxSide) / Double(longest)
        let size = CGSize(width: (Double(image.width) * factor).rounded(), height: (Double(image.height) * factor).rounded())
        return resized(image, to: size)
    }

    static func resized(_ image: CGImage, to size: CGSize) -> CGImage {
        draw(size: size) { ctx in
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
        } ?? image
    }

    /// Füllt die Zielgröße vollständig aus (wie „Aspect Fill“) und beschneidet den Rest.
    /// Hochformatige Motive werden eher oben gehalten, damit Köpfe nicht abgeschnitten werden.
    static func filled(_ image: CGImage, to size: CGSize) -> CGImage {
        if image.width == Int(size.width) && image.height == Int(size.height) { return image }
        let scale = max(size.width / Double(image.width), size.height / Double(image.height))
        let drawn = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
        let x = (size.width - drawn.width) / 2
        // CoreGraphics zählt y von unten: 65 % des Überstands fallen unten weg, nur 35 % oben.
        let y = -(drawn.height - size.height) * 0.65
        return draw(size: size) { ctx in
            ctx.draw(image, in: CGRect(x: x, y: y, width: drawn.width, height: drawn.height))
        } ?? image
    }

    /// Ausschnitt, den `filled` vom Bild übrig lässt – in Pixeln des Bildes (Ursprung oben links).
    static func fillCropRect(width: Int, height: Int, ratio: Double) -> CGRect {
        let width = Double(width)
        let height = Double(height)
        if width / height > ratio {
            let visible = (height * ratio).rounded()
            return CGRect(x: ((width - visible) / 2).rounded(), y: 0, width: visible, height: height)
        }
        let visible = (width / ratio).rounded()
        // Wie in `filled`: 35 % des Überstands fallen oben weg, 65 % unten.
        return CGRect(x: 0, y: ((height - visible) * 0.35).rounded(), width: width, height: visible)
    }

    /// Schneidet genauso zu wie `filled`, aber in voller Auflösung (ohne zu skalieren).
    static func filledCrop(_ image: CGImage, toRatio ratio: Double) -> CGImage {
        let rect = fillCropRect(width: image.width, height: image.height, ratio: ratio)
        guard rect.width < Double(image.width) || rect.height < Double(image.height) else { return image }
        return image.cropping(to: rect) ?? image
    }

    static func cropped(_ image: CGImage, toRatio ratio: Double) -> CGImage {
        let width = Double(image.width)
        let height = Double(image.height)
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > ratio {
            rect.size.width = (height * ratio).rounded()
            rect.origin.x = ((width - rect.width) / 2).rounded()
        } else {
            rect.size.height = (width / ratio).rounded()
            rect.origin.y = ((height - rect.height) / 2).rounded()
        }
        return image.cropping(to: rect) ?? image
    }

    /// Ausschnitt in normierten Koordinaten (0 … 1, Ursprung oben links).
    static func cropped(_ image: CGImage, normalized rect: CGRect) -> CGImage {
        let width = Double(image.width)
        let height = Double(image.height)
        let pixels = CGRect(
            x: (rect.minX * width).rounded(), y: (rect.minY * height).rounded(),
            width: max((rect.width * width).rounded(), 16), height: max((rect.height * height).rounded(), 16)
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        return image.cropping(to: pixels) ?? image
    }

    /// Begradigen: drehen und so weit vergrößern, dass keine leeren Ecken entstehen.
    static func straightened(_ image: CGImage, degrees: Double) -> CGImage {
        guard degrees != 0 else { return image }
        let filter = CIFilter.straighten()
        filter.inputImage = CIImage(cgImage: image)
        filter.angle = Float(degrees * .pi / 180)
        guard let output = filter.outputImage else { return image }
        return render(output.cropped(to: CGRect(x: 0, y: 0, width: image.width, height: image.height))) ?? image
    }

    static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage {
        let size = CGSize(width: image.height, height: image.width)
        return draw(size: size) { ctx in
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
            ctx.draw(image, in: CGRect(x: -Double(image.width) / 2, y: -Double(image.height) / 2, width: Double(image.width), height: Double(image.height)))
        } ?? image
    }

    static func flipped(_ image: CGImage, horizontal: Bool) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        return draw(size: size) { ctx in
            if horizontal {
                ctx.translateBy(x: size.width, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            } else {
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
            }
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
        } ?? image
    }

    /// Hochskalieren mit Lanczos und leichter Nachschärfung.
    static func upscaled(_ image: CGImage, factor: Double) -> CGImage {
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = CIImage(cgImage: image)
        lanczos.scale = Float(factor)
        lanczos.aspectRatio = 1
        guard let scaled = lanczos.outputImage else { return image }
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = scaled
        sharpen.sharpness = 0.35
        sharpen.radius = 1.2
        let output = (sharpen.outputImage ?? scaled).cropped(to: scaled.extent)
        return render(output) ?? image
    }

    static func draw(size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }

    // MARK: Farbe messen

    /// Mittlere Farbe (0 … 1) eines kleinen Bereichs um den Punkt (normiert, Ursprung oben links).
    static func averageColor(in image: CGImage, at point: CGPoint, radius: Int = 3) -> (r: Double, g: Double, b: Double)? {
        let x = Int(point.x * Double(image.width))
        let y = Int(point.y * Double(image.height))
        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2 + 1, height: radius * 2 + 1)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty, let patch = image.cropping(to: rect) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    // MARK: Histogramm

    struct Histogram: Equatable {
        var red: [Double]
        var green: [Double]
        var blue: [Double]
        var luminance: [Double]
    }

    static func histogram(_ image: CGImage, bins: Int = 64) -> Histogram? {
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var red = [Double](repeating: 0, count: bins)
        var green = red, blue = red, luminance = red
        let scale = Double(bins) / 256
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 0 {
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            red[Int(Double(r) * scale)] += 1
            green[Int(Double(g) * scale)] += 1
            blue[Int(Double(b) * scale)] += 1
            let luma: Double = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
            luminance[min(Int(luma * scale), bins - 1)] += 1
        }
        // Gemeinsam normieren, Ausreißer an den Rändern nicht alles plattdrücken lassen.
        let all: [Double] = red + green + blue + luminance
        let peak: Double = max(all.sorted(by: >).dropFirst(4).first ?? 1, 1)
        let norm = { (values: [Double]) in values.map { min($0 / peak, 1) } }
        return Histogram(red: norm(red), green: norm(green), blue: norm(blue), luminance: norm(luminance))
    }

    // MARK: Masken (weiß = ausgewählt)

    static func blankMask(width: Int, height: Int) -> CGImage? {
        maskContext(width: width, height: height)?.makeImage()
    }

    private static func maskContext(width: Int, height: Int) -> CGContext? {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: grayColorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        ctx?.setFillColor(gray: 0, alpha: 1)
        ctx?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    /// Malt einen Pinselstrich in die Maske. Punkte normiert (Ursprung oben links),
    /// Durchmesser als Anteil der längeren Bildseite.
    static func paint(_ mask: CGImage, stroke points: [CGPoint], diameter: Double, erase: Bool) -> CGImage {
        let width = mask.width, height = mask.height
        guard let ctx = maskContext(width: width, height: height), !points.isEmpty else { return mask }
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
        let lineWidth = diameter * Double(max(width, height))
        let mapped = points.map { CGPoint(x: $0.x * Double(width), y: (1 - $0.y) * Double(height)) }
        ctx.setStrokeColor(gray: erase ? 0 : 1, alpha: 1)
        ctx.setFillColor(gray: erase ? 0 : 1, alpha: 1)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if mapped.count == 1 {
            let p = mapped[0]
            ctx.fillEllipse(in: CGRect(x: p.x - lineWidth / 2, y: p.y - lineWidth / 2, width: lineWidth, height: lineWidth))
        } else {
            ctx.addLines(between: mapped)
            ctx.strokePath()
        }
        return ctx.makeImage() ?? mask
    }

    static func inverted(_ mask: CGImage) -> CGImage {
        let output = CIImage(cgImage: mask).applyingFilter("CIColorInvert")
        return grayImage(output, size: CGSize(width: mask.width, height: mask.height)) ?? mask
    }

    static func grayImage(_ image: CIImage, size: CGSize) -> CGImage? {
        let extent = image.extent
        let scaled = image.transformed(by: CGAffineTransform(scaleX: size.width / extent.width, y: size.height / extent.height))
        let rect = CGRect(origin: .zero, size: size)
        return context.createCGImage(scaled.cropped(to: rect), from: rect, format: .L8, colorSpace: grayColorSpace)
    }

    static func isEmptyMask(_ mask: CGImage) -> Bool {
        guard let histogram = histogram(mask, bins: 8) else { return true }
        return histogram.luminance.dropFirst().allSatisfy { $0 == 0 }
    }

    /// Maske passend zum Bild skaliert und mit weicher Kante (Anteil der längeren Seite).
    private static func maskCI(_ mask: CGImage, for extent: CGRect, feather: Double) -> CIImage {
        var ci = CIImage(cgImage: mask)
            .transformed(by: CGAffineTransform(scaleX: extent.width / Double(mask.width), y: extent.height / Double(mask.height)))
        if feather > 0 {
            ci = ci.clampedToExtent()
                .applyingGaussianBlur(sigma: feather * max(extent.width, extent.height))
                .cropped(to: extent)
        }
        return ci
    }

    /// Übernimmt `edited` nur dort, wo die Maske weiß ist – sonst bleibt `original`.
    static func composite(_ edited: CGImage, over original: CGImage, mask: CGImage, feather: Double) -> CGImage {
        let base = CIImage(cgImage: original)
        let extent = base.extent
        let top = CIImage(cgImage: edited)
            .transformed(by: CGAffineTransform(scaleX: extent.width / Double(edited.width), y: extent.height / Double(edited.height)))
        let blend = CIFilter.blendWithMask()
        blend.inputImage = top
        blend.backgroundImage = base
        blend.maskImage = maskCI(mask, for: extent, feather: feather)
        guard let output = blend.outputImage else { return original }
        return render(output.cropped(to: extent)) ?? original
    }

    enum BackgroundEffect {
        case transparent
        case blur(Double)
        case monochrome
        case color(CGColor)
    }

    /// Verändert alles außerhalb der Auswahl.
    static func applyBackground(_ effect: BackgroundEffect, to image: CGImage, mask: CGImage, feather: Double) -> CGImage {
        let base = CIImage(cgImage: image)
        let extent = base.extent
        let background: CIImage
        switch effect {
        case .transparent:
            background = CIImage(color: .clear).cropped(to: extent)
        case .blur(let amount):
            background = base.clampedToExtent()
                .applyingGaussianBlur(sigma: amount * max(extent.width, extent.height) * 0.03)
                .cropped(to: extent)
        case .monochrome:
            background = base.applyingFilter("CIPhotoEffectNoir")
        case .color(let color):
            background = CIImage(color: CIColor(cgColor: color)).cropped(to: extent)
        }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = base
        blend.backgroundImage = background
        blend.maskImage = maskCI(mask, for: extent, feather: feather)
        guard let output = blend.outputImage else { return image }
        return render(output.cropped(to: extent)) ?? image
    }

    /// Farbige, halbtransparente Darstellung der Auswahl für den Canvas.
    static func selectionOverlay(_ mask: CGImage, color: CGColor) -> CGImage? {
        let maskImage = CIImage(cgImage: mask)
        let extent = maskImage.extent
        let tint = CIImage(color: CIColor(cgColor: color).withAlpha(0.5)).cropped(to: extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = tint
        blend.backgroundImage = CIImage(color: .clear).cropped(to: extent)
        blend.maskImage = maskImage
        return blend.outputImage.flatMap { render($0.cropped(to: extent)) }
    }
}

private extension CIColor {
    func withAlpha(_ alpha: Double) -> CIColor {
        CIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
