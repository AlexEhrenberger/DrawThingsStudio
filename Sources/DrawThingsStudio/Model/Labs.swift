import CoreGraphics
import Foundation

// Labs: Experimente mit Qwen Image Edit 2511 abseits der vier Modi – „Bild zusammenbauen“.
// Labs schickt nichts an Draw Things: Gemma schreibt den Prompt, eingefügt wird er in Draw Things von Hand.

/// Ein Platz in „Bild zusammenbauen“: Platz 0 ist der Canvas, 1 bis 3 sind die Moodboards –
/// genau wie in Draw Things.
struct LabSlot: Identifiable {
    let id = UUID()
    var image: CGImage? {
        didSet { thumbnail = image.map { ImageTools.scaled($0, maxSide: 1200) } }
    }
    private(set) var thumbnail: CGImage?
    /// Was mit diesem Bild passieren soll – auf Deutsch, Gemma übersetzt.
    var instruction = ""

    static let count = 4
    static let canvas = 0

    static func title(_ index: Int) -> String {
        index == canvas ? "Canvas" : "Moodboard \(index)"
    }
}

/// Ein Prompt, den Gemma geschrieben hat – für den Verlauf in der Seitenleiste.
struct LabPromptRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var prompt: String
    var check: String
    /// Was Gemma unklar war und wie sie es gelesen hat (ältere Einträge haben das Feld nicht).
    var assumptions: String?
    var imageCount: Int
}

/// Zustand von „Bild zusammenbauen“.
struct LabComposition {
    var slots: [LabSlot] = (0..<LabSlot.count).map { _ in LabSlot() }
    /// Gilt für das ganze Bild, z. B. „Abendstimmung, alles bleibt fotorealistisch“.
    var general = ""
    /// Ergebnis – bearbeitbar, bevor es in Draw Things eingefügt wird.
    var prompt = ""
    /// Gemmas Erklärung auf Deutsch: Was der Prompt verlangt und welches Bild was beisteuert.
    var check = ""
    /// Was Gemma unklar war und wie sie es gelesen hat – z. B. ein Tippfehler. Leer = alles klar.
    var assumptions = ""
    /// Hinweis der App, z. B. wenn Gemma ein Bild nennt, das es nicht gibt.
    var warning: String?
    var correction = ""
    var isWriting = false
    var writingStarted: Date?
    var error: String?
    var history: [LabPromptRecord] = []

    var canvas: CGImage? { slots[LabSlot.canvas].image }

    /// Nummer im Prompt: Canvas = Picture 1, die belegten Moodboards folgen der Reihe nach –
    /// so, wie Draw Things sie an Qwen gibt (das Modell bekommt sie als „Picture 1: …, Picture 2: …“).
    func imageNumber(_ index: Int) -> Int? {
        guard slots.indices.contains(index), slots[index].image != nil else { return nil }
        return slots[...index].filter { $0.image != nil }.count
    }

    var filledCount: Int { slots.filter { $0.image != nil }.count }

    var filledMoodboards: [Int] {
        (1..<LabSlot.count).filter { slots[$0].image != nil }
    }

    var hasInstruction: Bool {
        slots.contains { !$0.instruction.trimmed.isEmpty } || !general.trimmed.isEmpty
    }

    /// Warum Gemma noch nicht schreiben kann (nil = bereit).
    var blocker: String? {
        if isWriting { return "Gemma schreibt gerade." }
        if canvas == nil { return "Lege zuerst das Bild, das du verändern willst, auf den Canvas." }
        if !hasInstruction { return "Schreib unter die Bilder, was passieren soll." }
        return nil
    }
}

/// Was von Labs in der Bibliothek liegt: `Katalog/Labs/labs.json` und die Bilder daneben (`slot-1.png` …).
struct LabsDraft: Codable {
    var instructions: [String]
    var general: String
    var prompt: String
    var check: String
    var assumptions: String?
    var history: [LabPromptRecord]
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
