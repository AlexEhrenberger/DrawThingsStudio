import AppKit
import SwiftUI

/// Labs – dunkel wie der Fokusmodus: Canvas, Moodboards und Gemmas Prompt für Draw Things.
struct LabsView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ComposeLabView()
        }
        .overlay(alignment: .top) {
            if let message = studio.errorMessage {
                ErrorBanner(message: message)
                    .padding(.top, 14)
            }
        }
        .animation(.smooth(duration: 0.25), value: studio.errorMessage)
        // Lesbar bleiben, selbst wenn das Fenster kurz hell wird (wie im Fokusmodus).
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Seitenleiste

/// Links nur der Verlauf: Gemmas Prompts, ein Klick holt einen zurück ins Ergebnis.
struct LabsSidebar: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        List {
            Section("Verlauf") {
                if studio.composition.history.isEmpty {
                    Text("Gemmas Prompts erscheinen hier.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                ForEach(studio.composition.history) { record in
                    LabHistoryRow(record: record)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct LabHistoryRow: View {
    @Environment(Studio.self) private var studio
    let record: LabPromptRecord

    var body: some View {
        Button {
            studio.restoreLabPrompt(record)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.prompt)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(record.prompt == studio.composition.prompt ? .primary : .secondary)
                Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.imageCount == 1 ? "1 Bild" : "\(record.imageCount) Bilder")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .help(record.check.isEmpty ? "Prompt wieder ins Ergebnis holen" : record.check)
        .contextMenu {
            Button("Ins Ergebnis holen", systemImage: "arrow.uturn.backward") { studio.restoreLabPrompt(record) }
            Button("Prompt kopieren", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.prompt, forType: .string)
            }
            Divider()
            Button("Aus dem Verlauf löschen", systemImage: "trash", role: .destructive) { studio.deleteLabRecord(record) }
        }
    }
}

// MARK: - Bild zusammenbauen

private struct ComposeLabView: View {
    @Environment(Studio.self) private var studio
    @State private var boardWidth: CGFloat = 900
    @State private var confirmClear = false

    private let spacing: CGFloat = 14

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                board
                generalRow
                hints
                LabResultCard()
                LabSetupCard()
            }
            .padding(24)
            .frame(maxWidth: 1500)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flask.fill")
                        .foregroundStyle(GemmaStyle.gradient)
                    Text("LABS")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
                Text("Bild zusammenbauen")
                    .font(.largeTitle.weight(.semibold))
                Text("Lege das Bild, das du verändern willst, auf den Canvas und bis zu drei Bilder auf die Moodboards – wie in Draw Things. Schreib unter jedes Bild auf Deutsch, was passieren soll. Gemma schreibt daraus den Prompt für Qwen Image Edit 2511; du fügst ihn in Draw Things ein.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            Spacer(minLength: 0)
            Button("Leeren", systemImage: "trash") { confirmClear = true }
                .disabled(studio.composition.filledCount == 0 && !studio.composition.hasInstruction && studio.composition.prompt.isEmpty)
                .help("Bilder, Anweisungen und Prompt entfernen – der Verlauf bleibt")
                .confirmationDialog("Labs leeren?", isPresented: $confirmClear) {
                    Button("Leeren", role: .destructive) {
                        withAnimation(.smooth(duration: 0.25)) { studio.clearComposition() }
                    }
                } message: {
                    Text("Bilder, Anweisungen und Prompt werden entfernt. Der Verlauf links bleibt.")
                }
        }
    }

