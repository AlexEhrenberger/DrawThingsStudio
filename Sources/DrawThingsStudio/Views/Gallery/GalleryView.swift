import SwiftUI

/// Galerie: alle Bilder und Videos der Bibliothek als Raster, nach Tagen gruppiert – Serien liegen als Stapel.
/// Ein Klick auf einen Stapel fächert ihn zum Vergleich auf, ein Doppelklick auf ein Bild zeigt es groß.
struct GalleryView: View {
    @Environment(Studio.self) private var studio
    @State private var isImportTargeted = false

    var body: some View {
        @Bindable var gallery = studio.gallery
        let entries = gallery.entries
        ZStack {
            GalleryBackground()
            if !studio.isLibraryAvailable {
                LibraryUnavailableView()
            } else if let viewer = gallery.viewer {
                GalleryViewer(state: viewer, entries: entries)
                    .transition(.opacity)
            } else if gallery.collection == .notes {
                GalleryNotesView()
                    .transition(.opacity)
            } else if case .persona(let id) = gallery.collection {
                CharacterScreen(personaID: id, entries: entries)
                    .transition(.opacity)
            } else if case .assets(let categoryID) = gallery.collection {
                AssetBrowser(scope: categoryID.map { .category($0) } ?? .all)
                    .transition(.opacity)
            } else if case .assetSection(let sectionID) = gallery.collection {
                AssetBrowser(scope: .section(sectionID))
                    .transition(.opacity)
            } else if case .story(let id) = gallery.collection {
                StoryPage(storyID: id)
                    .transition(.opacity)
            } else if entries.isEmpty {
                GalleryEmptyState()
            } else {
                GalleryGrid(entries: entries)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if gallery.viewer == nil, gallery.showsGrid, !gallery.items.isEmpty, studio.isLibraryAvailable {
                GalleryBar(entries: entries)
                    .padding(.bottom, 18)
            }
        }
        .overlay(alignment: .top) {
            if let message = studio.errorMessage {
                ErrorBanner(message: message)
                    .padding(.top, 14)
            }
        }
        .animation(.smooth, value: studio.errorMessage)
        .overlay {
            if isImportTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(10)
                    .overlay {
                        Label("In „\(studio.libraryName)“ importieren", systemImage: "square.and.arrow.down.on.square")
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .allowsHitTesting(false)
            }
        }
        // Bilder und Videos aus dem Finder (z. B. Clips aus Gemini) landen als Kopie in der Bibliothek.
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { isImportTargeted },
            set: { isImportTargeted = $0 && gallery.drag == nil && gallery.collection.showsGrid && gallery.viewer == nil }
        )) { providers in
            // Eigene Kacheln, die zurück aufs Raster fallen, liegen schon in der Bibliothek – importFiles überspringt sie.
            gallery.drag = nil
            guard gallery.collection.showsGrid, gallery.viewer == nil else { return false }
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                    }) { urls.append(url) }
                }
                studio.importIntoLibrary(urls)
            }
            return true
        }
        // Suchfeld: eigenes Werkzeugleisten-Element in MainView (`ToolbarSearchField`), nicht `.searchable`.
        .confirmationDialog(
            trashTitle,
            isPresented: Binding(get: { gallery.trashRequest != nil }, set: { if !$0 { gallery.trashRequest = nil } }),
            titleVisibility: .visible
        ) {
            Button("In den Papierkorb legen", role: .destructive) {
                if let ids = gallery.trashRequest { studio.moveToTrash(ids) }
                gallery.trashRequest = nil
            }
        } message: {
            Text("Die Dateien wandern aus der Bibliothek in den Papierkorb und lassen sich dort zurücklegen.")
        }
    }

    private var trashTitle: String {
        let count = studio.gallery.trashRequest?.count ?? 0
        return count == 1 ? "Bild in den Papierkorb legen?" : "\(count) Bilder in den Papierkorb legen?"
    }
}

// MARK: - Raster

/// Raster der Galerie – auch im Fokusmodus (dann schwarz, ohne Fußzeilen).
struct GalleryGrid: View {
    @Environment(Studio.self) private var studio
    let entries: [GalleryEntry]
    var isFocus = false

