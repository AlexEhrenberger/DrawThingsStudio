import SwiftUI

enum StoryTab: String, CaseIterable, Identifiable {
    case board, video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "Storyboard"
        case .video: "Video"
        }
    }

    var symbol: String {
        switch self {
        case .board: "square.grid.2x2"
        case .video: "film"
        }
    }
}

/// Seite einer Story: oben Name, Umschalter Storyboard · Video und „Präsentieren“.
/// Storyboard = die Bilder in ihrer Reihenfolge (ziehen zum Umsortieren, zoomen wie in der Galerie),
/// Video = Gemma schreibt aus je zwei benachbarten Bildern den Prompt für einen Clip.
struct StoryPage: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID
    @AppStorage("story.tab") private var tab: StoryTab = .board
    @State private var showPicker = false

    var body: some View {
        let gallery = studio.gallery
        if let story = gallery.story(storyID) {
            let items = gallery.storyItems(storyID)
            VStack(spacing: 0) {
                header(story, items: items)
                Group {
                    switch tab {
                    case .board:
                        if items.isEmpty { emptyState } else { StoryBoard(storyID: storyID, items: items) }
                    case .video:
                        StoryVideoView(storyID: storyID)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sheet(isPresented: $showPicker) {
                LibraryPicker(title: "Bild zur Story hinzufügen", subtitle: "Kommt ans Ende von „\(story.name)“") { item in
                    if gallery.addToStory(storyID, itemIDs: [item.id]) == 0 {
                        studio.errorMessage = "Das Bild steht schon in der Story."
                    }
                }
            }
        } else {
            ContentUnavailableView("Story nicht gefunden", systemImage: GalleryStory.symbol)
        }
    }

    // MARK: Kopf

    private func header(_ story: GalleryStory, items: [GalleryItem]) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(story.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Text(subtitle(story, items: items))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            Picker("Ansicht", selection: $tab) {
                ForEach(StoryTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Storyboard: Reihenfolge und Zoom · Video: Gemma schreibt die Clips")
            Button {
                showPicker = true
            } label: {
                Image(systemName: "photo.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Bild aus der Bibliothek ans Ende der Story hängen – oder Bilder aus der Galerie auf die Story in der Seitenleiste ziehen")
            PresentButton(storyID: storyID)
                .disabled(items.isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func subtitle(_ story: GalleryStory, items: [GalleryItem]) -> String {
        guard !items.isEmpty else { return "Noch leer" }
        var parts = [items.count == 1 ? "1 Bild" : "\(items.count) Bilder"]
        let clips = max(items.count - 1, 0)
        if clips > 0 {
            let transitions = studio.gallery.storyTransitions(storyID)
            let written = transitions.filter { !(story.video.clip(from: $0.from.id, to: $0.to.id)?.prompt.trimmed.isEmpty ?? true) }.count
            parts.append(clips == 1 ? "1 Clip" : "\(clips) Clips")
            parts.append(written == clips ? "alle Prompts geschrieben" : "\(written) von \(clips) Prompts")
        }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Noch keine Bilder", systemImage: GalleryStory.symbol)
        } description: {
            Text("Zieh Bilder aus der Galerie auf die Story in der Seitenleiste oder nutze „Story“ im Kontextmenü. Sie kommen in der Reihenfolge, in der sie entstanden sind – danach ordnest du sie hier durch Ziehen.")
        } actions: {
            Button("Bild aus der Bibliothek …", systemImage: "photo.badge.plus") { showPicker = true }
            Button("Zur Galerie", systemImage: "photo.on.rectangle") { studio.gallery.collection = .all }
        }
    }
}

// MARK: - Präsentieren

/// „Präsentieren“: Klick startet mit der zuletzt gewählten Art, der Pfeil daneben bietet alle sechs.
struct PresentButton: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID
    @AppStorage("story.presentLayout") private var layoutRaw = PresentationLayout.single.rawValue
    @AppStorage("story.presentFullScreen") private var fullScreen = true

    var body: some View {
        let layout = PresentationLayout(rawValue: layoutRaw) ?? .single
        Menu {
            PresentMenuItems(storyID: storyID)
        } label: {
            Label("Präsentieren", systemImage: "play.fill")
                .labelStyle(.titleAndIcon)
        } primaryAction: {
            studio.present(storyID, layout: layout, fullScreen: fullScreen)
        }
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .fixedSize()
        .help("Präsentieren – \(fullScreen ? "Vollbild" : "im Fenster"), \(layout.title) (⌥⌘P). Der Pfeil bietet alle Arten.")
    }
}

/// Vollbild oder Fenster, je mit einem Bild oder einem Raster aus 2 bzw. 4 Bildern.
struct PresentMenuItems: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID
    var from = 0

    var body: some View {
        Section("Vollbild") {
            ForEach(PresentationLayout.allCases) { layout in
                Button(layout.title, systemImage: layout.symbol) {
                    studio.present(storyID, layout: layout, fullScreen: true, from: from)
                }
            }
        }
        Section("Im Fenster") {
            ForEach(PresentationLayout.allCases) { layout in
                Button(layout.title, systemImage: layout.symbol) {
                    studio.present(storyID, layout: layout, fullScreen: false, from: from)
                }
            }
        }
    }
}

/// Einträge „Story ›“ – in Kontextmenüs der Galerie: anhängen, entfernen, neue Story.
struct StoryMenuItems: View {
    @Environment(Studio.self) private var studio
    let itemIDs: [UUID]

    var body: some View {
        let gallery = studio.gallery
        let images = itemIDs.filter { gallery.item($0)?.isVideo == false }
        ForEach(gallery.stories) { story in
            let contains = !images.isEmpty && images.allSatisfy { gallery.storyMembers[story.id]?.contains($0) == true }
            Button(story.name, systemImage: contains ? "checkmark" : GalleryStory.symbol) {
                if contains {
                    gallery.removeFromStory(story.id, itemIDs: images)
                } else {
                    gallery.addToStory(story.id, itemIDs: images)
                }
            }
        }
        if !gallery.stories.isEmpty { Divider() }
        Button("Neue Story …", systemImage: "plus") {
            gallery.createStory(itemIDs: images)
        }
        if images.isEmpty {
            Text("Videos gehören nicht in eine Story")
        }
    }
}

// MARK: - Storyboard

/// Wer gerade aus dem Storyboard gezogen wird – mit Zeitpunkt, damit ein abgebrochenes Ziehen
/// keine spätere Ablage (z. B. aus dem Finder) für ein Umsortieren hält.
private struct StoryDrag: Equatable {
    let id: UUID
    let started: Date

    var isFresh: Bool { Date().timeIntervalSince(started) < 60 }
}

/// Die Bilder der Story als Raster in ihrer Reihenfolge. Zoomen wie in der Galerie (Pinch, + / −, Regler),
/// Ziehen sortiert um, ⌘← / ⌘→ schiebt die Auswahl, ⌫ nimmt sie aus der Story.
private struct StoryBoard: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID
    let items: [GalleryItem]

    @FocusState private var isFocused: Bool
    @State private var drag: StoryDrag?
    @State private var width: CGFloat = 800
    @State private var height: CGFloat = 600
    @State private var pinchAnchor: CGFloat = 0.5

    private let spacing: CGFloat = 12
    private let padding: CGFloat = 22

    var body: some View {
        let gallery = studio.gallery
        let size = gallery.thumbnailSize
        let order = items.map(\.id)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: size, maximum: size * 1.5), spacing: spacing)],
                    alignment: .leading,
                    spacing: spacing
                ) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        StoryCell(
                            item: item,
                            number: index + 1,
                            count: items.count,
                            isSelected: gallery.selection.contains(item.id),
                            onClick: { click(item, order: order) },
                            onOpen: { open(item) }
                        )
                        .id(item.id)
                        .onDrag {
                            drag = StoryDrag(id: item.id, started: .now)
                            // Für das Ablegen auf einem Projekt oder einer anderen Story in der Seitenleiste.
                            gallery.drag = (item.path, gallery.selection.contains(item.id) ? order.filter(gallery.selection.contains) : [item.id])
                            return NSItemProvider(object: item.url as NSURL)
                        }
                        .onDrop(of: [.fileURL], delegate: StoryReorderDrop(target: item.id, storyID: storyID, gallery: gallery, drag: $drag))
                        .contextMenu { StoryCellMenu(storyID: storyID, item: item, index: index, order: order) }
                    }
                }
                .animation(.smooth(duration: 0.25), value: order)
                .padding(.horizontal, padding)
                .padding(.top, 6)
                .padding(.bottom, 100)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                gallery.selection = []
                drag = nil
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: {
                width = $0.width
                height = $0.height
            }
            .background {
                CanvasEventMonitor(isActive: true, onScroll: nil, onMagnify: { factor, location in
                    pinchAnchor = height > 0 ? min(max(location.y / height, 0), 1) : 0.5
                    gallery.zoomGrid(by: factor)
                })
            }
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
                if let id = gallery.lastViewedEntryID, order.contains(id) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .overlay(alignment: .bottom) {
            StoryBar(storyID: storyID, count: items.count)
                .padding(.bottom, 18)
        }
    }

    private var columns: Int {
        max(Int((width - padding * 2 + spacing) / (studio.gallery.thumbnailSize + spacing)), 1)
    }

    private func click(_ item: GalleryItem, order: [UUID]) {
        drag = nil
        studio.gallery.click(item.id, order: order, modifiers: NSEvent.modifierFlags)
        isFocused = true
    }

    private func open(_ item: GalleryItem) {
        withAnimation(.smooth(duration: 0.25)) { studio.gallery.open(.image(item)) }
    }

    private func handleKey(_ press: KeyPress, order: [UUID], proxy: ScrollViewProxy) -> KeyPress.Result {
        let gallery = studio.gallery
        let selected = order.filter(gallery.selection.contains)
        func move(_ delta: Int) -> KeyPress.Result {
            if press.modifiers.contains(.command) {
                // ⌘ + Pfeil: die Auswahl in der Story verschieben.
                guard !selected.isEmpty else { return .ignored }
                withAnimation(.smooth(duration: 0.25)) { gallery.moveStoryItems(storyID, itemIDs: Set(selected), by: delta) }
                if let id = selected.first { withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(id) } }
                return .handled
            }
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
            guard let id = selected.first, let item = gallery.item(id) else { return .ignored }
            open(item)
            return .handled
        case .delete, .deleteForward:
            guard !selected.isEmpty else { return .ignored }
            if press.modifiers.contains(.command) {
                gallery.trashRequest = selected
            } else {
                withAnimation(.smooth(duration: 0.25)) { gallery.removeFromStory(storyID, itemIDs: selected) }
            }
            return .handled
        case .escape:
            gallery.selection = []
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
        default:
            return GalleryKeys.apply(key, to: selected, in: gallery) ? .handled : .ignored
        }
    }
}

