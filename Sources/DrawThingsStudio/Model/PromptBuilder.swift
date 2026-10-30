import AppKit
import Observation

/// Text, der im Bild erscheinen soll (Qwen kann Schrift sehr gut rendern).
struct TextInImage: Codable, Equatable {
    var text = ""
    var replace = false
    var find = ""
    var keepStyle = true
    var font: String?
    var size: String?
    var color: String?
    var effect: String?
    var layout: String?
    var surface: String?
    var position: String?

    subscript(group: String) -> String? {
        get {
            switch group {
            case "font": font
            case "size": size
            case "color": color
            case "effect": effect
            case "layout": layout
            case "surface": surface
            default: nil
            }
        }
        set {
            switch group {
            case "font": font = newValue
            case "size": size = newValue
            case "color": color = newValue
            case "effect": effect = newValue
            case "layout": layout = newValue
            case "surface": surface = newValue
            default: break
            }
        }
    }
}

/// Setzt aus den gewählten Bausteinen den englischen Prompt zusammen.
///
/// Solange der Prompt nicht von Hand geändert wurde, wird er komplett neu gebaut.
/// Danach ändert jede Kachel nur noch ihren eigenen Satz: Sie ersetzt ihn an Ort
/// und Stelle, entfernt ihn oder setzt ihn hinter den nächsten vorhandenen
/// Vorgänger – eigene Formulierungen und Gemmas Optimierungen bleiben erhalten.
@MainActor
@Observable
final class PromptBuilder {
    var selections: [String: [String]] = [:]
    var extras: [String: String] = [:]
    var textInImage = TextInImage()
    var referenceSentences: [String: String] = [:]
    /// Beschreibungen der gewählten Assets (außerhalb von „Referenzen“).
    private(set) var assetSentence = ""
    /// Hinweis zum Raster mit Gesichtsreferenz (nur „Bearbeiten“).
    private(set) var assistSentence = ""
    var mode: StudioMode = .generate {
        didSet { if mode != oldValue { recompose() } }
    }

    private(set) var prompt = ""
    private var lastSentences: [String: String] = [:]

    var isEdited: Bool { prompt != Self.join(lastSentences) }

    /// Reihenfolge der Sätze – kommt aus dem (bearbeitbaren) Katalog.
    static var order: [String] { CatalogStore.shared.promptOrder }

    private static func section(of key: String) -> String {
        String(key.split(separator: "/").first ?? "")
    }

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    // MARK: Auswahl

    func isSelected(_ key: String, _ id: String) -> Bool {
        selections[key]?.contains(id) ?? false
    }

    func toggle(_ key: String, _ id: String) {
        guard let group = Catalog.shared.group(key) else { return }
        var ids = selections[key] ?? []
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else if group.multi {
            ids.append(id)
        } else {
            ids = [id]
        }
        selections[key] = ids.isEmpty ? nil : ids
        recompose()
    }

    func setSelection(_ key: String, ids: [String]) {
        selections[key] = ids.isEmpty ? nil : ids
        recompose()
    }

    func clear(_ key: String) {
        selections[key] = nil
        recompose()
    }

    func selectedNames(_ key: String) -> [String] {
        guard let group = Catalog.shared.group(key), let ids = selections[key] else { return [] }
        return group.options.filter { ids.contains($0.id) }.map(\.name)
    }

    func selectionCount(in section: CatalogSection) -> Int {
        section.groups.reduce(0) { $0 + (selections[$1.key]?.count ?? 0) }
            + (extras[section.id]?.trimmingCharacters(in: .whitespaces).isEmpty == false ? 1 : 0)
    }

    func setExtra(_ section: String, _ text: String) {
        extras[section] = text
        recompose()
    }

    func updateText(_ change: (inout TextInImage) -> Void) {
        change(&textInImage)
        recompose()
    }

    func setReferenceSentences(_ sentences: [String: String]) {
        guard sentences != referenceSentences else { return }
        referenceSentences = sentences
        recompose()
    }

    func setAssetSentence(_ text: String) {
        guard text != assetSentence else { return }
        assetSentence = text
        recompose()
    }

    func setAssistSentence(_ text: String) {
        guard text != assistSentence else { return }
        assistSentence = text
        recompose()
    }

    // MARK: Prompt

    /// Änderung direkt im Textfeld.
    func editPrompt(_ text: String) {
        prompt = text
        save()
    }