    @FocusState private var isFocused: Bool
    @State private var width: CGFloat = 800
    @State private var height: CGFloat = 600
    /// Stelle des letzten Pinch (Anteil der Höhe) – dort bleibt die Kachel unter den Fingern stehen.
    @State private var pinchAnchor: CGFloat = 0.5
    @AppStorage("focus.showSidebar") private var focusShowSidebar = false
    @AppStorage("focus.showInfo") private var focusShowInfo = false

    private var spacing: CGFloat { isFocus ? 18 : 12 }
    private var padding: CGFloat { isFocus ? 34 : 22 }

    var body: some View {
        let gallery = studio.gallery
        let size = gallery.thumbnailSize
        let order = entries.map(\.id)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: size, maximum: size * 1.5), spacing: spacing)],
                    alignment: .leading,
                    spacing: spacing,
                    // Im Fokusmodus wandern die Tagesüberschriften mit – oben links liegen die Knöpfe.
                    pinnedViews: isFocus ? [] : [.sectionHeaders]
                ) {
                    if gallery.showsDates {
                        ForEach(gallery.sections(of: entries)) { section in
                            Section {
                                cells(section.entries, order: order)
                            } header: {
                                SectionHeader(section: section, isFocus: isFocus)
                            }
                        }
                    } else {
                        // Ohne Datum: alle Kacheln am Stück, keine halb leeren Zeilen am Ende eines Tages.
                        cells(entries, order: order)
                    }
                }
                .padding(.horizontal, padding)
                .padding(.top, isFocus ? 54 : 6)
                .padding(.bottom, 100)
            }
            .contentShape(Rectangle())
            // Klick in die Leerfläche hebt die Auswahl auf (Klicks auf Kacheln haben Vorrang).
            .onTapGesture { gallery.selection = [] }
            .onGeometryChange(for: CGSize.self) { $0.size } action: {
                width = $0.width
                height = $0.height
            }
            .background {
                // Pinch auf dem Trackpad vergrößert die Kacheln; Scrollen mit zwei Fingern bleibt beim System.
                CanvasEventMonitor(isActive: true, onScroll: nil, onMagnify: { factor, location in
                    pinchAnchor = height > 0 ? min(max(location.y / height, 0), 1) : 0.5
                    gallery.zoomGrid(by: factor)
                })
            }
            // Mit neuer Spaltenzahl springt das Raster – die Kachel unter dem Zeiger bleibt, wo sie war.
            .onChange(of: columns) {
                guard let id = gallery.hoveredEntryID ?? gallery.selectionAnchor, order.contains(id) else { return }
                proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: pinchAnchor))
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in
                handleKey(press, order: order, proxy: proxy)
            }
            .onAppear {
                isFocused = true
                if let id = gallery.lastViewedEntryID { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var columns: Int {
        max(Int((width - padding * 2 + spacing) / (studio.gallery.thumbnailSize + spacing)), 1)
    }

    private func cells(_ entries: [GalleryEntry], order: [UUID]) -> some View {
        let gallery = studio.gallery
        return ForEach(entries) { entry in
            GalleryCell(
                entry: entry,
                isSelected: gallery.selection.contains(entry.id),
                isFocus: isFocus,
                onClick: { click(entry, order: order) },
                onOpen: { open(entry) }
            )
            .id(entry.id)
        }
    }

    private func click(_ entry: GalleryEntry, order: [UUID]) {
        let modifiers = NSEvent.modifierFlags
        studio.gallery.click(entry.id, order: order, modifiers: modifiers)
        isFocused = true
        // Ein Stapel fächert sich beim Klick auf – mit ⌘ oder ⇧ wird er nur ausgewählt.
        if case .stack = entry, modifiers.intersection([.command, .shift]).isEmpty {
            open(entry)
        }
    }

    private func open(_ entry: GalleryEntry) {
        withAnimation(.smooth(duration: 0.25)) { studio.gallery.open(entry) }
    }

    private func handleKey(_ press: KeyPress, order: [UUID], proxy: ScrollViewProxy) -> KeyPress.Result {
        let gallery = studio.gallery
        let selected = gallery.expand(gallery.selection, in: entries)
        func move(_ delta: Int) -> KeyPress.Result {
            gallery.moveSelection(by: delta, order: order)
            if let id = gallery.selectionAnchor { withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(id) } }
            return .handled
        }
        switch press.key {
        case .leftArrow: return move(-1)
        case .rightArrow: return move(1)
        case .upArrow: return move(-columns)
        case .downArrow: return move(columns)
        case .space, .return:
            if gallery.selection.count == 1, let entry = entries.first(where: { gallery.selection.contains($0.id) }) {
                open(entry)
            } else if selected.count > 1 {
                withAnimation(.smooth(duration: 0.25)) { gallery.compare(selected) }
            }
            return .handled
        case .delete, .deleteForward:
            guard press.modifiers.contains(.command), !selected.isEmpty else { return .ignored }
            gallery.trashRequest = selected
            return .handled
        case .escape where isFocus:
            withAnimation(.smooth(duration: 0.3)) { studio.isFocusMode = false }
            return .handled
        case .tab where isFocus:
            // Wie in Lightroom: Tab blendet die Seitenleiste ein und aus.
            withAnimation(.smooth(duration: 0.28)) { focusShowSidebar.toggle() }
            return .handled
        default:
            break
        }
        guard !press.modifiers.contains(.command), let key = press.characters.lowercased().first else { return .ignored }
        switch key {
        case "+", "=":
            gallery.zoomGrid(by: 1.25)
            return .handled
        case "-":
            gallery.zoomGrid(by: 1 / 1.25)
            return .handled
        case "f":
            withAnimation(.smooth(duration: 0.3)) { studio.isFocusMode.toggle() }
            return .handled
        case "i" where isFocus:
            withAnimation(.smooth(duration: 0.28)) { focusShowInfo.toggle() }
            return .handled
        default:
            break
        }
        if key == "c", selected.count > 1 {
            withAnimation(.smooth(duration: 0.25)) { gallery.compare(selected) }
            return .handled
        }
        if key == "n", gallery.selection.count == 1, let id = gallery.selection.first, gallery.item(id) != nil {
            studio.showInspector = true
            gallery.noteFieldRequest += 1
            return .handled
        }
        if key == "t", !selected.isEmpty {
            studio.focusTagField()
            return .handled
        }
        return GalleryKeys.apply(key, to: selected, in: gallery) ? .handled : .ignored
    }
}

