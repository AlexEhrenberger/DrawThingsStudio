import SwiftUI
import UniformTypeIdentifiers

/// Charakter in der Galerie: oben die Reiter, darunter die Seite zum Aufbauen oder seine Bilder und Videos
/// als Raster – mit Leiste und Filtern wie unter „Alle Bilder“.
struct CharacterScreen: View {
    @Environment(Studio.self) private var studio
    let personaID: UUID
    let entries: [GalleryEntry]
    var isFocus = false

    var body: some View {
        @Bindable var gallery = studio.gallery
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $gallery.personaTab) {
                ForEach(PersonaTab.allCases) { tab in
                    Text(tab == .media ? "\(tab.title) (\(gallery.count(.persona(personaID))))" : tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 14)
            .padding(.bottom, gallery.personaTab == .media ? 0 : 4)
            if gallery.personaTab == .character {
                CharacterPage(personaID: personaID)
            } else if entries.isEmpty {
                if isFocus {
                    ContentUnavailableView("Keine Bilder", systemImage: GalleryCollection.persona(personaID).symbol)
                        .frame(maxHeight: .infinity)
                } else {
                    GalleryEmptyState()
                        .frame(maxHeight: .infinity)
                }
            } else {
                GalleryGrid(entries: entries, isFocus: isFocus)
            }
        }
    }
}

/// Seite eines Charakters: Fotos mit Blickrichtung, Referenz für Draw Things, Beschreibung
/// und Test Raster gegen Einzelfoto. Seine Bilder zeigt der Reiter „Bilder & Videos“.
struct CharacterPage: View {
    @Environment(Studio.self) private var studio
    let personaID: UUID

    @State private var isDropTargeted = false

    var body: some View {
        if let persona = studio.personas.persona(personaID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    CharacterHeader(persona: persona)
                    ConsentCard(persona: persona)
                    PhotosSection(persona: persona)
                    HStack(alignment: .top, spacing: 20) {
                        SheetPreviewCard(persona: persona)
                            .frame(width: 320)
                        VStack(alignment: .leading, spacing: 20) {
                            DescriptionCard(persona: persona)
                            TestCard(persona: persona)
                        }
                    }
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .padding(10)
                        .overlay {
                            Label("Als Fotos von \(persona.name) hinzufügen", systemImage: "person.crop.square.badge.plus")
                                .font(.title2.weight(.semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .glassEffect(.regular, in: .capsule)
                        }
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                PersonaDrop.handle(providers, personaID: personaID, studio: studio)
            }
        } else {
            ContentUnavailableView("Charakter nicht gefunden", systemImage: "person.crop.square")
        }
    }
}

/// Fotos aus dem Finder, Bilddaten oder Kacheln aus der Galerie aufnehmen
/// (aus der Galerie gezogen: die ganze Auswahl bzw. der ganze Stapel).
enum PersonaDrop {
    @MainActor
    static func handle(_ providers: [NSItemProvider], personaID: UUID, studio: Studio) -> Bool {
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
                studio.addGalleryItems(drag.ids, toPersona: personaID)
                urls = []
            }
            studio.gallery.drag = nil
            if !urls.isEmpty { studio.addPersonaPhotos(urls: urls, to: personaID) }
            if !images.isEmpty { studio.addPersonaPhotos(images, to: personaID) }
        }
        return true
    }
}

// MARK: - Kopf

private struct CharacterHeader: View {
    @Environment(Studio.self) private var studio
    let persona: Persona

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            PersonaAvatar(persona: persona, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(persona.name)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(1)
                Text(summary)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button {
                studio.usePersonaInStudio(persona.id)
            } label: {
                Label("Im Studio verwenden", systemImage: "photo.stack")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(persona.mainPhoto == nil)
            .help("In „Mit Referenzen arbeiten“ als Person (Bild 1) einsetzen")
        }
    }

