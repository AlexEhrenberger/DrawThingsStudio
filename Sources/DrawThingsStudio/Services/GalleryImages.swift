import AVFoundation
import AppKit
import ImageIO

/// Vorschaubilder und volle Bilder für die Galerie – im Hintergrund geladen und zwischengespeichert.
/// Vorschaubilder liegen zusätzlich als JPEG im Katalog der Bibliothek, damit die Galerie beim Start sofort steht.
enum GalleryImages {
    static let thumbnailSide = 512

    private static let thumbnails: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 800
        return cache
    }()

    private static let fullImages: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 12
        return cache
    }()

    private static func key(_ id: UUID) -> NSString { id.uuidString as NSString }
    private static func diskURL(_ id: UUID) -> URL { Library.thumbnailsFolder.appending(path: "\(id.uuidString).jpg") }

    // MARK: Vorschaubilder

    static func cachedThumbnail(_ item: GalleryItem) -> CGImage? {
        thumbnails.object(forKey: key(item.id))
    }

    static func thumbnail(for item: GalleryItem) async -> CGImage? {
        if let cached = cachedThumbnail(item) { return cached }
        let id = item.id, url = item.url, isVideo = item.isVideo
        let image = await Task.detached(priority: .userInitiated) { () async -> CGImage? in
            if let data = try? Data(contentsOf: diskURL(id)), let image = ImageTools.image(from: data) { return image }
            let made: CGImage?
            if isVideo {
                made = await videoFrame(url, maxSide: thumbnailSide)
            } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: thumbnailSide,
                ]
                made = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            } else {
                made = nil
            }
            guard let image = made else { return nil }
            if let data = ImageTools.jpegData(image, quality: 0.82), Library.ensure(Library.thumbnailsFolder) {
                try? data.write(to: diskURL(id))
            }
            return image
        }.value
        if let image { thumbnails.setObject(image, forKey: key(id)) }
        return image
    }

    // MARK: Volle Bilder

    static func cachedImage(_ item: GalleryItem) -> CGImage? {
        fullImages.object(forKey: key(item.id))
    }

    static func image(for item: GalleryItem) async -> CGImage? {
        if let cached = cachedImage(item) { return cached }
        let url = item.url, isVideo = item.isVideo
        let image = await Task.detached(priority: .userInitiated) { () async -> CGImage? in
            // Bei Videos: ein Standbild (für Vergleich und Vorschau).
            isVideo ? await videoFrame(url, maxSide: nil) : ImageTools.image(from: url)
        }.value
        if let image { fullImages.setObject(image, forKey: key(item.id)) }
        return image
    }

    /// Standbild aus einem Video – nach einer Sekunde (bei kurzen Clips aus der Mitte).
    private static func videoFrame(_ url: URL, maxSide: Int?) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maxSide { generator.maximumSize = CGSize(width: maxSide, height: maxSide) }
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let seconds = duration.isFinite ? min(1, max(duration / 2, 0)) : 0
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// Nach dem Löschen: Zwischenspeicher und Vorschau-Datei entfernen.
    static func forget(_ id: UUID) {
        thumbnails.removeObject(forKey: key(id))
        fullImages.removeObject(forKey: key(id))
        try? FileManager.default.removeItem(at: diskURL(id))
    }

    /// Bibliothek gewechselt oder gelöscht: nichts aus ihr im Speicher behalten.
    static func forgetAll() {
        thumbnails.removeAllObjects()
        fullImages.removeAllObjects()
    }
}
