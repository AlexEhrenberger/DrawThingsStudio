import AppKit
import Observation
import UniformTypeIdentifiers

/// Bereich im Asset-Baukasten – wie ein Bereich der Prompt-Bausteine („Motiv“, „Kleidung“ …).
struct AssetSection: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var icon: String

    static let defaults: [AssetSection] = [
        AssetSection(id: "mode", name: "Mode", icon: "tshirt"),
        AssetSection(id: "orte-dinge", name: "Orte & Dinge", icon: "mountain.2"),
        AssetSection(id: "pose-stil", name: "Pose & Stil", icon: "figure.wave"),
        AssetSection(id: "referenzen", name: "Referenzen", icon: "photo.stack"),
    ]

    /// Bereich für eigene Kategorien aus Katalogen ohne Bereiche.
    static let custom = AssetSection(id: "eigene", name: "Eigene", icon: "tag")

    /// Bereich der mitgelieferten Kategorien – für ältere Kataloge ohne Bereiche.
    static func defaultSectionID(forCategory id: String) -> String? {
        AssetCategory.defaults.first { $0.id == id }?.sectionID
    }
}

/// Kategorie im Asset-Baukasten – wie eine Kategorie der Prompt-Bausteine, nur mit Bildern.
struct AssetCategory: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var icon: String
    /// Bereich, in dem die Kategorie steht (ältere Kataloge kennen das Feld nicht).
    var sectionID: String?
    /// Wofür die Bilder als Referenz stehen (bestimmt Gemmas Beschreibung und den Satz im Prompt).
    var role: ReferenceRole
    var hint: String?
    /// Eigenes Thema auf Englisch, z. B. „hairstyle“ für „Frisuren“ – ersetzt die Rolle in Gemmas
    /// Beschreibung und im Prompt (wie der englische Satz eines eigenen Bausteins).
    var subject: String?

    static let defaults: [AssetCategory] = [
        AssetCategory(id: "kleidung", name: "Kleidung", icon: "tshirt", sectionID: "mode", role: .outfit, hint: "Oberteile, Kleider, Jacken, ganze Outfits"),
        AssetCategory(id: "schuhe", name: "Schuhe", icon: "shoe", sectionID: "mode", role: .footwear, hint: "Sneaker, Stiefel, Pumps …"),
        AssetCategory(id: "accessoires", name: "Accessoires", icon: "eyeglasses", sectionID: "mode", role: .accessory, hint: "Taschen, Schmuck, Brillen, Hüte"),
        AssetCategory(id: "orte", name: "Orte", icon: "mountain.2", sectionID: "orte-dinge", role: .location, hint: "Räume, Straßen, Landschaften"),
        AssetCategory(id: "objekte", name: "Objekte & Produkte", icon: "shippingbox", sectionID: "orte-dinge", role: .object, hint: "Produkte, Requisiten, Fahrzeuge"),
        AssetCategory(id: "posen", name: "Posen", icon: "figure.wave", sectionID: "pose-stil", role: .pose, hint: "Körperhaltungen und Gesten"),
        AssetCategory(id: "stile", name: "Stile & Looks", icon: "paintpalette", sectionID: "pose-stil", role: .style, hint: "Farbstimmung, Licht, Filmlook"),
        AssetCategory(id: "gesamt", name: "Gesamtreferenzen", icon: "photo.stack", sectionID: "referenzen", role: .general, hint: "Ganze Bilder, die du oft als Referenz nimmst"),
    ]

    /// Symbole zur Auswahl für eigene Kategorien.
    static let symbols = [
        "tshirt", "shoe", "eyeglasses", "bag", "crown", "mountain.2", "building.2", "sofa", "tree", "car",
        "shippingbox", "cup.and.saucer", "figure.wave", "paintpalette", "camera.filters", "sparkles", "photo.stack", "tag",
    ]
}

extension AssetCategory {
    /// Eigenes Thema, falls gesetzt.
    var customSubject: String? {
        let text = subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Was die Bilder zeigen – für Gemma.
    var englishName: String { customSubject ?? role.englishName }

    /// Satz, wenn das Bild selbst als „Picture n“ an Draw Things geht.
    static func referenceSentence(subject: String, imageNumber n: Int) -> String {
        "Picture \(n) shows the \(subject) – use exactly this \(subject) with all its shapes, colors and details."
    }

    /// Satz, wenn nur Gemmas Beschreibung in den Prompt kommt.
    static func descriptionSentence(subject: String, description: String) -> String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return subject.prefix(1).uppercased() + subject.dropFirst() + ": " + text
    }

