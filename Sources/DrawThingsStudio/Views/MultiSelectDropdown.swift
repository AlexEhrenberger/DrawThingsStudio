import SwiftUI
import AppKit

/// Eine Zeile im Dropdown: Kennung, Name und die Zahl der Bilder, die dazugehören.
struct DropdownOption<ID: Hashable>: Identifiable {
    var id: ID
    var title: String
    var count: Int
}

/// Knopf mit Zähler und ein Popover mit Häkchenliste. Anders als `Menu` bleibt es beim Anklicken offen,
/// damit man mehrere Einträge nacheinander wählen kann.
struct MultiSelectDropdown<ID: Hashable, Leading: View>: View {
    let title: String
    let symbol: String
    /// Text, solange es keine Einträge gibt („Noch keine Tags.“).
    let emptyText: String
    /// Knopftext ohne Auswahl, sonst steht dort `title`.
    var placeholder: String?
    /// Erklärung unten im Popover.
    var note: String?
    let options: [DropdownOption<ID>]
    @Binding var selection: Set<ID>
    /// Nur für Tags: „einer davon“ (false) oder „alle“ (true).
    var matchAll: Binding<Bool>?
    /// Nur für Tags: Rechtsklick › Umbenennen bzw. › Von allen Bildern entfernen.
    var onRename: ((ID, String) -> Void)?
    var onDelete: ((ID) -> Void)?
    /// Läuft, wenn das Popover zugeht – z. B. um den Fokus an das Raster zurückzugeben.
    var onClose: () -> Void
    let leading: (DropdownOption<ID>) -> Leading

    @State private var isOpen = false
    @State private var search = ""
    @State private var renaming: ID?
    @State private var renameText = ""
    /// Höhe der ganzen Liste – die Liste ist so hoch wie ihr Inhalt, höchstens `listMaxHeight`.
    @State private var listHeight: CGFloat = 0

    /// Ab so vielen Einträgen gibt es ein Suchfeld.
    private static var searchThreshold: Int { 8 }
    private static var listMaxHeight: CGFloat { 260 }

