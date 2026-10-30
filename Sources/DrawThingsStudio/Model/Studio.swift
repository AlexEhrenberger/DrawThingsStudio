import AppKit
import Observation
import SwiftUI

/// Zentraler Zustand der App: Dokument, Versionen, Verbindungen und Gemma.
@MainActor
@Observable
final class Studio {
    let settings = AppSettings.shared
    let builder = PromptBuilder()
    /// Katalog, Charaktere und Assets der geöffneten Bibliothek – nur über `openLibrary` austauschen.
    var gallery: Gallery
    var personas: PersonaStore
    var assets: AssetStore
    /// Die geöffnete Bibliothek ist erreichbar (z. B. die SD-Karte steckt).
    var isLibraryAvailable = true
    /// Bibliothek, für die gerade „Löschen?“ gefragt wird.
    var libraryDeletion: LibraryEntry?
    @ObservationIgnored var volumeObservers: [Any] = []

    /// Galerie (wie Lightrooms Bibliothek), Studio mit den vier Modi oder Labs.
    var showGallery = true {
        didSet {
            if !showGallery { isFocusMode = false }
            if showGallery {
                showLabs = false
                // Wer in die Galerie geht, markiert dort neu – die Marke der letzten Runde gilt nicht mehr.
                galleryMark = nil
            }
        }
    }
    /// Labs: eigener, dunkler Bereich mit Experimenten – statt Galerie oder Studio.
    var showLabs = false {
        didSet { if showLabs { showGallery = false } }
    }
    /// Fokusmodus der Galerie: Vollbild, schwarz, nur die Bilder.
    var isFocusMode = false {
        didSet {
            guard isFocusMode != oldValue else { return }
            if isFocusMode {
                showGallery = true
                enterFocusFullScreen()
            } else {
                leaveFocusFullScreen()
            }
        }
    }
    @ObservationIgnored var focusEnteredFullScreen = false

    var mode: StudioMode = .generate {
        didSet {
            guard mode != oldValue else { return }
            builder.mode = mode
            updateReferenceSentences()
            updateAssetSentence()
            updateAssistSentence()
            announceModel()
            if mode == .references { inspectorTab = .references }
            if oldValue == .references && inspectorTab == .references { inspectorTab = .adjust }
            if mode == .series {
                inspectorTab = .series
                showInspector = true
                adoptSeriesSourceIfNeeded()
            }
            if oldValue == .series && inspectorTab == .series { inspectorTab = .adjust }
        }
    }

    // MARK: Dokument

    var aspect: AspectRatio?
    var versions: [ImageVersion] = []
    var currentID: UUID? {
        didSet {
            guard currentID != oldValue else { return }
            previewBaseCache = nil
            adjustments = Adjustments()
            crop = CropState()
            cropPreview = nil
            isPickingWhiteBalance = false
            identityAssistFollowCurrent()
        }
    }
    var showNewImageSheet = false
    var isComparing = false
    /// Vorher/Nachher-Regler: beide Bilder übereinander, getrennt durch eine verschiebbare Linie.
    var isSplitComparing = false {
        didSet {
            if isSplitComparing && (inspectorTab == .crop || inspectorTab == .selection) { inspectorTab = .adjust }
        }
    }
    var splitPosition: Double = 0.5
    var zoom: Double?   // nil = ins Fenster einpassen
    var canvasPan: CGSize = .zero
    @ObservationIgnored var fitScale: Double = 1
    /// Eingepasster Maßstab für die Prozentanzeige – nachgezogen, sobald das Layout steht.
    var shownFitScale: Double = 1
    @ObservationIgnored var canvasSize: CGSize = .zero
    @ObservationIgnored var contentPixelSize: CGSize = .zero
    /// Klein · Normal · Groß – gilt für die nächste Generierung, Bearbeitung, Komposition oder Serie.
    var sizeTier: SizeTier = .normal {
        didSet { settings.lastSizeTier = sizeTier.rawValue }
    }
    /// Format für „Bearbeiten“ – nil = automatisch das Draw-Things-Format, das dem Bild am nächsten kommt.
    /// Gilt, bis ein anderes Bild ins Studio kommt.
    var editAspect: AspectRatio?