    func descriptionSentence(_ description: String) -> String {
        customSubject.map { Self.descriptionSentence(subject: $0, description: description) } ?? role.sentence(description: description)
    }

    func editSentence(_ description: String) -> String {
        guard let subject = customSubject else { return role.editSentence(description: description) }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "" : "Change the \(subject) to this: \(text)"
    }

    /// Anweisung an Gemma zum Beschreiben eines Bildes dieser Kategorie.
    @MainActor
    var describeInstruction: String {
        customSubject.map(PromptTemplates.reference(subject:)) ?? PromptTemplates.reference(role)
    }
}

/// Ein Bild im Asset-Baukasten – z. B. eine Jacke, ein Paar Schuhe, ein Ort.
struct Asset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var categoryID: String
    /// Pfad relativ zu `Assets/` in der Bibliothek.
    var fileName: String
    var width: Int
    var height: Int
    /// Gemmas Beschreibung (englisch) – Text-Anker im Prompt, wenn das Bild selbst nicht an Draw Things geht.
    var description = ""
    var createdAt = Date()
    /// Wie oft es als Referenz oder Baustein benutzt wurde – häufige stehen vorne.
    var useCount = 0
    var lastUsedAt: Date?

    var aspect: Double { Double(max(width, 1)) / Double(max(height, 1)) }
}

/// Alle Assets einer Bibliothek – `Katalog/assets.json` und die Bilder in `Assets/<Kategorie>/`.
@MainActor
@Observable
final class AssetStore {
    private(set) var sections: [AssetSection] = AssetSection.defaults
    /// In Reihenfolge – innerhalb eines Bereichs gilt die Reihenfolge dieser Liste.
    private(set) var categories: [AssetCategory] = AssetCategory.defaults
    private(set) var assets: [Asset] = []
    /// Asset, das gerade im Inspector steht.
    var selectedID: UUID?
    /// Kategorie, deren Name in der Seitenleiste gerade bearbeitet wird.
    var renamingCategoryID: String?
    /// Bereich, dessen Name in der Seitenleiste gerade bearbeitet wird.
    var renamingSectionID: String?
    /// Assets, die gerade kopiert werden.
    private(set) var importing = 0
    /// Assets, die Gemma gerade beschreibt oder noch beschreiben soll.
    var describing: Set<UUID> = []
    /// Kategorien, für die Gemma gerade das englische Thema vorschlägt.
    var suggestingSubjectIDs: Set<String> = []

    let root: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isClosed = false

    init(root: URL) {
        self.root = root.standardizedFileURL
        load()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    // MARK: Abfragen

    func asset(_ id: UUID) -> Asset? {
        assets.first { $0.id == id }
    }

    func category(_ id: String) -> AssetCategory? {
        categories.first { $0.id == id }
    }

    /// Assets einer Kategorie – oft benutzte zuerst, sonst die neuesten.
    func assets(in categoryID: String?) -> [Asset] {
        assets
            .filter { categoryID == nil || $0.categoryID == categoryID }
            .sorted { ($0.useCount, $0.createdAt) > ($1.useCount, $1.createdAt) }
    }

    func count(in categoryID: String) -> Int {
        assets.lazy.filter { $0.categoryID == categoryID }.count
    }

    nonisolated static func url(for asset: Asset) -> URL {
        Library.assetsFolder.appending(path: asset.fileName)
    }

    // MARK: Hinzufügen

    /// Bilddatei übernehmen – als Kopie in der Bibliothek, in voller Qualität.
    func add(fileAt source: URL, to categoryID: String) async -> Asset? {
        importing += 1
        defer { importing -= 1 }
        let id = UUID()
        let ext = source.pathExtension.lowercased()
        let name = source.deletingPathExtension().lastPathComponent
        let relative = "\(categoryID)/\(id.uuidString).\(GalleryMedia.imageExtensions.contains(ext) ? ext : "png")"
        let target = Library.assetsFolder.appending(path: relative)
        let result = await Task.detached(priority: .userInitiated) { () -> CGSize? in
            guard Library.ensure(target.deletingLastPathComponent()) else { return nil }
            if GalleryMedia.imageExtensions.contains(ext) {
                guard (try? FileManager.default.copyItem(at: source, to: target)) != nil,
                      let size = ImageTools.pixelSize(of: target) else { return nil }
                return size
            }
            guard let image = ImageTools.image(from: source), let data = ImageTools.pngData(image),
                  (try? data.write(to: target)) != nil else { return nil }
            return CGSize(width: image.width, height: image.height)
        }.value
        guard let size = result else { return nil }
        return insert(Asset(id: id, name: Self.cleanName(name), categoryID: categoryID, fileName: relative, width: Int(size.width), height: Int(size.height)))
    }

    /// Bild ohne Datei (Zwischenablage, aus einer anderen App gezogen) übernehmen.
    func add(image: CGImage, name: String, to categoryID: String) async -> Asset? {
        importing += 1
        defer { importing -= 1 }
        let id = UUID()
        let relative = "\(categoryID)/\(id.uuidString).png"
        let target = Library.assetsFolder.appending(path: relative)
        let saved = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard Library.ensure(target.deletingLastPathComponent()), let data = ImageTools.pngData(image) else { return false }
            return (try? data.write(to: target)) != nil
        }.value
        guard saved else { return nil }
        return insert(Asset(id: id, name: name, categoryID: categoryID, fileName: relative, width: image.width, height: image.height))
    }

