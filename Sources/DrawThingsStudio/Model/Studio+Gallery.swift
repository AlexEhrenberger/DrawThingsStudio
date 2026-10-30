import AppKit
import UniformTypeIdentifiers

/// Was die Galerie beim Verlassen markiert hatte; `appliedModes` merkt, wo es schon eingelöst wurde.
struct GalleryMark {
    var itemIDs: [UUID]
    var appliedModes: Set<StudioMode> = []
}

/// Verbindung zwischen Galerie und Studio: Bilder öffnen, weiterverwenden, exportieren, löschen.
extension Studio {

    /// Neue Dateien in der Bibliothek aufnehmen und fehlende ausblenden.
    func syncGallery() async {
        isLibraryAvailable = Library.isAvailable(gallery.root)
        guard isLibraryAvailable else { return }
        await gallery.sync(folder: gallery.root)
    }

    /// Modus wählen – verlässt dabei die Galerie.
    func show(_ mode: StudioMode) {
        showGallery = false
        showLabs = false
        self.mode = mode
    }

    /// Zurück in die Galerie (Toolbar, ⌘G): Prompt und Bausteine bleiben nicht stehen.
    /// Abkürzungen mitten im Arbeiten („Assets verwalten …“) setzen weiter `showGallery` und leeren nichts.
    func enterGallery() {
        let cameFromStudio = !showGallery && !showLabs
        showGallery = true
        if cameFromStudio { clearPromptDraft() }
    }

    /// Prompt, Bausteine, Wunsch an Gemma, offenen Vorschlag und Asset-Auswahl leeren –
    /// der Prompt bleibt über „Bild › Prompt wiederherstellen“ erreichbar.
    private func clearPromptDraft() {
        builder.stashDraft()
        builder.reset()
        gemmaWish = ""
        optimizerTask?.cancel()
        optimizer = OptimizerState()
        selectedAssetIDs = []
        updateAssetSentence()
    }

    /// Toolbar und ⌘1–4: Modus wählen und das markierte Galeriebild mitnehmen.
    /// `show(_:)` bleibt für gezielte Aktionen („Als Referenz verwenden“, „Im Studio verwenden“), die kein zweites Bild wollen.
    func switchTo(_ mode: StudioMode) {
        if showGallery { galleryMark = GalleryMark(itemIDs: gallery.markedItems.map(\.id)) }
        show(mode)
        applyGalleryMark(for: mode)
    }

    /// Marke im Modus einlösen – je Modus einmal, danach nie wieder bis zur nächsten Runde durch die Galerie.
    /// Bearbeiten und Serien nehmen genau ein Bild, Referenzen bis zu drei in die freien Plätze.
    func applyGalleryMark(for mode: StudioMode) {
        guard var mark = galleryMark, !mark.appliedModes.contains(mode), !mark.itemIDs.isEmpty else { return }
        let ids = mark.itemIDs
        let items = ids.compactMap { gallery.item($0) }
        // Das Laden dauert; wer inzwischen in die Galerie zurück ist, will das Bild nicht mehr.
        let stillMarked = { [weak self] in self?.galleryMark?.itemIDs == ids }
        switch mode {
        case .generate:
            return
        case .edit:
            if items.count == 1, let item = items.first {
                let before = currentID
                Task {
                    guard let version = await studioVersion(for: item, select: false), stillMarked() else { return }
                    // Ein anderes Bild beginnt wieder mit dem passenden Format.
                    if version.id != before { editAspect = nil }
                    select(version)
                }
            }
        case .series:
            if items.count == 1, let item = items.first {
                Task {
                    guard let version = await studioVersion(for: item, select: false), stillMarked() else { return }
                    setSeriesSource(version)
                }
            }
        case .references:
            Task {
                for item in items.prefix(references.count) {
                    guard stillMarked(), !references.contains(where: { $0.galleryItemID == item.id }),
                          let slot = references.firstIndex(where: { $0.image == nil }) else { continue }
                    await setReference(from: item, at: slot)
                }
            }
        }
        mark.appliedModes.insert(mode)
        galleryMark = mark
    }

    // MARK: Ins Studio holen

    /// Bild aus der Galerie im Studio öffnen – als Version im Verlauf, ohne es erneut zu sichern.
    /// - Parameter then: läuft, sobald das Bild im Studio liegt.
    func openInStudio(_ item: GalleryItem, mode target: StudioMode = .edit, then: (() -> Void)? = nil) {
        Task {
            guard let version = await studioVersion(for: item, select: target != .series) else { return }
            showGallery = false
            galleryMark = nil
            // Ein anderes Bild beginnt wieder mit dem passenden Format.
            if target != .series, version.id != currentID { editAspect = nil }
            if target == .series {
                setSeriesSource(version)
            } else {
                select(version)
            }
            mode = target
            then?()
        }
    }

