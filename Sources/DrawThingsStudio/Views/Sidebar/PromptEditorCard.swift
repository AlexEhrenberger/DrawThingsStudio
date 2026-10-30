import SwiftUI

/// Oben in der Seitenleiste: der Prompt selbst, Gemma und die Bibliothek.
struct PromptEditorCard: View {
    @Environment(Studio.self) private var studio
    @FocusState private var editorFocused: Bool
    @FocusState private var wishFocused: Bool
    @State private var showLibrary = false
    @State private var copied = false

    private var builder: PromptBuilder { studio.builder }

    private var wordCount: Int {
        builder.prompt.split { $0.isWhitespace || $0.isNewline }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            editor
            gemmaBar
            if studio.optimizer.isVisible {
                OptimizerCard()
                    .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: studio.optimizer.isVisible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Prompt")
                .font(.title3.weight(.semibold))
            Text(studio.mode.modelName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            Spacer()
            if builder.isEdited && !builder.prompt.isEmpty {
                Image(systemName: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Von Hand bearbeitet – Bausteine ändern nur noch ihre eigenen Sätze.")
            }
            Button {
                showLibrary = true
            } label: {
                Image(systemName: "books.vertical")
            }
            .buttonStyle(.borderless)
            .help("Bibliothek")
            .popover(isPresented: $showLibrary, arrowEdge: .bottom) {
                LibraryPopover(isPresented: $showLibrary)
            }
            Menu {
                Button("In Bibliothek sichern", systemImage: "bookmark") { studio.savePromptToLibrary() }
                    .disabled(builder.prompt.isEmpty)
                Button("Prompt kopieren", systemImage: "doc.on.doc") { copy() }
                    .disabled(builder.prompt.isEmpty)
                Divider()
                Button("Bausteine neu zusammensetzen", systemImage: "arrow.triangle.2.circlepath") {
                    builder.replacePrompt("")
                    builder.recompose()
                }
                Button("Alles zurücksetzen", systemImage: "trash", role: .destructive) { builder.reset() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: { builder.prompt }, set: { builder.editPrompt($0) }))
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .padding(.horizontal, 5)
                    .padding(.top, 7)
                if builder.prompt.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 7)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 170)

            HStack(spacing: 10) {
                Text(wordCount == 1 ? "1 Wort" : "\(wordCount) Wörter")
                    .font(.caption)
                    .foregroundStyle(wordCount > 200 ? Color.orange : Color.secondary)
                    .monospacedDigit()
                Spacer()
                Button {
                    copy()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .disabled(builder.prompt.isEmpty)
                .help("Prompt kopieren")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.75)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(editorFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: editorFocused ? 1.5 : 0.5)
        )
    }

    private var placeholder: String {
        switch studio.mode {
        case .generate: "Beschreibe das Bild – oder wähle unten Bausteine …"
        case .edit: "Was soll sich am Bild ändern? Deutsch geht auch – Gemma übersetzt."
        case .references: "Was soll aus den Referenzen entstehen?"
        case .series: "Optional: gilt für alle Bilder der Serie, z. B. „sie lächelt in die Kamera“. Die Varianten legst du rechts fest."
        }
    }

    private var gemmaBar: some View {
        @Bindable var studio = studio
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(GemmaStyle.gradient)
                TextField("Wunsch an Gemma, z. B. „mach eine Nachtszene“", text: $studio.gemmaWish)
                    .textFieldStyle(.plain)
                    .focused($wishFocused)
                    .onSubmit { studio.optimizePrompt() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(wishFocused ? GemmaStyle.tint.opacity(0.6) : Color.clear, lineWidth: 1))

            Button {
                studio.optimizePrompt()
            } label: {
                Label("Optimieren", systemImage: "wand.and.sparkles")
            }
            .buttonStyle(.glassProminent)
            .tint(GemmaStyle.tint)
            .disabled(studio.optimizer.isRunning || (builder.prompt.isEmpty && studio.gemmaWish.isEmpty))
            .help("Gemma schreibt den Prompt für \(studio.mode.modelName) um (⌥⌘O)")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(builder.prompt, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }
}

/// Gemmas Vorschlag – live geschrieben, dann übernehmen oder verwerfen.
struct OptimizerCard: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let optimizer = studio.optimizer
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(GemmaStyle.gradient)
                    .symbolEffect(.pulse, isActive: optimizer.isRunning)
                Text(optimizer.isRunning ? "Gemma schreibt …" : "Vorschlag für \(optimizer.mode.modelName)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if optimizer.isRunning {
                    ProgressView().controlSize(.small)
                }
            }
            if !optimizer.text.isEmpty {
                ScrollView {
                    Text(optimizer.text)
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let error = optimizer.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Verwerfen") { studio.discardOptimizedPrompt() }
                    .buttonStyle(.bordered)
                Button("Übernehmen") { studio.acceptOptimizedPrompt() }
                    .buttonStyle(.borderedProminent)
                    .tint(GemmaStyle.tint)
                    .disabled(optimizer.isRunning || optimizer.text.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GemmaStyle.tint.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GemmaStyle.gradient.opacity(optimizer.isRunning ? 0.9 : 0.45), lineWidth: 1)
        )
    }
}

/// Gesicherte Prompts.
struct LibraryPopover: View {
    @Environment(Studio.self) private var studio
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bibliothek").font(.headline)
                Spacer()
                Button("Aktuellen sichern", systemImage: "bookmark") { studio.savePromptToLibrary() }
                    .controlSize(.small)
                    .disabled(studio.builder.prompt.isEmpty)
            }
            .padding(12)
            Divider()
            if studio.library.isEmpty {
                ContentUnavailableView("Noch leer", systemImage: "books.vertical", description: Text("Sichere Prompts, die du wiederverwenden willst."))
                    .frame(height: 200)
            } else {
                List {
                    ForEach(studio.library) { entry in
                        Button {
                            studio.builder.replacePrompt(entry.text)
                            studio.mode = entry.mode
                            isPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.text)
                                    .font(.callout)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 4) {
                                    Image(systemName: entry.mode.symbol)
                                    Text(entry.mode.title)
                                    Text("·")
                                    Text(entry.savedAt, format: .dateTime.day().month().hour().minute())
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Löschen", systemImage: "trash", role: .destructive) { studio.deleteFromLibrary(entry) }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { studio.library[$0] }.forEach(studio.deleteFromLibrary)
                    }
                }
                .listStyle(.inset)
                .frame(height: 320)
            }
        }
        .frame(width: 380)
    }
}