    var current: ImageVersion? { versions.first { $0.id == currentID } }

    /// Ausgangsversion der aktuellen (sonst die vorige in der Liste).
    var comparisonBase: ImageVersion? {
        if let parentID = current?.parentID, let parent = versions.first(where: { $0.id == parentID }) { return parent }
        return previousVersion
    }

    /// Bildpaar für den Vergleich: offene Anpassungen gegen Original, sonst Ausgangsversion gegen aktuelle.
    var comparisonPair: (before: CGImage, after: CGImage)? {
        guard let current else { return nil }
        if !adjustments.isIdentity, let adjustedPreview { return (current.image, adjustedPreview) }
        guard let base = comparisonBase else { return nil }
        return (base.image, current.image)
    }

    var previousVersion: ImageVersion? {
        guard let index = versions.firstIndex(where: { $0.id == currentID }), index > 0 else { return nil }
        return versions[index - 1]
    }

    /// Was der Canvas zeigt: Vorher-Ansicht, Begradigungs- oder Anpassungs-Vorschau oder die aktuelle Version.
    var displayImage: CGImage? {
        if isComparing, let comparisonBase { return comparisonBase.image }
        if inspectorTab == .crop, crop.angle != 0, let cropPreview { return cropPreview }
        if !adjustments.isIdentity, let adjustedPreview { return adjustedPreview }
        return current?.image
    }

    /// Verkleinerte Fassung der aktuellen Version für flüssige Vorschauen.
    var previewBase: CGImage? {
        guard let current else { return nil }
        if let cached = previewBaseCache, cached.id == current.id { return cached.image }
        let image = ImageTools.scaled(current.image, maxSide: 2048)
        previewBaseCache = (current.id, image)
        return image
    }
    @ObservationIgnored private var previewBaseCache: (id: UUID, image: CGImage)?

    // MARK: Zuschneiden & Auswahl

    var crop = CropState() {
        didSet { if crop.angle != oldValue.angle { scheduleCropPreview() } }
    }
    var cropPreview: CGImage?
    @ObservationIgnored var cropPreviewTask: Task<Void, Never>?

    var selectionMask: CGImage? {
        didSet { selectionOverlay = selectionMask.flatMap { ImageTools.selectionOverlay($0, color: NSColor.controlAccentColor.cgColor) } }
    }
    private(set) var selectionOverlay: CGImage?
    var selectionSource: SelectionSource = .painted
    var selectionTool: SelectionTool = .brush
    var brushDiameter: Double = 0.06
    var selectionFeather: Double = 0.004
    var applyEditToSelection = true
    var showSelectionOverlay = true
    var isPickingWhiteBalance = false
    var visionTask: VisionTask?

    // MARK: Anpassen

    var adjustments = Adjustments() {
        didSet { if adjustments != oldValue { scheduleAdjustmentPreview() } }
    }
    private(set) var adjustedPreview: CGImage?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    // MARK: Oberfläche

    var showInspector = true
    var inspectorTab: InspectorTab = .adjust {
        didSet { if inspectorTab == .crop || inspectorTab == .selection { isSplitComparing = false } }
    }
    var errorMessage: String?

    // MARK: Generierung

    private(set) var generation: GenerationProgress?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var dockTask: Task<Void, Never>?

    // MARK: Verbindungen

    var lmStatus: LMStatus = .unknown
    var lmBusy = 0
    var dtConfig: DrawThingsConfig?
    var dtReachable: Bool?
    /// Modell, das die App zuletzt an Draw Things geschickt hat (die HTTP-API meldet einen Wechsel nicht zurück).
    private(set) var lastSentModel: String?
    /// Kurzer Hinweis nach dem Moduswechsel, welches Modell jetzt dran ist.
    var modelNotice: String?
    var lmModels: [String] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    var lm: LMStudioClient { LMStudioClient(baseURL: settings.lmStudioURL, model: settings.lmModel) }
    var drawThings: DrawThingsClient { DrawThingsClient(baseURL: settings.drawThingsURL) }

    // MARK: Gemma