    private var summary: String {
        let images = studio.gallery.count(.persona(persona.id))
        var parts = [persona.photos.count == 1 ? "1 Foto" : "\(persona.photos.count) Fotos"]
        if images > 0 { parts.append(images == 1 ? "1 Bild generiert" : "\(images) Bilder generiert") }
        parts.append("Referenz: \(persona.referenceMode.title)")
        return parts.joined(separator: " · ")
    }
}

/// Rundes Gesicht aus dem Hauptfoto.
struct PersonaAvatar: View {
    let persona: Persona
    var size: CGFloat = 20

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.08))
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: persona.mainPhoto?.id) { image = await avatar() }
    }

    /// Gesicht aus dem Hauptfoto, quadratisch zugeschnitten.
    private func avatar() async -> CGImage? {
        guard let photo = persona.mainPhoto, let full = await PersonaImages.image(photo, of: persona.id) else { return nil }
        let imageSize = CGSize(width: full.width, height: full.height)
        guard let face = photo.face else { return await PersonaImages.thumbnail(photo, of: persona.id) }
        let crop = CharacterSheet.faceCrop(face: face, imageSize: imageSize, aspect: 1, zoom: 1.7)
        return full.cropping(to: crop).map { ImageTools.scaled($0, maxSide: 160) }
    }
}

// MARK: - Einverständnis

private struct ConsentCard: View {
    @Environment(Studio.self) private var studio
    let persona: Persona

    var body: some View {
        let store = studio.personas
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: Binding(get: { persona.hasConsent }, set: { value in store.update(persona.id) { $0.hasConsent = value } })) {
                Text("Einverständnis liegt vor")
                    .fontWeight(.medium)
            }
            .toggleStyle(.checkbox)
            TextField(
                "Wann, wofür – z. B. „Hochzeit, 12.10.2026, mündlich“",
                text: Binding(get: { persona.consentNote }, set: { value in store.update(persona.id) { $0.consentNote = value } })
            )
            .textFieldStyle(.roundedBorder)
            if !persona.hasConsent {
                Label("Nur mit Einverständnis der Person verwenden", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize()
            }
        }
        .card(padding: 12)
    }
}

// MARK: - Fotos

private struct PhotosSection: View {
    @Environment(Studio.self) private var studio
    let persona: Persona

    @State private var showsLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fotos")
                    .font(.title3.weight(.semibold))
                Text("frontal, ¾ von beiden Seiten, Profil und eine Ganzkörperaufnahme – gleichmäßiges Licht, neutraler Ausdruck, ohne Sonnenbrille")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Menu("Fotos hinzufügen …", systemImage: "plus") {
                    Button("Aus der Bibliothek …", systemImage: "photo.on.rectangle") { showsLibrary = true }
                    Button("Aus Dateien …", systemImage: "folder") { studio.choosePersonaPhotos(for: persona.id) }
                }
                .fixedSize()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(persona.photos) { photo in
                    PhotoCard(persona: persona, photo: photo, isMain: persona.mainPhoto?.id == photo.id)
                }
                ForEach(studio.personas.importing.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 180)
                        .overlay { ProgressView().controlSize(.small) }
                }
                AddPhotoCard(personaID: persona.id) { showsLibrary = true }
            }
        }
        .sheet(isPresented: $showsLibrary) {
            LibraryPicker(
                title: "Fotos für „\(persona.name)“ aus der Bibliothek",
                subtitle: "Ansicht (frontal, ¾, Profil …) erkennt die App, du kannst sie je Foto ändern",
                allowsMultiple: true,
                onPick: { studio.addGalleryItems([$0.id], toPersona: persona.id) },
                onPickMany: { studio.addGalleryItems($0.map(\.id), toPersona: persona.id) }
            )
        }
        .onAppear(perform: takeLibraryRequest)
        .onChange(of: studio.personaLibraryRequest) { takeLibraryRequest() }
    }

    /// Das Kontextmenü des Charakters in der Seitenleiste bittet um die Bibliotheksauswahl.
    private func takeLibraryRequest() {
        guard studio.personaLibraryRequest == persona.id else { return }
        studio.personaLibraryRequest = nil
        showsLibrary = true
    }
}

