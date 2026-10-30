import SwiftUI
import UniformTypeIdentifiers

/// Asset-Baukasten in der Galerie: Kleidung, Schuhe, Orte … als Bilder, nach Kategorien.
/// Bilder aus dem Finder oder der Galerie hierher ziehen – Gemma beschreibt sie passend zur Kategorie.
struct AssetBrowser: View {
    /// Was die Seite zeigt: alle Assets, einen Bereich oder eine Kategorie.
    enum Scope: Hashable {
        case all
        case section(String)
        case category(String)
    }

    @Environment(Studio.self) private var studio
    let scope: Scope

    @State private var isDropTargeted = false
    @State private var previewID: UUID?
    @State private var pendingDelete: Asset?

    /// Wohin Bilder fallen, die auf die Seite gezogen werden.
    private var dropCategoryID: String? {
        let store = studio.assets
        switch scope {
        case .category(let id): return id
        case .section(let id): return store.categories(in: id).first?.id
        case .all: return store.categories.first?.id
        }
    }

    var body: some View {
        let store = studio.assets
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                switch scope {
                case .category(let id):
                    if let category = store.category(id) {
                        AssetGrid(assets: store.assets(in: id), category: category, onPreview: { previewID = $0 }, onDelete: { pendingDelete = $0 })
                    }
                case .section(let id):
                    // Auch leere Kategorien – damit man hineinziehen kann.
                    ForEach(store.categories(in: id)) { category in
                        categoryBlock(category, showsEmpty: true)
                    }
                    if store.categories(in: id).isEmpty {
                        Text("Noch keine Kategorien – lege mit „Neue Kategorie“ eine an.")
                            .foregroundStyle(.secondary)
                    }
                case .all:
                    ForEach(store.sections) { section in
                        let filled = store.categories(in: section.id).filter { store.count(in: $0.id) > 0 }
                        if !filled.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Button {
                                    studio.gallery.collection = .assetSection(section.id)
                                } label: {
                                    Label(section.name, systemImage: section.icon)
                                        .font(.title2.weight(.bold))
                                }
                                .buttonStyle(.plain)
                                ForEach(filled) { category in
                                    categoryBlock(category, showsEmpty: false)
                                }
                            }
                        }
                    }
                    if store.assets.isEmpty {
                        emptyHint
                    }
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = nil }
        .overlay {
            if isDropTargeted, let id = dropCategoryID, let category = store.category(id) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(10)
                    .overlay {
                        Label("Zu „\(category.name)“ hinzufügen", systemImage: category.icon)
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            guard let id = dropCategoryID else { return false }
            return AssetDrop.handle(providers, categoryID: id, studio: studio)
        }
        .overlay {
            if let id = previewID, let asset = store.asset(id) {
                AssetPreview(asset: asset) { withAnimation(.smooth(duration: 0.2)) { previewID = nil } }
                    .transition(.opacity)
            }
        }
        .confirmationDialog(
            "„\(pendingDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Asset löschen", role: .destructive) {
                if let asset = pendingDelete { studio.deleteAssets([asset.id]) }
                pendingDelete = nil
            }
        } message: {
            Text("Die Kopie in der Bibliothek wird gelöscht. Bilder in der Galerie bleiben.")
        }
    }

    /// Überschrift einer Kategorie (führt zu ihrer Seite) und ihr Raster.
    private func categoryBlock(_ category: AssetCategory, showsEmpty: Bool) -> some View {
        let store = studio.assets
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                studio.gallery.collection = .assets(category.id)
            } label: {
                HStack(spacing: 8) {
                    Label(category.name, systemImage: category.icon)
                        .font(.title3.weight(.semibold))
                    Text("\(store.count(in: category.id))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            AssetGrid(assets: store.assets(in: category.id), category: category, onPreview: { previewID = $0 }, onDelete: { pendingDelete = $0 })
        }
    }

    @ViewBuilder
    private var header: some View {
        let store = studio.assets
        switch scope {
        case .category(let id):
            if let category = store.category(id) {
                HStack(alignment: .center, spacing: 14) {
                    headerIcon(category.icon)
                    VStack(alignment: .leading, spacing: 4) {
                        if let section = category.sectionID.flatMap({ store.section($0) }) {
                            Button {
                                studio.gallery.collection = .assetSection(section.id)
                            } label: {
                                Label(section.name, systemImage: section.icon)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Zum Bereich „\(section.name)“")
                        }
                        Text(category.name)
                            .font(.system(size: 28, weight: .bold))
                            .lineLimit(1)
                        Text(subtitle(category))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    AssetMeaningPicker(category: category)
                    Button("Bilder hinzufügen …", systemImage: "plus") { studio.chooseAssetFiles(for: category.id) }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            }
        case .section(let id):
            if let section = store.section(id) {
                HStack(alignment: .center, spacing: 14) {
                    headerIcon(section.icon)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.name)
                            .font(.system(size: 28, weight: .bold))
                            .lineLimit(1)
                        let categories = store.categories(in: id).count
                        let count = store.count(inSection: id)
                        Text("\(categories == 1 ? "1 Kategorie" : "\(categories) Kategorien") · \(count == 1 ? "1 Asset" : "\(count) Assets")")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("Neue Kategorie", systemImage: "plus") {
                        studio.gallery.collection = .assets(store.addCategory(in: id))
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        case .all:
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assets")
                        .font(.system(size: 28, weight: .bold))
                    Text("Kleidung, Schuhe, Orte und Bilder, die du oft als Referenz brauchst – nach Bereichen und Kategorien wie die Prompt-Bausteine. In „Referenzen“ gehen sie als Bild an Draw Things, sonst kommt Gemmas Beschreibung in den Prompt.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
            }
        }
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 52, height: 52)
            .background(Circle().fill(Color.accentColor.opacity(0.14)))
    }

    private func subtitle(_ category: AssetCategory) -> String {
        let count = studio.assets.count(in: category.id)
        var parts = [count == 1 ? "1 Asset" : "\(count) Assets"]
        if let hint = category.hint, !hint.isEmpty { parts.append(hint) }
        return parts.joined(separator: " · ")
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Noch keine Assets")
                .font(.title3.weight(.semibold))
            Text("Ziehe Bilder aus dem Finder oder der Galerie auf eine Kategorie links – oder hierher (landet in „\(studio.assets.categories.first?.name ?? "")“).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// Raster der Assets einer Kategorie – plus Feld zum Hinzufügen.
private struct AssetGrid: View {
    @Environment(Studio.self) private var studio
    let assets: [Asset]
    let category: AssetCategory
    let onPreview: (UUID) -> Void
    let onDelete: (Asset) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)], alignment: .leading, spacing: 14) {
            ForEach(assets) { asset in
                AssetCard(asset: asset, onPreview: { onPreview(asset.id) }, onDelete: { onDelete(asset) })
            }
            AddAssetCard(categoryID: category.id)
        }
    }
}

private struct AssetCard: View {
    @Environment(Studio.self) private var studio
    let asset: Asset
    let onPreview: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        let store = studio.assets
        let isSelected = store.selectedID == asset.id
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AssetThumbnail(asset: asset)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                }
                .overlay(alignment: .topTrailing) {
                    if store.describing.contains(asset.id) {
                        ProgressView()
                            .controlSize(.small)
                            .padding(6)
                            .glassEffect(.regular, in: .circle)
                            .padding(4)
                            .help("Gemma beschreibt das Asset …")
                    }
                }
            HStack(spacing: 4) {
                Text(asset.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if asset.useCount > 0 {
                    Text("\(asset.useCount)×")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("So oft verwendet")
                }
            }
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
        .onTapGesture {
            store.selectedID = asset.id
            studio.showInspector = true
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { withAnimation(.smooth(duration: 0.2)) { onPreview() } })
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .onDrag { NSItemProvider(object: AssetStore.url(for: asset) as NSURL) }
        .contextMenu { AssetMenu(asset: asset, onDelete: onDelete) }
        .help(asset.description.isEmpty ? asset.name : asset.description)
    }
}

/// Aktionen für ein Asset – im Raster und im Inspector.
struct AssetMenu: View {
    @Environment(Studio.self) private var studio
    let asset: Asset
    /// nil = ohne „Löschen“ (z. B. im Baukasten der Seitenleiste).
    var onDelete: (() -> Void)?

    var body: some View {
        let store = studio.assets
        Button("In „Referenzen“ verwenden", systemImage: "photo.stack") { studio.useAssetInStudio(asset.id) }
        Menu("Als Referenz in Platz", systemImage: "square.stack.3d.up") {
            ForEach(studio.references.indices, id: \.self) { index in
                Button("Bild \(index + 1) · \(studio.references[index].image == nil ? "leer" : studio.references[index].role.title)") {
                    studio.setAsset(asset.id, at: index)
                    studio.show(.references)
                }
            }
        }
        Menu("In Labs verwenden", systemImage: "flask") {
            LabsSlotMenuItems { slot in studio.useAssetInLabs(asset.id, slot: slot) }
        }
        Divider()
        Menu("Kategorie", systemImage: "folder") {
            ForEach(store.sections) { section in
                Section(section.name) {
                    ForEach(store.categories(in: section.id)) { category in
                        Button {
                            store.update(asset.id) { $0.categoryID = category.id }
                        } label: {
                            Label(category.name, systemImage: category.id == asset.categoryID ? "checkmark" : category.icon)
                        }
                    }
                }
            }
        }
        Button("Neu beschreiben (Gemma)", systemImage: "sparkles") { studio.describeAssets([asset.id]) }
            .disabled(store.describing.contains(asset.id))
        Button("Im Finder zeigen", systemImage: "folder") { studio.revealAsset(asset) }
        if let onDelete {
            Divider()
            Button("Asset löschen …", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// Kontextmenü einer Kategorie in der Seitenleiste.
struct AssetCategoryMenu: View {
    @Environment(Studio.self) private var studio
    let category: AssetCategory

    var body: some View {
        let store = studio.assets
        Button("Bilder hinzufügen …", systemImage: "plus") { studio.chooseAssetFiles(for: category.id) }
        Button("Umbenennen", systemImage: "pencil") { store.renamingCategoryID = category.id }
        Menu("Gilt als", systemImage: category.role.symbol) {
            ForEach(ReferenceRole.allCases) { role in
                Button {
                    studio.setAssetCategoryRole(role, of: category.id)
                } label: {
                    Label(role.title, systemImage: role == category.role && category.customSubject == nil ? "checkmark" : role.symbol)
                }
            }
            Divider()
            Button {
                studio.suggestAssetSubject(for: category.id)
            } label: {
                Label(category.customSubject.map { "Eigenes Thema: \($0)" } ?? "Eigenes Thema …",
                      systemImage: category.customSubject == nil ? "character.cursor.ibeam" : "checkmark")
            }
        }
        Menu("Symbol", systemImage: category.icon) {
            ForEach(AssetCategory.symbols, id: \.self) { symbol in
                Button {
                    store.updateCategory(category.id) { $0.icon = symbol }
                } label: {
                    Label(symbol, systemImage: symbol)
                }
            }
        }
        Menu("Bereich", systemImage: "folder") {
            ForEach(store.sections) { section in
                Button {
                    store.moveCategory(category.id, toSection: section.id)
                } label: {
                    Label(section.name, systemImage: section.id == category.sectionID ? "checkmark" : section.icon)
                }
            }
        }
        if store.categories.count > 1 {
            Divider()
            Button("Kategorie löschen", systemImage: "trash", role: .destructive) {
                if studio.gallery.collection == .assets(category.id) { studio.gallery.collection = .assets(nil) }
                store.deleteCategory(category.id)
            }
            .help("Die Assets wandern in die erste andere Kategorie")
        }
    }
}

private struct AddAssetCard: View {
    @Environment(Studio.self) private var studio
    let categoryID: String
    @State private var isTargeted = false

    var body: some View {
        Button {
            studio.chooseAssetFiles(for: categoryID)
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        if studio.assets.importing > 0 {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus.viewfinder")
                                .font(.title)
                        }
                        Text("Bilder hierher ziehen\noder klicken")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            AssetDrop.handle(providers, categoryID: categoryID, studio: studio)
        }
    }
}

/// Vorschaubild eines Assets – lädt im Hintergrund.
struct AssetThumbnail: View {
    let asset: Asset
    @State private var loaded: (id: UUID, image: CGImage)?

    private var image: CGImage? {
        if let loaded, loaded.id == asset.id { return loaded.image }
        return AssetImages.cachedThumbnail(asset)
    }

    var body: some View {
        Group {
            if let image {
                CGImageView(image: image)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .aspectRatio(asset.aspect, contentMode: .fit)
            }
        }
        .task(id: asset.id) {
            if let image = await AssetImages.thumbnail(asset) { loaded = (asset.id, image) }
        }
    }
}

/// Asset groß – Klick oder Esc schließt.
private struct AssetPreview: View {
    let asset: Asset
    let close: () -> Void
    @State private var image: CGImage?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 12) {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                } else {
                    AssetThumbnail(asset: asset)
                }
                Text(asset.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                if !asset.description.isEmpty {
                    Text(asset.description)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                }
            }
            .padding(40)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.space) { close(); return .handled }
        .onAppear { focused = true }
        .task(id: asset.id) { image = await AssetImages.image(asset) }
    }
}

/// Bilder aus dem Finder, Bilddaten oder Kacheln aus der Galerie als Assets aufnehmen.
enum AssetDrop {
    @MainActor
    static func handle(_ providers: [NSItemProvider], categoryID: String, studio: Studio) -> Bool {
        Task {
            var urls: [URL] = []
            var images: [CGImage] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                       _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                   }) {
                    urls.append(url)
                } else if let image = await DropLoader.loadImage(from: [provider]) {
                    images.append(image)
                }
            }
            if let drag = studio.gallery.drag, urls.count == 1, urls[0].path == drag.path {
                studio.addGalleryItemsAsAssets(drag.ids, to: categoryID)
                urls = []
            }
            studio.gallery.drag = nil
            // Ein Asset aus einer anderen Kategorie hierher gezogen: verschieben statt kopieren.
            let assetFolder = Library.assetsFolder.path + "/"
            for url in urls where url.path.hasPrefix(assetFolder) {
                let relative = String(url.path.dropFirst(assetFolder.count))
                if let asset = studio.assets.assets.first(where: { $0.fileName == relative }) {
                    studio.assets.update(asset.id) { $0.categoryID = categoryID }
                }
            }
            urls.removeAll { $0.path.hasPrefix(assetFolder) }
            if !urls.isEmpty { studio.addAssets(urls: urls, to: categoryID) }
            if !images.isEmpty { studio.addAssets(images: images, to: categoryID) }
        }
        return true
    }
}

