import SwiftUI

/// Aufgefächerter Stapel, Vergleich mehrerer Bilder oder ein einzelnes Bild groß (Lupe).
/// Drei Ansichten: Raster (alle nebeneinander), Synchron-Zoom (Zoomen und Verschieben wirkt auf alle)
/// und Blättern (ein Bild groß – Zoom und Ausschnitt bleiben beim Weiterblättern erhalten).
struct GalleryViewer: View {
    @Environment(Studio.self) private var studio
    let state: GalleryViewerState
    /// Kacheln der Galerie – die Lupe blättert mit den Pfeiltasten durch sie.
    let entries: [GalleryEntry]
    /// Fokusmodus: schwarz, ohne Leisten – nur das Bild, Aktionen per Rechtsklick.
    var isFocus = false

    @State private var unfolded = false
    /// 1 = eingepasst. Gilt für alle Bilder gleichzeitig.
    @State private var zoom: Double = 1
    /// Bildpunkt (0 … 1) in der Mitte des Ausschnitts.
    @State private var center = CGPoint(x: 0.5, y: 0.5)
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var lastDrag: CGSize = .zero
    /// Höhe der Leisten – bei schmalem Fenster brechen sie in mehrere Zeilen um, das Bild weicht ihnen aus.
    @State private var viewerWidth: CGFloat = 0
    /// Ganze Ansicht – bis an ihren Rand wächst ein einzelnes Bild beim Zoomen.
    @State private var viewerSize: CGSize = .zero
    @State private var topBarHeight: CGFloat = 0
    @State private var bottomBarHeight: CGFloat = 0
    @FocusState private var isFocused: Bool

    private let spacing: CGFloat = 18
    private let captionHeight: CGFloat = 34

    private var gallery: Gallery { studio.gallery }
    private var items: [GalleryItem] { state.displayIDs.compactMap { gallery.item($0) } }
    /// Die Bilder der aktuellen Seite – Raster, Filmstreifen und Vorladen arbeiten nur mit ihnen.
    private var pageItems: [GalleryItem] { state.pageIDs.compactMap { gallery.item($0) } }
    private var isSingle: Bool { state.isLoupe || items.count < 2 }
    private var mode: CompareMode { isSingle ? .flip : gallery.compareMode }
    private var isZoomable: Bool { mode != .grid && !(mode == .flip && current?.isVideo == true) }
    private var stack: GalleryStack? { state.stackID.flatMap { gallery.stacks[$0] } }
    private var current: GalleryItem? { state.currentID.flatMap { gallery.item($0) } }

    /// Was im Voraus geladen wird: die Seite, beim Blättern dazu das vorige und das nächste Bild.
    private var preloadIDs: [UUID] {
        var ids = state.pageIDs
        if mode == .flip {
            let all = state.displayIDs
            if all.indices.contains(state.index) {
                for neighbor in [state.index - 1, state.index + 1] where all.indices.contains(neighbor) && !ids.contains(all[neighbor]) {
                    ids.append(all[neighbor])
                }
            }
        }
        return ids
    }

