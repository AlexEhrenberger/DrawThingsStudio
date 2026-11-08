import SwiftUI

/// Rechte Seite: klassische Werkzeuge, Analyse, Referenzen und Verlauf.
struct InspectorView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        VStack(spacing: 0) {
            Picker("Werkzeug", selection: $studio.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Image(systemName: tab.symbol)
                        .help(tab.title)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.top, 10)

            HStack {
                Text(studio.inspectorTab.title)
                    .font(.title3.weight(.semibold))
                Spacer()
                if studio.inspectorTab == .history, !studio.versions.isEmpty {
                    Text("\(studio.versions.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Group {
                switch studio.inspectorTab {
                case .adjust: AdjustPanel()
                case .crop: CropPanel()
                case .selection: SelectionPanel()
                case .analysis: AnalysisPanel()
                case .references: ReferencesPanel()
                case .series: SeriesPanel()
                case .history: HistoryPanel()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Platzhalter, solange kein Bild auf dem Canvas liegt.
struct NoImageView: View {
    let symbol: String
    let text: String

    var body: some View {
        ContentUnavailableView("Kein Bild", systemImage: symbol, description: Text(text))
    }
}

// MARK: - Anpassen

struct AdjustPanel: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if studio.current == nil {
            NoImageView(symbol: "slider.horizontal.3", text: "Generiere oder öffne ein Bild – dann kannst du es hier in Licht und Farbe anpassen.")
        } else {
            form
        }
    }

    private var form: some View {
        @Bindable var studio = studio
        return Form {
            Section {
                HistogramView()
                    .frame(height: 86)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                Toggle(isOn: $studio.adjustments.autoEnhance) {
                    Label("Auto-Verbessern", systemImage: "wand.and.rays")
                }
                .help("Apples automatische Bildverbesserung – dieselbe wie der Zauberstab in Fotos.")
                HStack {
                    Label("Weißabgleich", systemImage: "eyedropper")
                    Spacer()
                    if studio.adjustments.whiteBalance != nil {
                        Button("Zurück") { studio.adjustments.whiteBalance = nil }
                            .controlSize(.small)
                    }
                    Button(studio.isPickingWhiteBalance ? "Klicke ins Bild …" : "Pipette") {
                        studio.isPickingWhiteBalance.toggle()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .tint(studio.isPickingWhiteBalance ? Color.accentColor : nil)
                    .help("Auf eine Stelle klicken, die neutral grau oder weiß sein soll.")
                }
            } header: {
                Text("Automatisch")
            }

            Section("Licht") {
                AdjustSlider(title: "Belichtung", value: $studio.adjustments.exposure, spec: SliderSpecs.exposure)
                AdjustSlider(title: "Kontrast", value: $studio.adjustments.contrast, spec: SliderSpecs.contrast)
                AdjustSlider(title: "Lichter", value: $studio.adjustments.highlights, spec: SliderSpecs.highlights)
                AdjustSlider(title: "Tiefen", value: $studio.adjustments.shadows, spec: SliderSpecs.shadows)
            }

            Section {
                CurveEditor(values: $studio.adjustments.curve)
                    .frame(height: 170)
                    .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("Tonwertkurve")
                    Spacer()
                    if studio.adjustments.curve != Adjustments.linearCurve {
                        Button("Zurücksetzen") { studio.adjustments.curve = Adjustments.linearCurve }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }

            Section("Farbe") {
                AdjustSlider(title: "Sättigung", value: $studio.adjustments.saturation, spec: SliderSpecs.saturation)
                AdjustSlider(title: "Dynamik", value: $studio.adjustments.vibrance, spec: SliderSpecs.vibrance)
                AdjustSlider(title: "Temperatur", value: $studio.adjustments.temperature, spec: SliderSpecs.temperature)
                AdjustSlider(title: "Tönung", value: $studio.adjustments.tint, spec: SliderSpecs.tint)
            }

            Section {
                AdjustSlider(title: "Rot", value: $studio.adjustments.red, spec: SliderSpecs.colorChannel,
                             track: [Color(red: 0.1, green: 0.78, blue: 0.85), Color(red: 0.95, green: 0.22, blue: 0.18)])
                AdjustSlider(title: "Grün", value: $studio.adjustments.green, spec: SliderSpecs.colorChannel,
                             track: [Color(red: 0.86, green: 0.25, blue: 0.82), Color(red: 0.22, green: 0.78, blue: 0.3)])
                AdjustSlider(title: "Blau", value: $studio.adjustments.blue, spec: SliderSpecs.colorChannel,
                             track: [Color(red: 0.96, green: 0.82, blue: 0.15), Color(red: 0.2, green: 0.42, blue: 0.96)])
            } header: {
                HStack {
                    Text("Farbkorrektur (RGB)")
                    Spacer()
                    if studio.adjustments.hasColorBalance {
                        Button("Zurücksetzen") {
                            studio.adjustments.red = 0
                            studio.adjustments.green = 0
                            studio.adjustments.blue = 0
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            } footer: {
                Text("Nach links Cyan, Magenta, Gelb – nach rechts Rot, Grün, Blau. Die Helligkeit bleibt dabei gleich.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Details") {
                AdjustSlider(title: "Schärfe", value: $studio.adjustments.sharpness, spec: SliderSpecs.sharpness)
                AdjustSlider(title: "Klarheit", value: $studio.adjustments.clarity, spec: SliderSpecs.clarity)
                AdjustSlider(title: "Rauschreduzierung", value: $studio.adjustments.noiseReduction, spec: SliderSpecs.noise)
                AdjustSlider(title: "Vignette", value: $studio.adjustments.vignette, spec: SliderSpecs.vignette)
                AdjustSlider(title: "Körnung", value: $studio.adjustments.grain, spec: SliderSpecs.grain)
            }

            Section("Filter") {
                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(PhotoFilter.allCases) { filter in
                        Chip(title: filter.title, isOn: studio.adjustments.filter == filter) {
                            studio.adjustments.filter = filter
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Section {
                HStack {
                    Button("Zurücksetzen") { studio.adjustments = Adjustments() }
                        .disabled(studio.adjustments.isIdentity)
                    Spacer()
                    Button("Als neue Version anwenden") { studio.applyAdjustments() }
                        .buttonStyle(.borderedProminent)
                        .disabled(studio.adjustments.isIdentity)
                }
            } footer: {
                Text("Regler sind um den Nullpunkt besonders fein. ⌥ beim Ziehen = noch feiner, Doppelklick = zurücksetzen, Klick auf die Zahl = Wert eintippen. Beim Bearbeiten mit Qwen werden offene Anpassungen automatisch übernommen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .panelFormBackground()
    }

}

/// Quadratischer Knopf mit Symbol für Werkzeugreihen.
struct ToolButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(maxWidth: .infinity, minHeight: 22)
        }
        .buttonStyle(.bordered)
        .help(help)
    }
}

// MARK: - Verlauf

struct HistoryPanel: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if studio.versions.isEmpty {
            ContentUnavailableView("Noch keine Versionen", systemImage: "clock.arrow.circlepath", description: Text("Jede Generierung, Bearbeitung und Anpassung landet hier – und automatisch in der Bibliothek."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                        ForEach(studio.versions.reversed()) { version in
                            VersionTile(version: version, number: (studio.versions.firstIndex(of: version) ?? 0) + 1)
                        }
                    }
                    if let current = studio.current {
                        VersionDetails(version: current)
                        // Bild aus der Galerie: seine Notizen und To-dos gleich hier.
                        if let item = studio.gallery.item(current.id) {
                            NotesSection(item: item)
                        }
                    }
                }
                .padding(14)
            }
        }
    }
}

private struct VersionTile: View {
    @Environment(Studio.self) private var studio
    let version: ImageVersion
    let number: Int

    private var isCurrent: Bool { studio.currentID == version.id }

    var body: some View {
        Button {
            studio.select(version)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                CGImageView(image: version.thumbnail)
                    .padding(4)
                HStack(spacing: 4) {
                    Image(systemName: version.source.symbol)
                    Text("\(number)")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.5)))
                .padding(6)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onDrag {
            if let url = version.fileURL { return NSItemProvider(object: url as NSURL) }
            return NSItemProvider(object: NSImage(cgImage: version.image, size: .zero))
        }
        .contextMenu {
            if !version.prompt.isEmpty {
                Button("Prompt übernehmen", systemImage: "text.quote") { studio.builder.replacePrompt(version.prompt) }
            }
            Menu("Als Referenz verwenden", systemImage: "photo.stack") {
                ForEach(studio.references.indices, id: \.self) { index in
                    Button("Bild \(index + 1) · \(studio.references[index].role.title)") {
                        studio.setReference(version.image, at: index)
                    }
                }
            }
            Button("Als Ausgangsbild für eine Serie", systemImage: "square.grid.2x2") {
                studio.setSeriesSource(version)
                studio.mode = .series
            }
            Button("Exportieren …", systemImage: "square.and.arrow.up") { studio.exportWithPanel(version) }
            Button("Im Finder zeigen", systemImage: "folder") { studio.revealInFinder(version) }
                .disabled(version.fileURL == nil)
            OpenInAppButton(urls: version.fileURL.map { [$0] } ?? [])
            Divider()
            Button("Aus dem Verlauf entfernen", systemImage: "trash", role: .destructive) { studio.delete(version) }
        }
        .help("\(version.source.title) · \(version.createdAt.formatted(date: .omitted, time: .shortened))")
    }
}

private struct VersionDetails: View {
    @Environment(Studio.self) private var studio
    let version: ImageVersion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(version.source.title, systemImage: version.source.symbol)
                    .font(.headline)
                Spacer()
                Text(version.createdAt, format: .dateTime.hour().minute().second())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Größe", "\(Format.size(version.size)) px")
                if let seed = version.seed { row("Seed", "\(seed)") }
                if let duration = version.duration { row("Dauer", Format.duration(duration)) }
                if let url = version.fileURL { row("Datei", url.lastPathComponent) }
            }
            .font(.callout)
            if !version.prompt.isEmpty {
                Text(version.prompt)
                    .font(.callout)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Prompt übernehmen") { studio.builder.replacePrompt(version.prompt) }
                    Spacer()
                    Button("Im Finder", systemImage: "folder") { studio.revealInFinder(version) }
                        .disabled(version.fileURL == nil)
                }
                .controlSize(.small)
            }
        }
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().textSelection(.enabled)
        }
    }
}
