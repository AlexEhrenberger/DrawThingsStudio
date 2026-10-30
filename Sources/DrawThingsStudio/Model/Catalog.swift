import AppKit
import Observation

/// Bausteine des Prompt Builders. Standard: Resources/Catalog.json (Basis ThePromptEngineer,
/// erweitert). Eigene Änderungen liegen in der Bibliothek (`Katalog/building-blocks.json`) –
/// jede neue Bibliothek beginnt mit dem mitgelieferten Stand.
struct Catalog: Codable {
    var version: Int?
    var sections: [CatalogSection]
    var order: [String]
    var text: TextCatalog

    /// Der aktuell gültige Katalog (inklusive eigener Änderungen).
    @MainActor static var shared: Catalog { CatalogStore.shared.catalog }

    func group(_ key: String) -> CatalogGroup? {
        for section in sections {
            if let group = section.groups.first(where: { $0.key == key }) { return group }
        }
        return EditCatalog.groups.first { $0.key == key }
    }

    func section(_ id: String) -> CatalogSection? {
        sections.first { $0.id == id }
    }
}

struct CatalogSection: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var icon: String
    var groups: [CatalogGroup]
}

struct CatalogGroup: Codable, Identifiable, Hashable {
    var key: String
    var name: String
    var icon: String
    var multi: Bool
    /// Kurze Erklärung unter dem Namen.
    var hint: String?
    /// Satzvorlage, „{}“ wird durch die gewählten Bausteine ersetzt (z. B. bei Stilen).
    var template: String?
    /// Satzvorlage im Modus „Bearbeiten“ (z. B. „Restyle the whole image as {} …“).
    var editTemplate: String?
    var options: [CatalogOption]

    var id: String { key }
}

struct CatalogOption: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var text: String
}

struct TextCatalog: Codable {
    var groups: [TextGroup]
    var positions: [TextOption]

    func option(_ group: String, _ id: String?) -> TextOption? {
        guard let id else { return nil }
        return groups.first { $0.id == group }?.options.first { $0.id == id }
    }
}

struct TextGroup: Codable, Identifiable {
    var id: String
    var name: String
    var options: [TextOption]
}

struct TextOption: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var text: String
    var swatch: String?
}

/// Lädt, speichert und bearbeitet den Katalog.
@MainActor
@Observable
final class CatalogStore {
    static let shared = CatalogStore()

    private(set) var catalog: Catalog
    private(set) var isCustomized: Bool
    /// Bausteine, für die Gemma gerade den englischen Satz schreibt.
    var pendingOptionIDs: Set<String> = []
    /// Reihenfolge der Sätze im Prompt – wird bei jeder Änderung neu berechnet.
    private(set) var promptOrder: [String] = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Noch nicht geschriebener Stand – wird beim Wechsel der Bibliothek sofort gesichert.
    @ObservationIgnored private var pending: (catalog: Catalog, url: URL)?
    @ObservationIgnored var onChange: (() -> Void)?

    /// Datei der geöffneten Bibliothek (nil = noch keine geöffnet).
    private(set) var fileURL: URL?