// MARK: - Inspector

/// Rechte Seite der Galerie, wenn ein Asset gewählt ist.
struct AssetInfo: View {
    @Environment(Studio.self) private var studio
    let asset: Asset
    @State private var pendingDelete = false

    var body: some View {
        let store = studio.assets
        let isDescribing = store.describing.contains(asset.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AssetThumbnail(asset: asset)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: 260)

                TextField("Name", text: Binding(get: { asset.name }, set: { value in store.update(asset.id) { $0.name = value } }))
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)

                Picker("Kategorie", selection: Binding(get: { asset.categoryID }, set: { id in store.update(asset.id) { $0.categoryID = id } })) {
                    ForEach(store.sections) { section in
                        Section(section.name) {
                            ForEach(store.categories(in: section.id)) { category in
                                Label(category.name, systemImage: category.icon).tag(category.id)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Beschreibung")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            studio.describeAssets([asset.id])
                        } label: {
                            if isDescribing {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.mini)
                                    Text("Gemma …")
                                }
                            } else {
                                Label(asset.description.isEmpty ? "Beschreiben" : "Neu beschreiben", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(isDescribing)
                    }
                    TextField(
                        "Gemma beschreibt das Bild auf Englisch – diese Beschreibung kommt in den Prompt, wenn das Bild selbst nicht an Draw Things geht.",
                        text: Binding(get: { asset.description }, set: { studio.setAssetDescription($0, of: asset.id) }),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(3...10)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
                }
                .card()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("Größe").foregroundStyle(.secondary); Text("\(asset.width) × \(asset.height) px").monospacedDigit() }
                    GridRow { Text("Verwendet").foregroundStyle(.secondary); Text(asset.useCount == 1 ? "1-mal" : "\(asset.useCount)-mal").monospacedDigit() }
                    GridRow { Text("Angelegt").foregroundStyle(.secondary); Text(asset.createdAt.formatted(date: .abbreviated, time: .shortened)) }
                }
                .font(.callout)
                .card()

                VStack(spacing: 8) {
                    Button {
                        studio.useAssetInStudio(asset.id)
                    } label: {
                        Label("In „Referenzen“ verwenden", systemImage: "photo.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Menu {
                        ForEach(studio.references.indices, id: \.self) { index in
                            Button("Bild \(index + 1) · \(studio.references[index].image == nil ? "leer" : studio.references[index].role.title)") {
                                studio.setAsset(asset.id, at: index)
                                studio.show(.references)
                            }
                        }
                    } label: {
                        Label("Als Referenz in Platz …", systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity)
                    }
                    HStack {
                        Button("Im Finder", systemImage: "folder") { studio.revealAsset(asset) }
                        Spacer()
                        Button("Löschen …", systemImage: "trash", role: .destructive) { pendingDelete = true }
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
                .controlSize(.large)
            }
            .padding(14)
        }
        .confirmationDialog("„\(asset.name)“ löschen?", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("Asset löschen", role: .destructive) { studio.deleteAssets([asset.id]) }
        } message: {
            Text("Die Kopie in der Bibliothek wird gelöscht. Bilder in der Galerie bleiben.")
        }
    }
}

/// Wofür die Bilder einer Kategorie stehen: eine der Rollen – oder ein eigenes Thema (englisch),
/// das wie der Satz eines eigenen Bausteins in Gemmas Beschreibung und den Prompt eingeht.
struct AssetMeaningPicker: View {
    @Environment(Studio.self) private var studio
    let category: AssetCategory

