import CoreGraphics
import Foundation

/// Ein Stand des Bildes auf dem Canvas. Jede Generierung, Bearbeitung oder
/// Anpassung legt eine neue Version an – nichts geht verloren.
struct ImageVersion: Identifiable, Equatable {
    enum Source: Equatable {
        case generated(StudioMode)
        case imported
        case adjusted
        case transformed

        var title: String {
            switch self {
            case .generated(.generate): "Generiert"
            case .generated(.edit): "Bearbeitet"
            case .generated(.references): "Aus Referenzen"
            case .generated(.series): "Aus Serie"
            case .imported: "Importiert"
            case .adjusted: "Angepasst"
            case .transformed: "Transformiert"
            }
        }

        var symbol: String {
            switch self {
            case .generated(let mode): mode.symbol
            case .imported: "square.and.arrow.down"
            case .adjusted: "slider.horizontal.3"
            case .transformed: "crop.rotate"
            }
        }

        /// Kürzel im Dateinamen und in der Galerie.
        var fileKind: String {
            switch self {
            case .generated(let mode): mode.rawValue
            case .adjusted: "adjusted"
            case .transformed: "transformed"
            case .imported: "imported"
            }
        }

        init(fileKind: String) {
            switch fileKind {
            case "adjusted": self = .adjusted
            case "transformed": self = .transformed
            case "imported": self = .imported
            default: self = StudioMode(rawValue: fileKind).map { .generated($0) } ?? .imported
            }
        }
    }

    let id: UUID
    let image: CGImage
    let thumbnail: CGImage
    let prompt: String
    let source: Source
    let createdAt: Date
    var seed: UInt32?
    var duration: TimeInterval?
    var fileURL: URL?
    /// Version, aus der diese entstanden ist (für den Vorher/Nachher-Vergleich).
    var parentID: UUID?
    /// Bild einer Serie – damit die Galerie es im richtigen Stapel ablegt.
    var series: SeriesTag?
    /// Charaktere, deren Referenz in dieses Bild eingeflossen ist.
    var personaIDs: [UUID] = []

    init(id: UUID = UUID(), image: CGImage, prompt: String, source: Source, seed: UInt32? = nil, duration: TimeInterval? = nil, parentID: UUID? = nil, series: SeriesTag? = nil, createdAt: Date = .now) {
        self.id = id
        self.createdAt = createdAt
        self.parentID = parentID
        self.series = series
        self.image = image
        self.thumbnail = ImageTools.scaled(image, maxSide: 360)
        self.prompt = prompt
        self.source = source
        self.seed = seed
        self.duration = duration
    }

    var size: CGSize { CGSize(width: image.width, height: image.height) }

