import AppKit

/// Alles, was Gemma (LM Studio) erledigt: Prompts optimieren, Bilder analysieren,
/// Referenzen beschreiben.
extension Studio {

    // MARK: Prompt optimieren

    func optimizePrompt() {
        let draft = builder.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let wish = gemmaWish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty || !wish.isEmpty else { return }
        optimizerTask?.cancel()
        optimizer = OptimizerState(isRunning: true, mode: mode)

        var context = ["Target image model: \(mode.modelName)"]
        if let ratio = aspectForPrompt {
            context.append("Aspect ratio: \(ratio.label) (\(ratio.orientation) format)")
        }
        var images: [String] = []
        switch mode {
        case .generate:
            break
        case .edit:
            if activeIdentityAssist == nil, let image = current?.image, let url = ImageTools.dataURL(image) {
                images.append(url)
                context.append("The attached image is Picture 1 – the current image that will be edited.")
            }
            if applyEditToSelection, hasSelection {
                context.append(selectionSource.promptHint)
            }
        case .series:
            if let image = seriesSource?.image, let url = ImageTools.dataURL(image) {
                images.append(url)
                context.append("The attached image is Picture 1 – the source picture of an image series. The prompt is a common instruction that applies to every picture of the series; each picture additionally changes the \(seriesSetup.variable == .custom ? seriesSetup.variableName : seriesSetup.variable.englishName).")
            }
        case .references:
            for (index, slot) in filledReferences.enumerated() {
                guard let image = slot.image, let url = ImageTools.dataURL(image, maxSide: 768) else { continue }
                images.append(url)
                let sent = index == 0 || settings.sendAllReferences
                var line = "Attached reference \(index + 1), role: \(slot.assetSubject ?? slot.role.englishName). "
                line += sent
                    ? "The image model receives it as Picture \(index + 1)."
                    : "The image model does NOT receive this image – describe what is needed from it in words, never mention its number."
                if !slot.description.isEmpty { line += " Notes: \(slot.description)" }
                if slot.personaID != nil, slot.personaMode == .sheet, sent {
                    line += " This reference is a character sheet: one person shown from several angles in one image. The new picture shows this person once – one single photograph, never a grid or collage."
                }
                context.append(line)
            }
        }

        // Gewählte Assets: Gemma sieht die Bilder, Draw Things bekommt nur ihre Beschreibung.
        let chosenAssets = mode == .references ? [] : selectedAssetIDs.compactMap { assets.asset($0) }.prefix(3)
        let mode = self.mode
        let assistPersona = mode == .edit ? activeIdentityAssist?.persona : nil
        let assistBase = assistPersona == nil ? nil : current?.image
        optimizerTask = Task {
            lmBusy += 1
            defer { lmBusy -= 1 }
            var images = images
            var context = context
            // Mit Gesichtsreferenz sieht Gemma genau das Raster, das an Draw Things geht.
            if let assistPersona, let assistBase, let size = targetSize(for: .edit),
               let built = await IdentityComposite.render(base: ImageTools.filled(assistBase, to: size), persona: assistPersona, tier: sizeTier),
               let url = ImageTools.dataURL(built.image) {
                images.insert(url, at: 0)
                context.append(identityAssistContext(assistPersona))
            }
            for asset in chosenAssets {
                guard let image = await AssetImages.image(asset), let url = ImageTools.dataURL(image, maxSide: 768) else { continue }
                images.append(url)
                let topic = assets.category(asset.categoryID)?.englishName ?? ReferenceRole.general.englishName
                context.append("Attached image \(images.count) is the \(topic) asset \"\(asset.name)\". The image model does NOT receive it – describe what is needed from it in words, never mention its number.")
            }
            let messages: [ChatMessage] = [
                .system(PromptTemplates.optimizer(for: mode)),
                .user(PromptTemplates.optimizerRequest(draft: draft, wish: wish, context: context), images: images),
            ]
            do {
                try await ensureLMReady()
                for try await chunk in lm.stream(messages, temperature: 0.4, maxTokens: 700) {
                    optimizer.text += chunk
                }
                optimizer.text = LMStudioClient.clean(optimizer.text)
                if optimizer.text.isEmpty { optimizer.error = "Gemma hat keinen Text geliefert." }
            } catch is CancellationError {
            } catch {
                optimizer.error = error.localizedDescription
            }
            optimizer.isRunning = false
        }
    }

