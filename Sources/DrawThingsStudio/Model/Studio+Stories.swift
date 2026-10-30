import AppKit
import UniformTypeIdentifiers

/// Was Gemma bei einer Story schreiben soll.
enum StoryWriteScope: Equatable {
    /// Handlung (falls leer) und alle Clips ohne Prompt.
    case missing
    /// Alle Clips neu – die Handlung bleibt, falls es schon eine gibt.
    case all
    /// Nur die Handlung neu vorschlagen.
    case arcOnly
    /// Ein einzelner Clip (`StoryTransition.id`).
    case clip(String)
}

/// Stories: präsentieren, Gemma schreibt Handlung und Video-Prompts, alles für das Videomodell kopieren oder exportieren.
/// Generiert wird außerhalb der App – in Gemini oder Google Flow.
extension Studio {

    // MARK: Präsentieren

    func present(_ storyID: UUID, layout: PresentationLayout, fullScreen: Bool, from index: Int = 0) {
        let count = gallery.storyItems(storyID).count
        guard count > 0 else {
            errorMessage = "Die Story ist noch leer – zieh Bilder aus der Galerie auf sie."
            return
        }
        let start = (min(max(index, 0), count - 1) / layout.rawValue) * layout.rawValue
        gallery.closeViewer()
        // Der Knopf „Präsentieren“ startet beim nächsten Mal genauso.
        UserDefaults.standard.set(layout.rawValue, forKey: "story.presentLayout")
        UserDefaults.standard.set(fullScreen, forKey: "story.presentFullScreen")
        presentation = StoryPresentation(storyID: storyID, layout: layout, isFullScreen: fullScreen, index: start)
        // Wie im Fokusmodus: die Werkzeugleiste ganz weg, auch im Fenster.
        studioWindow?.toolbar?.isVisible = false
        if fullScreen { enterPresentationFullScreen() }
    }

    func endPresentation() {
        guard presentation != nil else { return }
        presentation = nil
        if !isFocusMode { studioWindow?.toolbar?.isVisible = true }
        leavePresentationFullScreen()
    }

    func setPresentationFullScreen(_ on: Bool) {
        guard presentation != nil, presentation?.isFullScreen != on else { return }
        presentation?.isFullScreen = on
        if on { enterPresentationFullScreen() } else { leavePresentationFullScreen() }
    }

    /// Ein Bild ↔ Raster: Die Seite bleibt bei dem Bild, das gerade vorne war.
    func setPresentationLayout(_ layout: PresentationLayout) {
        guard var current = presentation, current.layout != layout else { return }
        let count = gallery.storyItems(current.storyID).count
        let index = min(current.index, max(count - 1, 0))
        current.index = (index / layout.rawValue) * layout.rawValue
        current.layout = layout
        presentation = current
    }

    /// Seitenweise blättern; hinter der letzten Seite steht „Ende der Story“.
    func stepPresentation(_ delta: Int) {
        guard var current = presentation else { return }
        let count = gallery.storyItems(current.storyID).count
        guard count > 0 else { return }
        let perPage = current.layout.rawValue
        let lastPage = ((count - 1) / perPage) * perPage
        if current.index >= count {
            if delta < 0 { current.index = lastPage }
        } else {
            let next = current.index + delta * perPage
            current.index = next > lastPage ? count : max(next, 0)
        }
        presentation = current
    }

    func jumpPresentation(toEnd: Bool) {
        guard var current = presentation else { return }
        let count = gallery.storyItems(current.storyID).count
        let perPage = current.layout.rawValue
        current.index = toEnd ? ((max(count, 1) - 1) / perPage) * perPage : 0
        presentation = current
    }

    private func enterPresentationFullScreen() {
        guard let window = studioWindow, !window.styleMask.contains(.fullScreen) else { return }
        presentationEnteredFullScreen = true
        window.toggleFullScreen(nil)
    }

