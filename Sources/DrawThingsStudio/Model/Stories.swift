import Foundation

/// Story: Bilder in fester Reihenfolge – Bild 1 ist der Anfang, Bild n das Ende. Wie ein Projekt, nur geordnet.
/// Zum Präsentieren und als Vorlage für ein Video: Je zwei benachbarte Bilder werden ein Clip
/// (Bild n = Startframe, Bild n+1 = Endframe), Gemma schreibt die Prompts dafür.
struct GalleryStory: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// Reihenfolge der Story – jedes Bild höchstens einmal, keine Videos.
    var itemIDs: [UUID] = []
    var video = StoryVideoPlan()

    static let symbol = "book.pages"

    init(name: String, itemIDs: [UUID] = []) {
        self.name = name
        self.itemIDs = itemIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        itemIDs = try container.decodeIfPresent([UUID].self, forKey: .itemIDs) ?? []
        video = try container.decodeIfPresent(StoryVideoPlan.self, forKey: .video) ?? StoryVideoPlan()
    }
}

/// Seitenverhältnis der Clips – Gemini Omni kennt nur 16:9 und 9:16.
enum StoryVideoFormat: String, Codable, CaseIterable, Identifiable {
    case auto, landscape, portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .landscape: "16:9"
        case .portrait: "9:16"
        }
    }

    /// Auto: wie die meisten Bilder der Story (Gleichstand: quer).
    func resolved(for items: [GalleryItem]) -> StoryVideoFormat {
        guard self == .auto else { return self }
        let portrait = items.filter { $0.height > $0.width }.count
        return portrait * 2 > items.count ? .portrait : .landscape
    }

    var promptText: String {
        switch self {
        case .portrait: "9:16 (vertical)"
        case .landscape, .auto: "16:9 (landscape)"
        }
    }
}

/// Was Gemma für den Ton schreibt – Gemini Omni erzeugt zu jedem Video eine Tonspur.
enum StoryAudio: String, Codable, CaseIterable, Identifiable {
    case ambience, music, auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ambience: "Nur Geräusche"
        case .music: "Geräusche & Musik"
        case .auto: "Gemma entscheidet"
        }
    }

    var help: String {
        switch self {
        case .ambience: "Umgebung und Geräusche passend zur Handlung – keine Musik, kein Dialog"
        case .music: "Umgebung, Geräusche und eine passende Musik – Dialog nur, wenn du ihn beim Clip vorgibst"
        case .auto: "Gemma wählt, was der Szene dient"
        }
    }
}

/// Ein Clip: Übergang von einem Bild der Story zum nächsten. Hängt an den beiden Bildern –
/// wird die Reihenfolge geändert, bleibt der Text erhalten und kommt zurück, sobald die Bilder wieder nebeneinanderliegen.
struct StoryClip: Codable, Equatable {
    var fromID: UUID
    var toID: UUID
    /// Was passieren soll – vom Nutzer, auf Deutsch (darf leer bleiben, dann entscheidet Gemma).
    var wish = ""
    /// Gemmas Prompt für das Videomodell (englisch, bearbeitbar).
    var prompt = ""
    /// Gemmas Zusammenfassung auf Deutsch – ein Satz.
    var summary = ""
    /// Eigene Länge in Sekunden (nil = wie die Story).
    var duration: Int?
    var writtenAt: Date?

    init(fromID: UUID, toID: UUID) {
        self.fromID = fromID
        self.toID = toID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromID = try container.decode(UUID.self, forKey: .fromID)
        toID = try container.decode(UUID.self, forKey: .toID)
        wish = try container.decodeIfPresent(String.self, forKey: .wish) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        writtenAt = try container.decodeIfPresent(Date.self, forKey: .writtenAt)
    }
}