    init(
        title: String, symbol: String, emptyText: String, placeholder: String? = nil, note: String? = nil,
        options: [DropdownOption<ID>], selection: Binding<Set<ID>>, matchAll: Binding<Bool>? = nil,
        onRename: ((ID, String) -> Void)? = nil, onDelete: ((ID) -> Void)? = nil, onClose: @escaping () -> Void = {},
        @ViewBuilder leading: @escaping (DropdownOption<ID>) -> Leading
    ) {
        self.title = title
        self.symbol = symbol
        self.emptyText = emptyText
        self.placeholder = placeholder
        self.note = note
        self.options = options
        self._selection = selection
        self.matchAll = matchAll
        self.onRename = onRename
        self.onDelete = onDelete
        self.onClose = onClose
        self.leading = leading
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(buttonTitle)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selection.isEmpty ? nil : Color.accentColor)
        .accessibilityLabel(title)
        .accessibilityValue(selection.isEmpty ? "keine Auswahl" : "\(selection.count) gewählt")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { panel }
        .onChange(of: isOpen) {
            if !isOpen {
                search = ""
                renaming = nil
                onClose()
            }
        }
    }

    /// „Tags“ (oder der Platzhalter), bei einer Auswahl deren Name, bei mehreren „Tags · 2“.
    private var buttonTitle: String {
        switch selection.count {
        case 0: placeholder ?? title
        case 1: options.first { selection.contains($0.id) }?.title ?? "\(title) · 1"
        default: "\(title) · \(selection.count)"
        }
    }

    // MARK: Popover

    private var shownOptions: [DropdownOption<ID>] {
        let words = search.split(separator: " ")
        guard !words.isEmpty else { return options }
        return options.filter { option in
            words.allSatisfy { option.title.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if options.count >= Self.searchThreshold {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("\(title) suchen", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                Divider()
            }
            if options.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 22)
            } else if shownOptions.isEmpty {
                Text("Nichts gefunden.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(shownOptions) { option in
                            row(option)
                        }
                    }
                    .padding(8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                // Feste Höhe statt `maxHeight`: sonst wächst das Popover nach einer Suche nicht wieder.
                .frame(height: min(listHeight, Self.listMaxHeight))
            }
            Divider()
            footer
        }
        .frame(width: 270)
        .font(.callout)
    }

    @ViewBuilder
    private func row(_ option: DropdownOption<ID>) -> some View {
        if renaming == option.id {
            RenameField(text: $renameText, onCommit: commitRename, onCancel: { renaming = nil })
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
        } else {
            toggle(option)
                .contextMenu {
                    if onRename != nil {
                        Button("Umbenennen …", systemImage: "pencil") { startRename(option) }
                    }
                    if let onDelete {
                        Button("Von \(option.count == 1 ? "dem Bild" : "allen \(option.count) Bildern") entfernen",
                               systemImage: "tag.slash") { onDelete(option.id) }
                    }
                }
        }
    }

    private func startRename(_ option: DropdownOption<ID>) {
        renameText = option.title
        renaming = option.id
    }

    private func commitRename() {
        guard let id = renaming else { return }
        renaming = nil
        onRename?(id, renameText)
    }

    private func toggle(_ option: DropdownOption<ID>) -> some View {
        Toggle(isOn: Binding(
            get: { selection.contains(option.id) },
            set: { isOn in
                if isOn { selection.insert(option.id) } else { selection.remove(option.id) }
            }
        )) {
            HStack(spacing: 8) {
                leading(option)
                Text(option.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(option.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let matchAll {
                HStack(spacing: 8) {
                    Text("Bilder mit:")
                        .foregroundStyle(.secondary)
                    Picker("Bilder mit", selection: matchAll) {
                        Text("einem davon").tag(false)
                        Text("allen").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Auswahl aufheben") { selection.removeAll() }
                    .buttonStyle(.link)
                    .disabled(selection.isEmpty)
                Spacer()
            }
        }
        .padding(10)
    }
}

/// Textfeld fürs Umbenennen. SwiftUIs `@FocusState` greift im Popover eines Popovers nicht – das Suchfeld
/// behielte den Fokus. Dieses Feld macht sich selbst zum First Responder, sobald es im Fenster steht.
private struct RenameField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = SelfFocusingTextField(string: text)
        field.bezelStyle = .roundedBezel
        field.font = .preferredFont(forTextStyle: .callout)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        private var finished = false

        init(_ parent: RenameField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        /// Escape bricht ab, statt das Popover zu schließen.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            finish(cancel: true)
            return true
        }

        /// Return oder Klick woandershin übernimmt den Namen.
        func controlTextDidEndEditing(_ notification: Notification) {
            finish(cancel: false)
        }

        private func finish(cancel: Bool) {
            guard !finished else { return }
            finished = true
            if cancel { parent.onCancel() } else { parent.onCommit() }
        }
    }
}

private final class SelfFocusingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // Einen Takt später – erst dann ist das Kontextmenü zu. Markiert zugleich den ganzen Namen.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window.makeFirstResponder(self)
        }
    }
}

extension MultiSelectDropdown where Leading == EmptyView {
    /// Ohne Symbol oder Bild vor dem Namen.
    init(
        title: String, symbol: String, emptyText: String, placeholder: String? = nil, note: String? = nil,
        options: [DropdownOption<ID>], selection: Binding<Set<ID>>, matchAll: Binding<Bool>? = nil,
        onRename: ((ID, String) -> Void)? = nil, onDelete: ((ID) -> Void)? = nil, onClose: @escaping () -> Void = {}
    ) {
        self.init(title: title, symbol: symbol, emptyText: emptyText, placeholder: placeholder, note: note,
                  options: options, selection: selection, matchAll: matchAll,
                  onRename: onRename, onDelete: onDelete, onClose: onClose) { _ in EmptyView() }
    }
}
