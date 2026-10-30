import Foundation

/// Videomodell, für das Gemma die Clips einer Story schreibt. Generiert wird außerhalb der App –
/// das Preset sagt Gemma, wie das Modell Prompts versteht, und dir, wie du es bedienst.
/// Bisher nur Gemini Omni; weitere Modelle kommen als weitere Presets dazu.
struct VideoPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let maker: String
    /// Mögliche Längen eines Clips in Sekunden.
    let durations: [Int]
    let defaultDuration: Int
    /// Kurzbeschreibung unter der Auswahl.
    let summary: String
    /// Gemmas Regeln für den Prompt eines Clips (englisch).
    let clipInstructions: String
    /// So machst du in der App des Anbieters aus Start- und Endbild ein Video.
    let steps: [String]
    let guideURL: URL?

    static func preset(_ id: String) -> VideoPreset {
        all.first { $0.id == id } ?? geminiOmni
    }

    static var all: [VideoPreset] { [geminiOmni] }

    /// Google Gemini Omni (Omni Flash, I/O 2026) – Start- und Endbild, ein durchgehender Shot, Ton immer dabei.
    /// Recherchiert am 16.10.2026 aus Googles Prompt-Anleitung (deepmind.google/models/gemini-omni/prompt-guide)
    /// und der Gemini-API-Doku (ai.google.dev/gemini-api/docs/omni):
    /// - Erstes und letztes Bild mitgeben, dann den Übergang beschreiben: was das erste Bild zeigt, welcher Weg
    ///   (Kamera, Bewegung) dazwischen liegt und was das letzte Bild genau zeigt.
    /// - „single continuous shot“ / „no scene cuts“, sonst schneidet Omni gern selbst.
    /// - Kamera mit Begriffen wie static / locked off, push in, dolly, orbit; Licht, Ort, Handlung kurz – Omni
    ///   braucht weniger Vorgaben als Veo und füllt Details aus seinem Weltwissen.
    /// - Kein Feld für negative Prompts: Ausschlüsse als kurze Sätze („No dialogue.“). Ton beschreiben, sonst
    ///   erfindet Omni Musik. Zeitangaben natürlich („After 3 seconds …“) oder als [0-3s].
    /// - Clips 3–10 s (in Gemini und Flow), 16:9 oder 9:16, Ton wird immer erzeugt.
    static let geminiOmni = VideoPreset(
        id: "gemini-omni",
        name: "Gemini Omni",
        maker: "Google",
        durations: [4, 6, 8, 10],
        defaultDuration: 8,
        summary: "Start- und Endbild, ein durchgehender Shot · 3–10 s je Clip · 16:9 oder 9:16 · mit Ton",
        clipInstructions: PromptTemplates.geminiOmniClip,
        steps: [
            "Öffne Gemini (Video erstellen) oder Google Flow und wähle Gemini Omni.",
            "Hänge zuerst das Startbild, dann das Endbild an – in Flow in die Felder für Start- und Endbild.",
            "Füge den Prompt des Clips ein.",
            "Stelle Format und Länge ein, falls die App sie anbietet.",
            "Den fertigen Clip in die Galerie ziehen – er landet in der Bibliothek.",
        ],
        guideURL: URL(string: "https://deepmind.google/models/gemini-omni/prompt-guide/")
    )
}
