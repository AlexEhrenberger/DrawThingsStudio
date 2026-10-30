import AppKit
import ImageIO
import Observation

/// Markierung wie in Lightroom: behalten (P), verwerfen (X) oder keine (U).
enum GalleryFlag: String, Codable {
    case none, pick, reject

    var title: String {
        switch self {
        case .none: "Ohne Markierung"
        case .pick: "Behalten"
        case .reject: "Verworfen"
        }
    }

    var symbol: String {
        switch self {
        case .none: "flag.slash"
        case .pick: "flag.fill"
        case .reject: "xmark.circle.fill"
        }
    }
}

/// Bild einer Serie: zu welchem Stapel es gehört und welchen Zustand der Variable es zeigt.
struct SeriesTag: Equatable {
    /// Stapel in der Galerie – zugleich die ID des Serien-Durchlaufs.
    let id: UUID
    let index: Int
    let value: String
    let title: String
    let symbol: String
    let sourceID: UUID?
    let prompt: String
    /// false = von Hand oder für einen Test gebildeter Stapel, keine Serie.
    var isSeries = true
}

/// Ein Bild oder Video in der Galerie: eine Datei in der Bibliothek plus alles, was die App dazu weiß.
struct GalleryItem: Identifiable, Codable, Equatable {
    /// Gleich der ID der Version im Studio – so bleiben Herkunft und Serien verknüpft.
    var id: UUID
    var path: String
    var createdAt: Date
    /// generate, edit, references, series, adjusted, transformed, imported
    var kind: String
    var prompt: String
    var seed: UInt32?
    var width: Int
    var height: Int
    var duration: TimeInterval?
    var parentID: UUID?
    var stackID: UUID?
    /// Platz in der Serie (1 … 4).
    var stackIndex: Int?
    /// Zustand der Variable, z. B. „Trenchcoat“.
    var label: String?
    var flag: GalleryFlag = .none
    var rating = 0
    /// Charaktere, die in das Bild eingeflossen sind (ältere Kataloge kennen das Feld nicht).
    var personaIDs: [UUID]?
    /// Länge eines Videos in Sekunden.
    var videoLength: Double?
    /// Freie Tags wie „Strand“ oder „Kampagne Herbst“ (ältere Kataloge kennen das Feld nicht).
    var tags: [String]?
    /// Wann das Bild in die Galerie kam (Import, Erzeugung, Einlesen) – ältere Kataloge kennen das Feld nicht.
    var addedAt: Date?

    /// Zeitpunkt für „Zuletzt hinzugefügt“; ohne Angabe gilt das Aufnahmedatum.
    var addedDate: Date { addedAt ?? createdAt }

    var url: URL { URL(fileURLWithPath: path) }
    var isVideo: Bool { GalleryMedia.videoExtensions.contains(url.pathExtension.lowercased()) }
    var size: CGSize { CGSize(width: width, height: height) }
    var aspect: Double { Double(max(width, 1)) / Double(max(height, 1)) }
    var source: ImageVersion.Source { ImageVersion.Source(fileKind: kind) }
}

/// Mehrere Bilder, die zusammengehören – eine Serie oder ein von Hand gebildeter Stapel.
struct GalleryStack: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    /// Name der Variable („Kleidung“) oder „Stapel“.
    var title: String
    var symbol: String
    var isSeries: Bool
    /// Ausgangsbild der Serie, falls es in der Galerie liegt.
    var sourceID: UUID?
    /// Prompt aus der Seitenleiste, der für alle Bilder galt.
    var prompt: String?
}

/// Was die Galerie gerade zeigt – links in der Seitenleiste gewählt.
enum GalleryCollection: Hashable {
    case all, series, picks, rated, rejected
    /// Bilder der letzten sieben Tage, die neu in die Galerie kamen (importiert, erzeugt, eingelesen).
    case recent
    /// Bilder ohne Charakter und ohne Tag – noch nirgends einsortiert.
    case unassigned
    /// Übersicht aller Notizen und To-dos statt des Rasters.
    case notes
    case project(UUID)
    /// Seite eines Charakters: Fotos, Raster, Bilder mit ihm.
    case persona(UUID)
    /// Asset-Baukasten: eine Kategorie (nil = alle).
    case assets(String?)
    /// Asset-Baukasten: alle Kategorien eines Bereichs.
    case assetSection(String)
    /// Story: Bilder in fester Reihenfolge – Storyboard, Präsentation und Video-Prompts.
    case story(UUID)

    /// Titel ohne Projektnamen – den kennt nur die Galerie (`Gallery.title(for:)`).
    var title: String {
        switch self {
        case .all: "Alle Bilder"
        case .recent: "Zuletzt hinzugefügt"
        case .unassigned: "Nicht zugeordnet"
        case .series: "Serien & Stapel"
        case .picks: "Behalten"
        case .rated: "Bewertet"
        case .rejected: "Verworfen"
        case .notes: "Notizen & To-dos"
        case .project: "Projekt"
        case .persona: "Charakter"
        case .assets, .assetSection: "Assets"
        case .story: "Story"
        }
    }

    /// Seiten des Asset-Baukastens.
    var isAssets: Bool {
        switch self {
        case .assets, .assetSection: true
        default: false
        }
    }

    /// Raster mit Leiste – nicht bei Notizen-Übersicht, Charakterseite, Assets und Story (eigene Seiten).
    var showsGrid: Bool {
        switch self {
        case .notes, .persona, .assets, .assetSection, .story: false
        default: true
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .recent: "clock.arrow.circlepath"
        case .unassigned: "questionmark.square.dashed"
        case .series: "square.stack"
        case .picks: "flag.fill"
        case .rated: "star.fill"
        case .rejected: "xmark.bin"
        case .notes: "checklist"
        case .project: "folder"
        case .persona: "person.crop.square"
        case .assets, .assetSection: "shippingbox"
        case .story: GalleryStory.symbol
        }
    }
}

