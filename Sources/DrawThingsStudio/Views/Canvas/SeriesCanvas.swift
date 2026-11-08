import SwiftUI

/// Eine Kachel im Serien-Raster: Ausgangsbild, Bild der Serie oder Vorschau vor dem Start.
struct SeriesTile: Identifiable {
    enum Kind {
        case source
        case item(SeriesItem)
        case preview(number: Int, value: String)
    }

    let id: String
    let kind: Kind

    var item: SeriesItem? {
        if case .item(let item) = kind { return item }
        return nil
    }
}

/// Canvas im Modus „Serien“: alle Varianten nebeneinander zum Vergleichen.
/// Klick auf ein Bild vergrößert es, ein zweiter Klick führt zurück zum Raster.
struct SeriesCanvas: View {
    @Environment(Studio.self) private var studio
    @State private var focusedID: String?
    @State private var showSource = false

    private let spacing: CGFloat = 18
    private let captionHeight: CGFloat = 30

    private var source: SeriesSource? { studio.seriesRun?.source ?? studio.seriesSource }

    var body: some View {
        ZStack {
            CanvasBackdrop()
            if let source {
                GeometryReader { proxy in
                    // Platz lassen für Hinweise oben und die Leiste unten.
                    let area = CGSize(width: max(proxy.size.width - 80, 100), height: max(proxy.size.height - 180, 100))
                    grid(source: source, in: area)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .offset(y: -12)
                }
            } else {
                SeriesEmptyState()
            }
        }
        .overlay(alignment: .bottom) {
            if source != nil {
                SeriesBar(tiles: tiles, focusedID: $focusedID, showSource: $showSource)
                    .padding(.bottom, 18)
            }
        }
        .animation(.smooth(duration: 0.3), value: focusedID)
        .animation(.smooth(duration: 0.3), value: showSource)
        .onChange(of: studio.seriesRun?.id) { focusedID = nil }
    }

    private var tiles: [SeriesTile] {
        var tiles: [SeriesTile] = []
        if showSource { tiles.append(SeriesTile(id: "source", kind: .source)) }
        if let run = studio.seriesRun {
            tiles += run.items.map { SeriesTile(id: $0.id.uuidString, kind: .item($0)) }
        } else {
            let values = studio.seriesSetup.filledValues
            let previews = values.isEmpty ? Array(repeating: "", count: SeriesSetup.maxCount) : values
            tiles += previews.enumerated().map { index, value in
                SeriesTile(id: "preview-\(index)", kind: .preview(number: index + 1, value: value))
            }
        }
        return tiles
    }

    @ViewBuilder
    private func grid(source: SeriesSource, in area: CGSize) -> some View {
        let all = tiles
        let shown = all.first { $0.id == focusedID }.map { [$0] } ?? all
        let aspect = source.size.width / max(source.size.height, 1)
        let layout = Self.layout(count: shown.count, aspect: aspect, in: area, spacing: spacing, caption: captionHeight)
        let rows = stride(from: 0, to: shown.count, by: layout.columns).map { Array(shown[$0..<min($0 + layout.columns, shown.count)]) }

        VStack(spacing: spacing) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(rows[row]) { tile in
                        SeriesTileView(tile: tile, source: source, imageSize: layout.image, isFocused: focusedID != nil) {
                            focusedID = focusedID == nil ? tile.id : nil
                        }
                    }
                }
            }
        }
    }

    /// Spaltenzahl, bei der die Bilder im verfügbaren Platz am größten werden.
    static func layout(count: Int, aspect: Double, in area: CGSize, spacing: CGFloat, caption: CGFloat) -> (columns: Int, image: CGSize) {
        func size(columns: Int) -> (cell: CGSize, image: CGSize) {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let cellWidth = (area.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (area.height - spacing * CGFloat(rows - 1)) / CGFloat(rows) - caption
            let width = max(min(cellWidth, cellHeight * aspect), 1)
            return (CGSize(width: cellWidth, height: cellHeight), CGSize(width: width, height: max(width / aspect, 1)))
        }
        var best: (columns: Int, image: CGSize)?
        for columns in 1...max(count, 1) {
            let (cell, image) = size(columns: columns)
            guard cell.width > 20, cell.height > 20 else { continue }
            if best == nil || image.width * image.height > best!.image.width * best!.image.height { best = (columns, image) }
        }
        // Passt nichts mit Zellen über 20 pt, lieber ein quadratisches Raster als alles auf 1 × 1.
        if let best { return best }
        let columns = Int(ceil(Double(max(count, 1)).squareRoot()))
        return (columns, size(columns: columns).image)
    }
}

// MARK: - Kachel

