import SwiftUI

/// „Bearbeiten“: In welchem Draw-Things-Format das Bild an Draw Things geht.
/// Draw Things verarbeitet nur seine eigenen Größen – größere Bilder werden darauf verkleinert,
/// bei anderem Seitenverhältnis zusätzlich beschnitten.
struct EditFormatEditor: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if let current = studio.current, let format = studio.editFormat {
            form(current: current, format: format)
        } else {
            Text("Öffne ein Bild – dann wählst du hier, in welchem Format es an Draw Things geht.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func form(current: ImageVersion, format: AspectRatio) -> some View {
        @Bindable var studio = studio
        let target = format.pixelSize(studio.sizeTier)
        let automatic = AspectRatio.closest(to: current.size)
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                FormatTile(ratio: automatic, title: "Auto", isSelected: studio.editAspect == nil) {
                    studio.editAspect = nil
                }
                .help("Automatisch: das Draw-Things-Format, das dem Bild am nächsten kommt (\(automatic.label))")
                ForEach(AspectRatio.all) { ratio in
                    FormatTile(ratio: ratio, title: ratio.label, isSelected: studio.editAspect == ratio) {
                        studio.editAspect = ratio
                    }
                    .help(ratio.name)
                }
            }

            Picker("Größe", selection: $studio.sizeTier) {
                ForEach(SizeTier.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                LabeledContent("Bild") {
                    Text("\(Format.size(current.size)) px").monospacedDigit()
                }
                LabeledContent("An Draw Things") {
                    Text("\(Format.size(target)) px").monospacedDigit().fontWeight(.semibold)
                }
            }
            .font(.callout)

            if let note = note(image: current.size, format: format, target: target) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if current.size != target {
                Button("Bild jetzt auf \(Format.size(target)) bringen", systemImage: "arrow.down.right.and.arrow.up.left") {
                    studio.conformToEditFormat()
                }
                .controlSize(.small)
                .disabled(studio.isBusy)
                .help("Legt eine neue Version in genau dieser Größe an – so siehst du vorher, was Draw Things bekommt.")
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 4)
    }

    /// Was beim Senden mit dem Bild passiert.
    private func note(image: CGSize, format: AspectRatio, target: CGSize) -> String? {
        var parts: [String] = []
        if format.effectiveTier(studio.sizeTier) != studio.sizeTier {
            parts.append("\(format.label) gibt es in Draw Things nicht als \(studio.sizeTier.title) – es wird \(format.effectiveTier(studio.sizeTier).title).")
        }
        let imageRatio = image.width / image.height
        let targetRatio = target.width / target.height
        if abs(log(imageRatio / targetRatio)) > 0.01 {
            parts.append(imageRatio > targetRatio
                         ? "Das Seitenverhältnis weicht ab: links und rechts wird beschnitten."
                         : "Das Seitenverhältnis weicht ab: oben und unten wird beschnitten (Köpfe bleiben eher drin).")
        }
        if image.width > target.width || image.height > target.height {
            parts.append("Das Bild ist größer und wird vor dem Senden verkleinert.")
        } else if image.width < target.width && image.height < target.height {
            parts.append("Das Bild ist kleiner und wird hochgerechnet.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Kachel wie in Draw Things: kleines Rechteck im Format, darunter das Verhältnis.
private struct FormatTile: View {
    let ratio: AspectRatio
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            VStack(spacing: 3) {
                AspectGlyph(ratio: ratio, size: 20, lineWidth: 1.3)
                    .frame(height: 22)
                Text(title)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.8))
            .background(shape.fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(isHovering ? 0.09 : 0.04)))
            .overlay {
                if isSelected { shape.strokeBorder(Color.accentColor, lineWidth: 1.5) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