/// Umsortieren beim Ziehen: Sobald das gezogene Bild über einem anderen steht, nimmt es dessen Platz ein.
private struct StoryReorderDrop: DropDelegate {
    let target: UUID
    let storyID: UUID
    let gallery: Gallery
    @Binding var drag: StoryDrag?

    func validateDrop(info: DropInfo) -> Bool {
        drag?.isFresh == true
    }

    func dropEntered(info: DropInfo) {
        guard let drag, drag.isFresh, drag.id != target else { return }
        withAnimation(.smooth(duration: 0.25)) { gallery.moveStoryItem(storyID, item: drag.id, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: drag?.isFresh == true ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag = nil
        gallery.drag = nil
        return true
    }
}

/// Kachel im Storyboard: Bild mit Nummer – Bild 1 ist der Anfang, das letzte das Ende.
private struct StoryCell: View {
    @Environment(Studio.self) private var studio
    let item: GalleryItem
    let number: Int
    let count: Int
    let isSelected: Bool
    let onClick: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        let gallery = studio.gallery
        VStack(spacing: 7) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GalleryThumbnail(item: item, prefersFullImage: gallery.thumbnailSize > 300)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        .opacity(item.flag == .reject ? 0.35 : 1)
                }
                .overlay(alignment: .topLeading) { badge }
            HStack(spacing: 6) {
                Text(role ?? "Bild \(number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(role == nil ? Color.secondary : Color.accentColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.rating > 0 || isHovering || isSelected {
                    StarRating(rating: item.rating, size: 10, subtleEmpty: true) { gallery.setRating($0, for: [item.id]) }
                }
            }
            .frame(height: 16)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(isHovering ? 0.07 : 0))
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
            if hovering { gallery.hoveredEntryID = item.id } else if gallery.hoveredEntryID == item.id { gallery.hoveredEntryID = nil }
        }
        .help("Bild \(number) von \(count) · Ziehen ändert die Reihenfolge · Doppelklick zeigt es groß")
    }

    private var role: String? {
        if number == 1 { return count == 1 ? "Bild 1" : "Anfang" }
        if number == count { return "Ende" }
        return nil
    }

    private var badge: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 22)
            .background(Capsule().fill(role == nil ? AnyShapeStyle(Color.black.opacity(0.6)) : AnyShapeStyle(Color.accentColor)))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .padding(6)
    }
}

