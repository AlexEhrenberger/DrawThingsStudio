import SwiftUI

/// Übersicht aller Notizen: jedes Bild mit seinen To-dos, Lob und Kritik – Bilder mit offenen To-dos zuerst.
struct GalleryNotesView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var gallery = studio.gallery
        let groups = gallery.noteGroups
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if groups.isEmpty {
                    empty
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(groups, id: \.item.id) { group in
                            NoteCard(item: group.item, notes: group.notes, isSelected: gallery.selection == [group.item.id])
                        }
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .animation(.smooth(duration: 0.25), value: gallery.notesFilter)
    }

    private var header: some View {
        @Bindable var gallery = studio.gallery
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notizen & To-dos")
                    .font(.system(size: 26, weight: .bold))
                Text(summary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            Picker("Zeigen", selection: $gallery.notesFilter) {
                ForEach(NotesFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if !gallery.projects.isEmpty {
                Picker("Projekt", selection: $gallery.notesProjectID) {
                    Text("Alle Projekte").tag(UUID?.none)
                    Divider()
                    ForEach(gallery.projects) { project in
                        Text(project.name).tag(UUID?.some(project.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("Nur Bilder eines Projekts")
            }
        }
    }

    private var summary: String {
        let gallery = studio.gallery
        let visible = gallery.notes.filter { note in
            !gallery.missing.contains(note.itemID)
                && (gallery.notesProjectID.map { gallery.projectMembers[$0]?.contains(note.itemID) == true } ?? true)
        }
        let open = visible.filter(\.isOpenTodo)
        let done = visible.filter { $0.kind == .todo && $0.isDone }.count
        let images = Set(open.map(\.itemID)).count
        var text = open.count == 1 ? "1 offenes To-do" : "\(open.count) offene To-dos"
        if images > 0 { text += images == 1 ? " bei 1 Bild" : " bei \(images) Bildern" }
        if done > 0 { text += " · \(done) erledigt" }
        return text
    }

    @ViewBuilder
    private var empty: some View {
        let gallery = studio.gallery
        if gallery.notes.isEmpty {
            ContentUnavailableView(
                "Noch keine Notizen",
                systemImage: "checklist",
                description: Text("Wähle ein Bild und schreib rechts im Inspector, was dir gefällt, was nicht und was noch zu tun ist – oder drück N.")
            )
        } else if !gallery.searchText.isEmpty {
            ContentUnavailableView.search(text: gallery.searchText)
        } else if gallery.notesFilter == .open {
            ContentUnavailableView("Alles erledigt", systemImage: "checkmark.circle", description: Text("Es gibt keine offenen To-dos."))
        } else {
            ContentUnavailableView("Keine Notizen", systemImage: "checklist", description: Text("Hier passt gerade keine Notiz zum Filter."))
        }
    }
}

/// Ein Bild mit seinen Notizen.
private struct NoteCard: View {
    @Environment(Studio.self) private var studio
    let item: GalleryItem
    let notes: [GalleryNote]
    let isSelected: Bool

    var body: some View {
        let gallery = studio.gallery
        HStack(alignment: .top, spacing: 14) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { gallery.compare([item.id]) }
            } label: {
                Color.clear
                    .frame(width: 128, height: 128)
                    .overlay {
                        GalleryThumbnail(item: item)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                    }
            }
            .buttonStyle(.plain)
            .help("Groß ansehen")

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    ForEach(gallery.projects(containing: item.id)) { project in
                        Label(project.name, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button {
                        studio.openInStudio(item, mode: .edit)
                    } label: {
                        Image(systemName: "paintbrush.pointed")
                    }
                    .buttonStyle(.borderless)
                    .help("Im Studio bearbeiten")
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(notes) { note in
                        NoteRow(note: note)
                    }
                }
                .font(.callout)
                NoteComposer(itemID: item.id)
                    .font(.callout)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.07), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            gallery.selection = [item.id]
            gallery.selectionAnchor = item.id
        }
        .contextMenu { GalleryEntryMenu(entry: .image(item)) }
    }

    private var title: String {
        if let stackID = item.stackID, let stack = studio.gallery.stacks[stackID] {
            if let number = item.stackIndex {
                return "\(stack.title) · " + (item.label.map { "\(number): \($0)" } ?? "Bild \(number)")
            }
            return stack.title
        }
        return item.source.title
    }

    private var symbol: String {
        if let stackID = item.stackID, let stack = studio.gallery.stacks[stackID] { return stack.symbol }
        return item.source.symbol
    }
}
