import SwiftUI

/// „Text im Bild“: exakter Text plus Schrift, Farbe, Position – oder Text ersetzen.
struct TextInImageEditor: View {
    @Environment(Studio.self) private var studio
    @State private var expanded: Set<String> = []

    private var builder: PromptBuilder { studio.builder }
    private var text: TextInImage { builder.textInImage }
    private var catalog: TextCatalog { Catalog.shared.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if studio.mode != .generate {
                Picker("", selection: Binding(get: { text.replace }, set: { value in builder.updateText { $0.replace = value } })) {
                    Text("Hinzufügen").tag(false)
                    Text("Ersetzen").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if studio.mode != .generate && text.replace {
                field("Vorhandener Text im Bild", text.find) { value in builder.updateText { $0.find = value } }
            }
            field(text.replace && studio.mode != .generate ? "Neuer Text" : "Text, der im Bild stehen soll", text.text) { value in
                builder.updateText { $0.text = value }
            }

            if studio.mode != .generate && text.replace {
                Toggle("Schrift, Größe, Farbe und Position beibehalten", isOn: Binding(get: { text.keepStyle }, set: { value in builder.updateText { $0.keepStyle = value } }))
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }

            if !(text.replace && text.keepStyle && studio.mode != .generate) {
                ForEach(catalog.groups) { group in
                    styleGroup(group)
                }
                if !(text.replace && studio.mode != .generate) {
                    positionGrid
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.trailing, 4)
    }

    private func field(_ title: String, _ value: String, set: @escaping (String) -> Void) -> some View {
        TextField(title, text: Binding(get: { value }, set: set), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...3)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    private func styleGroup(_ group: TextGroup) -> some View {
        let selectedName = group.options.first { $0.id == text[group.id] }?.name
        return DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(group.id) },
            set: { value in if value { expanded.insert(group.id) } else { expanded.remove(group.id) } }
        )) {
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(group.options) { option in
                    Chip(title: option.name, isOn: text[group.id] == option.id, swatch: option.swatch.flatMap(Color.init(hex:))) {
                        builder.updateText { state in
                            state[group.id] = state[group.id] == option.id ? nil : option.id
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(group.name)
                Spacer()
                if let selectedName {
                    Text(selectedName)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var positionGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Position")
            Spacer()
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { column in
                            let position = catalog.positions[row * 3 + column]
                            let isOn = text.position == position.id
                            Button {
                                builder.updateText { $0.position = isOn ? nil : position.id }
                            } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
                                    .frame(width: 30, height: 20)
                                    .overlay {
                                        Capsule()
                                            .fill(isOn ? Color.white : Color.primary.opacity(0.35))
                                            .frame(width: 14, height: 3)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(position.name)
                        }
                    }
                }
            }
        }
    }
}

extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