/// Video aus einer Story: Preset, Einstellungen, Handlung und die Prompts der Clips.
struct StoryVideoPlan: Codable, Equatable {
    var presetID = VideoPreset.geminiOmni.id
    /// Worum es geht – vom Nutzer, auf Deutsch.
    var idea = ""
    /// Handlung, die Gemma aus den Bildern abgeleitet hat (Deutsch, bearbeitbar).
    var arc = ""
    /// Reihenfolge, für die die Handlung geschrieben wurde – weicht sie ab, ist sie womöglich veraltet.
    var arcOrder: [UUID] = []
    var format: StoryVideoFormat = .auto
    /// Sekunden je Clip.
    var duration = VideoPreset.geminiOmni.defaultDuration
    var audio: StoryAudio = .ambience
    var clips: [StoryClip] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID) ?? VideoPreset.geminiOmni.id
        idea = try container.decodeIfPresent(String.self, forKey: .idea) ?? ""
        arc = try container.decodeIfPresent(String.self, forKey: .arc) ?? ""
        arcOrder = try container.decodeIfPresent([UUID].self, forKey: .arcOrder) ?? []
        format = try container.decodeIfPresent(StoryVideoFormat.self, forKey: .format) ?? .auto
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? VideoPreset.geminiOmni.defaultDuration
        audio = try container.decodeIfPresent(StoryAudio.self, forKey: .audio) ?? .ambience
        clips = try container.decodeIfPresent([StoryClip].self, forKey: .clips) ?? []
    }

    var preset: VideoPreset { VideoPreset.preset(presetID) }

    func clip(from: UUID, to: UUID) -> StoryClip? {
        clips.first { $0.fromID == from && $0.toID == to }
    }

    func duration(of clip: StoryClip?) -> Int {
        clip?.duration ?? duration
    }
}

/// Übergang zwischen zwei benachbarten Bildern der Story.
struct StoryTransition: Identifiable, Equatable {
    /// 1 … n-1
    let number: Int
    let from: GalleryItem
    let to: GalleryItem
    var id: String { "\(from.id.uuidString)>\(to.id.uuidString)" }
}

/// Präsentation einer Story: ein Bild oder ein Raster aus 2 bzw. 4 Bildern je Seite.
enum PresentationLayout: Int, CaseIterable, Identifiable {
    case single = 1, two = 2, four = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .single: "Ein Bild"
        case .two: "2 Bilder"
        case .four: "4 Bilder"
        }
    }

    var symbol: String {
        switch self {
        case .single: "rectangle"
        case .two: "rectangle.split.2x1"
        case .four: "square.grid.2x2"
        }
    }
}

struct StoryPresentation: Equatable {
    var storyID: UUID
    var layout: PresentationLayout
    var isFullScreen: Bool
    /// Erstes Bild der gezeigten Seite; = Anzahl der Bilder heißt „Ende der Story“.
    var index = 0
}

/// Gemma schreibt gerade Handlung oder Clips einer Story.
struct StoryWriting: Equatable {
    var storyID: UUID
    /// nil = Handlung, sonst der Clip, an dem Gemma gerade schreibt.
    var transitionID: String?
    var done = 0
    var total: Int
    var started = Date()
}

// MARK: - Galerie

extension Gallery {
    func story(_ id: UUID) -> GalleryStory? {
        stories.first { $0.id == id }
    }

    /// Bilder der Story in ihrer Reihenfolge – ohne fehlende Dateien.
    func storyItems(_ id: UUID) -> [GalleryItem] {
        guard let story = story(id) else { return [] }
        return story.itemIDs.compactMap { item($0) }.filter { !missing.contains($0.id) }
    }

    /// Übergänge zwischen den sichtbaren Bildern: Bild 1 → 2, 2 → 3 …
    func storyTransitions(_ id: UUID) -> [StoryTransition] {
        let items = storyItems(id)
        guard items.count > 1 else { return [] }
        return (0..<(items.count - 1)).map { StoryTransition(number: $0 + 1, from: items[$0], to: items[$0 + 1]) }
    }

    func stories(containing itemID: UUID) -> [GalleryStory] {
        stories.filter { storyMembers[$0.id]?.contains(itemID) == true }
    }

    /// Neue Story – der Name lässt sich gleich in der Seitenleiste ändern.
    @discardableResult
    func createStory(name: String = "Neue Story", itemIDs: [UUID] = []) -> UUID {
        var unique = name
        var number = 2
        while stories.contains(where: { $0.name == unique }) {
            unique = "\(name) \(number)"
            number += 1
        }
        let story = GalleryStory(name: unique, itemIDs: storyCandidates(itemIDs, excluding: []))
        stories.append(story)
        renamingStoryID = story.id
        scheduleSave()
        return story.id
    }

    func renameStory(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = stories.firstIndex(where: { $0.id == id }) else { return }
        stories[index].name = name
        scheduleSave()
    }

    func deleteStory(_ id: UUID) {
        stories.removeAll { $0.id == id }
        if collection == .story(id) { collection = .all }
        scheduleSave()
    }