    private enum Meaning: Hashable {
        case role(ReferenceRole)
        case custom
    }

    var body: some View {
        let isSuggesting = studio.assets.suggestingSubjectIDs.contains(category.id)
        VStack(alignment: .trailing, spacing: 6) {
            Picker("Gilt als", selection: Binding<Meaning>(
                get: { category.customSubject != nil ? .custom : .role(category.role) },
                set: { meaning in
                    switch meaning {
                    case .role(let role): studio.setAssetCategoryRole(role, of: category.id)
                    case .custom: studio.suggestAssetSubject(for: category.id)
                    }
                }
            )) {
                ForEach(ReferenceRole.allCases) { role in
                    Label(role.title, systemImage: role.symbol).tag(Meaning.role(role))
                }
                Divider()
                Label("Eigenes Thema …", systemImage: "character.cursor.ibeam").tag(Meaning.custom)
            }
            .fixedSize()
            .help("Wofür die Bilder als Referenz stehen – bestimmt Gemmas Beschreibung und den Satz im Prompt")
            if category.customSubject != nil || isSuggesting {
                HStack(spacing: 6) {
                    Text("Thema (englisch)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isSuggesting {
                        ProgressView().controlSize(.small)
                    } else {
                        TextField("z. B. hairstyle", text: Binding(
                            get: { category.subject ?? "" },
                            set: { studio.setAssetCategorySubject($0, of: category.id) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .help("So heißen die Bilder dieser Kategorie im Prompt: „Picture 1 shows the \(category.customSubject ?? "…") …“")
                    }
                }
            }
        }
    }
}

/// Kontextmenü eines Bereichs in der Seitenleiste.
struct AssetSectionMenu: View {
    @Environment(Studio.self) private var studio
    let section: AssetSection

    var body: some View {
        let store = studio.assets
        Button("Neue Kategorie", systemImage: "plus") {
            studio.gallery.collection = .assets(store.addCategory(in: section.id))
        }
        Button("Umbenennen", systemImage: "pencil") { store.renamingSectionID = section.id }
        Menu("Symbol", systemImage: section.icon) {
            ForEach(AssetCategory.symbols + ["folder", "square.grid.2x2"], id: \.self) { symbol in
                Button {
                    store.updateSection(section.id) { $0.icon = symbol }
                } label: {
                    Label(symbol, systemImage: symbol)
                }
            }
        }
        if let index = store.sections.firstIndex(of: section), store.sections.count > 1 {
            Divider()
            Button("Nach oben", systemImage: "arrow.up") {
                store.moveSections(from: [index], to: index - 1)
            }
            .disabled(index == 0)
            Button("Nach unten", systemImage: "arrow.down") {
                store.moveSections(from: [index], to: index + 2)
            }
            .disabled(index == store.sections.count - 1)
        }
        if store.sections.count > 1 {
            Divider()
            Button("Bereich löschen", systemImage: "trash", role: .destructive) {
                if studio.gallery.collection == .assetSection(section.id) { studio.gallery.collection = .assets(nil) }
                store.deleteSection(section.id)
            }
            .help("Die Kategorien samt Assets wandern in den ersten anderen Bereich")
        }
    }
}

/// „Als Asset sichern“: Kategorien nach Bereichen – im Kontextmenü der Galerie und der Großansicht.
struct SaveAsAssetMenuItems: View {
    @Environment(Studio.self) private var studio
    let itemIDs: [UUID]

    var body: some View {
        let store = studio.assets
        ForEach(store.sections) { section in
            Section(section.name) {
                ForEach(store.categories(in: section.id)) { category in
                    Button {
                        studio.addGalleryItemsAsAssets(itemIDs, to: category.id)
                    } label: {
                        Label(category.name, systemImage: category.icon)
                    }
                }
            }
        }
    }
}