    var optimizer = OptimizerState()
    var gemmaWish = ""
    @ObservationIgnored var optimizerTask: Task<Void, Never>?
    var analysisSource: CGImage? {
        didSet { analysisThumbnail = analysisSource.map { ImageTools.scaled($0, maxSide: 240) } }
    }
    private(set) var analysisThumbnail: CGImage?
    var analysisResults: [AnalysisResult] = []

    // MARK: Referenzen

    /// Bild(er), die die Galerie beim Verlassen markiert hatte – je Modus einmal eingelöst (`switchTo`).
    @ObservationIgnored var galleryMark: GalleryMark?
    var references: [ReferenceSlot] = [
        ReferenceSlot(role: .identity),
        ReferenceSlot(role: .outfit),
        ReferenceSlot(role: .location),
    ]

    // MARK: Serien

    var seriesSetup = SeriesSetup() {
        didSet { if seriesSetup != oldValue { seriesSetup.save(root: gallery.root) } }
    }
    var seriesSource: SeriesSource?
    var seriesRun: SeriesRun?
    @ObservationIgnored var seriesTask: Task<Void, Never>?

    // MARK: Assets

    /// Im Asset-Baukasten gewählte Assets – außerhalb von „Referenzen“ kommt ihre Beschreibung in den Prompt.
    var selectedAssetIDs: [UUID] = []
    /// Assets, die Gemma noch beschreiben soll – nacheinander, nie gleichzeitig.
    @ObservationIgnored var assetQueue: [UUID] = []
    @ObservationIgnored var assetDescribeTask: Task<Void, Never>?

    // MARK: Charaktere

    /// Charakter, dessen Bibliotheksauswahl die Charakterseite öffnen soll – das Kontextmenü der Seitenleiste
    /// kann kein Sheet zeigen und stellt nur die Anfrage.
    var personaLibraryRequest: UUID?
    /// Gesichtsreferenz beim Bearbeiten: Ansichten des Charakters als Raster neben dem Bild.
    var identityAssist: IdentityAssist?
    /// Laufender Vergleich Raster gegen Einzelfoto.
    var personaTest: PersonaTest?
    @ObservationIgnored var personaTestTask: Task<Void, Never>?
    /// Charakter, den Gemma gerade beschreibt.
    var describingPersonaID: UUID?

    // MARK: Labs

    /// „Bild zusammenbauen“: Canvas, drei Moodboards, Anweisungen und Gemmas Prompt.
    var composition = LabComposition() {
        didSet { scheduleLabsSave() }
    }
    @ObservationIgnored var labsTask: Task<Void, Never>?
    @ObservationIgnored var labsSaveTask: Task<Void, Never>?
    /// Ordner `Katalog/Labs` der geöffneten Bibliothek – nil, solange keine offen ist (Wechsel, Löschen).
    @ObservationIgnored var labsFolder: URL?
    @ObservationIgnored var labsRestoring = false

    // MARK: Stories

    /// Laufende Präsentation einer Story – im Vollbild oder im Fenster.
    var presentation: StoryPresentation?
    /// Die Präsentation hat das Fenster ins Vollbild gebracht – beim Beenden wieder heraus.
    @ObservationIgnored var presentationEnteredFullScreen = false
    /// Gemma schreibt gerade Handlung oder Clips einer Story.
    var storyWriting: StoryWriting?
    /// Letzter Fehler beim Schreiben, je Story.
    var storyErrors: [UUID: String] = [:]
    @ObservationIgnored var storyTask: Task<Void, Never>?

    // MARK: Bibliothek

    var library: [SavedPrompt] = []
    /// Kategorie, die der Bausteine-Editor beim Öffnen anzeigen soll.
    var editorFocusKey: String?