    /// Bilder ans Ende der Story hängen – Videos und Bilder, die schon drin sind, bleiben draußen.
    /// - Returns: wie viele Bilder dazugekommen sind.
    @discardableResult
    func addToStory(_ id: UUID, itemIDs: [UUID]) -> Int {
        guard let index = stories.firstIndex(where: { $0.id == id }) else { return 0 }
        let new = storyCandidates(itemIDs, excluding: Set(stories[index].itemIDs))
        guard !new.isEmpty else { return 0 }
        stories[index].itemIDs += new
        scheduleSave()
        return new.count
    }

    func removeFromStory(_ id: UUID, itemIDs: [UUID]) {
        guard let index = stories.firstIndex(where: { $0.id == id }) else { return }
        let removed = Set(itemIDs)
        stories[index].itemIDs.removeAll { removed.contains($0) }
        selection.subtract(removed)
        scheduleSave()
    }

    /// Ein Bild an die Stelle eines anderen schieben (Ziehen im Storyboard).
    func moveStoryItem(_ id: UUID, item itemID: UUID, to targetID: UUID) {
        guard let index = stories.firstIndex(where: { $0.id == id }),
              let from = stories[index].itemIDs.firstIndex(of: itemID),
              let to = stories[index].itemIDs.firstIndex(of: targetID), from != to else { return }
        var order = stories[index].itemIDs
        order.remove(at: from)
        order.insert(itemID, at: to)
        stories[index].itemIDs = order
        scheduleSave()
    }

    /// Bilder um `delta` Plätze verschieben (⌘← / ⌘→) – die Auswahl bleibt zusammen und in ihrer Reihenfolge.
    func moveStoryItems(_ id: UUID, itemIDs: Set<UUID>, by delta: Int) {
        guard let index = stories.firstIndex(where: { $0.id == id }), !itemIDs.isEmpty, delta != 0 else { return }
        var order = stories[index].itemIDs
        let moving = order.filter { itemIDs.contains($0) }
        guard let first = order.firstIndex(where: { itemIDs.contains($0) }) else { return }
        order.removeAll { itemIDs.contains($0) }
        let target = min(max(first + delta, 0), order.count)
        order.insert(contentsOf: moving, at: target)
        guard order != stories[index].itemIDs else { return }
        stories[index].itemIDs = order
        scheduleSave()
    }

    /// An den Anfang (Bild 1) oder ans Ende (Bild n).
    func moveStoryItems(_ id: UUID, itemIDs: Set<UUID>, toStart: Bool) {
        guard let index = stories.firstIndex(where: { $0.id == id }) else { return }
        let order = stories[index].itemIDs
        let moving = order.filter { itemIDs.contains($0) }
        let rest = order.filter { !itemIDs.contains($0) }
        stories[index].itemIDs = toStart ? moving + rest : rest + moving
        scheduleSave()
    }

    /// Reihenfolge umdrehen – das Ende wird der Anfang.
    func reverseStory(_ id: UUID) {
        guard let index = stories.firstIndex(where: { $0.id == id }) else { return }
        stories[index].itemIDs.reverse()
        scheduleSave()
    }

    /// Video-Plan ändern (Einstellungen, Handlung, Wünsche, Prompts).
    func updateStoryVideo(_ id: UUID, _ change: (inout StoryVideoPlan) -> Void) {
        guard let index = stories.firstIndex(where: { $0.id == id }) else { return }
        change(&stories[index].video)
        scheduleSave()
    }

    /// Clip zwischen zwei Bildern ändern – fehlt er, wird er angelegt.
    func updateClip(_ id: UUID, from: UUID, to: UUID, _ change: (inout StoryClip) -> Void) {
        updateStoryVideo(id) { plan in
            if let index = plan.clips.firstIndex(where: { $0.fromID == from && $0.toID == to }) {
                change(&plan.clips[index])
            } else {
                var clip = StoryClip(fromID: from, toID: to)
                change(&clip)
                plan.clips.append(clip)
            }
        }
    }

    /// Bild- oder Stapel-IDs zu Bildern für eine Story: Stapel aufgelöst, Videos und Doppelte raus.
    /// Mehrere neue Bilder kommen in der Reihenfolge, in der sie entstanden sind – das älteste zuerst.
    private func storyCandidates(_ ids: [UUID], excluding existing: Set<UUID>) -> [UUID] {
        var seen = existing
        var result: [GalleryItem] = []
        for id in itemIDs(for: ids) {
            guard let item = item(id), !item.isVideo, !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(item)
        }
        return result.sorted { $0.createdAt < $1.createdAt }.map(\.id)
    }
}