    /// Canvas groß links, die drei Moodboards daneben; in schmalen Fenstern darunter.
    private var board: some View {
        let compact = boardWidth < 860
        let unit = max((boardWidth - 3 * spacing) / 5, 120)
        let height = compact ? 300 : min(max(unit * 1.7, 240), 420)
        return Group {
            if compact {
                VStack(alignment: .leading, spacing: spacing) {
                    LabSlotCard(index: 0, imageHeight: height)
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(1..<LabSlot.count, id: \.self) { index in
                            LabSlotCard(index: index, imageHeight: 170)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    LabSlotCard(index: 0, imageHeight: height)
                        .frame(width: unit * 2 + spacing)
                    ForEach(1..<LabSlot.count, id: \.self) { index in
                        LabSlotCard(index: index, imageHeight: height)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boardWidth = $0 }
    }

    private var generalRow: some View {
        @Bindable var studio = studio
        return HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Für das ganze Bild", systemImage: "wand.and.rays")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Optional, z. B. „Abendstimmung, alles bleibt fotorealistisch“", text: $studio.composition.general, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            Button {
                if studio.composition.isWriting { studio.cancelLabPrompt() } else { studio.writeLabPrompt() }
            } label: {
                Label(studio.composition.isWriting ? "Abbrechen" : "Prompt schreiben",
                      systemImage: studio.composition.isWriting ? "stop.fill" : "sparkles")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(studio.composition.isWriting ? Color.red : GemmaStyle.tint)
            .disabled(!studio.composition.isWriting && studio.composition.blocker != nil)
            .help(studio.composition.blocker ?? "Gemma schreibt den Prompt für Draw Things (⌘↩)")
        }
    }

    @ViewBuilder
    private var hints: some View {
        let composition = studio.composition
        let silent = composition.filledMoodboards.filter { composition.slots[$0].instruction.trimmed.isEmpty }
        if composition.filledCount == LabSlot.count || !silent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if composition.filledCount == LabSlot.count {
                    Label("Vier Bilder: Qwen Image Edit ist laut Alibaba auf ein bis drei Eingabebilder ausgelegt – mit drei Moodboards kann die Treue nachlassen.", systemImage: "info.circle")
                }
                if !silent.isEmpty {
                    let names = silent.map { LabSlot.title($0) }.joined(separator: ", ")
                    Label("\(names) \(silent.count == 1 ? "hat" : "haben") keine Anweisung – Gemma nutzt \(silent.count == 1 ? "es" : "sie") nur, wenn eine andere Anweisung darauf verweist.", systemImage: "text.badge.xmark")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: Platz

private struct LabSlotCard: View {
    @Environment(Studio.self) private var studio
    let index: Int
    let imageHeight: CGFloat
    @State private var isDropTargeted = false
    @State private var isHovering = false

    private var slot: LabSlot { studio.composition.slots[index] }
    private var number: Int? { studio.composition.imageNumber(index) }
    private var isCanvas: Bool { index == LabSlot.canvas }

    var body: some View {
        @Bindable var studio = studio
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: isCanvas ? "photo.artframe" : "photo.on.rectangle")
                    .foregroundStyle(.secondary)
                Text(LabSlot.title(index))
                    .font(.headline)
                    .lineLimit(1)
                if let number {
                    Text("Picture \(number)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .fixedSize()
                        .help("So heißt das Bild im Prompt – so beschriftet Qwen Image Edit die Eingabebilder. Canvas ist Picture 1, die belegten Moodboards folgen der Reihe nach")
                }
                Spacer(minLength: 0)
                sourceMenu
            }

            imageArea
                .frame(height: imageHeight)

            TextField(placeholder, text: $studio.composition.slots[index].instruction, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(3...8)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .card()
    }

    private var placeholder: String {
        switch index {
        case 0: "Was bleibt, was ändert sich? z. B. „Der Mann in der Mitte bleibt genau so“"
        case 1: "Was kommt aus diesem Bild? z. B. „Ersetze die Ampel durch diese Laterne“"
        case 2: "z. B. „Nimm diesen Himmel für das Canvas-Bild“"
        default: "z. B. „Er trägt diese Jacke“"
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        ZStack {
            if let thumbnail = slot.thumbnail, let image = slot.image {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.07))
                CGImageView(image: thumbnail)
                    .padding(6)
                    .onDrag {
                        studio.labDragProvider(image, name: "Picture \(number ?? index + 1) – \(LabSlot.title(index))")
                    }
                    .overlay(alignment: .topTrailing) {
                        if isHovering {
                            HStack(spacing: 6) {
                                overlayButton("doc.on.doc", help: "Für Draw Things kopieren – dort mit ⌘V einfügen") { studio.copyLabImage(at: index) }
                                overlayButton("xmark", help: "Entfernen") {
                                    withAnimation(.smooth(duration: 0.2)) { studio.removeLabImage(at: index) }
                                }
                            }
                            .padding(10)
                            .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if isHovering {
                            Text("\(image.width) × \(image.height)")
                                .font(.caption2.monospacedDigit())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.55)))
                                .foregroundStyle(.white)
                                .padding(12)
                                .transition(.opacity)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.45))
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(isDropTargeted ? 0.06 : 0.02)))
                VStack(spacing: 6) {
                    Image(systemName: "plus.viewfinder")
                        .font(.system(size: isCanvas ? 30 : 22, weight: .light))
                    Text(isCanvas ? "Bild, das du verändern willst" : "Bild mit dem, was dazukommt")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Text("Hierher ziehen oder klicken")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(10)
            }
        }
        .overlay {
            if isDropTargeted && slot.image != nil {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .onTapGesture {
            guard slot.image == nil else { return }
            chooseFile()
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            Task {
                if let image = await DropLoader.loadImage(from: providers) { studio.setLabImage(image, at: index) }
            }
            return true
        }
        .contextMenu { sourceItems }
    }

    private func overlayButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }

    private var sourceMenu: some View {
        Menu {
            sourceItems
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Bild wählen, einfügen, aus Assets oder Charakteren")
    }

    @ViewBuilder
    private var sourceItems: some View {
        Button("Bild wählen …", systemImage: "folder") { chooseFile() }
        Button("Aus der Zwischenablage einfügen", systemImage: "doc.on.clipboard") { studio.pasteIntoLab(at: index) }
        if let current = studio.current {
            Button("Bild aus dem Studio", systemImage: "photo") { studio.setLabImage(current.image, at: index) }
        }
        assetMenu
        personaMenu
        if slot.image != nil {
            Divider()
            Button("Für Draw Things kopieren", systemImage: "doc.on.doc") { studio.copyLabImage(at: index) }
            Button("Entfernen", systemImage: "trash", role: .destructive) { studio.removeLabImage(at: index) }
        }
    }

    @ViewBuilder
    private var assetMenu: some View {
        let store = studio.assets
        if !store.assets.isEmpty {
            Menu("Asset", systemImage: "shippingbox") {
                ForEach(store.sections) { section in
                    let categories = store.categories(in: section.id).filter { store.count(in: $0.id) > 0 }
                    if !categories.isEmpty {
                        Section(section.name) {
                            ForEach(categories) { category in
                                Menu(category.name, systemImage: category.icon) {
                                    ForEach(store.assets(in: category.id)) { asset in
                                        Button(asset.name) { studio.useAssetInLabs(asset.id, slot: index) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var personaMenu: some View {
        let personas = studio.personas.personas.filter { $0.mainPhoto != nil }
        if !personas.isEmpty {
            Menu("Charakter", systemImage: "person.crop.square") {
                ForEach(personas) { persona in
                    Button(persona.name) { studio.usePersonaInLabs(persona.id, slot: index) }
                }
            }
        }
    }

    private func chooseFile() {
        if let image = studio.chooseImage(message: "Bild für \(LabSlot.title(index)) wählen") {
            studio.setLabImage(image, at: index)
        }
    }
}

// MARK: Ergebnis

private struct LabResultCard: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        let composition = studio.composition
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Prompt für Draw Things", systemImage: "text.quote")
                    .font(.headline)
                Spacer(minLength: 8)
                if composition.isWriting, let started = composition.writingStarted {
                    ProgressView()
                        .controlSize(.small)
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text("Gemma schreibt … \(Int(context.date.timeIntervalSince(started))) s")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else if !composition.prompt.trimmed.isEmpty {
                    CopyButton(title: "Prompt kopieren", help: "In Draw Things ins Prompt-Feld einfügen", prominent: true) {
                        studio.copyLabPrompt()
                    }
                }
            }

            if composition.prompt.isEmpty && !composition.isWriting {
                Text("Hier erscheint Gemmas Prompt – auf Englisch, so wie Qwen Image Edit ihn am besten versteht. Du kannst ihn danach noch ändern.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            } else {
                TextEditor(text: $studio.composition.prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 260)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                    .disabled(composition.isWriting)
                    .opacity(composition.isWriting ? 0.5 : 1)
            }

            if !composition.assumptions.isEmpty && !composition.isWriting {
                Label {
                    Text("Gemma war sich nicht sicher: \(composition.assumptions)")
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "questionmark.bubble.fill")
                }
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .help("Stimmt das nicht, unten mit „Nachbessern“ korrigieren oder die Anweisung oben ändern")
            }

            if let warning = composition.warning, !composition.isWriting {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !composition.check.isEmpty && !composition.isWriting {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.bubble")
                        .foregroundStyle(GemmaStyle.gradient)
                    Text(composition.check)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help("Gemmas Kontrolle: So hat sie deine Anweisungen verstanden")
            }

            if !composition.prompt.trimmed.isEmpty && !composition.isWriting {
                HStack(spacing: 8) {
                    TextField("Korrektur an Gemma, z. B. „Die Laterne soll links vom Mann stehen“", text: $studio.composition.correction)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .onSubmit { studio.writeLabPrompt(correction: studio.composition.correction) }
                    Button("Nachbessern", systemImage: "arrow.trianglehead.counterclockwise") {
                        studio.writeLabPrompt(correction: studio.composition.correction)
                    }
                    .disabled(composition.correction.trimmed.isEmpty)
                    .help("Gemma schreibt den Prompt mit dieser Korrektur neu")
                }
            }

            if let error = composition.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 16)
        .overlay {
            if composition.isWriting { GlowBorder(cornerRadius: 12, lineWidth: 2) }
        }
    }
}

// MARK: Draw Things einrichten

/// Checkliste für Draw Things – in genau der Reihenfolge, die der Prompt erwartet.
private struct LabSetupCard: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let composition = studio.composition
        VStack(alignment: .leading, spacing: 12) {
            Label("So richtest du Draw Things ein", systemImage: "paintpalette")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                step(1, "Modell") {
                    Text("Qwen Image Edit 2511")
                }
                step(2, "Canvas") {
                    if composition.canvas != nil {
                        imageChip(LabSlot.canvas)
                    } else {
                        Text("noch leer").foregroundStyle(.tertiary)
                    }
                }
                step(3, "Moodboard") {
                    if composition.filledMoodboards.isEmpty {
                        Text("leer lassen").foregroundStyle(.tertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                ForEach(composition.filledMoodboards, id: \.self) { index in
                                    imageChip(index)
                                }
                            }
                            Text("in dieser Reihenfolge – nichts anderes im Moodboard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                step(4, "Größe") {
                    if let canvas = composition.canvas {
                        let format = AspectRatio.closest(to: CGSize(width: canvas.width, height: canvas.height))
                        let tier = format.effectiveTier(studio.sizeTier)
                        Text("\(format.label) · \(Format.size(format.pixelSize(tier))) (\(tier.title)) – passend zum Canvas-Bild")
                            .monospacedDigit()
                    } else {
                        Text("wie das Canvas-Bild").foregroundStyle(.tertiary)
                    }
                }
                step(5, "Prompt") {
                    if composition.prompt.trimmed.isEmpty {
                        Text("erst schreiben lassen").foregroundStyle(.tertiary)
                    } else {
                        CopyButton(title: "Prompt kopieren", help: "In Draw Things ins Prompt-Feld einfügen") { studio.copyLabPrompt() }
                    }
                }
            }
            .font(.callout)
            Text("Labs schickt nichts an Draw Things – Bilder ziehst du aus den Plätzen hinüber oder kopierst sie (⌘V in Draw Things). LoRAs, Sampler und Schritte stellst du dort selbst ein.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 16)
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.1)))
                .gridColumnAlignment(.center)
            Text(title)
                .foregroundStyle(.secondary)
            content()
                .gridColumnAlignment(.leading)
        }
    }

    private func imageChip(_ index: Int) -> some View {
        let composition = studio.composition
        return HStack(spacing: 6) {
            if let thumbnail = composition.slots[index].thumbnail {
                CGImageView(image: thumbnail, contentMode: .fill)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Text("Picture \(composition.imageNumber(index) ?? 0)")
                .font(.callout.weight(.semibold))
            if index != LabSlot.canvas {
                Text(LabSlot.title(index))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            CopyButton(title: "Kopieren", help: "Bild kopieren – in Draw Things mit ⌘V einfügen", compact: true) {
                studio.copyLabImage(at: index)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// „In Labs verwenden ›“ – Canvas oder eines der Moodboards, mit Hinweis, was dort schon liegt.
struct LabsSlotMenuItems: View {
    @Environment(Studio.self) private var studio
    let pick: (Int) -> Void

    var body: some View {
        ForEach(0..<LabSlot.count, id: \.self) { index in
            Button {
                pick(index)
            } label: {
                Label(
                    LabSlot.title(index) + (studio.composition.slots[index].image == nil ? "" : " – ersetzen"),
                    systemImage: index == LabSlot.canvas ? "photo.artframe" : "photo.on.rectangle"
                )
            }
        }
    }
}

/// Knopf, der nach dem Kopieren kurz „Kopiert“ zeigt.
struct CopyButton: View {
    let title: String
    let help: String
    var prominent = false
    var compact = false
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        let button = Button {
            action()
            withAnimation(.smooth(duration: 0.2)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.smooth(duration: 0.2)) { copied = false }
            }
        } label: {
            Label(copied ? "Kopiert" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .contentTransition(.symbolEffect(.replace))
        }
        .help(help)
        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderless)
        }
    }
}

/// Damit `labelStyle` je nach Lage wechseln kann.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
