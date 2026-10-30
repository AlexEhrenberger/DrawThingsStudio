import AppKit

/// Fotos der Charaktere laden – im Hintergrund und zwischengespeichert.
enum PersonaImages {
    private static let images: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 40
        return cache
    }()

    private static let thumbnails: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 300
        return cache
    }()

    static func cachedThumbnail(_ photo: PersonaPhoto) -> CGImage? {
        thumbnails.object(forKey: photo.id.uuidString as NSString)
    }

    static func image(_ photo: PersonaPhoto, of personaID: UUID) async -> CGImage? {
        let key = photo.id.uuidString as NSString
        if let cached = images.object(forKey: key) { return cached }
        let url = PersonaStore.url(for: photo, of: personaID)
        let image = await Task.detached(priority: .userInitiated) { ImageTools.image(from: url) }.value
        if let image { images.setObject(image, forKey: key) }
        return image
    }

    static func thumbnail(_ photo: PersonaPhoto, of personaID: UUID) async -> CGImage? {
        let key = photo.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let image = await image(photo, of: personaID) else { return nil }
        let small = await Task.detached(priority: .userInitiated) { ImageTools.scaled(image, maxSide: 480) }.value
        thumbnails.setObject(small, forKey: key)
        return small
    }

    static func forget(photoID: UUID) {
        images.removeObject(forKey: photoID.uuidString as NSString)
        thumbnails.removeObject(forKey: photoID.uuidString as NSString)
    }

    /// Nach dem Löschen eines Charakters oder beim Wechsel der Bibliothek – die Fotos sind dann ohnehin weg.
    static func forget(personaID: UUID? = nil) {
        images.removeAllObjects()
        thumbnails.removeAllObjects()
    }
}

/// Referenzbild eines Charakters für Qwen Image Edit: ein Raster aus mehreren Ansichten
/// (ein großes Frontalporträt, daneben bis zu drei kleinere Ansichten) oder nur das Frontalfoto.
/// Gesichter werden eng auf Kopf und Schultern zugeschnitten, damit bei ~1 Megapixel möglichst viel Detail bleibt.
/// Bewusst ohne Beschriftungen – Qwen würde Text sonst abmalen.
enum CharacterSheet {
    /// Hintergrund zwischen den Feldern: neutrales Hellgrau.
    private static let background = CGColor(gray: 0.92, alpha: 1)

    static func render(_ persona: Persona, mode: PersonaReferenceMode, size: CGSize) async -> CGImage? {
        guard let main = persona.mainPhoto, let mainImage = await PersonaImages.image(main, of: persona.id) else { return nil }
        var others: [(PersonaPhoto, CGImage)] = []
        if mode == .sheet {
            for photo in sheetPhotos(persona, excluding: main) {
                if let image = await PersonaImages.image(photo, of: persona.id) { others.append((photo, image)) }
            }
        }
        let input = others
        return await Task.detached(priority: .userInitiated) {
            compose(main: (main, mainImage), others: input, size: size)
        }.value
    }

    /// Bis zu drei weitere Ansichten – jede Blickrichtung nur einmal, Ganzkörper zuletzt.
    static func sheetPhotos(_ persona: Persona, excluding main: PersonaPhoto) -> [PersonaPhoto] {
        var seen: Set<PersonaView> = [main.view]
        var chosen: [PersonaPhoto] = []
        for photo in persona.photos.sorted(by: { $0.view.sheetPriority < $1.view.sheetPriority }) where photo.id != main.id {
            guard !seen.contains(photo.view) else { continue }
            seen.insert(photo.view)
            chosen.append(photo)
            if chosen.count == 3 { break }
        }
        return chosen
    }

    // MARK: Zeichnen

    private static func compose(main: (PersonaPhoto, CGImage), others: [(PersonaPhoto, CGImage)], size: CGSize) -> CGImage? {
        let layout = layout(size: size, small: others.map { $0.0.view == .body || $0.0.face == nil ? 0.45 : 0.8 })
        return ImageTools.draw(size: size) { ctx in
            ctx.setFillColor(background)
            ctx.fill(CGRect(origin: .zero, size: size))
            draw(main.1, photo: main.0, in: layout.main, canvas: size, context: ctx, zoom: 2.5)
            for (index, other) in others.enumerated() where layout.small.indices.contains(index) {
                draw(other.1, photo: other.0, in: layout.small[index], canvas: size, context: ctx, zoom: 2.7)
            }
        }
    }

