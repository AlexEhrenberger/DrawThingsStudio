import AppKit

/// Asset-Baukasten: Kleidung, Schuhe, Orte … als Bilder ablegen, beschreiben lassen und verwenden –
/// in „Referenzen“ als Referenzbild, sonst mit Gemmas Beschreibung im Prompt.
extension Studio {

    // MARK: Hinzufügen

    func addAssets(urls: [URL], to categoryID: String) {
        Task {
            var added: [UUID] = []
            for url in urls {
                if let asset = await assets.add(fileAt: url, to: categoryID) {
                    added.append(asset.id)
                } else {
                    errorMessage = Library.isAvailable()
                        ? "„\(url.lastPathComponent)“ konnte nicht als Asset übernommen werden."
                        : "Die Bibliothek ist nicht erreichbar."
                }
            }
            afterAssetsAdded(added)
        }
    }

    func addAssets(images: [CGImage], to categoryID: String) {
        Task {
            var added: [UUID] = []
            let name = assets.category(categoryID)?.name ?? "Asset"
            for image in images {
                if let asset = await assets.add(image: image, name: name, to: categoryID) { added.append(asset.id) }
            }
            afterAssetsAdded(added)
        }
    }

    /// Bilder aus der Galerie als Assets übernehmen (als Kopie – die Galerie bleibt, wie sie ist).
    func addGalleryItemsAsAssets(_ itemIDs: [UUID], to categoryID: String) {
        let urls = itemIDs.compactMap { gallery.item($0) }.filter { !$0.isVideo }.map(\.url)
        addAssets(urls: urls, to: categoryID)
    }

    func chooseAssetFiles(for categoryID: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Bilder für „\(assets.category(categoryID)?.name ?? "Assets")“ wählen"
        guard panel.runModal() == .OK else { return }
        addAssets(urls: panel.urls, to: categoryID)
    }

    private func afterAssetsAdded(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if ids.count == 1 { assets.selectedID = ids[0] }
        describeAssets(ids)
    }

    func deleteAssets(_ ids: [UUID]) {
        for index in references.indices where references[index].assetID.map(ids.contains) == true {
            removeReference(at: index)
        }
        selectedAssetIDs.removeAll { ids.contains($0) }
        assets.delete(ids)
        updateAssetSentence()
    }

    func revealAsset(_ asset: Asset) {
        NSWorkspace.shared.activateFileViewerSelecting([AssetStore.url(for: asset)])
    }

    // MARK: Beschreiben

    /// Gemma beschreibt die Assets nacheinander – passend zur Rolle ihrer Kategorie.
    func describeAssets(_ ids: [UUID]) {
        let fresh = ids.filter { !assetQueue.contains($0) }
        assetQueue += fresh
        assets.describing.formUnion(fresh)
        guard assetDescribeTask == nil else { return }
        assetDescribeTask = Task {
            while !assetQueue.isEmpty {
                let id = assetQueue.removeFirst()
                guard await describeAsset(id) else {
                    // Gemma nicht erreichbar: nicht für jedes Asset dieselbe Fehlermeldung.
                    assets.describing.subtract(assetQueue)
                    assetQueue = []
                    break
                }
            }
            assetDescribeTask = nil
        }
    }

    /// - Returns: false, wenn Gemma nicht erreichbar war.
    private func describeAsset(_ id: UUID) async -> Bool {
        let store = assets
        defer { store.describing.remove(id) }
        guard let asset = store.asset(id), let category = store.category(asset.categoryID),
              let image = await AssetImages.image(asset), let url = ImageTools.dataURL(image, maxSide: 768) else { return true }
        lmBusy += 1
        defer { lmBusy -= 1 }
        do {
            try await ensureLMReady()
            let messages: [ChatMessage] = [.system(category.describeInstruction), .user("Describe this reference image.", images: [url])]
            let text = LMStudioClient.clean(try await lm.complete(messages, temperature: 0.2, maxTokens: 300))
            guard !text.isEmpty else { return true }
            setAssetDescription(text, of: id)
            return true
        } catch {
            errorMessage = "Gemma konnte „\(asset.name)“ nicht beschreiben: \(error.localizedDescription) – später mit „Neu beschreiben“ nachholen."
            return false
        }
    }

    func setAssetDescription(_ text: String, of id: UUID) {
        assets.update(id) { $0.description = text }
        for index in references.indices where references[index].assetID == id {
            references[index].description = text
        }
        updateReferenceSentences()
        updateAssetSentence()
    }

    // MARK: Verwenden

    /// Ist das Asset gerade in Gebrauch – als Referenzbild oder als Baustein im Prompt?
    func isAssetActive(_ id: UUID) -> Bool {
        mode == .references ? references.contains { $0.assetID == id } : selectedAssetIDs.contains(id)
    }