    /// Nur verlassen, was die Präsentation selbst eingeschaltet hat (nicht das Vollbild des Fokusmodus).
    private func leavePresentationFullScreen() {
        guard presentationEnteredFullScreen else { return }
        presentationEnteredFullScreen = false
        if let window = studioWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    /// Bibliothek wird gewechselt: Präsentation beenden, Gemma anhalten.
    func closeStories() {
        cancelStoryWriting()
        storyErrors = [:]
        endPresentation()
    }

    // MARK: Gemma

    func isWriting(_ storyID: UUID) -> Bool { storyWriting?.storyID == storyID }

    /// Gemma schreibt nacheinander – erst die Handlung aus allen Bildern, dann jeden Clip mit Start- und Endbild.
    func writeStory(_ storyID: UUID, scope: StoryWriteScope) {
        guard storyWriting == nil, let story = gallery.story(storyID) else { return }
        let transitions = gallery.storyTransitions(storyID)
        guard !transitions.isEmpty else {
            storyErrors[storyID] = "Eine Story braucht mindestens zwei Bilder – je zwei nebeneinander werden ein Clip."
            return
        }
        let plan = story.video
        let needsArc: Bool
        let targets: [StoryTransition]
        switch scope {
        case .arcOnly:
            needsArc = true
            targets = []
        case .all:
            needsArc = plan.arc.trimmed.isEmpty
            targets = transitions
        case .missing:
            needsArc = plan.arc.trimmed.isEmpty
            targets = transitions.filter { plan.clip(from: $0.from.id, to: $0.to.id)?.prompt.trimmed.isEmpty ?? true }
        case .clip(let id):
            needsArc = false
            targets = transitions.filter { $0.id == id }
        }
        guard needsArc || !targets.isEmpty else { return }

        storyErrors[storyID] = nil
        storyWriting = StoryWriting(storyID: storyID, transitionID: needsArc ? nil : targets.first?.id, total: targets.count + (needsArc ? 1 : 0))
        storyTask = Task {
            lmBusy += 1
            defer { lmBusy -= 1 }
            do {
                try await ensureLMReady()
                if needsArc {
                    try await writeStoryArc(storyID)
                    storyWriting?.done += 1
                }
                for transition in targets {
                    try Task.checkCancellation()
                    storyWriting?.transitionID = transition.id
                    try await writeClip(storyID, transition)
                    storyWriting?.done += 1
                }
                if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                storyErrors[storyID] = error.localizedDescription
            }
            // Abgebrochen: `cancelStoryWriting` hat den Zustand schon zurückgesetzt.
            guard !Task.isCancelled else { return }
            storyWriting = nil
            storyTask = nil
        }
    }

    func cancelStoryWriting() {
        storyTask?.cancel()
        storyTask = nil
        storyWriting = nil
    }

    /// Handlung: Gemma sieht alle Bilder (bei vielen eine gleichmäßige Auswahl) und schreibt auf Deutsch, worum es geht.
    private func writeStoryArc(_ storyID: UUID) async throws {
        let items = gallery.storyItems(storyID)
        let idea = gallery.story(storyID)?.video.idea.trimmed ?? ""
        var sources: [(number: Int, image: CGImage)] = []
        for index in Self.sampleIndices(items.count, limit: 8) {
            if let image = await GalleryImages.image(for: items[index]) { sources.append((index + 1, image)) }
        }
        let attached = await Task.detached(priority: .userInitiated) {
            sources.compactMap { source in ImageTools.dataURL(source.image, maxSide: 512).map { (source.number, $0) } }
        }.value
        try Task.checkCancellation()
        guard !attached.isEmpty else { throw ServiceError("Die Bilder der Story konnten nicht geladen werden.") }
        let request = PromptTemplates.storyArcRequest(numbers: attached.map(\.0), total: items.count, idea: idea)
        let messages: [ChatMessage] = [.system(PromptTemplates.storyArc), .user(request, images: attached.map(\.1))]
        let raw = try await lm.complete(messages, temperature: 0.5, maxTokens: 400 + 60 * items.count,
                                        schema: PromptTemplates.storyArcSchema(pictureCount: items.count))
        try Task.checkCancellation()
        let object = try Self.jsonObject(raw)
        let about = (object["about"] as? String)?.trimmed ?? ""
        let pictures = (object["pictures"] as? [String] ?? []).prefix(items.count).map(\.trimmed)
        guard !about.isEmpty || !pictures.isEmpty else { throw ServiceError("Gemma hat keine Handlung geliefert.") }
        let arc = PromptTemplates.storyArcText(about: about, pictures: Array(pictures))
        gallery.updateStoryVideo(storyID) { plan in
            plan.arc = arc
            plan.arcOrder = items.map(\.id)
        }
    }

    /// Ein Clip: Gemma sieht Start- und Endbild und kennt Handlung, Nachbar-Clips und deinen Wunsch.
    private func writeClip(_ storyID: UUID, _ transition: StoryTransition) async throws {
        guard let plan = gallery.story(storyID)?.video else { return }
        // Die Reihenfolge kann sich während des Schreibens geändert haben – Nummer und Nachbarn frisch bestimmen.
        let transitions = gallery.storyTransitions(storyID)
        let position = transitions.firstIndex { $0.id == transition.id }
        let number = position.map { $0 + 1 } ?? transition.number
        let items = gallery.storyItems(storyID)
        let fromNumber = (items.firstIndex { $0.id == transition.from.id } ?? number - 1) + 1
        let toNumber = (items.firstIndex { $0.id == transition.to.id } ?? number) + 1

        func describe(_ neighbour: StoryTransition) -> String {
            let clip = plan.clip(from: neighbour.from.id, to: neighbour.to.id)
            if let summary = clip?.summary.trimmed, !summary.isEmpty { return summary }
            if let wish = clip?.wish.trimmed, !wish.isEmpty { return wish }
            return "not written yet"
        }
        let previous = position.flatMap { $0 > 0 ? describe(transitions[$0 - 1]) : nil }
        let next = position.flatMap { $0 + 1 < transitions.count ? describe(transitions[$0 + 1]) : nil }
        let clip = plan.clip(from: transition.from.id, to: transition.to.id)
        let context = PromptTemplates.ClipContext(
            number: number,
            total: max(transitions.count, number),
            fromNumber: fromNumber,
            toNumber: toNumber,
            duration: plan.duration(of: clip),
            format: plan.format.resolved(for: items),
            audio: plan.audio,
            idea: plan.idea.trimmed,
            arc: plan.arc.trimmed,
            previous: number == 1 ? nil : previous ?? "not written yet",
            next: number == transitions.count ? nil : next ?? "not written yet",
            wish: clip?.wish.trimmed ?? ""
        )

        guard let start = await GalleryImages.image(for: transition.from),
              let end = await GalleryImages.image(for: transition.to) else {
            throw ServiceError("Bild \(fromNumber) oder \(toNumber) konnte nicht geladen werden.")
        }
        let images = await Task.detached(priority: .userInitiated) {
            [start, end].compactMap { ImageTools.dataURL($0, maxSide: 768) }
        }.value
        try Task.checkCancellation()
        guard images.count == 2 else { throw ServiceError("Bild \(fromNumber) oder \(toNumber) konnte nicht verkleinert werden.") }

        let messages: [ChatMessage] = [
            .system(plan.preset.clipInstructions),
            .user(PromptTemplates.clipRequest(context), images: images),
        ]
        let raw = try await lm.complete(messages, temperature: 0.4, maxTokens: 900, schema: PromptTemplates.clipSchema)
        try Task.checkCancellation()
        let object = try Self.jsonObject(raw)
        let scene = (object["scene"] as? String)?.trimmed ?? ""
        guard !scene.isEmpty else { throw ServiceError("Gemma hat für Clip \(number) keinen Prompt geliefert.") }
        let prompt = PromptTemplates.assembleClipPrompt(
            scene: scene,
            sound: (object["sound"] as? String)?.trimmed ?? "",
            music: (object["music"] as? String)?.trimmed ?? "",
            dialogue: (object["dialogue"] as? String)?.trimmed ?? "",
            audio: plan.audio,
            wish: context.wish
        )
        let summary = (object["summary"] as? String)?.trimmed ?? ""
        gallery.updateClip(storyID, from: transition.from.id, to: transition.to.id) { clip in
            clip.prompt = prompt
            clip.summary = summary
            clip.writtenAt = .now
        }
    }

    /// Gleichmäßig verteilte Bilder, erstes und letztes immer dabei.
    nonisolated static func sampleIndices(_ count: Int, limit: Int) -> [Int] {
        guard count > limit, limit > 1 else { return Array(0..<count) }
        return (0..<limit).map { Int((Double($0) * Double(count - 1) / Double(limit - 1)).rounded()) }
    }

    /// JSON aus Gemmas Antwort – auch wenn sie es in einen Codeblock gepackt hat.
    private static func jsonObject(_ raw: String) throws -> [String: Any] {
        var text = raw
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError("Gemmas Antwort war kein gültiges JSON.")
        }
        return object
    }