/// Reiter auf der Seite eines Charakters.
enum PersonaTab: String, CaseIterable, Identifiable {
    /// Fotos, Referenz, Beschreibung, Test – den Charakter aufbauen.
    case character
    /// Alle Bilder und Videos mit ihm – Raster mit denselben Filtern wie „Alle Bilder“.
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .character: "Charakter"
        case .media: "Bilder & Videos"
        }
    }
}

/// Art einer Notiz zu einem Bild.
enum NoteKind: String, Codable, CaseIterable, Identifiable {
    case todo, like, dislike

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To-do"
        case .like: "Gefällt"
        case .dislike: "Gefällt nicht"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "checklist"
        case .like: "hand.thumbsup"
        case .dislike: "hand.thumbsdown"
        }
    }

    var placeholder: String {
        switch self {
        case .todo: "Was ist noch zu tun?"
        case .like: "Was gefällt dir?"
        case .dislike: "Was stört dich?"
        }
    }
}

/// Notiz zu einem Bild: Lob, Kritik oder ein To-do zum Abhaken.
struct GalleryNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var itemID: UUID
    var kind: NoteKind
    var text: String
    var createdAt = Date()
    var doneAt: Date?
    /// Bilder, die beim Umsetzen dieses To-dos im Studio entstanden sind.
    var resultIDs: [UUID] = []

    var isDone: Bool { doneAt != nil }
    var isOpenTodo: Bool { kind == .todo && doneAt == nil }
}

/// Projekt wie eine Sammlung in Lightroom – ein Bild kann in mehreren Projekten liegen.
struct GalleryProject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var itemIDs: [UUID] = []
}

/// Welche Notizen die Übersicht zeigt.
enum NotesFilter: String, CaseIterable, Identifiable {
    case open, done, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Offene To-dos"
        case .done: "Erledigt"
        case .all: "Alle Notizen"
        }
    }
}

/// Eine Kachel im Raster: ein einzelnes Bild oder ein Stapel.
enum GalleryEntry: Identifiable {
    case image(GalleryItem)
    case stack(GalleryStack, [GalleryItem])

    var id: UUID {
        switch self {
        case .image(let item): item.id
        case .stack(let stack, _): stack.id
        }
    }

    var items: [GalleryItem] {
        switch self {
        case .image(let item): [item]
        case .stack(_, let members): members
        }
    }

    /// Oberstes Bild: das erste behaltene, sonst das erste der Serie.
    var cover: GalleryItem {
        switch self {
        case .image(let item): item
        case .stack(_, let members): members.first { $0.flag == .pick } ?? members[0]
        }
    }

    /// Ein Stapel steht beim jüngsten seiner Bilder.
    var date: Date { items.map(\.createdAt).max() ?? .distantPast }

    /// Wie `date`, aber nach dem Zeitpunkt, zu dem die Bilder in die Galerie kamen.
    var addedDate: Date { items.map(\.addedDate).max() ?? .distantPast }
}

struct GallerySection: Identifiable {
    let day: Date
    let entries: [GalleryEntry]
    var id: Date { day }
    var imageCount: Int { entries.reduce(0) { $0 + $1.items.count } }
}

/// Filter über dem Raster – gelten in jeder Sammlung.
struct GalleryFilter: Equatable {
    var showImages = true
    var showVideos = true
    /// IDs aus `AspectRatio.all` und `GalleryFilter.freeAspect`.
    var aspects: Set<String> = []
    var personaIDs: Set<UUID> = []
    var tags: Set<String> = []
    /// true = nur Bilder mit allen gewählten Tags, sonst mit mindestens einem.
    var requiresAllTags = false

    static let freeAspect = "frei"

    var activeCount: Int {
        (showImages && showVideos ? 0 : 1) + (aspects.isEmpty ? 0 : 1) + (personaIDs.isEmpty ? 0 : 1) + (tags.isEmpty ? 0 : 1)
    }

    /// Nächstes Draw-Things-Format (±4,5 %), sonst „frei“. Verglichen wird auch mit den echten Pixelgrößen –
    /// 4:5 Klein ist 704 × 832, 1344 × 768 zählt noch als 16:9.
    nonisolated static func aspectKey(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return freeAspect }
        let value = Double(width) / Double(height)
        let closest = AspectRatio.closest(toRatio: value)
        return closest.distance(to: value) < 0.045 ? closest.id : freeAspect
    }
}

/// Vergleichsansicht für mehrere Bilder.
enum CompareMode: String, CaseIterable, Identifiable {
    case grid, zoom, flip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Raster"
        case .zoom: "Synchron-Zoom"
        case .flip: "Blättern"
        }
    }

    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .zoom: "plus.magnifyingglass"
        case .flip: "rectangle.on.rectangle"
        }
    }

    var key: Character {
        switch self {
        case .grid: "g"
        case .zoom: "z"
        case .flip: "b"
        }
    }
}

/// Geöffneter Stapel, Vergleich mehrerer Bilder oder ein einzelnes Bild groß (Lupe).
struct GalleryViewerState: Equatable {
    var itemIDs: [UUID]
    var stackID: UUID?
    /// Ausgangsbild der Serie, falls es in der Galerie liegt.
    var sourceID: UUID?
    var showSource = false
    /// Bild, auf dem Tastatur und Inspector gerade arbeiten.
    var index = 0
    /// Lupe: ein einzelnes Bild aus dem Raster – die Pfeiltasten blättern durch die ganze Galerie.
    var isLoupe = false

