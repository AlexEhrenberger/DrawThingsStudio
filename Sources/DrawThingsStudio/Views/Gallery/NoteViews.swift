import SwiftUI

extension NoteKind {
    var color: Color {
        switch self {
        case .todo: .orange
        case .like: .green
        case .dislike: .red
        }
    }
}

/// Eine Notiz: To-dos mit Häkchen, Lob und Kritik mit Daumen. Doppelklick bearbeitet den Text.
struct NoteRow: View {
    @Environment(Studio.self) private var studio
    let note: GalleryNote
    /// Knopf „Umsetzen“ bei offenen To-dos.
    var showsWorkButton = true

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    private var isWorking: Bool { studio.gallery.workingTodoID == note.id }

    var body: some View {
        let gallery = studio.gallery
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if note.kind == .todo {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { gallery.toggleDone(note.id) }
                    } label: {
                        Image(systemName: note.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(note.isDone ? Color.green : NoteKind.todo.color)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .help(note.isDone ? "Wieder öffnen" : "Als erledigt abhaken")
                } else {
                    Image(systemName: note.kind.symbol + ".fill")
                        .foregroundStyle(note.kind.color)
                        .help(note.kind.title)
                }

                if isEditing {
                    TextField(note.kind.placeholder, text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($editorFocused)
                        .onSubmit(commit)
                        .onExitCommand { isEditing = false }
                        .onChange(of: editorFocused) { if !editorFocused { commit() } }
                } else {
                    Text(note.text)
                        .strikethrough(note.isDone, color: .secondary)
                        .foregroundStyle(note.isDone ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2, perform: startEditing)
                        .textSelection(.enabled)
                }

                if !isEditing {
                    HStack(spacing: 6) {
                        if note.isOpenTodo && showsWorkButton {
                            Button {
                                studio.workOn(note)
                            } label: {
                                Label(isWorking ? "In Arbeit" : "Umsetzen", systemImage: "wand.and.sparkles")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(GemmaStyle.gradient)
                            }
                            .buttonStyle(.plain)
                            .help("Bild im Studio öffnen – Gemma schreibt aus dem To-do die Bearbeitung")
                        }
                        if isHovering {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { gallery.deleteNote(note.id) }
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Notiz löschen")
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            if !note.resultIDs.isEmpty {
                ResultStrip(ids: note.resultIDs)
                    .padding(.leading, 24)
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Bearbeiten", systemImage: "pencil", action: startEditing)
            Menu("Art", systemImage: "tag") {
                ForEach(NoteKind.allCases) { kind in
                    Button(kind.title, systemImage: kind.symbol) {
                        gallery.updateNote(note.id) { $0.kind = kind; if kind != .todo { $0.doneAt = nil } }
                    }
                    .disabled(kind == note.kind)
                }
            }
            if note.isOpenTodo {
                Button("Im Studio umsetzen", systemImage: "wand.and.sparkles") { studio.workOn(note) }
            }
            Divider()
            Button("Löschen", systemImage: "trash", role: .destructive) { gallery.deleteNote(note.id) }
        }
    }

    private func startEditing() {
        draft = note.text
        isEditing = true
        editorFocused = true
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        if draft != note.text { studio.gallery.updateNote(note.id) { $0.text = draft } }
    }
}

/// Kleine Vorschaubilder der Ergebnisse eines To-dos – Klick zeigt sie groß.
private struct ResultStrip: View {
    @Environment(Studio.self) private var studio
    let ids: [UUID]

    var body: some View {
        let gallery = studio.gallery
        let items = ids.compactMap { gallery.item($0) }
        if !items.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(items) { item in
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { gallery.compare([item.id]) }
                    } label: {
                        GalleryThumbnail(item: item)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Ergebnis groß ansehen")
                }
                Text(items.count == 1 ? "1 Ergebnis" : "\(items.count) Ergebnisse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Eingabe für eine neue Notiz: Art wählen, Text tippen, Return.
struct NoteComposer: View {
    @Environment(Studio.self) private var studio
    let itemID: UUID
    /// Fokussiert das Feld, sobald sich der Wert ändert (Taste N).
    var focusRequest = 0

    @AppStorage("gallery.lastNoteKind") private var kind: NoteKind = .todo
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(NoteKind.allCases) { option in
                    Button {
                        kind = option
                        isFocused = true
                    } label: {
                        Image(systemName: option.symbol)
                            .symbolVariant(kind == option ? .fill : .none)
                            .foregroundStyle(kind == option ? option.color : Color.secondary)
                            .frame(width: 24, height: 22)
                            .background {
                                if kind == option {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(option.color.opacity(0.15))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                }
            }
            TextField(kind.placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(add)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(kind.color)
                }
                .buttonStyle(.plain)
                .help("\(kind.title) hinzufügen (↩)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? kind.color.opacity(0.6) : .clear, lineWidth: 1)
        )
        .onChange(of: focusRequest) { isFocused = true }
    }

    private func add() {
        guard studio.gallery.addNote(to: itemID, kind: kind, text: text) != nil else { return }
        text = ""
        isFocused = true
    }
}

/// Notizen eines Bildes im Inspector.
struct NotesSection: View {
    @Environment(Studio.self) private var studio
    let item: GalleryItem

    var body: some View {
        let gallery = studio.gallery
        let notes = gallery.notes(for: item.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notizen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                let open = notes.filter(\.isOpenTodo).count
                if open > 0 {
                    Text(open == 1 ? "1 offenes To-do" : "\(open) offene To-dos")
                        .font(.caption)
                        .foregroundStyle(NoteKind.todo.color)
                }
            }
            ForEach(notes) { note in
                NoteRow(note: note)
            }
            NoteComposer(itemID: item.id, focusRequest: gallery.noteFieldRequest)
        }
        .font(.callout)
        .card()
    }
}

/// Projekte eines Bildes im Inspector – als Kapseln, mit Menü zum Hinzufügen.
struct ProjectsSection: View {
    @Environment(Studio.self) private var studio
    let itemIDs: [UUID]

    var body: some View {
        let gallery = studio.gallery
        let memberOf = gallery.projects.filter { project in itemIDs.allSatisfy { gallery.projectMembers[project.id]?.contains($0) == true } }
        VStack(alignment: .leading, spacing: 8) {
            Text("Projekte")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(memberOf) { project in
                    HStack(spacing: 4) {
                        Image(systemName: gallery.activeProjectID == project.id ? "folder.fill" : "folder")
                        Text(project.name)
                            .lineLimit(1)
                        Button {
                            gallery.removeFromProject(project.id, itemIDs: itemIDs)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Aus „\(project.name)“ entfernen")
                    }
                    .font(.callout)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                Menu {
                    ProjectMenuItems(itemIDs: itemIDs)
                } label: {
                    Label("Projekt", systemImage: "plus")
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .card()
    }
}

/// Einträge „Zu Projekt hinzufügen“ – im Inspector und in Kontextmenüs.
struct ProjectMenuItems: View {
    @Environment(Studio.self) private var studio
    let itemIDs: [UUID]

    var body: some View {
        let gallery = studio.gallery
        ForEach(gallery.projects) { project in
            let contains = itemIDs.allSatisfy { gallery.projectMembers[project.id]?.contains($0) == true }
            Button(project.name, systemImage: contains ? "checkmark" : "folder") {
                if contains {
                    gallery.removeFromProject(project.id, itemIDs: itemIDs)
                } else {
                    gallery.addToProject(project.id, itemIDs: itemIDs)
                }
            }
        }
        if !gallery.projects.isEmpty { Divider() }
        Button("Neues Projekt …", systemImage: "folder.badge.plus") {
            gallery.createProject(itemIDs: itemIDs)
        }
    }
}

/// Charaktere, die auf dem Bild zu sehen sind – für den Filter und die Gesichtsreferenz beim Bearbeiten.
struct PersonaTagsSection: View {
    @Environment(Studio.self) private var studio
    let itemIDs: [UUID]

    var body: some View {
        let gallery = studio.gallery
        let personas = studio.personas.personas
        if !personas.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Charaktere auf dem Bild")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(personas) { persona in
                        let isOn = itemIDs.allSatisfy { gallery.item($0)?.personaIDs?.contains(persona.id) == true }
                        Button {
                            gallery.togglePersona(persona.id, for: itemIDs)
                        } label: {
                            HStack(spacing: 5) {
                                PersonaAvatar(persona: persona, size: 16)
                                Text(persona.name).lineLimit(1)
                            }
                            .font(.callout)
                            .padding(.leading, 4)
                            .padding(.trailing, 9)
                            .padding(.vertical, 3)
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .background(Capsule().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07))))
                        }
                        .buttonStyle(.plain)
                        .help(isOn ? "Nicht mehr zuordnen" : "\(persona.name) ist auf dem Bild")
                    }
                }
            }
            .card()
        }
    }
}
