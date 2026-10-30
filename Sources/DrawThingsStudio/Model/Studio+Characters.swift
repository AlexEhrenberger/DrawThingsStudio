import AppKit

/// Vergleich für einen Charakter: dieselbe Szene, derselbe Seed – einmal mit dem Raster, einmal nur mit dem Frontalfoto.
struct PersonaTest {
    enum Phase: Equatable {
        case writing
        case rendering(PersonaReferenceMode)
        case done
        case failed(String)
        case cancelled
    }

    /// Zugleich der Stapel, in dem die Ergebnisse in der Galerie liegen.
    let id = UUID()
    let personaID: UUID
    let scene: String
    /// Szene auf Englisch (von Gemma, sonst wie eingegeben).
    var prompt = ""
    var usedGemma = false
    var phase: Phase = .writing
    var resultIDs: [UUID] = []

    var isRunning: Bool {
        switch phase {
        case .writing, .rendering: true
        default: false
        }
    }
}

/// Charaktere im Studio: als Referenz verwenden, beschreiben lassen, Fotos aufnehmen, Raster gegen Einzelfoto testen.
extension Studio {

    // MARK: Referenzen

    /// Charakter in einen Referenzplatz setzen – Rolle „Person“, Gemmas Beschreibung als Text-Anker.
    func setPersona(_ personaID: UUID, mode: PersonaReferenceMode? = nil, at index: Int) {
        guard references.indices.contains(index), let persona = personas.persona(personaID) else { return }
        guard persona.mainPhoto != nil else {
            errorMessage = "„\(persona.name)“ hat noch keine Fotos."
            return
        }
        references[index].personaID = personaID
        references[index].assetID = nil
        references[index].assetSubject = nil
        references[index].galleryItemID = nil
        references[index].personaMode = mode ?? persona.referenceMode
        references[index].role = .identity
        references[index].description = persona.description
        references[index].error = nil
        references[index].isAnalyzing = false
        refreshPersonaReference(at: index)
    }

    func setPersonaMode(_ mode: PersonaReferenceMode, at index: Int) {
        guard references.indices.contains(index), references[index].personaID != nil else { return }
        references[index].personaMode = mode
        refreshPersonaReference(at: index)
    }

    /// Referenzbild des Charakters neu zusammensetzen – im Format des Bildes, das entstehen soll.
    func refreshPersonaReference(at index: Int) {
        guard references.indices.contains(index), let personaID = references[index].personaID,
              let persona = personas.persona(personaID) else { return }
        let slotID = references[index].id
        let mode = references[index].personaMode
        let size = personaReferenceSize
        Task {
            let image = await CharacterSheet.render(persona, mode: mode, size: size)
            guard let slot = references.firstIndex(where: { $0.id == slotID }), references[slot].personaID == personaID else { return }
            references[slot].image = image
            updateReferenceSentences()
        }
    }

    /// Größe der Vorschau im Referenzplatz: Format des Dokuments, sonst 3:4 hoch.
    private var personaReferenceSize: CGSize {
        pixelSize(for: aspect?.value ?? 3.0 / 4.0)
    }

    /// PNG-Daten der Referenzen für Draw Things – Charaktere frisch in genau dieser Größe.
    func referenceImageData(_ slots: [ReferenceSlot], size: CGSize) async -> [Data] {
        var data: [Data] = []
        for slot in slots {
            var image = slot.image
            if let personaID = slot.personaID, let persona = personas.persona(personaID) {
                image = await CharacterSheet.render(persona, mode: slot.personaMode, size: size) ?? image
            }
            if let image, let png = ImageTools.pngData(ImageTools.filled(image, to: size)) { data.append(png) }
        }
        return data
    }

    /// Charakter als Bild 1 in „Mit Referenzen arbeiten“. Steht dort schon etwas anderes, rückt es in einen freien Platz.
    func usePersonaInStudio(_ personaID: UUID) {
        if references[0].image != nil, references[0].personaID != personaID, references[0].role != .identity,
           let free = references.indices.dropFirst().first(where: { references[$0].image == nil }) {
            references.swapAt(0, free)
        }
        setPersona(personaID, at: 0)
        show(.references)
        showInspector = true
    }

