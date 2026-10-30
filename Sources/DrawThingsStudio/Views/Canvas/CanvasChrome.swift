import SwiftUI

/// Schwebende Leiste unter dem Bild: Format, Größe, Zoom, Vorher/Nachher, Versionen.
struct CanvasBar: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    aspectMenu
                    SizeTierMenu()
                    divider
                    sizeLabel
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

                HStack(spacing: 6) {
                    Button { studio.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("Verkleinern (⌘−)")
                    Button {
                        studio.toggleActualSize()
                    } label: {
                        Text("\(Int(((studio.zoom ?? studio.shownFitScale) * 100).rounded())) %")
                            .monospacedDigit()
                            .frame(minWidth: 44)
                    }
                    .help(studio.zoom == nil ? "Originalgröße" : "Einpassen (⌘0)")
                    Button { studio.zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("Vergrößern (⌘+)")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

                if studio.versions.count > 1 || studio.comparisonPair != nil {
                    HStack(spacing: 8) {
                        if studio.versions.count > 1 {
                            Button { studio.selectAdjacentVersion(-1) } label: { Image(systemName: "chevron.left") }
                                .disabled(studio.previousVersion == nil)
                                .help("Vorherige Version (⌘[)")
                            Text(versionLabel)
                                .monospacedDigit()
                                .font(.callout)
                            Button { studio.selectAdjacentVersion(1) } label: { Image(systemName: "chevron.right") }
                                .disabled(studio.versions.last?.id == studio.currentID)
                                .help("Nächste Version (⌘])")
                            divider
                        }
                        SplitCompareToggle()
                        CompareButton()
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                }
            }
        }
        .font(.callout)
    }

    private var divider: some View {
        Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 16)
    }

    private var versionLabel: String {
        let index = (studio.versions.firstIndex { $0.id == studio.currentID } ?? 0) + 1
        return "\(index) / \(studio.versions.count)"
    }

    /// In „Bearbeiten“ das Format, in dem das Bild an Draw Things geht – sonst das Seitenverhältnis neuer Bilder.
    private var aspectMenu: some View {
        let isEditing = studio.mode == .edit && studio.current != nil
        let shown = isEditing ? studio.editFormat : studio.aspect
        return Menu {
            if isEditing {
                Button {
                    studio.editAspect = nil
                } label: {
                    let title = "Automatisch – wie das Bild"
                    if studio.editAspect == nil { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
                Divider()
            }
            ForEach(AspectRatio.all) { ratio in
                Button {
                    if isEditing { studio.editAspect = ratio } else { studio.changeAspect(ratio) }
                } label: {
                    if ratio == (isEditing ? studio.editAspect : studio.aspect) {
                        Label("\(ratio.label)  \(ratio.name)", systemImage: "checkmark")
                    } else {
                        Text("\(ratio.label)  \(ratio.name)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                AspectGlyph(ratio: shown ?? .square, size: 14)
                Text(shown?.label ?? "–")
                    .monospacedDigit()
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(isEditing ? "Format, in dem das Bild an Draw Things geht" : "Seitenverhältnis für neue Generierungen")
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if studio.mode == .edit, !studio.isComparing, let image = studio.current?.image, let target = studio.targetSize(for: .edit) {
            let size = CGSize(width: image.width, height: image.height)
            Text(size == target ? "\(Format.size(size)) px" : "\(Format.size(size)) → \(Format.size(target)) px")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help(size == target
                      ? "Das Bild hat schon ein Draw-Things-Format"
                      : "So groß geht das Bild an Draw Things – Format links unter „Format“")
        } else if let image = studio.current?.image, studio.mode != .generate || studio.isComparing {
            Text("\(Format.size(CGSize(width: image.width, height: image.height))) px")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else if let size = studio.targetSize(for: .generate) {
            Text("\(Format.size(size)) px")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("So groß rendert Draw Things das nächste Bild")
        }
    }
}

/// Klein · Normal · Groß wie in Draw Things – gilt für die nächste Generierung, Bearbeitung, Komposition oder Serie.
struct SizeTierMenu: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let format = studio.targetFormat(for: studio.mode)
        let effective = format?.effectiveTier(studio.sizeTier) ?? studio.sizeTier
        Menu {
            ForEach(SizeTier.allCases) { tier in
                Button {
                    studio.sizeTier = tier
                } label: {
                    let title = menuTitle(tier, format: format)
                    if tier == studio.sizeTier { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
                .disabled(format.map { !$0.offers(tier) } ?? false)
            }
        } label: {
            Text(effective.title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(effective == .large ? Color.white : Color.secondary)
                .background(Capsule().fill(effective == .large ? Color.accentColor : Color.primary.opacity(0.1)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(effective == studio.sizeTier
              ? "Größe wie in Draw Things: Klein, Normal oder Groß"
              : "\(format?.label ?? "") gibt es in Draw Things nicht als \(studio.sizeTier.title) – es wird \(effective.title)")
    }

    private func menuTitle(_ tier: SizeTier, format: AspectRatio?) -> String {
        guard let format else { return tier.title }
        guard format.offers(tier) else { return "\(tier.title) – gibt es bei \(format.label) nicht" }
        return "\(tier.title)  \(Format.size(format.pixelSize(tier))) px"
    }
}

/// Vorher/Nachher-Regler ein- und ausschalten (⌘Y).
private struct SplitCompareToggle: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let isOn = studio.isSplitComparing
        Button {
            withAnimation(.smooth(duration: 0.2)) { studio.isSplitComparing.toggle() }
        } label: {
            Label("Vergleich", systemImage: "rectangle.split.2x1")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .disabled(studio.comparisonPair == nil)
        .help(isOn ? "Vorher/Nachher-Regler ausblenden (⌘Y)" : "Vorher/Nachher mit verschiebbarer Linie vergleichen (⌘Y)")
    }
}

/// Gedrückt halten zeigt die vorherige Version (wie in Fotos).
private struct CompareButton: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        Label("Vorher", systemImage: "eye")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(studio.isComparing ? Color.accentColor : (studio.comparisonBase == nil ? Color.secondary.opacity(0.5) : Color.primary))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0, maximumDistance: 40) {
            } onPressingChanged: { pressing in
                guard studio.comparisonBase != nil else { return }
                studio.isComparing = pressing
            }
            .help("Gedrückt halten, um die vorherige Version zu sehen")
    }
}

/// Kleines Rechteck im Seitenverhältnis.
struct AspectGlyph: View {
    let ratio: AspectRatio
    var size: CGFloat = 40
    var lineWidth: CGFloat = 1.5

    var body: some View {
        let width = ratio.value >= 1 ? size : size * ratio.value
        let height = ratio.value >= 1 ? size / ratio.value : size
        RoundedRectangle(cornerRadius: max(2, size * 0.08), style: .continuous)
            .strokeBorder(lineWidth: lineWidth)
            .frame(width: width, height: height)
            .frame(width: size, height: size)
    }
}

/// Auswahl des Seitenverhältnisses als Kacheln.
struct AspectRatioGrid: View {
    @Environment(Studio.self) private var studio
    var selected: AspectRatio?
    let onSelect: (AspectRatio) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            // Bis zu sechs Kacheln je Zeile, bei schmalem Fenster weniger.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108, maximum: 108), spacing: 12)], spacing: 12) {
                ForEach(AspectRatio.all) { ratio in
                    AspectTile(ratio: ratio, isSelected: ratio == selected, pixels: pixels(for: ratio)) {
                        onSelect(ratio)
                    }
                }
            }
            .frame(maxWidth: 6 * 108 + 5 * 12)
        }
    }

    private func pixels(for ratio: AspectRatio) -> CGSize {
        studio.pixelSize(for: ratio.value)
    }
}

private struct AspectTile: View {
    let ratio: AspectRatio
    let isSelected: Bool
    let pixels: CGSize
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AspectGlyph(ratio: ratio, size: 46, lineWidth: 2)
                    .foregroundStyle(isSelected || isHovering ? Color.accentColor : Color.primary.opacity(0.75))
                    .frame(height: 52)
                VStack(spacing: 1) {
                    Text(ratio.label)
                        .font(.headline)
                        .monospacedDigit()
                    Text(ratio.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Format.size(pixels))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 108, height: 128)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(Color.accentColor.opacity(0.25)).interactive() : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .scaleEffect(isHovering ? 1.03 : 1)
        .animation(.smooth(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

/// Startbildschirm, solange noch kein Bild angelegt ist.
struct WelcomeView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(GemmaStyle.gradient)
                        .frame(width: 74, height: 74)
                        .shadow(color: GemmaStyle.tint.opacity(0.45), radius: 18, y: 6)
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                }
                Text("Neues Bild")
                    .font(.system(size: 30, weight: .bold))
                Text("Wähle ein Seitenverhältnis – das Bild erscheint dann hier auf dem Canvas.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            AspectRatioGrid(selected: nil) { ratio in
                withAnimation(.smooth) { studio.newDocument(ratio) }
            }

            SizeTierPicker()

            HStack(spacing: 12) {
                Button("Bild öffnen …", systemImage: "photo.badge.plus") { studio.importWithPanel() }
                Button("Aus Zwischenablage", systemImage: "doc.on.clipboard") { studio.pasteImage() }
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Text("Oder ein Bild einfach hierher ziehen")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}

/// Klein · Normal · Groß – unter den Format-Kacheln.
struct SizeTierPicker: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        VStack(spacing: 6) {
            Picker("Größe", selection: $studio.sizeTier) {
                ForEach(SizeTier.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            Text("Größen wie in Draw Things – 16:9 und 9:16 gibt es nur in Klein und Groß.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// ⌘N: neues Bild mit Seitenverhältnis.
struct NewImageSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State private var selection: AspectRatio = .square

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text("Neues Bild")
                    .font(.title2.weight(.bold))
                Text("Seitenverhältnis wählen. Die bisherigen Versionen liegen weiter in der Bibliothek.")
                    .foregroundStyle(.secondary)
            }
            AspectRatioGrid(selected: selection) { ratio in
                selection = ratio
            }
            SizeTierPicker()
            HStack {
                Button("Bild öffnen …") {
                    dismiss()
                    studio.importWithPanel()
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Erstellen") {
                    studio.newDocument(selection)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 780)
        .onAppear {
            selection = studio.aspect ?? AspectRatio.with(id: studio.settings.lastAspectID) ?? .square
        }
    }
}
