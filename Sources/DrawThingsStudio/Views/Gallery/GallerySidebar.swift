import SwiftUI
import UniformTypeIdentifiers

/// Linke Seite der Galerie: Sammlungen, Notizen, Projekte, Stories, Charaktere und Assets.
struct GallerySidebar: View {
    @Environment(Studio.self) private var studio
    /// Deckender Grund der Fußleiste – die Liste scrollt sonst sichtbar darunter durch.
    var footerBackground = Color(nsColor: .windowBackgroundColor)
    @State private var projectToDelete: GalleryProject?
    @State private var storyToDelete: GalleryStory?
    @State private var personaToDelete: Persona?
    @AppStorage("sidebar.projectsExpanded") private var projectsExpanded = true
    @AppStorage("sidebar.storiesExpanded") private var storiesExpanded = true
    @AppStorage("sidebar.personasExpanded") private var personasExpanded = true
    @AppStorage("sidebar.assetsExpanded") private var assetsExpanded = true
    /// Zugeklappte Asset-Bereiche.
    @State private var collapsedAssetSections: Set<String> = []

    private static let collections: [GalleryCollection] = [.all, .recent, .unassigned, .series, .picks, .rated, .rejected]

    var body: some View {
        let gallery = studio.gallery
        List(selection: Binding<GalleryCollection?>(get: { gallery.collection }, set: { if let value = $0 { gallery.collection = value } })) {
            Section("Galerie") {
                ForEach(Self.collections, id: \.self) { collection in
                    row(collection, count: gallery.count(collection))
                }
                // Zahl = offene To-dos.
                row(.notes, count: gallery.count(.notes))
            }

            Section(isExpanded: $projectsExpanded) {
                ForEach(gallery.projects) { project in
                    ProjectRow(project: project, onDelete: { projectToDelete = project })
                        .tag(GalleryCollection.project(project.id))
                }
                if gallery.projects.isEmpty {
                    Text("Ziehe Bilder auf ein Projekt oder lege eins mit + an.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            } header: {
                HStack {
                    Text("Projekte")
                    Spacer()
                    Button {
                        let id = gallery.createProject(itemIDs: gallery.itemIDs(for: gallery.selection))
                        projectsExpanded = true
                        gallery.collection = .project(id)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Neues Projekt – mit den ausgewählten Bildern")
                }
            }

            Section(isExpanded: $storiesExpanded) {
                ForEach(gallery.stories) { story in
                    StoryRow(story: story, onDelete: { storyToDelete = story })
                        .tag(GalleryCollection.story(story.id))
                }
                if gallery.stories.isEmpty {
                    Text("Geordnete Bilder – präsentieren, Video planen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            } header: {
                HStack {
                    Text("Stories")
                    Spacer()
                    Button {
                        let id = gallery.createStory(itemIDs: Array(gallery.selection))
                        storiesExpanded = true
                        gallery.collection = .story(id)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Neue Story – mit den ausgewählten Bildern")
                }
            }

            Section(isExpanded: $personasExpanded) {
                ForEach(studio.personas.personas) { persona in
                    PersonaRow(persona: persona, onDelete: { personaToDelete = persona })
                        .tag(GalleryCollection.persona(persona.id))
                }
                if studio.personas.personas.isEmpty {
                    Text("Fotos einer Person von vorne, von der Seite und ganz – für Bilder, auf denen sie gleich aussieht.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            } header: {
                HStack {
                    Text("Charaktere")
                    Spacer()
                    Button {
                        personasExpanded = true
                        gallery.collection = .persona(studio.personas.create())
                        gallery.personaTab = .character
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Neuer Charakter")
                }
            }

            Section(isExpanded: $assetsExpanded) {
                Label("Alle Assets", systemImage: "square.grid.2x2")
                    .badge(studio.assets.assets.count)
                    .tag(GalleryCollection.assets(nil))
                // Wie bei den Prompt-Bausteinen: Bereiche, darin Kategorien. Ein Klick auf den Bereich zeigt
                // alle seine Kategorien, der Pfeil klappt ihn auf und zu.
                ForEach(studio.assets.sections) { section in
                    let expanded = !collapsedAssetSections.contains(section.id)
                    AssetSectionRow(section: section, isExpanded: expanded) {
                        withAnimation(.snappy(duration: 0.2)) {
                            if expanded { collapsedAssetSections.insert(section.id) } else { collapsedAssetSections.remove(section.id) }
                        }
                    }
                    .tag(GalleryCollection.assetSection(section.id))
                    if expanded {
                        ForEach(studio.assets.categories(in: section.id)) { category in
                            AssetCategoryRow(category: category)
                                .padding(.leading, 18)
                                .tag(GalleryCollection.assets(category.id))
                        }
                        .onMove { studio.assets.moveCategories(in: section.id, from: $0, to: $1) }
                    }
                }
            } header: {
                HStack {
                    Text("Assets")
                    Spacer()
                    Menu {
                        Button("Neue Kategorie", systemImage: "square.badge.plus") {
                            gallery.collection = .assets(studio.assets.addCategory(in: currentAssetSectionID))
                        }
                        Button("Neuer Bereich", systemImage: "folder.badge.plus") {
                            let id = studio.assets.addSection()
                            collapsedAssetSections.remove(id)
                            gallery.collection = .assetSection(id)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Neue Asset-Kategorie oder neuer Bereich")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .confirmationDialog(
            "Projekt „\(projectToDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Projekt löschen", role: .destructive) {
                if let project = projectToDelete { gallery.deleteProject(project.id) }
                projectToDelete = nil
            }
        } message: {
            Text("Die Bilder bleiben in der Galerie, nur die Zuordnung verschwindet.")
        }
        .confirmationDialog(
            "Story „\(storyToDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { storyToDelete != nil }, set: { if !$0 { storyToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Story löschen", role: .destructive) {
                if let story = storyToDelete { gallery.deleteStory(story.id) }
                storyToDelete = nil
            }
        } message: {
            Text("Die Bilder bleiben in der Galerie – Reihenfolge, Handlung und Video-Prompts der Story gehen verloren.")
        }
        .confirmationDialog(
            "Charakter „\(personaToDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { personaToDelete != nil }, set: { if !$0 { personaToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Charakter löschen", role: .destructive) {
                if let persona = personaToDelete { studio.deletePersona(persona.id) }
                personaToDelete = nil
            }
        } message: {
            Text("Seine Fotos werden aus der App entfernt (die Originale im Finder bleiben). Generierte Bilder bleiben in der Galerie.")
        }
    }

    /// Bereich, in den eine neue Kategorie kommt: der gerade gezeigte, sonst der letzte.
    private var currentAssetSectionID: String? {
        let store = studio.assets
        switch studio.gallery.collection {
        case .assetSection(let id): return id
        case .assets(let id?): return store.category(id)?.sectionID
        default: return store.sections.last?.id
        }
    }

    private func row(_ collection: GalleryCollection, count: Int) -> some View {
        Label(collection.title, systemImage: collection.symbol)
            .badge(count)
            .tag(collection)
    }

    private var footer: some View {
        let gallery = studio.gallery
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                LibraryMenu()
                Spacer(minLength: 4)
                if gallery.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await studio.syncGallery() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Bibliothek neu einlesen – nimmt Bilder und Videos auf, die dort neu liegen")
                    .disabled(!studio.isLibraryAvailable)
                }
                Button {
                    studio.openLibraryFolder()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Bibliothek im Finder öffnen")
                .disabled(!studio.isLibraryAvailable)
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(footerBackground)
    }
}

/// Ein Projekt in der Seitenleiste: umbenennen, als aktiv markieren, Bilder darauf ablegen.
private struct ProjectRow: View {
    @Environment(Studio.self) private var studio
    let project: GalleryProject
    let onDelete: () -> Void

    @State private var name = ""
    @State private var isTargeted = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let gallery = studio.gallery
        let isActive = gallery.activeProjectID == project.id
        Group {
            if gallery.renamingProjectID == project.id {
                Label {
                    TextField("Projektname", text: $name)
                        .focused($nameFocused)
                        .onSubmit(commit)
                        .onExitCommand { gallery.renamingProjectID = nil }
                        .onChange(of: nameFocused) { if !nameFocused { commit() } }
                } icon: {
                    Image(systemName: "folder")
                }
                .onAppear {
                    name = project.name
                    nameFocused = true
                }
            } else {
                Label {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .lineLimit(1)
                        if isActive {
                            Text("aktiv")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                .foregroundStyle(Color.accentColor)
                                .help("Neue Bilder landen automatisch in diesem Projekt")
                        }
                    }
                } icon: {
                    Image(systemName: isActive ? "folder.fill" : "folder")
                }
                .badge(gallery.count(.project(project.id)))
            }
        }
        .listRowBackground(
            isTargeted ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.25)) : nil
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            drop(providers)
        }
        .contextMenu {
            Button("Umbenennen", systemImage: "pencil") { gallery.renamingProjectID = project.id }
            if isActive {
                Button("Nicht mehr aktiv", systemImage: "folder") { gallery.activeProjectID = nil }
            } else {
                Button("Als aktives Projekt festlegen", systemImage: "folder.fill") { gallery.activeProjectID = project.id }
            }
            if !gallery.selection.isEmpty {
                Button("Auswahl hinzufügen", systemImage: "plus") {
                    gallery.addToProject(project.id, itemIDs: gallery.itemIDs(for: gallery.selection))
                }
            }
            Divider()
            Button("Projekt löschen …", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private func commit() {
        let gallery = studio.gallery
        guard gallery.renamingProjectID == project.id else { return }
        gallery.renameProject(project.id, to: name)
        gallery.renamingProjectID = nil
    }

    /// Aus dem Raster gezogen: alle betroffenen Bilder (ganze Auswahl, Stapel komplett).
    /// Aus dem Finder: Dateien, die die Galerie kennt.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let gallery = studio.gallery
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }) { urls.append(url) }
            }
            if let drag = gallery.drag, urls.count == 1, urls[0].path == drag.path {
                gallery.addToProject(project.id, itemIDs: drag.ids)
            } else {
                let paths = Set(urls.map(\.path))
                gallery.addToProject(project.id, itemIDs: gallery.items.filter { paths.contains($0.path) }.map(\.id))
            }
            gallery.drag = nil
        }
        return true
    }
}

/// Eine Story in der Seitenleiste: umbenennen, präsentieren, Bilder darauf ablegen (sie kommen ans Ende).
private struct StoryRow: View {
    @Environment(Studio.self) private var studio
    let story: GalleryStory
    let onDelete: () -> Void

    @State private var name = ""
    @State private var isTargeted = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let gallery = studio.gallery
        Group {
            if gallery.renamingStoryID == story.id {
                Label {
                    TextField("Name der Story", text: $name)
                        .focused($nameFocused)
                        .onSubmit(commit)
                        .onExitCommand { gallery.renamingStoryID = nil }
                        .onChange(of: nameFocused) { if !nameFocused { commit() } }
                } icon: {
                    Image(systemName: GalleryStory.symbol)
                }
                .onAppear {
                    name = story.name
                    nameFocused = true
                }
            } else {
                Label {
                    HStack(spacing: 6) {
                        Text(story.name)
                            .lineLimit(1)
                        if studio.isWriting(story.id) {
                            ProgressView()
                                .controlSize(.mini)
                                .help("Gemma schreibt die Video-Prompts")
                        }
                    }
                } icon: {
                    Image(systemName: GalleryStory.symbol)
                }
                .badge(gallery.count(.story(story.id)))
            }
        }
        .listRowBackground(
            isTargeted ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.25)) : nil
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            drop(providers)
        }
        .contextMenu {
            Menu("Präsentieren", systemImage: "play.rectangle") {
                PresentMenuItems(storyID: story.id)
            }
            .disabled(gallery.count(.story(story.id)) == 0)
            Button("Umbenennen", systemImage: "pencil") { gallery.renamingStoryID = story.id }
            if !gallery.selection.isEmpty {
                Button("Auswahl anhängen", systemImage: "plus") {
                    gallery.addToStory(story.id, itemIDs: Array(gallery.selection))
                }
            }
            Divider()
            Button("Story löschen …", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private func commit() {
        let gallery = studio.gallery
        guard gallery.renamingStoryID == story.id else { return }
        gallery.renameStory(story.id, to: name)
        gallery.renamingStoryID = nil
    }

    /// Aus dem Raster gezogen: alle betroffenen Bilder (ganze Auswahl, Stapel komplett) – ans Ende der Story.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let gallery = studio.gallery
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }) { urls.append(url) }
            }
            let ids: [UUID]
            if let drag = gallery.drag, urls.count == 1, urls[0].path == drag.path {
                ids = drag.ids
            } else {
                let paths = Set(urls.map(\.path))
                ids = gallery.items.filter { paths.contains($0.path) }.map(\.id)
            }
            if gallery.addToStory(story.id, itemIDs: ids) == 0, !ids.isEmpty {
                studio.errorMessage = "Nichts angehängt – Videos gehören nicht in eine Story, und jedes Bild steht nur einmal darin."
            }
            gallery.drag = nil
        }
        return true
    }
}