private struct SeriesTileView: View {
    @Environment(Studio.self) private var studio
    let tile: SeriesTile
    let source: SeriesSource
    let imageSize: CGSize
    let isFocused: Bool
    let onTap: () -> Void

    @State private var isHovering = false
    @State private var showPrompt = false

    private var item: SeriesItem? { tile.item }
    private var isDone: Bool { item?.phase == .done }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                picture
                status
            }
            .frame(width: imageSize.width, height: imageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .overlay {
                if item?.phase == .rendering {
                    GlowBorder(cornerRadius: 8, lineWidth: 3)
                        .padding(-3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isHovering, let item, isDone {
                    actions(for: item)
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .help(isFocused ? "Klicken für das Raster" : "Klicken zum Vergrößern")
            .popover(isPresented: $showPrompt, arrowEdge: .trailing) {
                if let item { SeriesPromptPopover(item: item, isPresented: $showPrompt) }
            }

            caption
                .frame(width: imageSize.width, height: 22)
        }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .contextMenu { menu }
        .onDrag {
            if let url = item?.fileURL { return NSItemProvider(object: url as NSURL) }
            if let image = item?.image { return NSItemProvider(object: NSImage(cgImage: image, size: .zero)) }
            return NSItemProvider()
        }
    }

    // MARK: Bild

    @ViewBuilder
    private var picture: some View {
        switch tile.kind {
        case .source:
            Image(decorative: source.image, scale: 1).resizable()
        case .item(let item):
            if let image = item.image {
                Image(decorative: image, scale: 1).resizable()
                    .overlay { if item.phase != .done { Rectangle().fill(.black.opacity(0.45)) } }
            } else {
                dimmedSource
            }
        case .preview:
            dimmedSource
        }
    }

    /// Ausgangsbild abgedunkelt, solange die Variante noch nicht da ist.
    private var dimmedSource: some View {
        Image(decorative: source.thumbnail, scale: 1)
            .resizable()
            .saturation(0.35)
            .overlay(Rectangle().fill(.black.opacity(0.5)))
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        switch tile.kind {
        case .source:
            EmptyView()
        case .preview(_, let value):
            statusBox {
                Label(value.isEmpty ? "Variante eintragen" : value, systemImage: studio.seriesSetup.variable.symbol)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
            }
        case .item(let item):
            switch item.phase {
            case .done:
                EmptyView()
            case .waiting:
                statusBox { Label("Wartet", systemImage: "clock").font(.callout.weight(.medium)) }
            case .writing:
                statusBox {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(GemmaStyle.gradient)
                                .symbolEffect(.pulse)
                            Text("Gemma schreibt den Prompt …")
                        }
                        .font(.callout.weight(.medium))
                        if !item.prompt.isEmpty {
                            Text(item.prompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .truncationMode(.head)
                        }
                    }
                }
            case .queued:
                statusBox {
                    VStack(spacing: 4) {
                        Label("Prompt fertig", systemImage: "checkmark.circle")
                            .font(.callout.weight(.medium))
                        Text("wartet auf Draw Things")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .rendering:
                if let generation = studio.generation {
                    statusBox { RenderProgress(generation: generation) }
                }
            case .failed(let message):
                statusBox {
                    VStack(spacing: 8) {
                        Label("Fehlgeschlagen", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                        Button("Erneut versuchen", systemImage: "arrow.clockwise") { studio.rerenderSeriesItem(item.id) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .disabled(studio.isBusy)
                    }
                }
            case .cancelled:
                statusBox {
                    VStack(spacing: 8) {
                        Label("Abgebrochen", systemImage: "stop.circle")
                            .font(.callout.weight(.medium))
                        Button("Jetzt rendern", systemImage: "play.fill") { studio.rerenderSeriesItem(item.id) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .disabled(studio.isBusy)
                    }
                }
            }
        }
    }

    private func statusBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: min(max(imageSize.width - 24, 120), 280))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Beschriftung

    private var caption: some View {
        HStack(spacing: 8) {
            switch tile.kind {
            case .source:
                Label("Ausgangsbild", systemImage: "photo")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 0)
            case .preview(let number, let value):
                NumberBadge(number: number)
                Text(value.isEmpty ? "Variante \(number)" : value)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            case .item(let item):
                NumberBadge(number: item.number)
                Text(item.value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .help(item.value)
                if item.usesTemplate {
                    Text("Vorlage")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(.orange)
                        .help("Gemma war nicht erreichbar – der Prompt stammt aus einer einfachen Vorlage.")
                }
                Spacer(minLength: 0)
                if let duration = item.duration, item.phase == .done {
                    Text(Format.duration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if !item.prompt.isEmpty, item.phase != .writing {
                    Button {
                        showPrompt = true
                    } label: {
                        Image(systemName: "text.quote")
                    }
                    .buttonStyle(.borderless)
                    .help("Prompt ansehen und ändern")
                }
            }
        }
    }

    // MARK: Aktionen

    private func actions(for item: SeriesItem) -> some View {
        HStack(spacing: 6) {
            Button {
                studio.openSeriesItemForEditing(item)
            } label: {
                Image(systemName: "paintbrush.pointed")
            }
            .help("In „Bearbeiten“ öffnen")
            .disabled(item.versionID == nil)
            Button {
                studio.rerenderSeriesItem(item.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Neu rendern (neuer Seed)")
            .disabled(studio.isBusy)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    @ViewBuilder
    private var menu: some View {
        Button(isFocused ? "Zurück zum Raster" : "Vergrößern", systemImage: isFocused ? "square.grid.2x2" : "arrow.up.left.and.arrow.down.right", action: onTap)
        if let item {
            if isDone {
                Button("In „Bearbeiten“ öffnen", systemImage: "paintbrush.pointed") { studio.openSeriesItemForEditing(item) }
                    .disabled(item.versionID == nil)
                Button("Als neues Ausgangsbild verwenden", systemImage: "arrow.uturn.backward.square") { studio.useSeriesItemAsSource(item) }
            }
            Divider()
            Button("Neu rendern", systemImage: "arrow.clockwise") { studio.rerenderSeriesItem(item.id) }
                .disabled(studio.isBusy || item.prompt.isEmpty)
            Button("Prompt neu schreiben und rendern", systemImage: "wand.and.sparkles") { studio.rerenderSeriesItem(item.id, rewrite: true) }
                .disabled(studio.isBusy)
            Button("Prompt ansehen und ändern …", systemImage: "text.quote") { showPrompt = true }
                .disabled(item.prompt.isEmpty || item.phase == .writing)
            if isDone {
                Divider()
                Button("Exportieren …", systemImage: "square.and.arrow.up") {
                    if let version = studio.versions.first(where: { $0.id == item.versionID }) { studio.exportWithPanel(version) }
                }
                .disabled(!studio.versions.contains { $0.id == item.versionID })
                Button("Im Finder zeigen", systemImage: "folder") {
                    if let url = item.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .disabled(item.fileURL == nil)
                OpenInAppButton(urls: item.fileURL.map { [$0] } ?? [])
            }
        }
    }
}

struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.accentColor))
    }
}

/// Fortschritt des Bildes, das Draw Things gerade rendert (geschätzt, siehe GenerationProgress).
private struct RenderProgress: View {
    let generation: GenerationProgress

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let fraction = generation.fraction(at: context.date)
            let remaining = generation.remaining(at: context.date)
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(generation.loadingModel.map { "Lädt \($0) …" } ?? "Draw Things rendert …")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(Int((fraction * 100).rounded())) %")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                GradientProgressBar(fraction: fraction, height: 6)
                Text(remaining > 1 ? "noch ca. \(Format.duration(remaining))" : "gleich fertig …")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Prompt eines Bildes ansehen, ändern und damit neu rendern.
private struct SeriesPromptPopover: View {
    @Environment(Studio.self) private var studio
    let item: SeriesItem
    @Binding var isPresented: Bool
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NumberBadge(number: item.number)
                Text(item.value)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let seed = item.seed {
                    Text("Seed \(seed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            TextEditor(text: $draft)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 170)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.75)))
            if item.usesTemplate {
                Label("Gemma war nicht erreichbar – das ist ein einfacher Vorlagen-Prompt.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Kopieren", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft, forType: .string)
                }
                Button("Gemma neu schreiben lassen", systemImage: "wand.and.sparkles") {
                    studio.rerenderSeriesItem(item.id, rewrite: true)
                    isPresented = false
                }
                .disabled(studio.isBusy)
                Spacer()
                Button("Neu rendern") {
                    studio.rerenderSeriesItem(item.id, prompt: draft)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(studio.isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(studio.isBusy ? "Warte, bis die Serie fertig ist." : "Mit diesem Prompt und neuem Seed rendern")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 420)
        .onAppear { draft = item.prompt }
    }
}

// MARK: - Leiste

/// Schwebende Leiste unter dem Raster: Fortschritt, Ausgangsbild, Größe, Ablage.
private struct SeriesBar: View {
    @Environment(Studio.self) private var studio
    let tiles: [SeriesTile]
    @Binding var focusedID: String?
    @Binding var showSource: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if focusedID != nil {
                    focusControls
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                }

                statusControls
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)

                HStack(spacing: 12) {
                    Button {
                        if showSource && focusedID == "source" { focusedID = nil }
                        showSource.toggle()
                    } label: {
                        Label("Ausgangsbild", systemImage: showSource ? "photo.fill" : "photo")
                            .foregroundStyle(showSource ? Color.accentColor : Color.primary)
                    }
                    .help(showSource ? "Ausgangsbild aus dem Raster nehmen" : "Ausgangsbild zum Vergleich ins Raster stellen")
                    divider
                    SizeTierMenu()
                    if let size = studio.seriesRun?.size ?? studio.targetSize(for: .series) {
                        Text("\(Format.size(size)) px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .help("So groß rendert Draw Things jedes Bild der Serie")
                    }
                    divider
                    Button {
                        studio.openLibraryFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Bibliothek im Finder öffnen – dort liegen alle Bilder der Serie")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .font(.callout)
    }

    private var divider: some View {
        Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 16)
    }

    private var focusControls: some View {
        let index = tiles.firstIndex { $0.id == focusedID } ?? 0
        return HStack(spacing: 8) {
            Button {
                focusedID = nil
            } label: {
                Label("Raster", systemImage: "square.grid.2x2")
            }
            .keyboardShortcut(.cancelAction)
            .help("Zurück zum Raster (Esc)")
            divider
            Button { focusedID = tiles[max(index - 1, 0)].id } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
            Text("\(index + 1) / \(tiles.count)")
                .monospacedDigit()
            Button { focusedID = tiles[min(index + 1, tiles.count - 1)].id } label: { Image(systemName: "chevron.right") }
                .disabled(index >= tiles.count - 1)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var statusControls: some View {
        let setup = studio.seriesSetup
        HStack(spacing: 10) {
            if let run = studio.seriesRun {
                Label(run.variableName, systemImage: run.variable.symbol)
                    .fontWeight(.medium)
                divider
                if run.isRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 10) {
                            Text(runningLabel(run))
                                .monospacedDigit()
                            GradientProgressBar(fraction: overallFraction(run, at: context.date), height: 5)
                                .frame(width: 110)
                            if let remaining = studio.seriesRemaining(at: context.date), remaining > 1 {
                                Text("noch ca. \(Format.duration(remaining))")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } else {
                    Text("\(run.doneCount) von \(run.items.count) fertig")
                        .monospacedDigit()
                    if run.hasUnfinished {
                        Button("Rest rendern", systemImage: "play.fill") { studio.resumeSeries() }
                            .buttonStyle(.borderless)
                            .disabled(studio.isBusy)
                    }
                    Button {
                        focusedID = nil
                        studio.clearSeriesRun()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Raster leeren – die Bilder bleiben im Verlauf und in der Bibliothek")
                }
            } else {
                Label(setup.variableName, systemImage: setup.variable.symbol)
                    .fontWeight(.medium)
                divider
                if let blocker = studio.seriesBlocker {
                    Text(blocker)
                        .foregroundStyle(.secondary)
                } else {
                    Text(setup.filledValues.count == 1 ? "1 Bild · ⌘↩ startet" : "\(setup.filledValues.count) Bilder · ⌘↩ startet")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func runningLabel(_ run: SeriesRun) -> String {
        if run.items.contains(where: { $0.phase == .writing }) { return "Gemma schreibt die Prompts" }
        let rendering = run.items.first { $0.phase == .rendering }
        return rendering.map { "Bild \($0.number) von \(run.items.count)" } ?? "\(run.doneCount) von \(run.items.count) fertig"
    }

    private func overallFraction(_ run: SeriesRun, at date: Date) -> Double {
        let current = run.items.contains { $0.phase == .rendering } ? studio.generation?.fraction(at: date) ?? 0 : 0
        return (Double(run.doneCount) + current) / Double(max(run.items.count, 1))
    }
}

// MARK: - Leer

/// Solange es kein Ausgangsbild gibt.
private struct SeriesEmptyState: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(GemmaStyle.gradient)
                        .frame(width: 74, height: 74)
                        .shadow(color: GemmaStyle.tint.opacity(0.45), radius: 18, y: 6)
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                }
                Text("Bilderserie")
                    .font(.system(size: 30, weight: .bold))
                Text("Aus einem Ausgangsbild entstehen bis zu vier Varianten –\nz. B. dieselbe Person in vier verschiedenen Outfits.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                if let current = studio.current {
                    Button("Aktuelles Bild verwenden", systemImage: "photo") { studio.setSeriesSource(current) }
                }
                Button("Bild öffnen …", systemImage: "photo.badge.plus") { studio.importWithPanel() }
                Button("Aus Zwischenablage", systemImage: "doc.on.clipboard") { studio.pasteImage() }
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Text("Oder ein Bild einfach hierher ziehen")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}
