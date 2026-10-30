import CoreGraphics
import Foundation

/// Wofür ein Referenzbild steht – bestimmt, was Gemma darin beschreibt
/// und wie es im Prompt auftaucht.
enum ReferenceRole: String, CaseIterable, Identifiable, Codable {
    case identity
    case outfit
    case footwear
    case accessory
    case location
    case style
    case pose
    case object
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identity: "Person"
        case .outfit: "Kleidung"
        case .footwear: "Schuhe"
        case .accessory: "Accessoire"
        case .location: "Ort"
        case .style: "Stil"
        case .pose: "Pose"
        case .object: "Objekt / Produkt"
        case .general: "Allgemein"
        }
    }

    var symbol: String {
        switch self {
        case .identity: "person.crop.circle"
        case .outfit: "tshirt"
        case .footwear: "shoe"
        case .accessory: "eyeglasses"
        case .location: "mountain.2"
        case .style: "paintpalette"
        case .pose: "figure.wave"
        case .object: "shippingbox"
        case .general: "photo"
        }
    }

    /// Satz, wenn das Bild selbst an Draw Things geht (als „Picture n“).
    func sentence(imageNumber n: Int) -> String {
        switch self {
        case .identity: "Picture \(n) shows the person – keep the face, facial features, hairstyle and skin tone exactly consistent."
        case .outfit: "Picture \(n) shows the outfit – the person wears exactly this outfit with all its colors and details."
        case .footwear: "Picture \(n) shows the shoes – the person wears exactly these shoes with all their colors and details."
        case .accessory: "Picture \(n) shows the accessory – the person carries or wears exactly this item, keep its shape, colors and details."
        case .location: "Picture \(n) shows the location – place the scene there and keep its architecture and atmosphere."
        case .style: "Adopt the visual style, color grading and lighting of Picture \(n)."
        case .pose: "Picture \(n) shows the pose – the person takes exactly this body pose and gesture."
        case .object: "Picture \(n) shows the product – keep its shape, colors, materials, logos and proportions exactly the same."
        case .general: "Use the content of Picture \(n)."
        }
    }

    /// Satz, wenn nur Gemmas Beschreibung in den Prompt kommt.
    func sentence(description: String) -> String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        switch self {
        case .identity: return text
        case .outfit:
            return text.lowercased().hasPrefix("wearing") ? "The person is \(text)" : "Outfit: \(text)"
        case .footwear:
            return text.lowercased().hasPrefix("wearing") ? "The person is \(text)" : "Shoes: \(text)"
        case .accessory: return "Accessory: \(text)"
        case .location: return "The setting: \(text)"
        case .style: return "Visual style: \(text)"
        case .pose: return "Pose: \(text)"
        case .object: return "The scene includes this object: \(text)"
        case .general: return text
        }
    }

    /// Satz für „Bearbeiten“, wenn ein Asset nur als Beschreibung mitkommt – als Anweisung für Qwen Image Edit.
    func editSentence(description: String) -> String {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        switch self {
        case .identity: return "The person: \(text)"
        case .outfit: return "Change the clothing to this outfit, \(text)"
        case .footwear: return "Change the shoes to these, \(text)"
        case .accessory: return "Add this accessory: \(text)"
        case .location: return "Replace the background with this setting: \(text)"
        case .style: return "Restyle the image in this visual style: \(text)"
        case .pose: return "Change the pose to this: \(text)"
        case .object: return "Add this object at a natural position: \(text)"
        case .general: return text
        }
    }
}

struct ReferenceSlot: Identifiable {
    let id = UUID()
    var image: CGImage? {
        didSet { thumbnail = image.map { ImageTools.scaled($0, maxSide: 480) } }
    }
    private(set) var thumbnail: CGImage?
    var role: ReferenceRole
    var description = ""
    var isAnalyzing = false
    var error: String?
    /// Charakter statt eines einzelnen Fotos – das Referenzbild entsteht beim Rendern passend zur Bildgröße.
    var personaID: UUID?
    /// Asset aus dem Asset-Baukasten, aus dem das Bild stammt.
    var assetID: UUID?
    /// Eigenes Thema seiner Kategorie („hairstyle“) – ersetzt die Rolle im Prompt.
    var assetSubject: String?
    var personaMode: PersonaReferenceMode = .sheet
    /// Bild aus der Galerie, aus dem der Platz stammt – damit „Markiertes Bild mitnehmen“ es nicht doppelt einsetzt.
    var galleryItemID: UUID?
}
