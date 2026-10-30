import AppKit
import Observation

/// Blickrichtung auf einem Charakterfoto – aus Sicht des Betrachters.
enum PersonaView: String, Codable, CaseIterable, Identifiable {
    case front
    case threeQuarterLeft
    case threeQuarterRight
    case profileLeft
    case profileRight
    case body

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Frontal"
        case .threeQuarterLeft: "¾ nach links"
        case .threeQuarterRight: "¾ nach rechts"
        case .profileLeft: "Profil nach links"
        case .profileRight: "Profil nach rechts"
        case .body: "Ganzkörper"
        }
    }

    var symbol: String {
        switch self {
        case .front: "person.crop.square"
        case .threeQuarterLeft, .profileLeft: "arrow.turn.up.left"
        case .threeQuarterRight, .profileRight: "arrow.turn.up.right"
        case .body: "figure.stand"
        }
    }

    /// Kopfdrehung (Vision, Grad: negativ = zum linken Bildrand) → Ansicht.
    static func from(yaw: Double) -> PersonaView {
        switch yaw {
        case ..<(-55): .profileLeft
        case ..<(-18): .threeQuarterLeft
        case ...18: .front
        case ...55: .threeQuarterRight
        default: .profileRight
        }
    }

    /// Reihenfolge für die kleinen Felder des Rasters.
    var sheetPriority: Int {
        switch self {
        case .front: 0
        case .threeQuarterLeft: 1
        case .threeQuarterRight: 2
        case .profileLeft: 3
        case .profileRight: 4
        case .body: 5
        }
    }
}

/// Ein Foto eines Charakters. Die Datei liegt als Kopie in der Bibliothek (`Charaktere/<ID>/`).
struct PersonaPhoto: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileName: String
    var view: PersonaView
    /// Gesicht, normiert, Ursprung oben links (nil = keins gefunden).
    var face: CGRect?
    var addedAt = Date()
}

/// Was als Referenz an Draw Things geht.
enum PersonaReferenceMode: String, Codable, CaseIterable, Identifiable {
    /// Raster aus mehreren Ansichten in einem Bild.
    case sheet
    /// Nur das beste Frontalfoto (Kopf und Schultern).
    case single

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sheet: "Raster"
        case .single: "Einzelfoto"
        }
    }
}

extension PersonaReferenceMode {
    /// Satz für den Prompt, wenn das Referenzbild als „Picture n“ an Draw Things geht.
    @MainActor
    func sentence(imageNumber n: Int, description: String) -> String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = text.isEmpty ? "" : " The person: \(PromptBuilder.withPeriod(text))"
        switch self {
        case .sheet:
            return "Picture \(n) is a character reference sheet that shows one and the same person from several angles. "
                + "Create one single photograph of exactly this person and keep the face, facial features, hairstyle and skin tone exactly consistent with the sheet – one single image, not a collage or grid."
                + anchor
        case .single:
            return ReferenceRole.identity.sentence(imageNumber: n) + anchor
        }
    }
}

/// Eine Person, von der es Fotos aus mehreren Blickwinkeln gibt – für konsistente Bilder mit Qwen Image Edit.
struct Persona: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var photos: [PersonaPhoto] = []
    /// Gemmas Beschreibung des Aussehens (englisch, für den Prompt) – bearbeitbar.
    var description = ""
    var referenceMode: PersonaReferenceMode = .sheet
    /// Einverständnis der Person für Fotos und generierte Bilder.
    var hasConsent = false
    var consentNote = ""

    /// Bestes Frontalfoto: frontal mit Gesicht, sonst irgendein Foto mit Gesicht.
    var mainPhoto: PersonaPhoto? {
        photos.first { $0.view == .front && $0.face != nil }
            ?? photos.filter { $0.face != nil }.min { $0.view.sheetPriority < $1.view.sheetPriority }
            ?? photos.first
    }
}

/// Alle Charaktere einer Bibliothek – `Katalog/characters.json` und die Fotos in `Charaktere/<ID>/`,
/// dazu die Szene für den Charaktertest in `Katalog/character-test.json`.
@MainActor
@Observable
final class PersonaStore {
    private(set) var personas: [Persona] = []
    /// Szene für den Test Raster gegen Einzelfoto – gehört zur Bibliothek wie die Charaktere selbst.
    /// Eigene Datei und eigenes Sichern – Tippen hier schreibt `characters.json` nicht neu.
    var testScene = PersonaStore.defaultTestScene {
        didSet { if testScene != oldValue, !isLoading { scheduleTestSceneSave() } }
    }
    static let defaultTestScene = "sitzt lächelnd an einem Cafétisch am Fenster, Halbtotale, weiches Tageslicht"
    /// Die Bibliothek hat schon eine eigene Szene (sonst gilt die Vorgabe).
    private(set) var hasStoredTestScene = false
    /// Charakter, dessen Name in der Seitenleiste gerade bearbeitet wird.
    var renamingID: UUID?
    /// Fotos, die gerade eingelesen werden (Gesichtserkennung läuft).
    private(set) var importing: Set<UUID> = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var testSceneSaveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoading = false
    /// Ordner der Bibliothek, zu der diese Charaktere gehören.
    let root: URL
    @ObservationIgnored private var isClosed = false

