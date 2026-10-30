import Foundation

/// Die vier Arbeitsweisen der App – umschaltbar oben in der Toolbar.
enum StudioMode: String, CaseIterable, Identifiable, Codable {
    case generate
    case edit
    case references
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generate: "Generieren"
        case .edit: "Bearbeiten"
        case .references: "Referenzen"
        case .series: "Serien"
        }
    }

    var longTitle: String {
        switch self {
        case .generate: "Bild generieren"
        case .edit: "Bild bearbeiten"
        case .references: "Mit Referenzen arbeiten"
        case .series: "Bilderserie erstellen"
        }
    }

    var symbol: String {
        switch self {
        case .generate: "sparkles"
        case .edit: "paintbrush.pointed"
        case .references: "photo.stack"
        case .series: "square.grid.2x2"
        }
    }

    /// Bildmodell, für das der Prompt geschrieben wird.
    var modelName: String {
        switch self {
        case .generate: "Qwen Image 1.0"
        case .edit, .references, .series: "Qwen Image Edit 2511"
        }
    }

    var actionTitle: String {
        switch self {
        case .generate: "Generieren"
        case .edit: "Anwenden"
        case .references: "Komponieren"
        case .series: "Serie starten"
        }
    }

    var actionSymbol: String {
        switch self {
        case .generate: "sparkles"
        case .edit: "wand.and.stars"
        case .references: "square.stack.3d.up.fill"
        case .series: "square.grid.2x2.fill"
        }
    }

    var shortcutKey: Character {
        switch self {
        case .generate: "1"
        case .edit: "2"
        case .references: "3"
        case .series: "4"
        }
    }

    /// Passt das in Draw Things geladene Modell zu diesem Modus?
    func matches(drawThingsModel file: String) -> Bool {
        let name = file.lowercased()
        switch self {
        case .generate: return !name.contains("edit")
        case .edit, .references, .series: return name.contains("edit") || name.contains("kontext")
        }
    }

    /// Unter welchem Modus die gemessene Renderdauer gespeichert wird –
    /// eine Serie bearbeitet ein Bild wie „Bearbeiten“ und teilt sich deshalb die Messung.
    var timingMode: StudioMode { self == .series ? .edit : self }
}
