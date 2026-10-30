import SwiftUI

/// Linke Seitenleiste: Promptfeld oben, darunter die aufklappbaren Bausteine.
struct PromptBuilderSidebar: View {
    @Environment(Studio.self) private var studio
    @State private var search = ""
    @State private var collapsedSections: Set<String> = []
    @State private var expandedGroups: Set<String> = ["edit/aktion", "motiv/subjekt"]

    private var builder: PromptBuilder { studio.builder }
    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            PromptEditorCard()
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                searchField
                ClearComponentsButton()
                EditCatalogButton()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            List {
                if studio.mode == .edit && !isSearching {
                    section(id: "format", title: "Format", symbol: "aspectratio", count: 0) {
                        EditFormatEditor()
                    }
                }
                if studio.mode == .edit {
                    section(id: "edit", title: "Bearbeitung", symbol: "wand.and.stars", count: editCount) {
                        ForEach(EditCatalog.groups) { group in groupRow(group) }
                        if !isSearching { IdentityAssistRow() }
                    }
                }
                if studio.mode == .references {
                    section(id: "refs", title: "Referenzen", symbol: "photo.stack", count: studio.filledReferences.count) {
                        ReferenceSummaryRow()
                    }
                }
                if studio.mode == .series {
                    section(id: "series", title: "Serie", symbol: "square.grid.2x2", count: studio.seriesSetup.filledValues.count) {
                        SeriesSummaryRow()
                    }
                }
                if !isSearching || !filteredAssetCategories.isEmpty {
                    section(id: "assets", title: "Assets", symbol: "shippingbox", count: activeAssetCount) {
                        assetRows
                    }
                }
                ForEach(Catalog.shared.sections.filter { !isSearching || $0.groups.contains { !filtered($0).isEmpty } }) { catalogSection in
                    section(id: catalogSection.id, title: catalogSection.name, symbol: catalogSection.icon, count: builder.selectionCount(in: catalogSection)) {
                        ForEach(catalogSection.groups) { group in groupRow(group) }
                        if !isSearching { extraRow(catalogSection) }
                    }
                }
                if isSearching && !Catalog.shared.sections.contains(where: { $0.groups.contains { !filtered($0).isEmpty } }) {
                    Text("Kein Baustein passt zu „\(search)“.")
                        .foregroundStyle(.secondary)
                }
                if !isSearching {
                    section(id: "text", title: "Text im Bild", symbol: "textformat", count: builder.textInImage.text.isEmpty ? 0 : 1) {
                        TextInImageEditor()
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Asset-Baukasten

    private var activeAssetCount: Int {
        studio.assets.assets.filter { studio.isAssetActive($0.id) }.count
    }

    private func filteredAssets(_ category: AssetCategory) -> [Asset] {
        let assets = studio.assets.assets(in: category.id)
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !category.name.localizedCaseInsensitiveContains(query) else { return assets }
        return assets.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }

    private var filteredAssetCategories: [AssetCategory] {
        studio.assets.categories.filter { !filteredAssets($0).isEmpty }
    }

    @ViewBuilder
    private var assetRows: some View {
        let categories = filteredAssetCategories
        if categories.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Kleidung, Schuhe, Orte und Lieblingsreferenzen als Bilder – angelegt in der Galerie unter „Assets“.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Assets anlegen", systemImage: "plus") {
                    studio.gallery.collection = .assets(nil)
                    studio.showGallery = true
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            .padding(.vertical, 4)
        } else {
            Text(studio.mode == .references
                 ? "Klick setzt das Bild in den nächsten freien Referenzplatz."
                 : "Klick nimmt Gemmas Beschreibung in den Prompt – in „Referenzen“ geht das Bild selbst mit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Nach Bereichen gruppiert – wie die Prompt-Bausteine.
            ForEach(studio.assets.sections) { section in
                let inSection = categories.filter { $0.sectionID == section.id }
                if !inSection.isEmpty {
                    Label(section.name, systemImage: section.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(inSection) { category in
                        assetGroup(category)
                    }
                }
            }
        }
    }

    private func assetGroup(_ category: AssetCategory) -> some View {
        let key = "asset/\(category.id)"
        return DisclosureGroup(isExpanded: Binding(
            get: { isSearching || expandedGroups.contains(key) },
            set: { expanded in
                if expanded { expandedGroups.insert(key) } else { expandedGroups.remove(key) }
            }
        )) {
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(filteredAssets(category)) { asset in
                    AssetChip(asset: asset)
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, 4)
        } label: {
            AssetGroupLabel(category: category)
        }
    }

    private var editCount: Int {
        EditCatalog.groups.reduce(0) { $0 + (builder.selections[$1.key]?.count ?? 0) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Bausteine suchen", text: $search)
                .textFieldStyle(.plain)
            if isSearching {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    // MARK: Abschnitte

    @ViewBuilder
    private func section<Content: View>(id: String, title: String, symbol: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        Section(isExpanded: Binding(
            get: { isSearching || !collapsedSections.contains(id) },
            set: { expanded in
                if expanded { collapsedSections.remove(id) } else { collapsedSections.insert(id) }
            }
        )) {
            content()
        } header: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
        }
    }

    @ViewBuilder
    private func groupRow(_ group: CatalogGroup) -> some View {
        let options = filtered(group)
        if !isSearching || !options.isEmpty {
            DisclosureGroup(isExpanded: Binding(
                get: { isSearching || expandedGroups.contains(group.key) },
                set: { expanded in
                    if expanded { expandedGroups.insert(group.key) } else { expandedGroups.remove(group.key) }
                }
            )) {
                VStack(alignment: .leading, spacing: 7) {
                    if !isSearching {
                        Text(caption(for: group))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(options) { option in
                            OptionChip(group: group, option: option)
                        }
                    }
                    if !isSearching && !group.key.hasPrefix("edit/") {
                        CustomOptionField(groupKey: group.key)
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 4)
            } label: {
                GroupLabel(group: group)
            }
        }
    }

    private func caption(for group: CatalogGroup) -> String {
        let mode = group.multi ? "Mehrfachwahl" : "Einzelwahl"
        guard let hint = group.hint, !hint.isEmpty else { return mode }
        return "\(mode) · \(hint)"
    }

    private func filtered(_ group: CatalogGroup) -> [CatalogOption] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return group.options }
        if group.name.localizedCaseInsensitiveContains(query) { return group.options }
        return group.options.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query)
        }
    }

    private func extraRow(_ section: CatalogSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "plus.bubble")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField(
                "Eigene Ergänzung",
                text: Binding(get: { builder.extras[section.id] ?? "" }, set: { builder.setExtra(section.id, $0) }),
                prompt: Text("Eigene Ergänzung, z. B. Trigger-Wörter").foregroundStyle(.tertiary),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...4)
        }
        .padding(.vertical, 2)
    }
}

/// Ein Baustein als Chip – Rechtsklick zum Bearbeiten oder Löschen.
private struct OptionChip: View {
    @Environment(Studio.self) private var studio
    @Environment(\.openWindow) private var openWindow
    let group: CatalogGroup
    let option: CatalogOption