/// Ein Charakter in der Seitenleiste: Gesicht, Name, Fotos darauf ablegen.
private struct PersonaRow: View {
    @Environment(Studio.self) private var studio
    let persona: Persona
    let onDelete: () -> Void

    @State private var name = ""
    @State private var isTargeted = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let store = studio.personas
        Group {
            if store.renamingID == persona.id {
                Label {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .onSubmit(commit)
                        .onExitCommand { store.renamingID = nil }
                        .onChange(of: nameFocused) { if !nameFocused { commit() } }
                } icon: {
                    PersonaAvatar(persona: persona, size: 18)
                }
                .onAppear {
                    name = persona.name
                    nameFocused = true
                }
            } else {
                Label {
                    Text(persona.name)
                        .lineLimit(1)
                } icon: {
                    PersonaAvatar(persona: persona, size: 18)
                }
                .badge(studio.gallery.count(.persona(persona.id)))
            }
        }
        .listRowBackground(
            isTargeted ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.25)) : nil
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            PersonaDrop.handle(providers, personaID: persona.id, studio: studio)
        }
        .contextMenu {
            Button("Umbenennen", systemImage: "pencil") { store.renamingID = persona.id }
            Button("Im Studio verwenden", systemImage: "photo.stack") { studio.usePersonaInStudio(persona.id) }
                .disabled(persona.mainPhoto == nil)
            Button("Fotos aus der Bibliothek …", systemImage: "photo.on.rectangle") {
                studio.gallery.collection = .persona(persona.id)
                studio.gallery.personaTab = .character
                studio.personaLibraryRequest = persona.id
            }
            Button("Fotos hinzufügen …", systemImage: "plus") { studio.choosePersonaPhotos(for: persona.id) }
            Divider()
            Button("Charakter löschen …", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private func commit() {
        let store = studio.personas
        guard store.renamingID == persona.id else { return }
        store.rename(persona.id, to: name)
        store.renamingID = nil
    }
}

/// Eine Asset-Kategorie in der Seitenleiste: umbenennen, Rolle wählen, Bilder darauf ablegen.
private struct AssetCategoryRow: View {
    @Environment(Studio.self) private var studio
    let category: AssetCategory

    @State private var name = ""
    @State private var isTargeted = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let store = studio.assets
        Group {
            if store.renamingCategoryID == category.id {
                Label {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .onSubmit(commit)
                        .onExitCommand { store.renamingCategoryID = nil }
                        .onChange(of: nameFocused) { if !nameFocused { commit() } }
                } icon: {
                    Image(systemName: category.icon)
                }
                .onAppear {
                    name = category.name
                    nameFocused = true
                }
            } else {
                Label(category.name, systemImage: category.icon)
                    .lineLimit(1)
                    .badge(store.count(in: category.id))
            }
        }
        .listRowBackground(
            isTargeted ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.25)) : nil
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            AssetDrop.handle(providers, categoryID: category.id, studio: studio)
        }
        .contextMenu { AssetCategoryMenu(category: category) }
    }

    private func commit() {
        let store = studio.assets
        guard store.renamingCategoryID == category.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != category.name {
            store.updateCategory(category.id) { $0.name = trimmed }
            // Eigene Kategorie ohne Rolle: Gemma schlägt das englische Thema vor („Frisuren“ → „hairstyle“).
            if category.id.hasPrefix("kategorie-"), category.role == .general, category.customSubject == nil {
                studio.suggestAssetSubject(for: category.id, fallbackToName: false)
            }
        }
        store.renamingCategoryID = nil
    }
}

