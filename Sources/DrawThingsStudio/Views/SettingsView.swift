import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Verbindungen", systemImage: "network") { ConnectionSettings() }
            Tab("Generierung", systemImage: "sparkles") { GenerationSettings() }
            Tab("Bausteine", systemImage: "square.grid.2x2") { CatalogSettings() }
            Tab("Bibliotheken", systemImage: "books.vertical") { StorageSettings() }
            Tab("Darstellung", systemImage: "circle.lefthalf.filled") { AppearanceSettings() }
        }
        .frame(width: 580, height: 500)
    }
}

private struct ConnectionSettings: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var settings = studio.settings
        Form {
            Section {
                TextField("Adresse", text: $settings.lmStudioURL)
                if studio.lmModels.isEmpty {
                    TextField("Modell", text: $settings.lmModel)
                } else {
                    Picker("Modell", selection: $settings.lmModel) {
                        ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
                    }
                }
                LabeledContent("Status") {
                    HStack {
                        Text(studio.lmStatus.title)
                        Button("Prüfen") {
                            Task {
                                studio.lmModels = await studio.lm.availableModels()
                                await studio.refreshLM()
                            }
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("LM Studio (Gemma)")
            } footer: {
                Text("Das Modell braucht Bildverständnis (Vision) für Analyse und Bearbeiten.")
            }

            Section {
                TextField("Adresse", text: $settings.drawThingsURL)
                LabeledContent("Status") {
                    HStack {
                        Text(studio.dtReachable == true ? "Verbunden – \(studio.dtConfig?.modelDisplayName ?? "")" : studio.dtReachable == false ? "Nicht erreichbar" : "…")
                        Button("Prüfen") { Task { await studio.refreshDrawThings() } }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Draw Things")
            } footer: {
                Text("In Draw Things: Einstellungen › API-Server › Protokoll HTTP, Port 7860.")
            }
        }
        .formStyle(.grouped)
    }

    private var modelChoices: [String] {
        studio.lmModels.contains(studio.settings.lmModel) ? studio.lmModels : [studio.settings.lmModel] + studio.lmModels
    }
}

private struct GenerationSettings: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var settings = studio.settings
        @Bindable var studio = studio
        Form {
            Section {
                Picker("Größe", selection: $studio.sizeTier) {
                    ForEach(SizeTier.allCases) { Text($0.title).tag($0) }
                }
                DrawThingsFormatTable(highlight: studio.sizeTier)
            } header: {
                Text("Größe")
            } footer: {
                Text("Genau die Formate, die Draw Things anbietet. Größere Bilder verkleinert die App vor dem Senden darauf, bei anderem Seitenverhältnis wird beschnitten. 16:9 und 9:16 gibt es nicht als Normal – dort nimmt Draw Things Klein.")
            }

            Section {
                Toggle("Bei jeder Generierung neuer Zufalls-Seed", isOn: $settings.randomSeed)
                Text("Sonst nutzt Draw Things seinen eingestellten Seed – gleicher Prompt ergibt dann dasselbe Bild.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Modell passend zum Modus laden", isOn: $settings.switchModelPerMode)
                if settings.switchModelPerMode {
                    ModelPicker(title: "Generieren", selection: $settings.generateModelFile)
                    ModelPicker(title: "Bearbeiten & Referenzen", selection: $settings.editModelFile)
                }
                Text(settings.switchModelPerMode
                     ? "Die App schickt das Modell mit jeder Anfrage mit; Draw Things wechselt beim nächsten Durchlauf. LoRAs werden nie verändert."
                     : "Aus: Draw Things rendert mit dem Modell, das dort gerade geladen ist. LoRAs werden nie verändert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Draw Things")
            }

            Section {
                Toggle("Alle Referenzbilder an Draw Things senden", isOn: $settings.sendAllReferences)
                    .onChange(of: settings.sendAllReferences) { studio.updateReferenceSentences() }
                Text("Experimentell: Die HTTP-API nimmt mehrere Eingabebilder an, nutzt die weiteren im Test aber nicht zuverlässig. Standard: nur Bild 1 senden, die übrigen beschreibt Gemma im Prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Referenzen")
            }
        }
        .formStyle(.grouped)
    }
}

/// Prompt-Bausteine: Editor öffnen, Standard wiederherstellen.
private struct CatalogSettings: View {
    @Environment(\.openWindow) private var openWindow
    @State private var confirmReset = false

    private var store: CatalogStore { CatalogStore.shared }

    var body: some View {
        let catalog = store.catalog
        let groups = catalog.sections.reduce(0) { $0 + $1.groups.count }
        let options = catalog.sections.reduce(0) { $0 + $1.groups.reduce(0) { $0 + $1.options.count } }
        Form {
            Section {
                LabeledContent("Umfang", value: "\(catalog.sections.count) Bereiche · \(groups) Kategorien · \(options) Bausteine")
                LabeledContent("Stand", value: store.isCustomized ? "Eigene Fassung" : "Standard")
                HStack {
                    Button("Bausteine-Editor öffnen …") { openWindow(id: "catalog-editor") }
                        .buttonStyle(.borderedProminent)
                    Button("Auf Standard zurücksetzen", role: .destructive) { confirmReset = true }
                        .disabled(!store.isCustomized)
                    Spacer()
                    Button("Im Finder zeigen") {
                        if let url = store.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    .disabled(!store.isCustomized || store.fileURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
                }
            } header: {
                Text("Prompt-Bausteine")
            } footer: {
                Text("Im Editor legst du eigene Bereiche und Kategorien an und bearbeitest Namen, Symbole und die englischen Prompts. Eigene Werte kannst du auch direkt in der Seitenleiste mit „Eigenen Wert eingeben + Enter“ hinzufügen. Die Bausteine gehören zur Bibliothek „\(Library.root.lastPathComponent)“ (Katalog/building-blocks.json) – jede neue Bibliothek beginnt mit dem mitgelieferten Stand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Alle Bausteine auf den Standard zurücksetzen?", isPresented: $confirmReset) {
            Button("Zurücksetzen", role: .destructive) { store.resetToDefault() }
        } message: {
            Text("Eigene Bereiche, Kategorien und Bausteine gehen dabei verloren.")
        }
    }
}

/// Auswahl aus den in Draw Things installierten Modellen.
private struct ModelPicker: View {
    let title: String
    @Binding var selection: String
    @State private var installed: [String] = []

    var body: some View {
        Group {
            if installed.isEmpty {
                TextField(title, text: $selection)
            } else {
                Picker(title, selection: $selection) {
                    ForEach(choices, id: \.self) { file in
                        Text("\(DrawThingsConfig.displayName(for: file))  ·  \(file)").tag(file)
                    }
                }
            }
        }
        .task { installed = DrawThingsModels.installed() }
    }

    private var choices: [String] {
        installed.contains(selection) ? installed : [selection] + installed
    }
}

private struct StorageSettings: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var settings = studio.settings
        Form {
            Section {
                ForEach(studio.libraries) { entry in
                    let isCurrent = entry.url.standardizedFileURL == Library.root
                    HStack(spacing: 10) {
                        Image(systemName: entry.isAvailable ? "books.vertical" : "externaldrive.badge.exclamationmark")
                            .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.name).fontWeight(isCurrent ? .semibold : .regular)
                                if isCurrent {
                                    Text("geöffnet")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                        .foregroundStyle(Color.accentColor)
                                } else if !entry.isAvailable {
                                    Text("nicht verfügbar").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(entry.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if !isCurrent {
                            Button("Öffnen") { studio.openLibrary(entry.url) }
                                .disabled(!entry.isAvailable)
                        }
                        Menu {
                            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                                .disabled(!entry.isAvailable)
                            if !isCurrent {
                                Button("Aus der Liste entfernen") { studio.forgetLibrary(entry) }
                            }
                            Divider()
                            Button("Bibliothek löschen …", role: .destructive) { studio.libraryDeletion = entry }
                                .disabled(!entry.isAvailable)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
                HStack {
                    Button("Neue Bibliothek …") { studio.createLibraryWithPanel() }
                    Button("Bibliothek öffnen …") { studio.openLibraryWithPanel() }
                }
            } header: {
                Text("Bibliotheken")
            } footer: {
                Text("Eine Bibliothek ist ein normaler Ordner: Bilder und Videos nach Tagen, dazu „Charaktere“, „Assets“ und „Katalog“ (Markierungen, Notizen, Projekte, Prompt-Bausteine, gespeicherte Prompts, Entwurf, Vorschaubilder). Eine neue Bibliothek beginnt bei null – mit den mitgelieferten Bausteinen und Asset-Kategorien. Ordner kopieren nimmt sie mit, z. B. auf eine SD-Karte; „Bibliothek löschen“ entfernt alles endgültig.")
            }

            Section {
                Toggle("Jedes Ergebnis automatisch in der Bibliothek sichern", isOn: $settings.autosave)
            } footer: {
                Text("PNG-Dateien, nach Tagen sortiert. Der Prompt steht in den Metadaten der Datei.")
            }

            AppDataSection()
        }
        .formStyle(.grouped)
    }
}

/// Was die App außerhalb der Bibliotheken ablegt – zum Nachsehen, z. B. nach dem Ende eines Auftrags.
private struct AppDataSection: View {
    /// Dateien, die hierher gehören – seit alles in den Bibliotheken liegt, keine mehr.
    private static let known: [String: String] = [:]

    @State private var contents: [String] = []

    private var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "DrawThings Studio")
    }

    private var preferencesFile: URL {
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Preferences/\(domain).plist")
    }

    var body: some View {
        Section {
            LabeledContent {
                Button("Im Finder zeigen") { NSWorkspace.shared.open(supportFolder) }
                    .disabled(contents.isEmpty)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Application Support")
                    Text(supportFolder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if contents.isEmpty {
                        Text("Leer – hier liegt nichts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(contents, id: \.self) { name in
                        if let meaning = Self.known[name] {
                            Label("\(name) – \(meaning)", systemImage: "doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("\(name) – gehört nicht hierher (Rest einer älteren Version?)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            LabeledContent {
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([preferencesFile]) }
                    .disabled(!FileManager.default.fileExists(atPath: preferencesFile.path))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Einstellungen der App")
                    Text(preferencesFile.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Verbindungen, Modelle, Darstellung und Fenster – keine Bilder, Prompts oder Bausteine")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Außerhalb der Bibliotheken")
        } footer: {
            Text("Zum Nachsehen nach dem Ende eines Auftrags. Bilder, Charaktere, Assets, Prompt-Bausteine, gespeicherte Prompts, der Prompt-Entwurf und die Serien-Werte liegen nie hier, sondern immer im Ordner der Bibliothek. Application Support sollte leer sein.")
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        contents = ((try? FileManager.default.contentsOfDirectory(atPath: supportFolder.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }
}

private struct AppearanceSettings: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var settings = studio.settings
        Form {
            Section {
                Picker("Seitenleiste & Inspector", selection: $settings.interfaceStyle) {
                    ForEach(InterfaceStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Oberfläche")
            } footer: {
                Text(settings.interfaceStyle == .glass
                     ? "Glas: Seitenleiste und Inspector als Liquid Glass – der Schreibtisch hinter dem Fenster färbt sie leicht ein. Arbeitsfläche und Galerie bleiben deckend."
                     : "Matt: Seitenleiste und Inspector liegen wie gewohnt auf der grauen Fensterfläche.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Übersicht aller Draw-Things-Formate (Breite × Höhe je Stufe).
private struct DrawThingsFormatTable: View {
    let highlight: SizeTier

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                Text("Format")
                ForEach(SizeTier.allCases) { tier in
                    Text(tier.title).gridColumnAlignment(.trailing)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(AspectRatio.all) { ratio in
                GridRow {
                    HStack(spacing: 6) {
                        AspectGlyph(ratio: ratio, size: 12, lineWidth: 1)
                        Text(ratio.label).monospacedDigit()
                        Text(ratio.name).foregroundStyle(.secondary)
                    }
                    ForEach(SizeTier.allCases) { tier in
                        Text(ratio.offers(tier) ? Format.size(ratio.pixelSize(tier)) : "–")
                            .monospacedDigit()
                            .foregroundStyle(tier == highlight ? Color.primary : Color.secondary)
                            .fontWeight(tier == highlight ? .semibold : .regular)
                    }
                }
            }
        }
        .font(.callout)
        .padding(.vertical, 4)
    }
}