    init() {
        let root = URL(fileURLWithPath: AppSettings.shared.libraryPath).standardizedFileURL
        Library.root = root
        Library.migrateLegacyData(into: root)
        gallery = Gallery(root: root)
        personas = PersonaStore(root: root)
        assets = AssetStore(root: root)
        isLibraryAvailable = Library.isAvailable(root)
        sizeTier = SizeTier(rawValue: settings.lastSizeTier) ?? .normal
        // Bausteine, Entwurf, Serien-Werte und gespeicherte Prompts gehören zur Bibliothek.
        CatalogStore.shared.open(root: root)
        builder.mode = mode
        builder.open(root: root)
        seriesSetup = SeriesSetup.load(root: root)
        loadLibrary()
        openLabs(root: root)
        personas.adoptLegacyTestScene()
        // Geänderte Bausteine sofort im Prompt nachziehen.
        CatalogStore.shared.onChange = { [weak self] in self?.builder.recompose() }
        observeVolumes()
        observeFullScreenExit()
    }

    // MARK: - Dokument & Versionen

    func newDocument(_ ratio: AspectRatio) {
        aspect = ratio
        editAspect = nil
        settings.lastAspectID = ratio.id
        versions = []
        currentID = nil
        zoom = nil
        canvasPan = .zero
        showNewImageSheet = false
        showGallery = false
        showLabs = false
        galleryMark = nil
        if mode != .references { mode = .generate }
    }

    // MARK: Canvas-Navigation

    private var currentScale: Double { zoom ?? fitScale }

    /// Zoomen um die Mitte (Knöpfe, ⌘+ / ⌘−).
    func zoom(by factor: Double) {
        let old = currentScale
        let new = min(max(old * factor, 0.05), 8)
        withAnimation(.smooth(duration: 0.25)) {
            canvasPan = CGSize(width: canvasPan.width * new / old, height: canvasPan.height * new / old)
            zoom = new
            clampPan()
        }
    }

    /// Zoomen um einen Punkt der Arbeitsfläche (Pinch, ⌘-Scrollen) – der Punkt bleibt unter dem Zeiger.
    func zoom(by factor: Double, at point: CGPoint) {
        let old = currentScale
        let new = min(max(old * factor, 0.05), 8)
        guard new != old else { return }
        let k = new / old
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        canvasPan = CGSize(
            width: point.x - center.x - (point.x - center.x - canvasPan.width) * k,
            height: point.y - center.y - (point.y - center.y - canvasPan.height) * k
        )
        zoom = new
        clampPan()
    }

    func pan(by delta: CGSize) {
        canvasPan = CGSize(width: canvasPan.width + delta.width, height: canvasPan.height + delta.height)
        clampPan()
    }

    /// Bild zentrieren und ans Fenster anpassen.
    func fitToWindow() {
        withAnimation(.smooth(duration: 0.3)) {
            zoom = nil
            canvasPan = .zero
        }
    }

    /// 100 % ↔ Einpassen; mit Punkt bleibt die Stelle unter dem Zeiger.
    func toggleActualSize(at point: CGPoint? = nil) {
        if zoom == nil || abs(currentScale - 1) > 0.01 {
            withAnimation(.smooth(duration: 0.3)) {
                if let point { zoom(by: 1 / currentScale, at: point) } else { canvasPan = .zero; zoom = 1 }
            }
        } else {
            fitToWindow()
        }
    }

    func actualSize() {
        withAnimation(.smooth(duration: 0.3)) {
            canvasPan = .zero
            zoom = 1
        }
    }

    /// Mindestens ein Stück des Bildes bleibt sichtbar.
    private func clampPan() {
        guard canvasSize.width > 0, contentPixelSize.width > 0 else { return }
        let display = CGSize(width: contentPixelSize.width * currentScale, height: contentPixelSize.height * currentScale)
        let maxX = max((display.width + canvasSize.width) / 2 - 80, 0)
        let maxY = max((display.height + canvasSize.height) / 2 - 80, 0)
        canvasPan = CGSize(width: min(max(canvasPan.width, -maxX), maxX), height: min(max(canvasPan.height, -maxY), maxY))
    }

    func changeAspect(_ ratio: AspectRatio) {
        aspect = ratio
        settings.lastAspectID = ratio.id
    }