    var body: some View {
        let builder = studio.builder
        let isEditable = !group.key.hasPrefix("edit/")
        Chip(
            title: option.name,
            isOn: builder.isSelected(group.key, option.id),
            isPending: CatalogStore.shared.pendingOptionIDs.contains(option.id)
        ) {
            builder.toggle(group.key, option.id)
        }
        .help(option.text)
        .contextMenu {
            if isEditable {
                Button("Im Bausteine-Editor bearbeiten …", systemImage: "square.and.pencil") {
                    studio.editorFocusKey = group.key
                    openWindow(id: "catalog-editor")
                }
                Button("Prompt neu von Gemma schreiben lassen", systemImage: "wand.and.sparkles") {
                    studio.writeOptionText(groupKey: group.key, optionID: option.id, name: option.name)
                }
                Divider()
                Button("Baustein löschen", systemImage: "trash", role: .destructive) {
                    if builder.isSelected(group.key, option.id) { builder.toggle(group.key, option.id) }
                    CatalogStore.shared.deleteOption(group.key, option.id)
                }
            }
        }
    }
}

/// „Eigenen Wert eingeben + Enter“ – legt einen neuen Baustein in der Kategorie an.
private struct CustomOptionField: View {
    @Environment(Studio.self) private var studio
    let groupKey: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Eigener Wert", text: $text, prompt: Text("Eigenen Wert eingeben + Enter").foregroundStyle(.tertiary))
            .textFieldStyle(.plain)
            .font(.callout)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.14), lineWidth: 1)
            )
            .onSubmit {
                studio.addCustomOption(to: groupKey, name: text)
                text = ""
            }
            .help("Deutsch geht auch – Gemma schreibt daraus den englischen Prompt im Stil dieser Kategorie.")
    }
}

/// Öffnet das Fenster „Bausteine verwalten“.
private struct EditCatalogButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: "catalog-editor")
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .buttonStyle(.borderless)
        .help("Bausteine verwalten – Kategorien und Prompts anlegen und bearbeiten (⌥⌘B)")
    }
}

