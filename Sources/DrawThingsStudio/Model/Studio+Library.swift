import AppKit

/// Bibliotheken: anlegen, öffnen, wechseln, löschen – z. B. eine je Kunde oder Auftrag.
extension Studio {

    /// Alle bekannten Bibliotheken, die geöffnete zuerst.
    var libraries: [LibraryEntry] {
        let current = Library.root.path
        let paths = [current] + settings.libraryPaths.filter { $0 != current }
        return paths.map { LibraryEntry(url: URL(fileURLWithPath: $0)) }
    }

    var libraryName: String { gallery.root.lastPathComponent }

    // MARK: Öffnen & Wechseln

    /// Bibliothek öffnen – speichert die bisherige, leert das Studio und lädt Katalog, Charaktere und Assets neu.
    func openLibrary(_ url: URL) {
        let url = url.standardizedFileURL
        guard !isBusy else {
            errorMessage = "Warte, bis Draw Things fertig ist – sonst landet das Ergebnis in der falschen Bibliothek."
            return
        }
        closeLibrary(saving: true)
        resetWorkspace(clearPrompt: false)
        load(url)
        Task { await syncGallery() }
    }

    /// - Parameter remember: in die Liste der Bibliotheken aufnehmen (nicht nach dem Löschen).
    private func load(_ url: URL, remember: Bool = true) {
        Library.root = url
        settings.libraryPath = url.path
        if remember, !settings.libraryPaths.contains(url.path) { settings.libraryPaths.append(url.path) }
        Library.migrateLegacyData(into: url)
        gallery = Gallery(root: url)
        personas = PersonaStore(root: url)
        assets = AssetStore(root: url)
        isLibraryAvailable = Library.isAvailable(url)
        // Stand der Bibliothek – eine neue beginnt mit den mitgelieferten Bausteinen und leerem Entwurf.
        CatalogStore.shared.open(root: url)
        builder.open(root: url)
        seriesSetup = SeriesSetup.load(root: url)
        loadLibrary()
        openLabs(root: url)
        updateReferenceSentences()
        updateAssetSentence()
        updateAssistSentence()
        showGallery = true
    }

    private func closeLibrary(saving: Bool) {
        gallery.close(saving: saving)
        personas.close(saving: saving)
        assets.close(saving: saving)
        CatalogStore.shared.close(saving: saving)
        builder.close(saving: saving)
        closeLabs(saving: saving)
        closeStories()
        GalleryImages.forgetAll()
        PersonaImages.forget()
        AssetImages.forgetAll()
    }