    /// - Parameter select: false = im Verlauf ablegen, ohne das Bild auf dem Canvas zu wechseln (Serien).
    @discardableResult
    func addVersion(_ version: ImageVersion, autosave: Bool = true, select: Bool = true) -> ImageVersion {
        var version = version
        // Bearbeitet, angepasst, zugeschnitten: Wer auf dem Ausgangsbild war, ist es auch hier.
        if version.personaIDs.isEmpty, let parentID = version.parentID, let parent = versions.first(where: { $0.id == parentID }) {
            version.personaIDs = parent.personaIDs
        }
        if autosave && settings.autosave && version.source != .imported {
            version.fileURL = writeAutosave(version)
            gallery.register(version)
        }
        versions.append(version)
        if select || currentID == nil { currentID = version.id }
        if aspect == nil { aspect = AspectRatio.closest(to: version.size) }
        return version
    }

    func select(_ version: ImageVersion) {
        currentID = version.id
    }

    func selectAdjacentVersion(_ delta: Int) {
        guard let index = versions.firstIndex(where: { $0.id == currentID }) else { return }
        let next = index + delta
        guard versions.indices.contains(next) else { return }
        currentID = versions[next].id
    }

    func delete(_ version: ImageVersion) {
        guard let index = versions.firstIndex(of: version) else { return }
        versions.remove(at: index)
        if currentID == version.id {
            currentID = versions.indices.contains(index) ? versions[index].id : versions.last?.id
        }
    }

    func importImage(_ image: CGImage) {
        // In Labs landet das Bild im nächsten freien Platz – zuerst auf dem Canvas.
        if showLabs {
            placeInLabs(image)
            return
        }
        if aspect == nil || versions.isEmpty { aspect = AspectRatio.closest(to: CGSize(width: image.width, height: image.height)) }
        editAspect = nil
        galleryMark = nil
        let version = addVersion(ImageVersion(image: image, prompt: "", source: .imported))
        showGallery = false
        if mode == .generate { mode = .edit }
        if mode == .series { setSeriesSource(image, versionID: version.id) }
    }

    // MARK: - Anpassen & Transformieren

