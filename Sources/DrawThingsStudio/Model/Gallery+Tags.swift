import Foundation

/// Tags der Galerie: freie Schlagwörter je Bild – für den Filter unter dem Raster und die Suche.
extension Gallery {

    /// Alle Tags der Bibliothek mit der Zahl ihrer Bilder, alphabetisch.
    var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items where !missing.contains(item.id) {
            for tag in item.tags ?? [] { counts[tag, default: 0] += 1 }
        }
        return counts
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    /// Tags, die alle diese Bilder tragen, und solche, die nur manche tragen – jeweils alphabetisch.
    func tags(of itemIDs: [UUID]) -> (common: [String], partial: [String]) {
        let lists = itemIDs.compactMap { item($0) }.map { $0.tags ?? [] }
        guard let first = lists.first else { return ([], []) }
        var common = Set(first)
        var all = Set(first)
        for list in lists.dropFirst() {
            common.formIntersection(list)
            all.formUnion(list)
        }
        let sorted = { (tags: Set<String>) in tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
        return (sorted(common), sorted(all.subtracting(common)))
    }

    /// Eingabe aufräumen (Leerzeichen) und die Schreibweise eines vorhandenen Tags übernehmen – „strand“ wird „Strand“.
    func normalizedTag(_ text: String, among existing: [String]) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let tag = words.joined(separator: " ")
        return existing.first { $0.compare(tag, options: .caseInsensitive) == .orderedSame } ?? tag
    }

    /// Tags hinzufügen – mehrere durch Komma getrennt („Strand, Sommer“).
    func addTags(_ text: String, to itemIDs: [UUID]) {
        var known = tagCounts.map(\.tag)
        var added: [String] = []
        for part in text.split(separator: ",") {
            guard let tag = normalizedTag(String(part), among: known), !added.contains(tag) else { continue }
            added.append(tag)
            if !known.contains(tag) { known.append(tag) }
        }
        guard !added.isEmpty else { return }
        update(itemIDs) { item in
            var tags = item.tags ?? []
            for tag in added where !tags.contains(tag) { tags.append(tag) }
            item.tags = tags
        }
    }

    func removeTag(_ tag: String, from itemIDs: [UUID]) {
        update(itemIDs) { item in
            item.tags?.removeAll { $0 == tag }
            if item.tags?.isEmpty == true { item.tags = nil }
        }
        // Ein Tag, das kein Bild mehr trägt, steht nicht mehr im Filter – sonst bliebe das Raster leer.
        let remaining = Set(tagCounts.map(\.tag))
        filter.tags.formIntersection(remaining)
    }

    /// Tragen schon alle Bilder das Tag, wird es entfernt, sonst bekommen es alle.
    func toggleTag(_ tag: String, for itemIDs: [UUID]) {
        if itemIDs.allSatisfy({ item($0)?.tags?.contains(tag) == true }) {
            removeTag(tag, from: itemIDs)
        } else {
            addTags(tag, to: itemIDs)
        }
    }

    /// Überall umbenennen. Heißt schon ein anderes Tag so, werden beide zusammengelegt.
    func renameTag(_ old: String, to text: String) {
        let others = tagCounts.map(\.tag).filter { $0 != old }
        guard let new = normalizedTag(text.replacingOccurrences(of: ",", with: " "), among: others), new != old else { return }
        let ids = items.filter { $0.tags?.contains(old) == true }.map(\.id)
        update(ids) { item in
            guard var tags = item.tags, let index = tags.firstIndex(of: old) else { return }
            if tags.contains(new) { tags.remove(at: index) } else { tags[index] = new }
            item.tags = tags
        }
        if filter.tags.remove(old) != nil { filter.tags.insert(new) }
    }

    /// Tag von allen Bildern entfernen.
    func deleteTag(_ tag: String) {
        removeTag(tag, from: items.filter { $0.tags?.contains(tag) == true }.map(\.id))
    }

    /// „Alle Bilder“ mit nur diesem Tag zeigen.
    func showImages(taggedWith tag: String) {
        collection = .all
        filter.tags = [tag]
    }
}
