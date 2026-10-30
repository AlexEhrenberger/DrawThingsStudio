import SwiftUI

/// Was die Bibliotheksauswahl gerade zeigt – links in ihrer Seitenleiste gewählt.
/// Tags und Charaktere filtern zusätzlich darüber (Dropdowns über dem Raster).
enum LibraryPickerScope: Hashable {
    case all, picks, rated
    case project(UUID)
    case day(Date)
}

/// Die Bibliothek im Kleinen – wie die Fotoauswahl in macOS: links Sammlungen, rechts die Bilder.
/// Klick wählt, Doppelklick oder ↩ übernimmt, Leertaste zeigt das Bild groß. Videos stehen hier nicht.
/// Mit `allowsMultiple` wählen ⌘- und ⇧-Klick mehrere Bilder (z. B. mehrere Ansichten eines Charakters).
struct LibraryPicker: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String?
    var allowsMultiple = false
    /// Einzelwahl – auch der Doppelklick bei höchstens einem gewählten Bild.
    let onPick: (GalleryItem) -> Void
    /// Mehrfachwahl: alle gewählten Bilder in der Reihenfolge des Rasters.
    var onPickMany: (([GalleryItem]) -> Void)?

    @State private var scope: LibraryPickerScope = .all
    @State private var search = ""
    @State private var selectedIDs: Set<UUID> = []
    /// Zuletzt angeklicktes oder per Pfeil erreichtes Bild – die große Ansicht zeigt es.
    @State private var focusedID: UUID?
    /// Ausgangspunkt für ⇧-Klick.
    @State private var anchorID: UUID?
    /// Klick auf ein Bild einer Mehrfachauswahl: wird zur Einzelwahl, sobald kein Doppelklick mehr folgt.
    @State private var collapseTask: Task<Void, Never>?
    /// Filter über dem Raster – unabhängig von der Sammlung links, sie bleiben beim Wechsel stehen.
    @State private var selectedTags: Set<String> = []
    @State private var tagsMatchAll = false
    @State private var selectedPersonas: Set<UUID> = []
    @State private var isPreviewing = false
    @State private var gridWidth: CGFloat = 700
    @AppStorage("libraryPicker.thumbnailSize") private var thumbnailSize = 140.0
    @FocusState private var gridFocused: Bool

    private static let spacing: CGFloat = 10
    private static let padding: CGFloat = 14

    var body: some View {
        let images = studio.gallery.visibleItems.filter { !$0.isVideo }
        let shown = filtered(images)
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar(images)
                    .frame(width: 220)
                Divider()
                VStack(spacing: 0) {
                    filterBar(images)
                    Divider()
                    content(shown)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer(shown)
        }
        .frame(minWidth: 860, idealWidth: 1020, maxWidth: .infinity, minHeight: 560, idealHeight: 700, maxHeight: .infinity)
        .onAppear { gridFocused = true }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle ?? "Bibliothek „\(studio.libraryName)“")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Prompt oder Tag suchen", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Suche löschen")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            .frame(width: 260)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: Seitenleiste

    private func sidebar(_ images: [GalleryItem]) -> some View {
        let gallery = studio.gallery
        let days = gallery.days
        return List(selection: Binding<LibraryPickerScope?>(get: { scope }, set: { if let value = $0 { scope = value } })) {
            Section("Bibliothek") {
                row(.all, title: "Alle Bilder", symbol: "photo.on.rectangle", images: images)
                row(.picks, title: "Behalten", symbol: "flag.fill", images: images)
                row(.rated, title: "Bewertet", symbol: "star.fill", images: images)
            }
            if !gallery.projects.isEmpty {
                Section("Projekte") {
                    ForEach(gallery.projects) { project in
                        row(.project(project.id), title: project.name, symbol: "folder", images: images)
                    }
                }
            }
            if !days.isEmpty {
                Section("Datum") {
                    ForEach(days, id: \.day) { day in
                        row(.day(day.day), title: Gallery.dayTitle(day.day), symbol: "calendar", images: images)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ scope: LibraryPickerScope, title: String, symbol: String, images: [GalleryItem]) -> some View {
        Label(title, systemImage: symbol)
            .lineLimit(1)
            .badge(count(scope, in: images))
            .tag(scope)
    }

    private func count(_ scope: LibraryPickerScope, in images: [GalleryItem]) -> Int {
        images.lazy.filter { self.matches($0, scope) }.count
    }

    // MARK: Filter

    private var hasFilter: Bool { !selectedTags.isEmpty || !selectedPersonas.isEmpty }

    /// Zwei Dropdowns über dem Raster. Die Zahlen zählen die Bilder der ganzen Bibliothek, nicht der Sammlung links.
    private func filterBar(_ images: [GalleryItem]) -> some View {
        HStack(spacing: 8) {
            MultiSelectDropdown(
                title: "Tags", symbol: "tag", emptyText: "Noch keine Tags.",
                options: tagOptions(images), selection: $selectedTags, matchAll: $tagsMatchAll,
                onClose: { gridFocused = true }
            )
            MultiSelectDropdown(
                title: "Charaktere", symbol: "person.crop.circle", emptyText: "Noch keine Charaktere.",
                options: personaOptions(images), selection: $selectedPersonas,
                onClose: { gridFocused = true }
            ) { option in
                if let persona = studio.personas.persona(option.id) { PersonaAvatar(persona: persona, size: 18) }
            }
            if hasFilter {
                Button("Zurücksetzen") {
                    selectedTags = []
                    tagsMatchAll = false
                    selectedPersonas = []
                    gridFocused = true
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, 8)
    }

    private func tagOptions(_ images: [GalleryItem]) -> [DropdownOption<String>] {
        var counts: [String: Int] = [:]
        for item in images {
            for tag in item.tags ?? [] { counts[tag, default: 0] += 1 }
        }
        return counts
            .map { DropdownOption(id: $0.key, title: $0.key, count: $0.value) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func personaOptions(_ images: [GalleryItem]) -> [DropdownOption<UUID>] {
        var counts: [UUID: Int] = [:]
        for item in images {
            for id in item.personaIDs ?? [] { counts[id, default: 0] += 1 }
        }
        return studio.personas.personas.map { DropdownOption(id: $0.id, title: $0.name, count: counts[$0.id] ?? 0) }
    }

    // MARK: Raster

    @ViewBuilder
    private func content(_ items: [GalleryItem]) -> some View {
        if !studio.isLibraryAvailable {
            ContentUnavailableView(
                "Bibliothek nicht verfügbar",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("Der Ordner von „\(studio.libraryName)“ ist gerade nicht erreichbar – z. B. weil die SD-Karte fehlt.")
            )
        } else if items.isEmpty {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if hasFilter {
                ContentUnavailableView("Keine Bilder", systemImage: "line.3.horizontal.decrease.circle", description: Text("Zu diesen Filtern gibt es hier kein Bild."))
            } else {
                ContentUnavailableView("Keine Bilder", systemImage: "photo.on.rectangle", description: Text("Hier liegt noch kein Bild."))
            }
        } else {
            grid(items)
                .overlay {
                    if isPreviewing, let id = focusedID, let item = items.first(where: { $0.id == id }) {
                        preview(item)
                    }
                }
        }
    }

    private func grid(_ items: [GalleryItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize * 1.5), spacing: Self.spacing)],
                    spacing: Self.spacing
                ) {
                    ForEach(items) { item in
                        PickerTile(item: item, isSelected: selectedIDs.contains(item.id), showsCheck: allowsMultiple)
                            .id(item.id)
                            .onTapGesture { tapped(item, in: items) }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { doubleTapped(item, in: items) })
                    }
                }
                .padding(Self.padding)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .focusable()
            .focused($gridFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in
                handleKey(press, items: items, proxy: proxy)
            }
        }
    }

    private var columns: Int {
        max(Int((gridWidth - Self.padding * 2 + Self.spacing) / (thumbnailSize + Self.spacing)), 1)
    }

    /// Leertaste: das gewählte Bild groß – Pfeiltasten blättern weiter, Leertaste oder Esc schließen.
    private func preview(_ item: GalleryItem) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.88))
            VStack(spacing: 10) {
                GalleryFullImage(item: item)
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                Text("\(item.kindTitle) · \(item.width) × \(item.height) px · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture { isPreviewing = false }
        .simultaneousGesture(TapGesture(count: 2).onEnded { doubleTapped(item, in: [item]) })
        .transition(.opacity)
    }

    private func handleKey(_ press: KeyPress, items: [GalleryItem], proxy: ScrollViewProxy) -> KeyPress.Result {
        let ids = items.map(\.id)
        func move(_ delta: Int) -> KeyPress.Result {
            guard !ids.isEmpty else { return .ignored }
            let current = focusedID.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
            let next = ids[min(max(current + delta, 0), ids.count - 1)]
            selectedIDs = [next]
            focusedID = next
            anchorID = next
            withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(next) }
            return .handled
        }
        switch press.key {
        case .leftArrow: return move(-1)
        case .rightArrow: return move(1)
        case .upArrow: return move(-columns)
        case .downArrow: return move(columns)
        case .space:
            guard focusedID != nil else { return .ignored }
            withAnimation(.smooth(duration: 0.2)) { isPreviewing.toggle() }
            return .handled
        case .escape where isPreviewing:
            withAnimation(.smooth(duration: 0.2)) { isPreviewing = false }
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: Fuß

    private func footer(_ items: [GalleryItem]) -> some View {
        let chosen = items.filter { selectedIDs.contains($0.id) }
        return HStack(spacing: 12) {
            Text(items.count == 1 ? "1 Bild" : "\(items.count) Bilder")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "photo")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: $thumbnailSize, in: 90...320)
                .controlSize(.small)
                .frame(width: 110)
                .help("Kachelgröße")
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Spacer()
            if !chosen.isEmpty {
                Text(allowsMultiple ? "⌘- oder ⇧-Klick wählt mehrere · Leertaste zeigt das Bild groß" : "Leertaste zeigt das Bild groß")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if allowsMultiple {
                Text("⌘- oder ⇧-Klick wählt mehrere")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button("Abbrechen", role: .cancel) { dismiss() }
                // In der großen Ansicht schließt Esc nur die Ansicht.
                .keyboardShortcut(isPreviewing ? nil : .cancelAction)
            Button(allowsMultiple ? "Übernehmen (\(chosen.count))" : "Übernehmen") {
                commit(chosen)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(chosen.isEmpty)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: Auswahl

    private func filtered(_ images: [GalleryItem]) -> [GalleryItem] {
        let words = search.split(separator: " ")
        return images.filter { item in
            guard matches(item, scope) else { return false }
            // Wie der Filter der Galerie: Charaktere – mindestens einer, Tags – einer davon oder alle.
            if !selectedPersonas.isEmpty, !(item.personaIDs ?? []).contains(where: selectedPersonas.contains) { return false }
            if !selectedTags.isEmpty {
                let tags = Set(item.tags ?? [])
                if tagsMatchAll ? !selectedTags.isSubset(of: tags) : tags.isDisjoint(with: selectedTags) { return false }
            }
            guard !words.isEmpty else { return true }
            let haystack = ([item.prompt, item.label ?? ""] + (item.tags ?? [])).joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    private func matches(_ item: GalleryItem, _ scope: LibraryPickerScope) -> Bool {
        switch scope {
        case .all: true
        case .picks: item.flag == .pick
        case .rated: item.rating > 0
        case .project(let id): studio.gallery.projectMembers[id]?.contains(item.id) == true
        case .day(let day): Calendar.current.isDate(item.createdAt, inSameDayAs: day)
        }
    }

    /// Klick: Einzelwahl. Mit Mehrfachwahl schaltet ⌘ ein Bild an und aus, ⇧ wählt von der letzten Wahl bis hierher.
    private func tapped(_ item: GalleryItem, in items: [GalleryItem]) {
        gridFocused = true
        focusedID = item.id
        guard allowsMultiple else {
            selectedIDs = [item.id]
            return
        }
        // Der zweite Klick eines Doppelklicks ändert nichts mehr an der Wahl des ersten.
        guard (NSApp.currentEvent?.clickCount ?? 1) < 2 else { return }
        collapseTask?.cancel()
        let modifiers = (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
            anchorID = item.id
        } else if modifiers.contains(.shift), let anchor = anchorID,
                  let a = items.firstIndex(where: { $0.id == anchor }), let b = items.firstIndex(where: { $0.id == item.id }) {
            selectedIDs = Set(items[min(a, b)...max(a, b)].map(\.id))
        } else if selectedIDs.count > 1, selectedIDs.contains(item.id) {
            // Folgt ein Doppelklick, gilt die ganze Auswahl; sonst bleibt nur dieses Bild.
            collapseTask = Task {
                try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
                guard !Task.isCancelled else { return }
                selectedIDs = [item.id]
                anchorID = item.id
            }
        } else {
            selectedIDs = [item.id]
            anchorID = item.id
        }
    }

    /// Doppelklick übernimmt dieses Bild – oder, bei mehreren gewählten, die ganze Auswahl.
    private func doubleTapped(_ item: GalleryItem, in items: [GalleryItem]) {
        collapseTask?.cancel()
        if allowsMultiple, selectedIDs.count > 1, selectedIDs.contains(item.id) {
            commit(items.filter { selectedIDs.contains($0.id) })
        } else {
            pick(item)
        }
    }

    private func commit(_ items: [GalleryItem]) {
        if allowsMultiple, items.count > 1 {
            if let onPickMany { onPickMany(items) } else { items.forEach(onPick) }
            dismiss()
        } else if let item = items.first {
            pick(item)
        }
    }

    private func pick(_ item: GalleryItem) {
        onPick(item)
        dismiss()
    }
}

/// Kachel der Bibliotheksauswahl: Bild, Sterne und Markierung.
private struct PickerTile: View {
    let item: GalleryItem
    let isSelected: Bool
    /// Mehrfachwahl: gewählte Kacheln tragen ein Häkchen.
    var showsCheck = false

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GalleryThumbnail(item: item)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .opacity(item.flag == .reject ? 0.4 : 1)
                }
            HStack(spacing: 4) {
                if item.rating > 0 {
                    Text(String(repeating: "★", count: item.rating))
                        .foregroundStyle(.yellow)
                }
                Spacer(minLength: 0)
                if item.flag == .pick {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.system(size: 9))
            .frame(height: 10)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(isHovering ? 0.07 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            if showsCheck && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovering = $0 }
        .help(help)
    }

    private var help: String {
        var parts = [item.kindTitle, item.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let tags = item.tags, !tags.isEmpty { parts.append(tags.joined(separator: ", ")) }
        return parts.joined(separator: " · ") + " – Doppelklick übernimmt"
    }
}