    private init() {
        catalog = Self.loadDefault()
        isCustomized = false
        promptOrder = Self.computeOrder(catalog)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// Bausteine einer Bibliothek laden – ohne eigene Datei der mitgelieferte Stand.
    func open(root: URL) {
        flush()
        let url = root.appending(path: "Katalog/building-blocks.json")
        fileURL = url
        pendingOptionIDs = []
        if let data = try? Data(contentsOf: url), let custom = try? JSONDecoder().decode(Catalog.self, from: data) {
            catalog = custom
            isCustomized = true
        } else {
            catalog = Self.loadDefault()
            isCustomized = false
        }
        promptOrder = Self.computeOrder(catalog)
        onChange?()
    }

    /// Bibliothek wird gewechselt oder gelöscht: offene Änderungen sichern (oder verwerfen), danach nichts mehr schreiben.
    func close(saving: Bool) {
        if saving { flush() } else { saveTask?.cancel(); pending = nil }
        fileURL = nil
    }

    static func loadDefault() -> Catalog {
        let candidates = [
            Bundle.main.url(forResource: "Catalog", withExtension: "json"),
            // Beim Start per `swift run` liegt die Datei noch im Projektordner.
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Resources/Catalog.json"),
        ]
        for case let url? in candidates {
            if let data = try? Data(contentsOf: url),
               let catalog = try? JSONDecoder().decode(Catalog.self, from: data) {
                return catalog
            }
        }
        return Catalog(version: nil, sections: [], order: [], text: TextCatalog(groups: [], positions: []))
    }

    // MARK: Ändern & Sichern

    func update(_ change: (inout Catalog) -> Void) {
        change(&catalog)
        isCustomized = true
        promptOrder = Self.computeOrder(catalog)
        scheduleSave()
        onChange?()
    }

    func resetToDefault() {
        saveTask?.cancel()
        pending = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        catalog = Self.loadDefault()
        isCustomized = false
        promptOrder = Self.computeOrder(catalog)
        onChange?()
    }

    private func scheduleSave() {
        guard let fileURL else { return }
        pending = (catalog, fileURL)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        guard let (snapshot, url) = pending else { return }
        pending = nil
        let root = url.deletingLastPathComponent().deletingLastPathComponent()
        guard Library.ensure(url.deletingLastPathComponent(), in: root) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: Bereiche, Kategorien, Bausteine

    private static func newID(_ prefix: String) -> String {
        prefix + "-" + UUID().uuidString.prefix(8).lowercased()
    }

    @discardableResult
    func addSection(name: String) -> String {
        let id = Self.newID("bereich")
        update { $0.sections.append(CatalogSection(id: id, name: name, icon: "folder", groups: [])) }
        return id
    }

    @discardableResult
    func addGroup(to sectionID: String, name: String) -> String? {
        guard let index = catalog.sections.firstIndex(where: { $0.id == sectionID }) else { return nil }
        let key = "\(sectionID)/" + Self.newID("kategorie")
        update { $0.sections[index].groups.append(CatalogGroup(key: key, name: name, icon: "tag", multi: false, options: [])) }
        return key
    }

    @discardableResult
    func addOption(to key: String, name: String, text: String) -> String? {
        guard let (s, g) = indices(of: key) else { return nil }
        let id = Self.newID("eigen")
        update { $0.sections[s].groups[g].options.append(CatalogOption(id: id, name: name, text: text)) }
        return id
    }

    func updateSection(_ id: String, _ change: (inout CatalogSection) -> Void) {
        guard let index = catalog.sections.firstIndex(where: { $0.id == id }) else { return }
        update { change(&$0.sections[index]) }
    }

    func updateGroup(_ key: String, _ change: (inout CatalogGroup) -> Void) {
        guard let (s, g) = indices(of: key) else { return }
        update { change(&$0.sections[s].groups[g]) }
    }

    func updateOption(_ key: String, _ optionID: String, _ change: (inout CatalogOption) -> Void) {
        guard let (s, g) = indices(of: key),
              let o = catalog.sections[s].groups[g].options.firstIndex(where: { $0.id == optionID }) else { return }
        update { change(&$0.sections[s].groups[g].options[o]) }
    }

    func deleteSection(_ id: String) {
        update { $0.sections.removeAll { $0.id == id } }
    }

    func deleteGroup(_ key: String) {
        guard let (s, g) = indices(of: key) else { return }
        update { $0.sections[s].groups.remove(at: g) }
    }

    func deleteOption(_ key: String, _ optionID: String) {
        guard let (s, g) = indices(of: key) else { return }
        update { $0.sections[s].groups[g].options.removeAll { $0.id == optionID } }
    }

    func moveSections(from source: IndexSet, to destination: Int) {
        update { $0.sections.move(fromOffsets: source, toOffset: destination) }
    }

    func moveGroups(in sectionID: String, from source: IndexSet, to destination: Int) {
        guard let index = catalog.sections.firstIndex(where: { $0.id == sectionID }) else { return }
        update { $0.sections[index].groups.move(fromOffsets: source, toOffset: destination) }
    }

    func moveOptions(in key: String, from source: IndexSet, to destination: Int) {
        guard let (s, g) = indices(of: key) else { return }
        update { $0.sections[s].groups[g].options.move(fromOffsets: source, toOffset: destination) }
    }

    func sectionID(ofGroup key: String) -> String? {
        indices(of: key).map { catalog.sections[$0.0].id }
    }

    private func indices(of key: String) -> (Int, Int)? {
        for (s, section) in catalog.sections.enumerated() {
            if let g = section.groups.firstIndex(where: { $0.key == key }) { return (s, g) }
        }
        return nil
    }

    // MARK: Reihenfolge im Prompt

    /// Feste Reihenfolge aus dem Katalog; neue Kategorien landen hinter der letzten ihres Bereichs.
    /// Eigene Ergänzungen eines Bereichs („extra/…“) folgen jeweils auf dessen letzten Satz.
    private static func computeOrder(_ catalog: Catalog) -> [String] {
        let sectionOf = { (key: String) -> String in
            catalog.sections.first { $0.groups.contains { $0.key == key } }?.id ?? String(key.split(separator: "/").first ?? "")
        }
        var base = catalog.order.filter { catalog.group($0) != nil && !$0.hasPrefix("edit/") }
        for section in catalog.sections {
            for group in section.groups where !base.contains(group.key) {
                if let last = base.lastIndex(where: { sectionOf($0) == section.id }) {
                    base.insert(group.key, at: last + 1)
                } else {
                    base.append(group.key)
                }
            }
        }
        var lastIndex: [String: Int] = [:]
        for (index, key) in base.enumerated() { lastIndex[sectionOf(key)] = index }
        var result = ["assist/identity", "ref/1", "ref/2", "ref/3", "edit/aktion", "assets"]
        for (index, key) in base.enumerated() {
            result.append(key)
            let section = sectionOf(key)
            if lastIndex[section] == index { result.append("extra/\(section)") }
        }
        // Bereiche ohne Kategorien bekommen trotzdem einen Platz für eigene Ergänzungen.
        for section in catalog.sections where !result.contains("extra/\(section.id)") {
            result.append("extra/\(section.id)")
        }
        result += ["text", "edit/erhalten"]
        return result
    }
}

/// Bausteine, die nur beim Bearbeiten erscheinen. Qwen Image Edit 2511 versteht
/// Anweisungen („Replace …“, „Remove …“) besser als reine Bildbeschreibungen.
enum EditCatalog {
    static let actions = CatalogGroup(
        key: "edit/aktion", name: "Was soll passieren?", icon: "wand.and.stars", multi: true,
        options: [
            .init(id: "hintergrund", name: "Hintergrund ersetzen", text: "Replace the background with the setting described below, keeping the subject, its pose and the light on it unchanged."),
            .init(id: "entfernen", name: "Störendes entfernen", text: "Remove distracting objects and passers-by from the background and fill those areas naturally."),
            .init(id: "objekt", name: "Objekt hinzufügen", text: "Add the object described below at a natural position, matching the perspective, scale and lighting of the scene."),
            .init(id: "kleidung", name: "Outfit ändern", text: "Change only the clothing to the outfit described below, keeping the face, hair, body and pose unchanged."),
            .init(id: "pose", name: "Pose ändern", text: "Change the pose of the person to the pose described below, keeping identity, clothing and background unchanged."),
            .init(id: "ausdruck", name: "Ausdruck ändern", text: "Change the facial expression to the one described below, keeping the identity unchanged."),
            .init(id: "ansicht", name: "Kamera drehen", text: "Rotate the camera to the viewpoint described below while keeping the subject and the scene identical."),
            .init(id: "licht", name: "Neu beleuchten", text: "Relight the scene with the lighting described below, keeping all content and the composition unchanged."),
            .init(id: "stil", name: "Stil übertragen", text: "Restyle the whole image in the style described below, keeping the composition and the content."),
            .init(id: "freistellen", name: "Freistellen", text: "Isolate the subject on a clean, seamless white background."),
            .init(id: "restaurieren", name: "Restaurieren", text: "Restore the photo: remove scratches, dust and noise, recover faded colors and sharpen the details."),
            .init(id: "kolorieren", name: "Kolorieren", text: "Colorize the black-and-white photo with natural, realistic colors."),
            .init(id: "details", name: "Details verbessern", text: "Enhance the image with crisp, natural fine detail and clean textures without changing the content."),
            .init(id: "retusche", name: "Porträt-Retusche", text: "Retouch the portrait subtly: even skin tone with natural texture and brighter eyes."),
            .init(id: "winter", name: "Winter", text: "Turn the scene into winter with fresh snow on the ground and on all surfaces."),
            .init(id: "nacht", name: "Nacht", text: "Turn the scene into night, with the existing light sources glowing realistically."),
        ]
    )

    static let keep = CatalogGroup(
        key: "edit/erhalten", name: "Beibehalten", icon: "lock", multi: true,
        options: [
            .init(id: "identitaet", name: "Identität", text: "Keep the person's face, identity, hairstyle and body proportions exactly the same."),
            .init(id: "komposition", name: "Bildaufbau", text: "Keep the composition, framing and camera angle unchanged."),
            .init(id: "rest", name: "Alles andere", text: "Keep everything else unchanged."),
        ]
    )

    static let groups = [actions, keep]
}
