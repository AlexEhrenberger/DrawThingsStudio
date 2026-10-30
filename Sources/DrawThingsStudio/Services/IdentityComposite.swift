import CoreGraphics
import Foundation

/// Gesichtsreferenz beim Bearbeiten: Draw Things nimmt über HTTP nur ein Bild zuverlässig an.
/// Deshalb liegt das zu bearbeitende Bild groß links, rechts daneben stehen zwei Ansichten desselben
/// Charakters (frontal und seitlich). Qwen Image Edit bearbeitet das große Feld und kann sich dabei
/// an den Gesichtern orientieren – z. B. wenn sich der Kopf zur Kamera drehen soll und Qwen sonst ein
/// Gesicht erfinden müsste. Danach schneidet die App das große Feld wieder heraus.
enum IdentityComposite {
    /// Hintergrund zwischen den Feldern – wie beim Charakter-Raster.
    private static let background = CGColor(gray: 0.92, alpha: 1)

    struct Layout: Equatable {
        /// Gesamtgröße – immer eine der Größen, die Draw Things anbietet.
        var size: CGSize
        /// Feld des zu bearbeitenden Bildes – kleiner als bei einer normalen Bearbeitung (Ursprung oben links).
        var main: CGRect
        /// Felder der Referenzansichten, oben nach unten.
        var panels: [CGRect]
        /// Spalte mit allen Referenzfeldern (für die Kontrolle danach).
        var strip: CGRect
    }

    /// Ansichten, die neben das Bild kommen: das Hauptbild (frontal) und die beste Seitenansicht.
    static func photos(of persona: Persona) -> [PersonaPhoto] {
        guard let main = persona.mainPhoto else { return [] }
        let side = persona.photos
            .filter { $0.id != main.id && $0.view != .body && $0.face != nil && $0.view != main.view }
            .min { rank($0.view) < rank($1.view) }
        return [main] + (side.map { [$0] } ?? [])
    }

    /// ¾-Ansichten zeigen mehr vom Gesicht als ein Profil.
    private static func rank(_ view: PersonaView) -> Int {
        switch view {
        case .threeQuarterLeft, .threeQuarterRight: 0
        case .profileLeft, .profileRight: 1
        case .front: 2
        case .body: 3
        }
    }

    /// Spalte mit den Ansichten als Anteil der Gesamthöhe: nicht schmaler als ⅓ (sonst werden die Gesichter zu klein),
    /// nicht breiter als 0,8 (sonst verschenkt das Raster Platz). Am liebsten wie früher etwa 0,4.
    private static let columnRange = 0.33...0.8
    private static let preferredColumn = 0.4

    /// Das ganze Raster hat eine der Größen, die Draw Things anbietet (in der gewählten Stufe) – das Bild wird dafür kleiner.
    /// Gewählt wird das Format, in dem das Bild am größten bleibt; ein Bild, das nicht die ganze Höhe füllt
    /// (Rand oben und unten), zählt etwas weniger. Größer als bei einer normalen Bearbeitung wird das Bild nie.
    static func layout(main mainSize: CGSize, panelCount: Int, tier: SizeTier) -> Layout {
        let gap = 16.0
        let ratio = mainSize.width / mainSize.height
        var totals: [CGSize] = []
        for format in AspectRatio.all {
            let size = format.pixelSize(tier)
            if !totals.contains(size) { totals.append(size) }
        }

        var best: (size: CGSize, main: CGRect, score: CGFloat, column: CGFloat)?
        for total in totals {
            let maxWidth = total.width - (total.height * columnRange.lowerBound).rounded(.up)
            var height = min(total.height, mainSize.height)
            var width = (height * ratio).rounded(.down)
            if width > maxWidth {
                width = maxWidth
                height = (width / ratio).rounded(.down)
            }
            guard width > 0, height > 0 else { continue }
            let column = (total.width - width) / total.height
            guard columnRange.contains(column) else { continue }
            let score = width * height * (height / total.height).squareRoot()
            let main = CGRect(x: 0, y: ((total.height - height) / 2).rounded(), width: width, height: height)
            if let current = best {
                // Fast gleich groß: die Spalte, die näher an 40 % liegt.
                let nearlyEqual = abs(score - current.score) < current.score * 0.005
                let better = nearlyEqual
                    ? abs(column - preferredColumn) < abs(current.column - preferredColumn)
                    : score > current.score
                if !better { continue }
            }
            best = (total, main, score, column)
        }
        // Kommt bei den Draw-Things-Formaten nicht vor – zur Sicherheit wie früher: Bild unverändert, Spalte daneben.
        let size = best?.size ?? CGSize(width: mainSize.width + (mainSize.height * preferredColumn).rounded(), height: mainSize.height)
        let main = best?.main ?? CGRect(origin: .zero, size: mainSize)

        let strip = CGRect(x: main.maxX + gap, y: 0, width: size.width - main.maxX - gap, height: size.height)
        let count = max(panelCount, 1)
        let panelHeight = (size.height - gap * Double(count - 1)) / Double(count)
        let panels = (0..<count).map { index in
            CGRect(x: strip.minX, y: (panelHeight + gap) * Double(index), width: strip.width, height: panelHeight).integral
        }
        return Layout(size: size, main: main, panels: panels, strip: strip)
    }

