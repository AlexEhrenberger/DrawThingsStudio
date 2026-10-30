import SwiftUI

/// Rechte Seite der Galerie: alles über das gewählte Bild, den Stapel oder die Auswahl.
struct GalleryInspector: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Info")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            content
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var content: some View {
        let gallery = studio.gallery
        if gallery.collection.isAssets {
            if let id = studio.assets.selectedID, let asset = studio.assets.asset(id) {
                AssetInfo(asset: asset)
            } else {
                ContentUnavailableView(
                    "Kein Asset ausgewählt",
                    systemImage: "shippingbox",
                    description: Text("Klicke ein Asset an, um Namen, Kategorie und Gemmas Beschreibung zu bearbeiten.")
                )
            }
        } else if let id = gallery.viewer?.currentID, let item = gallery.item(id) {
            ItemInfo(item: item)
        } else if gallery.selection.count == 1, let id = gallery.selection.first {
            if let stack = gallery.stacks[id] {
                StackInfo(stack: stack, members: gallery.members(of: id))
            } else if let item = gallery.item(id) {
                ItemInfo(item: item)
            }
        } else if gallery.selection.count > 1 {
            let ids = gallery.selection.flatMap { id in gallery.stacks[id] != nil ? gallery.members(of: id).map(\.id) : [id] }
            SelectionInfo(items: ids.compactMap { gallery.item($0) }.sorted { $0.createdAt > $1.createdAt })
        } else {
            ContentUnavailableView(
                "Nichts ausgewählt",
                systemImage: "photo.on.rectangle",
                description: Text("Klicke ein Bild an, um Prompt, Seed und Bewertung zu sehen. Ein Stapel fächert sich beim Klick auf.")
            )
        }
    }
}

// MARK: - Einzelbild

private struct ItemInfo: View {
    @Environment(Studio.self) private var studio
    let item: GalleryItem

    var body: some View {
        let gallery = studio.gallery
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GalleryThumbnail(item: item)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: 260)

                HStack {
                    Label(item.kindTitle, systemImage: item.kindSymbol)
                        .font(.headline)
                    Spacer()
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    StarRating(rating: item.rating, size: 16) { gallery.setRating($0, for: [item.id]) }
                    Spacer()
                    FlagButtons(flag: item.flag, size: 16) { gallery.setFlag($0, for: [item.id]) }
                }
                .card(padding: 10)

                NotesSection(item: item)

                if let stackID = item.stackID, let stack = gallery.stacks[stackID] {
                    StackBadge(stack: stack, item: item)
                }