/// Rechtsklick auf ein Bild im Storyboard – gilt für die ganze Auswahl, wenn das Bild dazugehört.
private struct StoryCellMenu: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID
    let item: GalleryItem
    let index: Int
    let order: [UUID]

    var body: some View {
        let gallery = studio.gallery
        let targets = gallery.selection.contains(item.id) ? order.filter(gallery.selection.contains) : [item.id]
        let isFirst = targets.first == order.first
        let isLast = targets.last == order.last
        Button("Groß ansehen", systemImage: "eye") {
            withAnimation(.smooth(duration: 0.25)) { gallery.open(.image(item)) }
        }
        Menu("Ab hier präsentieren", systemImage: "play") {
            PresentMenuItems(storyID: storyID, from: index)
        }
        Divider()
        Button("An den Anfang", systemImage: "arrow.left.to.line") {
            withAnimation(.smooth(duration: 0.25)) { gallery.moveStoryItems(storyID, itemIDs: Set(targets), toStart: true) }
        }
        .disabled(isFirst && targets.count == 1)
        Button("Eins nach vorne (⌘←)", systemImage: "arrow.left") {
            withAnimation(.smooth(duration: 0.25)) { gallery.moveStoryItems(storyID, itemIDs: Set(targets), by: -1) }
        }
        .disabled(isFirst)
        Button("Eins nach hinten (⌘→)", systemImage: "arrow.right") {
            withAnimation(.smooth(duration: 0.25)) { gallery.moveStoryItems(storyID, itemIDs: Set(targets), by: 1) }
        }
        .disabled(isLast)
        Button("Ans Ende", systemImage: "arrow.right.to.line") {
            withAnimation(.smooth(duration: 0.25)) { gallery.moveStoryItems(storyID, itemIDs: Set(targets), toStart: false) }
        }
        .disabled(isLast && targets.count == 1)
        Divider()
        Button("Bild kopieren", systemImage: "doc.on.doc") { studio.copyStoryImage(item) }
        Button("Im Studio bearbeiten", systemImage: "paintbrush.pointed") { studio.openInStudio(item, mode: .edit) }
        Button("Im Finder zeigen", systemImage: "folder") { studio.revealInFinder(targets.compactMap { gallery.item($0) }) }
        OpenInAppButton(urls: targets.compactMap { gallery.item($0)?.url })
        Divider()
        Button(targets.count == 1 ? "Aus der Story nehmen" : "\(targets.count) Bilder aus der Story nehmen", systemImage: "minus.circle") {
            withAnimation(.smooth(duration: 0.25)) { gallery.removeFromStory(storyID, itemIDs: targets) }
        }
    }
}

/// Schwebende Leiste unter dem Storyboard: Anzahl, Reihenfolge umdrehen, Kachelgröße.
private struct StoryBar: View {
    @Environment(Studio.self) private var studio
    let storyID: UUID
    let count: Int

    var body: some View {
        @Bindable var gallery = studio.gallery
        let selected = gallery.selection.count
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Text((count == 1 ? "1 Bild" : "\(count) Bilder") + (selected > 0 ? " · \(selected) ausgewählt" : "") + " · ziehen zum Umsortieren")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)

                Button {
                    withAnimation(.smooth(duration: 0.3)) { gallery.reverseStory(storyID) }
                } label: {
                    Label("Umdrehen", systemImage: "arrow.left.arrow.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
                .help("Reihenfolge umdrehen – das Ende wird der Anfang")
                .disabled(count < 2)

                HStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $gallery.thumbnailSize, in: Gallery.thumbnailRange)
                        .help("Kachelgröße – auch mit zwei Fingern auf dem Trackpad aufziehen oder ⌘+ / ⌘−")
                        .controlSize(.small)
                        .frame(width: 110)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
    }
}