private struct PhotoCard: View {
    @Environment(Studio.self) private var studio
    let persona: Persona
    let photo: PersonaPhoto
    let isMain: Bool

    @State private var image: CGImage?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.primary.opacity(0.06)
                if let image {
                    GeometryReader { proxy in
                        let fitted = fit(CGSize(width: image.width, height: image.height), in: proxy.size)
                        ZStack(alignment: .topLeading) {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .frame(width: fitted.width, height: fitted.height)
                            // Erkanntes Gesicht.
                            if let face = photo.face {
                                Rectangle()
                                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                    .frame(width: face.width * fitted.width, height: face.height * fitted.height)
                                    .offset(x: face.minX * fitted.width, y: face.minY * fitted.height)
                            }
                        }
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                if isMain {
                    Label("Hauptbild", systemImage: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                        .padding(6)
                        .help("Großes Feld im Raster und Foto für „Einzelfoto“")
                }
            }
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button {
                        studio.removePersonaPhoto(photo.id, from: persona.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Foto entfernen")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if photo.face == nil {
                    Text("kein Gesicht erkannt")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .padding(6)
                }
            }
            Picker("Ansicht", selection: Binding(get: { photo.view }, set: { studio.setPersonaPhotoView($0, of: photo.id, in: persona.id) })) {
                ForEach(PersonaView.allCases) { view in
                    Label(view.title, systemImage: view.symbol).tag(view)
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .onHover { isHovering = $0 }
        .task(id: photo.id) { image = await PersonaImages.thumbnail(photo, of: persona.id) }
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private struct AddPhotoCard: View {
    @Environment(Studio.self) private var studio
    let personaID: UUID
    let onLibrary: () -> Void
    @State private var isTargeted = false

    var body: some View {
        Menu {
            Button("Aus der Bibliothek …", systemImage: "photo.on.rectangle", action: onLibrary)
            Button("Aus Dateien …", systemImage: "folder") { studio.choosePersonaPhotos(for: personaID) }
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(height: 180)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.square.badge.plus")
                            .font(.title)
                        Text("Fotos hierher ziehen\noder klicken")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            PersonaDrop.handle(providers, personaID: personaID, studio: studio)
        }
    }
}

// MARK: - Referenz für Draw Things

/// Vorschau des Referenzbildes – Raster oder Einzelfoto, in verschiedenen Formaten.
private struct SheetPreviewCard: View {
    @Environment(Studio.self) private var studio
    let persona: Persona

    @State private var ratio = 3.0 / 4.0
    @State private var preview: CGImage?

    private static let formats: [(title: String, ratio: Double)] = [("3:4", 3.0 / 4.0), ("1:1", 1), ("16:9", 16.0 / 9.0)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Referenz für Draw Things")
                .font(.headline)
            Picker("Referenz", selection: Binding(get: { persona.referenceMode }, set: { mode in
                studio.personas.update(persona.id) { $0.referenceMode = mode }
            })) {
                ForEach(PersonaReferenceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let preview {
                    CGImageView(image: preview)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        .padding(8)
                } else if persona.photos.isEmpty {
                    Text("Noch keine Fotos")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(height: 340)

            Picker("Format", selection: $ratio) {
                ForEach(Self.formats, id: \.ratio) { format in
                    Text(format.title).tag(format.ratio)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(persona.referenceMode == .sheet
                 ? "Das Raster wird bei jedem Bild passend zum Format neu zusammengesetzt: großes Frontalporträt, daneben bis zu drei Ansichten, ohne Beschriftung."
                 : "Nur das Hauptbild – Kopf und Schultern, so groß wie möglich.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .task(id: PreviewKey(persona: persona, ratio: ratio)) {
            preview = await CharacterSheet.render(persona, mode: persona.referenceMode, size: studio.pixelSize(for: ratio))
        }
    }

    private struct PreviewKey: Equatable {
        let persona: Persona
        let ratio: Double
    }
}

// MARK: - Beschreibung

private struct DescriptionCard: View {
    @Environment(Studio.self) private var studio
    let persona: Persona

    var body: some View {
        let isDescribing = studio.describingPersonaID == persona.id
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Beschreibung")
                    .font(.headline)
                Text("Text-Anker im Prompt (englisch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    studio.describePersona(persona.id)
                } label: {
                    if isDescribing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Gemma beschreibt …")
                        }
                    } else {
                        Label(persona.description.isEmpty ? "Von Gemma beschreiben lassen" : "Neu beschreiben", systemImage: "sparkles")
                    }
                }
                .disabled(isDescribing || studio.describingPersonaID != nil || persona.mainPhoto == nil)
                .controlSize(.small)
            }
            TextField(
                "Haare, Augen, Gesichtsform, Merkmale – Gemma füllt das nach dem ersten Foto aus.",
                text: Binding(get: { persona.description }, set: { studio.setPersonaDescription($0, of: persona.id) }),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(3...8)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
        }
        .card()
    }
}

// MARK: - Test

private struct TestCard: View {
    @Environment(Studio.self) private var studio
    let persona: Persona

    private var test: PersonaTest? {
        studio.personaTest.flatMap { $0.personaID == persona.id ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Test: Raster oder Einzelfoto?")
                .font(.headline)
            Text("Rendert dieselbe Szene zweimal mit gleichem Seed in 3:4 – einmal mit dem Raster, einmal nur mit dem Hauptbild. Die beiden Bilder liegen danach als Stapel in der Galerie, zum Vergleichen mit Synchron-Zoom.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Szene, z. B. „steht auf einem Steg am See, Abendlicht“", text: Bindable(studio.personas).testScene)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(start)
                Button("Test starten", systemImage: "play.fill", action: start)
                    .buttonStyle(.borderedProminent)
                    .disabled(studio.isBusy || persona.mainPhoto == nil || studio.personas.testScene.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help(studio.isBusy ? "Warte, bis Draw Things fertig ist." : "Zwei Bilder rendern – dauert etwa doppelt so lang wie ein Bild")
            }
            if let test {
                status(test)
            }
        }
        .card()
    }

    private func start() {
        studio.startPersonaTest(persona.id, scene: studio.personas.testScene)
    }

    @ViewBuilder
    private func status(_ test: PersonaTest) -> some View {
        switch test.phase {
        case .writing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Gemma schreibt die Szene auf Englisch …")
                    .font(.callout)
            }
        case .rendering(let mode):
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Draw Things rendert: \(mode.title) (\(mode == .sheet ? 1 : 2) / 2)")
                            .font(.callout)
                        Spacer()
                        Button("Abbrechen", systemImage: "stop.fill") { studio.cancelPersonaTest() }
                            .controlSize(.small)
                    }
                    GradientProgressBar(fraction: overall(test, mode: mode, at: context.date), height: 6)
                }
            }
        case .done:
            HStack {
                Label("Fertig – beide Bilder liegen in der Galerie", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Spacer()
                Button("Vergleichen", systemImage: "rectangle.split.2x1") { studio.openPersonaTestResults() }
                    .buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        case .cancelled:
            HStack {
                Label("Abgebrochen", systemImage: "stop.circle")
                    .font(.callout)
                if !test.resultIDs.isEmpty {
                    Spacer()
                    Button("Bisheriges ansehen") { studio.openPersonaTestResults() }
                        .controlSize(.small)
                }
            }
        }
        if !test.usedGemma, test.phase != .writing, !test.prompt.isEmpty {
            Text("Gemma war nicht erreichbar – die Szene ging so an Draw Things, wie du sie geschrieben hast.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func overall(_ test: PersonaTest, mode: PersonaReferenceMode, at date: Date) -> Double {
        let current = studio.generation?.fraction(at: date) ?? 0
        return (Double(mode == .sheet ? 0 : 1) + current) / 2
    }
}
