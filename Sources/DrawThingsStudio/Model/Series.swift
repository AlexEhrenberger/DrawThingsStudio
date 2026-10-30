import CoreGraphics
import Foundation

/// Was sich innerhalb einer Bilderserie ändert. Alles andere am Ausgangsbild bleibt gleich.
enum SeriesVariable: String, CaseIterable, Identifiable, Codable {
    case outfit
    case pose
    case background
    case colors
    case lighting
    case expression
    case hair
    case camera
    case style
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outfit: "Kleidung"
        case .pose: "Pose"
        case .background: "Hintergrund"
        case .colors: "Farben"
        case .lighting: "Beleuchtung"
        case .expression: "Mimik"
        case .hair: "Frisur"
        case .camera: "Perspektive"
        case .style: "Stil"
        case .custom: "Eigene Variable"
        }
    }

    var symbol: String {
        switch self {
        case .outfit: "tshirt"
        case .pose: "figure.wave"
        case .background: "mountain.2"
        case .colors: "paintpalette"
        case .lighting: "lightbulb"
        case .expression: "face.smiling"
        case .hair: "scissors"
        case .camera: "camera.viewfinder"
        case .style: "camera.filters"
        case .custom: "character.cursor.ibeam"
        }
    }

    /// Kurz erklärt, was wechselt und was bleibt.
    var hint: String {
        switch self {
        case .outfit: "Nur die Kleidung wechselt – Gesicht, Pose, Ort und Licht bleiben."
        case .pose: "Nur Haltung und Gestik wechseln – Person, Kleidung und Ort bleiben."
        case .background: "Nur Ort und Hintergrund wechseln – die Person bleibt, wie sie ist."
        case .colors: "Nur die Farben wechseln – der Kleidung, der Umgebung oder die ganze Farbstimmung."
        case .lighting: "Nur das Licht wechselt – Tageszeit, Richtung, Lichtfarbe, Stimmung."
        case .expression: "Nur der Gesichtsausdruck wechselt."
        case .hair: "Nur die Frisur wechselt – Gesicht, Kleidung und Ort bleiben."
        case .camera: "Nur Blickwinkel und Ausschnitt wechseln – Szene und Person bleiben."
        case .style: "Nur der Bildstil wechselt – Inhalt und Komposition bleiben."
        case .custom: "Gemma ändert nur, was du als Variable benennst – alles andere bleibt."
        }
    }

    /// Beispiele als Platzhalter in den vier Feldern.
    var examples: [String] {
        switch self {
        case .outfit: ["Polohemd und schwarze Jeans", "Trenchcoat", "Bikini", "Hoodie mit kurzer Hose"]
        case .pose: ["lehnt am Geländer", "sitzt auf einer Bank", "geht auf die Kamera zu", "Arme verschränkt"]
        case .background: ["Dachterrasse bei Nacht", "Sandstrand", "Café in einem Altbau", "verschneiter Wald"]
        case .colors: ["ganz in Rot", "Pastelltöne", "Schwarz-Weiß", "Neonfarben"]
        case .lighting: ["goldene Stunde", "Mittagssonne", "Neonlicht bei Nacht", "weiches Studiolicht"]
        case .expression: ["lacht", "ernst", "überrascht", "verträumt"]
        case .hair: ["Pferdeschwanz", "kurzer Bob", "lange Locken", "Dutt"]
        case .camera: ["Ansicht von vorne", "Seitenansicht von links", "Froschperspektive", "Nahaufnahme"]
        case .style: ["Analogfilm", "Aquarell", "Comic", "Ölgemälde"]
        case .custom: ["Zustand 1", "Zustand 2", "Zustand 3", "Zustand 4"]
        }
    }

    /// Bausteine aus dem Katalog, die sich als Werte anbieten.
    var catalogKeys: [String] {
        switch self {
        case .outfit: ["kleidung/outfit", "kleidung/oberteil", "kleidung/hose", "kleidung/schuhe", "kleidung/kopf", "kleidung/accessoires"]
        case .pose: ["pose/ganzkoerper", "pose/oberkoerper", "pose/haende", "pose/unterkoerper"]
        case .background: ["ort/stadt", "ort/natur", "ort/innen", "ort/fantasie"]
        case .colors: ["bildkomposition/farbe-look"]
        case .lighting: ["kamera/licht", "ort/wetter"]
        case .expression: ["motiv/mimik", "motiv/blick"]
        case .hair: ["motiv/gesicht"]
        case .camera: ["kamera/winkel", "kamera/ausschnitt"]
        case .style: ["bildkomposition/stil", "stile/technik", "stile/illustration", "stile/digital", "stile/epoche"]
        case .custom: []
        }
    }
}