    // MARK: Beschreiben

    /// Gemma beschreibt das Aussehen anhand des Rasters – das wird der Text-Anker im Prompt.
    func describePersona(_ personaID: UUID) {
        guard describingPersonaID == nil, let persona = personas.persona(personaID), persona.mainPhoto != nil else { return }
        describingPersonaID = personaID
        Task {
            lmBusy += 1
            defer {
                lmBusy -= 1
                describingPersonaID = nil
            }
            do {
                try await ensureLMReady()
                guard let sheet = await CharacterSheet.render(persona, mode: .sheet, size: CGSize(width: 896, height: 1152)),
                      let url = ImageTools.dataURL(sheet, maxSide: 1024) else { return }
                let messages: [ChatMessage] = [.system(PromptTemplates.personaDescription), .user("Describe this person.", images: [url])]
                let text = LMStudioClient.clean(try await lm.complete(messages, temperature: 0.2, maxTokens: 300))
                guard !text.isEmpty else { throw ServiceError("Gemma hat keine Beschreibung geliefert.") }
                personas.update(personaID) { $0.description = text }
                for index in references.indices where references[index].personaID == personaID {
                    references[index].description = text
                }
                updateReferenceSentences()
            } catch {
                errorMessage = "Gemma konnte „\(persona.name)“ nicht beschreiben: \(error.localizedDescription)"
            }
        }
    }

    func setPersonaDescription(_ text: String, of personaID: UUID) {
        personas.update(personaID) { $0.description = text }
        for index in references.indices where references[index].personaID == personaID {
            references[index].description = text
        }
        updateReferenceSentences()
    }

    // MARK: Fotos

    func addPersonaPhotos(_ images: [CGImage], to personaID: UUID) {
        Task {
            for image in images { await personas.addPhoto(image, to: personaID) }
            afterPhotosChanged(personaID)
        }
    }

    func addPersonaPhotos(urls: [URL], to personaID: UUID) {
        Task {
            for url in urls {
                guard let image = await Task.detached(priority: .userInitiated, operation: { ImageTools.image(from: url) }).value else {
                    errorMessage = "„\(url.lastPathComponent)“ konnte nicht als Bild gelesen werden."
                    continue
                }
                await personas.addPhoto(image, to: personaID)
            }
            afterPhotosChanged(personaID)
        }
    }

    /// Bilder aus der Galerie als Fotos übernehmen – z. B. eine generierte Figur, die immer gleich aussehen soll.
    func addGalleryItems(_ itemIDs: [UUID], toPersona personaID: UUID) {
        Task {
            for id in itemIDs {
                guard let item = gallery.item(id), let image = await GalleryImages.image(for: item) else { continue }
                await personas.addPhoto(image, to: personaID)
            }
            afterPhotosChanged(personaID)
        }
    }

    func choosePersonaPhotos(for personaID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Fotos der Person wählen – frontal, von der Seite, ganz"
        guard panel.runModal() == .OK else { return }
        addPersonaPhotos(urls: panel.urls, to: personaID)
    }

    func removePersonaPhoto(_ photoID: UUID, from personaID: UUID) {
        personas.removePhoto(photoID, from: personaID)
        refreshPersonaReferences(personaID)
    }

    func setPersonaPhotoView(_ view: PersonaView, of photoID: UUID, in personaID: UUID) {
        personas.setView(view, of: photoID, in: personaID)
        refreshPersonaReferences(personaID)
    }

    func deletePersona(_ personaID: UUID) {
        for index in references.indices where references[index].personaID == personaID {
            references[index].personaID = nil
        }
        if gallery.collection == .persona(personaID) { gallery.collection = .all }
        personas.delete(personaID)
        updateReferenceSentences()
    }

    /// Nach neuen Fotos: Referenzplätze nachziehen und – beim ersten Mal – Gemma beschreiben lassen.
    private func afterPhotosChanged(_ personaID: UUID) {
        refreshPersonaReferences(personaID)
        if personas.persona(personaID)?.description.isEmpty == true { describePersona(personaID) }
    }

    private func refreshPersonaReferences(_ personaID: UUID) {
        for index in references.indices where references[index].personaID == personaID {
            refreshPersonaReference(at: index)
        }
    }

