import SwiftUI

/// Fenster „Bausteine verwalten“: Bereiche, Kategorien und Bausteine (Name + englischer Prompt)
/// anlegen, bearbeiten, sortieren und löschen.
struct CatalogEditorView: View {
    enum Selection: Hashable {
        case section(String)
        case group(String)
    }

    @Environment(Studio.self) private var studio
    @State private var selection: Selection?
    @State private var confirmReset = false
    @State private var pendingDelete: Selection?

    private var store: CatalogStore { CatalogStore.shared }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.catalog.sections) { section in
                    Section {
                        ForEach(section.groups) { group in
                            Label(group.name, systemImage: group.icon)
                                .badge(group.options.count)
                                .tag(Selection.group(group.key))
                        }
                        .onMove { store.moveGroups(in: section.id, from: $0, to: $1) }
                    } header: {
                        Button {
                            selection = .section(section.id)
                        } label: {
                            HStack {
                                Label(section.name, systemImage: section.icon)
                                Spacer()
                                Image(systemName: "pencil")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Bereich „\(section.name)“ bearbeiten")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 360)
            .safeAreaInset(edge: .bottom) { bottomBar }
        } detail: {
            switch selection {
            case .group(let key):
                GroupEditor(key: key)
                    .id(key)
            case .section(let id):
                SectionEditor(id: id, selection: $selection)
                    .id(id)
            case nil:
                ContentUnavailableView(
                    "Kategorie wählen",
                    systemImage: "square.grid.2x2",
                    description: Text("Links eine Kategorie auswählen – oder mit + einen neuen Bereich bzw. eine neue Kategorie anlegen.")
                )
            }
        }
        .navigationTitle("Bausteine verwalten")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Auf Standard zurücksetzen", systemImage: "arrow.counterclockwise") { confirmReset = true }
                    .disabled(!store.isCustomized)
                    .help("Alle eigenen Bereiche, Kategorien und Bausteine verwerfen")
            }
        }
        .confirmationDialog("Alle Bausteine auf den Standard zurücksetzen?", isPresented: $confirmReset) {
            Button("Zurücksetzen", role: .destructive) {
                store.resetToDefault()
                selection = nil
            }
        } message: {
            Text("Eigene Bereiche, Kategorien und Bausteine gehen dabei verloren.")
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Löschen", role: .destructive) { performDelete() }
        } message: {
            Text("Das lässt sich nur über „Auf Standard zurücksetzen“ rückgängig machen.")
        }
        .onAppear(perform: applyFocus)
        .onChange(of: studio.editorFocusKey) { applyFocus() }
        .frame(minWidth: 900, minHeight: 580)
    }

    /// Bausteine gehören zur Bibliothek – im Fenster steht, zu welcher.
    private var subtitle: String {
        let library = store.fileURL?.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let state = store.isCustomized ? "Eigene Fassung" : "Standard"
        return library.map { "Bibliothek „\($0)“ · \(state)" } ?? state
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Neue Kategorie", systemImage: "plus.square.on.square") { addGroup() }
                    .disabled(store.catalog.sections.isEmpty)
                Button("Neuer Bereich", systemImage: "folder.badge.plus") { addSection() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Neue Kategorie oder neuen Bereich anlegen")

            Button {
                pendingDelete = selection
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Auswahl löschen")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var deleteTitle: String {
        switch pendingDelete {
        case .section(let id): "Bereich „\(store.catalog.section(id)?.name ?? "")“ mit allen Kategorien löschen?"
        case .group(let key): "Kategorie „\(store.catalog.group(key)?.name ?? "")“ mit allen Bausteinen löschen?"
        case nil: ""
        }
    }

    private func performDelete() {
        switch pendingDelete {
        case .section(let id): store.deleteSection(id)
        case .group(let key): store.deleteGroup(key)
        case nil: break
        }
        selection = nil
        pendingDelete = nil
    }

    private func addSection() {
        let id = store.addSection(name: "Neuer Bereich")
        selection = .section(id)
    }

    private func addGroup() {
        let sectionID: String? = switch selection {
        case .section(let id): id
        case .group(let key): store.sectionID(ofGroup: key)
        case nil: store.catalog.sections.last?.id
        }
        guard let sectionID, let key = store.addGroup(to: sectionID, name: "Neue Kategorie") else { return }
        selection = .group(key)
    }

    private func applyFocus() {
        if let key = studio.editorFocusKey {
            selection = .group(key)
            studio.editorFocusKey = nil
        } else if selection == nil, let first = store.catalog.sections.first?.groups.first {
            selection = .group(first.key)
        }
    }
}

// MARK: - Kategorie

private struct GroupEditor: View {
    @Environment(Studio.self) private var studio
    let key: String

    private var store: CatalogStore { CatalogStore.shared }

    var body: some View {
        if let group = store.catalog.group(key) {
            List {
                Section("Kategorie") {
                    TextField("Name", text: binding(\.name))
                    SymbolField(symbol: binding(\.icon))
                    Toggle("Mehrfachauswahl", isOn: binding(\.multi))
                    TextField("Hinweis", text: optionalBinding(\.hint), prompt: Text("optional, z. B. „Haltung, Hände, Gewichtsverteilung“"))
                }

                Section {
                    TextField("Generieren", text: optionalBinding(\.template), prompt: Text("z. B. The image is rendered as {}."))
                    TextField("Bearbeiten", text: optionalBinding(\.editTemplate), prompt: Text("z. B. Restyle the whole image as {}, keeping …"))
                } header: {
                    Text("Satzvorlagen (optional)")
                } footer: {
                    Text("„{}“ wird durch die gewählten Bausteine ersetzt. Leer lassen, wenn jeder Baustein ein ganzer Satz ist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(group.options) { option in
                        OptionEditorRow(groupKey: key, optionID: option.id)
                    }
                    .onMove { store.moveOptions(in: key, from: $0, to: $1) }
                    .onDelete { offsets in
                        offsets.map { group.options[$0].id }.forEach { store.deleteOption(key, $0) }
                    }
                    Button {
                        _ = store.addOption(to: key, name: "Neuer Baustein", text: "")
                    } label: {
                        Label("Baustein hinzufügen", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    HStack {
                        Text("Bausteine (\(group.options.count))")
                        Spacer()
                        Text("Name in der App · Prompt für Qwen (Englisch)")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Zum Sortieren ziehen. ✨ lässt Gemma den englischen Prompt aus dem Namen schreiben – passend zu den anderen Bausteinen dieser Kategorie.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        } else {
            ContentUnavailableView("Kategorie nicht gefunden", systemImage: "questionmark.square.dashed")
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<CatalogGroup, Value>) -> Binding<Value> where Value: Equatable {
        Binding(
            get: { store.catalog.group(key)![keyPath: path] },
            set: { value in store.updateGroup(key) { $0[keyPath: path] = value } }
        )
    }

    private func optionalBinding(_ path: WritableKeyPath<CatalogGroup, String?>) -> Binding<String> {
        Binding(
            get: { store.catalog.group(key)?[keyPath: path] ?? "" },
            set: { value in store.updateGroup(key) { $0[keyPath: path] = value.isEmpty ? nil : value } }
        )
    }
}

private struct OptionEditorRow: View {
    @Environment(Studio.self) private var studio
    let groupKey: String
    let optionID: String

    private var store: CatalogStore { CatalogStore.shared }
    private var option: CatalogOption? { store.catalog.group(groupKey)?.options.first { $0.id == optionID } }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            TextField("Name", text: binding(\.name))
                .frame(width: 180)
            TextField("Prompt (Englisch)", text: binding(\.text), axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(.secondary)
            if store.pendingOptionIDs.contains(optionID) {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    studio.writeOptionText(groupKey: groupKey, optionID: optionID, name: option?.name ?? "")
                } label: {
                    Image(systemName: "wand.and.sparkles")
                }
                .buttonStyle(.borderless)
                .help("Gemma schreibt den englischen Prompt aus dem Namen")
            }
            Button {
                store.deleteOption(groupKey, optionID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Baustein löschen")
        }
        .textFieldStyle(.roundedBorder)
    }

    private func binding(_ path: WritableKeyPath<CatalogOption, String>) -> Binding<String> {
        Binding(
            get: { option?[keyPath: path] ?? "" },
            set: { value in store.updateOption(groupKey, optionID) { $0[keyPath: path] = value } }
        )
    }
}

// MARK: - Bereich

private struct SectionEditor: View {
    let id: String
    @Binding var selection: CatalogEditorView.Selection?

    private var store: CatalogStore { CatalogStore.shared }

    var body: some View {
        if let section = store.catalog.section(id) {
            Form {
                Section("Bereich") {
                    TextField("Name", text: Binding(
                        get: { store.catalog.section(id)?.name ?? "" },
                        set: { value in store.updateSection(id) { $0.name = value } }
                    ))
                    SymbolField(symbol: Binding(
                        get: { store.catalog.section(id)?.icon ?? "folder" },
                        set: { value in store.updateSection(id) { $0.icon = value } }
                    ))
                }
                Section("Kategorien (\(section.groups.count))") {
                    ForEach(section.groups) { group in
                        Button {
                            selection = .group(group.key)
                        } label: {
                            HStack {
                                Label(group.name, systemImage: group.icon)
                                Spacer()
                                Text("\(group.options.count) Bausteine")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        if let key = store.addGroup(to: id, name: "Neue Kategorie") { selection = .group(key) }
                    } label: {
                        Label("Kategorie hinzufügen", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                Section {
                    HStack {
                        Button("Nach oben") { move(-1) }
                            .disabled(store.catalog.sections.first?.id == id)
                        Button("Nach unten") { move(1) }
                            .disabled(store.catalog.sections.last?.id == id)
                    }
                } header: {
                    Text("Position in der Seitenleiste")
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Bereich nicht gefunden", systemImage: "questionmark.folder")
        }
    }

    private func move(_ delta: Int) {
        guard let index = store.catalog.sections.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard store.catalog.sections.indices.contains(target) else { return }
        store.moveSections(from: IndexSet(integer: index), to: delta > 0 ? target + 1 : target)
    }
}

// MARK: - Symbolwahl

/// SF-Symbol per Name oder aus einer Auswahl.
struct SymbolField: View {
    @Binding var symbol: String

    static let suggestions = [
        "tag", "star", "heart", "folder", "person", "person.2", "figure.stand", "figure.walk", "figure.wave",
        "hand.raised", "eye", "face.smiling", "mustache", "tshirt", "hanger", "shoe.2", "crown", "handbag", "eyeglasses",
        "house", "sofa", "building.2", "building.columns", "leaf", "tree", "mountain.2", "sparkles", "cloud.sun",
        "sun.max", "moon.stars", "snowflake", "drop", "flame", "bolt", "camera", "camera.aperture", "lightbulb", "film",
        "paintpalette", "paintbrush", "paintbrush.pointed", "pencil.and.outline", "photo", "map", "mappin.and.ellipse",
        "car", "airplane", "pawprint", "fork.knife", "cup.and.saucer", "music.note", "theatermasks", "wand.and.stars",
        "book", "graduationcap", "briefcase", "gamecontroller", "gift", "party.popper", "globe.europe.africa",
    ]

    var body: some View {
        LabeledContent("Symbol") {
            HStack(spacing: 8) {
                Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "questionmark.square.dashed" : symbol)
                    .frame(width: 22)
                    .foregroundStyle(Color.accentColor)
                TextField("SF-Symbol", text: $symbol)
                    .frame(width: 200)
                    .textFieldStyle(.roundedBorder)
                Menu("Auswählen") {
                    ForEach(Self.suggestions, id: \.self) { name in
                        Button {
                            symbol = name
                        } label: {
                            Label(name, systemImage: name)
                        }
                    }
                }
                .fixedSize()
            }
        }
    }
}
