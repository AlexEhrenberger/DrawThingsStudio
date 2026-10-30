import SwiftUI
import UniformTypeIdentifiers

/// Die große Arbeitsfläche in der Mitte.
struct CanvasView: View {
    @Environment(Studio.self) private var studio
    @State private var isDropTargeted = false
    @State private var lastDrag: CGSize = .zero

    private var hasDocument: Bool { studio.aspect != nil || !studio.versions.isEmpty }

    var body: some View {
        Group {
            if studio.mode == .series {
                SeriesCanvas()
            } else {
                imageCanvas
            }
        }
        .overlay(alignment: .top) {
            if let generation = studio.generation {
                CanvasProgressStrip(generation: generation)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let message = studio.errorMessage {
                    ErrorBanner(message: message)
                }
                ModelMismatchHint()
                if let notice = studio.modelNotice {
                    ModelNotice(text: notice)
                }
                WorkingTodoBanner()
                IdentityAssistBanner()
            }
            .padding(.top, 14)
            .animation(.smooth, value: studio.errorMessage)
            .animation(.smooth, value: studio.modelNotice)
            .animation(.smooth, value: studio.identityAssist)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(10)
                    .overlay {
                        Label(studio.mode == .series ? "Als Ausgangsbild der Serie" : "Bild öffnen", systemImage: "photo.badge.plus")
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            Task {
                // Im Modus „Serien“ wird das Bild zugleich zum Ausgangsbild (siehe importImage).
                if let image = await DropLoader.loadImage(from: providers) {
                    studio.importImage(image)
                }
            }
            return true
        }
    }

    /// Einzelbild mit Zoom, Werkzeugen und Leiste – alle Modi außer „Serien“.
    private var imageCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                CanvasBackdrop()
                    .contentShape(Rectangle())
                    // Klick auf die Leerfläche: zentrieren und einpassen.
                    .onTapGesture { if hasDocument { studio.fitToWindow() } }
                    .gesture(panDrag, including: hasDocument ? .all : .none)
                if hasDocument {
                    stage(in: proxy.size)
                } else {
                    WelcomeView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                // Trackpad: zwei Finger schieben, Pinch zoomt – überall auf der Arbeitsfläche.
                CanvasEventMonitor(
                    isActive: hasDocument,
                    onScroll: { delta, location, zoomModifier in
                        if zoomModifier {
                            studio.zoom(by: exp(delta.height * 0.01), at: location)
                        } else {
                            studio.pan(by: delta)
                        }
                    },
                    onMagnify: { factor, location in studio.zoom(by: factor, at: location) },
                    onSmartMagnify: { location in studio.toggleActualSize(at: location) }
                )
            }
        }
        .clipped()
        .overlay(alignment: .bottom) {
            if hasDocument {
                CanvasBar()
                    .padding(.bottom, 18)
            }
        }
    }

    /// Ziehen mit der Maus verschiebt das Bild (auf der Leerfläche immer, auf dem Bild ohne aktives Werkzeug).
    private var panDrag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                studio.pan(by: CGSize(width: value.translation.width - lastDrag.width, height: value.translation.height - lastDrag.height))
                lastDrag = value.translation
            }
            .onEnded { _ in lastDrag = .zero }
    }

    // MARK: Bühne

    @ViewBuilder
    private func stage(in available: CGSize) -> some View {
        let content = contentSize
        let room = CGSize(width: max(available.width - 120, 100), height: max(available.height - 150, 100))
        let fit = min(room.width / content.width, room.height / content.height)
        let scale = studio.zoom ?? fit
        let display = CGSize(width: content.width * scale, height: content.height * scale)
        let _ = {
            studio.fitScale = fit
            studio.canvasSize = available
            studio.contentPixelSize = content
        }()
        let tool = studio.canvasTool

        ZStack {
            if tool == .compare, let pair = studio.comparisonPair {
                @Bindable var studio = studio
                CompareSplitView(before: pair.before, after: pair.after, size: display, position: $studio.splitPosition)
            } else if let image = studio.displayImage {
                if ImageTools.hasAlpha(image) {
                    Checkerboard()
                }
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(scale > 2.5 ? .none : .high)
                    .frame(width: display.width, height: display.height)
                if studio.inspectorTab == .selection, studio.showSelectionOverlay, let overlay = studio.selectionOverlay {
                    Image(decorative: overlay, scale: 1)
                        .resizable()
                        .frame(width: display.width, height: display.height)
                        .allowsHitTesting(false)
                }
            } else {
                EmptyFrame(size: display)
            }
        }
        .frame(width: display.width, height: display.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .overlay {
            switch tool {
            case .crop: CropOverlay(size: display)
            case .brush, .eraser: BrushOverlay(size: display, erase: tool == .eraser)
            case .pipette: PipetteOverlay(size: display)
            case .none, .compare: EmptyView()
            }
        }
        .overlay {
            // Bilder einer Serie rendern im Raster – nicht über dem Bild auf dem Canvas.
            if let generation = studio.generation, generation.mode != .series {
                GlowBorder(cornerRadius: 6, lineWidth: 3)
                    .padding(-3)
            }
        }
        .overlay {
            if let generation = studio.generation, generation.mode != .series {
                GenerationOverlay(generation: generation, hasImage: studio.displayImage != nil)
            }
        }
        .overlay(alignment: .topLeading) {
            StageBadge()
                .padding(12)
        }
        .offset(studio.canvasPan)
        // Erst nach dem Layout übernehmen – während des Zeichnens darf sich der Zustand nicht ändern.
        .task(id: fit) { if studio.shownFitScale != fit { studio.shownFitScale = fit } }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { studio.toggleActualSize() },
            including: tool == .none ? .all : .subviews
        )
        .gesture(panDrag, including: tool == .none ? .all : .subviews)
    }

    /// Größe des Inhalts in Pixeln: die aktuelle Version (Vorschauen sind evtl. verkleinert) oder das Format.
    private var contentSize: CGSize {
        if studio.isComparing, let base = studio.comparisonBase { return base.size }
        if let current = studio.current { return current.size }
        if let size = studio.targetSize(for: .generate) { return size }
        return CGSize(width: 1024, height: 1024)
    }
}

