import AppKit
import UniformTypeIdentifiers

/// Öffnen, Sichern, Zwischenablage und automatisches Ablegen der Ergebnisse.
extension Studio {

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Bild zum Bearbeiten öffnen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let image = ImageTools.image(from: url) {
            importImage(image)
        } else {
            errorMessage = "„\(url.lastPathComponent)“ konnte nicht als Bild gelesen werden."
        }
    }

    func chooseImage(message: String) -> CGImage? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ImageTools.image(from: url)
    }

    func exportWithPanel(_ version: ImageVersion? = nil) {
        guard let version = version ?? current else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "DrawThings Studio \(Self.fileStamp.string(from: version.createdAt)).png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let image = version.id == currentID && !adjustments.isIdentity
            ? AdjustmentPipeline.apply(adjustments, to: version.image)
            : version.image
        let data = url.pathExtension.lowercased().hasPrefix("jp")
            ? ImageTools.jpegData(image, quality: 0.95)
            : ImageTools.pngData(image, description: version.prompt.isEmpty ? nil : version.prompt)
        do {
            guard let data else { throw ServiceError("Das Bild konnte nicht kodiert werden.") }
            try data.write(to: url)
        } catch {
            errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func copyCurrentImage() {
        guard let image = displayImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    func pasteImage() {
        guard let nsImage = NSImage(pasteboard: .general), let image = ImageTools.image(from: nsImage) else {
            errorMessage = "In der Zwischenablage ist kein Bild."
            return
        }
        importImage(image)
    }

    func revealInFinder(_ version: ImageVersion) {
        if let url = version.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            openLibraryFolder()
        }
    }

    /// Ordner der Bibliothek im Finder öffnen.
    func openLibraryFolder() {
        guard Library.isAvailable() else {
            errorMessage = "Die Bibliothek „\(Library.root.lastPathComponent)“ ist nicht erreichbar."
            return
        }
        NSWorkspace.shared.open(Library.root)
    }

    /// Legt jedes Ergebnis als PNG in der Bibliothek ab – mit dem Prompt in den Metadaten.
    func writeAutosave(_ version: ImageVersion) -> URL? {
        let day = Self.dayStamp.string(from: version.createdAt)
        let folder = Library.root.appending(path: day)
        // Nie still woanders sichern – z. B. wenn die SD-Karte mit der Bibliothek fehlt.
        guard Library.ensure(folder) else {
            errorMessage = "Die Bibliothek „\(Library.root.lastPathComponent)“ ist nicht erreichbar – das Bild wurde nicht gesichert, es steht nur im Verlauf."
            return nil
        }
        let kind = version.source.fileKind
        let url = folder.appending(path: "\(Self.timeStamp.string(from: version.createdAt))-\(kind).png")
        // Serien-Angaben stehen mit in der Datei – so findet die Galerie den Stapel auch ohne ihren Katalog.
        let comment = AutosaveComment(mode: kind, seed: version.seed, series: version.series, personas: version.personaIDs).text
        do {
            guard let data = ImageTools.pngData(version.image, description: version.prompt.isEmpty ? nil : version.prompt, comment: comment) else { return nil }
            try data.write(to: url)
            return url
        } catch {
            errorMessage = "Automatisches Sichern fehlgeschlagen: \(error.localizedDescription)"
            return nil
        }
    }

    static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        return formatter
    }()

    static let dayStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss-SSS"
        return formatter
    }()
}

/// Bilder aus Drag & Drop laden (Dateien aus dem Finder oder Bilddaten).
enum DropLoader {
    static func loadImage(from providers: [NSItemProvider]) async -> CGImage? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await loadURL(provider), let image = ImageTools.image(from: url) {
                return image
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await loadData(provider), let image = ImageTools.image(from: data) {
                return image
            }
        }
        return nil
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private static func loadData(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