    /// Klick auf ein Asset im Baukasten: in „Referenzen“ in den nächsten freien Platz,
    /// sonst kommt seine Beschreibung in den Prompt.
    func toggleAsset(_ id: UUID) {
        if mode == .references {
            if let index = references.firstIndex(where: { $0.assetID == id }) {
                removeReference(at: index)
            } else if let free = references.firstIndex(where: { $0.image == nil }) {
                setAsset(id, at: free)
            } else {
                errorMessage = "Alle drei Referenzplätze sind belegt – entferne zuerst ein Bild."
            }
            return
        }
        if let index = selectedAssetIDs.firstIndex(of: id) {
            selectedAssetIDs.remove(at: index)
        } else {
            selectedAssetIDs.append(id)
            assets.markUsed(id)
            if assets.asset(id)?.description.isEmpty == true { describeAssets([id]) }
        }
        updateAssetSentence()
    }

    /// Asset als Referenzbild in einen Platz setzen – mit der Rolle seiner Kategorie.
    func setAsset(_ id: UUID, at index: Int) {
        guard references.indices.contains(index), let asset = assets.asset(id), let category = assets.category(asset.categoryID) else { return }
        let slotID = references[index].id
        Task {
            guard let image = await AssetImages.image(asset) else {
                errorMessage = "Das Bild von „\(asset.name)“ konnte nicht geladen werden."
                return
            }
            guard let slot = references.firstIndex(where: { $0.id == slotID }) else { return }
            references[slot].image = image
            references[slot].personaID = nil
            references[slot].assetID = id
            references[slot].assetSubject = category.customSubject
            references[slot].galleryItemID = nil
            references[slot].role = category.role
            references[slot].description = asset.description
            references[slot].error = nil
            references[slot].isAnalyzing = false
            assets.markUsed(id)
            updateReferenceSentences()
            if asset.description.isEmpty { describeAssets([id]) }
        }
    }

    /// Asset ins Studio holen: in „Referenzen“ als Referenzbild.
    func useAssetInStudio(_ id: UUID) {
        show(.references)
        if !references.contains(where: { $0.assetID == id }) { toggleAsset(id) }
        showInspector = true
    }

    // MARK: Kategorien

    /// Bedeutung einer Kategorie ändern: eine der Rollen – oder ein eigenes Thema.
    func setAssetCategoryRole(_ role: ReferenceRole, of categoryID: String) {
        assets.updateCategory(categoryID) { category in
            category.role = role
            category.subject = nil
        }
        assetCategoryChanged(categoryID)
    }

    func setAssetCategorySubject(_ subject: String, of categoryID: String) {
        assets.updateCategory(categoryID) { category in
            category.role = .general
            category.subject = subject
        }
        assetCategoryChanged(categoryID)
    }

    /// Eigenes Thema: Gemma übersetzt den Namen der Kategorie („Frisuren“ → „hairstyle“).
    /// - Parameter fallbackToName: Ohne Gemma den Namen selbst eintragen (zum Anpassen) – beim automatischen
    ///   Vorschlag nach dem Umbenennen nicht, dann bleibt die Kategorie „Allgemein“.
    func suggestAssetSubject(for categoryID: String, fallbackToName: Bool = true) {
        guard let category = assets.category(categoryID) else { return }
        assets.suggestingSubjectIDs.insert(categoryID)
        Task {
            lmBusy += 1
            defer {
                lmBusy -= 1
                assets.suggestingSubjectIDs.remove(categoryID)
            }
            var subject: String?
            if (try? await ensureLMReady()) != nil,
               let text = try? await lm.complete([.system(PromptTemplates.assetSubject), .user(category.name)], temperature: 0.1, maxTokens: 20) {
                let cleaned = LMStudioClient.clean(text).trimmingCharacters(in: CharacterSet(charactersIn: ".\"„“ ")).lowercased()
                if !cleaned.isEmpty, cleaned.count < 60 { subject = cleaned }
            }
            if let subject = subject ?? (fallbackToName ? category.name : nil) {
                setAssetCategorySubject(subject, of: categoryID)
            }
        }
    }

    /// Referenzplätze und Prompt-Sätze nachziehen, die Assets dieser Kategorie nutzen.
    private func assetCategoryChanged(_ categoryID: String) {
        guard let category = assets.category(categoryID) else { return }
        for index in references.indices {
            guard let id = references[index].assetID, assets.asset(id)?.categoryID == categoryID else { continue }
            references[index].role = category.role
            references[index].assetSubject = category.customSubject
        }
        updateReferenceSentences()
        updateAssetSentence()
    }

    /// Satz für den Prompt aus den gewählten Assets – beim Bearbeiten als Anweisung formuliert.
    func updateAssetSentence() {
        let sentences = selectedAssetIDs.compactMap { id -> String? in
            guard let asset = assets.asset(id), let category = assets.category(asset.categoryID) else { return nil }
            let text = mode == .edit ? category.editSentence(asset.description) : category.descriptionSentence(asset.description)
            return text.isEmpty ? nil : PromptBuilder.withPeriod(text)
        }
        builder.setAssetSentence(sentences.joined(separator: " "))
    }
}
