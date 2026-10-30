import AppKit
import UniformTypeIdentifiers

/// Labs: Experimente mit Qwen Image Edit 2511. „Bild zusammenbauen“ – Canvas und bis zu drei Moodboards,
/// Gemma schreibt den Prompt, eingefügt wird er in Draw Things von Hand (nichts geht über HTTP).
extension Studio {

    // MARK: Navigation

    func enterLabs() {
        showLabs = true
    }

    // MARK: Plätze

    func setLabImage(_ image: CGImage, at index: Int) {
        guard composition.slots.indices.contains(index) else { return }
        composition.slots[index].image = image
        writeLabImage(image, at: index)
    }

    func removeLabImage(at index: Int) {
        guard composition.slots.indices.contains(index) else { return }
        composition.slots[index].image = nil
        writeLabImage(nil, at: index)
    }

    /// Bild in den nächsten freien Platz legen – zuerst auf den Canvas.
    func placeInLabs(_ image: CGImage) {
        guard let index = composition.slots.firstIndex(where: { $0.image == nil }) else {
            errorMessage = "Canvas und Moodboards sind belegt – zieh das Bild auf einen Platz, um es zu ersetzen."
            return
        }
        setLabImage(image, at: index)
    }

    func useInLabs(_ item: GalleryItem, slot: Int) {
        Task {
            guard let image = await GalleryImages.image(for: item) else {
                errorMessage = "„\(item.url.lastPathComponent)“ konnte nicht geladen werden."
                return
            }
            setLabImage(image, at: slot)
            enterLabs()
        }
    }

    func useAssetInLabs(_ assetID: UUID, slot: Int) {
        guard let asset = assets.asset(assetID) else { return }
        Task {
            guard let image = await AssetImages.image(asset) else {
                errorMessage = "Das Bild von „\(asset.name)“ konnte nicht geladen werden."
                return
            }
            setLabImage(image, at: slot)
            enterLabs()
        }
    }

    /// Hauptbild eines Charakters – etwa als Moodboard, damit Gemma die Person genau benennen kann.
    func usePersonaInLabs(_ personaID: UUID, slot: Int) {
        guard let persona = personas.persona(personaID), let photo = persona.mainPhoto else { return }
        Task {
            guard let image = await PersonaImages.image(photo, of: personaID) else {
                errorMessage = "Das Foto von „\(persona.name)“ konnte nicht geladen werden."
                return
            }
            setLabImage(image, at: slot)
            enterLabs()
        }
    }

    func pasteIntoLab(at index: Int) {
        guard let nsImage = NSImage(pasteboard: .general), let image = ImageTools.image(from: nsImage) else {
            errorMessage = "In der Zwischenablage ist kein Bild."
            return
        }
        setLabImage(image, at: index)
    }

    /// Bilder, Anweisungen und Prompt leeren – der Verlauf bleibt.
    func clearComposition() {
        cancelLabPrompt()
        for index in composition.slots.indices where composition.slots[index].image != nil {
            removeLabImage(at: index)
        }
        let history = composition.history
        composition = LabComposition()
        composition.history = history
    }

    // MARK: Für Draw Things kopieren