    var body: some View {
        GeometryReader { proxy in
            let usual: CGFloat = isFocus ? (mode == .flip ? 24 : 70) : (mode == .flip ? 210 : 190)
            // Mehrzeilige Leisten brauchen oben und unten mehr Platz (das Bild liegt in der Mitte).
            let reserved = isFocus ? usual : max(usual, 2 * (max(topBarHeight + 14, bottomBarHeight + 18) + 20))
            let area = CGSize(width: max(proxy.size.width - (isFocus ? 24 : 80), 100), height: max(proxy.size.height - reserved, 100))
            ZStack {
                Group {
                    if isFocus { Color.black.ignoresSafeArea() } else { GalleryBackground() }
                }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if isZoomable { resetZoom() } }
                Group {
                    if mode == .flip {
                        if let current { single(current, in: area, viewport: proxy.size) }
                    } else {
                        tiles(pageItems, in: area)
                    }
                }
                .offset(y: isFocus ? 0 : -4)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .coordinateSpace(.named("viewer"))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewerWidth = $0 }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewerSize = $0 }
        .background {
            // Trackpad und Mausrad: zwei Finger verschieben, Pinch und ⌘-Scrollen zoomen.
            CanvasEventMonitor(
                isActive: true,
                onScroll: { delta, location, zoomModifier in
                    guard isZoomable else { return }
                    if zoomModifier { zoom(by: exp(delta.height * 0.01), at: location) } else { pan(by: delta) }
                },
                onMagnify: { factor, location in
                    if !isZoomable { withAnimation(.smooth(duration: 0.2)) { gallery.compareMode = .zoom } }
                    zoom(by: factor, at: location)
                },
                onSmartMagnify: { location in if isZoomable { toggleZoom(at: location) } }
            )
        }
        .gesture(panDrag, including: isZoomable && zoom > 1.001 ? .all : .subviews)
        .overlay(alignment: .top) {
            if !isFocus {
                topBar
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
                    .padding(.top, 14)
            }
        }
        .overlay(alignment: .bottom) {
            if !isFocus {
                bottomBar
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomBarHeight = $0 }
                    .padding(.bottom, 18)
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear {
            isFocused = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { unfolded = true }
        }
        .task(id: preloadIDs) {
            // Nur die Seite (höchstens neun) vorladen – der Zwischenspeicher fasst zwölf volle Bilder.
            for id in preloadIDs {
                if let item = gallery.item(id) { _ = await GalleryImages.image(for: item) }
            }
        }
        .onChange(of: state.page) {
            // Rahmen der Kacheln von der alten Seite bestimmen sonst Prozentanzeige und Zoompunkt mit.
            let onPage = Set(state.pageIDs)
            tileFrames = tileFrames.filter { onPage.contains($0.key) }
        }
        .animation(.smooth(duration: 0.3), value: mode)
        .animation(.smooth(duration: 0.3), value: state.showSource)
    }

    // MARK: Raster & Synchron-Zoom

