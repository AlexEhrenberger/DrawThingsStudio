import SwiftUI

extension Studio {
    /// Info rechts öffnen und das Tag-Feld fokussieren (Taste T, „Neues Tag …“) – im Fokusmodus die Info-Spalte dort.
    func focusTagField() {
        if isFocusMode {
            UserDefaults.standard.set(true, forKey: "focus.showInfo")
        } else {
            showInspector = true
        }
        gallery.wantsTagField = true
    }
}

/// Tags eines oder mehrerer Bilder im Inspector: Kapseln mit ×, ein Feld mit Vorschlägen und häufige Tags zum Anklicken.
struct TagsSection: View {
    @Environment(Studio.self) private var studio
    let itemIDs: [UUID]

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let gallery = studio.gallery
        let (common, partial) = gallery.tags(of: itemIDs)
        let counts = gallery.tagCounts
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !common.isEmpty || !partial.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(common, id: \.self) { tag in
                        TagCapsule(tag: tag, itemIDs: itemIDs, isPartial: false)
                    }
                    ForEach(partial, id: \.self) { tag in
                        TagCapsule(tag: tag, itemIDs: itemIDs, isPartial: true)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                TextField(itemIDs.count == 1 ? "Tag hinzufügen" : "Tag für alle hinzufügen", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(add)
                    .textInputSuggestions {
                        ForEach(suggestions(from: counts.map(\.tag), excluding: common), id: \.tag) { suggestion in
                            Text(suggestion.tag)
                                .textInputCompletion(suggestion.completion)
                        }
                    }
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Hinzufügen (↩) – mehrere mit Komma trennen")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            )
            .help("Tag eintippen und ↩ – mehrere mit Komma trennen, z. B. „Strand, Sommer“")

            // Häufige Tags, die hier noch fehlen – ein Klick gibt sie dem Bild.
            let present = Set(common + partial)
            let frequent = counts
                .filter { !present.contains($0.tag) }
                .sorted { $0.count > $1.count }
                .prefix(6)
            if !frequent.isEmpty {
                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(Array(frequent), id: \.tag) { entry in
                        Button {
                            gallery.addTags(entry.tag, to: itemIDs)
                        } label: {
                            Label(entry.tag, systemImage: "plus")
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("„\(entry.tag)“ hinzufügen (\(entry.count) \(entry.count == 1 ? "Bild" : "Bilder"))")
                    }
                }
            }
        }
        .font(.callout)
        .card()
        .task(id: gallery.wantsTagField) {
            guard gallery.wantsTagField else { return }
            // Erst wenn das Feld steht – nach dem Einblenden der Info.
            try? await Task.sleep(for: .milliseconds(80))
            isFocused = true
            gallery.wantsTagField = false
        }
    }

    private func add() {
        studio.gallery.addTags(text, to: itemIDs)
        text = ""
        isFocused = true
    }

    /// Vorhandene Tags zum zuletzt getippten Wort (nach dem letzten Komma) – Treffer am Anfang zuerst.
    private func suggestions(from tags: [String], excluding present: [String]) -> [(tag: String, completion: String)] {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        let word = (parts.last.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return [] }
        let before = parts.dropLast().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let matches = tags.filter { tag in
            !present.contains(tag) && tag.range(of: word, options: options) != nil && tag.compare(word, options: .caseInsensitive) != .orderedSame
        }
        let ranked = matches.filter { $0.range(of: word, options: options.union(.anchored)) != nil }
            + matches.filter { $0.range(of: word, options: options.union(.anchored)) == nil }
        return ranked.prefix(8).map { tag in (tag: tag, completion: (before + [tag]).joined(separator: ", ")) }
    }
}

/// Ein Tag im Inspector. Gestrichelt = nur manche der ausgewählten Bilder tragen es (Klick gibt es allen).
private struct TagCapsule: View {
    @Environment(Studio.self) private var studio
    let tag: String
    let itemIDs: [UUID]
    let isPartial: Bool

    var body: some View {
        let gallery = studio.gallery
        HStack(spacing: 4) {
            Text(tag)
                .lineLimit(1)
            Button {
                gallery.removeTag(tag, from: itemIDs)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(itemIDs.count == 1 ? "Tag entfernen" : "Tag bei allen ausgewählten Bildern entfernen")
        }
        .font(.callout)
        .foregroundStyle(isPartial ? .secondary : .primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(isPartial ? Color.primary.opacity(0.03) : Color.accentColor.opacity(0.15)))
        .overlay {
            if isPartial {
                Capsule().strokeBorder(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            if isPartial { gallery.addTags(tag, to: itemIDs) }
        }
        .help(isPartial ? "Nur manche der Bilder tragen „\(tag)“ – klicken gibt es allen" : "Rechtsklick: alle Bilder mit „\(tag)“ zeigen")
        .contextMenu {
            if isPartial {
                Button("Allen ausgewählten Bildern geben", systemImage: "plus") { gallery.addTags(tag, to: itemIDs) }
            }
            Button("Alle Bilder mit „\(tag)“ zeigen", systemImage: "line.3.horizontal.decrease.circle") {
                gallery.showImages(taggedWith: tag)
            }
            Divider()
            Button(itemIDs.count == 1 ? "Vom Bild entfernen" : "Von diesen Bildern entfernen", systemImage: "xmark") {
                gallery.removeTag(tag, from: itemIDs)
            }
        }
    }
}

/// Einträge im Menü „Tags“ – Haken bei Tags, die alle Bilder tragen.
struct TagMenuItems: View {
    @Environment(Studio.self) private var studio
    let itemIDs: [UUID]
    /// Öffnet das Tag-Feld im Inspector.
    let onNewTag: () -> Void

    var body: some View {
        let gallery = studio.gallery
        let tags = gallery.tagCounts
        ForEach(tags, id: \.tag) { entry in
            Toggle(entry.tag, isOn: Binding(
                get: { itemIDs.allSatisfy { gallery.item($0)?.tags?.contains(entry.tag) == true } },
                set: { _ in gallery.toggleTag(entry.tag, for: itemIDs) }
            ))
        }
        if !tags.isEmpty { Divider() }
        Button("Neues Tag … (T)", systemImage: "plus", action: onNewTag)
    }
}

/// Tags im Filter unter dem Raster: ein Dropdown mit Häkchenliste, damit auch viele Tags das Popover nicht sprengen.
/// Rechtsklick auf ein Tag benennt es überall um oder entfernt es von allen Bildern.
struct TagFilterSection: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var gallery = studio.gallery
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            MultiSelectDropdown(
                title: "Tags", symbol: "tag",
                emptyText: "Noch keine Tags. Vergeben kannst du sie rechts in der Info (Taste T) oder per Rechtsklick › Tags.",
                placeholder: "Tags wählen …",
                note: "Rechtsklick auf ein Tag: umbenennen oder von allen Bildern entfernen.",
                options: gallery.tagCounts.map { DropdownOption(id: $0.tag, title: $0.tag, count: $0.count) },
                selection: $gallery.filter.tags, matchAll: $gallery.filter.requiresAllTags,
                onRename: { gallery.renameTag($0, to: $1) },
                onDelete: { gallery.deleteTag($0) }
            )
        }
    }
}