/// Hinweis oben links auf dem Bild: Vorher-Ansicht, Vorschau, aktive Auswahl.
private struct StageBadge: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if studio.isComparing, studio.comparisonBase != nil {
            badge("Vorher", symbol: nil)
        } else if studio.canvasTool == .compare {
            EmptyView()
        } else if studio.isPickingWhiteBalance {
            badge("Klicke auf eine Stelle, die neutral grau sein soll", symbol: "eyedropper")
        } else if !studio.adjustments.isIdentity {
            badge("Vorschau der Anpassungen", symbol: "slider.horizontal.3")
        } else if studio.hasSelection, studio.mode == .edit, studio.applyEditToSelection, studio.inspectorTab != .selection {
            badge("Qwen-Ergebnis nur in der Auswahl", symbol: "lasso")
        }
    }

    private func badge(_ text: String, symbol: String?) -> some View {
        Group {
            if let symbol { Label(text, systemImage: symbol) } else { Text(text) }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Schachbrett hinter transparenten Bildern.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color(white: 0.78)))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
    }
}

/// Dezentes Punktraster wie in Pixelmator & Co.
struct CanvasBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.6, height: 1.6))
            let color = colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.08)
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .background(colorScheme == .dark ? Color(white: 0.115) : Color(white: 0.9))
        .ignoresSafeArea()
    }
}

/// Leeres Blatt im gewählten Format, bevor das erste Bild da ist.
private struct EmptyFrame: View {
    @Environment(Studio.self) private var studio
    let size: CGSize

    var body: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .textBackgroundColor))
            if !studio.isGenerating {
                VStack(spacing: 10) {
                    Image(systemName: studio.mode == .references ? "photo.stack" : "sparkles")
                        .font(.system(size: min(size.width, size.height) * 0.12, weight: .light))
                        .foregroundStyle(GemmaStyle.gradient)
                    if let aspect = studio.aspect {
                        Text("\(aspect.name) · \(aspect.label)")
                            .font(.headline)
                    }
                    if let pixels = studio.targetSize(for: .generate) {
                        Text("\(Format.size(pixels)) Pixel")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding()
            }
        }
    }

    private var hint: String {
        switch studio.mode {
        case .generate: "Prompt links bauen, dann ⌘↩"
        case .edit: "Zum Bearbeiten ein Bild öffnen oder hierher ziehen"
        case .references: "Referenzbilder rechts hinzufügen, dann ⌘↩"
        case .series: "Ausgangsbild und Varianten rechts festlegen, dann ⌘↩"
        }
    }
}