    /// Neue, leere Bibliothek anlegen – Ort und Name wählt man im Sichern-Dialog.
    func createLibraryWithPanel() {
        let panel = NSSavePanel()
        panel.title = "Neue Bibliothek"
        panel.message = "Ein Ordner für alle Bilder, Videos, Charaktere und Assets – z. B. je Kunde oder Auftrag. Er darf auch auf einer SD-Karte liegen."
        panel.nameFieldLabel = "Name:"
        panel.nameFieldStringValue = "Neue Bibliothek"
        panel.prompt = "Anlegen"
        panel.canCreateDirectories = true
        panel.directoryURL = Library.defaultURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                guard Library.isAvailable(url) else { throw ServiceError("Dort liegt schon eine Datei mit diesem Namen.") }
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            }
            try FileManager.default.createDirectory(at: url.appending(path: "Katalog"), withIntermediateDirectories: true)
            openLibrary(url)
        } catch {
            errorMessage = "Die Bibliothek konnte nicht angelegt werden: \(error.localizedDescription)"
        }
    }

    /// Vorhandene Bibliothek öffnen – oder einen beliebigen Ordner mit Bildern zur Bibliothek machen.
    func openLibraryWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Bibliothek öffnen"
        panel.message = "Ordner einer Bibliothek wählen – oder einen Ordner mit Bildern, der zur Bibliothek werden soll."
        panel.prompt = "Öffnen"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLibrary(url)
    }

    /// Aus der Liste nehmen – die Dateien bleiben, wo sie sind.
    func forgetLibrary(_ entry: LibraryEntry) {
        guard entry.url.standardizedFileURL != Library.root else { return }
        settings.libraryPaths.removeAll { $0 == entry.url.path }
    }

    // MARK: SD-Karte & Co.

    /// Laufwerk ein- oder ausgesteckt: Bibliothek nachladen bzw. als nicht erreichbar zeigen.
    func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLibraryAvailability() }
            })
        }
    }

    func refreshLibraryAvailability() {
        let available = Library.isAvailable(gallery.root)
        guard available != isLibraryAvailable else { return }
        if available {
            // War beim Start nicht da: Katalog jetzt richtig laden.
            closeLibrary(saving: false)
            load(gallery.root)
            Task { await syncGallery() }
        } else {
            isLibraryAvailable = false
        }
    }

    // MARK: Löschen

    /// Bibliothek mitsamt allen Bildern, Videos, Charakterfotos, Assets und Vorschaubildern endgültig löschen –
    /// nicht in den Papierkorb. Dazu Bilder, die früher aus ihr in den Papierkorb gelegt wurden,
    /// und die Vorschaubilder von Quick Look. Ist es die geöffnete, wird auch das Studio geleert.
    func deleteLibrary(_ entry: LibraryEntry) async {
        let url = entry.url.standardizedFileURL
        guard !isBusy else {
            errorMessage = "Warte, bis Draw Things fertig ist."
            return
        }
        let isCurrent = url == Library.root
        let trashed = isCurrent ? gallery.trashedFiles : Gallery.trashedFiles(in: url)
        if isCurrent {
            closeLibrary(saving: false)
            resetWorkspace(clearPrompt: true)
        }
        let failure = await Task.detached(priority: .userInitiated) { () -> String? in
            let fm = FileManager.default
            var failure: String?
            if fm.fileExists(atPath: url.path) {
                do { try fm.removeItem(at: url) } catch { failure = error.localizedDescription }
            }
            for path in trashed where fm.fileExists(atPath: path) { try? fm.removeItem(atPath: path) }
            // Finder und Quick Look merken sich Vorschaubilder – deren Zwischenspeicher zurücksetzen.
            let quickLook = Process()
            quickLook.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            quickLook.arguments = ["-r", "cache"]
            quickLook.standardOutput = FileHandle.nullDevice
            quickLook.standardError = FileHandle.nullDevice
            try? quickLook.run()
            quickLook.waitUntilExit()
            return failure
        }.value

        settings.libraryPaths.removeAll { $0 == url.path }
        if let failure {
            errorMessage = "Die Bibliothek wurde nicht vollständig gelöscht: \(failure)"
        }
        guard isCurrent else { return }
        if let next = libraries.first(where: { $0.url.standardizedFileURL != url && $0.isAvailable }) {
            load(next.url.standardizedFileURL)
            Task { await syncGallery() }
        } else {
            // Keine andere da: leer und „nicht vorhanden“ – angelegt wird erst auf Wunsch.
            load(url, remember: false)
        }
    }

    // MARK: Studio leeren

    /// Alles aus dem Studio entfernen, was zur bisherigen Bibliothek gehört.
    /// - Parameter clearPrompt: auch Prompt, Bausteine und Serien-Werte (beim Löschen einer Bibliothek).
    func resetWorkspace(clearPrompt: Bool) {
        optimizerTask?.cancel()
        optimizer = OptimizerState()
        versions = []
        currentID = nil
        zoom = nil
        canvasPan = .zero
        selectionMask = nil
        clearReferences()
        seriesSource = nil
        seriesRun = nil
        personaTest = nil
        analysisSource = nil
        analysisResults = []
        selectedAssetIDs = []
        identityAssist = nil
        if clearPrompt {
            builder.reset()
            gemmaWish = ""
        }
        updateAssetSentence()
    }
}

extension Gallery {
    /// Papierkorb-Dateien einer anderen (nicht geöffneten) Bibliothek.
    nonisolated static func trashedFiles(in root: URL) -> [String] {
        struct Partial: Decodable { var trashedFiles: [String]? }
        guard let data = try? Data(contentsOf: root.appending(path: "Katalog/gallery.json")),
              let partial = try? JSONDecoder().decode(Partial.self, from: data) else { return [] }
        return partial.trashedFiles ?? []
    }
}
