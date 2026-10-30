import SwiftUI

/// Serie einrichten: Ausgangsbild, Variable und bis zu vier Varianten.
struct SeriesPanel: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if studio.mode != .series {
                    Button {
                        studio.mode = .series
                    } label: {
                        Label("Zum Modus „Serien“ wechseln", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Aus einem Ausgangsbild entstehen bis zu vier Varianten, die sich nur in einer Variable unterscheiden. Gemma schreibt für jede Variante den Prompt, Draw Things rendert sie nacheinander – alle Bilder landen im Verlauf und in der Bibliothek.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SeriesSourceCard()
                SeriesVariableCard()
                SeriesValuesCard()

                if studio.mode == .series {
                    SeriesStartSection()
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Ausgangsbild

private struct SeriesSourceCard: View {
    @Environment(Studio.self) private var studio
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ausgangsbild")
                    .font(.headline)
                Spacer()
                if let source = studio.seriesSource {
                    Text("\(Format.size(source.size)) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            dropZone

            HStack {
                if let current = studio.current, !studio.currentIsSeriesSource {
                    Button("Aktuelles Bild übernehmen", systemImage: "arrow.down.right.and.arrow.up.left") {
                        studio.setSeriesSource(current)
                    }
                    .help("Das zuletzt gewählte Bild aus dem Verlauf als Ausgangsbild verwenden")
                }
                Spacer()
                if studio.seriesSource != nil {
                    Button("Entfernen", systemImage: "trash", role: .destructive) { studio.clearSeriesSource() }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .card()
    }

    private var dropZone: some View {
        ZStack {
            if let source = studio.seriesSource {
                CGImageView(image: source.thumbnail, contentMode: .fit)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(height: 110)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.viewfinder")
                                .font(.title2)
                            Text("Bild hierher ziehen oder klicken")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
            }
        }
        .overlay {
            if isDropTargeted && studio.seriesSource != nil {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let image = studio.chooseImage(message: "Ausgangsbild für die Serie wählen") {
                studio.importSeriesSource(image)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            Task {
                if let image = await DropLoader.loadImage(from: providers) { studio.importSeriesSource(image) }
            }
            return true
        }
        .help("Klicken, um ein anderes Bild zu wählen")
    }
}

// MARK: - Variable

private struct SeriesVariableCard: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        VStack(alignment: .leading, spacing: 10) {
            Text("Was ändert sich?")
                .font(.headline)

            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(SeriesVariable.allCases) { variable in
                    Chip(title: variable.title, isOn: studio.seriesSetup.variable == variable) {
                        studio.seriesSetup.variable = variable
                    }
                    .help(variable.hint)
                }
            }

            if studio.seriesSetup.variable == .custom {
                TextField("Name der Variable", text: $studio.seriesSetup.customName, prompt: Text("Name der Variable, z. B. Accessoire").foregroundStyle(.tertiary))
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .fieldBackground()
            }

            Label(studio.seriesSetup.variable.hint, systemImage: studio.seriesSetup.variable.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

// MARK: - Varianten

private struct SeriesValuesCard: View {
    @Environment(Studio.self) private var studio
    @FocusState private var focusedField: Int?

    private var setup: SeriesSetup { studio.seriesSetup }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Varianten")
                    .font(.headline)
                Text("\(setup.filledValues.count) von \(SeriesSetup.maxCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if !setup.variable.catalogKeys.isEmpty {
                    catalogMenu
                }
                if !setup.filledValues.isEmpty {
                    Button {
                        studio.seriesSetup.values = Array(repeating: "", count: SeriesSetup.maxCount)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Alle Felder leeren")
                }
            }

            ForEach(0..<SeriesSetup.maxCount, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isFilled(index) ? Color.white : Color.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isFilled(index) ? Color.accentColor : Color.primary.opacity(0.08)))
                    TextField(
                        "Variante \(index + 1)",
                        text: Binding(get: { studio.seriesSetup.values[index] }, set: { studio.setSeriesValue($0, at: index) }),
                        prompt: Text(placeholder(index)).foregroundStyle(.tertiary)
                    )
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($focusedField, equals: index)
                    .onSubmit { focusedField = index + 1 < SeriesSetup.maxCount ? index + 1 : nil }
                    .fieldBackground(isFocused: focusedField == index)
                }
            }

            Text("Kurz auf Deutsch reicht – Gemma macht daraus für jedes Bild einen genauen englischen Prompt. Leere Felder werden übersprungen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func isFilled(_ index: Int) -> Bool {
        !setup.values[index].trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func placeholder(_ index: Int) -> String {
        let examples = setup.variable.examples
        return "z. B. " + examples[index % examples.count]
    }

    /// Bausteine der passenden Kategorien als Schnellauswahl – füllt das nächste freie Feld.
    private var catalogMenu: some View {
        Menu {
            ForEach(setup.variable.catalogKeys, id: \.self) { key in
                if let group = Catalog.shared.group(key) {
                    Menu(group.name) {
                        ForEach(group.options) { option in
                            Button(option.name) { studio.addSeriesValue(option.name) }
                        }
                    }
                }
            }
        } label: {
            Label("Bausteine", systemImage: "square.grid.3x3.topleft.filled")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .disabled(!studio.seriesHasFreeField)
        .help(studio.seriesHasFreeField ? "Baustein ins nächste freie Feld übernehmen" : "Alle vier Felder sind belegt")
    }
}

// MARK: - Start

private struct SeriesStartSection: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        let count = studio.seriesSetup.filledValues.count
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Gleicher Seed für alle Bilder", isOn: $studio.seriesSetup.sameSeed)
                .disabled(!studio.settings.randomSeed)
                .help(studio.settings.randomSeed
                      ? "Dann unterscheiden sich die Bilder nur durch die Variable – gut zum Vergleichen."
                      : "Der Seed kommt aus Draw Things (in den Einstellungen ist „Zufälliger Seed“ aus).")

            Button {
                if studio.isBusy { studio.cancelGeneration() } else { studio.startSeries() }
            } label: {
                Label(
                    studio.isBusy ? "Abbrechen" : (count == 1 ? "Serie starten · 1 Bild" : "Serie starten · \(count) Bilder"),
                    systemImage: studio.isBusy ? "stop.fill" : "square.grid.2x2.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(studio.isBusy ? Color.red : Color.accentColor)
            .disabled(!studio.isBusy && studio.seriesBlocker != nil)

            if !studio.isBusy {
                if let blocker = studio.seriesBlocker {
                    Text(blocker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let estimate = studio.seriesEstimate(count: count) {
                    Text("Dauer ca. \(Format.duration(estimate)) min · \(studio.mode.modelName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("Geschätzt aus dem letzten Durchlauf von „Bearbeiten“ bzw. einer Serie")
                }
            }
        }
        .padding(.top, 4)
    }
}

private extension View {
    /// Eingabefeld im Stil der Seitenleiste.
    func fieldBackground(isFocused: Bool = false) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}
