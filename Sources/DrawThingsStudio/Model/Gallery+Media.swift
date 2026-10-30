import AVFoundation
import AppKit

/// Videos in der Galerie und Dateien von außen in die Bibliothek übernehmen.
extension Gallery {

    // MARK: Videos

    /// Größe, Länge und Aufnahmedatum eines Videos – ohne es abzuspielen.
    nonisolated static func readVideo(_ url: URL) async -> ScannedFile? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize) else { return nil }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        // Hochkant aufgenommen: die Drehung steckt in der Transformation.
        let size = natural.applying(transform)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds)
        var date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
        if let item = try? await asset.load(.creationDate), let recorded = try? await item.load(.dateValue) {
            date = recorded
        }
        var item = GalleryItem(
            id: UUID(),
            path: url.path,
            createdAt: date ?? .now,
            kind: "video",
            prompt: "",
            width: Int(abs(size.width).rounded()),
            height: Int(abs(size.height).rounded())
        )
        if let duration, duration.isFinite { item.videoLength = duration }
        return ScannedFile(item: item)
    }

    // MARK: Importieren

    /// Bilder und Videos von außen in die Bibliothek kopieren (in den Tagesordner ihres Aufnahmedatums)
    /// und gleich aufnehmen. Dateien, die schon in der Bibliothek liegen, bleiben, wo sie sind.
    /// - Returns: Namen der Dateien, die nicht übernommen werden konnten.
    func importFiles(_ urls: [URL]) async -> [String] {
        let root = self.root
        let known = Set(items.map(\.path))
        let results = await Task.detached(priority: .userInitiated) { () -> (files: [ScannedFile], failures: [String]) in
            let dayStamp = DateFormatter()
            dayStamp.dateFormat = "yyyy-MM-dd"
            var files: [ScannedFile] = []
            var failures: [String] = []
            let rootPath = root.path + "/"
            for url in urls {
                let ext = url.pathExtension.lowercased()
                let isVideo = GalleryMedia.videoExtensions.contains(ext)
                guard isVideo || GalleryMedia.imageExtensions.contains(ext) else {
                    failures.append(url.lastPathComponent)
                    continue
                }
                if url.path.hasPrefix(rootPath) { continue }
                // Erst lesen (für das Datum), dann kopieren und den Pfad umstellen.
                guard var file = isVideo ? await Gallery.readVideo(url) : Gallery.read(url) else {
                    failures.append(url.lastPathComponent)
                    continue
                }
                if !isVideo { file.item.kind = "imported" }
                let folder = root.appending(path: dayStamp.string(from: file.item.createdAt))
                guard Library.ensure(folder, in: root) else {
                    failures.append(url.lastPathComponent)
                    continue
                }
                let target = Gallery.uniqueURL(in: folder, name: url.lastPathComponent)
                guard !known.contains(target.path), (try? FileManager.default.copyItem(at: url, to: target)) != nil else {
                    failures.append(url.lastPathComponent)
                    continue
                }
                file.item.path = target.path
                files.append(file)
            }
            return (files, failures)
        }.value
        guard !results.files.isEmpty else { return results.failures }
        for file in results.files where item(file.item.id) == nil {
            insertImported(file.item)
        }
        return results.failures
    }

    /// „Clip.mp4“ → „Clip 2.mp4“, falls es den Namen schon gibt.
    private nonisolated static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appending(path: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(base) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return url
    }
}