    func acceptOptimizedPrompt() {
        guard !optimizer.text.isEmpty else { return }
        builder.replacePrompt(optimizer.text)
        optimizer = OptimizerState()
        gemmaWish = ""
    }

    func discardOptimizedPrompt() {
        optimizerTask?.cancel()
        optimizer = OptimizerState()
    }

    private var aspectForPrompt: AspectRatio? {
        targetFormat(for: mode)
    }

    // MARK: Bildanalyse

    var analysisImage: CGImage? { analysisSource ?? current?.image }

    func analyze(_ kind: AnalysisKind, question: String? = nil) {
        guard let image = analysisImage, let url = ImageTools.dataURL(image) else { return }
        var result = AnalysisResult(kind: kind, question: question, thumbnail: ImageTools.scaled(image, maxSide: 120))
        result.isRunning = true
        analysisResults.insert(result, at: 0)
        let id = result.id

        if kind == .text {
            Task {
                do {
                    let lines = try await VisionTools.recognizeText(in: image)
                    updateResult(id) { result in
                        result.lines = lines
                        result.text = lines.isEmpty ? "Kein Text gefunden." : ""
                    }
                } catch {
                    updateResult(id) { $0.error = error.localizedDescription }
                }
                updateResult(id) { $0.isRunning = false }
            }
            return
        }

        Task {
            lmBusy += 1
            defer { lmBusy -= 1 }
            do {
                try await ensureLMReady()
                if kind == .recognize {
                    try await recognizeBlocks(imageURL: url, resultID: id)
                } else {
                    let system: String
                    let request: String
                    switch kind {
                    case .reversePrompt: (system, request) = (PromptTemplates.reversePrompt, "Write the prompt for this image.")
                    case .subject: (system, request) = (PromptTemplates.subject, "Describe the main subject of this image.")
                    case .style: (system, request) = (PromptTemplates.style, "Describe the style of this image.")
                    default: (system, request) = (PromptTemplates.question, question ?? "")
                    }
                    let messages: [ChatMessage] = [.system(system), .user(request, images: [url])]
                    for try await chunk in lm.stream(messages, temperature: 0.3, maxTokens: 600) {
                        updateResult(id) { $0.text += chunk }
                    }
                    updateResult(id) { result in
                        result.text = kind.producesPrompt ? LMStudioClient.clean(result.text) : result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } catch {
                updateResult(id) { $0.error = error.localizedDescription }
            }
            updateResult(id) { $0.isRunning = false }
        }
    }

    private func recognizeBlocks(imageURL: String, resultID: UUID) async throws {
        let messages: [ChatMessage] = [
            .system(PromptTemplates.recognize),
            .user("Catalog (id=name):\n\(PromptTemplates.recognizeCatalog())\n\nPick the matching options for this image.", images: [imageURL]),
        ]
        let raw = try await lm.complete(messages, temperature: 0.1, maxTokens: 700, schema: PromptTemplates.recognizeSchema())
        guard let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError("Gemmas Antwort war kein gültiges JSON.")
        }
        var recognized: [String: [String]] = [:]
        for key in PromptTemplates.recognizableGroups {
            guard let group = Catalog.shared.group(key) else { continue }
            let valid = Set(group.options.map(\.id))
            let ids: [String]
            if let list = object[key] as? [String] { ids = list } else if let id = object[key] as? String { ids = [id] } else { ids = [] }
            let filtered = ids.filter { valid.contains($0) }
            if !filtered.isEmpty { recognized[key] = Array(filtered.prefix(group.multi ? 3 : 1)) }
        }
        updateResult(resultID) { result in
            result.recognized = recognized
            result.text = recognized.isEmpty ? "Keine passenden Bausteine erkannt." : ""
        }
    }

    private func updateResult(_ id: UUID, _ change: (inout AnalysisResult) -> Void) {
        guard let index = analysisResults.firstIndex(where: { $0.id == id }) else { return }
        change(&analysisResults[index])
    }

    func applyRecognized(_ result: AnalysisResult) {
        for (key, ids) in result.recognized {
            builder.setSelection(key, ids: ids)
        }
    }

    // MARK: Eigene Bausteine

    /// „Eigenen Wert eingeben + Enter“: neuer Baustein in der Kategorie, sofort gewählt.
    /// Gemma schreibt danach den englischen Satz im Stil der Kategorie.
    func addCustomOption(to key: String, name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let group = Catalog.shared.group(key) else { return }
        if let existing = group.options.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) {
            if !builder.isSelected(key, existing.id) { builder.toggle(key, existing.id) }
            return
        }
        guard let id = CatalogStore.shared.addOption(to: key, name: value, text: value) else { return }
        builder.toggle(key, id)
        writeOptionText(groupKey: key, optionID: id, name: value)
    }

