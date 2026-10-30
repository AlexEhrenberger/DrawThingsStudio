import SwiftUI

/// Bis zu drei Referenzbilder mit Rolle. Gemma beschreibt jedes Bild passend zur Rolle.
struct ReferencesPanel: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if studio.mode != .references {
                    Button {
                        studio.mode = .references
                    } label: {
                        Label("Zum Modus „Mit Referenzen arbeiten“ wechseln", systemImage: "photo.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !studio.filledReferences.isEmpty {
                        Button {
                            withAnimation(.smooth(duration: 0.2)) { studio.clearReferences() }
                        } label: {
                            Label("Alle entfernen", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .font(.callout)
                        .fixedSize()
                        .help("Alle Referenzbilder entfernen – ihre Sätze verschwinden aus dem Prompt")
                    }
                }

                ForEach(studio.references.indices, id: \.self) { index in
                    ReferenceCard(index: index)
                }
            }
            .padding(14)
        }
    }

    private var explanation: String {
        studio.settings.sendAllReferences
            ? "Alle Bilder gehen an Draw Things (experimentell) und heißen im Prompt „Picture 1“, „Picture 2“ …"
            : "Das erste Bild geht als „Picture 1“ an Draw Things. Die übrigen beschreibt Gemma – ihre Beschreibung landet im Prompt, weil die HTTP-API von Draw Things nur ein Eingabebild zuverlässig annimmt."
    }
}

private struct ReferenceCard: View {
    @Environment(Studio.self) private var studio
    let index: Int
    @State private var isDropTargeted = false
    @State private var showsLibrary = false

    private var slot: ReferenceSlot { studio.references[index] }

    /// Nummer im Prompt (leere Plätze zählen nicht mit).
    private var imageNumber: Int? {
        guard slot.image != nil else { return nil }
        return (studio.filledReferences.firstIndex { $0.id == slot.id } ?? 0) + 1
    }

