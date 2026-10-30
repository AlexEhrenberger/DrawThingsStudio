import CoreImage
import CoreImage.CIFilterBuiltins

/// Klassische Bildanpassungen – nicht destruktiv, bis „Anwenden“ gedrückt wird.
struct Adjustments: Equatable {
    var autoEnhance = false         // Apples automatische Verbesserung (wie in Fotos)
    var whiteBalance: [Double]?     // Kanal-Verstärkung R, G, B aus der Pipette
    var exposure: Double = 0        // EV, −2 … 2
    var contrast: Double = 1        // 0.75 … 1.3
    var highlights: Double = 1      // 0.3 … 2 (1 = unverändert, < 1 dunkler, > 1 heller)
    var shadows: Double = 0         // −1 … 1
    var curve: [Double] = Adjustments.linearCurve   // y-Werte bei x = 0, ¼, ½, ¾, 1
    var saturation: Double = 1      // 0 … 2
    var vibrance: Double = 0        // −1 … 1
    var temperature: Double = 0     // −100 … 100 (wärmer > 0)
    var tint: Double = 0            // −60 … 60
    var red: Double = 0             // −1 … 1, Farbkorrektur: Cyan ↔ Rot
    var green: Double = 0           // −1 … 1, Magenta ↔ Grün
    var blue: Double = 0            // −1 … 1, Gelb ↔ Blau
    var sharpness: Double = 0       // 0 … 1.5
    var clarity: Double = 0         // 0 … 1, lokaler Kontrast
    var noiseReduction: Double = 0  // 0 … 1
    var vignette: Double = 0        // 0 … 1.5
    var grain: Double = 0           // 0 … 1
    var filter: PhotoFilter = .none

    static let linearCurve: [Double] = [0, 0.25, 0.5, 0.75, 1]

    var hasColorBalance: Bool { red != 0 || green != 0 || blue != 0 }

    var isIdentity: Bool { self == Adjustments() }
}

enum PhotoFilter: String, CaseIterable, Identifiable {
    case none, mono, noir, tonal, chrome, fade, instant, process, transfer, sepia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Original"
        case .mono: "Mono"
        case .noir: "Noir"
        case .tonal: "Tonal"
        case .chrome: "Chrom"
        case .fade: "Verblasst"
        case .instant: "Sofortbild"
        case .process: "Prozess"
        case .transfer: "Transfer"
        case .sepia: "Sepia"
        }
    }

    var ciName: String? {
        switch self {
        case .none: nil
        case .mono: "CIPhotoEffectMono"
        case .noir: "CIPhotoEffectNoir"
        case .tonal: "CIPhotoEffectTonal"
        case .chrome: "CIPhotoEffectChrome"
        case .fade: "CIPhotoEffectFade"
        case .instant: "CIPhotoEffectInstant"
        case .process: "CIPhotoEffectProcess"
        case .transfer: "CIPhotoEffectTransfer"
        case .sepia: "CISepiaTone"
        }
    }
}

/// Die Core-Image-Kette für alle Anpassungen.
enum AdjustmentPipeline {
    /// Apples Auto-Filter hängen vom Bild ab – einmal pro Bild berechnen, nicht bei jedem Reglerzug.
    nonisolated(unsafe) private static var autoCache: (id: ObjectIdentifier, filters: [CIFilter])?

