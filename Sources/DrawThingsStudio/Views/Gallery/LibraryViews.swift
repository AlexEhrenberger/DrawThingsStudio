import SwiftUI

/// Bibliothek wählen, anlegen, öffnen, löschen – unten in der Seitenleiste der Galerie.
struct LibraryMenu: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let libraries = studio.libraries
        let others = libraries.dropFirst()
        Menu {
            Section("Bibliotheken") {
                ForEach(libraries) { entry in
                    let isCurrent = entry.url.standardizedFileURL == Library.root
                    Button {
                        if !isCurrent { studio.openLibrary(entry.url) }
                    } label: {
                        if isCurrent {
                            Label("\(entry.name) · \(entry.place)", systemImage: "checkmark")
                        } else {
                            Text(entry.isAvailable ? "\(entry.name) · \(entry.place)" : "\(entry.name) · \(entry.place) – nicht verfügbar")
                        }
                    }
                    .disabled(!isCurrent && !entry.isAvailable)
                }
            }
            Divider()
            Button("Neue Bibliothek …", systemImage: "plus") { studio.createLibraryWithPanel() }
            Button("Bibliothek öffnen …", systemImage: "folder") { studio.openLibraryWithPanel() }
            Divider()
            Button("Im Finder zeigen", systemImage: "arrow.up.forward.app") { studio.openLibraryFolder() }
                .disabled(!studio.isLibraryAvailable)
            if !others.isEmpty {
                Menu("Aus der Liste entfernen", systemImage: "minus.circle") {
                    ForEach(Array(others)) { entry in
                        Button(entry.name) { studio.forgetLibrary(entry) }
                    }
                }
            }
            Button("Bibliothek löschen …", systemImage: "trash", role: .destructive) {
                studio.libraryDeletion = libraries.first
            }
            .disabled(!studio.isLibraryAvailable)
        } label: {
            Label(studio.libraryName, systemImage: studio.isLibraryAvailable ? "books.vertical" : "externaldrive.badge.exclamationmark")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .help("Bibliothek: \(Library.root.path)")
    }
}

/// Die geöffnete Bibliothek fehlt – z. B. weil die SD-Karte nicht steckt oder der Ordner gelöscht wurde.
struct LibraryUnavailableView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let root = studio.gallery.root
        let onVolume = root.pathComponents.count > 2 && root.pathComponents[1] == "Volumes"
        let parentExists = Library.isAvailable(root.deletingLastPathComponent())
        VStack(spacing: 18) {
            Image(systemName: onVolume && !parentExists ? "externaldrive.badge.questionmark" : "questionmark.folder")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text(onVolume && !parentExists ? "„\(root.lastPathComponent)“ ist nicht erreichbar" : "„\(root.lastPathComponent)“ gibt es nicht mehr")
                    .font(.title2.weight(.semibold))
                Text(onVolume && !parentExists
                     ? "Die Bibliothek liegt auf „\(root.pathComponents[2])“. Steck das Laufwerk ein – die Galerie lädt dann von selbst."
                     : "Der Ordner \(root.path) fehlt. Öffne eine andere Bibliothek oder lege eine neue an.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            HStack(spacing: 10) {
                Button("Erneut prüfen", systemImage: "arrow.clockwise") { studio.refreshLibraryAvailability() }
                Button("Neue Bibliothek …", systemImage: "plus") { studio.createLibraryWithPanel() }
                Button("Bibliothek öffnen …", systemImage: "folder") { studio.openLibraryWithPanel() }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            let others = studio.libraries.dropFirst().filter(\.isAvailable)
            if !others.isEmpty {
                VStack(spacing: 6) {
                    Text("Andere Bibliotheken")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(others)) { entry in
                        Button("\(entry.name) · \(entry.place)") { studio.openLibrary(entry.url) }
                            .buttonStyle(.link)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(40)
    }
}

/// Rückfrage vor dem endgültigen Löschen einer Bibliothek – mit Übersicht, was alles verschwindet.
struct LibraryDeleteSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    let entry: LibraryEntry

    @State private var summary: LibrarySummary?
    @State private var confirmation = ""
    @State private var isDeleting = false

    private var isCurrent: Bool { entry.url.standardizedFileURL == Library.root }
    private var trashedCount: Int {
        let paths = isCurrent ? studio.gallery.trashedFiles : Gallery.trashedFiles(in: entry.url)
        return paths.filter { FileManager.default.fileExists(atPath: $0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bibliothek „\(entry.name)“ endgültig löschen?")
                        .font(.title3.weight(.semibold))
                    Text(entry.url.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Group {
                if let summary {
                    Text(summaryText(summary))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Inhalt wird gezählt …").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .card(padding: 10)

            VStack(alignment: .leading, spacing: 6) {
                Text("Gelöscht wird – nicht in den Papierkorb, sondern sofort:")
                    .font(.callout.weight(.semibold))
                bullet("der ganze Ordner: Bilder, Videos, Charakterfotos, Assets")
                bullet("der Katalog: Markierungen, Bewertungen, Notizen, Projekte, Beschreibungen, Vorschaubilder")
                if trashedCount > 0 {
                    bullet(trashedCount == 1 ? "1 Bild, das aus dieser Bibliothek noch im Papierkorb liegt"
                                             : "\(trashedCount) Bilder, die aus dieser Bibliothek noch im Papierkorb liegen")
                }
                bullet("die Vorschaubilder, die sich Finder und Quick Look gemerkt haben")
                if isCurrent {
                    bullet("im Studio: offenes Bild und Verlauf, Referenzen, Prompt, Serien-Werte und Analysen")
                }
            }
            .font(.callout)

            Text("Nicht erfasst sind Kopien an anderen Orten: Exporte, Time-Machine-Backups und der Verlauf in Draw Things selbst. Das Löschen lässt sich nicht rückgängig machen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Zum Bestätigen den Namen der Bibliothek eingeben:")
                    .font(.callout)
                TextField(entry.name, text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(delete)
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive, action: delete) {
                    if isDeleting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Endgültig löschen")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canDelete)
            }
        }
        .padding(22)
        .frame(width: 500)
        .task {
            let url = entry.url
            summary = await Task.detached(priority: .userInitiated) { LibrarySummary.measure(url) }.value
        }
    }

    private var canDelete: Bool {
        !isDeleting && confirmation.trimmingCharacters(in: .whitespaces) == entry.name
    }

    private func delete() {
        guard canDelete else { return }
        isDeleting = true
        Task {
            await studio.deleteLibrary(entry)
            isDeleting = false
            dismiss()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryText(_ summary: LibrarySummary) -> String {
        var parts = [summary.images == 1 ? "1 Bild" : "\(summary.images) Bilder"]
        if summary.videos > 0 { parts.append(summary.videos == 1 ? "1 Video" : "\(summary.videos) Videos") }
        if isCurrent {
            let personas = studio.personas.personas.count
            let assets = studio.assets.assets.count
            if personas > 0 { parts.append(personas == 1 ? "1 Charakter" : "\(personas) Charaktere") }
            if assets > 0 { parts.append(assets == 1 ? "1 Asset" : "\(assets) Assets") }
        }
        parts.append("\(summary.files) Dateien")
        parts.append(ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file))
        return parts.joined(separator: " · ")
    }
}