                TagsSection(itemIDs: [item.id])
                    .id(item.id)
                ProjectsSection(itemIDs: [item.id])
                PersonaTagsSection(itemIDs: [item.id])

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    row("Größe", "\(item.width) × \(item.height) px")
                    if let length = item.videoLength { row("Länge", Format.duration(length)) }
                    if let seed = item.seed { row("Seed", "\(seed)") }
                    if let duration = item.duration { row("Dauer", Format.duration(duration)) }
                    row("Datei", item.url.lastPathComponent)
                }
                .font(.callout)
                .card()

                if !item.prompt.isEmpty {
                    PromptCard(prompt: item.prompt) { studio.adoptPrompt(of: item) }
                }

                VStack(spacing: 8) {
                    if item.isVideo {
                        Button {
                            withAnimation(.smooth(duration: 0.25)) { gallery.open(.image(item)) }
                        } label: {
                            Label("Abspielen", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            studio.openInStudio(item, mode: .edit)
                        } label: {
                            Label("Im Studio bearbeiten", systemImage: "paintbrush.pointed")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            studio.openInStudio(item, mode: .series)
                        } label: {
                            Label("Als Ausgangsbild für eine Serie", systemImage: "square.grid.2x2")
                                .frame(maxWidth: .infinity)
                        }
                        Menu {
                            ForEach(studio.references.indices, id: \.self) { index in
                                Button("Bild \(index + 1) · \(studio.references[index].role.title)") { studio.useAsReference(item, slot: index) }
                            }
                        } label: {
                            Label("Als Referenz verwenden", systemImage: "photo.stack")
                                .frame(maxWidth: .infinity)
                        }
                        Menu {
                            LabsSlotMenuItems { slot in studio.useInLabs(item, slot: slot) }
                        } label: {
                            Label("In Labs verwenden", systemImage: "flask")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    HStack {
                        Button("Im Finder", systemImage: "folder") { studio.revealInFinder([item]) }
                        Spacer()
                        Button("Exportieren …", systemImage: "square.and.arrow.up") { studio.export(item) }
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
                .controlSize(.large)
            }
            .padding(14)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

/// Zu welcher Serie das Bild gehört – mit Knopf zum Auffächern.
private struct StackBadge: View {
    @Environment(Studio.self) private var studio
    let stack: GalleryStack
    let item: GalleryItem

    var body: some View {
        let gallery = studio.gallery
        HStack(spacing: 10) {
            Image(systemName: stack.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(stack.isSeries ? "Serie · \(stack.title)" : stack.title)
                    .font(.callout.weight(.semibold))
                if let number = item.stackIndex {
                    Text(item.label.map { "Variante \(number): \($0)" } ?? "Bild \(number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if gallery.viewer?.stackID != stack.id {
                Button("Auffächern") {
                    let members = gallery.members(of: stack.id)
                    guard !members.isEmpty else { return }
                    withAnimation(.smooth(duration: 0.25)) { gallery.open(members.count == 1 ? .image(members[0]) : .stack(stack, members)) }
                }
                .controlSize(.small)
            }
        }
        .card(padding: 10)
    }
}

/// Prompt zum Lesen, Kopieren und Übernehmen.
private struct PromptCard: View {
    let prompt: String
    let adopt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(prompt)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Kopieren", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prompt, forType: .string)
                }
                Spacer()
                Button("Übernehmen", systemImage: "text.quote", action: adopt)
                    .help("Prompt in die Seitenleiste des Studios übernehmen")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .card()
    }
}

// MARK: - Stapel

private struct StackInfo: View {
    @Environment(Studio.self) private var studio
    let stack: GalleryStack
    let members: [GalleryItem]

    var body: some View {
        let gallery = studio.gallery
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: stack.symbol)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stack.isSeries ? "Serie · \(stack.title)" : stack.title)
                            .font(.headline)
                        Text("\(members.count) Bilder · \((members.map(\.createdAt).max() ?? stack.createdAt).formatted(date: .abbreviated, time: .shortened))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(members) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            GalleryThumbnail(item: item)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .opacity(item.flag == .reject ? 0.4 : 1)
                                .frame(maxWidth: .infinity)
                            HStack(spacing: 4) {
                                if let number = item.stackIndex { NumberBadge(number: number).scaleEffect(0.8) }
                                if let title = item.captionTitle {
                                    Text(title)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if item.flag == .pick {
                                    Image(systemName: "flag.fill").font(.caption2).foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                HStack {
                    Text("Alle bewerten")
                        .foregroundStyle(.secondary)
                    Spacer()
                    StarRating(rating: commonRating, size: 14) { gallery.setRating($0, for: members.map(\.id)) }
                }
                .font(.callout)
                .card(padding: 10)

                let noted = members.filter { !gallery.notes(for: $0.id).isEmpty }
                if !noted.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notizen")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(noted) { item in
                            HStack(alignment: .top, spacing: 8) {
                                if let number = item.stackIndex {
                                    NumberBadge(number: number)
                                        .scaleEffect(0.85)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(gallery.notes(for: item.id)) { note in
                                        NoteRow(note: note)
                                    }
                                }
                            }
                        }
                    }
                    .font(.callout)
                    .card()
                }

                TagsSection(itemIDs: members.map(\.id))
                    .id(stack.id)
                ProjectsSection(itemIDs: members.map(\.id))

                if let prompt = stack.prompt, !prompt.isEmpty {
                    PromptCard(prompt: prompt) {
                        studio.builder.replacePrompt(prompt)
                        studio.showGallery = false
                    }
                }

                VStack(spacing: 8) {
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { gallery.open(.stack(stack, members)) }
                    } label: {
                        Label("Auffächern und vergleichen", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        gallery.unstack(stack.id)
                    } label: {
                        Label("Stapel auflösen", systemImage: "square.stack.3d.down.right")
                            .frame(maxWidth: .infinity)
                    }
                    Button("Im Finder zeigen", systemImage: "folder") { studio.revealInFinder(members) }
                        .buttonStyle(.borderless)
                }
                .controlSize(.large)
            }
            .padding(14)
        }
    }

    /// Gemeinsame Bewertung – nur wenn alle Bilder gleich bewertet sind.
    private var commonRating: Int {
        let ratings = Set(members.map(\.rating))
        return ratings.count == 1 ? ratings.first ?? 0 : 0
    }
}

// MARK: - Mehrere Bilder

private struct SelectionInfo: View {
    @Environment(Studio.self) private var studio
    let items: [GalleryItem]

    var body: some View {
        let gallery = studio.gallery
        let ids = items.map(\.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(items.count) Bilder ausgewählt")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(items.prefix(12)) { item in
                        GalleryThumbnail(item: item)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                if items.count > 12 {
                    Text("und \(items.count - 12) weitere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    HStack {
                        Text("Bewerten")
                            .foregroundStyle(.secondary)
                        Spacer()
                        StarRating(rating: commonRating, size: 14) { gallery.setRating($0, for: ids) }
                    }
                    HStack {
                        Text("Markieren")
                            .foregroundStyle(.secondary)
                        Spacer()
                        FlagButtons(flag: commonFlag, size: 14) { gallery.setFlag($0, for: ids) }
                    }
                }
                .font(.callout)
                .card(padding: 10)

                TagsSection(itemIDs: ids)
                    .id(ids)
                ProjectsSection(itemIDs: ids)
                PersonaTagsSection(itemIDs: ids)

                VStack(spacing: 8) {
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { gallery.compare(ids) }
                    } label: {
                        Label("Vergleichen", systemImage: "rectangle.split.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        gallery.group(ids)
                    } label: {
                        Label("Als Stapel gruppieren", systemImage: "square.stack")
                            .frame(maxWidth: .infinity)
                    }
                    HStack {
                        Button("Im Finder", systemImage: "folder") { studio.revealInFinder(items) }
                        Spacer()
                        Button("In den Papierkorb …", systemImage: "trash", role: .destructive) { gallery.trashRequest = ids }
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
                .controlSize(.large)
            }
            .padding(14)
        }
    }

    private var commonRating: Int {
        let ratings = Set(items.map(\.rating))
        return ratings.count == 1 ? ratings.first ?? 0 : 0
    }

    private var commonFlag: GalleryFlag {
        let flags = Set(items.map(\.flag))
        return flags.count == 1 ? flags.first ?? .none : .none
    }
}
