import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var lmStudioURL: String { didSet { defaults.set(lmStudioURL, forKey: "lmStudioURL") } }
    var lmModel: String { didSet { defaults.set(lmModel, forKey: "lmModel") } }
    var drawThingsURL: String { didSet { defaults.set(drawThingsURL, forKey: "drawThingsURL") } }
    var randomSeed: Bool { didSet { defaults.set(randomSeed, forKey: "randomSeed") } }
    var switchModelPerMode: Bool { didSet { defaults.set(switchModelPerMode, forKey: "modelPerMode") } }
    var generateModelFile: String { didSet { defaults.set(generateModelFile, forKey: "generateModelFile") } }
    var editModelFile: String { didSet { defaults.set(editModelFile, forKey: "editModelFile") } }
    var sendAllReferences: Bool { didSet { defaults.set(sendAllReferences, forKey: "sendAllReferences") } }
    var autosave: Bool { didSet { defaults.set(autosave, forKey: "autosave") } }
    /// Ordner der geöffneten Bibliothek.
    var libraryPath: String { didSet { defaults.set(libraryPath, forKey: "libraryPath") } }
    /// Alle bekannten Bibliotheken (auch auf gerade nicht eingesteckten Laufwerken).
    var libraryPaths: [String] { didSet { defaults.set(libraryPaths, forKey: "libraryPaths") } }
    var lastAspectID: String { didSet { defaults.set(lastAspectID, forKey: "lastAspectID") } }
    /// Größenstufe Klein · Normal · Groß (wie in Draw Things).
    var lastSizeTier: String { didSet { defaults.set(lastSizeTier, forKey: "lastSizeTier") } }
    /// Seitenleiste und Inspector: matt wie gewohnt oder Liquid Glass, das den Schreibtisch durchscheinen lässt.
    var interfaceStyle: InterfaceStyle { didSet { defaults.set(interfaceStyle.rawValue, forKey: "interfaceStyle") } }

    private init() {
        let d = UserDefaults.standard
        lmStudioURL = d.string(forKey: "lmStudioURL") ?? "http://127.0.0.1:1234"
        lmModel = d.string(forKey: "lmModel") ?? "gemma-4-e4b-uncensored-hauhaucs-aggressive"
        drawThingsURL = d.string(forKey: "drawThingsURL") ?? "http://127.0.0.1:7860"
        randomSeed = d.object(forKey: "randomSeed") as? Bool ?? true
        // Modell je Modus ist seit dem 11.10.2026 Standard (neuer Schlüssel, alte Abwahl gilt nicht mehr).
        switchModelPerMode = d.object(forKey: "modelPerMode") as? Bool ?? true
        generateModelFile = d.string(forKey: "generateModelFile") ?? "qwen_image_1.0_q6p.ckpt"
        editModelFile = d.string(forKey: "editModelFile") ?? "qwen_image_edit_2511_q6p.ckpt"
        sendAllReferences = d.object(forKey: "sendAllReferences") as? Bool ?? false
        autosave = d.object(forKey: "autosave") as? Bool ?? true
        // Vor den Bibliotheken hieß der Ordner „Ablageordner“ (autosaveFolder) – er wird die erste Bibliothek.
        let library = d.string(forKey: "libraryPath") ?? d.string(forKey: "autosaveFolder") ?? Library.defaultURL.path
        libraryPath = library
        libraryPaths = d.stringArray(forKey: "libraryPaths") ?? [library]
        lastAspectID = d.string(forKey: "lastAspectID") ?? AspectRatio.square.id
        // Bis 12.10.2026 gab es Standard und 2K (lastResolution) – 2K wird zu Groß.
        lastSizeTier = d.string(forKey: "lastSizeTier")
            ?? (d.string(forKey: "lastResolution") == "twoK" ? SizeTier.large : SizeTier.normal).rawValue
        interfaceStyle = InterfaceStyle(rawValue: d.string(forKey: "interfaceStyle") ?? "") ?? .solid
    }

    func modelFile(for mode: StudioMode) -> String {
        mode == .generate ? generateModelFile : editModelFile
    }
}