    private func insert(_ asset: Asset) -> Asset {
        assets.append(asset)
        scheduleSave()
        return asset
    }

    /// Dateiname als Name – Unterstriche werden zu Leerzeichen.
    private static func cleanName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Asset" : cleaned
    }

    // MARK: Ändern

    func update(_ id: UUID, _ change: (inout Asset) -> Void) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        change(&assets[index])
        scheduleSave()
    }

    func markUsed(_ id: UUID) {
        update(id) { asset in
            asset.useCount += 1
            asset.lastUsedAt = .now
        }
    }

    func delete(_ ids: [UUID]) {
        let removed = assets.filter { ids.contains($0.id) }
        for asset in removed {
            try? FileManager.default.removeItem(at: Self.url(for: asset))
            AssetImages.forget(asset.id)
        }
        assets.removeAll { ids.contains($0.id) }
        if let selected = selectedID, ids.contains(selected) { selectedID = nil }
        scheduleSave()
    }

    // MARK: Bereiche

    func section(_ id: String) -> AssetSection? {
        sections.first { $0.id == id }
    }

    /// Kategorien eines Bereichs in ihrer Reihenfolge.
    func categories(in sectionID: String) -> [AssetCategory] {
        categories.filter { $0.sectionID == sectionID }
    }

    func count(inSection sectionID: String) -> Int {
        let ids = Set(categories(in: sectionID).map(\.id))
        return assets.lazy.filter { ids.contains($0.categoryID) }.count
    }

    @discardableResult
    func addSection(name: String = "Neuer Bereich") -> String {
        let id = "bereich-" + UUID().uuidString.prefix(8).lowercased()
        sections.append(AssetSection(id: id, name: unique(name, among: sections.map(\.name)), icon: "folder"))
        renamingSectionID = id
        scheduleSave()
        return id
    }

    func updateSection(_ id: String, _ change: (inout AssetSection) -> Void) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        change(&sections[index])
        scheduleSave()
    }

    /// Bereich löschen – seine Kategorien (mit allen Assets) wandern in den ersten anderen Bereich.
    func deleteSection(_ id: String) {
        guard sections.count > 1, let fallback = sections.first(where: { $0.id != id }) else { return }
        for index in categories.indices where categories[index].sectionID == id {
            categories[index].sectionID = fallback.id
        }
        sections.removeAll { $0.id == id }
        scheduleSave()
    }

    func moveSections(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    // MARK: Kategorien

    @discardableResult
    func addCategory(name: String = "Neue Kategorie", role: ReferenceRole = .general, in sectionID: String? = nil) -> String {
        let id = "kategorie-" + UUID().uuidString.prefix(8).lowercased()
        let section = sectionID.flatMap { self.section($0) }?.id ?? sections.last?.id
        let category = AssetCategory(id: id, name: unique(name, among: categories.map(\.name)), icon: role.symbol, sectionID: section, role: role)
        // Hinter die letzte Kategorie des Bereichs, damit sie dort auch erscheint.
        if let last = categories.lastIndex(where: { $0.sectionID == section }) {
            categories.insert(category, at: last + 1)
        } else {
            categories.append(category)
        }
        renamingCategoryID = id
        scheduleSave()
        return id
    }

    private func unique(_ name: String, among names: [String]) -> String {
        var unique = name
        var number = 2
        while names.contains(unique) {
            unique = "\(name) \(number)"
            number += 1
        }
        return unique
    }

    /// Kategorie in einen anderen Bereich – ans Ende seiner Kategorien.
    func moveCategory(_ id: String, toSection sectionID: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }), section(sectionID) != nil,
              categories[index].sectionID != sectionID else { return }
        var category = categories.remove(at: index)
        category.sectionID = sectionID
        if let last = categories.lastIndex(where: { $0.sectionID == sectionID }) {
            categories.insert(category, at: last + 1)
        } else {
            categories.append(category)
        }
        scheduleSave()
    }

    func updateCategory(_ id: String, _ change: (inout AssetCategory) -> Void) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        change(&categories[index])
        scheduleSave()
    }

    /// Kategorie löschen – ihre Assets wandern in eine andere Kategorie, bevorzugt im selben Bereich (nichts geht verloren).
    func deleteCategory(_ id: String) {
        let sectionID = category(id)?.sectionID
        guard categories.count > 1,
              let fallback = categories.first(where: { $0.id != id && $0.sectionID == sectionID }) ?? categories.first(where: { $0.id != id })
        else { return }
        for index in assets.indices where assets[index].categoryID == id {
            assets[index].categoryID = fallback.id
        }
        categories.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Umsortieren innerhalb eines Bereichs (Indizes beziehen sich auf `categories(in:)`).
    func moveCategories(in sectionID: String, from source: IndexSet, to destination: Int) {
        var subset = categories(in: sectionID)
        subset.move(fromOffsets: source, toOffset: destination)
        var iterator = subset.makeIterator()
        for index in categories.indices where categories[index].sectionID == sectionID {
            categories[index] = iterator.next() ?? categories[index]
        }
        scheduleSave()
    }

    // MARK: Sichern

    private struct Stored: Codable {
        var version = 2
        /// Version 1 kannte keine Bereiche.
        var sections: [AssetSection]?
        var categories: [AssetCategory]
        var assets: [Asset]
    }

    private var fileURL: URL { root.appending(path: "Katalog/assets.json") }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        categories = stored.categories.isEmpty ? AssetCategory.defaults : stored.categories
        sections = stored.sections ?? AssetSection.defaults
        if sections.isEmpty { sections = AssetSection.defaults }
        // Kategorien ohne (gültigen) Bereich zuordnen: mitgelieferte an ihren Stammplatz, eigene nach „Eigene“.
        let known = Set(sections.map(\.id))
        for index in categories.indices where categories[index].sectionID.map(known.contains) != true {
            if let home = AssetSection.defaultSectionID(forCategory: categories[index].id), known.contains(home) {
                categories[index].sectionID = home
            } else {
                if section(AssetSection.custom.id) == nil { sections.append(AssetSection.custom) }
                categories[index].sectionID = AssetSection.custom.id
            }
        }
        assets = stored.assets
    }

    private func scheduleSave() {
        guard !isClosed else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func save() {
        // Ohne Assets und ohne geänderte Kategorien gibt es nichts zu sichern – keine leere Datei anlegen.
        guard !isClosed,
              !(assets.isEmpty && categories == AssetCategory.defaults && sections == AssetSection.defaults
                && !FileManager.default.fileExists(atPath: fileURL.path)),
              Library.ensure(fileURL.deletingLastPathComponent(), in: root) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Stored(sections: sections, categories: categories, assets: assets)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func close(saving: Bool = true) {
        saveTask?.cancel()
        if saving { save() }
        isClosed = true
    }
}

/// Bilder der Assets – im Hintergrund geladen und zwischengespeichert.
enum AssetImages {
    private static let images: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 24
        return cache
    }()

    private static let thumbnails: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 400
        return cache
    }()

    static func cachedThumbnail(_ asset: Asset) -> CGImage? {
        thumbnails.object(forKey: asset.id.uuidString as NSString)
    }

    static func image(_ asset: Asset) async -> CGImage? {
        let key = asset.id.uuidString as NSString
        if let cached = images.object(forKey: key) { return cached }
        let url = AssetStore.url(for: asset)
        let image = await Task.detached(priority: .userInitiated) { ImageTools.image(from: url) }.value
        if let image { images.setObject(image, forKey: key) }
        return image
    }

    static func thumbnail(_ asset: Asset) async -> CGImage? {
        let key = asset.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let url = AssetStore.url(for: asset)
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    static func forget(_ id: UUID) {
        images.removeObject(forKey: id.uuidString as NSString)
        thumbnails.removeObject(forKey: id.uuidString as NSString)
    }

    static func forgetAll() {
        images.removeAllObjects()
        thumbnails.removeAllObjects()
    }
}