    /// Raster zusammensetzen: `base` hat schon die Größe einer normalen Bearbeitung und wird ins Feld verkleinert.
    static func render(base: CGImage, persona: Persona, tier: SizeTier) async -> (image: CGImage, layout: Layout)? {
        var views: [(PersonaPhoto, CGImage)] = []
        for photo in photos(of: persona) {
            if let image = await PersonaImages.image(photo, of: persona.id) { views.append((photo, image)) }
        }
        guard !views.isEmpty else { return nil }
        let layout = layout(main: CGSize(width: base.width, height: base.height), panelCount: views.count, tier: tier)
        let input = views
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            ImageTools.draw(size: layout.size) { ctx in
                ctx.setFillColor(background)
                ctx.fill(CGRect(origin: .zero, size: layout.size))
                // CoreGraphics zählt y von unten.
                ctx.draw(base, in: CGRect(x: layout.main.minX, y: layout.size.height - layout.main.maxY, width: layout.main.width, height: layout.main.height))
                for (index, view) in input.enumerated() where layout.panels.indices.contains(index) {
                    CharacterSheet.draw(view.1, photo: view.0, in: layout.panels[index], canvas: layout.size, context: ctx, zoom: 2.4)
                }
            }
        }.value
        guard let image else { return nil }
        return (image, layout)
    }

    /// Das bearbeitete große Feld aus dem Ergebnis schneiden – liefert Draw Things eine andere Größe, anteilig.
    static func extractMain(from output: CGImage, layout: Layout) -> CGImage {
        let sx = Double(output.width) / layout.size.width
        let sy = Double(output.height) / layout.size.height
        let rect = CGRect(x: layout.main.minX * sx, y: layout.main.minY * sy, width: layout.main.width * sx, height: layout.main.height * sy).integral
        guard let cropped = output.cropping(to: rect) else { return output }
        if cropped.width == Int(layout.main.width) && cropped.height == Int(layout.main.height) { return cropped }
        return ImageTools.resized(cropped, to: layout.main.size)
    }

    /// Wie stark sich die Referenzspalte im Ergebnis verändert hat (0 = gleich, 1 = völlig anders).
    /// Hat Qwen das Raster gehalten, bleiben die Gesichter rechts fast unverändert.
    static func stripChange(output: CGImage, input: CGImage, layout: Layout) -> Double {
        func sample(_ image: CGImage) -> [Double]? {
            let sx = Double(image.width) / layout.size.width
            let sy = Double(image.height) / layout.size.height
            let rect = CGRect(x: layout.strip.minX * sx, y: layout.strip.minY * sy, width: layout.strip.width * sx, height: layout.strip.height * sy).integral
            guard let strip = image.cropping(to: rect) else { return nil }
            let width = 24, height = 64
            var pixels = [UInt8](repeating: 0, count: width * height)
            guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.interpolationQuality = .medium
            ctx.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: height))
            return pixels.map { Double($0) / 255 }
        }
        guard let a = sample(output), let b = sample(input), a.count == b.count, !a.isEmpty else { return 1 }
        return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
    }
}