    /// Bild für Draw Things in die Zwischenablage (dort ⌘V auf Canvas bzw. Moodboard).
    func copyLabImage(at index: Int) {
        guard composition.slots.indices.contains(index), let image = composition.slots[index].image else { return }
        let item = NSPasteboardItem()
        if let png = ImageTools.pngData(image) { item.setData(png, forType: .png) }
        if let tiff = NSImage(cgImage: image, size: .zero).tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    func copyLabPrompt() {
        let prompt = composition.prompt.trimmed
        guard !prompt.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
    }

    /// Zum Herausziehen (z. B. nach Draw Things oder in den Finder): die PNG entsteht erst beim Ablegen –
    /// in der Bibliothek (`Katalog/Labs/Ziehen/`), nicht im Temp-Ordner des Systems, damit Bilder eines Mandanten
    /// nirgends sonst liegen. Der Ordner wird beim Öffnen und Schließen der Bibliothek geleert.
    func labDragProvider(_ image: CGImage, name: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        guard let labsFolder else { return provider }
        let folder = labsFolder.appending(path: Self.labsDragFolder, directoryHint: .isDirectory)
        let root = labsFolder.deletingLastPathComponent().deletingLastPathComponent()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            let url = folder.appending(path: "\(name).png")
            do {
                guard Library.ensure(folder, in: root) else { throw ServiceError("Die Bibliothek ist nicht erreichbar.") }
                guard let data = ImageTools.pngData(image) else { throw ServiceError("Das Bild konnte nicht kodiert werden.") }
                try data.write(to: url, options: .atomic)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    // MARK: Gemma

    /// Gemma sieht alle Bilder und schreibt aus den deutschen Anweisungen den Prompt für Qwen Image Edit 2511.
    /// - Parameter correction: Nachbessern – Gemma bekommt ihren letzten Prompt und die Korrektur dazu.
    func writeLabPrompt(correction: String? = nil) {
        let correction = correction?.trimmed
        if let correction {
            guard !composition.isWriting, composition.canvas != nil, !correction.isEmpty, !composition.prompt.trimmed.isEmpty else { return }
        } else {
            guard composition.blocker == nil else { return }
        }
        labsTask?.cancel()

        var pictures: [PromptTemplates.LabPicture] = []
        var sources: [(image: CGImage, maxSide: Int)] = []
        var wishes: [Int: String] = [:]
        for (index, slot) in composition.slots.enumerated() {
            guard let image = slot.image else { continue }
            let number = sources.count + 1
            sources.append((image, index == LabSlot.canvas ? 1024 : 768))
            let wish = slot.instruction.trimmed
            wishes[number] = wish
            pictures.append(PromptTemplates.LabPicture(
                number: number,
                place: index == LabSlot.canvas ? "canvas (the base picture)" : "moodboard \(index)",
                wish: wish
            ))
        }
        let request = PromptTemplates.labsComposeRequest(
            pictures: pictures,
            general: composition.general.trimmed,
            previous: correction == nil ? nil : composition.prompt.trimmed,
            correction: correction
        )
        let count = sources.count

        composition.isWriting = true
        composition.writingStarted = .now
        composition.error = nil
        labsTask = Task {
            lmBusy += 1
            defer { lmBusy -= 1 }
            do {
                // Verkleinern kostet bei großen Fotos etwas – nicht auf dem Hauptthread.
                let images = await Task.detached(priority: .userInitiated) {
                    sources.compactMap { ImageTools.dataURL($0.image, maxSide: $0.maxSide) }
                }.value
                try Task.checkCancellation()
                try await ensureLMReady()
                let messages: [ChatMessage] = [.system(PromptTemplates.labsCompose), .user(request, images: images)]
                // Niedrige Temperatur: Gemma soll übersetzen, nicht erfinden.
                let raw = try await lm.complete(messages, temperature: 0.2, maxTokens: 1200, schema: PromptTemplates.labsComposeSchema)
                try Task.checkCancellation()
                guard let data = raw.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ServiceError("Gemmas Antwort war kein gültiges JSON.")
                }
                var prompt = LMStudioClient.clean(object["prompt"] as? String ?? "")
                guard !prompt.isEmpty else { throw ServiceError("Gemma hat keinen Prompt geliefert.") }
                // Personen zu sehen, aber kein Wort zur Identität: den Satz selbst ergänzen.
                if object["has_person"] as? Bool == true, !Self.mentionsIdentity(prompt) {
                    prompt = Self.insertIdentity(into: prompt)
                }
                let check = (object["check"] as? String)?.trimmed ?? ""
                let assumptions = (object["assumptions"] as? String)?.trimmed ?? ""
                composition.prompt = prompt
                composition.check = check
                composition.assumptions = assumptions
                composition.warning = Self.labWarning(for: prompt, imageCount: count, wishes: wishes)
                if correction != nil { composition.correction = "" }
                composition.history.insert(LabPromptRecord(prompt: prompt, check: check, assumptions: assumptions, imageCount: count), at: 0)
                if composition.history.count > 40 { composition.history.removeLast(composition.history.count - 40) }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                composition.error = error.localizedDescription
            }
            // Abgebrochen: `cancelLabPrompt` hat den Zustand schon zurückgesetzt.
            guard !Task.isCancelled else { return }
            composition.isWriting = false
            composition.writingStarted = nil
            labsTask = nil
        }
    }

    func cancelLabPrompt() {
        labsTask?.cancel()
        labsTask = nil
        if composition.isWriting {
            composition.isWriting = false
            composition.writingStarted = nil
        }
    }

    /// Prompt aus dem Verlauf wieder ins Ergebnis holen.
    func restoreLabPrompt(_ record: LabPromptRecord) {
        guard !composition.isWriting else { return }
        composition.prompt = record.prompt
        composition.check = record.check
        composition.assumptions = record.assumptions ?? ""
        composition.warning = nil
        composition.error = nil
    }

    func deleteLabRecord(_ record: LabPromptRecord) {
        composition.history.removeAll { $0.id == record.id }
    }

    private static func mentionsIdentity(_ prompt: String) -> Bool {
        let text = prompt.lowercased()
        return text.contains("identity") || text.contains("facial")
    }

    /// Satz zur Identität ans Ende hängen.
    private static func insertIdentity(into prompt: String) -> String {
        let sentence = PromptTemplates.labsIdentityFallback
        return prompt.hasSuffix(".") ? prompt + " " + sentence : prompt + ". " + sentence
    }

    /// Nennt Gemma ein Bild, das es nicht gibt, oder fehlt ein Moodboard mit Anweisung im Prompt?
    private static func labWarning(for prompt: String, imageCount: Int, wishes: [Int: String]) -> String? {
        let mentioned = Set(prompt.matches(of: #/(?:Picture|Image)\s+(\d+)/#.ignoresCase()).compactMap { Int($0.1) })
        if let wrong = mentioned.filter({ $0 > imageCount || $0 < 1 }).min() {
            return "Gemma nennt „Picture \(wrong)“, es gibt aber nur \(imageCount == 1 ? "ein Bild" : "\(imageCount) Bilder") – prüfe den Prompt oder lass ihn neu schreiben."
        }
        let missing = wishes.filter { $0.key > 1 && !$0.value.isEmpty && !mentioned.contains($0.key) }.keys.sorted()
        if !missing.isEmpty {
            let list = missing.map { "Picture \($0)" }.joined(separator: ", ")
            return "\(list) kommt im Prompt nicht vor, obwohl du dazu etwas geschrieben hast – prüfe den Prompt oder bessere nach."
        }
        return nil
    }

    // MARK: Sichern

    /// Labs einer Bibliothek laden – eine neue beginnt leer. Liegt in `Katalog/Labs/`.
    func openLabs(root: URL) {
        labsTask?.cancel()
        labsTask = nil
        labsSaveTask?.cancel()
        labsRestoring = true
        defer { labsRestoring = false }
        let folder = root.appending(path: "Katalog/Labs", directoryHint: .isDirectory)
        labsFolder = folder
        Self.removeLabDragFiles(in: folder)
        composition = LabComposition()
        if let data = try? Data(contentsOf: folder.appending(path: "labs.json")),
           let draft = try? JSONDecoder().decode(LabsDraft.self, from: data) {
            for (index, text) in draft.instructions.prefix(LabSlot.count).enumerated() {
                composition.slots[index].instruction = text
            }
            composition.general = draft.general
            composition.prompt = draft.prompt
            composition.check = draft.check
            composition.assumptions = draft.assumptions ?? ""
            composition.history = draft.history
        }
        // Bilder im Hintergrund lesen – große Fotos würden sonst den Start bremsen.
        Task {
            let images = await Task.detached(priority: .userInitiated) {
                (0..<LabSlot.count).map { ImageTools.image(from: folder.appending(path: "slot-\($0).png")) }
            }.value
            guard labsFolder == folder else { return }
            for (index, image) in images.enumerated() where image != nil && composition.slots[index].image == nil {
                composition.slots[index].image = image
            }
        }
    }

    /// Bibliothek wird gewechselt oder gelöscht: Entwurf sichern (oder verwerfen), danach nichts mehr schreiben.
    func closeLabs(saving: Bool) {
        labsTask?.cancel()
        labsTask = nil
        if saving { flushLabs() }
        labsSaveTask?.cancel()
        if let labsFolder { Self.removeLabDragFiles(in: labsFolder) }
        labsFolder = nil
    }

    static let labsDragFolder = "Ziehen"

    /// Kopien, die beim Herausziehen entstanden sind, wegräumen – dazu die aus Versionen, die noch den Temp-Ordner nutzten.
    private static func removeLabDragFiles(in folder: URL) {
        let targets = [
            folder.appending(path: labsDragFolder, directoryHint: .isDirectory),
            FileManager.default.temporaryDirectory.appending(path: "DrawThings Studio Labs", directoryHint: .isDirectory),
        ]
        Task.detached(priority: .utility) {
            for url in targets where FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Beim Tippen nicht bei jedem Zeichen schreiben.
    func scheduleLabsSave() {
        guard !labsRestoring, labsFolder != nil else { return }
        labsSaveTask?.cancel()
        labsSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            flushLabs()
        }
    }

    private func flushLabs() {
        guard let folder = labsFolder else { return }
        let draft = LabsDraft(
            instructions: composition.slots.map(\.instruction),
            general: composition.general,
            prompt: composition.prompt,
            check: composition.check,
            assumptions: composition.assumptions,
            history: composition.history
        )
        let root = folder.deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? JSONEncoder().encode(draft), Library.ensure(folder, in: root) else { return }
        try? data.write(to: folder.appending(path: "labs.json"), options: .atomic)
    }

    /// Bild eines Platzes in der Bibliothek ablegen (nil = Datei löschen).
    private func writeLabImage(_ image: CGImage?, at index: Int) {
        guard let folder = labsFolder else { return }
        let url = folder.appending(path: "slot-\(index).png")
        let root = folder.deletingLastPathComponent().deletingLastPathComponent()
        Task.detached(priority: .utility) {
            guard let image else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            guard Library.ensure(folder, in: root), let data = ImageTools.pngData(image) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
