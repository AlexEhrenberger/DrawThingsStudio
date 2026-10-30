import AppKit
import SwiftUI

@main
struct DrawThingsStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var studio = Studio()

    var body: some Scene {
        Window("DrawThings Studio", id: "main") {
            MainView()
                .environment(studio)
                .frame(minWidth: 1180, minHeight: 720)
                .task {
                    studio.startPolling()
                    await studio.syncGallery()
                }
        }
        .defaultSize(width: 1560, height: 960)
        .windowToolbarStyle(.unified)
        .commands { StudioCommands(studio: studio) }

        Window("Bausteine verwalten", id: "catalog-editor") {
            CatalogEditorView()
                .environment(studio)
        }
        .defaultSize(width: 1040, height: 700)

        Settings {
            SettingsView()
                .environment(studio)
        }
    }
}

extension Notification.Name {
    static let openImageFiles = Notification.Name("DrawThingsStudio.openImageFiles")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Dateien aus dem Finder („Öffnen mit“) oder vom Dock-Symbol – werden abgeholt, sobald das Fenster da ist.
    static var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        Self.pendingURLs += urls
        NotificationCenter.default.post(name: .openImageFiles, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Auch beim Start per `swift run` als normale App mit Dock-Symbol auftreten.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        URLSession.removeLegacyDiskCaches()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct StudioCommands: Commands {
    let studio: Studio
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Bausteine verwalten …") { openWindow(id: "catalog-editor") }
                .keyboardShortcut("b", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .newItem) {
            Button("Neues Bild …") { studio.showNewImageSheet = true }
                .keyboardShortcut("n")
            Button("Bild öffnen …") { studio.importWithPanel() }
                .keyboardShortcut("o")
            Button("Bilder & Videos in die Bibliothek importieren …") { studio.importIntoLibraryWithPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!studio.isLibraryAvailable)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Exportieren …") { studio.exportCurrent() }
                .keyboardShortcut("s")
                .disabled(!studio.canExport)
        }
        CommandGroup(after: .saveItem) {
            Divider()
            Menu("Bibliothek") {
                ForEach(studio.libraries) { entry in
                    Button(entry.isAvailable ? "\(entry.name) · \(entry.place)" : "\(entry.name) – nicht verfügbar") {
                        studio.openLibrary(entry.url)
                    }
                    .disabled(!entry.isAvailable || entry.url.standardizedFileURL == Library.root)
                }
                Divider()
                Button("Neue Bibliothek …") { studio.createLibraryWithPanel() }
                Button("Bibliothek öffnen …") { studio.openLibraryWithPanel() }
            }
            Button("Bibliothek im Finder zeigen") { studio.openLibraryFolder() }
                .disabled(!studio.isLibraryAvailable)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Bild kopieren") { studio.copyCurrentImage() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(studio.current == nil)
            Button("Bild aus Zwischenablage einfügen") { studio.pasteImage() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandMenu("Bild") {
            // In Labs schreibt ⌘↩ den Prompt (Gemma) – an Draw Things geht dort nichts.
            Button(studio.showLabs ? "Prompt schreiben" : studio.mode.actionTitle) {
                if studio.showLabs { studio.writeLabPrompt() } else { studio.run() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(studio.showLabs ? studio.composition.blocker != nil : !studio.canRun || studio.showGallery)
            Button("Generierung abbrechen") { studio.cancelGeneration() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!studio.isBusy)
            Divider()
            Button("Prompt mit Gemma optimieren") { studio.optimizePrompt() }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Button("Prompt in Bibliothek sichern") { studio.savePromptToLibrary() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Prompt wiederherstellen") { studio.builder.restoreDraft() }
                .disabled(!studio.builder.canRestoreDraft)
            Divider()
            Button("Galerie") { studio.enterGallery() }
                .keyboardShortcut("g")
            Button(studio.isFocusMode ? "Fokusmodus beenden" : "Fokusmodus") {
                withAnimation(.smooth(duration: 0.3)) { studio.isFocusMode.toggle() }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Button(studio.presentation == nil ? "Story präsentieren" : "Präsentation beenden") {
                if studio.presentation != nil {
                    studio.endPresentation()
                } else if case .story(let id) = studio.gallery.collection {
                    let defaults = UserDefaults.standard
                    let layout = PresentationLayout(rawValue: defaults.integer(forKey: "story.presentLayout")) ?? .single
                    studio.present(id, layout: layout, fullScreen: defaults.object(forKey: "story.presentFullScreen") as? Bool ?? true)
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(studio.presentation == nil && !studio.canPresentStory)
            ForEach(StudioMode.allCases) { mode in
                Button(mode.longTitle) { studio.switchTo(mode) }
                    .keyboardShortcut(KeyEquivalent(mode.shortcutKey))
            }
            Button("Labs") { studio.enterLabs() }
                .keyboardShortcut("5")
            Divider()
            Button("Motiv auswählen") {
                studio.inspectorTab = .selection
                studio.selectSubject(peopleOnly: false)
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(studio.current == nil)
            Button("Auswahl umkehren") { studio.invertSelection() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!studio.hasSelection)
            Button("Auswahl aufheben") { studio.clearSelection() }
                .keyboardShortcut("d")
                .disabled(!studio.hasSelection)
            Button("Zuschneiden …") { studio.inspectorTab = .crop; studio.showInspector = true }
                .keyboardShortcut("k")
                .disabled(studio.current == nil)
            Divider()
            Button(studio.isSplitComparing ? "Vorher/Nachher-Vergleich ausblenden" : "Vorher/Nachher-Vergleich") {
                studio.isSplitComparing.toggle()
            }
            .keyboardShortcut("y")
            .disabled(studio.comparisonPair == nil)
            Button("Vorherige Version") { studio.selectAdjacentVersion(-1) }
                .keyboardShortcut("[")
            Button("Nächste Version") { studio.selectAdjacentVersion(1) }
                .keyboardShortcut("]")
        }
        CommandGroup(after: .toolbar) {
            Button("Vergrößern") {
                if studio.showGallery { studio.gallery.zoomGrid(by: 1.25) } else { studio.zoom(by: 1.25) }
            }
            .keyboardShortcut("+")
            Button("Verkleinern") {
                if studio.showGallery { studio.gallery.zoomGrid(by: 1 / 1.25) } else { studio.zoom(by: 1 / 1.25) }
            }
            .keyboardShortcut("-")
            Button("Originalgröße") { studio.actualSize() }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Einpassen") { studio.fitToWindow() }
                .keyboardShortcut("0")
            Button(studio.gallery.showsDates ? "Datum in der Galerie ausblenden" : "Datum in der Galerie einblenden") {
                studio.gallery.showsDates.toggle()
            }
            .disabled(!studio.showGallery)
            Divider()
            Button(studio.showInspector ? "Werkzeuge ausblenden" : "Werkzeuge einblenden") { studio.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