    // MARK: Kopieren & Exportieren

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Bild für Gemini oder Flow im Browser in die Zwischenablage (dort ⌘V).
    func copyStoryImage(_ item: GalleryItem) {
        Task {
            guard let image = await GalleryImages.image(for: item) else {
                errorMessage = "„\(item.url.lastPathComponent)“ konnte nicht geladen werden."
                return
            }
            let entry = NSPasteboardItem()
            if let png = ImageTools.pngData(image) { entry.setData(png, forType: .png) }
            if let tiff = NSImage(cgImage: image, size: .zero).tiffRepresentation { entry.setData(tiff, forType: .tiff) }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([entry])
        }
    }

    func copyAllStoryPrompts(_ storyID: UUID) {
        copyToPasteboard(storyPromptsText(storyID))
    }

    /// Alle Clips als Text – mit Dateinamen, wenn die Bilder exportiert wurden.
    func storyPromptsText(_ storyID: UUID, fileNames: [UUID: String] = [:]) -> String {
        guard let story = gallery.story(storyID) else { return "" }
        let plan = story.video
        let items = gallery.storyItems(storyID)
        let format = plan.format.resolved(for: items)
        var lines = [
            "Story „\(story.name)“ – \(plan.preset.name)",
            "Format \(format.title) · \(plan.duration) s je Clip · Ton: \(plan.audio.title)",
        ]
        if !plan.idea.trimmed.isEmpty { lines += ["", "Worum es geht: \(plan.idea.trimmed)"] }
        if !plan.arc.trimmed.isEmpty { lines += ["", "Handlung:", plan.arc.trimmed] }
        for transition in gallery.storyTransitions(storyID) {
            let clip = plan.clip(from: transition.from.id, to: transition.to.id)
            lines += ["", String(repeating: "─", count: 40)]
            lines.append("Clip \(transition.number) · Bild \(transition.number) → Bild \(transition.number + 1) · \(plan.duration(of: clip)) s")
            if let start = fileNames[transition.from.id], let end = fileNames[transition.to.id] {
                lines.append("Startbild: \(start) · Endbild: \(end)")
            }
            if let wish = clip?.wish.trimmed, !wish.isEmpty { lines.append("Wunsch: \(wish)") }
            lines.append("")
            let prompt = clip?.prompt.trimmed ?? ""
            lines.append(prompt.isEmpty ? "(noch nicht geschrieben)" : prompt)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Ordner mit den Bildern in Story-Reihenfolge (01.png, 02.png …) und allen Prompts – zum Hochladen in Gemini oder Flow.
    func exportStoryForVideo(_ storyID: UUID) {
        guard let story = gallery.story(storyID) else { return }
        let items = gallery.storyItems(storyID)
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Exportieren"
        panel.message = "Ordner wählen – darin entsteht „\(story.name)“ mit den Bildern in Story-Reihenfolge und den Prompts."
        guard panel.runModal() == .OK, let base = panel.url else { return }

        let fm = FileManager.default
        let name = story.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var folder = base.appending(path: name, directoryHint: .isDirectory)
        var number = 2
        while fm.fileExists(atPath: folder.path) {
            folder = base.appending(path: "\(name) \(number)", directoryHint: .isDirectory)
            number += 1
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let digits = max(String(items.count).count, 2)
            var fileNames: [UUID: String] = [:]
            for (index, item) in items.enumerated() {
                let file = String(format: "%0\(digits)d", index + 1) + "." + item.url.pathExtension.lowercased()
                try fm.copyItem(at: item.url, to: folder.appending(path: file))
                fileNames[item.id] = file
            }
            try storyPromptsText(storyID, fileNames: fileNames).write(to: folder.appending(path: "Prompts.txt"), atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

extension Studio {
    /// ⌥⌘P: In der Galerie ist eine Story mit Bildern offen.
    var canPresentStory: Bool {
        guard showGallery, case .story(let id) = gallery.collection else { return false }
        return !gallery.storyItems(id).isEmpty
    }
}