    private func scheduleAdjustmentPreview() {
        previewTask?.cancel()
        guard let base = previewBase, !adjustments.isIdentity else {
            adjustedPreview = nil
            return
        }
        let settings = adjustments
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            let preview = AdjustmentPipeline.apply(settings, to: base)
            guard !Task.isCancelled else { return }
            adjustedPreview = preview
        }
    }

    func applyAdjustments() {
        guard let current, !adjustments.isIdentity else { return }
        let result = AdjustmentPipeline.apply(adjustments, to: current.image)
        addVersion(ImageVersion(image: result, prompt: current.prompt, source: .adjusted, parentID: current.id))
    }

    enum Transform { case rotateLeft, rotateRight, flipHorizontal, flipVertical, cropToAspect }

    func transform(_ transform: Transform) {
        guard let current else { return }
        let image: CGImage
        switch transform {
        case .rotateLeft: image = ImageTools.rotated(current.image, clockwise: false)
        case .rotateRight: image = ImageTools.rotated(current.image, clockwise: true)
        case .flipHorizontal: image = ImageTools.flipped(current.image, horizontal: true)
        case .flipVertical: image = ImageTools.flipped(current.image, horizontal: false)
        case .cropToAspect:
            guard let aspect else { return }
            image = ImageTools.cropped(current.image, toRatio: aspect.value)
        }
        addVersion(ImageVersion(image: image, prompt: current.prompt, source: .transformed, parentID: current.id))
    }

    // MARK: - Generieren

    var isGenerating: Bool { generation != nil }

    /// Draw Things rendert oder eine Serie läuft (auch während Gemma ihre Prompts schreibt).
    var isBusy: Bool { isGenerating || seriesRun?.isRunning == true || personaTest?.isRunning == true }

    var filledReferences: [ReferenceSlot] { references.filter { $0.image != nil } }

    /// Warum der Generieren-Knopf gerade nicht geht (nil = alles bereit).
    var runBlocker: String? {
        if isGenerating { return "Draw Things rendert gerade." }
        if seriesRun?.isRunning == true { return "Die Serie läuft gerade." }
        if personaTest?.isRunning == true { return "Der Charaktertest läuft gerade." }
        if mode == .series { return seriesBlocker }
        if builder.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Der Prompt ist leer." }
        switch mode {
        case .generate: if aspect == nil { return "Lege zuerst ein neues Bild mit Seitenverhältnis an." }
        case .edit: if current == nil { return "Es gibt noch kein Bild zum Bearbeiten." }
        case .references: if filledReferences.isEmpty { return "Füge mindestens ein Referenzbild hinzu." }
        case .series: break
        }
        return nil
    }

    var canRun: Bool { runBlocker == nil }

    /// Format, in dem das Bild an Draw Things geht – gewählt oder das nächstgelegene.
    var editFormat: AspectRatio? {
        guard let image = current?.image else { return nil }
        return editAspect ?? AspectRatio.closest(to: CGSize(width: image.width, height: image.height))
    }

    /// Draw-Things-Format je Modus: aus Dokument bzw. Bild, sonst das nächstgelegene.
    func targetFormat(for mode: StudioMode) -> AspectRatio? {
        switch mode {
        case .generate:
            return aspect
        case .edit:
            return editFormat
        case .references:
            if let aspect { return aspect }
            guard let image = filledReferences.first?.image else { return nil }
            return AspectRatio.closest(to: CGSize(width: image.width, height: image.height))
        case .series:
            return seriesSource.map { AspectRatio.closest(to: $0.size) }
        }
    }

    /// Pixelgröße für Draw Things – immer eine der Größen, die Draw Things anbietet.
    /// Größere Bilder werden darauf verkleinert (und bei anderem Seitenverhältnis beschnitten).
    func targetSize(for mode: StudioMode) -> CGSize? {
        targetFormat(for: mode)?.pixelSize(sizeTier)
    }

    /// Pixelgröße für ein Seitenverhältnis: das nächstgelegene Draw-Things-Format in der gewählten Stufe.
    func pixelSize(for ratio: Double, tier: SizeTier? = nil) -> CGSize {
        AspectRatio.closest(toRatio: ratio).pixelSize(tier ?? sizeTier)
    }

    /// Bild schon vor dem Senden auf das Draw-Things-Format bringen – als neue Version, damit man sieht, was ankommt.
    func conformToEditFormat() {
        guard let current, let size = targetSize(for: .edit), current.size != size else { return }
        let image = ImageTools.filled(current.image, to: size)
        // Eine Auswahl bleibt über Versionen hinweg bestehen – sie wird genauso zugeschnitten.
        if let mask = selectionMask { selectionMask = ImageTools.filledCrop(mask, toRatio: size.width / size.height) }
        addVersion(ImageVersion(image: image, prompt: current.prompt, source: .transformed, parentID: current.id))
    }

    func run() {
        guard canRun, generationTask == nil else { return }
        if mode == .series {
            startSeries()
            return
        }
        guard let size = targetSize(for: mode) else { return }
        if mode == .edit && !adjustments.isIdentity { applyAdjustments() }
        errorMessage = nil
        let mode = self.mode
        let tier = sizeTier
        let prompt = builder.prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var initImages: [CGImage] = []
        let baseID = mode == .edit ? current?.id : nil
        // Lokale Bearbeitung: das Ergebnis später nur innerhalb der Auswahl übernehmen.
        var localEdit: (original: CGImage, mask: CGImage, feather: Double)?
        switch mode {
        case .generate, .series: break
        case .edit:
            if let image = current?.image {
                initImages = [image]
                if applyEditToSelection, let mask = selectionMask {
                    // Original und Maske so zuschneiden wie das Bild, das an Draw Things geht – sonst verrutscht
                    // das Ergebnis, wenn das Format vom Bild abweicht.
                    let ratio = size.width / size.height
                    localEdit = (ImageTools.filledCrop(image, toRatio: ratio), ImageTools.filledCrop(mask, toRatio: ratio), selectionFeather)
                }
            }
        case .references:
            // Charaktere werden erst im Task passend zur Bildgröße gerendert.
            break
        }
        let sentReferences = settings.sendAllReferences ? filledReferences : Array(filledReferences.prefix(1))
        let personaIDs = mode == .references ? filledReferences.compactMap(\.personaID) : []
        // Gesichtsreferenz: Bild groß links, Ansichten des Charakters rechts – in einem Bild an Draw Things.
        let assist = mode == .edit ? activeIdentityAssist?.persona : nil

        var request = DrawThingsRequest(
            prompt: prompt,
            width: Int(size.width),
            height: Int(size.height),
            initImages: initImages.compactMap { ImageTools.pngData(ImageTools.filled($0, to: size)) },
            model: settings.switchModelPerMode ? settings.modelFile(for: mode) : nil,
            seed: settings.randomSeed ? UInt32.random(in: 0..<UInt32.max) : nil
        )

        generationTask = Task {
            do {
                if mode == .references {
                    request.initImages = await referenceImageData(sentReferences, size: size)
                    try Task.checkCancellation()
                }
                var composite: (image: CGImage, layout: IdentityComposite.Layout)?
                if let assist, let base = initImages.first {
                    guard let built = await IdentityComposite.render(base: ImageTools.filled(base, to: size), persona: assist, tier: tier),
                          let png = ImageTools.pngData(built.image) else {
                        throw ServiceError("Das Raster mit der Gesichtsreferenz konnte nicht erstellt werden.")
                    }
                    composite = built
                    request.width = Int(built.layout.size.width)
                    request.height = Int(built.layout.size.height)
                    request.initImages = [png]
                    try Task.checkCancellation()
                }
                let (results, total) = try await render(request, mode: mode, size: composite?.layout.size ?? size)
                for data in results {
                    guard var image = ImageTools.image(from: data) else { continue }
                    if let composite {
                        // Nur das große Feld ist das Ergebnis – und prüfen, ob Qwen das Raster gehalten hat.
                        let change = IdentityComposite.stripChange(output: image, input: composite.image, layout: composite.layout)
                        identityAssist?.lastRawOutput = image
                        identityAssist?.lastStripChange = change
                        if change > IdentityAssist.driftWarning {
                            errorMessage = "Die Gesichtsreferenz hat womöglich nicht gegriffen: Qwen hat das Raster verändert. Prüfe das Ergebnis – das ganze Raster steht unter „Gesichtsreferenz › Letztes Raster“."
                        }
                        image = IdentityComposite.extractMain(from: image, layout: composite.layout)
                    }
                    if let localEdit {
                        image = ImageTools.composite(image, over: localEdit.original, mask: localEdit.mask, feather: localEdit.feather)
                    }
                    var version = ImageVersion(image: image, prompt: prompt, source: .generated(mode), seed: request.seed, duration: total, parentID: baseID)
                    version.personaIDs = personaIDs
                    if let assist, !version.personaIDs.contains(assist.id) {
                        version.personaIDs = (versions.first { $0.id == baseID }?.personaIDs ?? []) + [assist.id]
                    }
                    addVersion(version)
                }
                if aspect == nil, let image = current?.image { aspect = AspectRatio.closest(to: CGSize(width: image.width, height: image.height)) }
                if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                errorMessage = error.localizedDescription
            }
            generationTask = nil
            await refreshDrawThings()
        }
    }

    /// Ein Durchlauf in Draw Things mit geschätztem Fortschritt (Balken, Dock-Symbol) und Zeitmessung –
    /// für Einzelbilder und für jedes Bild einer Serie.
    func render(_ request: DrawThingsRequest, mode: StudioMode, size: CGSize) async throws -> (images: [Data], duration: TimeInterval) {
        let area = Double(size.width * size.height)
        let steps = dtConfig?.steps
        let timing = RunTiming.load(for: mode.timingMode)
        let switchesModel = request.model.map { $0 != activeModel } ?? false
        let progress = GenerationProgress(
            mode: mode, startedAt: .now, size: size,
            // Ein Modellwechsel kostet zusätzlich Ladezeit.
            estimate: timing.estimate(area: area, steps: steps) + (switchesModel ? 30 : 0),
            isCalibrated: timing.isMeasured,
            loadingModel: switchesModel ? request.model.map(DrawThingsConfig.displayName(for:)) : nil
        )
        generation = progress
        showDockProgress()
        defer {
            // Nach einem Abbruch läuft vielleicht schon der nächste Durchlauf – dessen Anzeige bleibt.
            if generation?.id == progress.id {
                generation = nil
                hideDockProgress()
            }
        }
        let started = Date()
        let results = try await drawThings.generate(request)
        let total = Date().timeIntervalSince(started)
        let seconds = max(total - (switchesModel ? 30 : 0), 1)
        if let model = request.model { lastSentModel = model }
        RunTiming(seconds: seconds, area: area, steps: steps ?? timing.steps, isMeasured: true).save(for: mode.timingMode)
        return (results, total)
    }

    /// Modell, mit dem Draw Things gerade arbeitet – soweit die App es weiß.
    var activeModel: String? { lastSentModel ?? dtConfig?.model }

    /// Nach dem Moduswechsel kurz anzeigen, welches Modell dieser Modus nutzt.
    private func announceModel() {
        guard settings.switchModelPerMode else { return }
        let target = settings.modelFile(for: mode)
        let name = DrawThingsConfig.displayName(for: target)
        modelNotice = target == activeModel
            ? "\(name) ist in Draw Things aktiv"
            : "Draw Things lädt \(name) " + (mode == .series ? "beim Start der Serie" : "beim nächsten \(mode.actionTitle)")
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        cancelSeries()
        cancelPersonaTest()
        generation = nil
        hideDockProgress()
    }

    /// Prozentanzeige am Dock-Symbol, damit man den Fortschritt auch sieht, wenn die App im Hintergrund ist.
    private func showDockProgress() {
        dockTask?.cancel()
        dockTask = Task {
            while !Task.isCancelled, let generation {
                NSApp.dockTile.badgeLabel = "\(Int((generation.fraction(at: .now) * 100).rounded())) %"
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func hideDockProgress() {
        dockTask?.cancel()
        dockTask = nil
        NSApp.dockTile.badgeLabel = nil
    }

    // MARK: - Verbindungen

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await refreshLM()
                if !isGenerating { await refreshDrawThings() }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refreshLM() async {
        guard lmBusy == 0, lmStatus != .loading else { return }
        let status = await lm.status()
        if status != lmStatus { lmStatus = status }
        if lmModels.isEmpty, status != .offline { lmModels = await lm.availableModels() }
    }

    func refreshDrawThings() async {
        do {
            let config = try await drawThings.config()
            if config != dtConfig { dtConfig = config }
            if dtReachable != true { dtReachable = true }
        } catch {
            if dtReachable != false { dtReachable = false }
        }
    }

    /// Lädt Gemma in LM Studio, falls nötig. Wirft eine verständliche Fehlermeldung.
    func ensureLMReady() async throws {
        if lmStatus == .unknown || lmStatus == .offline { lmStatus = await lm.status() }
        switch lmStatus {
        case .offline: throw ServiceError("LM Studio ist nicht erreichbar (\(settings.lmStudioURL)).")
        case .modelMissing: throw ServiceError("Das Modell „\(settings.lmModel)“ gibt es in LM Studio nicht.")
        case .notLoaded:
            lmStatus = .loading
            do {
                try await lm.load()
                lmStatus = .ready
            } catch {
                lmStatus = .notLoaded
                throw error
            }
        default: break
        }
    }

    // MARK: - Bibliothek

    /// Gespeicherte Prompts gehören zur Bibliothek: `Katalog/saved-prompts.json`.
    private var libraryURL: URL { gallery.root.appending(path: "Katalog/saved-prompts.json") }

    func loadLibrary() {
        library = []
        guard let data = try? Data(contentsOf: libraryURL),
              let entries = try? JSONDecoder().decode([SavedPrompt].self, from: data) else { return }
        library = entries
    }

    private func saveLibrary() {
        guard Library.ensure(libraryURL.deletingLastPathComponent(), in: gallery.root),
              let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }

    func savePromptToLibrary() {
        let text = builder.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !library.contains(where: { $0.text == text }) else { return }
        library.insert(SavedPrompt(text: text, mode: mode), at: 0)
        saveLibrary()
    }

    func deleteFromLibrary(_ entry: SavedPrompt) {
        library.removeAll { $0.id == entry.id }
        saveLibrary()
    }
}
