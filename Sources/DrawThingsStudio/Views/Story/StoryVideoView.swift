import SwiftUI

/// „Video“ einer Story: Gemma schreibt für je zwei benachbarte Bilder (Bild n = Startframe, Bild n+1 = Endframe)
/// den Prompt eines Clips – für das Videomodell des Presets (bisher Gemini Omni). Oben Einstellungen, Idee und Handlung,
/// darunter alle Clips der Reihe nach, am Ende die Anleitung. Generiert wird außerhalb der App.
struct StoryVideoView: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID

    var body: some View {
        let transitions = studio.gallery.storyTransitions(storyID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StoryVideoSetup(storyID: storyID, transitions: transitions)
                if transitions.isEmpty {
                    Label("Eine Story braucht mindestens zwei Bilder – je zwei nebeneinander werden ein Clip: Bild 1 ist das Startbild, Bild 2 das Endbild.",
                          systemImage: "film")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 16)
                } else {
                    ForEach(transitions) { transition in
                        StoryClipCard(storyID: storyID, transition: transition, total: transitions.count)
                    }
                    StoryVideoGuide(storyID: storyID)
                }
            }
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 4)
            .padding(.bottom, 30)
        }
    }
}

/// Bindungen an den Video-Plan einer Story – jede Änderung landet im Katalog der Bibliothek.
@MainActor
private struct PlanBinding {
    let gallery: Gallery
    let storyID: UUID

    func callAsFunction<Value>(_ keyPath: WritableKeyPath<StoryVideoPlan, Value>) -> Binding<Value> {
        Binding(
            get: { (gallery.story(storyID)?.video ?? StoryVideoPlan())[keyPath: keyPath] },
            set: { value in gallery.updateStoryVideo(storyID) { $0[keyPath: keyPath] = value } }
        )
    }

    func clip<Value>(_ transition: StoryTransition, _ keyPath: WritableKeyPath<StoryClip, Value>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { gallery.story(storyID)?.video.clip(from: transition.from.id, to: transition.to.id)?[keyPath: keyPath] ?? fallback },
            set: { value in gallery.updateClip(storyID, from: transition.from.id, to: transition.to.id) { $0[keyPath: keyPath] = value } }
        )
    }
}

// MARK: - Einstellungen, Idee, Handlung

