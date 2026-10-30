import SwiftUI

/// Fokusmodus der Galerie: Vollbild, schwarzer Hintergrund, nur die Bilder.
/// Pinch zoomt das Raster, Doppelklick zeigt ein Bild ganz ohne Leisten, Rechtsklick bietet alle Aktionen.
/// Oben links blenden zwei kleine Knöpfe die Seitenleiste (Projekte, Stories, Charaktere, Assets) und die Info ein;
/// die Knöpfe verschwinden, solange die Maus ruht.
struct FocusModeView: View {
    @Environment(Studio.self) private var studio
    @AppStorage("focus.showSidebar") private var showSidebar = false
    @AppStorage("focus.showInfo") private var showInfo = false
    @State private var chromeVisible = true
    @State private var showHint = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        let gallery = studio.gallery
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                if showSidebar {
                    GallerySidebar(footerBackground: Color(white: 0.08))
                        .frame(width: 260)
                        .background(Color(white: 0.08))
                        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showInfo {
                    GalleryInspector()
                        .frame(width: 320)
                        .background(Color(white: 0.08))
                        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .overlay(alignment: .topLeading) {
            controls
                .padding(.leading, showSidebar ? 274 : 16)
                .padding(.top, 14)
                .opacity(chromeVisible || showSidebar || showInfo ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: chromeVisible)
        }
        .overlay(alignment: .bottom) {
            if showHint, gallery.viewer == nil {
                Text("Pinch zoomt · Doppelklick zeigt ein Bild groß · Rechtsklick für Aktionen · Tab Seitenleiste · I Info · Esc beendet")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect(.clear, in: .capsule)
                    .padding(.bottom, 22)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let message = studio.errorMessage {
                ErrorBanner(message: message)
                    .padding(.top, 14)
            }
        }
        .environment(\.colorScheme, .dark)
        .onContinuousHover { phase in
            if case .active = phase { revealChrome() }
        }
        .onAppear(perform: revealChrome)
        .task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.6)) { showHint = false }
        }
        .animation(.smooth(duration: 0.28), value: showSidebar)
        .animation(.smooth(duration: 0.28), value: showInfo)
        .confirmationDialog(
            trashTitle,
            isPresented: Binding(get: { gallery.trashRequest != nil }, set: { if !$0 { gallery.trashRequest = nil } }),
            titleVisibility: .visible
        ) {
            Button("In den Papierkorb legen", role: .destructive) {
                if let ids = gallery.trashRequest { studio.moveToTrash(ids) }
                gallery.trashRequest = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let gallery = studio.gallery
        let entries = gallery.entries
        if !studio.isLibraryAvailable {
            LibraryUnavailableView()
        } else if let viewer = gallery.viewer {
            GalleryViewer(state: viewer, entries: entries, isFocus: true)
                .transition(.opacity)
        } else if gallery.collection == .notes {
            GalleryNotesView()
        } else if case .persona(let id) = gallery.collection {
            CharacterScreen(personaID: id, entries: entries, isFocus: true)
        } else if case .assets(let categoryID) = gallery.collection {
            AssetBrowser(scope: categoryID.map { .category($0) } ?? .all)
        } else if case .assetSection(let sectionID) = gallery.collection {
            AssetBrowser(scope: .section(sectionID))
        } else if case .story(let id) = gallery.collection {
            StoryPage(storyID: id)
        } else if entries.isEmpty {
            ContentUnavailableView("Keine Bilder", systemImage: gallery.collection.symbol,
                                   description: Text("In „\(gallery.title(for: gallery.collection))“ ist nichts zu sehen."))
        } else {
            GalleryGrid(entries: entries, isFocus: true)
                .transition(.opacity)
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                chromeButton("sidebar.left", isOn: showSidebar, label: "Seitenleiste",
                             help: showSidebar ? "Seitenleiste ausblenden (Tab)" : "Seitenleiste einblenden – Projekte, Stories, Charaktere, Assets (Tab)") {
                    showSidebar.toggle()
                }
                chromeButton("info.circle", isOn: showInfo, label: "Info", help: showInfo ? "Info ausblenden (I)" : "Info einblenden – Bewertung, Notizen, Prompt (I)") {
                    showInfo.toggle()
                }
                chromeButton("arrow.down.right.and.arrow.up.left", isOn: false, label: "Fokusmodus beenden", help: "Fokusmodus beenden (Esc)") {
                    withAnimation(.smooth(duration: 0.3)) { studio.isFocusMode = false }
                }
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.clear, in: .capsule)
            }
        }
    }

    private var title: String {
        let gallery = studio.gallery
        var parts = [gallery.title(for: gallery.collection)]
        if gallery.filter.activeCount > 0 { parts.append("gefiltert") }
        return parts.joined(separator: " · ")
    }

    private func chromeButton(_ symbol: String, isOn: Bool, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : .white)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .circle)
        .help(help)
        .accessibilityLabel(label)
    }

    /// Knöpfe zeigen und nach 2,5 s Ruhe wieder ausblenden.
    private func revealChrome() {
        if !chromeVisible { chromeVisible = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            chromeVisible = false
        }
    }

    private var trashTitle: String {
        let count = studio.gallery.trashRequest?.count ?? 0
        return count == 1 ? "Bild in den Papierkorb legen?" : "\(count) Bilder in den Papierkorb legen?"
    }
}

extension Studio {
    /// Fokusmodus ein: Fenster in den Vollbildmodus (falls es das noch nicht ist).
    func enterFocusFullScreen() {
        // Werkzeugleiste ganz weg – auch der Knopf der Seitenleiste, der sonst als helles Feld stehen bliebe.
        studioWindow?.toolbar?.isVisible = false
        guard let window = studioWindow, !window.styleMask.contains(.fullScreen) else {
            focusEnteredFullScreen = false
            return
        }
        focusEnteredFullScreen = true
        window.toggleFullScreen(nil)
    }

    /// Fokusmodus aus: Vollbild nur verlassen, wenn der Fokusmodus es eingeschaltet hat.
    func leaveFocusFullScreen() {
        studioWindow?.toolbar?.isVisible = true
        guard focusEnteredFullScreen else { return }
        focusEnteredFullScreen = false
        if let window = studioWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    /// Verlässt das Fenster das Vollbild auf anderem Weg (Esc, grüner Knopf, ⌃⌘F), endet auch der Fokusmodus –
    /// sonst bliebe er schwarz im normalen Fenster stehen.
    func observeFullScreenExit() {
        volumeObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Eine Präsentation, die das Vollbild selbst eingeschaltet hat, läuft im Fenster weiter (Esc beendet sie).
                if self.presentation != nil, self.presentationEnteredFullScreen {
                    self.presentationEnteredFullScreen = false
                    self.presentation?.isFullScreen = false
                    return
                }
                guard self.isFocusMode, self.focusEnteredFullScreen else { return }
                self.focusEnteredFullScreen = false
                withAnimation(.smooth(duration: 0.3)) { self.isFocusMode = false }
            }
        })
    }

    /// Hauptfenster – auch wenn gerade ein anderes Fenster (Einstellungen) vorne ist.
    var studioWindow: NSWindow? {
        let candidates = [NSApp.keyWindow, NSApp.mainWindow] + NSApp.windows.map(Optional.some)
        return candidates.compactMap { $0 }.first { $0.isVisible && $0.canBecomeMain && $0.identifier?.rawValue.hasPrefix("main") == true }
            ?? NSApp.mainWindow ?? NSApp.keyWindow
    }
}