    /// Englischen Prompt-Satz (oder bei Satzvorlagen eine Wortgruppe) für einen Baustein schreiben lassen.
    func writeOptionText(groupKey: String, optionID: String, name: String) {
        let store = CatalogStore.shared
        guard let group = Catalog.shared.group(groupKey) else { return }
        let sectionName = store.catalog.sections.first { $0.groups.contains { $0.key == groupKey } }?.name ?? ""
        let isFragment = group.template?.contains("{}") == true
        let examples = Array(group.options.filter { $0.id != optionID && $0.text != $0.name }.prefix(5).map(\.text))
        let messages: [ChatMessage] = [
            .system(PromptTemplates.optionWriter(fragment: isFragment)),
            .user(PromptTemplates.optionRequest(category: "\(sectionName) › \(group.name)", examples: examples, value: name)),
        ]
        store.pendingOptionIDs.insert(optionID)
        Task {
            lmBusy += 1
            defer { lmBusy -= 1 }
            do {
                try await ensureLMReady()
                var text = LMStudioClient.clean(try await lm.complete(messages, temperature: 0.2, maxTokens: 160))
                if isFragment, text.hasSuffix(".") { text.removeLast() }
                if !text.isEmpty {
                    store.updateOption(groupKey, optionID) { $0.text = text }
                    builder.recompose()
                }
            } catch {
                errorMessage = "Gemma konnte „\(name)“ nicht umschreiben – der Baustein nutzt den Text, wie er ist."
            }
            store.pendingOptionIDs.remove(optionID)
        }
    }

    /// Erkannten Text als „Text ersetzen“ für Qwen Image Edit vorbereiten.
    func prepareTextReplacement(_ line: String) {
        builder.updateText { text in
            text.replace = true
            text.find = line
            text.text = ""
            text.keepStyle = true
        }
        if current != nil && mode != .edit { mode = .edit }
    }

    func usePromptText(_ text: String, append: Bool) {
        let current = builder.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        builder.replacePrompt(append && !current.isEmpty ? current + " " + text : text)
    }

    func removeResult(_ result: AnalysisResult) {
        analysisResults.removeAll { $0.id == result.id }
    }

    // MARK: Referenzen

    func setReference(_ image: CGImage, at index: Int) {
        guard references.indices.contains(index) else { return }
        references[index].image = image
        references[index].personaID = nil
        references[index].assetID = nil
        references[index].assetSubject = nil
        references[index].galleryItemID = nil
        references[index].description = ""
        references[index].error = nil
        updateReferenceSentences()
        describeReference(at: index)
    }

    func removeReference(at index: Int) {
        guard references.indices.contains(index) else { return }
        references[index].image = nil
        references[index].personaID = nil
        references[index].assetID = nil
        references[index].assetSubject = nil
        references[index].galleryItemID = nil
        references[index].description = ""
        references[index].error = nil
        references[index].isAnalyzing = false
        updateReferenceSentences()
    }