    // MARK: Test: Raster gegen Einzelfoto

    /// Dieselbe Szene zweimal rendern – mit Raster und mit Einzelfoto, gleicher Seed, gleiche Größe.
    /// Die Bilder landen als Stapel in der Galerie und lassen sich dort mit Synchron-Zoom vergleichen.
    func startPersonaTest(_ personaID: UUID, scene: String) {
        let scene = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !scene.isEmpty, let persona = personas.persona(personaID), persona.mainPhoto != nil else { return }
        errorMessage = nil
        let test = PersonaTest(personaID: personaID, scene: scene)
        personaTest = test
        let size = pixelSize(for: 3.0 / 4.0)
        // Immer ein fester Seed – sonst unterscheiden sich die beiden Bilder nicht nur durch die Referenz.
        let seed = UInt32.random(in: 0..<UInt32.max)

        personaTestTask = Task {
            let english = await translatePersonaScene(scene)
            guard !Task.isCancelled, personaTest?.id == test.id else { return }
            personaTest?.prompt = english ?? scene
            personaTest?.usedGemma = english != nil

            for (index, mode) in [PersonaReferenceMode.sheet, .single].enumerated() {
                guard !Task.isCancelled, personaTest?.id == test.id else { return }
                personaTest?.phase = .rendering(mode)
                guard let reference = await CharacterSheet.render(persona, mode: mode, size: size),
                      let png = ImageTools.pngData(reference) else {
                    personaTest?.phase = .failed("Das Referenzbild konnte nicht erstellt werden.")
                    return
                }
                let prompt = mode.sentence(imageNumber: 1, description: persona.description) + " " + (english ?? scene)
                let request = DrawThingsRequest(
                    prompt: prompt,
                    width: Int(size.width),
                    height: Int(size.height),
                    initImages: [png],
                    model: settings.switchModelPerMode ? settings.modelFile(for: .references) : nil,
                    seed: seed
                )
                do {
                    let (results, duration) = try await render(request, mode: .references, size: size)
                    guard let data = results.first, let image = ImageTools.image(from: data) else {
                        throw ServiceError("Draw Things hat kein lesbares Bild geliefert.")
                    }
                    let tag = SeriesTag(
                        id: test.id, index: index + 1, value: mode.title, title: "Charaktertest · \(persona.name)",
                        symbol: "person.2.crop.square.stack", sourceID: nil, prompt: english ?? scene, isSeries: false
                    )
                    var version = ImageVersion(image: image, prompt: prompt, source: .generated(.references), seed: seed, duration: duration, series: tag)
                    version.personaIDs = [personaID]
                    let added = addVersion(version, select: false)
                    personaTest?.resultIDs.append(added.id)
                } catch is CancellationError {
                    return
                } catch let error as URLError where error.code == .cancelled {
                    return
                } catch {
                    personaTest?.phase = .failed(error.localizedDescription)
                    personaTestTask = nil
                    return
                }
            }
            personaTest?.phase = .done
            personaTestTask = nil
            if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
            await refreshDrawThings()
        }
    }

    func cancelPersonaTest() {
        personaTestTask?.cancel()
        personaTestTask = nil
        if personaTest?.isRunning == true { personaTest?.phase = .cancelled }
    }

    /// Ergebnisse des Tests in der Galerie auffächern – gleich mit Synchron-Zoom.
    func openPersonaTestResults() {
        guard let test = personaTest, let stack = gallery.stacks[test.id] else { return }
        let members = gallery.members(of: test.id)
        guard !members.isEmpty else { return }
        showGallery = true
        gallery.open(members.count == 1 ? .image(members[0]) : .stack(stack, members))
        if members.count > 1 { gallery.compareMode = .zoom }
    }

    /// Szene auf Englisch – nil, wenn Gemma nicht erreichbar ist.
    private func translatePersonaScene(_ scene: String) async -> String? {
        lmBusy += 1
        defer { lmBusy -= 1 }
        do {
            try await ensureLMReady()
            let messages: [ChatMessage] = [.system(PromptTemplates.personaScene), .user(scene)]
            let text = LMStudioClient.clean(try await lm.complete(messages, temperature: 0.3, maxTokens: 220))
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}
