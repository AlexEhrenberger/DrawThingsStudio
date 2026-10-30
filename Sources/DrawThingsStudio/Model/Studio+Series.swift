import AppKit

/// Bilderserien: Aus einem Ausgangsbild entstehen bis zu vier Varianten, die sich nur in
/// einer Variable unterscheiden. Gemma schreibt zuerst alle Prompts, danach rendert
/// Draw Things ein Bild nach dem anderen – jedes landet im Verlauf und in der Bibliothek.
extension Studio {

    // MARK: Ausgangsbild

    func setSeriesSource(_ image: CGImage, versionID: UUID? = nil) {
        seriesSource = SeriesSource(image: image, versionID: versionID)
    }

    func setSeriesSource(_ version: ImageVersion) {
        setSeriesSource(version.image, versionID: version.id)
    }

    /// Bild von außen (Finder, Drag & Drop): erst in den Verlauf, dann als Ausgangsbild.
    func importSeriesSource(_ image: CGImage) {
        setSeriesSource(addVersion(ImageVersion(image: image, prompt: "", source: .imported), select: false))
    }

    func clearSeriesSource() {
        seriesSource = nil
    }

    /// Beim Wechsel in den Modus: das aktuelle Bild übernehmen, solange noch keins gewählt ist.
    func adoptSeriesSourceIfNeeded() {
        if seriesSource == nil, let current { setSeriesSource(current) }
    }

    /// Ist das aktuelle Canvas-Bild schon das Ausgangsbild?
    var currentIsSeriesSource: Bool {
        guard let current, let source = seriesSource else { return false }
        return source.versionID == current.id
    }

    // MARK: Einrichtung

    func setSeriesValue(_ text: String, at index: Int) {
        guard seriesSetup.values.indices.contains(index) else { return }
        seriesSetup.values[index] = text
    }