    @ViewBuilder
    private func tiles(_ pageItems: [GalleryItem], in area: CGSize) -> some View {
        // Das Raster ist für alle Seiten gleich groß, damit die Kacheln beim Blättern nicht springen.
        let slots = min(items.count, GalleryViewerState.pageSize)
        let aspect = items.first?.aspect ?? 1
        let wide = SeriesCanvas.layout(count: slots, aspect: aspect, in: area, spacing: spacing, caption: captionHeight)
        // Unter schmalen Bildern braucht die Beschriftung zwei Zeilen.
        let captionHeight = wide.image.width < 260 ? self.captionHeight + 22 : self.captionHeight
        let layout = captionHeight == self.captionHeight
            ? wide
            : SeriesCanvas.layout(count: slots, aspect: aspect, in: area, spacing: spacing, caption: captionHeight)
        let rows = stride(from: 0, to: pageItems.count, by: layout.columns).map { Array(pageItems[$0..<min($0 + layout.columns, pageItems.count)]) }
        let rowHeight = layout.image.height + captionHeight + spacing
        // Die letzte Seite füllt die Reihen von links; der Rahmen bleibt der einer vollen Seite.
        let slotRows = Int(ceil(Double(slots) / Double(layout.columns)))
        let gridSize = CGSize(
            width: CGFloat(layout.columns) * layout.image.width + CGFloat(layout.columns - 1) * spacing,
            height: CGFloat(slotRows) * (layout.image.height + captionHeight) + CGFloat(slotRows - 1) * spacing
        )
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(rows[row].enumerated()), id: \.element.id) { column, item in
                        let indexInPage = row * layout.columns + column
                        // Versatz zur Mitte – von dort fächern die Bilder beim Öffnen auf.
                        let toCenter = CGSize(
                            width: -(CGFloat(column) - CGFloat(rows[row].count - 1) / 2) * (layout.image.width + spacing),
                            height: -(CGFloat(row) - CGFloat(rows.count - 1) / 2) * rowHeight
                        )
                        // Zustand und Tasten zählen über den ganzen Stapel, Reihe und Spalte nur auf der Seite.
                        tile(item, index: state.page * GalleryViewerState.pageSize + indexInPage, box: layout.image, captionHeight: captionHeight)
                            .modifier(UnfoldEffect(isUnfolded: unfolded, index: indexInPage, toCenter: toCenter))
                    }
                }
            }
        }
        .frame(width: gridSize.width, height: gridSize.height, alignment: .topLeading)
        .id(state.page)
        .transition(.opacity)
    }

    private func tile(_ item: GalleryItem, index: Int, box: CGSize, captionHeight: CGFloat) -> some View {
        let fit = Self.fit(item.aspect, in: box)
        let isCurrent = item.id == state.currentID && items.count > 1
        return VStack(spacing: 8) {
            ZoomableImage(item: item, size: fit, zoom: mode == .zoom ? zoom : 1, center: mode == .zoom ? center : CGPoint(x: 0.5, y: 0.5))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("viewer")) } action: { tileFrames[item.id] = $0 }
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2.5)
                        .padding(-4)
                }
                .opacity(item.flag == .reject ? 0.45 : 1)
                .contentShape(Rectangle())
                .onTapGesture { setIndex(index) }
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                    doubleClick(index: index, at: CGPoint(x: (tileFrames[item.id]?.minX ?? 0) + value.location.x, y: (tileFrames[item.id]?.minY ?? 0) + value.location.y))
                })
                .contextMenu { itemMenu(item) }
                .frame(width: box.width, height: box.height)
            ViewerCaption(item: item, isSource: isSourceItem(item), isCurrent: isCurrent)
                .frame(width: box.width, height: captionHeight - 8)
        }
    }

    // MARK: Blättern & Lupe

    @ViewBuilder
    private func single(_ item: GalleryItem, in area: CGSize, viewport: CGSize) -> some View {
        if item.isVideo {
            video(item, in: area)
        } else {
            image(item, in: area, viewport: viewport)
        }
    }

    /// Videos spielen gleich los – mit den Bedienelementen von macOS.
    private func video(_ item: GalleryItem, in area: CGSize) -> some View {
        let fit = Self.fit(item.aspect, in: area)
        return VideoPlayerView(url: item.url)
            .id(item.id)
            .frame(width: fit.width, height: fit.height)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .contextMenu { itemMenu(item) }
            .scaleEffect(unfolded ? 1 : 0.94)
            .opacity(unfolded ? 1 : 0)
    }

    private func image(_ item: GalleryItem, in area: CGSize, viewport: CGSize) -> some View {
        let fit = Self.fit(item.aspect, in: area)
        return LoupeImage(item: item, size: fit, zoom: zoom, center: center, viewport: viewport)
            // Mit der ID im Wert: Blättert man zu einem gleich großen Bild, muss sein Rahmen trotzdem eingetragen werden.
            // Eingetragen wird der eingepasste Rahmen (gleiche Mitte) – darauf beruhen Zoompunkt, Verschieben und Prozentangabe.
            .onGeometryChange(for: KeyedFrame.self) { proxy in
                let frame = proxy.frame(in: .named("viewer"))
                return KeyedFrame(id: item.id, frame: CGRect(x: frame.midX - fit.width / 2, y: frame.midY - fit.height / 2, width: fit.width, height: fit.height))
            } action: { tileFrames = [$0.id: $0.frame] }
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .opacity(item.flag == .reject ? 0.6 : 1)
            .contentShape(Rectangle())
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                toggleZoom(at: CGPoint(x: (tileFrames[item.id]?.minX ?? 0) + value.location.x, y: (tileFrames[item.id]?.minY ?? 0) + value.location.y))
            })
            .contextMenu { itemMenu(item) }
            .scaleEffect(unfolded ? 1 : 0.94)
            .opacity(unfolded ? 1 : 0)
    }

    // MARK: Leisten

    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            // Reicht die Breite nicht, wandern Ansicht und Seiten in eine zweite Zeile.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    backButton
                    titleBar
                    viewOptions
                    pagerBar
                    editButton
                }
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        backButton
                        titleBar
                        editButton
                    }
                    HStack(spacing: 10) {
                        viewOptions
                        pagerBar
                    }
                }
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        backButton
                        titleBar
                        editButton
                    }
                    viewOptions
                    pagerBar
                }
            }
        }
        .font(.callout)
    }

    private var backButton: some View {
        Button {
            close()
        } label: {
            Label("Galerie", systemImage: "chevron.left")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Zurück zur Galerie (Esc)")
    }

    private var titleBar: some View {
        title
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder
    private var viewOptions: some View {
        if !isSingle || state.sourceID != nil {
            HStack(spacing: 10) {
                if items.count > 1 {
                    Picker("Ansicht", selection: Binding(get: { gallery.compareMode }, set: { mode in
                        withAnimation(.smooth(duration: 0.3)) { gallery.compareMode = mode }
                    })) {
                        ForEach(CompareMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol)
                                .help("\(mode.title) (\(String(mode.key).uppercased()))")
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if state.sourceID != nil {
                    Button {
                        toggleSource()
                    } label: {
                        Label("Ausgangsbild", systemImage: state.showSource ? "photo.fill" : "photo")
                            .foregroundStyle(state.showSource ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.borderless)
                    .help(state.showSource ? "Ausgangsbild ausblenden" : "Ausgangsbild der Serie zum Vergleich dazunehmen")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
        }
    }

    /// Stapel und Vergleiche mit mehr als neun Bildern blättern seitenweise.
    @ViewBuilder
    private var pagerBar: some View {
        if state.pageCount > 1 {
            ViewerPager(
                page: state.page, pageCount: state.pageCount,
                firstNumber: state.page * GalleryViewerState.pageSize + 1,
                lastNumber: state.page * GalleryViewerState.pageSize + state.pageIDs.count,
                total: state.displayIDs.count,
                turn: turnPage
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder
    private var editButton: some View {
        if let current, !current.isVideo {
            Button {
                studio.openInStudio(current, mode: .edit)
            } label: {
                Label("Bearbeiten", systemImage: "paintbrush.pointed")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
            .help("Markiertes Bild im Studio bearbeiten")
        }
    }

    @ViewBuilder
    private var title: some View {
        if let stack {
            HStack(spacing: 8) {
                Label(stack.title, systemImage: stack.symbol)
                    .fontWeight(.semibold)
                Text(state.itemIDs.count == 1 ? "1 Bild" : "\(state.itemIDs.count) Bilder")
                    .foregroundStyle(.secondary)
            }
        } else if isSingle, let current {
            HStack(spacing: 8) {
                Label(current.kindTitle, systemImage: current.kindSymbol)
                    .fontWeight(.semibold)
                Text(current.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Label("Vergleich", systemImage: "rectangle.split.2x2")
                    .fontWeight(.semibold)
                Text("\(items.count) Bilder")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            if mode == .flip {
                // Neun Vorschaubilder, Beschriftung und Zoom passen nicht in jede Breite nebeneinander.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        filmstripBar
                        captionBar
                        loupeBar
                        zoomOrHintBar
                    }
                    VStack(spacing: 10) {
                        filmstripBar
                        HStack(spacing: 10) {
                            captionBar
                            loupeBar
                            zoomOrHintBar
                        }
                    }
                    VStack(spacing: 10) {
                        filmstripBar
                        HStack(spacing: 10) {
                            captionBar
                            loupeBar
                        }
                        zoomOrHintBar
                    }
                }
            } else {
                zoomOrHintBar
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var filmstripBar: some View {
        if mode == .flip, !isSingle {
            filmstrip
                .padding(6)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var captionBar: some View {
        if mode == .flip, let current {
            ViewerCaption(item: current, isSource: isSourceItem(current), isCurrent: false)
                .frame(width: 340)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder
    private var loupeBar: some View {
        if mode == .flip, state.isLoupe, entries.count > 1 {
            loupeNavigation
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder
    private var zoomOrHintBar: some View {
        if isZoomable {
            zoomControls
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        } else {
            // Schmal: zuerst die kurze Fassung, zuletzt zwei Zeilen.
            ViewThatFits(in: .horizontal) {
                Text(hint(compact: false)).fixedSize()
                Text(hint(compact: true)).fixedSize()
                Text(hint(compact: true)).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
    }

    private func hint(compact: Bool) -> String {
        let keys = "← → wählt · P behalten · X verwerfen · 1–5 Sterne"
        let base = compact || (current?.isVideo == true && mode == .flip) ? keys : "Doppelklick vergrößert · " + keys
        return state.pageCount > 1 ? base + " · Bild↑↓ Seite" : base
    }

    /// Kantenlänge der Vorschaubilder: 54 pt, bei schmalem Fenster so klein, dass alle neun der Seite in die Leiste passen.
    private var thumbSize: CGFloat {
        let count = CGFloat(max(pageItems.count, 1))
        guard viewerWidth > 0 else { return 54 }
        return min(54, max(30, ((viewerWidth - 32 - 12 - 6 * (count - 1)) / count).rounded(.down)))
    }

    private var filmstrip: some View {
        let thumb = thumbSize
        return HStack(spacing: 6) {
            ForEach(Array(pageItems.enumerated()), id: \.element.id) { offset, item in
                let index = state.page * GalleryViewerState.pageSize + offset
                let isCurrent = item.id == state.currentID
                Button {
                    setIndex(index)
                } label: {
                    GalleryThumbnail(item: item)
                        .frame(width: thumb, height: thumb)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            if let number = item.stackIndex, !isSourceItem(item) {
                                NumberBadge(number: number)
                                    .scaleEffect(0.75)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isCurrent ? Color.accentColor : .white.opacity(0.15), lineWidth: isCurrent ? 2.5 : 1)
                        }
                        .opacity(item.flag == .reject ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .help(isSourceItem(item) ? "Ausgangsbild" : item.displayTitle)
            }
        }
    }

    private var loupeNavigation: some View {
        let order = entries.map(\.cover.id)
        let position = state.currentID.flatMap { order.firstIndex(of: $0) }
        return HStack(spacing: 8) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(position == nil || position == 0)
            Text(position.map { "\($0 + 1) / \(order.count)" } ?? "–")
                .monospacedDigit()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(position == nil || position == order.count - 1)
        }
        .buttonStyle(.borderless)
    }

    private var zoomControls: some View {
        HStack(spacing: 10) {
            Button { zoom(by: 1 / 1.25, at: nil) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(zoom <= 1.001)
                .help("Verkleinern (−)")
            Text(zoomLabel)
                .monospacedDigit()
                .frame(minWidth: 48)
            Button { zoom(by: 1.25, at: nil) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Vergrößern (+)")
            Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 16)
            Button("Einpassen") { resetZoom() }
                .disabled(zoom <= 1.001)
            Button("100 %") { setActualSize() }
        }
        .buttonStyle(.borderless)
    }

    private var zoomLabel: String {
        guard let reference = referenceTile, reference.frame.width > 0 else { return "–" }
        return "\(Int((zoom * reference.frame.width / Double(reference.item.width) * 100).rounded())) %"
    }

    // MARK: Kontextmenü

    @ViewBuilder
    private func itemMenu(_ item: GalleryItem) -> some View {
        if isFocus {
            Button("Zurück zum Raster", systemImage: "square.grid.3x3") { close() }
            Divider()
        }
        if !item.isVideo {
            Button("Im Studio bearbeiten", systemImage: "paintbrush.pointed") { studio.openInStudio(item, mode: .edit) }
            Button("Als Ausgangsbild für eine Serie", systemImage: "square.grid.2x2") { studio.openInStudio(item, mode: .series) }
            if !item.prompt.isEmpty {
                Button("Prompt übernehmen", systemImage: "text.quote") { studio.adoptPrompt(of: item) }
            }
            Menu("Als Referenz verwenden", systemImage: "photo.stack") {
                ForEach(studio.references.indices, id: \.self) { index in
                    Button("Bild \(index + 1) · \(studio.references[index].role.title)") { studio.useAsReference(item, slot: index) }
                }
            }
            Menu("In Labs verwenden", systemImage: "flask") {
                LabsSlotMenuItems { slot in studio.useInLabs(item, slot: slot) }
            }
        }
        Divider()
        Menu("Markierung", systemImage: "flag") {
            Button("Behalten (P)", systemImage: "flag.fill") { gallery.setFlag(.pick, for: [item.id], toggle: false) }
            Button("Verwerfen (X)", systemImage: "xmark.circle") { gallery.setFlag(.reject, for: [item.id], toggle: false) }
            Button("Ohne Markierung (U)", systemImage: "flag.slash") { gallery.setFlag(.none, for: [item.id], toggle: false) }
        }
        Menu("Bewertung", systemImage: "star") {
            ForEach((0...5).reversed(), id: \.self) { value in
                Button(value == 0 ? "Keine Sterne (0)" : String(repeating: "★", count: value) + " (\(value))") {
                    gallery.setRating(value, for: [item.id], toggle: false)
                }
            }
        }
        Menu("Tags", systemImage: "tag") {
            TagMenuItems(itemIDs: [item.id]) {
                if let index = state.displayIDs.firstIndex(of: item.id) { gallery.viewer?.index = index }
                studio.focusTagField()
            }
        }
        Menu("Projekt", systemImage: "folder") {
            ProjectMenuItems(itemIDs: [item.id])
        }
        if !item.isVideo {
            Menu("Story", systemImage: GalleryStory.symbol) {
                StoryMenuItems(itemIDs: [item.id])
            }
        }
        if !item.isVideo {
            Menu("Als Asset sichern", systemImage: "shippingbox") {
                SaveAsAssetMenuItems(itemIDs: [item.id])
            }
        }
        Divider()
        Button("Exportieren …", systemImage: "square.and.arrow.up") { studio.export(item) }
        Button("Im Finder zeigen", systemImage: "folder") { studio.revealInFinder([item]) }
        OpenInAppButton(urls: [item.url])
        if item.stackID != nil, !isSourceItem(item) {
            Divider()
            Button("Aus dem Stapel lösen", systemImage: "square.stack.3d.down.right") {
                gallery.removeFromStack(item.id)
                gallery.viewer?.itemIDs.removeAll { $0 == item.id }
                if gallery.viewer?.itemIDs.isEmpty == true { gallery.closeViewer() }
            }
        }
        Divider()
        Button("In den Papierkorb legen …", systemImage: "trash", role: .destructive) { gallery.trashRequest = [item.id] }
    }

    // MARK: Steuerung

    private func isSourceItem(_ item: GalleryItem) -> Bool {
        state.showSource && item.id == state.sourceID
    }

    private func setIndex(_ index: Int) {
        gallery.viewer?.index = index
        isFocused = true
    }

    private func toggleSource() {
        guard var viewer = gallery.viewer, viewer.sourceID != nil else { return }
        viewer.showSource.toggle()
        viewer.index = max(viewer.index + (viewer.showSource ? 1 : -1), 0)
        withAnimation(.smooth(duration: 0.3)) { gallery.viewer = viewer }
    }

    private func close() {
        withAnimation(.smooth(duration: 0.22)) { unfolded = false }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.smooth(duration: 0.22)) { gallery.closeViewer() }
        }
    }

    /// Pfeiltasten: in der Lupe durch die Galerie, sonst durch die Bilder des Vergleichs.
    private func step(_ delta: Int) {
        if state.isLoupe {
            let order = entries.map(\.cover.id)
            guard let id = state.currentID, let position = order.firstIndex(of: id) else { return }
            let next = position + delta
            guard order.indices.contains(next) else { return }
            gallery.viewer?.itemIDs = [order[next]]
            gallery.lastViewedEntryID = entries[next].id
            gallery.selection = [entries[next].id]
            gallery.selectionAnchor = entries[next].id
        } else {
            let next = min(max(state.index + delta, 0), items.count - 1)
            let samePage = next / GalleryViewerState.pageSize == state.page
            withAnimation(samePage ? nil : .smooth(duration: 0.3)) { gallery.viewer?.index = next }
        }
    }

    /// Pager und Tasten: eine Seite weiter oder zurück, markiert wird das erste Bild der Seite.
    private func turnPage(_ delta: Int) {
        let target = state.page + delta
        guard (0..<state.pageCount).contains(target) else { return }
        withAnimation(.smooth(duration: 0.3)) { gallery.viewer?.setPage(target) }
    }

    private func doubleClick(index: Int, at point: CGPoint) {
        if mode == .grid {
            gallery.viewer?.index = index
            withAnimation(.smooth(duration: 0.3)) { gallery.compareMode = .flip }
        } else {
            toggleZoom(at: point)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape:
            close()
            return .handled
        case .pageUp where state.pageCount > 1:
            turnPage(-1)
            return .handled
        case .pageDown where state.pageCount > 1:
            turnPage(1)
            return .handled
        case .leftArrow where press.modifiers.contains(.command) && state.pageCount > 1:
            turnPage(-1)
            return .handled
        case .rightArrow where press.modifiers.contains(.command) && state.pageCount > 1:
            turnPage(1)
            return .handled
        case .leftArrow, .upArrow:
            step(-1)
            return .handled
        case .rightArrow, .downArrow:
            step(1)
            return .handled
        case .space:
            if state.isLoupe { close() } else { step(1) }
            return .handled
        default:
            break
        }
        guard !press.modifiers.contains(.command), let key = press.characters.lowercased().first else { return .ignored }
        switch key {
        case "+", "=":
            if !isZoomable { gallery.compareMode = .zoom }
            zoom(by: 1.25, at: nil)
            return .handled
        case "-":
            zoom(by: 1 / 1.25, at: nil)
            return .handled
        default:
            break
        }
        if key == "n", state.currentID != nil {
            studio.showInspector = true
            gallery.noteFieldRequest += 1
            return .handled
        }
        if key == "t", state.currentID != nil {
            studio.focusTagField()
            return .handled
        }
        if !isSingle, let mode = CompareMode.allCases.first(where: { $0.key == key }) {
            withAnimation(.smooth(duration: 0.3)) { gallery.compareMode = mode }
            return .handled
        }
        return GalleryKeys.apply(key, to: state.currentID.map { [$0] } ?? [], in: gallery) ? .handled : .ignored
    }

    // MARK: Zoomen

    /// Bild, an dem sich Prozentangabe und Verschieben orientieren: das markierte, sonst das erste.
    private var referenceTile: (item: GalleryItem, frame: CGRect)? {
        let candidates = [state.currentID].compactMap { $0 } + state.pageIDs
        for id in candidates {
            if let frame = tileFrames[id], let item = gallery.item(id) { return (item: item, frame: frame) }
        }
        return nil
    }

    private var maxZoom: Double {
        guard let reference = referenceTile, reference.frame.width > 0 else { return 8 }
        return max(Double(reference.item.width) / reference.frame.width * 4, 2)
    }

    /// Zoomen um einen Punkt (Ansichtskoordinaten) – der Bildpunkt darunter bleibt stehen, in allen Bildern.
    private func zoom(by factor: Double, at point: CGPoint?) {
        let old = zoom
        let new = min(max(old * factor, 1), maxZoom)
        guard new != old else { return }
        // Ein einzelnes Bild ragt beim Zoomen über seinen eingepassten Rahmen hinaus – dort zählt jeder Punkt.
        let anchor = mode == .flip ? tileFrames.values.first : point.flatMap { point in tileFrames.values.first { $0.contains(point) } }
        if let point, let frame = anchor, frame.width > 0 {
            let fx = (point.x - frame.midX) / frame.width
            let fy = (point.y - frame.midY) / frame.height
            let u = center.x + fx / old
            let v = center.y + fy / old
            center = CGPoint(x: u - fx / new, y: v - fy / new)
        }
        zoom = new
        clampCenter()
    }

    private func pan(by delta: CGSize) {
        guard zoom > 1.001, let frame = referenceTile?.frame, frame.width > 0 else { return }
        center.x -= delta.width / (frame.width * zoom)
        center.y -= delta.height / (frame.height * zoom)
        clampCenter()
    }

    private func clampCenter() {
        var half = CGSize(width: 0.5 / zoom, height: 0.5 / zoom)
        // Ein einzelnes Bild zeigt so viel, wie in die ganze Ansicht passt – verschieben lässt es sich erst, wenn es größer ist.
        if mode == .flip, let frame = referenceTile?.frame, frame.width > 0, frame.height > 0 {
            half = CGSize(
                width: min(max(viewerSize.width, frame.width) / (frame.width * zoom), 1) / 2,
                height: min(max(viewerSize.height, frame.height) / (frame.height * zoom), 1) / 2
            )
        }
        center = CGPoint(x: min(max(center.x, half.width), 1 - half.width), y: min(max(center.y, half.height), 1 - half.height))
    }

    private func resetZoom() {
        withAnimation(.smooth(duration: 0.3)) {
            zoom = 1
            center = CGPoint(x: 0.5, y: 0.5)
        }
    }

    /// Eingepasst ↔ 100 % (mindestens doppelt) – an der geklickten Stelle.
    private func toggleZoom(at point: CGPoint) {
        if zoom > 1.001 {
            resetZoom()
        } else {
            guard let reference = referenceTile, reference.frame.width > 0 else { return }
            let target = max(Double(reference.item.width) / reference.frame.width, 2)
            withAnimation(.smooth(duration: 0.3)) { zoom(by: target, at: point) }
        }
    }

    private func setActualSize() {
        guard let reference = referenceTile, reference.frame.width > 0 else { return }
        let target = Double(reference.item.width) / reference.frame.width
        withAnimation(.smooth(duration: 0.3)) { zoom(by: target / zoom, at: nil) }
    }

    private var panDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                pan(by: CGSize(width: value.translation.width - lastDrag.width, height: value.translation.height - lastDrag.height))
                lastDrag = value.translation
            }
            .onEnded { _ in lastDrag = .zero }
    }

    static func fit(_ aspect: Double, in box: CGSize) -> CGSize {
        let width = min(box.width, box.height * aspect)
        return CGSize(width: max(width, 1), height: max(width / aspect, 1))
    }
}

// MARK: - Bausteine

private struct KeyedFrame: Equatable {
    let id: UUID
    let frame: CGRect
}

/// Bild in einem festen Rahmen, vergrößert und verschoben um einen gemeinsamen Mittelpunkt.
private struct ZoomableImage: View {
    let item: GalleryItem
    let size: CGSize
    let zoom: Double
    let center: CGPoint

    var body: some View {
        let display = CGSize(width: size.width * zoom, height: size.height * zoom)
        let pixelScale = display.width / Double(max(item.width, 1))
        GalleryFullImage(item: item, interpolation: pixelScale > 2.5 ? .none : .high)
            .id(item.id)
            .frame(width: display.width, height: display.height)
            .offset(x: (0.5 - center.x) * display.width, y: (0.5 - center.y) * display.height)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Ein Bild allein (Lupe, Blättern): wächst beim Zoomen über seinen Rahmen hinaus bis an den Rand der Ansicht –
/// erst dort wird beschnitten. Im Vergleich bleiben die Rahmen fest (`ZoomableImage`).
private struct LoupeImage: View {
    let item: GalleryItem
    /// Eingepasste Größe.
    let size: CGSize
    let zoom: Double
    let center: CGPoint
    let viewport: CGSize

    var body: some View {
        let display = CGSize(width: size.width * zoom, height: size.height * zoom)
        let window = CGSize(width: min(display.width, max(viewport.width, size.width)), height: min(display.height, max(viewport.height, size.height)))
        let pixelScale = display.width / Double(max(item.width, 1))
        GalleryFullImage(item: item, interpolation: pixelScale > 2.5 ? .none : .high)
            .id(item.id)
            .frame(width: display.width, height: display.height)
            .offset(x: (0.5 - center.x) * display.width, y: (0.5 - center.y) * display.height)
            .frame(width: window.width, height: window.height)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Beschriftung unter einem Bild: Nummer und Variante, Sterne, Markierung.
private struct ViewerCaption: View {
    @Environment(Studio.self) private var studio
    let item: GalleryItem
    let isSource: Bool
    let isCurrent: Bool

    private var title: some View {
        HStack(spacing: 8) {
            if isSource {
                Label("Ausgangsbild", systemImage: "photo")
                    .font(.callout.weight(.semibold))
            } else {
                if let number = item.stackIndex {
                    NumberBadge(number: number)
                }
                if let title = item.captionTitle {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                        .help(item.prompt.isEmpty ? title : item.prompt)
                }
            }
        }
    }

    var body: some View {
        // Schmale Kacheln: Sterne und Markierung in eine zweite Zeile.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                title
                Spacer(minLength: 6)
                controls
            }
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    title
                    Spacer(minLength: 0)
                }
                HStack {
                    controls
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var controls: some View {
        let gallery = studio.gallery
        return HStack(spacing: 8) {
            StarRating(rating: item.rating, size: 11) { gallery.setRating($0, for: [item.id]) }
            FlagButtons(flag: item.flag, size: 12) { gallery.setFlag($0, for: [item.id]) }
        }
        .fixedSize()
    }
}

/// „‹  Seite 2 von 5 · Bild 10–18 von 41  ›“ – blättert die Seiten eines großen Stapels.
private struct ViewerPager: View {
    let page: Int
    let pageCount: Int
    let firstNumber: Int
    let lastNumber: Int
    let total: Int
    let turn: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { turn(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(page == 0)
                .help("Vorige Seite (Bild↑ oder ⌘←)")
                .accessibilityLabel("Vorige Seite")
            Text("Seite \(page + 1) von \(pageCount) · Bild \(firstNumber)–\(lastNumber) von \(total)")
                .monospacedDigit()
                .lineLimit(1)
            Button { turn(1) } label: { Image(systemName: "chevron.right") }
                .disabled(page >= pageCount - 1)
                .help("Nächste Seite (Bild↓ oder ⌘→)")
                .accessibilityLabel("Nächste Seite")
        }
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

/// Beim Öffnen liegen die Bilder als Stapel in der Mitte und fächern dann zu ihren Plätzen auf.
private struct UnfoldEffect: ViewModifier {
    let isUnfolded: Bool
    let index: Int
    let toCenter: CGSize

    private static let angles: [Double] = [-5, 4, -2, 7, -6, 3, -3, 5]

    func body(content: Content) -> some View {
        content
            .scaleEffect(isUnfolded ? 1 : 0.55)
            .rotationEffect(.degrees(isUnfolded ? 0 : Self.angles[index % Self.angles.count]))
            .offset(
                x: isUnfolded ? 0 : toCenter.width + CGFloat(index) * 6,
                y: isUnfolded ? 0 : toCenter.height - CGFloat(index) * 5
            )
            .zIndex(isUnfolded ? 0 : Double(-index))
    }
}