    /// Alle Referenzbilder entfernen – ihre Sätze verschwinden aus dem Prompt.
    func clearReferences() {
        for index in references.indices {
            references[index].image = nil
            references[index].personaID = nil
            references[index].assetID = nil
            references[index].assetSubject = nil
            references[index].galleryItemID = nil
            references[index].description = ""
            references[index].error = nil
            references[index].isAnalyzing = false
        }
        updateReferenceSentences()
    }

    func setReferenceRole(_ role: ReferenceRole, at index: Int) {
        guard references.indices.contains(index), references[index].role != role else { return }
        references[index].role = role
        // Von Hand gewählte Rolle gilt – das eigene Thema eines Assets nicht mehr.
        references[index].assetSubject = nil
        // Ein Charakter steht immer für die Person – mit anderer Rolle bleibt nur das Bild.
        if role != .identity { references[index].personaID = nil }
        updateReferenceSentences()
        if references[index].image != nil { describeReference(at: index) }
    }

    func setReferenceDescription(_ text: String, at index: Int) {
        guard references.indices.contains(index) else { return }
        references[index].description = text
        updateReferenceSentences()
    }

    func describeReference(at index: Int) {
        if references.indices.contains(index), let personaID = references[index].personaID {
            describePersona(personaID)
            return
        }
        // Asset mit derselben Rolle: Beschreibung gilt fürs Asset, also dort neu schreiben lassen.
        if references.indices.contains(index), let assetID = references[index].assetID,
           let asset = assets.asset(assetID), assets.category(asset.categoryID)?.role == references[index].role {
            describeAssets([assetID])
            return
        }
        guard references.indices.contains(index), let image = references[index].image,
              let url = ImageTools.dataURL(image, maxSide: 768) else { return }
        let slotID = references[index].id
        let role = references[index].role
        references[index].isAnalyzing = true
        references[index].error = nil
        Task {
            lmBusy += 1
            defer { lmBusy -= 1 }
            var text = ""
            var failure: String?
            do {
                try await ensureLMReady()
                let messages: [ChatMessage] = [.system(PromptTemplates.reference(role)), .user("Describe this reference image.", images: [url])]
                text = LMStudioClient.clean(try await lm.complete(messages, temperature: 0.2, maxTokens: 300))
            } catch {
                failure = error.localizedDescription
            }
            guard let slot = references.firstIndex(where: { $0.id == slotID }), references[slot].role == role else { return }
            references[slot].isAnalyzing = false
            references[slot].error = failure
            if failure == nil { references[slot].description = text }
            updateReferenceSentences()
        }
    }

    /// Sätze für den Prompt: Das erste Bild geht als „Picture 1“ an Draw Things,
    /// die übrigen nur als Beschreibung (außer der Versuch „alle senden“ ist an).
    func updateReferenceSentences() {
        var sentences: [String: String] = [:]
        for (index, slot) in filledReferences.enumerated() {
            let sent = index == 0 || settings.sendAllReferences
            if sent, slot.personaID != nil {
                sentences["ref/\(index + 1)"] = slot.personaMode.sentence(imageNumber: index + 1, description: slot.description)
            } else if let subject = slot.assetSubject {
                sentences["ref/\(index + 1)"] = sent
                    ? AssetCategory.referenceSentence(subject: subject, imageNumber: index + 1)
                    : AssetCategory.descriptionSentence(subject: subject, description: slot.description)
            } else {
                sentences["ref/\(index + 1)"] = sent
                    ? slot.role.sentence(imageNumber: index + 1)
                    : slot.role.sentence(description: slot.description)
            }
        }
        builder.setReferenceSentences(sentences)
    }
}

extension ReferenceRole {
    var englishName: String {
        switch self {
        case .identity: "person (keep the identity)"
        case .outfit: "outfit"
        case .footwear: "shoes"
        case .accessory: "accessory"
        case .location: "location"
        case .style: "visual style"
        case .pose: "pose"
        case .object: "object or product"
        case .general: "general content"
        }
    }
}