    /// Ein Feld füllen: mit Gesicht Kopf und Schultern, sonst das ganze Foto eingepasst.
    static func draw(_ image: CGImage, photo: PersonaPhoto, in rect: CGRect, canvas: CGSize, context ctx: CGContext, zoom: Double) {
        // Feld in CoreGraphics-Koordinaten (Ursprung unten links).
        let target = CGRect(x: rect.minX, y: canvas.height - rect.maxY, width: rect.width, height: rect.height)
        let imageSize = CGSize(width: image.width, height: image.height)
        if let face = photo.face, photo.view != .body,
           let crop = image.cropping(to: faceCrop(face: face, imageSize: imageSize, aspect: rect.width / rect.height, zoom: zoom)) {
            ctx.draw(crop, in: target)
        } else {
            let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
            let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            ctx.draw(image, in: CGRect(x: target.midX - drawn.width / 2, y: target.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
        }
    }

    /// Ausschnitt in Pixeln (Ursprung oben links) im Seitenverhältnis des Feldes:
    /// das Gesicht etwas oberhalb der Mitte, darunter Hals und Schultern.
    static func faceCrop(face: CGRect, imageSize: CGSize, aspect: Double, zoom: Double) -> CGRect {
        let faceWidth = face.width * imageSize.width
        let faceHeight = face.height * imageSize.height
        var height = faceHeight * zoom
        var width = height * aspect
        if width < faceWidth * 1.6 {
            width = faceWidth * 1.6
            height = width / aspect
        }
        let fit = min(1, imageSize.width / width, imageSize.height / height)
        width *= fit
        height *= fit
        // Gesichtsmitte auf 45 % der Höhe – darüber bleibt Platz für die Haare.
        let centerX = face.midX * imageSize.width
        let centerY = face.midY * imageSize.height + 0.05 * height
        let x = min(max(centerX - width / 2, 0), imageSize.width - width)
        let y = min(max(centerY - height / 2, 0), imageSize.height - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    // MARK: Aufteilung

    struct Layout {
        var main: CGRect
        var small: [CGRect]
    }

    /// Großes Feld links oder oben, die kleinen im Raster daneben. Gewählt wird die Aufteilung, deren Felder
    /// am besten zu ihrem Inhalt passen und das große Feld groß lässt.
    /// - Parameter small: gewünschtes Seitenverhältnis je kleinem Feld (Kopf und Schultern ~0,8, Ganzkörper ~0,45).
    static func layout(size: CGSize, small targets: [Double]) -> Layout {
        let n = targets.count
        let W = size.width, H = size.height
        let g = (min(W, H) * 0.014).rounded()
        // Nur ein Foto: randlos über die ganze Fläche.
        guard n > 0 else { return Layout(main: CGRect(origin: .zero, size: size), small: []) }
        let whole = CGRect(x: g, y: g, width: W - 2 * g, height: H - 2 * g)

        func badness(_ rect: CGRect, target: Double = 0.8) -> Double { abs(log((rect.width / rect.height) / target)) }

        var best: (score: Double, layout: Layout)?
        for mainFirstColumn in [true, false] {
            for fraction in [0.55, 0.62, 0.7] {
                for columns in 1...n {
                    let rows = Int((Double(n) / Double(columns)).rounded(.up))
                    let main: CGRect
                    let rest: CGRect
                    if mainFirstColumn {
                        let width = ((W - 3 * g) * fraction).rounded()
                        main = CGRect(x: g, y: g, width: width, height: H - 2 * g)
                        rest = CGRect(x: 2 * g + width, y: g, width: W - 3 * g - width, height: H - 2 * g)
                    } else {
                        let height = ((H - 3 * g) * fraction).rounded()
                        main = CGRect(x: g, y: g, width: W - 2 * g, height: height)
                        rest = CGRect(x: g, y: 2 * g + height, width: W - 2 * g, height: H - 3 * g - height)
                    }
                    let cellWidth = (rest.width - CGFloat(columns - 1) * g) / CGFloat(columns)
                    let cellHeight = (rest.height - CGFloat(rows - 1) * g) / CGFloat(rows)
                    guard cellWidth > 48, cellHeight > 48 else { continue }
                    let small = (0..<n).map { index in
                        CGRect(
                            x: rest.minX + CGFloat(index % columns) * (cellWidth + g),
                            y: rest.minY + CGFloat(index / columns) * (cellHeight + g),
                            width: cellWidth, height: cellHeight
                        ).integral
                    }
                    let score = 2.5 * badness(main)
                        + zip(small, targets).map { badness($0, target: $1) }.reduce(0, +)
                        + 0.6 * Double(rows * columns - n)
                        - 1.5 * Double(main.width * main.height) / Double(W * H)
                    if best == nil || score < best!.score { best = (score, Layout(main: main.integral, small: small)) }
                }
            }
        }
        return best?.layout ?? Layout(main: whole, small: [])
    }
}