/// Tasten zum Markieren und Bewerten – gleich im Raster und im Vergleich.
enum GalleryKeys {
    @MainActor
    static func apply(_ key: Character, to ids: [UUID], in gallery: Gallery) -> Bool {
        guard !ids.isEmpty else { return false }
        switch key {
        case "p": gallery.setFlag(.pick, for: ids, toggle: false)
        case "x": gallery.setFlag(.reject, for: ids, toggle: false)
        case "u": gallery.setFlag(.none, for: ids, toggle: false)
        case "0", "1", "2", "3", "4", "5": gallery.setRating(Int(String(key)) ?? 0, for: ids, toggle: false)
        default: return false
        }
        return true
    }
}

private struct SectionHeader: View {
    let section: GallerySection
    var isFocus = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Gallery.dayTitle(section.day))
                .font(.headline)
            Text(section.imageCount == 1 ? "1 Bild" : "\(section.imageCount) Bilder")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(isFocus ? .clear : .regular, in: .capsule)
        .opacity(isFocus ? 0.8 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

// MARK: - Kachel

private struct GalleryCell: View {
    @Environment(Studio.self) private var studio
    let entry: GalleryEntry
    let isSelected: Bool
    var isFocus = false
    let onClick: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 7) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { picture }
            if !isFocus {
                footer
                    .frame(height: 16)
            }
        }
        .padding(isFocus ? 4 : 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(isFocus ? 0.3 : 0.22) : Color.primary.opacity(isHovering && !isFocus ? 0.07 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onClick)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpen))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            if hovering { studio.gallery.hoveredEntryID = entry.id } else if studio.gallery.hoveredEntryID == entry.id { studio.gallery.hoveredEntryID = nil }
        }
        .contextMenu { GalleryEntryMenu(entry: entry) }
        .onDrag {
            // Ganze Auswahl bzw. den ganzen Stapel merken – fürs Ablegen auf einem Projekt.
            let gallery = studio.gallery
            let ids = gallery.selection.contains(entry.id) ? gallery.itemIDs(for: gallery.selection) : entry.items.map(\.id)
            gallery.drag = (entry.cover.path, ids)
            return NSItemProvider(object: entry.cover.url as NSURL)
        }
        .help(help)
    }

    private var help: String {
        let date = entry.date.formatted(date: .abbreviated, time: .shortened)
        switch entry {
        case .image(let item):
            let tags = item.tags.map { $0.isEmpty ? "" : " · " + $0.joined(separator: ", ") } ?? ""
            return item.isVideo ? "Video · \(date)\(tags) · Doppelklick spielt es ab" : "\(item.source.title) · \(date)\(tags) · Doppelklick zeigt das Bild groß"
        case .stack(let stack, let members):
            return "\(stack.title) · \(members.count) Bilder · \(date) – klicken zum Auffächern"
        }
    }

    // MARK: Bild

    @ViewBuilder
    private var picture: some View {
        switch entry {
        case .image(let item):
            GalleryThumbnail(item: item, prefersFullImage: studio.gallery.thumbnailSize > 300)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .overlay(alignment: .bottomLeading) {
                    if item.isVideo { VideoBadge(item: item) }
                }
                .opacity(item.flag == .reject ? 0.35 : 1)
                .overlay(alignment: .topLeading) {
                    if item.flag == .pick { flagBadge }
                }
        case .stack(_, let members):
            StackPicture(members: members, cover: entry.cover, isHovering: isHovering)
                .overlay(alignment: .topTrailing) {
                    Label("\(members.count)", systemImage: "square.stack.fill")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                }
                .overlay(alignment: .topLeading) {
                    if members.contains(where: { $0.flag == .pick }) { flagBadge }
                }
        }
    }

    private var flagBadge: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(Color.accentColor))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .padding(5)
    }

    // MARK: Fußzeile

    @ViewBuilder
    private var footer: some View {
        let gallery = studio.gallery
        switch entry {
        case .image(let item):
            HStack(spacing: 6) {
                if item.rating > 0 || isHovering || isSelected {
                    StarRating(rating: item.rating, size: 10, subtleEmpty: true) { gallery.setRating($0, for: [item.id]) }
                }
                NoteBadge(itemIDs: [item.id])
                if let tags = item.tags, !tags.isEmpty {
                    Image(systemName: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(tags.joined(separator: ", "))
                }
                Spacer(minLength: 0)
                if isHovering || item.flag != .none {
                    FlagButtons(flag: item.flag, size: 11) { gallery.setFlag($0, for: [item.id]) }
                }
            }
        case .stack(let stack, let members):
            HStack(spacing: 6) {
                Label(stack.title, systemImage: stack.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                NoteBadge(itemIDs: members.map(\.id))
                Spacer(minLength: 0)
                let picks = members.filter { $0.flag == .pick }.count
                if picks > 0 {
                    Label("\(picks)", systemImage: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .monospacedDigit()
                }
            }
        }
    }
}

/// Gefächerter Stapel: das oberste Bild vorne, dahinter leicht verdreht die übrigen.
private struct StackPicture: View {
    let members: [GalleryItem]
    let cover: GalleryItem
    let isHovering: Bool

    private static let angles: [Double] = [0, 6, -5, 9]
    private static let offsets: [CGSize] = [.zero, CGSize(width: 7, height: -5), CGSize(width: -7, height: -7), CGSize(width: 11, height: -10)]

    var body: some View {
        let layers = [cover] + members.filter { $0.id != cover.id }.prefix(3)
        ZStack {
            ForEach(Array(layers.enumerated().reversed()), id: \.element.id) { depth, item in
                let spread = isHovering ? 1.7 : 1
                GalleryThumbnail(item: item)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        if depth > 0 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    .scaleEffect(0.84)
                    .rotationEffect(.degrees(Self.angles[depth] * spread))
                    .offset(x: Self.offsets[depth].width * spread, y: Self.offsets[depth].height * spread)
                    .opacity(item.flag == .reject && depth == 0 ? 0.5 : 1)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
    }
}

// MARK: - Kontextmenü

/// Aktionen für ein Bild oder einen Stapel – oder die ganze Auswahl, wenn die Kachel dazugehört.
struct GalleryEntryMenu: View {
    @Environment(Studio.self) private var studio
    let entry: GalleryEntry

    var body: some View {
        let gallery = studio.gallery
        let targetItems: [GalleryItem] = gallery.selection.contains(entry.id) && gallery.selection.count > 1
            ? gallery.selection
                .flatMap { id in gallery.stacks[id] != nil ? gallery.members(of: id) : gallery.item(id).map { [$0] } ?? [] }
                .sorted { $0.createdAt > $1.createdAt }
            : entry.items
        let targets = targetItems.map(\.id)

        switch entry {
        case .image(let item) where item.isVideo:
            Button("Abspielen", systemImage: "play") { withAnimation(.smooth(duration: 0.25)) { gallery.open(entry) } }
        case .image(let item):
            Button("Groß ansehen", systemImage: "eye") { withAnimation(.smooth(duration: 0.25)) { gallery.open(entry) } }
            Button("Im Studio bearbeiten", systemImage: "paintbrush.pointed") { studio.openInStudio(item, mode: .edit) }
            Button("Als Ausgangsbild für eine Serie", systemImage: "square.grid.2x2") { studio.openInStudio(item, mode: .series) }
            Menu("Als Referenz verwenden", systemImage: "photo.stack") {
                ForEach(studio.references.indices, id: \.self) { index in
                    Button("Bild \(index + 1) · \(studio.references[index].role.title)") { studio.useAsReference(item, slot: index) }
                }
            }
            Menu("In Labs verwenden", systemImage: "flask") {
                LabsSlotMenuItems { slot in studio.useInLabs(item, slot: slot) }
            }
            if !item.prompt.isEmpty {
                Button("Prompt übernehmen", systemImage: "text.quote") { studio.adoptPrompt(of: item) }
            }
        case .stack(_, let members):
            Button("Auffächern und vergleichen", systemImage: "square.grid.2x2") { withAnimation(.smooth(duration: 0.25)) { gallery.open(entry) } }
            Button("Stapel auflösen", systemImage: "square.stack.3d.down.right") { gallery.unstack(entry.id) }
            if let first = members.first, !first.prompt.isEmpty {
                Button("Prompt des ersten Bildes übernehmen", systemImage: "text.quote") { studio.adoptPrompt(of: first) }
            }
        }

        if case .image(let item) = entry {
            Button("Notiz hinzufügen …", systemImage: "note.text.badge.plus") {
                gallery.selection = [item.id]
                gallery.selectionAnchor = item.id
                studio.showInspector = true
                gallery.noteFieldRequest += 1
            }
        }
        Menu("Tags", systemImage: "tag") {
            TagMenuItems(itemIDs: targets) {
                if !gallery.selection.contains(entry.id) {
                    gallery.selection = [entry.id]
                    gallery.selectionAnchor = entry.id
                }
                studio.focusTagField()
            }
        }
        Menu("Projekt", systemImage: "folder") {
            ProjectMenuItems(itemIDs: targets)
        }
        let hasImages = targetItems.contains { !$0.isVideo }
        if hasImages {
            Menu("Story", systemImage: GalleryStory.symbol) {
                StoryMenuItems(itemIDs: targets)
            }
        }
        Menu("Charakter", systemImage: "person.crop.square") {
            if !studio.personas.personas.isEmpty {
                Section("Ist auf dem Bild") {
                    ForEach(studio.personas.personas) { persona in
                        Toggle(persona.name, isOn: Binding(
                            get: { targets.allSatisfy { gallery.item($0)?.personaIDs?.contains(persona.id) == true } },
                            set: { _ in gallery.togglePersona(persona.id, for: targets) }
                        ))
                    }
                }
                Section("Als Foto zum Charakter") {
                    ForEach(studio.personas.personas) { persona in
                        Button(persona.name) { studio.addGalleryItems(targets, toPersona: persona.id) }
                    }
                }
            }
            Button("Neuer Charakter aus \(targetItems.count == 1 ? "diesem Bild" : "diesen Bildern") …", systemImage: "plus") {
                let id = studio.personas.create()
                studio.addGalleryItems(targets, toPersona: id)
                gallery.collection = .persona(id)
                gallery.personaTab = .character
            }
        }
        if hasImages {
            Menu("Als Asset sichern", systemImage: "shippingbox") {
                SaveAsAssetMenuItems(itemIDs: targets)
            }
        }
        if case .project(let projectID) = gallery.collection, let project = gallery.project(projectID) {
            Button("Aus „\(project.name)“ entfernen", systemImage: "folder.badge.minus") {
                gallery.removeFromProject(projectID, itemIDs: targets)
            }
        }

        Divider()
        Menu("Markierung", systemImage: "flag") {
            Button("Behalten (P)", systemImage: "flag.fill") { gallery.setFlag(.pick, for: targets, toggle: false) }
            Button("Verwerfen (X)", systemImage: "xmark.circle") { gallery.setFlag(.reject, for: targets, toggle: false) }
            Button("Ohne Markierung (U)", systemImage: "flag.slash") { gallery.setFlag(.none, for: targets, toggle: false) }
        }
        Menu("Bewertung", systemImage: "star") {
            ForEach((0...5).reversed(), id: \.self) { value in
                Button(value == 0 ? "Keine Sterne (0)" : String(repeating: "★", count: value) + " (\(value))") {
                    gallery.setRating(value, for: targets, toggle: false)
                }
            }
        }
        if targetItems.count > 1 {
            Button("Vergleichen (\(targetItems.count) Bilder)", systemImage: "rectangle.split.2x2") {
                withAnimation(.smooth(duration: 0.25)) { gallery.compare(targets) }
            }
            Button("Als Stapel gruppieren", systemImage: "square.stack") { gallery.group(targets) }
        }

        Divider()
        if case .image(let item) = entry, targetItems.count == 1 {
            Button("Exportieren …", systemImage: "square.and.arrow.up") { studio.export(item) }
        }
        Button("Im Finder zeigen", systemImage: "folder") { studio.revealInFinder(targetItems) }
        OpenInAppButton(urls: targetItems.map(\.url))
        Divider()
        Button(targetItems.count == 1 ? "In den Papierkorb legen …" : "\(targetItems.count) Bilder in den Papierkorb legen …", systemImage: "trash", role: .destructive) {
            gallery.trashRequest = targets
        }
    }
}

// MARK: - Leiste

/// Schwebende Leiste unter dem Raster: Sammlung, Auswahl, Vergleichen, Filter, Kachelgröße.
private struct GalleryBar: View {
    @Environment(Studio.self) private var studio
    let entries: [GalleryEntry]

    var body: some View {
        // Schmales Fenster (Inspector offen, Auswahl): erst Titel und Beschriftungen weglassen, nie umbrechen.
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .font(.callout)
        .padding(.horizontal, 12)
    }

    private func bar(compact: Bool) -> some View {
        @Bindable var gallery = studio.gallery
        let selected = gallery.expand(gallery.selection, in: entries)
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    if !compact {
                        Label(gallery.title(for: gallery.collection), systemImage: gallery.collection.symbol)
                            .fontWeight(.medium)
                        divider
                    }
                    Text(summary(selected: selected.count))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

                if selected.count > 1 {
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { gallery.compare(selected) }
                    } label: {
                        Label("Vergleichen", systemImage: "rectangle.split.2x2")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .help("Ausgewählte Bilder nebeneinander vergleichen (C)")
                }

                HStack(spacing: 10) {
                    Toggle(isOn: $gallery.filter.showImages) {
                        if compact { Image(systemName: "photo") } else { Label("Bilder", systemImage: "photo") }
                    }
                    .help("Bilder zeigen")
                    Toggle(isOn: $gallery.filter.showVideos) {
                        if compact { Image(systemName: "video") } else { Label("Videos", systemImage: "video") }
                    }
                    .help("Videos zeigen")
                    divider
                    Toggle(isOn: $gallery.showsDates) {
                        if compact { Image(systemName: "calendar") } else { Label("Datum", systemImage: "calendar") }
                    }
                    .help("Bilder nach Tagen mit Datum gruppieren – ausgeschaltet liegen alle Kacheln am Stück")
                }
                .toggleStyle(.checkbox)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

                HStack(spacing: 12) {
                    FilterButton()
                        .fixedSize()
                    divider
                    Menu {
                        Picker("Bewertung", selection: $gallery.minRating) {
                            Text("Alle Bilder").tag(0)
                            ForEach(1...5, id: \.self) { value in
                                Text(String(repeating: "★", count: value) + (value < 5 ? " und mehr" : "")).tag(value)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(gallery.minRating == 0 ? "Alle" : "ab \(gallery.minRating) ★", systemImage: gallery.minRating == 0 ? "star" : "star.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Nur Bilder ab einer Bewertung zeigen")
                    divider
                    Image(systemName: "photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $gallery.thumbnailSize, in: Gallery.thumbnailRange)
                        .help("Kachelgröße – auch mit zwei Fingern auf dem Trackpad aufziehen oder ⌘+ / ⌘−")
                        .controlSize(.small)
                        .frame(width: compact ? 70 : 110)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 16)
    }

    private func summary(selected: Int) -> String {
        let images = entries.reduce(0) { $0 + $1.items.count }
        let videos = entries.reduce(0) { $0 + $1.items.filter(\.isVideo).count }
        if videos > 0 {
            var text = images - videos == 1 ? "1 Bild" : "\(images - videos) Bilder"
            text += videos == 1 ? " · 1 Video" : " · \(videos) Videos"
            if selected > 0 { text += " · \(selected) ausgewählt" }
            return text
        }
        let stacks = entries.filter { if case .stack = $0 { true } else { false } }.count
        var text = images == 1 ? "1 Bild" : "\(images) Bilder"
        if stacks > 0 { text += stacks == 1 ? " · 1 Stapel" : " · \(stacks) Stapel" }
        if selected > 0 { text += " · \(selected) ausgewählt" }
        return text
    }
}

// MARK: - Leer

struct GalleryEmptyState: View {
    @Environment(Studio.self) private var studio

    private var emptyText: String {
        let gallery = studio.gallery
        let title = gallery.title(for: gallery.collection)
        if gallery.filter.activeCount > 0 { return "In „\(title)“ passt nichts zu den Filtern." }
        if gallery.minRating > 0 { return "In „\(title)“ hat kein Bild \(gallery.minRating) oder mehr Sterne." }
        if gallery.collection == .recent { return "In den letzten \(Gallery.recentDays) Tagen ist kein Bild dazugekommen." }
        if case .persona = gallery.collection { return "Noch keine. Mit „Im Studio verwenden“ geht der Charakter als Person an Draw Things – jedes Bild daraus erscheint hier." }
        if case .project = gallery.collection { return "Ziehe Bilder aus „Alle Bilder“ auf das Projekt in der Seitenleiste – oder nutze „Projekt“ im Kontextmenü." }
        return "In „\(title)“ liegt noch nichts."
    }

    var body: some View {
        let gallery = studio.gallery
        if gallery.items.isEmpty {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(GemmaStyle.gradient)
                            .frame(width: 74, height: 74)
                            .shadow(color: GemmaStyle.tint.opacity(0.45), radius: 18, y: 6)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Text("Galerie")
                        .font(.system(size: 30, weight: .bold))
                    Text(gallery.isSyncing
                         ? "Die Bibliothek wird eingelesen …"
                         : "Hier landet jedes Bild, das du generierst oder bearbeitest –\nSerien liegen als Stapel zusammen.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    Button("Neues Bild", systemImage: "plus") { studio.showNewImageSheet = true }
                    Button("Zum Studio", systemImage: "sparkles") { studio.showGallery = false }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(40)
        } else if !gallery.searchText.isEmpty {
            ContentUnavailableView.search(text: gallery.searchText)
        } else {
            ContentUnavailableView {
                Label("Keine Bilder", systemImage: gallery.collection.symbol)
            } description: {
                Text(emptyText)
            } actions: {
                if gallery.filter.activeCount > 0 || gallery.minRating > 0 {
                    Button("Filter zurücksetzen") {
                        gallery.filter = GalleryFilter()
                        gallery.minRating = 0
                    }
                }
            }
        }
    }
}

/// Kleiner Hinweis an der Kachel: offene To-dos (orange) oder vorhandene Notizen.
private struct NoteBadge: View {
    @Environment(Studio.self) private var studio
    let itemIDs: [UUID]

    var body: some View {
        let gallery = studio.gallery
        let notes = itemIDs.flatMap { gallery.notes(for: $0) }
        let open = notes.filter(\.isOpenTodo).count
        if open > 0 {
            Label("\(open)", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NoteKind.todo.color)
                .monospacedDigit()
                .help(open == 1 ? "1 offenes To-do" : "\(open) offene To-dos")
        } else if !notes.isEmpty {
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(notes.count == 1 ? "1 Notiz" : "\(notes.count) Notizen")
        }
    }
}

/// „Filter“ in der Leiste: Seitenverhältnis zum An- und Abhaken, Tags und Charaktere als Dropdowns.
private struct FilterButton: View {
    @Environment(Studio.self) private var studio
    @State private var isShown = false

    var body: some View {
        let count = studio.gallery.filter.activeCount
        Button {
            isShown.toggle()
        } label: {
            Label(count == 0 ? "Filter" : "Filter (\(count))",
                  systemImage: count == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(count == 0 ? Color.primary : Color.accentColor)
        }
        .buttonStyle(.borderless)
        .help("Nach Medium, Seitenverhältnis, Tags und Charakter filtern")
        .popover(isPresented: $isShown, arrowEdge: .top) { GalleryFilterPopover() }
    }
}

private struct GalleryFilterPopover: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var gallery = studio.gallery
        let counts = gallery.aspectCounts
        let personas = studio.personas.personas
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Filter").font(.headline)
                Spacer()
                Button("Zurücksetzen") { gallery.filter = GalleryFilter() }
                    .disabled(gallery.filter.activeCount == 0)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Medien").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Toggle("Bilder", isOn: $gallery.filter.showImages)
                    Toggle("Videos (\(gallery.videoCount))", isOn: $gallery.filter.showVideos)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Seitenverhältnis").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                    let ratios = AspectRatio.all
                    ForEach(0..<((ratios.count + 1) / 2), id: \.self) { row in
                        GridRow {
                            ForEach(ratios[(row * 2)..<min(row * 2 + 2, ratios.count)]) { ratio in
                                aspectToggle(id: ratio.id, title: "\(ratio.label)  \(ratio.name)", count: counts[ratio.id] ?? 0)
                            }
                        }
                    }
                    GridRow {
                        aspectToggle(id: GalleryFilter.freeAspect, title: "Freie Formate", count: counts[GalleryFilter.freeAspect] ?? 0)
                            .help("Bilder, die zu keinem der Standardformate passen")
                    }
                }
            }

            TagFilterSection()

            if !personas.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Charaktere").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    MultiSelectDropdown(
                        title: "Charaktere", symbol: "person.crop.circle", emptyText: "Noch keine Charaktere.",
                        placeholder: "Charaktere wählen …",
                        note: "Zeigt Bilder, in die der Charakter eingeflossen ist oder denen du ihn zugeordnet hast („Charakter › Ist auf dem Bild“).",
                        options: personas.map { DropdownOption(id: $0.id, title: $0.name, count: gallery.count(.persona($0.id))) },
                        selection: $gallery.filter.personaIDs
                    ) { option in
                        if let persona = studio.personas.persona(option.id) { PersonaAvatar(persona: persona, size: 18) }
                    }
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(16)
        .frame(width: 340)
    }

    private func aspectToggle(id: String, title: String, count: Int) -> some View {
        let gallery = studio.gallery
        return Toggle(isOn: Binding(
            get: { gallery.filter.aspects.contains(id) },
            set: { on in
                if on { gallery.filter.aspects.insert(id) } else { gallery.filter.aspects.remove(id) }
            }
        )) {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .disabled(count == 0 && !gallery.filter.aspects.contains(id))
    }
}