    var displayIDs: [UUID] {
        if showSource, let sourceID, !itemIDs.contains(sourceID) { return [sourceID] + itemIDs }
        return itemIDs
    }

    var currentID: UUID? {
        let ids = displayIDs
        return ids.indices.contains(index) ? ids[index] : ids.first
    }

    // MARK: Seiten

    /// Bilder je Seite – größere Stapel und Vergleiche werden durchgeblättert statt in ein winziges Raster gequetscht.
    static let pageSize = 9

    var pageCount: Int { max((displayIDs.count + Self.pageSize - 1) / Self.pageSize, 1) }

    /// Die Seite ergibt sich aus dem markierten Bild – so bleiben Pfeiltasten, Filmstreifen und Inspector ohne weitere Pflege stimmig.
    var page: Int {
        let position = displayIDs.indices.contains(index) ? index : 0
        return min(position / Self.pageSize, pageCount - 1)
    }

    var pageIDs: [UUID] {
        let ids = displayIDs
        let start = min(page * Self.pageSize, ids.count)
        return Array(ids[start..<min(start + Self.pageSize, ids.count)])
    }

    /// Auf eine Seite springen: markiert wird ihr erstes Bild.
    mutating func setPage(_ page: Int) {
        index = min(max(page, 0), pageCount - 1) * Self.pageSize
    }
}