    /// Wert aus den Bausteinen ins erste freie Feld.
    func addSeriesValue(_ text: String) {
        guard let index = seriesSetup.values.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return }
        seriesSetup.values[index] = text
    }

    var seriesHasFreeField: Bool {
        seriesSetup.values.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var seriesBlocker: String? {
        if seriesSource == nil { return "Wähle zuerst ein Ausgangsbild." }
        if seriesSetup.variable == .custom && seriesSetup.customName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Gib der eigenen Variable einen Namen, z. B. „Accessoire“."
        }
        if seriesSetup.filledValues.isEmpty { return "Trage mindestens eine Variante ein." }
        return nil
    }

    // MARK: Ablauf

    func startSeries() {
        guard seriesBlocker == nil, !isBusy, let source = seriesSource, let size = targetSize(for: .series) else { return }
        errorMessage = nil
        let setup = seriesSetup
        let run = SeriesRun(
            variable: setup.variable,
            variableName: setup.variableName,
            source: source,
            size: size,
            commonPrompt: builder.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            seed: settings.randomSeed && setup.sameSeed ? UInt32.random(in: 0..<UInt32.max) : nil,
            items: setup.filledValues.enumerated().map { SeriesItem(number: $0.offset + 1, value: $0.element) }
        )
        seriesRun = run
        process(run.items.map(\.id), in: run.id)
    }

    /// Ein Bild der Serie noch einmal rendern – mit neuem Seed, auf Wunsch mit geändertem Prompt.
    /// - Parameter rewrite: Gemma schreibt den Prompt neu.
    func rerenderSeriesItem(_ itemID: UUID, prompt: String? = nil, rewrite: Bool = false) {
        guard !isBusy, let run = seriesRun else { return }
        updateSeriesItem(itemID) { item in
            if let prompt {
                item.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                item.usesTemplate = false
            }
            if rewrite { item.prompt = "" }
            item.phase = item.prompt.isEmpty ? .waiting : .queued
        }
        process([itemID], in: run.id, freshSeed: true)
    }

    /// Alles rendern, was nach einem Abbruch oder Fehler noch fehlt.
    func resumeSeries() {
        guard !isBusy, let run = seriesRun else { return }
        let ids = run.items.filter { $0.phase != .done }.map(\.id)
        guard !ids.isEmpty else { return }
        for id in ids {
            updateSeriesItem(id) { $0.phase = $0.prompt.isEmpty ? .waiting : .queued }
        }
        process(ids, in: run.id)
    }

    func cancelSeries() {
        seriesTask?.cancel()
        seriesTask = nil
        guard var run = seriesRun, run.isRunning else { return }
        for index in run.items.indices where run.items[index].isPending {
            // Ein halb geschriebener Prompt taugt nicht zum Rendern.
            if run.items[index].phase == .writing { run.items[index].prompt = "" }
            run.items[index].phase = .cancelled
        }
        run.isRunning = false
        seriesRun = run
    }

    /// Ergebnisse aus dem Raster nehmen (die Bilder bleiben im Verlauf und in der Bibliothek).
    func clearSeriesRun() {
        guard !isBusy else { return }
        seriesRun = nil
    }

    /// Bild der Serie im Modus „Bearbeiten“ öffnen.
    func openSeriesItemForEditing(_ item: SeriesItem) {
        guard let versionID = item.versionID, let version = versions.first(where: { $0.id == versionID }) else { return }
        select(version)
        mode = .edit
    }

    func useSeriesItemAsSource(_ item: SeriesItem) {
        guard let image = item.image else { return }
        setSeriesSource(image, versionID: item.versionID)
    }

    /// Geschätzte Dauer für eine Serie mit `count` Bildern (vor dem Start).
    func seriesEstimate(count: Int) -> TimeInterval? {
        guard count > 0, let size = targetSize(for: .series) else { return nil }
        let perImage = RunTiming.load(for: StudioMode.series.timingMode)
            .estimate(area: Double(size.width * size.height), steps: dtConfig?.steps)
        return perImage * Double(count)
    }

    /// Geschätzte Restdauer der ganzen Serie: laufendes Bild plus alle, die noch warten.
    func seriesRemaining(at date: Date) -> TimeInterval? {
        guard let run = seriesRun, run.isRunning else { return nil }
        let waiting = run.items.filter { $0.isPending && $0.phase != .rendering }.count
        let perImage = RunTiming.load(for: StudioMode.series.timingMode)
            .estimate(area: Double(run.size.width * run.size.height), steps: dtConfig?.steps)
        return (generation?.remaining(at: date) ?? 0) + Double(waiting) * perImage
    }

    // MARK: Gemma & Draw Things

    private func process(_ ids: [UUID], in runID: UUID, freshSeed: Bool = false) {
        seriesRun?.isRunning = true
        seriesTask = Task {
            await writeSeriesPrompts(ids, in: runID)
            for id in ids {
                guard !Task.isCancelled, seriesRun?.id == runID else { break }
                await renderSeriesItem(id, in: runID, freshSeed: freshSeed)
            }
            guard seriesRun?.id == runID, !Task.isCancelled else { return }
            seriesRun?.isRunning = false
            seriesTask = nil
            if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
            await refreshDrawThings()
        }
    }

    /// Erst alle Prompts, dann rendern – so laufen Gemma und Draw Things nicht gleichzeitig
    /// und teilen sich nicht den Grafikspeicher.
    private func writeSeriesPrompts(_ ids: [UUID], in runID: UUID) async {
        guard let run = seriesRun, run.id == runID else { return }
        let todo = ids.filter { id in run.items.first { $0.id == id }?.prompt.isEmpty == true }
        guard !todo.isEmpty else { return }

        lmBusy += 1
        defer { lmBusy -= 1 }
        var gemmaError: String?
        do {
            try await ensureLMReady()
        } catch {
            gemmaError = error.localizedDescription
        }
        let imageURL = ImageTools.dataURL(run.source.image, maxSide: 768)
        let values = run.items.map(\.value)

        for id in todo {
            guard !Task.isCancelled, seriesRun?.id == runID,
                  let item = seriesRun?.items.first(where: { $0.id == id }) else { return }
            if gemmaError == nil, let imageURL {
                updateSeriesItem(id) { $0.phase = .writing }
                let request = PromptTemplates.seriesRequest(
                    variable: run.variable,
                    name: run.variableName,
                    value: item.value,
                    common: run.commonPrompt,
                    others: values.filter { $0 != item.value }
                )
                let messages: [ChatMessage] = [.system(PromptTemplates.series), .user(request, images: [imageURL])]
                do {
                    for try await chunk in lm.stream(messages, temperature: 0.35, maxTokens: 320) {
                        updateSeriesItem(id) { $0.prompt += chunk }
                    }
                    if Task.isCancelled { return }
                    let text = LMStudioClient.clean(seriesRun?.items.first { $0.id == id }?.prompt ?? "")
                    if text.isEmpty { throw ServiceError("Gemma hat keinen Prompt geliefert.") }
                    updateSeriesItem(id) { item in
                        item.prompt = text
                        item.usesTemplate = false
                        item.phase = .queued
                    }
                    continue
                } catch {
                    if Task.isCancelled { return }
                    gemmaError = error.localizedDescription
                }
            }
            // Ohne Gemma: einfacher Prompt aus der Regel der Variable.
            updateSeriesItem(id) { item in
                item.prompt = PromptTemplates.seriesFallback(variable: run.variable, name: run.variableName, value: item.value)
                item.usesTemplate = true
                item.phase = .queued
            }
        }
        if let gemmaError {
            errorMessage = "Gemma konnte die Prompts nicht schreiben (\(gemmaError)). Die Serie nutzt einfache Vorlagen."
        }
    }

    private func renderSeriesItem(_ id: UUID, in runID: UUID, freshSeed: Bool) async {
        guard let run = seriesRun, run.id == runID, let item = run.items.first(where: { $0.id == id }), !item.prompt.isEmpty else { return }
        let seed: UInt32? = freshSeed || run.seed == nil
            ? (settings.randomSeed ? UInt32.random(in: 0..<UInt32.max) : nil)
            : run.seed
        let request = DrawThingsRequest(
            prompt: item.prompt,
            width: Int(run.size.width),
            height: Int(run.size.height),
            initImages: [ImageTools.pngData(ImageTools.filled(run.source.image, to: run.size))].compactMap { $0 },
            model: settings.switchModelPerMode ? settings.modelFile(for: .series) : nil,
            seed: seed
        )
        updateSeriesItem(id) { $0.phase = .rendering }
        do {
            let (results, duration) = try await render(request, mode: .series, size: run.size)
            guard let data = results.first, let image = ImageTools.image(from: data) else {
                throw ServiceError("Draw Things hat kein lesbares Bild geliefert.")
            }
            guard seriesRun?.id == runID else { return }
            let tag = SeriesTag(
                id: run.id, index: item.number, value: item.value, title: run.variableName,
                symbol: run.variable.symbol, sourceID: run.source.versionID, prompt: run.commonPrompt
            )
            let version = addVersion(
                ImageVersion(image: image, prompt: item.prompt, source: .generated(.series), seed: seed, duration: duration, parentID: run.source.versionID, series: tag),
                select: false
            )
            updateSeriesItem(id) { item in
                item.image = image
                item.versionID = version.id
                item.fileURL = version.fileURL
                item.seed = seed
                item.duration = duration
                item.phase = .done
            }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            updateSeriesItem(id) { $0.phase = .failed(error.localizedDescription) }
        }
    }

    private func updateSeriesItem(_ id: UUID, _ change: (inout SeriesItem) -> Void) {
        guard let index = seriesRun?.items.firstIndex(where: { $0.id == id }) else { return }
        change(&seriesRun!.items[index])
    }
}