/// Fortschritt während Draw Things rendert (geschätzt – siehe GenerationProgress).
private struct GenerationOverlay: View {
    @Environment(Studio.self) private var studio
    let generation: GenerationProgress
    let hasImage: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let fraction = generation.fraction(at: context.date)
            let elapsed = context.date.timeIntervalSince(generation.startedAt)
            ZStack {
                if hasImage {
                    Rectangle().fill(.black.opacity(0.25))
                }
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.headline)
                        Spacer(minLength: 16)
                        Text("\(Int((fraction * 100).rounded())) %")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    GradientProgressBar(fraction: fraction, height: 8)
                    HStack {
                        Text(Format.duration(elapsed))
                        Spacer()
                        Text(remainingLabel(at: context.date))
                    }
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    HStack {
                        Text("\(Format.size(generation.size)) · \(generation.mode.modelName)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("Abbrechen", systemImage: "stop.fill") { studio.cancelGeneration() }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
                .frame(width: 300)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .help(generation.isCalibrated
                      ? "Geschätzt aus dem letzten Durchlauf – Draw Things meldet über HTTP keine Schritte."
                      : "Erste Schätzung – wird nach dieser Generierung auf deinen Rechner abgestimmt.")
            }
        }
    }

    private var title: String {
        if let model = generation.loadingModel { return "Lädt \(model) …" }
        return generation.mode == .generate ? "Draw Things rendert …" : "Draw Things bearbeitet …"
    }

    private func remainingLabel(at date: Date) -> String {
        let remaining = generation.remaining(at: date)
        if remaining > 1 { return "noch ca. \(Format.duration(remaining))" }
        return "gleich fertig …"
    }
}

/// Dünner Balken am oberen Rand des Canvas.
private struct CanvasProgressStrip: View {
    let generation: GenerationProgress

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            GradientProgressBar(fraction: generation.fraction(at: context.date), height: 3, showsTrack: false)
        }
        .allowsHitTesting(false)
    }
}

/// Fortschrittsbalken im Gemma-Farbverlauf.
struct GradientProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6
    var showsTrack = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if showsTrack {
                    Capsule().fill(Color.primary.opacity(0.12))
                }
                Capsule()
                    .fill(LinearGradient(colors: GemmaStyle.colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
                    .shadow(color: GemmaStyle.tint.opacity(0.6), radius: height, y: 0)
                    .animation(.linear(duration: 0.2), value: fraction)
            }
        }
        .frame(height: height)
    }
}

struct ErrorBanner: View {
    @Environment(Studio.self) private var studio
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                studio.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: message) {
            try? await Task.sleep(for: .seconds(12))
            if studio.errorMessage == message { studio.errorMessage = nil }
        }
    }
}

/// Kurz eingeblendet nach dem Moduswechsel.
private struct ModelNotice: View {
    @Environment(Studio.self) private var studio
    let text: String

    var body: some View {
        Label(text, systemImage: "cpu")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: text) {
                try? await Task.sleep(for: .seconds(3.5))
                if studio.modelNotice == text {
                    withAnimation(.smooth) { studio.modelNotice = nil }
                }
            }
    }
}

/// Hinweis, wenn in Draw Things gerade ein unpassendes Modell geladen ist.
private struct ModelMismatchHint: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if !studio.settings.switchModelPerMode, let config = studio.dtConfig, !config.model.isEmpty,
           !studio.mode.matches(drawThingsModel: config.model) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                Text("Draw Things hat \(config.modelDisplayName) geladen – für „\(studio.mode.title)“ ist \(studio.mode.modelName) gedacht.")
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

/// Solange ein To-do aus der Galerie umgesetzt wird: woran gerade gearbeitet wird – abhaken oder beenden.
private struct WorkingTodoBanner: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let gallery = studio.gallery
        if let id = gallery.workingTodoID, let todo = gallery.note(id), todo.isOpenTodo {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .foregroundStyle(NoteKind.todo.color)
                Text("To-do: „\(todo.text)“")
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                if !todo.resultIDs.isEmpty {
                    Text(todo.resultIDs.count == 1 ? "· 1 Ergebnis" : "· \(todo.resultIDs.count) Ergebnisse")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Erledigt", systemImage: "checkmark") {
                    withAnimation(.smooth) { gallery.toggleDone(id) }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("To-do abhaken – die Ergebnisse bleiben in der Galerie mit ihm verknüpft")
                Button {
                    withAnimation(.smooth) { gallery.workingTodoID = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Nicht mehr an diesem To-do arbeiten (es bleibt offen)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 620)
            .glassEffect(.regular, in: .capsule)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
