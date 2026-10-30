import AppKit

/// Gesichtsreferenz beim Bearbeiten eines Charakterbildes (siehe `IdentityComposite`).
struct IdentityAssist: Equatable {
    var personaID: UUID
    var isEnabled = true
    /// Was Draw Things beim letzten Durchlauf zurückgegeben hat – das ganze Raster, zum Nachprüfen.
    var lastRawOutput: CGImage?
    /// Änderung der Referenzspalte beim letzten Durchlauf (0 … 1) – groß heißt: Qwen hat das Raster nicht gehalten.
    var lastStripChange: Double?

    static func == (lhs: IdentityAssist, rhs: IdentityAssist) -> Bool {
        lhs.personaID == rhs.personaID && lhs.isEnabled == rhs.isEnabled
            && lhs.lastRawOutput === rhs.lastRawOutput && lhs.lastStripChange == rhs.lastStripChange
    }

    /// Ab dieser Änderung der Referenzspalte warnt die App. Geschätzt: Qwen rendert das ganze Bild neu,
    /// unverändert gebliebene Gesichter weichen nur wenige Prozent ab.
    static let driftWarning = 0.12
}

extension Studio {

    // MARK: Vorschlag

    /// Charakter auf dem aktuellen Bild, der Fotos für eine Gesichtsreferenz hat.
    var identityCandidate: Persona? {
        guard mode == .edit, let current else { return nil }
        return current.personaIDs.compactMap { personas.persona($0) }.first { $0.mainPhoto != nil }
    }

    /// Gesichtsreferenz, die beim nächsten „Anwenden“ wirklich mitgeht.
    var activeIdentityAssist: (assist: IdentityAssist, persona: Persona)? {
        guard mode == .edit, current != nil, let assist = identityAssist, assist.isEnabled,
              let persona = personas.persona(assist.personaID), persona.mainPhoto != nil else { return nil }
        return (assist, persona)
    }

    /// Gesichtsreferenz einschalten – der Charakter gilt damit auch als „ist auf dem Bild“.
    func enableIdentityAssist(_ personaID: UUID) {
        guard let persona = personas.persona(personaID), persona.mainPhoto != nil else {
            errorMessage = "Der Charakter hat noch keine Fotos."
            return
        }
        if let currentID, let index = versions.firstIndex(where: { $0.id == currentID }),
           !versions[index].personaIDs.contains(personaID) {
            versions[index].personaIDs.append(personaID)
            if gallery.item(currentID) != nil { gallery.togglePersona(personaID, for: [currentID]) }
        }
        identityAssist = IdentityAssist(personaID: personaID)
        updateAssistSentence()
    }

    func disableIdentityAssist() {
        identityAssist?.isEnabled = false
        updateAssistSentence()
    }

    /// Neues Bild auf dem Canvas: Gesichtsreferenz nur behalten, wenn derselbe Charakter darauf ist.
    func identityAssistFollowCurrent() {
        if let assist = identityAssist, current?.personaIDs.contains(assist.personaID) != true {
            identityAssist = nil
        }
        updateAssistSentence()
    }

    // MARK: Prompt

    /// Wie die Ansichten im Prompt heißen: „from the front and in a three-quarter view“.
    func identityViewsPhrase(_ persona: Persona) -> String {
        let names = IdentityComposite.photos(of: persona).map { photo -> String in
            switch photo.view {
            case .front: "from the front"
            case .threeQuarterLeft, .threeQuarterRight: "in a three-quarter view"
            case .profileLeft, .profileRight: "in profile"
            case .body: "in full length"
            }
        }
        guard names.count > 1, let last = names.last else { return names.first ?? "from the front" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Satz vorn im Prompt, solange die Gesichtsreferenz an ist.
    func updateAssistSentence() {
        guard let (_, persona) = activeIdentityAssist else {
            builder.setAssistSentence("")
            return
        }
        let count = IdentityComposite.photos(of: persona).count
        let panels = count == 1 ? "the narrow panel on the right shows" : "the narrow panels on the right show"
        builder.setAssistSentence(
            "Picture 1 is split into panels: the large panel on the left is the photo to edit, \(panels) the same person "
            + "\(identityViewsPhrase(persona)) as an identity reference. Apply the edit only to the large left panel and keep the person's face, "
            + "facial features, hairstyle and skin tone exactly consistent with the reference. Leave the reference panels unchanged."
        )
    }

    /// Zusatz für Gemma: Sie sieht das Raster und schreibt die Anweisung fürs große Feld.
    func identityAssistContext(_ persona: Persona) -> String {
        "Picture 1 is sent to the image model as a composite: the large left panel is the photo to edit, the right column shows reference photos of the same person "
            + "\(identityViewsPhrase(persona)). Write the instruction for the large left panel only, use the reference panels to keep the face consistent "
            + "(especially when the head turns or the face becomes more visible), and end with a sentence that the reference panels stay unchanged."
    }
}