/// Ein Asset-Bereich in der Seitenleiste: umbenennen, Bilder ablegen (landen in seiner ersten Kategorie).
private struct AssetSectionRow: View {
    @Environment(Studio.self) private var studio
    let section: AssetSection
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var name = ""
    @State private var isTargeted = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let store = studio.assets
        Group {
            if store.renamingSectionID == section.id {
                Label {
                    TextField("Bereich", text: $name)
                        .focused($nameFocused)
                        .onSubmit(commit)
                        .onExitCommand { store.renamingSectionID = nil }
                        .onChange(of: nameFocused) { if !nameFocused { commit() } }
                } icon: {
                    Image(systemName: section.icon)
                }
                .onAppear {
                    name = section.name
                    nameFocused = true
                }
            } else {
                HStack(spacing: 4) {
                    Button(action: toggle) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Zuklappen" : "Aufklappen")
                    .accessibilityLabel(isExpanded ? "Bereich zuklappen" : "Bereich aufklappen")
                    Label(section.name, systemImage: section.icon)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .badge(store.count(inSection: section.id))
            }
        }
        .listRowBackground(
            isTargeted ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.25)) : nil
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            guard let first = store.categories(in: section.id).first else { return false }
            return AssetDrop.handle(providers, categoryID: first.id, studio: studio)
        }
        .contextMenu { AssetSectionMenu(section: section) }
    }

    private func commit() {
        let store = studio.assets
        guard store.renamingSectionID == section.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.updateSection(section.id) { $0.name = trimmed } }
        store.renamingSectionID = nil
    }
}