extension SeriesVariable {
    /// Variable aus dem ersten Satz eines Serien-Prompts erraten – für ältere Bilder ohne Serien-Angaben.
    static func guess(fromPrompt prompt: String) -> SeriesVariable? {
        let start = prompt.prefix(80).lowercased()
        let hints: [(SeriesVariable, [String])] = [
            (.outfit, ["clothing", "outfit", "wearing", "dress the"]),
            (.camera, ["camera", "viewpoint", "angle", "shot", "frame the"]),
            (.pose, ["pose", "posture"]),
            (.background, ["background", "setting", "location"]),
            (.lighting, ["relight", "lighting", "light"]),
            (.expression, ["expression"]),
            (.hair, ["hairstyle", "hair"]),
            (.colors, ["color", "colour"]),
            (.style, ["restyle", "style"]),
        ]
        return hints.first { $0.1.contains { start.contains($0) } }?.0
    }
}

/// Einstellungen für die nächste Serie – bleiben zwischen zwei Starts erhalten.
struct SeriesSetup: Codable, Equatable {
    static let maxCount = 4

    var variable: SeriesVariable = .outfit
    var customName = ""
    var values = Array(repeating: "", count: maxCount)
    /// Alle Bilder mit demselben Seed – dann unterscheidet sie wirklich nur die Variable.
    var sameSeed = true

    var filledValues: [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var variableName: String {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return variable == .custom ? (custom.isEmpty ? "Variable" : custom) : variable.title
    }

    /// Je Bibliothek in `Katalog/series.json`.
    private static func fileURL(_ root: URL) -> URL { root.appending(path: "Katalog/series.json") }

    static func load(root: URL) -> SeriesSetup {
        guard let data = try? Data(contentsOf: fileURL(root)),
              var setup = try? JSONDecoder().decode(SeriesSetup.self, from: data) else { return SeriesSetup() }
        setup.values = Array((setup.values + Array(repeating: "", count: maxCount)).prefix(maxCount))
        return setup
    }

    func save(root: URL) {
        let url = Self.fileURL(root)
        // Unveränderter Ausgangsstand: keine Datei anlegen.
        guard self != SeriesSetup() || FileManager.default.fileExists(atPath: url.path),
              Library.ensure(url.deletingLastPathComponent(), in: root),
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Das Bild, aus dem die Serie entsteht.
struct SeriesSource {
    let image: CGImage
    let thumbnail: CGImage
    /// Version im Verlauf, falls das Bild von dort stammt (für den Vorher/Nachher-Vergleich).
    var versionID: UUID?

    init(image: CGImage, versionID: UUID?) {
        self.image = image
        self.thumbnail = ImageTools.scaled(image, maxSide: 480)
        self.versionID = versionID
    }

    var size: CGSize { CGSize(width: image.width, height: image.height) }
}

/// Ein Bild der Serie: erst schreibt Gemma den Prompt, dann rendert Draw Things.
struct SeriesItem: Identifiable {
    enum Phase: Equatable {
        case waiting
        case writing
        case queued
        case rendering
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let number: Int
    let value: String
    var prompt = ""
    /// Gemma war nicht erreichbar – der Prompt stammt aus einer einfachen Vorlage.
    var usesTemplate = false
    var phase: Phase = .waiting
    var image: CGImage?
    var versionID: UUID?
    var fileURL: URL?
    var seed: UInt32?
    var duration: TimeInterval?

    /// Wartet noch auf Gemma oder Draw Things.
    var isPending: Bool {
        switch phase {
        case .waiting, .writing, .queued, .rendering: true
        default: false
        }
    }
}

/// Eine gestartete Serie mit ihren Ergebnissen.
struct SeriesRun: Identifiable {
    let id = UUID()
    let variable: SeriesVariable
    let variableName: String
    let source: SeriesSource
    let size: CGSize
    /// Prompt aus der Seitenleiste – gilt für alle Bilder.
    let commonPrompt: String
    /// Gemeinsamer Seed (nil = je Bild neu bzw. wie in Draw Things eingestellt).
    let seed: UInt32?
    var items: [SeriesItem]
    var isRunning = true
    let startedAt = Date()

    var doneCount: Int { items.filter { $0.phase == .done }.count }
    var hasUnfinished: Bool { items.contains { $0.phase != .done } }
}