/// „Leeren“: alle Bausteine auf einmal abwählen – danach kurz „Rückgängig“.
private struct ClearComponentsButton: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let builder = studio.builder
        Group {
            if builder.canUndoClear {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { builder.undoClearComponents() }
                } label: {
                    Label("Rückgängig", systemImage: "arrow.uturn.backward")
                }
                .help("Abgewählte Bausteine wiederherstellen")
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    withAnimation(.smooth(duration: 0.2)) { builder.dismissUndoClear() }
                }
            } else {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { builder.clearComponents() }
                } label: {
                    Label("Leeren", systemImage: "trash")
                }
                .disabled(builder.componentCount == 0)
                .help(builder.componentCount == 0
                      ? "Keine Bausteine gewählt"
                      : "Alle \(builder.componentCount) Bausteine abwählen – ihre Sätze verschwinden aus dem Prompt")
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

/// Zeile einer Baustein-Gruppe mit der aktuellen Auswahl rechts.
private struct GroupLabel: View {
    @Environment(Studio.self) private var studio
    let group: CatalogGroup
    @State private var isHovering = false

    var body: some View {
        let names = studio.builder.selectedNames(group.key)
        HStack(spacing: 8) {
            Image(systemName: group.icon)
                .foregroundStyle(names.isEmpty ? Color.secondary : Color.accentColor)
                .frame(width: 18)
            Text(group.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            if !names.isEmpty {
                Text(names.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button {
                    studio.builder.clear(group.key)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .help("Auswahl entfernen")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// Im Referenz-Modus: kompakte Übersicht, Details im Inspector.
private struct ReferenceSummaryRow: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(studio.references.enumerated()), id: \.element.id) { index, slot in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                        if let image = slot.image {
                            CGImageView(image: slot.thumbnail ?? image, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            Image(systemName: slot.role.symbol)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 54, height: 54)
                    .overlay(alignment: .bottomLeading) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(.black.opacity(0.45)))
                            .padding(3)
                    }
                    .help("Bild \(index + 1): \(slot.role.title)")
                }
            }
            Button("Referenzen bearbeiten", systemImage: "sidebar.trailing") {
                studio.showInspector = true
                studio.inspectorTab = .references
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(.vertical, 4)
    }
}

/// Im Serien-Modus: kompakte Übersicht, Einrichtung im Inspector.
private struct SeriesSummaryRow: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let setup = studio.seriesSetup
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    if let source = studio.seriesSource {
                        CGImageView(image: source.thumbnail, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 54, height: 54)
                .help("Ausgangsbild")

                VStack(alignment: .leading, spacing: 3) {
                    Label(setup.variableName, systemImage: setup.variable.symbol)
                        .font(.callout.weight(.medium))
                    Text(setup.filledValues.isEmpty ? "Noch keine Varianten" : setup.filledValues.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Text("Der Prompt oben gilt zusätzlich für jedes Bild der Serie.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Serie einrichten", systemImage: "sidebar.trailing") {
                studio.showInspector = true
                studio.inspectorTab = .series
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(.vertical, 4)
    }
}

/// Asset als Baustein: kleines Vorschaubild und Name.
private struct AssetChip: View {
    @Environment(Studio.self) private var studio
    let asset: Asset
    @State private var isHovering = false

    var body: some View {
        let isOn = studio.isAssetActive(asset.id)
        let isDescribing = studio.assets.describing.contains(asset.id)
        Button {
            studio.toggleAsset(asset.id)
        } label: {
            HStack(spacing: 6) {
                AssetThumbnail(asset: asset)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(asset.name)
                    .font(.callout)
                    .lineLimit(1)
                if isDescribing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.leading, 3)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background {
                Capsule().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.12 : 0.065)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isOn)
        .help(asset.description.isEmpty ? asset.name : asset.description)
        .contextMenu {
            AssetMenu(asset: asset)
            Button("In der Galerie zeigen", systemImage: "shippingbox") {
                studio.gallery.collection = .assets(asset.categoryID)
                studio.assets.selectedID = asset.id
                studio.showGallery = true
            }
        }
    }
}

/// Zeile einer Asset-Kategorie mit den gewählten Assets rechts.
private struct AssetGroupLabel: View {
    @Environment(Studio.self) private var studio
    let category: AssetCategory

    var body: some View {
        let names = studio.assets.assets(in: category.id).filter { studio.isAssetActive($0.id) }.map(\.name)
        HStack(spacing: 8) {
            Image(systemName: category.icon)
                .foregroundStyle(names.isEmpty ? Color.secondary : Color.accentColor)
                .frame(width: 18)
            Text(category.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            if !names.isEmpty {
                Text(names.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}