    static func == (lhs: ImageVersion, rhs: ImageVersion) -> Bool {
        lhs.id == rhs.id && lhs.fileURL == rhs.fileURL
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case adjust, crop, selection, analysis, references, series, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adjust: "Anpassen"
        case .crop: "Zuschneiden & Ausrichten"
        case .selection: "Auswahl"
        case .analysis: "Analyse"
        case .references: "Referenzen"
        case .series: "Serie"
        case .history: "Verlauf"
        }
    }

    var symbol: String {
        switch self {
        case .adjust: "slider.horizontal.3"
        case .crop: "crop.rotate"
        case .selection: "lasso"
        case .analysis: "text.viewfinder"
        case .references: "photo.stack"
        case .series: "square.grid.2x2"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// Zuschnitt in normierten Koordinaten (0 … 1, Ursprung oben links) plus Begradigung.
struct CropState: Equatable {
    var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var angle: Double = 0
    /// Breite/Höhe in Pixeln, nil = frei.
    var lockedRatio: Double?
    var ratioID = "free"

    var isIdentity: Bool { rect == CGRect(x: 0, y: 0, width: 1, height: 1) && angle == 0 }
}

enum SelectionSource {
    case subject, people, painted, inverted

    /// Beschreibung für Gemma, welcher Bereich übernommen wird.
    var promptHint: String {
        switch self {
        case .subject: "Only the main subject area of the result will be kept; the rest of Picture 1 stays as it is. Focus the instruction on the main subject."
        case .people: "Only the people in the result will be kept; the rest of Picture 1 stays as it is. Focus the instruction on the people."
        case .inverted: "Only the background (everything except the main subject) will be kept from the result. Focus the instruction on the background."
        case .painted: "Only a hand-selected region of the result will be kept; the rest of Picture 1 stays as it is."
        }
    }
}

enum SelectionTool: String, CaseIterable, Identifiable {
    case brush, eraser, hand

    var id: String { rawValue }
    var title: String {
        switch self {
        case .brush: "Pinsel"
        case .eraser: "Radierer"
        case .hand: "Hand"
        }
    }
    var symbol: String {
        switch self {
        case .brush: "paintbrush.pointed"
        case .eraser: "eraser"
        case .hand: "hand.raised"
        }
    }
}

/// Was Apples Vision gerade rechnet (für Fortschrittsanzeigen).
enum VisionTask: Equatable {
    case subject, people, horizon, saliency, text
}

/// Werkzeug, das Mausaktionen auf dem Canvas bekommt.
enum CanvasTool: Equatable {
    case none, crop, brush, eraser, pipette, compare
}

/// Draw Things meldet über die HTTP-API keinen Schrittfortschritt. Der Balken läuft
/// deshalb gegen eine geschätzte Dauer, die aus dem letzten Durchlauf stammt
/// (umgerechnet auf Bildfläche und Schrittzahl).
struct GenerationProgress {
    let id = UUID()
    let mode: StudioMode
    let startedAt: Date
    let size: CGSize
    let estimate: TimeInterval
    /// false = Startwert, noch nicht auf diesem Rechner gemessen.
    let isCalibrated: Bool
    /// Name des Modells, das Draw Things für diesen Durchlauf erst laden muss.
    var loadingModel: String? = nil

    /// 0 … 1. Bis zur Schätzung linear auf 95 %, danach nähert sich der Balken langsam 99 %.
    func fraction(at date: Date) -> Double {
        let elapsed = max(date.timeIntervalSince(startedAt), 0)
        guard estimate > 0 else { return 0 }
        let ratio = elapsed / estimate
        if ratio < 1 { return 0.95 * ratio }
        return 0.95 + 0.04 * (1 - exp(-(ratio - 1) * 2.5))
    }

    func remaining(at date: Date) -> TimeInterval {
        max(estimate - date.timeIntervalSince(startedAt), 0)
    }
}

/// Gemessene Dauer eines Durchlaufs, je Modus gespeichert.
struct RunTiming: Codable {
    var seconds: TimeInterval
    var area: Double
    var steps: Int
    var isMeasured: Bool

    /// Startwerte aus Tests mit Qwen Image (Edit) Q6P, 4 Schritten, 896 × 1152 Pixeln.
    static func fallback(for mode: StudioMode) -> RunTiming {
        RunTiming(seconds: mode == .generate ? 135 : 250, area: 896 * 1152, steps: 4, isMeasured: false)
    }

    func estimate(area newArea: Double, steps newSteps: Int?) -> TimeInterval {
        let stepFactor = Double(max(newSteps ?? steps, 1)) / Double(max(steps, 1))
        return seconds * (newArea / max(area, 1)) * stepFactor
    }

    static func load(for mode: StudioMode) -> RunTiming {
        guard let data = UserDefaults.standard.data(forKey: "runTiming.\(mode.rawValue)"),
              let timing = try? JSONDecoder().decode(RunTiming.self, from: data) else { return fallback(for: mode) }
        return timing
    }

    func save(for mode: StudioMode) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "runTiming.\(mode.rawValue)")
        }
    }
}

struct OptimizerState {
    var isRunning = false
    var text = ""
    var error: String?
    var mode: StudioMode = .generate

    var isVisible: Bool { isRunning || !text.isEmpty || error != nil }
}

enum AnalysisKind: String {
    case reversePrompt, recognize, subject, style, question, text

    var title: String {
        switch self {
        case .reversePrompt: "Prompt aus Bild"
        case .recognize: "Erkannte Bausteine"
        case .subject: "Subjekt"
        case .style: "Stil & Licht"
        case .question: "Antwort"
        case .text: "Text im Bild"
        }
    }

    var symbol: String {
        switch self {
        case .reversePrompt: "text.viewfinder"
        case .recognize: "square.grid.3x3.topleft.filled"
        case .subject: "person.text.rectangle"
        case .style: "camera.filters"
        case .question: "bubble.left.and.text.bubble.right"
        case .text: "text.magnifyingglass"
        }
    }

    /// Ergebnis ist ein englischer Prompt-Text, der sich übernehmen lässt.
    var producesPrompt: Bool { self != .recognize && self != .question && self != .text }
}

struct AnalysisResult: Identifiable {
    let id = UUID()
    let kind: AnalysisKind
    var question: String?
    var text = ""
    var isRunning = true
    var error: String?
    var recognized: [String: [String]] = [:]
    var lines: [String] = []
    let thumbnail: CGImage?
}

struct SavedPrompt: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var mode: StudioMode
    var savedAt = Date()
}