    /// To-do umsetzen: Bild in „Bearbeiten“ öffnen, das To-do wird zum Prompt und Gemma schreibt daraus
    /// die Anweisung für Qwen Image Edit. Was danach aus dem Bild entsteht, hängt sich an das To-do.
    func workOn(_ note: GalleryNote) {
        guard note.isOpenTodo, let item = gallery.item(note.itemID) else { return }
        gallery.workingTodoID = note.id
        openInStudio(item, mode: .edit) { [weak self] in
            guard let self else { return }
            // Bausteine eines anderen Bildes passen nicht – „Leeren“ lässt sich rückgängig machen.
            builder.clearComponents()
            builder.replacePrompt(note.text)
            gemmaWish = ""
            optimizePrompt()
        }
    }

    func useAsReference(_ item: GalleryItem, slot: Int) {
        Task {
            guard await setReference(from: item, at: slot) else { return }
            show(.references)
        }
    }

    /// Bild aus der Bibliothek in einen Referenzplatz setzen – ohne den Modus zu wechseln (Auswahl im Inspector).
    @discardableResult
    func setReference(from item: GalleryItem, at slot: Int) async -> Bool {
        guard let image = await GalleryImages.image(for: item) else {
            couldNotLoad(item)
            return false
        }
        setReference(image, at: slot)
        if references.indices.contains(slot) { references[slot].galleryItemID = item.id }
        return true
    }

    /// Prompt in die Seitenleiste übernehmen und ins Studio wechseln.
    func adoptPrompt(of item: GalleryItem) {
        guard !item.prompt.isEmpty else { return }
        builder.replacePrompt(item.prompt)
        if item.kind == StudioMode.generate.rawValue { mode = .generate }
        showGallery = false
    }

    private func studioVersion(for item: GalleryItem, select: Bool) async -> ImageVersion? {
        if let existing = versions.first(where: { $0.id == item.id }) { return existing }
        guard let image = await GalleryImages.image(for: item) else {
            couldNotLoad(item)
            return nil
        }
        var version = ImageVersion(
            id: item.id, image: image, prompt: item.prompt, source: item.source, seed: item.seed,
            duration: item.duration, parentID: item.parentID, createdAt: item.createdAt
        )
        version.fileURL = item.url
        version.personaIDs = item.personaIDs ?? []
        return addVersion(version, autosave: false, select: select)
    }

    private func couldNotLoad(_ item: GalleryItem) {
        errorMessage = "„\(item.url.lastPathComponent)“ konnte nicht geladen werden."
    }

    // MARK: Datei

    /// ⌘S: im Studio die aktuelle Version, in der Galerie das gewählte Bild.
    var canExport: Bool {
        showGallery ? galleryExportItem != nil : current != nil
    }

    func exportCurrent() {
        if showGallery {
            if let item = galleryExportItem { export(item) }
        } else {
            exportWithPanel()
        }
    }

    private var galleryExportItem: GalleryItem? {
        if let id = gallery.viewer?.currentID { return gallery.item(id) }
        guard gallery.selection.count == 1, let id = gallery.selection.first else { return nil }
        return gallery.item(id)
    }

    func revealInFinder(_ items: [GalleryItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    func export(_ item: GalleryItem) {
        let panel = NSSavePanel()
        if item.isVideo {
            // Videos werden als Datei kopiert, wie sie sind.
            panel.allowedContentTypes = [UTType(filenameExtension: item.url.pathExtension) ?? .movie]
            panel.nameFieldStringValue = item.url.lastPathComponent
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: item.url, to: url)
            } catch {
                errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
            }
            return
        }
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "DrawThings Studio \(Self.fileStamp.string(from: item.createdAt)).png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if url.pathExtension.lowercased().hasPrefix("jp") {
                guard let image = ImageTools.image(from: item.url), let data = ImageTools.jpegData(image, quality: 0.95) else {
                    throw ServiceError("Das Bild konnte nicht kodiert werden.")
                }
                try data.write(to: url)
            } else {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: item.url, to: url)
            }
        } catch {
            errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: Importieren

    /// Bilder und Videos von außen in die Bibliothek kopieren.
    func importIntoLibrary(_ urls: [URL]) {
        guard isLibraryAvailable else {
            errorMessage = "Die Bibliothek ist nicht erreichbar."
            return
        }
        Task {
            let failures = await gallery.importFiles(urls)
            if !failures.isEmpty {
                errorMessage = "Nicht übernommen: \(failures.joined(separator: ", ")) – nur Bilder und Videos (MP4, MOV, M4V)."
            }
        }
    }

    func importIntoLibraryWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.message = "Bilder und Videos wählen – sie werden in die Bibliothek „\(libraryName)“ kopiert."
        panel.prompt = "Importieren"
        guard panel.runModal() == .OK else { return }
        importIntoLibrary(panel.urls)
    }

    func moveToTrash(_ itemIDs: [UUID]) {
        let failures = gallery.moveToTrash(itemIDs)
        if !failures.isEmpty {
            errorMessage = "Nicht in den Papierkorb gelegt: \(failures.joined(separator: ", "))"
        }
    }
}
