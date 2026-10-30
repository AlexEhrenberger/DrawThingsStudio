import AppKit
import SwiftUI

struct MainView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        // Die Arbeitsfläche bleibt im Fokusmodus darunter bestehen – sonst baut SwiftUI die Werkzeugleiste
        // danach nicht wieder auf. Ausgeblendet wird die Leiste über AppKit (siehe `enterFocusFullScreen`).
        ZStack {
            splitView
                .opacity(studio.isFocusMode || studio.presentation != nil ? 0 : 1)
                .allowsHitTesting(!studio.isFocusMode && studio.presentation == nil)
            if studio.isFocusMode {
                FocusModeView()
                    .transition(.opacity)
                    .opacity(studio.presentation == nil ? 1 : 0)
                    .allowsHitTesting(studio.presentation == nil)
            }
            if let presentation = studio.presentation {
                StoryPresentationView(presentation: presentation)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: studio.presentation == nil)
        .background(WindowStyler(
            transparent: studio.settings.interfaceStyle == .glass && !studio.isFocusMode && !studio.showLabs && studio.presentation == nil,
            dark: studio.showLabs || studio.presentation != nil
        ))
        // Dasselbe für SwiftUI – sonst stellt es das Fenster bei der nächsten Gelegenheit wieder hell.
        .preferredColorScheme(studio.showLabs || studio.presentation != nil ? .dark : nil)
        .navigationTitle("DrawThings Studio")
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $studio.showNewImageSheet) {
            NewImageSheet()
        }
        .sheet(item: $studio.libraryDeletion) { entry in
            LibraryDeleteSheet(entry: entry)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openImageFiles)) { _ in openPendingFiles() }
        .task { openPendingFiles() }
    }

    private var splitView: some View {
        @Bindable var studio = studio
        return NavigationSplitView {
            if studio.showGallery {
                GallerySidebar()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 360)
            } else if studio.showLabs {
                LabsSidebar()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
            } else {
                PromptBuilderSidebar()
                    .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 520)
            }
        } detail: {
            Group {
                if studio.showGallery {
                    // Im Fokusmodus zeigt die Galerie ihr Raster dort – hier nur der Hintergrund.
                    if studio.isFocusMode { GalleryBackground() } else { GalleryView() }
                } else if studio.showLabs {
                    LabsView()
                } else {
                    CanvasView()
                }
            }
            // Labs braucht die ganze Breite – der Inspector bleibt dort zu.
            .inspector(isPresented: Binding(
                get: { studio.showInspector && !studio.showLabs },
                set: { if !studio.showLabs { studio.showInspector = $0 } }
            )) {
                Group {
                    if studio.showGallery { GalleryInspector() } else { InspectorView() }
                }
                .inspectorColumnWidth(min: 290, ideal: 320, max: 440)
            }
        }
        .toolbar { toolbar }
    }

    private func openPendingFiles() {
        let urls = AppDelegate.pendingURLs
        AppDelegate.pendingURLs = []
        for url in urls {
            if let image = ImageTools.image(from: url) {
                studio.importImage(image)
            } else {
                studio.errorMessage = "„\(url.lastPathComponent)“ konnte nicht als Bild gelesen werden."
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        // Mit mehreren Bibliotheken: immer sichtbar, in welcher man arbeitet.
        if studio.settings.libraryPaths.count > 1 { parts.append(studio.libraryName) }
        if let presentation = studio.presentation {
            parts += ["Präsentation", studio.gallery.story(presentation.storyID)?.name ?? "Story"]
            return parts.joined(separator: " · ")
        }
        if studio.showGallery {
            let count = studio.gallery.visibleItems.count
            parts += ["Galerie", count == 1 ? "1 Bild" : "\(count) Bilder"]
        } else if studio.showLabs {
            parts += ["Labs", "Bild zusammenbauen"]
        } else {
            parts.append(studio.mode.longTitle)
            if let aspect = studio.aspect { parts.append(aspect.label) }
        }
        // Neue Bilder landen in diesem Projekt.
        if let id = studio.gallery.activeProjectID, let project = studio.gallery.project(id) {
            parts.append("Projekt „\(project.name)“")
        }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var studio = studio

        ToolbarItemGroup(placement: .navigation) {
            Button {
                studio.showNewImageSheet = true
            } label: {
                Label("Neues Bild", systemImage: "plus")
            }
            .help("Neues Bild (⌘N)")
            Button {
                studio.importWithPanel()
            } label: {
                Label("Bild öffnen", systemImage: "photo.badge.plus")
            }
            .help("Bild öffnen (⌘O)")
        }

        ToolbarItem(placement: .principal) {
            ModeSwitcher()
        }

        ToolbarItem(placement: .primaryAction) {
            ConnectionStatusView()
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        // In der Galerie nur, solange noch etwas läuft – dann als „Abbrechen“.
        if !studio.showGallery || studio.isBusy {
            ToolbarItem(placement: .primaryAction) {
                RunButton()
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        if studio.showGallery {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { studio.isFocusMode = true }
                } label: {
                    Label("Fokusmodus", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fokusmodus – Vollbild, schwarz, nur die Bilder (F)")
            }
        }

        // Labs exportiert nichts und hat keinen Inspector.
        if !studio.showLabs {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    studio.exportCurrent()
                } label: {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }
                .disabled(!studio.canExport)
                .help("Exportieren (⌘S)")
                Button {
                    studio.showInspector.toggle()
                } label: {
                    Label("Werkzeuge", systemImage: "sidebar.trailing")
                }
                .help("Werkzeuge ein-/ausblenden (⌥⌘I)")
            }
        }

        if studio.showGallery {
            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                ToolbarSearchField(text: $studio.gallery.searchText, prompt: "Prompts durchsuchen")
                    .frame(width: 220)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

/// Suchfeld der Galerie in der Werkzeugleiste.
///
/// Bewusst kein `.searchable`: SwiftUI setzt dessen Feld unter der festen Kennung `com.apple.SwiftUI.search`
/// in die Leiste und fügt es beim Wechsel Studio → Galerie gelegentlich ein zweites Mal ein – AppKit bricht
/// dann mit „already contains an item with the identifier com.apple.SwiftUI.search“ ab (Absturz).
/// Ein gewöhnliches Werkzeugleisten-Element bekommt bei jedem Erscheinen eine neue Kennung.
private struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.stringValue = text
        // Bei jedem Tastendruck filtern – wie bisher.
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        field.placeholderString = prompt
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        /// Tippen, Löschknopf und Esc.
        @objc func searchChanged(_ field: NSSearchField) {
            if text.wrappedValue != field.stringValue { text.wrappedValue = field.stringValue }
        }
    }
}

/// Umschalter Galerie · Generieren · Bearbeiten · Referenzen · Serien · Labs – nur Symbole
/// (der Name steht im Tooltip), mit gleitender Markierung.
private struct ModeSwitcher: View {
    @Environment(Studio.self) private var studio
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            segment("Galerie", symbol: "photo.on.rectangle.angled", isOn: studio.showGallery, help: "Galerie – alle Bilder, Serien als Stapel (⌘G) · leert Prompt und Bausteine") {
                studio.enterGallery()
            }
            divider
            ForEach(StudioMode.allCases) { mode in
                segment(mode.title, symbol: mode.symbol, isOn: !studio.showGallery && !studio.showLabs && studio.mode == mode,
                        help: "\(mode.longTitle) (⌘\(String(mode.shortcutKey))) · \(mode.modelName)") {
                    studio.switchTo(mode)
                }
            }
            divider
            segment("Labs", symbol: "flask", isOn: studio.showLabs, help: "Labs – Experimente mit Qwen Image Edit 2511, Prompts für Draw Things (⌘5)") {
                studio.enterLabs()
            }
        }
        .padding(3)
    }

    private var divider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.35))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func segment(_ title: String, symbol: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.28)) { action() }
        } label: {
            Image(systemName: symbol)
                .symbolVariant(isOn ? .fill : .none)
                .font(.system(size: 15, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 38, height: 26)
                .background {
                    if isOn {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
    }
}

/// Großer Knopf oben rechts: Generieren / Anwenden / Komponieren / Serie starten – oder Abbrechen.
private struct RunButton: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if studio.showLabs {
            labsButton
        } else {
            runButton
        }
    }

    /// In Labs schreibt Gemma nur den Prompt – an Draw Things geht nichts.
    private var labsButton: some View {
        let isWriting = studio.composition.isWriting
        return Button {
            if isWriting { studio.cancelLabPrompt() } else { studio.writeLabPrompt() }
        } label: {
            Label(isWriting ? "Abbrechen" : "Prompt schreiben", systemImage: isWriting ? "stop.fill" : "sparkles")
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 4)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glassProminent)
        .tint(isWriting ? Color.red : GemmaStyle.tint)
        .disabled(!isWriting && studio.composition.blocker != nil)
        .help(studio.composition.blocker ?? "Gemma schreibt den Prompt für Draw Things (⌘↩)")
    }

    private var runButton: some View {
        Button {
            if studio.isBusy { studio.cancelGeneration() } else { studio.run() }
        } label: {
            Label(
                studio.isBusy ? "Abbrechen" : studio.mode.actionTitle,
                systemImage: studio.isBusy ? "stop.fill" : studio.mode.actionSymbol
            )
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 4)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glassProminent)
        .tint(studio.isBusy ? Color.red : Color.accentColor)
        .disabled(!studio.isBusy && !studio.canRun)
        .help(studio.runBlocker ?? "\(studio.mode.actionTitle) mit \(studio.mode.modelName) (⌘↩)")
    }
}