    private var isSent: Bool { imageNumber == 1 || (imageNumber != nil && studio.settings.sendAllReferences) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Bild \(index + 1)")
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                if slot.image != nil {
                    Text(isSent ? "an Draw Things" : "als Beschreibung")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isSent ? Color.accentColor.opacity(0.18) : GemmaStyle.tint.opacity(0.15)))
                        .foregroundStyle(isSent ? Color.accentColor : GemmaStyle.tint)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer()
                Menu {
                    ForEach(ReferenceRole.allCases) { role in
                        Button {
                            studio.setReferenceRole(role, at: index)
                        } label: {
                            Label(role.title, systemImage: role.symbol)
                        }
                    }
                } label: {
                    Label(slot.role.title, systemImage: slot.role.symbol)
                }
                .menuStyle(.button)
                .controlSize(.small)
                .fixedSize()
            }

            dropZone

            if let assetID = slot.assetID, let asset = studio.assets.asset(assetID) {
                HStack(spacing: 8) {
                    Image(systemName: studio.assets.category(asset.categoryID)?.icon ?? "shippingbox")
                        .foregroundStyle(.secondary)
                    Text(asset.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    assetMenu
                        .labelStyle(.iconOnly)
                        .controlSize(.small)
                }
            }

            if let personaID = slot.personaID, let persona = studio.personas.persona(personaID) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        PersonaAvatar(persona: persona, size: 22)
                        Text(persona.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        personaMenu
                            .labelStyle(.iconOnly)
                    }
                    Picker("Referenz", selection: Binding(get: { slot.personaMode }, set: { studio.setPersonaMode($0, at: index) })) {
                        ForEach(PersonaReferenceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .help("Raster aus mehreren Ansichten oder nur das Hauptbild – wird beim Rendern passend zum Format erstellt")
                }
            }

            if slot.image != nil {
                if slot.isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Gemma beschreibt \(slot.role.title.lowercased()) …")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField(
                        "Beschreibung",
                        text: Binding(get: { slot.description }, set: { studio.setReferenceDescription($0, at: index) }),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(2...7)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
                    HStack {
                        Button("Neu beschreiben", systemImage: "sparkles") { studio.describeReference(at: index) }
                            .buttonStyle(.borderless)
                        Spacer()
                        Button("Entfernen", systemImage: "trash", role: .destructive) { studio.removeReference(at: index) }
                            .buttonStyle(.borderless)
                    }
                    .font(.caption)
                }
                if let error = slot.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                FlowLayout(spacing: 8, lineSpacing: 6) {
                    Button("Bibliothek", systemImage: "photo.on.rectangle") { showsLibrary = true }
                        .help("Bild aus der Bibliothek wählen – wie die Fotoauswahl in macOS")
                    if let current = studio.current {
                        Button("Canvas-Bild", systemImage: "arrow.down.right.and.arrow.up.left") {
                            studio.setReference(current.image, at: index)
                        }
                        .help("Das Bild, das gerade auf dem Canvas liegt, als Bild \(index + 1) übernehmen")
                    }
                    personaMenu
                    assetMenu
                }
                .controlSize(.small)
            }
        }
        .card()
        .sheet(isPresented: $showsLibrary) {
            LibraryPicker(title: "Bild \(index + 1) aus der Bibliothek", subtitle: "Referenz als „\(slot.role.title)“ – Doppelklick oder ↩ übernimmt") { item in
                Task { await studio.setReference(from: item, at: index) }
            }
        }
    }

    /// Asset aus dem Asset-Baukasten einsetzen – mit der Rolle seiner Kategorie.
    private var assetMenu: some View {
        Menu {
            ForEach(studio.assets.sections) { section in
                let categories = studio.assets.categories(in: section.id).filter { studio.assets.count(in: $0.id) > 0 }
                if !categories.isEmpty {
                    Section(section.name) {
                        ForEach(categories) { category in
                            Menu {
                                ForEach(studio.assets.assets(in: category.id)) { asset in
                                    Button {
                                        studio.setAsset(asset.id, at: index)
                                    } label: {
                                        Label(asset.name, systemImage: slot.assetID == asset.id ? "checkmark" : category.icon)
                                    }
                                }
                            } label: {
                                Label(category.name, systemImage: category.icon)
                            }
                        }
                    }
                }
            }
            if !studio.assets.assets.isEmpty { Divider() }
            Button("Assets verwalten …", systemImage: "shippingbox") {
                studio.gallery.collection = .assets(nil)
                studio.showGallery = true
            }
        } label: {
            Label(slot.assetID == nil ? "Asset" : "Anderes Asset", systemImage: slot.assetID == nil ? "shippingbox" : "arrow.triangle.2.circlepath")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Bild aus dem Asset-Baukasten verwenden – Kleidung, Schuhe, Orte, Gesamtreferenzen")
    }

    /// Charakter aus der Galerie als Person einsetzen.
    private var personaMenu: some View {
        Menu {
            ForEach(studio.personas.personas) { persona in
                Button {
                    studio.setPersona(persona.id, at: index)
                } label: {
                    Label(persona.name, systemImage: slot.personaID == persona.id ? "checkmark" : "person.crop.square")
                }
                .disabled(persona.mainPhoto == nil)
            }
            if !studio.personas.personas.isEmpty { Divider() }
            Button("Charaktere verwalten …", systemImage: "person.2.crop.square.stack") {
                studio.gallery.collection = studio.personas.personas.first.map { .persona($0.id) } ?? .persona(studio.personas.create())
                studio.gallery.personaTab = .character
                studio.showGallery = true
            }
        } label: {
            Label(slot.personaID == nil ? "Charakter" : "Anderer Charakter", systemImage: slot.personaID == nil ? "person.crop.square" : "arrow.triangle.2.circlepath")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Charakter als Person verwenden – Raster oder Einzelfoto geht als Bild an Draw Things")
    }

    private func chooseFile() {
        if let image = studio.chooseImage(message: "Referenzbild \(index + 1) wählen") {
            studio.setReference(image, at: index)
        }
    }

    private var dropZone: some View {
        ZStack {
            if let thumbnail = slot.thumbnail, slot.personaID != nil {
                // Raster eines Charakters: ganz zeigen, nicht beschneiden.
                CGImageView(image: thumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
            } else if let thumbnail = slot.thumbnail {
                CGImageView(image: thumbnail, contentMode: .fill)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(height: 96)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.viewfinder")
                                .font(.title2)
                            Text("Bild hierher ziehen oder klicken")
                                .font(.caption)
                            Text("Rechtsklick: aus der Bibliothek")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                    }
            }
        }
        .overlay {
            if isDropTargeted && slot.image != nil {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: chooseFile)
        .contextMenu {
            Button(slot.image == nil ? "Aus der Bibliothek …" : "Durch Bild aus der Bibliothek ersetzen …", systemImage: "photo.on.rectangle") {
                showsLibrary = true
            }
            Button("Datei wählen …", systemImage: "folder", action: chooseFile)
            if let current = studio.current {
                Button("Canvas-Bild übernehmen", systemImage: "arrow.down.right.and.arrow.up.left") {
                    studio.setReference(current.image, at: index)
                }
            }
            if slot.image != nil {
                Divider()
                Button("Entfernen", systemImage: "trash", role: .destructive) { studio.removeReference(at: index) }
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            Task {
                if let image = await DropLoader.loadImage(from: providers) { studio.setReference(image, at: index) }
            }
            return true
        }
    }
}