    /// Prompt von außen ersetzen (Gemma, Bibliothek, Analyse).
    func replacePrompt(_ text: String) {
        prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    /// Anzahl gewählter Bausteine (Chips, eigene Ergänzungen, Text im Bild).
    var componentCount: Int {
        selections.values.reduce(0) { $0 + $1.count }
            + extras.values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            + (textInImage.text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)
    }

    private struct Components {
        var selections: [String: [String]]
        var extras: [String: String]
        var textInImage: TextInImage
    }

    @ObservationIgnored private var clearedComponents: Components?
    /// true, solange „Leeren“ rückgängig gemacht werden kann.
    private(set) var canUndoClear = false

    /// Alle Bausteine auf einmal abwählen. Ihre Sätze verschwinden aus dem Prompt,
    /// eigene Formulierungen und Gemmas Text bleiben stehen.
    func clearComponents() {
        guard componentCount > 0 else { return }
        clearedComponents = Components(selections: selections, extras: extras, textInImage: textInImage)
        selections = [:]
        extras = [:]
        textInImage = TextInImage()
        canUndoClear = true
        recompose()
    }

    func undoClearComponents() {
        guard let cleared = clearedComponents else { return }
        selections = cleared.selections
        extras = cleared.extras
        textInImage = cleared.textInImage
        dismissUndoClear()
        recompose()
    }

    func dismissUndoClear() {
        clearedComponents = nil
        canUndoClear = false
    }

    @ObservationIgnored private var stashedDraft: Snapshot?
    /// true, solange ein beim Zurück in die Galerie geleerter Entwurf wiederherzustellen ist (nur im Speicher).
    private(set) var canRestoreDraft = false

    /// Entwurf merken, bevor er geleert wird. Ein leerer Entwurf lässt den früher gemerkten stehen.
    func stashDraft() {
        guard !prompt.isEmpty || componentCount > 0 else { return }
        stashedDraft = Snapshot(selections: selections, extras: extras, textInImage: textInImage, prompt: prompt, lastSentences: lastSentences)
        canRestoreDraft = true
    }

    /// Den gemerkten Entwurf zurückholen; Sätze, die zum aktuellen Modus gehören, ordnet `recompose` ein.
    func restoreDraft() {
        guard let draft = stashedDraft else { return }
        dismissUndoClear()
        selections = draft.selections
        extras = draft.extras
        textInImage = draft.textInImage
        prompt = draft.prompt
        lastSentences = draft.lastSentences
        stashedDraft = nil
        canRestoreDraft = false
        recompose()
    }

    func reset() {
        dismissUndoClear()
        selections = [:]
        extras = [:]
        textInImage = TextInImage()
        prompt = ""
        lastSentences = [:]
        recompose()
    }

    func recompose() {
        let next = sentences()
        prompt = isEdited ? Self.merge(prompt, before: lastSentences, after: next) : Self.join(next)
        lastSentences = next
        save()
    }

    // MARK: Sätze

    func sentences() -> [String: String] {
        var result: [String: String] = [:]
        for key in Self.order {
            let text: String
            if key.hasPrefix("extra/") {
                text = extras[String(key.dropFirst(6))] ?? ""
            } else if key == "text" {
                text = textSentence()
            } else if key.hasPrefix("ref/") {
                text = mode == .references ? referenceSentences[key] ?? "" : ""
            } else if key == "assets" {
                text = mode == .references ? "" : assetSentence
            } else if key == "assist/identity" {
                text = mode == .edit ? assistSentence : ""
            } else if key.hasPrefix("edit/") {
                text = mode == .edit ? optionText(key) : ""
            } else {
                text = optionText(key)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result[key] = Self.withPeriod(trimmed) }
        }
        return result
    }

    private func optionText(_ key: String) -> String {
        guard let group = Catalog.shared.group(key), let ids = selections[key] else { return "" }
        // Bei Mehrfachauswahl in der Reihenfolge der Kacheln.
        let texts = group.options.filter { ids.contains($0.id) }.map(\.text)
        guard !texts.isEmpty else { return "" }
        let template = (mode == .edit ? group.editTemplate : nil) ?? group.template
        if let template, template.contains("{}") {
            return template.replacingOccurrences(of: "{}", with: Self.list(texts))
        }
        return texts.joined(separator: " ")
    }

    /// „a, b and c“
    private static func list(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Text im Bild – nach Qwens Regeln: exakter Text in doppelten Anführungszeichen,
    /// Sprache und Schreibweise unverändert; Ersetzen als „Replace "alt" to "neu"“.
    private func textSentence() -> String {
        let t = textInImage
        let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let catalog = Catalog.shared.text
        func quote(_ value: String) -> String {
            "\"" + value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "”") + "\""
        }
        func pick(_ group: String) -> String? { catalog.option(group, t[group])?.text }
        let position = catalog.positions.first { $0.id == t.position }?.text

        var styling: [String] = []
        if t.font != nil || t.size != nil || t.color != nil {
            styling.append("in " + [pick("size"), pick("color"), pick("font") ?? "lettering"].compactMap { $0 }.joined(separator: " "))
        }
        if let effect = pick("effect") { styling.append(effect) }
        if let layout = pick("layout") { styling.append(layout) }

        let editing = mode != .generate
        if editing && t.replace {
            let find = t.find.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !find.isEmpty else { return "" }
            var parts = ["Replace \(quote(find)) to \(quote(text))"]
            parts += t.keepStyle ? ["keep font style, size, color and position unchanged"] : styling
            return parts.joined(separator: ", ") + ", keep other parts unchanged as much as possible."
        }

        var sentence = editing ? "Add the text \(quote(text))" : "The image shows the text \(quote(text))"
        if let surface = pick("surface") { sentence += " \(surface)" }
        var parts = [sentence]
        if let position { parts.append(position) }
        parts += styling
        return parts.joined(separator: ", ") + (editing ? ", keep other parts unchanged as much as possible." : ".")
    }

    static func withPeriod(_ value: String) -> String {
        guard let last = value.last else { return value }
        return ".!?\"”)".contains(last) ? value : value + "."
    }

    static func join(_ sentences: [String: String]) -> String {
        order.compactMap { sentences[$0] }.joined(separator: " ")
    }

    static func merge(_ original: String, before: [String: String], after: [String: String]) -> String {
        var text = original
        var added: [String] = []
        for key in Set(before.keys).union(after.keys) {
            let old = before[key]
            let new = after[key]
            if old == new { continue }
            if let old, let range = text.range(of: old) {
                text.replaceSubrange(range, with: new ?? "")
            } else if new != nil {
                added.append(key)
            }
        }

        let rank = { (key: String) in order.firstIndex(of: key) ?? order.count }
        for key in added.sorted(by: { rank($0) < rank($1) }) {
            guard let next = after[key] else { continue }
            let index = rank(key)
            let previous = order[..<min(index, order.count)].reversed()
                .compactMap { after[$0] }
                .first { $0 != next && text.contains($0) }
            let following = index + 1 < order.count
                ? order[(index + 1)...].compactMap { after[$0] }.first { text.contains($0) }
                : nil
            if let previous, let range = text.range(of: previous) {
                text.replaceSubrange(range, with: previous + " " + next)
            } else if let following, let range = text.range(of: following) {
                text.replaceSubrange(range, with: next + " " + following)
            } else if index == 0 {
                // Erster Satz der Reihenfolge (Hinweis zum Raster der Gesichtsreferenz) gehört nach vorn.
                text = text.isEmpty ? next : next + " " + withPeriod(text)
            } else {
                text = text.isEmpty ? next : withPeriod(text) + " " + next
            }
        }
        return text
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Sichern – je Bibliothek in `Katalog/prompt-draft.json`

    private struct Snapshot: Codable {
        var selections: [String: [String]]
        var extras: [String: String]
        var textInImage: TextInImage
        var prompt: String
        var lastSentences: [String: String]
    }

    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pending: (data: Data, url: URL)?

    /// Entwurf einer Bibliothek laden – eine neue beginnt leer.
    func open(root: URL) {
        flush()
        fileURL = nil
        dismissUndoClear()
        stashedDraft = nil
        canRestoreDraft = false
        selections = [:]
        extras = [:]
        textInImage = TextInImage()
        assetSentence = ""
        assistSentence = ""
        prompt = ""
        lastSentences = [:]
        fileURL = root.appending(path: "Katalog/prompt-draft.json")
        restore()
    }

    /// Bibliothek wird gewechselt oder gelöscht: Entwurf sichern (oder verwerfen), danach nichts mehr schreiben.
    func close(saving: Bool) {
        if saving { flush() } else { saveTask?.cancel(); pending = nil }
        fileURL = nil
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Snapshot(selections: selections, extras: extras, textInImage: textInImage, prompt: prompt, lastSentences: lastSentences)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        pending = (data, fileURL)
        // Beim Tippen nicht bei jedem Zeichen schreiben.
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        guard let (data, url) = pending else { return }
        pending = nil
        let root = url.deletingLastPathComponent().deletingLastPathComponent()
        guard Library.ensure(url.deletingLastPathComponent(), in: root) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func restore() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        // Auswahl aus Kategorien, die es nicht mehr gibt, verwerfen.
        let catalog = Catalog.shared
        selections = snapshot.selections.filter { key, _ in catalog.group(key) != nil }
        extras = snapshot.extras.filter { id, _ in catalog.section(id) != nil }
        textInImage = snapshot.textInImage
        prompt = snapshot.prompt
        lastSentences = snapshot.lastSentences
    }
}