/// Zwei kleine Statusanzeigen: Gemma (LM Studio) und Draw Things.
private struct ConnectionStatusView: View {
    @Environment(Studio.self) private var studio
    @State private var showLM = false
    @State private var showDT = false

    var body: some View {
        HStack(spacing: 2) {
            Button {
                showLM.toggle()
            } label: {
                StatusIcon(symbol: "brain", color: lmColor, pulsing: studio.lmBusy > 0 || studio.lmStatus == .loading)
            }
            .help("Gemma (LM Studio): \(studio.lmStatus.title)")
            .accessibilityLabel("Gemma")
            .popover(isPresented: $showLM, arrowEdge: .bottom) { LMStatusPopover() }

            Button {
                showDT.toggle()
            } label: {
                StatusIcon(symbol: "paintpalette", color: dtColor, pulsing: studio.isGenerating)
            }
            .help(dtHelp)
            .accessibilityLabel("Draw Things")
            .popover(isPresented: $showDT, arrowEdge: .bottom) { DTStatusPopover() }
        }
    }

    private var lmColor: Color {
        if studio.lmBusy > 0 { return GemmaStyle.tint }
        switch studio.lmStatus {
        case .ready: return .green
        case .notLoaded, .loading: return .yellow
        case .modelMissing: return .orange
        case .offline: return .red
        case .unknown: return .gray
        }
    }

