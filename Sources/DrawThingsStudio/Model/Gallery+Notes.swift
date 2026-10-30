import Foundation

/// Notizen, To-dos und Projekte der Galerie.
extension Gallery {

    // MARK: Notizen

    func notes(for itemID: UUID) -> [GalleryNote] {
        notesByItem[itemID] ?? []
    }

    func openTodoCount(for itemIDs: [UUID]) -> Int {
        itemIDs.reduce(0) { $0 + notes(for: $1).filter(\.isOpenTodo).count }
    }

    func note(_ id: UUID) -> GalleryNote? {
        notes.first { $0.id == id }
    }

    @discardableResult
    func addNote(to itemID: UUID, kind: NoteKind, text: String) -> GalleryNote? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, item(itemID) != nil else { return nil }
        let note = GalleryNote(itemID: itemID, kind: kind, text: text)
        notes.append(note)
        scheduleSave()
        return note
    }

    func updateNote(_ id: UUID, _ change: (inout GalleryNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[index])
        notes[index].text = notes[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes[index].text.isEmpty { notes.remove(at: index) }
        scheduleSave()
    }

    func toggleDone(_ id: UUID) {
        updateNote(id) { $0.doneAt = $0.doneAt == nil ? .now : nil }
        if workingTodoID == id, note(id)?.isDone == true { workingTodoID = nil }
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if workingTodoID == id { workingTodoID = nil }
        scheduleSave()
    }

    /// Neues Bild aus dem Studio, das aus dem Bild des laufenden To-dos entstanden ist.
    func linkToWorkingTodo(_ item: GalleryItem) {
        guard let id = workingTodoID, let todo = note(id), let parent = item.parentID else { return }
        // Auch Bearbeitungen eines Zwischenergebnisses zählen noch zum To-do.
        guard parent == todo.itemID || todo.resultIDs.contains(parent) else { return }
        updateNote(id) { $0.resultIDs.append(item.id) }
    }

    /// Bilder mit ihren Notizen für die Übersicht – gefiltert, Bilder mit offenen To-dos zuerst.
    var noteGroups: [(item: GalleryItem, notes: [GalleryNote])] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = notesProjectID.flatMap { projectMembers[$0] }
        var groups: [(item: GalleryItem, notes: [GalleryNote])] = []
        for (itemID, itemNotes) in notesByItem {
            guard let item = item(itemID), !missing.contains(itemID) else { continue }
            if let members, !members.contains(itemID) { continue }
            var shown = itemNotes.filter { note in
                switch notesFilter {
                case .open: note.isOpenTodo
                case .done: note.kind == .todo && note.isDone
                case .all: true
                }
            }
            if !search.isEmpty {
                let words = search.split(separator: " ")
                shown = shown.filter { note in
                    let haystack = note.text + " " + item.prompt
                    return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                }
            }
            guard !shown.isEmpty else { continue }
            // To-dos oben, dann Gefällt, dann Gefällt nicht – jeweils in der Reihenfolge des Anlegens.
            let order: [NoteKind: Int] = [.todo: 0, .like: 1, .dislike: 2]
            shown.sort { (order[$0.kind]!, $0.createdAt) < (order[$1.kind]!, $1.createdAt) }
            groups.append((item, shown))
        }
        return groups.sorted { a, b in
            let openA = a.notes.contains(where: \.isOpenTodo), openB = b.notes.contains(where: \.isOpenTodo)
            if openA != openB { return openA }
            return (a.notes.map(\.createdAt).max() ?? .distantPast) > (b.notes.map(\.createdAt).max() ?? .distantPast)
        }
    }

    // MARK: Projekte

    func project(_ id: UUID) -> GalleryProject? {
        projects.first { $0.id == id }
    }

    func projects(containing itemID: UUID) -> [GalleryProject] {
        projects.filter { projectMembers[$0.id]?.contains(itemID) == true }
    }

    /// Neues Projekt – der Name lässt sich gleich in der Seitenleiste ändern.
    @discardableResult
    func createProject(name: String = "Neues Projekt", itemIDs: [UUID] = []) -> UUID {
        var unique = name
        var number = 2
        while projects.contains(where: { $0.name == unique }) {
            unique = "\(name) \(number)"
            number += 1
        }
        let project = GalleryProject(name: unique, itemIDs: itemIDs)
        projects.append(project)
        renamingProjectID = project.id
        scheduleSave()
        return project.id
    }

    func renameProject(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = name
        scheduleSave()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if activeProjectID == id { activeProjectID = nil }
        if notesProjectID == id { notesProjectID = nil }
        if collection == .project(id) { collection = .all }
        scheduleSave()
    }

    func addToProject(_ id: UUID, itemIDs: [UUID]) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let existing = Set(projects[index].itemIDs)
        let new = itemIDs.filter { !existing.contains($0) }
        guard !new.isEmpty else { return }
        projects[index].itemIDs += new
        scheduleSave()
    }

    func removeFromProject(_ id: UUID, itemIDs: [UUID]) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let removed = Set(itemIDs)
        projects[index].itemIDs.removeAll { removed.contains($0) }
        selection.subtract(removed)
        scheduleSave()
    }

    /// Bild- oder Stapel-IDs zu Bild-IDs auflösen (Stapel mit allen Bildern).
    func itemIDs(for ids: some Sequence<UUID>) -> [UUID] {
        ids.flatMap { id in stacks[id] != nil ? members(of: id).map(\.id) : [id] }
    }
}