private struct StoryVideoSetup: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID
    let transitions: [StoryTransition]

    var body: some View {
        let gallery = studio.gallery
        let plan = gallery.story(storyID)?.video ?? StoryVideoPlan()
        let bind = PlanBinding(gallery: gallery, storyID: storyID)
        let items = gallery.storyItems(storyID)
        let writing = studio.storyWriting.flatMap { $0.storyID == storyID ? $0 : nil }
        let isBusy = studio.storyWriting != nil
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(GemmaStyle.gradient)
                Text("Video mit Gemma")
                    .font(.headline)
                Spacer(minLength: 8)
                if !transitions.isEmpty {
                    CopyButton(title: "Alle Prompts kopieren", help: "Alle Clips mit Nummer, Bildern und Prompt als Text") {
                        studio.copyAllStoryPrompts(storyID)
                    }
                    Button("Exportieren …", systemImage: "square.and.arrow.up") { studio.exportStoryForVideo(storyID) }
                        .buttonStyle(.borderless)
                        .help("Ordner mit den Bildern in Story-Reihenfolge (01.png, 02.png …) und Prompts.txt – zum Hochladen in Gemini oder Flow")
                }
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Videomodell").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Picker("Videomodell", selection: bind(\.presetID)) {
                                ForEach(VideoPreset.all) { preset in
                                    Text("\(preset.name) · \(preset.maker)").tag(preset.id)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            if let url = plan.preset.guideURL {
                                Link("Anleitung von \(plan.preset.maker)", destination: url)
                                    .font(.caption)
                            }
                        }
                        Text(plan.preset.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Format").foregroundStyle(.secondary)
                    Picker("Format", selection: bind(\.format)) {
                        ForEach(StoryVideoFormat.allCases) { format in
                            Text(format == .auto ? "Auto (\(StoryVideoFormat.auto.resolved(for: items).title))" : format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Gemini Omni kennt 16:9 und 9:16. Auto nimmt das Format der meisten Bilder.")
                }
                GridRow {
                    Text("Länge je Clip").foregroundStyle(.secondary)
                    Picker("Länge je Clip", selection: bind(\.duration)) {
                        ForEach(plan.preset.durations, id: \.self) { seconds in
                            Text("\(seconds) s").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Gemma plant die Bewegung für diese Länge. Einzelne Clips lassen sich unten anders einstellen.")
                }
                GridRow {
                    Text("Ton").foregroundStyle(.secondary)
                    Picker("Ton", selection: bind(\.audio)) {
                        ForEach(StoryAudio.allCases) { audio in
                            Text(audio.title).tag(audio)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help(plan.audio.help + ". Gemini Omni erzeugt immer eine Tonspur – ohne Angabe erfindet es gern Musik.")
                }
            }
            .font(.callout)

            VStack(alignment: .leading, spacing: 6) {
                Text("Worum geht es?")
                    .font(.callout.weight(.semibold))
                TextField("Optional, auf Deutsch – z. B. „Ein Tag am Meer, ruhig und warm, ohne Dialog“", text: bind(\.idea), axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            }

            if !plan.arc.isEmpty || writing?.transitionID == nil && writing != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Handlung")
                            .font(.callout.weight(.semibold))
                        Text("von Gemma, du kannst sie ändern")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Neu vorschlagen", systemImage: "arrow.trianglehead.counterclockwise") {
                            studio.writeStory(storyID, scope: .arcOnly)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isBusy || transitions.isEmpty)
                        .help("Gemma sieht sich alle Bilder noch einmal an und schreibt die Handlung neu")
                    }
                    TextEditor(text: bind(\.arc))
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80, maxHeight: 220)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                        .disabled(writing != nil)
                        .opacity(writing?.transitionID == nil && writing != nil ? 0.5 : 1)
                    if !plan.arcOrder.isEmpty, plan.arcOrder != items.map(\.id), writing == nil {
                        Label("Die Reihenfolge der Bilder hat sich seitdem geändert – „Neu vorschlagen“, damit die Nummern wieder stimmen.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                if let writing {
                    Button("Abbrechen", systemImage: "stop.fill") { studio.cancelStoryWriting() }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                    ProgressView()
                        .controlSize(.small)
                    TimelineView(.periodic(from: writing.started, by: 1)) { context in
                        Text(progressText(writing) + " · \(Int(context.date.timeIntervalSince(writing.started))) s")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let missing = transitions.filter { plan.clip(from: $0.from.id, to: $0.to.id)?.prompt.trimmed.isEmpty ?? true }.count
                    Button {
                        studio.writeStory(storyID, scope: missing == 0 ? .all : .missing)
                    } label: {
                        Label(writeTitle(missing: missing, total: transitions.count), systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(GemmaStyle.tint)
                    .disabled(transitions.isEmpty || isBusy)
                    .help("Gemma sieht sich die Bilder an, schreibt die Handlung (falls noch keine da ist) und danach jeden Clip – einen nach dem anderen")
                    if missing < transitions.count, missing > 0 {
                        Button("Alle neu schreiben") { studio.writeStory(storyID, scope: .all) }
                            .buttonStyle(.borderless)
                            .disabled(isBusy)
                            .help("Auch die Clips neu schreiben, die schon einen Prompt haben – deine Wünsche bleiben")
                    }
                    if plan.arc.isEmpty {
                        Button("Nur Handlung") { studio.writeStory(storyID, scope: .arcOnly) }
                            .buttonStyle(.borderless)
                            .disabled(transitions.isEmpty || isBusy)
                            .help("Erst nur die Handlung vorschlagen lassen, prüfen und anpassen – dann die Clips")
                    }
                    if isBusy {
                        Text("Gemma schreibt gerade an einer anderen Story.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let error = studio.storyErrors[storyID] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 16)
        .overlay {
            if writing?.transitionID == nil && writing != nil { GlowBorder(cornerRadius: 12, lineWidth: 2) }
        }
    }

    private func writeTitle(missing: Int, total: Int) -> String {
        if missing == 0 { return "Alle Clips neu schreiben" }
        if missing == total { return "Story schreiben" }
        return missing == 1 ? "Fehlenden Clip schreiben" : "\(missing) fehlende Clips schreiben"
    }

    private func progressText(_ writing: StoryWriting) -> String {
        guard let id = writing.transitionID else { return "Gemma liest die Bilder und schreibt die Handlung" }
        let number = (transitions.firstIndex { $0.id == id } ?? 0) + 1
        return "Gemma schreibt Clip \(number) · \(writing.done) von \(writing.total) fertig"
    }
}

// MARK: - Clip

/// Ein Übergang: Startbild → Endbild, dein Wunsch, Gemmas Prompt und ihre Zusammenfassung.
private struct StoryClipCard: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID
    let transition: StoryTransition
    let total: Int

    var body: some View {
        let gallery = studio.gallery
        let plan = gallery.story(storyID)?.video ?? StoryVideoPlan()
        let clip = plan.clip(from: transition.from.id, to: transition.to.id)
        let bind = PlanBinding(gallery: gallery, storyID: storyID)
        let isWritingThis = studio.storyWriting?.transitionID == transition.id
        let isBusy = studio.storyWriting != nil
        let prompt = clip?.prompt ?? ""
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    FrameThumb(item: transition.from, caption: "Start")
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    FrameThumb(item: transition.to, caption: "Ende")
                }
                Text("Bild \(transition.number) → Bild \(transition.number + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 236)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Clip \(transition.number)")
                        .font(.headline)
                        .monospacedDigit()
                    durationMenu(plan: plan, clip: clip)
                    if transition.number == 1 { tag("Anfang") }
                    if transition.number == total { tag("Ende") }
                    if isWritingThis {
                        ProgressView()
                            .controlSize(.small)
                        Text("Gemma schreibt …")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if !prompt.trimmed.isEmpty, !isWritingThis {
                        CopyButton(title: "Prompt kopieren", help: "In Gemini oder Flow ins Prompt-Feld einfügen", prominent: true) {
                            studio.copyToPasteboard(prompt.trimmed)
                        }
                    }
                    Button {
                        studio.writeStory(storyID, scope: .clip(transition.id))
                    } label: {
                        Label(prompt.trimmed.isEmpty ? "Schreiben" : "Neu schreiben", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isBusy)
                    .help("Gemma schreibt nur diesen Clip – mit Start- und Endbild, Handlung und deinem Wunsch")
                    Menu {
                        Button("Startbild kopieren", systemImage: "doc.on.doc") { studio.copyStoryImage(transition.from) }
                        Button("Endbild kopieren", systemImage: "doc.on.doc") { studio.copyStoryImage(transition.to) }
                        Button("Bilder im Finder zeigen", systemImage: "folder") { studio.revealInFinder([transition.from, transition.to]) }
                        Divider()
                        Button("Prompt leeren", systemImage: "eraser") {
                            gallery.updateClip(storyID, from: transition.from.id, to: transition.to.id) { clip in
                                clip.prompt = ""
                                clip.summary = ""
                                clip.writtenAt = nil
                            }
                        }
                        .disabled(prompt.isEmpty || isWritingThis)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                TextField("Was soll passieren? Optional – z. B. „Sie dreht sich zum Meer, die Kamera fährt langsam zurück“. Gesprochenes in „…“.",
                          text: bind.clip(transition, \.wish, default: ""), axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

                if prompt.isEmpty && !isWritingThis {
                    Text("Noch kein Prompt – „Schreiben“ hier oder oben „Story schreiben“. Gemma sieht dafür Start- und Endbild.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                } else {
                    TextEditor(text: bind.clip(transition, \.prompt, default: ""))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 96, maxHeight: 240)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                        .disabled(isWritingThis)
                        .opacity(isWritingThis ? 0.5 : 1)
                }

                if let summary = clip?.summary, !summary.isEmpty, !isWritingThis {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.bubble")
                            .foregroundStyle(GemmaStyle.gradient)
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .help("So hat Gemma den Übergang verstanden")
                }
            }
        }
        .card(padding: 14)
        .overlay {
            if isWritingThis { GlowBorder(cornerRadius: 12, lineWidth: 2) }
        }
    }

    private func durationMenu(plan: StoryVideoPlan, clip: StoryClip?) -> some View {
        let gallery = studio.gallery
        let seconds = plan.duration(of: clip)
        return Menu {
            Button("Wie die Story (\(plan.duration) s)") {
                gallery.updateClip(storyID, from: transition.from.id, to: transition.to.id) { $0.duration = nil }
            }
            Divider()
            ForEach(plan.preset.durations, id: \.self) { value in
                Button("\(value) s") {
                    gallery.updateClip(storyID, from: transition.from.id, to: transition.to.id) { $0.duration = value }
                }
            }
        } label: {
            Text("\(seconds) s")
                .font(.callout.monospacedDigit())
                .foregroundStyle(clip?.duration == nil ? Color.secondary : Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Länge dieses Clips – Gemma plant die Bewegung dafür (danach neu schreiben lassen)")
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(Color.accentColor)
    }
}

/// Start- oder Endbild eines Clips – zum Herausziehen in Gemini oder Flow im Browser.
private struct FrameThumb: View {
    @Environment(Studio.self) private var studio
    let item: GalleryItem
    let caption: String

    var body: some View {
        GalleryThumbnail(item: item)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .frame(width: 104, height: 104)
            .overlay(alignment: .bottomLeading) {
                Text(caption)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(4)
            }
            .onDrag { NSItemProvider(object: item.url as NSURL) }
            .contextMenu {
                Button("Bild kopieren", systemImage: "doc.on.doc") { studio.copyStoryImage(item) }
                Button("Im Finder zeigen", systemImage: "folder") { studio.revealInFinder([item]) }
                OpenInAppButton(urls: [item.url])
            }
            .help("\(caption)bild – in Gemini oder Flow im Browser ziehen, oder Rechtsklick › Bild kopieren")
    }
}

// MARK: - Anleitung

private struct StoryVideoGuide: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID

    var body: some View {
        let gallery = studio.gallery
        let plan = gallery.story(storyID)?.video ?? StoryVideoPlan()
        let format = plan.format.resolved(for: gallery.storyItems(storyID))
        VStack(alignment: .leading, spacing: 12) {
            Label("So wird daraus ein Video – \(plan.preset.name)", systemImage: "film.stack")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Array(plan.preset.steps.enumerated()), id: \.offset) { index, step in
                    GridRow {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
                        Text(step)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            Text("Für jeden Clip der Reihe nach – Format \(format.title), \(plan.duration) s. Danach die Clips in der Reihenfolge der Story aneinandersetzen. Gemma ist auf \(plan.preset.name) eingestellt; generiert wird nicht in DrawThings Studio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 16)
    }
}