/// Alle erzeugten Bilder – Lightrooms Katalog im Kleinen. Die Bilder selbst liegen im Ordner der Bibliothek,
/// hier steht, was dazugehört: Serie, Markierung, Bewertung.
@MainActor
@Observable
final class Gallery {
    /// Neueste zuerst.
    private(set) var items: [GalleryItem] = []
    private(set) var stacks: [UUID: GalleryStack] = [:]
    /// Bilder, deren Datei fehlt (z. B. im Finder gelöscht). Sie bleiben im Katalog, werden aber nicht gezeigt.
    private(set) var missing: Set<UUID> = []
    private(set) var isSyncing = false
    /// Notizen aller Bilder, älteste zuerst.
    var notes: [GalleryNote] = [] {
        didSet { notesByItem = Dictionary(grouping: notes, by: \.itemID) }
    }
    var projects: [GalleryProject] = [] {
        didSet { projectMembers = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, Set($0.itemIDs)) }) }
    }
    /// Stories: Bilder in fester Reihenfolge, dazu der Plan für Video-Prompts (siehe `Gallery+Stories`).
    var stories: [GalleryStory] = [] {
        didSet {
            // Beim Tippen in einem Prompt ändert sich nur der Video-Plan – die Mitglieder bleiben.
            if stories.map(\.itemIDs) != oldValue.map(\.itemIDs) || stories.map(\.id) != oldValue.map(\.id) {
                storyMembers = Dictionary(uniqueKeysWithValues: stories.map { ($0.id, Set($0.itemIDs)) })
            }
        }
    }
    /// Neue Bilder landen automatisch in diesem Projekt (steht im Katalog der Bibliothek).
    var activeProjectID: UUID? {
        didSet { if activeProjectID != oldValue { scheduleSave() } }
    }
    /// To-do, das gerade im Studio umgesetzt wird – neue Bilder daraus hängen sich an.
    var workingTodoID: UUID?

    // MARK: Oberfläche

    var collection: GalleryCollection = .all {
        didSet {
            guard collection != oldValue else { return }
            selection = []
            viewer = nil
        }
    }
    /// Reiter der Charakterseite – bleibt beim Wechsel zwischen Charakteren stehen.
    var personaTab: PersonaTab = .character {
        didSet { if personaTab != oldValue { selection = [] } }
    }
    var searchText = ""
    /// Nur Bilder ab so vielen Sternen.
    var minRating = 0
    var filter = GalleryFilter()
    /// Kachel unter dem Mauszeiger – beim Pinch-Zoom bleibt sie stehen.
    @ObservationIgnored var hoveredEntryID: UUID?
    /// IDs von Bildern oder Stapeln.
    var selection: Set<UUID> = []
    @ObservationIgnored var selectionAnchor: UUID?
    var viewer: GalleryViewerState?
    /// Bilder, für die gerade „In den Papierkorb?“ gefragt wird.
    var trashRequest: [UUID]?
    var notesFilter: NotesFilter = .open
    /// Übersicht der Notizen auf ein Projekt beschränken.
    var notesProjectID: UUID?
    /// Hochzählen, damit der Inspector das Notizfeld fokussiert (Taste N).
    var noteFieldRequest = 0
    /// Der Inspector soll das Tag-Feld fokussieren (Taste T, „Neues Tag …“) – er setzt es danach zurück.
    var wantsTagField = false
    /// Projekt, dessen Name in der Seitenleiste gerade bearbeitet wird.
    var renamingProjectID: UUID?
    /// Story, deren Name in der Seitenleiste gerade bearbeitet wird.
    var renamingStoryID: UUID?
    /// Was gerade aus dem Raster gezogen wird (Datei des gezogenen Bildes und alle betroffenen Bilder) –
    /// für das Ablegen auf einem Projekt.
    @ObservationIgnored var drag: (path: String, ids: [UUID])?
    private(set) var notesByItem: [UUID: [GalleryNote]] = [:]
    private(set) var projectMembers: [UUID: Set<UUID>] = [:]
    private(set) var storyMembers: [UUID: Set<UUID>] = [:]
    /// Kachel, zu der das Raster nach dem Schließen des Vergleichs zurückscrollt.
    var lastViewedEntryID: UUID?

    var thumbnailSize: Double {
        didSet { UserDefaults.standard.set(thumbnailSize, forKey: "gallery.thumbnailSize") }
    }
    /// Tagesüberschriften im Raster. Ausgeblendet liegen alle Kacheln ohne Lücken hintereinander.
    var showsDates: Bool {
        didSet { UserDefaults.standard.set(showsDates, forKey: "gallery.showsDates") }
    }
    /// Ein Stapel öffnet immer im Raster – aufgefächert nebeneinander.
    var compareMode: CompareMode = .grid

    @ObservationIgnored private var indexByID: [UUID: Int] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Ordner der Bibliothek, zu der dieser Katalog gehört.
    let root: URL
    /// Nach dem Wechsel der Bibliothek: nichts mehr sichern.
    @ObservationIgnored private var isClosed = false
    /// Dateien, die aus dieser Bibliothek in den Papierkorb gewandert sind – beim Löschen der Bibliothek
    /// werden sie dort mit entfernt.
    @ObservationIgnored private(set) var trashedFiles: [String] = []

    init(root: URL) {
        self.root = root.standardizedFileURL
        let defaults = UserDefaults.standard
        thumbnailSize = defaults.object(forKey: "gallery.thumbnailSize") as? Double ?? 200
        showsDates = defaults.object(forKey: "gallery.showsDates") as? Bool ?? true
        load()
        // Eine noch ausstehende Sicherung nicht verlieren.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    // MARK: Abfragen

    func item(_ id: UUID) -> GalleryItem? {
        indexByID[id].map { items[$0] }
    }

    var visibleItems: [GalleryItem] { items.filter { !missing.contains($0.id) } }

    /// Raster mit Leiste – auch auf der Charakterseite im Reiter „Bilder & Videos“.
    var showsGrid: Bool {
        if case .persona = collection { return personaTab == .media }
        return collection.showsGrid
    }

    /// Markierte Bilder: in der Lupe oder im Stapel das aktuelle, sonst die Rasterauswahl in Rasterreihenfolge
    /// (bei Stapeln das Deckbild). Videos und fehlende Dateien zählen nicht.
    var markedItems: [GalleryItem] {
        let candidates: [GalleryItem]
        if let id = viewer?.currentID {
            candidates = item(id).map { [$0] } ?? []
        } else {
            candidates = entries.filter { selection.contains($0.id) }.map(\.cover)
        }
        return candidates.filter { !$0.isVideo && !missing.contains($0.id) }
    }

    /// Alle Bilder eines Stapels in Serien-Reihenfolge.
    func members(of stackID: UUID) -> [GalleryItem] {
        items.filter { $0.stackID == stackID && !missing.contains($0.id) }.sorted(by: Self.stackOrder)
    }

    nonisolated static func stackOrder(_ a: GalleryItem, _ b: GalleryItem) -> Bool {
        let ia = a.stackIndex ?? .max, ib = b.stackIndex ?? .max
        return ia != ib ? ia < ib : a.createdAt < b.createdAt
    }

    private func matches(_ item: GalleryItem, search: String) -> Bool {
        guard !missing.contains(item.id) else { return false }
        switch collection {
        case .all: break
        case .recent: if !isRecent(item) { return false }
        case .unassigned: if !isUnassigned(item) { return false }
        case .series: if item.stackID == nil { return false }
        case .picks: if item.flag != .pick { return false }
        case .rated: if item.rating == 0 { return false }
        case .rejected: if item.flag != .reject { return false }
        case .notes: if notesByItem[item.id]?.isEmpty ?? true { return false }
        case .project(let id): if projectMembers[id]?.contains(item.id) != true { return false }
        case .persona(let id): if item.personaIDs?.contains(id) != true { return false }
        case .assets, .assetSection: return false
        case .story(let id): if storyMembers[id]?.contains(item.id) != true { return false }
        }
        if minRating > 0 && item.rating < minRating { return false }
        if !passesFilter(item) { return false }
        if !search.isEmpty {
            let noteText = notesByItem[item.id]?.map(\.text) ?? []
            let haystack = ([item.prompt, item.label ?? "", item.stackID.flatMap { stacks[$0]?.title } ?? ""] + noteText + (item.tags ?? []))
                .joined(separator: " ")
            let words = search.split(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return true
    }

    func passesFilter(_ item: GalleryItem, ignoringAspect: Bool = false) -> Bool {
        if item.isVideo ? !filter.showVideos : !filter.showImages { return false }
        if !ignoringAspect, !filter.aspects.isEmpty,
           !filter.aspects.contains(GalleryFilter.aspectKey(width: item.width, height: item.height)) { return false }
        if !filter.personaIDs.isEmpty, !(item.personaIDs ?? []).contains(where: filter.personaIDs.contains) { return false }
        if !filter.tags.isEmpty {
            let tags = Set(item.tags ?? [])
            if filter.requiresAllTags ? !filter.tags.isSubset(of: tags) : tags.isDisjoint(with: filter.tags) { return false }
        }
        return true
    }

    /// Wie viele sichtbare Bilder es je Format gibt – für die Auswahl im Filter.
    var aspectCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for item in items where !missing.contains(item.id) {
            counts[GalleryFilter.aspectKey(width: item.width, height: item.height), default: 0] += 1
        }
        return counts
    }

    var videoCount: Int { items.lazy.filter { !self.missing.contains($0.id) && $0.isVideo }.count }

    // MARK: Kachelgröße

    static let thumbnailRange: ClosedRange<Double> = 100...800

    /// Pinch, ⌘+ / ⌘−: Kacheln vergrößern oder verkleinern.
    func zoomGrid(by factor: Double) {
        thumbnailSize = min(max(thumbnailSize * factor, Self.thumbnailRange.lowerBound), Self.thumbnailRange.upperBound)
    }

    /// Kacheln für das Raster – gefiltert, Serien als Stapel, neueste zuerst.
    var entries: [GalleryEntry] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var members: [UUID: [GalleryItem]] = [:]
        var result: [GalleryEntry] = []
        // Eine Story zeigt ihre Bilder in ihrer Reihenfolge, jedes einzeln – auch die Lupe blättert so.
        if case .story(let id) = collection {
            let shown = Set(items.lazy.filter { self.matches($0, search: search) }.map(\.id))
            return storyItems(id).filter { shown.contains($0.id) }.map { .image($0) }
        }
        // In der Notizen-Übersicht und auf der Seite eines Charakters zählt jedes Bild einzeln.
        let stacking: Bool
        switch collection {
        case .notes, .persona, .assets, .assetSection, .story: stacking = false
        default: stacking = true
        }
        for item in items where matches(item, search: search) {
            if stacking, let stackID = item.stackID, stacks[stackID] != nil {
                members[stackID, default: []].append(item)
            } else {
                result.append(.image(item))
            }
        }
        for (stackID, group) in members {
            let sorted = group.sorted(by: Self.stackOrder)
            if sorted.count == 1 {
                result.append(.image(sorted[0]))
            } else if let stack = stacks[stackID] {
                result.append(.stack(stack, sorted))
            }
        }
        if collection == .recent { return result.sorted { $0.addedDate > $1.addedDate } }
        return result.sorted { $0.date > $1.date }
    }

    /// Wie lange ein Bild unter „Zuletzt hinzugefügt“ bleibt.
    static let recentDays = 7

    private func isRecent(_ item: GalleryItem) -> Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.recentDays, to: .now) else { return true }
        return item.addedDate >= cutoff
    }

    private func isUnassigned(_ item: GalleryItem) -> Bool {
        (item.personaIDs ?? []).isEmpty && (item.tags ?? []).isEmpty
    }

    /// Kacheln nach Tagen gruppiert.
    func sections(of entries: [GalleryEntry]) -> [GallerySection] {
        var order: [Date] = []
        var byDay: [Date: [GalleryEntry]] = [:]
        for entry in entries {
            let day = Calendar.current.startOfDay(for: collection == .recent ? entry.addedDate : entry.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(entry)
        }
        return order.map { GallerySection(day: $0, entries: byDay[$0] ?? []) }
    }

    /// Tage mit Bildern – für die Bibliotheksauswahl.
    var days: [(day: Date, count: Int)] {
        var counts: [Date: Int] = [:]
        for item in items where !missing.contains(item.id) {
            counts[Calendar.current.startOfDay(for: item.createdAt), default: 0] += 1
        }
        return counts.sorted { $0.key > $1.key }.map { (day: $0.key, count: $0.value) }
    }

    func count(_ collection: GalleryCollection) -> Int {
        let visible = items.lazy.filter { !self.missing.contains($0.id) }
        switch collection {
        case .all: return visible.count
        case .recent: return visible.filter { self.isRecent($0) }.count
        case .unassigned: return visible.filter { self.isUnassigned($0) }.count
        case .series: return Set(visible.compactMap(\.stackID)).count
        case .picks: return visible.filter { $0.flag == .pick }.count
        case .rated: return visible.filter { $0.rating > 0 }.count
        case .rejected: return visible.filter { $0.flag == .reject }.count
        case .notes: return notes.filter { $0.isOpenTodo && !missing.contains($0.itemID) }.count
        case .project(let id): return visible.filter { self.projectMembers[id]?.contains($0.id) == true }.count
        case .persona(let id): return visible.filter { $0.personaIDs?.contains(id) == true }.count
        case .assets, .assetSection: return 0
        case .story(let id): return storyItems(id).count
        }
    }

    func title(for collection: GalleryCollection) -> String {
        if case .project(let id) = collection { return project(id)?.name ?? "Projekt" }
        if case .story(let id) = collection { return story(id)?.name ?? "Story" }
        return collection.title
    }

    /// Bild- und Stapel-IDs aufgelöst zu Bildern (Stapel mit allen Bildern), in Raster-Reihenfolge.
    func expand(_ ids: Set<UUID>, in entries: [GalleryEntry]) -> [UUID] {
        entries.filter { ids.contains($0.id) }.flatMap { $0.items.map(\.id) }
    }

    nonisolated static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    // MARK: Auswahl

    func click(_ id: UUID, order: [UUID], modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            selectionAnchor = id
        } else if modifiers.contains(.shift), let anchor = selectionAnchor,
                  let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) {
            selection = Set(order[min(a, b)...max(a, b)])
        } else {
            selection = [id]
            selectionAnchor = id
        }
    }

    func moveSelection(by delta: Int, order: [UUID]) {
        guard !order.isEmpty else { return }
        let current = selectionAnchor.flatMap { order.firstIndex(of: $0) } ?? (delta > 0 ? -1 : order.count)
        let next = min(max(current + delta, 0), order.count - 1)
        selection = [order[next]]
        selectionAnchor = order[next]
    }

    // MARK: Ansehen & Vergleichen

    func open(_ entry: GalleryEntry) {
        lastViewedEntryID = entry.id
        compareMode = .grid
        switch entry {
        case .image(let item):
            viewer = GalleryViewerState(itemIDs: [item.id], isLoupe: true)
        case .stack(let stack, let members):
            let source = stack.sourceID.flatMap { item($0) }.flatMap { missing.contains($0.id) ? nil : $0 }
            viewer = GalleryViewerState(itemIDs: members.map(\.id), stackID: stack.id, sourceID: source?.id)
        }
    }

    func compare(_ itemIDs: [UUID]) {
        guard !itemIDs.isEmpty else { return }
        lastViewedEntryID = selectionAnchor
        compareMode = .grid
        viewer = GalleryViewerState(itemIDs: itemIDs, isLoupe: itemIDs.count == 1)
    }

    func closeViewer() {
        viewer = nil
    }

    // MARK: Markieren & Bewerten

    /// - Parameter toggle: Haben schon alle diese Markierung, wird sie entfernt (Klick auf den Knopf).
    func setFlag(_ flag: GalleryFlag, for ids: [UUID], toggle: Bool = true) {
        let clear = toggle && ids.allSatisfy { item($0)?.flag == flag }
        update(ids) { $0.flag = clear ? .none : flag }
    }

    /// - Parameter toggle: Haben schon alle diese Bewertung, wird sie zurückgesetzt (Klick auf den Stern).
    func setRating(_ rating: Int, for ids: [UUID], toggle: Bool = true) {
        let clear = toggle && ids.allSatisfy { item($0)?.rating == rating }
        update(ids) { $0.rating = clear ? 0 : rating }
    }

    /// Charakter als „ist auf dem Bild“ zuordnen bzw. entfernen (haben ihn schon alle, wird er entfernt).
    func togglePersona(_ personaID: UUID, for ids: [UUID]) {
        let remove = ids.allSatisfy { item($0)?.personaIDs?.contains(personaID) == true }
        update(ids) { item in
            var personas = item.personaIDs ?? []
            if remove {
                personas.removeAll { $0 == personaID }
            } else if !personas.contains(personaID) {
                personas.append(personaID)
            }
            item.personaIDs = personas.isEmpty ? nil : personas
        }
    }

    func update(_ ids: [UUID], _ change: (inout GalleryItem) -> Void) {
        for id in ids {
            guard let index = indexByID[id] else { continue }
            change(&items[index])
        }
        scheduleSave()
    }

    // MARK: Stapel

    /// Bilder von Hand zu einem Stapel zusammenfassen (wie ⌘G in Lightroom).
    func group(_ itemIDs: [UUID]) {
        let chosen = itemIDs.compactMap { item($0) }.sorted { $0.createdAt < $1.createdAt }
        guard chosen.count > 1 else { return }
        let oldStacks = Set(chosen.compactMap(\.stackID))
        let inherited = oldStacks.count == 1 ? oldStacks.first.flatMap { stacks[$0] } : nil
        let stack = GalleryStack(
            id: UUID(),
            createdAt: chosen[0].createdAt,
            title: inherited?.title ?? "Stapel",
            symbol: inherited?.symbol ?? "square.stack",
            isSeries: inherited?.isSeries ?? false,
            sourceID: inherited?.sourceID,
            prompt: inherited?.prompt
        )
        stacks[stack.id] = stack
        for (offset, member) in chosen.enumerated() {
            guard let index = indexByID[member.id] else { continue }
            items[index].stackID = stack.id
            items[index].stackIndex = offset + 1
        }
        removeEmptyStacks()
        selection = [stack.id]
        selectionAnchor = stack.id
        scheduleSave()
    }

    func unstack(_ stackID: UUID) {
        let ids = members(of: stackID).map(\.id)
        for id in ids {
            guard let index = indexByID[id] else { continue }
            items[index].stackID = nil
            items[index].stackIndex = nil
        }
        stacks[stackID] = nil
        selection = Set(ids)
        scheduleSave()
    }

    func removeFromStack(_ itemID: UUID) {
        guard let index = indexByID[itemID] else { return }
        items[index].stackID = nil
        items[index].stackIndex = nil
        removeEmptyStacks()
        scheduleSave()
    }

    private func removeEmptyStacks() {
        let used = Set(items.compactMap(\.stackID))
        for id in stacks.keys where !used.contains(id) { stacks[id] = nil }
    }

    // MARK: Löschen

    /// Bilder in den Papierkorb legen (lässt sich im Finder zurücklegen).
    @discardableResult
    func moveToTrash(_ itemIDs: [UUID]) -> [String] {
        var failures: [String] = []
        var removed: Set<UUID> = []
        for id in itemIDs {
            guard let item = item(id) else { continue }
            do {
                if FileManager.default.fileExists(atPath: item.path) {
                    var trashed: NSURL?
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: &trashed)
                    if let path = trashed?.path { trashedFiles.append(path) }
                }
                removed.insert(id)
                GalleryImages.forget(id)
            } catch {
                failures.append(item.url.lastPathComponent)
            }
        }
        items.removeAll { removed.contains($0.id) }
        notes.removeAll { removed.contains($0.itemID) }
        for index in projects.indices where projects[index].itemIDs.contains(where: removed.contains) {
            projects[index].itemIDs.removeAll { removed.contains($0) }
        }
        for index in stories.indices where stories[index].itemIDs.contains(where: removed.contains) {
            stories[index].itemIDs.removeAll { removed.contains($0) }
        }
        selection.subtract(removed)
        rebuildIndex()
        removeEmptyStacks()
        if var state = viewer {
            state.itemIDs.removeAll { removed.contains($0) }
            if let source = state.sourceID, removed.contains(source) {
                state.sourceID = nil
                state.showSource = false
            }
            state.index = min(state.index, max(state.displayIDs.count - 1, 0))
            viewer = state.itemIDs.isEmpty ? nil : state
        }
        scheduleSave()
        return failures
    }

    // MARK: Neue Bilder aus dem Studio

    /// Frisch gesichertes Bild aufnehmen – bei Serien gleich in den richtigen Stapel.
    func register(_ version: ImageVersion) {
        guard let url = version.fileURL, indexByID[version.id] == nil else { return }
        var item = GalleryItem(
            id: version.id,
            path: url.path,
            createdAt: version.createdAt,
            kind: version.source.fileKind,
            prompt: version.prompt,
            seed: version.seed,
            width: version.image.width,
            height: version.image.height,
            duration: version.duration,
            parentID: version.parentID,
            personaIDs: version.personaIDs.isEmpty ? nil : version.personaIDs,
            addedAt: .now
        )
        if let tag = version.series {
            if stacks[tag.id] == nil {
                stacks[tag.id] = GalleryStack(
                    id: tag.id, createdAt: version.createdAt, title: tag.title, symbol: tag.symbol,
                    isSeries: tag.isSeries, sourceID: tag.sourceID, prompt: tag.prompt.isEmpty ? nil : tag.prompt
                )
            }
            item.stackID = tag.id
            item.stackIndex = tag.index
            item.label = tag.value
        }
        items.insert(item, at: 0)
        items.sort { $0.createdAt > $1.createdAt }
        rebuildIndex()
        if let projectID = activeProjectID { addToProject(projectID, itemIDs: [item.id]) }
        linkToWorkingTodo(item)
        scheduleSave()
    }

    /// Von außen übernommene Datei aufnehmen (siehe `importFiles`).
    func insertImported(_ item: GalleryItem) {
        guard indexByID[item.id] == nil else { return }
        var item = item
        item.addedAt = .now
        items.append(item)
        items.sort { $0.createdAt > $1.createdAt }
        rebuildIndex()
        if let projectID = activeProjectID { addToProject(projectID, itemIDs: [item.id]) }
        scheduleSave()
    }

    // MARK: Abgleich mit dem Ordner der Bibliothek

    /// Neue Dateien in der Bibliothek aufnehmen (z. B. aus älteren Versionen der App) und fehlende ausblenden.
    func sync(folder: URL) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let knownPaths = Set(items.map(\.path))
        let allPaths = items.map { ($0.id, $0.path) }
        let (scanned, gone) = await Task.detached(priority: .utility) {
            let scanned = await Self.scan(folder: folder, known: knownPaths)
            let gone = Set(allPaths.filter { !FileManager.default.fileExists(atPath: $0.1) }.map(\.0))
            return (scanned, gone)
        }.value

        missing = gone
        guard !scanned.isEmpty else { return }
        var added: [GalleryItem] = []
        for file in scanned where indexByID[file.item.id] == nil {
            var item = file.item
            item.addedAt = .now
            if let seriesID = file.seriesID {
                if stacks[seriesID] == nil {
                    let variable = file.variable.flatMap { name in SeriesVariable.allCases.first { $0.title == name } }
                        ?? SeriesVariable.guess(fromPrompt: item.prompt)
                    stacks[seriesID] = GalleryStack(
                        id: seriesID, createdAt: item.createdAt, title: file.variable ?? variable?.title ?? "Serie",
                        symbol: file.isSeries ? variable?.symbol ?? "square.stack" : "person.2.crop.square.stack",
                        isSeries: file.isSeries
                    )
                }
                item.stackID = seriesID
            }
            added.append(item)
        }
        groupLegacySeries(&added)
        items.append(contentsOf: added)
        items.sort { $0.createdAt > $1.createdAt }
        rebuildIndex()
        scheduleSave()
    }

    /// Ältere Serienbilder tragen keine Serien-ID. Sie werden nach Zeitabstand gestapelt:
    /// höchstens vier Bilder, die kurz nacheinander entstanden sind.
    private func groupLegacySeries(_ added: inout [GalleryItem]) {
        let candidates = added.indices
            .filter { added[$0].kind == StudioMode.series.rawValue && added[$0].stackID == nil }
            .sorted { added[$0].createdAt < added[$1].createdAt }
        var groups: [[Int]] = []
        for index in candidates {
            if let last = groups.last?.last, groups[groups.count - 1].count < SeriesSetup.maxCount {
                let gap = added[index].createdAt.timeIntervalSince(added[last].createdAt)
                let sameSeed = added[index].seed != nil && added[index].seed == added[last].seed
                if gap < (sameSeed ? 15 * 60 : 6 * 60) {
                    groups[groups.count - 1].append(index)
                    continue
                }
            }
            groups.append([index])
        }
        for group in groups where group.count > 1 {
            let first = added[group[0]]
            let variable = SeriesVariable.guess(fromPrompt: first.prompt)
            let stack = GalleryStack(
                id: UUID(), createdAt: first.createdAt, title: variable?.title ?? "Serie",
                symbol: variable?.symbol ?? "square.stack", isSeries: true
            )
            stacks[stack.id] = stack
            for (offset, index) in group.enumerated() {
                added[index].stackID = stack.id
                added[index].stackIndex = offset + 1
            }
        }
    }

    struct ScannedFile {
        var item: GalleryItem
        var seriesID: UUID?
        var variable: String?
        var isSeries = true
    }

    nonisolated static func scan(folder: URL, known: Set<String>) async -> [ScannedFile] {
        var files: [ScannedFile] = []
        for url in mediaFiles(in: folder) where !known.contains(url.path) {
            if GalleryMedia.videoExtensions.contains(url.pathExtension.lowercased()) {
                if let file = await readVideo(url) { files.append(file) }
            } else if let file = read(url) {
                files.append(file)
            }
        }
        return files
    }

    /// Alle Bilder und Videos im Ordner – ohne Katalog, Charakterfotos und Assets.
    private nonisolated static func mediaFiles(in folder: URL) -> [URL] {
        let extensions = GalleryMedia.imageExtensions.union(GalleryMedia.videoExtensions)
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            if enumerator.level == 1, Library.reservedFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if extensions.contains(url.pathExtension.lowercased()) { urls.append(url) }
        }
        return urls
    }

    /// Größe, Prompt und Serien-Angaben aus den Metadaten – ohne das Bild zu dekodieren.
    nonisolated static func read(_ url: URL) -> ScannedFile? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let prompt = png?[kCGImagePropertyPNGDescription] as? String ?? tiff?[kCGImagePropertyTIFFImageDescription] as? String ?? ""
        let comment = AutosaveComment(png?[kCGImagePropertyPNGComment] as? String ?? "")

        // Dateiname aus der App: <Ordner yyyy-MM-dd>/<HHmmss-SSS>-<Art>.png
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-")
        let kindFromName = parts.count >= 3 ? String(parts[2...].joined(separator: "-")) : nil
        let date = dateFromName(day: url.deletingLastPathComponent().lastPathComponent, time: parts.prefix(2).joined(separator: "-"))
            ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
            ?? .now
        let kind = comment.mode ?? kindFromName.flatMap { ImageVersion.Source(fileKind: $0).fileKind == $0 ? $0 : nil } ?? "imported"

        let item = GalleryItem(
            id: UUID(),
            path: url.path,
            createdAt: date,
            kind: kind,
            prompt: prompt,
            seed: comment.seed,
            width: width,
            height: height,
            stackIndex: comment.variant,
            label: comment.value,
            personaIDs: comment.personas.isEmpty ? nil : comment.personas
        )
        return ScannedFile(item: item, seriesID: comment.series, variable: comment.variable, isSeries: comment.isSeries)
    }

    private nonisolated static func dateFromName(day: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss-SSS"
        return formatter.date(from: "\(day) \(time)")
    }

    // MARK: Speichern

    private struct Stored: Codable {
        var version = 2
        /// Pfade relativ zur Bibliothek (Version 1: absolut).
        var items: [GalleryItem]
        var stacks: [GalleryStack]
        var notes: [GalleryNote]?
        var projects: [GalleryProject]?
        var stories: [GalleryStory]?
        var activeProjectID: UUID?
        var trashedFiles: [String]?
    }

    private var fileURL: URL { root.appending(path: "Katalog/gallery.json") }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        items = stored.items
            .map { item in
                var item = item
                item.path = Library.resolve(item.path, in: root)
                return item
            }
            .sorted { $0.createdAt > $1.createdAt }
        stacks = Dictionary(stored.stacks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        notes = stored.notes ?? []
        projects = stored.projects ?? []
        stories = stored.stories ?? []
        trashedFiles = stored.trashedFiles ?? []
        // Bis Version 1 stand das aktive Projekt in den Einstellungen der App.
        let legacyActive = UserDefaults.standard.string(forKey: "gallery.activeProject").flatMap(UUID.init(uuidString:))
        let active = stored.activeProjectID ?? legacyActive
        activeProjectID = projects.contains { $0.id == active } ? active : nil
        UserDefaults.standard.removeObject(forKey: "gallery.activeProject")
        rebuildIndex()
    }

    func scheduleSave() {
        guard !isClosed else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Sofort sichern (beim Beenden und vor dem Wechsel der Bibliothek).
    func save() {
        guard !isClosed, Library.ensure(fileURL.deletingLastPathComponent(), in: root) else { return }
        let relativeItems = items.map { item in
            var item = item
            item.path = Library.relative(item.path, to: root)
            return item
        }
        let stored = Stored(
            items: relativeItems, stacks: Array(stacks.values), notes: notes, projects: projects,
            stories: stories.isEmpty ? nil : stories, activeProjectID: activeProjectID, trashedFiles: trashedFiles.isEmpty ? nil : trashedFiles
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(stored) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Bibliothek wird gewechselt oder gelöscht: letzter Stand sichern (optional), danach nichts mehr schreiben.
    func close(saving: Bool = true) {
        saveTask?.cancel()
        if saving { save() }
        isClosed = true
    }

    private func rebuildIndex() {
        indexByID = Dictionary(items.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Kommentar, den die App in jede PNG schreibt:
/// `mode: series, seed: 123, series: <UUID>, variable: Kleidung, variant: 2, value: Trenchcoat`
/// (`value` steht immer am Ende, weil es Kommas enthalten darf).
struct AutosaveComment {
    var mode: String?
    var seed: UInt32?
    var series: UUID?
    var variable: String?
    var variant: Int?
    var value: String?
    var personas: [UUID] = []
    /// false = Stapel eines Charaktertests, keine Serie.
    var isSeries = true

    init(mode: String? = nil, seed: UInt32? = nil, series: SeriesTag? = nil, personas: [UUID] = []) {
        self.mode = mode
        self.seed = seed
        self.series = series?.id
        self.isSeries = series?.isSeries ?? true
        self.variable = series?.title
        self.variant = series?.index
        self.value = series?.value
        self.personas = personas
    }

    init(_ text: String) {
        var rest = Substring(text)
        if let range = rest.range(of: "value: ") {
            value = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            rest = rest[..<range.lowerBound]
        }
        for part in rest.split(separator: ",") {
            let pair = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "mode": mode = pair[1]
            case "seed": seed = UInt32(pair[1])
            case "series": series = UUID(uuidString: pair[1])
            case "variable": variable = pair[1]
            case "variant": variant = Int(pair[1])
            case "personas": personas = pair[1].split(separator: " ").compactMap { UUID(uuidString: String($0)) }
            case "stack": isSeries = pair[1] != "test"
            default: break
            }
        }
    }

    var text: String {
        var parts: [String] = []
        if let mode { parts.append("mode: \(mode)") }
        if let seed { parts.append("seed: \(seed)") }
        if let series { parts.append("series: \(series.uuidString)") }
        if series != nil, !isSeries { parts.append("stack: test") }
        if let variable { parts.append("variable: \(variable.replacingOccurrences(of: ",", with: " "))") }
        if let variant { parts.append("variant: \(variant)") }
        if !personas.isEmpty { parts.append("personas: " + personas.map(\.uuidString).joined(separator: " ")) }
        if let value { parts.append("value: \(value)") }
        return parts.joined(separator: ", ")
    }
}