    static func apply(_ adjustments: Adjustments, to image: CGImage) -> CGImage {
        guard !adjustments.isIdentity else { return image }
        let input = CIImage(cgImage: image)
        let extent = input.extent
        var output = input

        if let gains = adjustments.whiteBalance, gains.count == 3 {
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gains[0], y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gains[1], z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gains[2], w: 0),
            ])
        }
        if adjustments.autoEnhance {
            for filter in autoFilters(for: image, input: input) {
                filter.setValue(output, forKey: kCIInputImageKey)
                output = filter.outputImage ?? output
            }
        }
        if adjustments.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = Float(adjustments.exposure)
            output = filter.outputImage ?? output
        }
        if adjustments.highlights < 1 || adjustments.shadows != 0 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.highlightAmount = Float(min(adjustments.highlights, 1))
            filter.shadowAmount = Float(adjustments.shadows)
            output = filter.outputImage ?? output
        }
        if adjustments.highlights > 1 {
            // Core Image kann Lichter nur abdunkeln – Aufhellen über den oberen Teil einer Tonkurve.
            let lift = CGFloat(min(adjustments.highlights - 1, 1))
            let filter = CIFilter.toneCurve()
            filter.inputImage = output
            filter.point0 = CGPoint(x: 0, y: 0)
            filter.point1 = CGPoint(x: 0.25, y: 0.25)
            filter.point2 = CGPoint(x: 0.5, y: 0.5 + 0.03 * lift)
            filter.point3 = CGPoint(x: 0.75, y: 0.75 + 0.13 * lift)
            filter.point4 = CGPoint(x: 1, y: 1)
            output = filter.outputImage ?? output
        }
        if adjustments.curve != Adjustments.linearCurve, adjustments.curve.count == 5 {
            let filter = CIFilter.toneCurve()
            filter.inputImage = output
            let y = adjustments.curve.map { CGFloat(min(max($0, 0), 1)) }
            filter.point0 = CGPoint(x: 0, y: y[0])
            filter.point1 = CGPoint(x: 0.25, y: y[1])
            filter.point2 = CGPoint(x: 0.5, y: y[2])
            filter.point3 = CGPoint(x: 0.75, y: y[3])
            filter.point4 = CGPoint(x: 1, y: y[4])
            output = filter.outputImage ?? output
        }
        if adjustments.contrast != 1 || adjustments.saturation != 1 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.contrast = Float(adjustments.contrast)
            filter.saturation = Float(adjustments.saturation)
            filter.brightness = 0
            output = filter.outputImage ?? output
        }
        if adjustments.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = output
            filter.amount = Float(adjustments.vibrance)
            output = filter.outputImage ?? output
        }
        if adjustments.temperature != 0 || adjustments.tint != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            filter.neutral = CIVector(x: 6500, y: 0)
            // Ziel unter 6500 K lässt das Bild wärmer wirken.
            filter.targetNeutral = CIVector(x: 6500 - adjustments.temperature * 30, y: adjustments.tint)
            output = filter.outputImage ?? output
        }
        if adjustments.hasColorBalance {
            // Kanäle verstärken bzw. abschwächen (±1 = doppelt bzw. halb so stark) und danach so ausgleichen,
            // dass Grau gleich hell bleibt – die Regler färben, ohne aufzuhellen (wie „Luminanz erhalten“ in Photoshop).
            let gains = [adjustments.red, adjustments.green, adjustments.blue].map { pow(2, $0) }
            let luminance = 0.2126 * gains[0] + 0.7152 * gains[1] + 0.0722 * gains[2]
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gains[0] / luminance, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gains[1] / luminance, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gains[2] / luminance, w: 0),
            ])
        }
        if let name = adjustments.filter.ciName, let filter = CIFilter(name: name) {
            filter.setValue(output, forKey: kCIInputImageKey)
            output = filter.outputImage ?? output
        }
        if adjustments.noiseReduction > 0 {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = output
            filter.noiseLevel = Float(adjustments.noiseReduction * 0.06)
            filter.sharpness = 0.4
            output = filter.outputImage ?? output
        }
        if adjustments.clarity > 0 {
            let filter = CIFilter.unsharpMask()
            filter.inputImage = output
            filter.radius = Float(max(extent.width, extent.height) * 0.02)
            filter.intensity = Float(adjustments.clarity * 0.8)
            output = filter.outputImage ?? output
        }
        if adjustments.sharpness > 0 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = output
            filter.sharpness = Float(adjustments.sharpness)
            filter.radius = 1.6
            output = filter.outputImage ?? output
        }
        if adjustments.grain > 0 {
            output = addGrain(to: output, amount: adjustments.grain, extent: extent)
        }
        if adjustments.vignette > 0 {
            let filter = CIFilter.vignette()
            filter.inputImage = output
            filter.intensity = Float(adjustments.vignette)
            filter.radius = Float(max(extent.width, extent.height) / 1.6)
            output = filter.outputImage ?? output
        }
        return ImageTools.render(output.cropped(to: extent)) ?? image
    }

    private static func autoFilters(for image: CGImage, input: CIImage) -> [CIFilter] {
        let id = ObjectIdentifier(image)
        if let cached = autoCache, cached.id == id { return cached.filters }
        let filters = input.autoAdjustmentFilters(options: [.redEye: false])
        autoCache = (id, filters)
        return filters
    }

    private static func addGrain(to image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let mono = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount * 0.35),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
        .cropped(to: extent)
        return mono.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }
}