    private var dtColor: Color {
        if studio.isGenerating { return .blue }
        switch studio.dtReachable {
        case true?:
            // Labs arbeitet mit Qwen Image Edit 2511 – wie „Bearbeiten“.
            let mode = studio.showLabs ? StudioMode.edit : studio.mode
            if let model = studio.dtConfig?.model, !studio.settings.switchModelPerMode, !mode.matches(drawThingsModel: model) {
                return .orange
            }
            return .green
        case false?: return .red
        case nil: return .gray
        }
    }

    private var dtHelp: String {
        if studio.isGenerating { return "Draw Things rendert" }
        if studio.dtReachable == false { return "Draw Things nicht erreichbar" }
        let model = studio.settings.switchModelPerMode ? studio.settings.modelFile(for: studio.mode) : (studio.activeModel ?? "")
        return model.isEmpty ? "Draw Things verbunden" : "Draw Things: \(DrawThingsConfig.displayName(for: model))"
    }
}

/// Symbol mit Statuspunkt oben rechts – grün bereit, gelb lädt bei Bedarf, rot nicht erreichbar.
private struct StatusIcon: View {
    let symbol: String
    let color: Color
    var pulsing = false

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 15))
            .frame(width: 30, height: 24)
            .overlay(alignment: .topTrailing) {
                StatusDot(color: color, pulsing: pulsing)
                    .scaleEffect(0.85)
                    .offset(x: 1, y: 0)
            }
    }
}

private struct LMStatusPopover: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Gemma in LM Studio", systemImage: "brain")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow { Text("Status").foregroundStyle(.secondary); Text(studio.lmStatus.title) }
                GridRow { Text("Modell").foregroundStyle(.secondary); Text(studio.settings.lmModel).textSelection(.enabled) }
                GridRow { Text("Adresse").foregroundStyle(.secondary); Text(studio.settings.lmStudioURL) }
            }
            .font(.callout)
            Text("Gemma optimiert Prompts für Qwen Image 1.0 und Qwen Image Edit 2511 und analysiert Bilder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SettingsLink { Text("Einstellungen …") }
                Spacer()
                Button("Erneut prüfen") { Task { await studio.refreshLM() } }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct DTStatusPopover: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Draw Things", systemImage: "paintpalette")
                .font(.headline)
            if studio.dtReachable == false {
                Text("Nicht erreichbar. In Draw Things unter Einstellungen › API-Server den HTTP-Server (Port 7860) einschalten.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let config = studio.dtConfig {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow { Text("Modell").foregroundStyle(.secondary); Text(DrawThingsConfig.displayName(for: studio.activeModel ?? config.model)) }
                    GridRow { Text("Datei").foregroundStyle(.secondary); Text(studio.activeModel ?? config.model).font(.caption).textSelection(.enabled) }
                    GridRow { Text("Eingestellt").foregroundStyle(.secondary); Text("\(config.width) × \(config.height)").monospacedDigit() }
                    if let steps = config.steps {
                        GridRow { Text("Schritte").foregroundStyle(.secondary); Text("\(steps)") }
                    }
                }
                .font(.callout)
                if studio.settings.switchModelPerMode {
                    let target = studio.settings.modelFile(for: studio.mode)
                    Label(
                        target == studio.activeModel
                            ? "„\(studio.mode.title)“ nutzt \(DrawThingsConfig.displayName(for: target)) – aktiv."
                            : "„\(studio.mode.title)“ nutzt \(DrawThingsConfig.displayName(for: target)) – Draw Things lädt es beim nächsten Durchlauf.",
                        systemImage: "cpu"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else if !studio.mode.matches(drawThingsModel: config.model) {
                    Label("Für „\(studio.mode.title)“ ist \(studio.mode.modelName) gedacht.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text(studio.settings.switchModelPerMode
                 ? "Gesendet werden Prompt, Bildgröße und das Modell des Modus. Sampler, Schritte und LoRAs bleiben, wie sie in Draw Things eingestellt sind."
                 : "Gesendet werden nur Prompt und Bildgröße. Modell, Sampler, Schritte und LoRAs bleiben, wie sie in Draw Things eingestellt sind.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SettingsLink { Text("Einstellungen …") }
                Spacer()
                Button("Erneut prüfen") { Task { await studio.refreshDrawThings() } }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 340)
    }
}