    init(root: URL) {
        self.root = root.standardizedFileURL
        load()
        // Eine noch ausstehende Sicherung nicht verlieren.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.save()
                self?.flushTestScene()
            }
        }
    }

    func persona(_ id: UUID) -> Persona? {
        personas.first { $0.id == id }
    }

    // MARK: Anlegen & Ändern

    @discardableResult
    func create(name: String = "Neuer Charakter") -> UUID {
        var unique = name
        var number = 2
        while personas.contains(where: { $0.name == unique }) {
            unique = "\(name) \(number)"
            number += 1
        }
        let persona = Persona(name: unique)
        personas.append(persona)
        renamingID = persona.id
        scheduleSave()
        return persona.id
    }

    func update(_ id: UUID, _ change: (inout Persona) -> Void) {
        guard let index = personas.firstIndex(where: { $0.id == id }) else { return }
        change(&personas[index])
        scheduleSave()
    }

    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update(id) { $0.name = name }
    }

    func delete(_ id: UUID) {
        personas.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.folder(for: id))
        PersonaImages.forget(personaID: id)
        scheduleSave()
    }

    // MARK: Fotos

    /// Foto übernehmen: verkleinert kopieren, Gesicht suchen und die Ansicht vorschlagen.
    func addPhoto(_ image: CGImage, to personaID: UUID) async {
        guard persona(personaID) != nil else { return }
        let photoID = UUID()
        importing.insert(photoID)
        defer { importing.remove(photoID) }
        let fileName = "\(photoID.uuidString).jpg"
        let url = Self.folder(for: personaID).appending(path: fileName)
        let analysis = await Task.detached(priority: .userInitiated) { () -> (CGRect?, PersonaView)? in
            let small = ImageTools.scaled(image, maxSide: 2048)
            guard let data = ImageTools.jpegData(small, quality: 0.92), Library.ensure(url.deletingLastPathComponent()) else { return nil }
            guard (try? data.write(to: url)) != nil else { return nil }
            let face = try? await VisionTools.mainFace(in: small)
            // Sehr kleines Gesicht im Bild: eine Ganzkörperaufnahme.
            guard let face, face.rect.height >= 0.09 else { return (face?.rect, .body) }
            return (face.rect, PersonaView.from(yaw: face.yaw))
        }.value
        guard let (face, view) = analysis else { return }
        let photo = PersonaPhoto(id: photoID, fileName: fileName, view: view, face: face)
        update(personaID) { $0.photos.append(photo) }
    }

    func removePhoto(_ photoID: UUID, from personaID: UUID) {
        guard let photo = persona(personaID)?.photos.first(where: { $0.id == photoID }) else { return }
        try? FileManager.default.removeItem(at: Self.url(for: photo, of: personaID))
        PersonaImages.forget(photoID: photoID)
        update(personaID) { $0.photos.removeAll { $0.id == photoID } }
    }

    func setView(_ view: PersonaView, of photoID: UUID, in personaID: UUID) {
        update(personaID) { persona in
            guard let index = persona.photos.firstIndex(where: { $0.id == photoID }) else { return }
            persona.photos[index].view = view
        }
    }

    // MARK: Ablage

    /// Fotos liegen in der Bibliothek unter `Charaktere/<ID>/`.
    nonisolated static func folder(for personaID: UUID) -> URL {
        Library.charactersFolder.appending(path: personaID.uuidString)
    }

    nonisolated static func url(for photo: PersonaPhoto, of personaID: UUID) -> URL {
        folder(for: personaID).appending(path: photo.fileName)
    }

    private var fileURL: URL { root.appending(path: "Katalog/characters.json") }
    private var testFileURL: URL { root.appending(path: "Katalog/character-test.json") }

    private struct TestSettings: Codable {
        var scene: String
    }

    private func load() {
        if let data = try? Data(contentsOf: testFileURL), let stored = try? JSONDecoder().decode(TestSettings.self, from: data) {
            isLoading = true
            testScene = stored.scene
            isLoading = false
            hasStoredTestScene = true
        }
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([Persona].self, from: data) else { return }
        personas = stored
    }

    /// Bis 12.10.2026 stand die Szene in den Einstellungen der App (für alle Bibliotheken) –
    /// sie zieht einmalig in die gerade geöffnete Bibliothek um.
    func adoptLegacyTestScene() {
        let key = "persona.testScene"
        guard let legacy = UserDefaults.standard.string(forKey: key) else { return }
        if !hasStoredTestScene, !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            testScene = legacy
            flushTestScene()
        }
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Bibliothek wird gewechselt oder gelöscht: letzter Stand sichern (optional), danach nichts mehr schreiben.
    func close(saving: Bool = true) {
        saveTask?.cancel()
        if saving {
            save()
            flushTestScene()
        }
        testSceneSaveTask?.cancel()
        testSceneSaveTask = nil
        isClosed = true
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
        guard !isClosed, Library.ensure(fileURL.deletingLastPathComponent(), in: root) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(personas) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func scheduleTestSceneSave() {
        guard !isClosed else { return }
        testSceneSaveTask?.cancel()
        testSceneSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            flushTestScene()
        }
    }

    /// Szene sichern, falls sich etwas getan hat.
    private func flushTestScene() {
        let pending = testSceneSaveTask != nil
        testSceneSaveTask?.cancel()
        testSceneSaveTask = nil
        guard pending || (!hasStoredTestScene && testScene != Self.defaultTestScene) else { return }
        guard !isClosed, Library.ensure(testFileURL.deletingLastPathComponent(), in: root) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(TestSettings(scene: testScene)) else { return }
        try? data.write(to: testFileURL, options: .atomic)
        hasStoredTestScene = true
    }
}
