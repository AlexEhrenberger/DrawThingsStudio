import AppKit
import os

/// Eine Bibliothek ist ein ganz normaler Ordner – nichts liegt versteckt in `~/Library`:
///
///     Kunde A/
///       2026-10-11/…            Bilder und Videos, nach Tagen
///       Charaktere/<ID>/…       Fotos der Charaktere
///       Assets/<ID>/…           Kleidung, Orte, Referenzen …
///       Katalog/                Markierungen, Notizen, Projekte, Charaktere, Assets (JSON) und Vorschaubilder
///
/// Ordner kopieren nimmt die Bibliothek mit (z. B. auf eine SD-Karte), Ordner löschen entfernt alles.
/// Pfade im Katalog stehen relativ zum Ordner – die Bibliothek funktioniert an jedem Ort.
enum Library {
    private static let state = OSAllocatedUnfairLock(initialState: URL(fileURLWithPath: NSHomeDirectory()))

    /// Ordner der geöffneten Bibliothek.
    static var root: URL {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue.standardizedFileURL } }
    }

    static var catalogFolder: URL { root.appending(path: "Katalog") }
    static var thumbnailsFolder: URL { catalogFolder.appending(path: "Vorschaubilder") }
    static var charactersFolder: URL { root.appending(path: "Charaktere") }
    static var assetsFolder: URL { root.appending(path: "Assets") }

    /// Ordner der App – beim Einlesen der Bilder übersprungen.
    static let reservedFolders: Set<String> = ["Katalog", "Charaktere", "Assets"]

    /// Vorgabe für die erste Bibliothek (dort lagen die Bilder schon vor den Bibliotheken).
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures/DrawThings Studio")
    }

    static func isAvailable(_ url: URL = root) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Ordner innerhalb der Bibliothek anlegen – nie die Bibliothek selbst. Sonst entstünde z. B. bei
    /// ausgeworfener SD-Karte ein leerer Ordner unter /Volumes, in den dann still gesichert würde.
    @discardableResult
    static func ensure(_ folder: URL, in root: URL = root) -> Bool {
        guard isAvailable(root) else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    // MARK: Pfade im Katalog

    /// Pfad relativ zur Bibliothek; Dateien außerhalb behalten den vollen Pfad.
    nonisolated static func relative(_ path: String, to root: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    nonisolated static func resolve(_ path: String, in root: URL) -> String {
        path.hasPrefix("/") ? path : root.appending(path: path).path
    }

    // MARK: Umzug aus Application Support

    /// Ordner, in dem die Bilder vor den Bibliotheken lagen (früher „Ablageordner“) – nur dorthin zieht der alte Stand um.
    static var legacyRoot: URL {
        URL(fileURLWithPath: UserDefaults.standard.string(forKey: "autosaveFolder") ?? defaultURL.path).standardizedFileURL
    }

    /// Bis Oktober 2026 lagen Katalog, Vorschaubilder, Charakterfotos, Bausteine und gespeicherte Prompts in
    /// `~/Library/Application Support/DrawThings Studio`, Prompt-Entwurf und Serien-Werte in den Einstellungen der App.
    /// Alles zieht einmalig in die Bibliothek mit den alten Bildern um – verschoben, nicht kopiert, es bleibt nichts zurück.
    /// Jede Datei nur, wenn es sie in der Bibliothek noch nicht gibt.
    static func migrateLegacyData(into root: URL) {
        guard root.standardizedFileURL == legacyRoot, isAvailable(root) else { return }
        let fm = FileManager.default
        let old = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "DrawThings Studio")
        let catalog = root.appending(path: "Katalog")

        func move(_ from: URL, _ to: URL) {
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: from, to: to)) == nil, (try? fm.copyItem(at: from, to: to)) != nil {
                try? fm.removeItem(at: from)
            }
        }
        move(old.appending(path: "gallery.json"), catalog.appending(path: "gallery.json"))
        move(old.appending(path: "characters.json"), catalog.appending(path: "characters.json"))
        move(old.appending(path: "catalog.json"), catalog.appending(path: "building-blocks.json"))
        move(old.appending(path: "library.json"), catalog.appending(path: "saved-prompts.json"))
        // Ordner einzeln umziehen – an Ziel-Ordnern, die es schon gibt, scheitert moveItem.
        for (from, to) in [(old.appending(path: "Characters"), root.appending(path: "Charaktere")),
                           (old.appending(path: "Thumbnails"), catalog.appending(path: "Vorschaubilder"))] {
            guard let children = try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) else { continue }
            for child in children { move(child, to.appending(path: child.lastPathComponent)) }
            if isEmptyFolder(from) { try? fm.removeItem(at: from) }
        }
        if isEmptyFolder(old) { try? fm.removeItem(at: old) }

        // Prompt-Entwurf und Serien-Werte standen in den Einstellungen.
        let defaults = UserDefaults.standard
        ensure(catalog, in: root)
        for (key, file) in [("promptBuilder.snapshot", "prompt-draft.json"), ("series.setup", "series.json")] {
            guard let data = defaults.data(forKey: key) else { continue }
            let url = catalog.appending(path: file)
            if fm.fileExists(atPath: url.path) || (try? data.write(to: url, options: .atomic)) != nil {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Leer bis auf .DS_Store.
    private static func isEmptyFolder(_ url: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return names.allSatisfy { $0 == ".DS_Store" }
    }
}

/// Eine Bibliothek in der Liste – auch solche auf gerade nicht eingesteckten Laufwerken.
struct LibraryEntry: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isAvailable: Bool { Library.isAvailable(url) }

    /// Ort für die Anzeige: „Bilder“ oder der Name des Laufwerks.
    var place: String {
        let components = url.pathComponents
        if components.count > 2, components[1] == "Volumes" { return components[2] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parent = url.deletingLastPathComponent().path
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }
}

/// Was in einer Bibliothek liegt – für die Rückfrage vor dem Löschen.
struct LibrarySummary {
    /// Bilder und Videos der Galerie (ohne Charakterfotos, Assets und Vorschaubilder).
    var images = 0
    var videos = 0
    /// Alle Dateien im Ordner, auch versteckte.
    var files = 0
    var bytes: Int64 = 0

    nonisolated static func measure(_ root: URL) -> LibrarySummary {
        var summary = LibrarySummary()
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey], options: []
        ) else { return summary }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey]),
                  values.isRegularFile == true else { continue }
            summary.files += 1
            summary.bytes += Int64(values.totalFileAllocatedSize ?? 0)
            let top = Library.relative(url.path, to: root).split(separator: "/").first.map(String.init) ?? ""
            guard !Library.reservedFolders.contains(top) else { continue }
            let ext = url.pathExtension.lowercased()
            if GalleryMedia.videoExtensions.contains(ext) { summary.videos += 1 }
            if GalleryMedia.imageExtensions.contains(ext) { summary.images += 1 }
        }
        return summary
    }
}

/// Dateiendungen, die die Galerie aufnimmt.
enum GalleryMedia {
    nonisolated static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp"]
    nonisolated static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
}
