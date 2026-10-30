# Anweisung für Claude Sonnet 5.5 – Epic „Verbesserungen II“

Du arbeitest an **DrawThings Studio**, einer persönlichen macOS-App (SwiftUI, macOS 26, SwiftPM ohne Xcode, Swift-Sprachmodus 5, rund 25 600 Zeilen) im Projektordner. Der Nutzer schreibt Deutsch und will eine macOS-typische Oberfläche. Lies zuerst `README.md` (Abschnitte Galerie, Charaktere, Referenzen) und `Planung/Plan-Epic-Verbesserungen-II.md` (Befunde, Entscheidungen, Abnahme). Dieses Dokument sagt dir, **was** du **wo** tust.

Alle UI-Texte, Kommentare (`///` und `//`) und der Bericht sind **deutsch**. Dein Code soll wie der Umgebungscode aussehen: gleiche Kommentardichte (kurze deutsche Doc-Kommentare, die das Warum sagen), gleiche Namen, gleiche Idiome (`@Observable`, `@MainActor`, Erweiterungen `Studio+Thema.swift`).

## Regeln (gelten für jeden Schritt)

1. **Laufende App nie anfassen.** Der Nutzer arbeitet parallel in der App. Kein `pkill`, kein Neustart, kein `./build.sh install`. `swift build` und `./build.sh` (nur Bundle bauen) sind erlaubt.
2. **Nie eine zweite Instanz gegen die echte Bibliothek** (`~/Pictures/DrawThings Studio`, `~/Library/Application Support/DrawThings Studio`). Zwei Instanzen überschreiben sich gegenseitig den Katalog.
3. **UI-Tests nur in einer isolierten Testkopie:**
   - Bundle `build/DrawThings Studio.app` in den Scratchpad kopieren, Bundle-ID auf `local.drawthings-studio.test` setzen (PlistBuddy) und neu signieren (`codesign --force --deep --sign -`).
   - Mit `open --env CFFIXED_USER_HOME=<scratch>/home "<app>"` starten. Die Bibliothek und Application Support **kopieren** (nie verlinken) in dieses Fake-Home.
   - In der Testdomain `libraryPath`/`libraryPaths` auf die Kopie setzen, `lmStudioURL` und `drawThingsURL` auf `http://127.0.0.1:9` (echte Server nur, wenn der Nutzer sagt, dass sie frei sind).
   - Testdaten ins Katalog-JSON (`Katalog/gallery.json` der Kopie) nur schreiben, solange die Test-App **beendet** ist. Sie speichert ihren Speicherstand beim Beenden.
   - Hinterher das Fake-Home **löschen** (enthält Kopien von Charakterfotos) und die Testschlüssel entfernen.
   - Eine abstürzende Testkopie zeigt dem Nutzer einen macOS-Dialog. In Testbuilds daher `+[NSApplication _crashOnException:]` per `method_setImplementation` auf „nur loggen“ setzen.
   - `screencapture -l` geht nicht (keine Bildschirmaufnahme-Erlaubnis). **Bevor** du den Bildschirm per Computer-Use übernimmst, kündige es dem Nutzer an und warte auf das OK. Hintergrund-Klicks können nicht hovern, nicht rechtsklicken, keine Sheets und kein Drag & Drop bedienen.
   - Alternativ ein vorübergehender Hook hinter einer Umgebungsvariable (z. B. `DTS_PAGING_CHECK`), der Zustände durchläuft und über `stderr` loggt (`NSLog` zeigt `<private>`). Die Binärdatei des Bundles direkt mit `CFFIXED_USER_HOME=…` starten und `NSApp.activate()` dabei überspringen. **Den Hook danach entfernen.**
   - Was du nicht prüfen konntest, schreibst du im Bericht ausdrücklich so hin („nicht in der UI geprüft“).
4. **Keine LoRAs** abfragen oder ändern (stellt der Nutzer selbst in Draw Things ein).
5. **Keine Bilder aus ThePromptEngineer** übernehmen. Symbole sind SF Symbols, sonst Text.
6. **Labs bekommt keine Untermenüs, Listen oder Platzhalter.** **Keine automatische Gruppierung ähnlicher Motive.**
7. **Kleine, schwer fassbare Fehler** nicht ausgraben: ein kurzer Check, Bericht, weiter.
8. Kein neuer Fenster-Toolbar-Trick: `.searchable` in der Werkzeugleiste ist absichtlich nicht im Einsatz (siehe Kommentar an `ToolbarSearchField` in `MainView.swift`, es führte zu einem AppKit-Absturz). Toolbar-Struktur nur ändern, wenn nötig.
9. Es gibt **kein Git** in diesem Ordner. Du committest nichts. Vor großen Umbauten einer Datei legst du **keine** Sicherungskopien im Projekt ab. Arbeite in kleinen, gut prüfbaren Änderungen.
10. Nach **jedem Eintrag**: `swift build` im Projektordner, **ohne Warnungen und Fehler**. Erst dann der nächste Eintrag.
11. Die README ist die Dokumentation der App. Aktualisiere sie am Ende (siehe „Abschluss“).

## Reihenfolge

1. Story V
2. Story III
3. Story I
4. Bug I
5. Bug II
6. Story IV (setzt `LibraryPicker` aus Bug II voraus)
7. Story VI

**Story II („Zuletzt hinzugefügt“) ist bereits umgesetzt** (`GalleryCollection.recent`, `GallerySidebar.collections`). Nicht anfassen.

---

## 1 · Story V – Projekte, Stories und Charaktere einklappbar

**Datei:** `Sources/DrawThingsStudio/Views/Gallery/GallerySidebar.swift`

Für „Assets“ gibt es das Muster schon: `@AppStorage("sidebar.assetsExpanded") private var assetsExpanded = true` und `Section(isExpanded: $assetsExpanded) { … } header: { … }`.

Schritte:
1. Drei neue `@AppStorage`-Eigenschaften (Standard `true`): `sidebar.projectsExpanded`, `sidebar.storiesExpanded`, `sidebar.personasExpanded`.
2. Die Sektionen „Projekte“, „Stories“, „Charaktere“ auf `Section(isExpanded:)` umstellen. Header (Titel, Spacer, „+“-Knopf) bleibt.
3. Die „+“-Aktionen (neues Projekt, neue Story, neuer Charakter) setzen die zugehörige Variable auf `true`, bevor sie `gallery.collection` auf das neue Objekt setzen.
4. Der Hinweistext bei leerer Sektion (`Text("Ziehe Bilder auf ein Projekt …")` usw.) bleibt in der Sektion.

Abnahme: Drei Sektionen klappen mit dem Pfeil im Header ein und aus. Der Zustand überlebt einen Neustart. „+“ klappt eine zugeklappte Sektion auf. Eine in einer zugeklappten Sektion gewählte Sammlung bleibt gewählt.

Hinweis für die README: Auf eine zugeklappte Sektion lassen sich keine Bilder ziehen.

---

## 2 · Story III – Zurück in die Galerie leert Prompt und Bausteine

**Dateien:** `Model/Studio+Gallery.swift`, `Model/Studio+Library.swift` (nur lesen), `Model/PromptBuilder.swift`, `Views/MainView.swift` (`ModeSwitcher`), `App/DrawThingsStudioApp.swift` (Menü „Bild › Galerie“).

Ausgangslage: Der Wechsel passiert über `studio.showGallery = true`. Das tun auch Abkürzungen mitten im Arbeiten (`ReferencesPanel.swift` ca. Zeilen 226 und 250, `PromptBuilderSidebar.swift` ca. Zeilen 104 und 554: „Assets verwalten …“, „Charaktere verwalten …“, „Assets anlegen“). Diese dürfen **nichts** leeren.

Schritte:
1. In `Studio+Gallery.swift` zwei Funktionen:
   ```swift
   /// Zurück in die Galerie (Toolbar, ⌘G): Prompt und Bausteine bleiben nicht stehen.
   func enterGallery() {
       let cameFromStudio = !showGallery && !showLabs
       showGallery = true
       if cameFromStudio { clearPromptDraft() }
   }
   ```
   `clearPromptDraft()` leert: den Prompt-Entwurf (`builder.reset()`), `gemmaWish = ""`, einen offenen Gemma-Vorschlag (`optimizerTask?.cancel(); optimizer = OptimizerState()`), die Asset-Auswahl (`selectedAssetIDs = []`, danach `updateAssetSentence()`).
2. **Rückgängig:** Bevor `clearPromptDraft()` leert, den Zustand merken (nur wenn Prompt oder Bausteine nicht leer waren): in `PromptBuilder` eine kleine Funktion `stashDraft()` (nutzt den vorhandenen privaten `Snapshot`) und `restoreDraft()` samt `var canRestoreDraft`. Im Menü „Bild“ ein Eintrag **„Prompt wiederherstellen“** (deaktiviert, wenn nichts zu holen ist). Der gemerkte Zustand gilt nur im Speicher und wird beim nächsten Leeren oder beim Wechseln der Bibliothek überschrieben bzw. verworfen. **Halte es klein** (rund 25 Zeilen). Wird es größer, lass es weg und melde es im Bericht.
3. `ModeSwitcher` (Segment „Galerie“) und das Menü „Galerie“ (⌘G) rufen `studio.enterGallery()` statt `studio.showGallery = true`. **Nur diese beiden.** Alle anderen Stellen bleiben bei `showGallery = true`.
4. Nicht anfassen: Referenzbilder, Canvas, Verlauf, Serien-Werte, Labs.

Bekannte Eigenheit (so lassen, im Bericht festhalten): `PromptBuilder.reset()` ruft `recompose()` auf. Im Modus „Referenzen“ erscheinen deshalb die Sätze der noch belegten Referenzplätze sofort wieder im Prompt. Das sind Ableitungen aus den Referenzbildern, keine Bausteine. In „Generieren“, „Bearbeiten“ und „Serien“ muss der Prompt nach der Rückkehr **leer** sein.

Abnahme: Prompt und Bausteine eingeben, Toolbar → Galerie, zurück ins Studio: alles leer (Wunsch an Gemma, Vorschlag, Assets ebenfalls). „Assets verwalten …“ leert **nicht**. „Prompt wiederherstellen“ bringt Prompt und Bausteine zurück.

---

## 3 · Story I – Markiertes Bild dient als Bearbeitungs- und Referenzquelle

**Dateien:** `Model/Studio+Gallery.swift`, `Model/Gallery.swift`, `Model/References.swift`, `Model/Studio+Gemma.swift` (`setReference`, `removeReference`, `clearReferences`), `Views/MainView.swift`, `App/DrawThingsStudioApp.swift`.

### Begriffe
- **Markiert** = (1) ist die Lupe oder ein Stapel offen (`gallery.viewer != nil`): das Bild `gallery.viewer?.currentID`; (2) sonst die Rasterauswahl `gallery.selection` (IDs von Bildern oder Stapeln), aufgelöst in **Rasterreihenfolge** über `gallery.entries` (bei Stapeln `GalleryEntry.cover`). Videos zählen nicht. Fehlende Dateien (`gallery.missing`) zählen nicht.
- **Marke** = der Zustand, den die Galerie beim Verlassen hinterlässt.

### Schritte
1. `Gallery`: `var markedItems: [GalleryItem]` nach den Regeln oben (kein Zustand, nur berechnet).
2. `ReferenceSlot` (`References.swift`) bekommt `var galleryItemID: UUID?` (Bild aus der Galerie, aus dem der Platz stammt).
   - `Studio.setReference(from item:, at:)` setzt es nach dem Einsetzen.
   - Überall, wo ein Platz anders befüllt oder geleert wird (`setReference(_ image:, at:)`, `removeReference`, `clearReferences`, `setPersona`, `setAsset`), wird es auf `nil` gesetzt. Suche mit `grep -n "assetSubject = nil"` nach diesen Stellen.
3. `Studio` bekommt `var galleryMark: GalleryMark?` mit
   ```swift
   struct GalleryMark { var itemIDs: [UUID]; var appliedModes: Set<StudioMode> = [] }
   ```
   (`@ObservationIgnored`, es wird nicht gezeichnet).
4. Neuer **Einstieg** `func switchTo(_ mode: StudioMode)` in `Studio+Gallery.swift`:
   ```swift
   /// Toolbar und ⌘1–4: Modus wählen und das markierte Galeriebild mitnehmen.
   func switchTo(_ mode: StudioMode) {
       if showGallery { galleryMark = GalleryMark(itemIDs: gallery.markedItems.map(\.id)) }
       show(mode)
       applyGalleryMark(for: mode)
   }
   ```
   **`show(_:)` bleibt unverändert** und wird weiter von „Als Referenz verwenden“, „Im Studio verwenden“ (Charakter) und dem Asset-Browser benutzt. Nur `ModeSwitcher` (Segmente der vier Modi) und die Menübefehle ⌘1–4 rufen `switchTo`. Ohne diese Trennung landet bei gezielten Aktionen zusätzlich das markierte Bild irgendwo.
5. `applyGalleryMark(for mode:)` (in `Studio+Gallery.swift`, damit es das dort `private` stehende `studioVersion(for:select:)` nutzen kann):
   - `guard var mark = galleryMark, !mark.appliedModes.contains(mode)`; leere `itemIDs` → nichts tun.
   - `.edit`: **genau ein** Bild → Version über `studioVersion(for:select: true)` laden. Ist `version.id != currentID`, `editAspect = nil` und `select(version)`. Mehrere Bilder → nichts.
   - `.series`: genau ein Bild → `setSeriesSource(version)` (wie `openInStudio(_, mode: .series)`).
   - `.references`: der Reihe nach (höchstens die freien Plätze, höchstens drei) jedes Bild, das noch in keinem Platz liegt (`galleryItemID`), in den ersten freien Platz (`references[i].image == nil`) mit `await setReference(from:at:)`. Kein freier Platz → nichts überschreiben, kein Dialog.
   - `.generate`: nichts, und `appliedModes` nicht ergänzen.
   - Danach `mark.appliedModes.insert(mode)` zurückschreiben.
   - Laden ist asynchron (`Task`). Der Modus-Wechsel selbst bleibt sofort.
6. Marke **verwerfen** (`galleryMark = nil`): in `enterGallery()` (Story III), in `openLibrary` (Bibliothekswechsel, die Bilder gehören zur alten), in `openInStudio`, `newDocument` und `importImage` (ein anderer Weg bringt ein Bild ins Studio und gewinnt).

Abnahme:
- Ein Bild markiert → Toolbar „Bearbeiten“: Bild liegt im Canvas. Danach „Referenzen“: Bild im ersten freien Platz, kein zweites Mal beim erneuten Wechseln. Danach „Serien“ (falls noch nicht geschehen): Ausgangsbild.
- Mehrere markiert → „Referenzen“: bis zu drei Plätze, „Bearbeiten“ unverändert.
- Alle drei Plätze belegt: nichts wird überschrieben.
- „Als Referenz verwenden“ auf Bild A bei markiertem Bild B setzt **nur** A. Charakter „Im Studio verwenden“ rührt die Marke nicht an.
- Ohne Markierung verhalten sich alle Wechsel wie bisher.

---

## 4 · Bug I – Stapel in Seiten zu je neun Bildern

**Dateien:** `Model/Gallery.swift` (`GalleryViewerState`, ca. Zeile 330), `Views/Gallery/GalleryViewer.swift`, `Views/Canvas/SeriesCanvas.swift` (`SeriesCanvas.layout`), `Services/GalleryImages.swift` (nur lesen).

### Ursache
`GalleryViewer.tiles` legt **alle** Bilder des Stapels in ein Raster. `SeriesCanvas.layout(count:aspect:in:spacing:caption:)` verwirft jede Spaltenzahl, bei der eine Zelle unter 20 pt fällt, und gibt im ungünstigen Fall die Startgröße 1 × 1 zurück. Der Filmstreifen (`filmstrip`) zeigt alle Bilder mit je 54 pt. `.task(id: state.displayIDs)` lädt **alle** Vollbilder, der Cache (`GalleryImages.fullImages`) fasst nur 12.

### Entwurf
Die Seite wird **aus dem Index** des markierten Bildes abgeleitet, nicht getrennt gespeichert. So bleiben Pfeiltasten, Filmstreifen und Inspector (`gallery.viewer?.index`) ohne weitere Pflege konsistent.

Schritte:
1. `GalleryViewerState` (rein berechnet, keine neuen gespeicherten Felder):
   ```swift
   static let pageSize = 9
   var pageCount: Int { max((displayIDs.count + Self.pageSize - 1) / Self.pageSize, 1) }
   var page: Int { min(max(index, 0) / Self.pageSize, pageCount - 1) }
   var pageIDs: [UUID] { /* displayIDs[page * pageSize ..< min(…, count)] */ }
   mutating func setPage(_ page: Int)  // index = clamped page * pageSize
   ```
2. `GalleryViewer`:
   - Neue Eigenschaft `pageItems: [GalleryItem]` aus `state.pageIDs`. **`tiles(…)`, `filmstrip` und das Vorladen benutzen `pageItems`**, nicht `items`.
   - **Indexfalle:** Innerhalb der Seite ist `index` seitenrelativ (nur für Reihe, Spalte und `UnfoldEffect`), für den Zustand (`setIndex`, `doubleClick`, `isCurrent`) aber **global** (`state.page * pageSize + indexInPage`). Vergleiche das markierte Bild über die **ID**, nicht über den Index.
   - Rastergröße für alle Seiten gleich: `SeriesCanvas.layout(count: min(items.count, 9), …)` verwenden, damit die Kacheln beim Blättern nicht in der Größe springen. Auf der letzten Seite (weniger als 9) füllen die Kacheln die Reihen von links.
   - Pager als eigene kleine Ansicht, sichtbar nur bei `pageCount > 1`, in der Leiste oben neben „Ansicht“ (Glas-Kapsel wie die übrigen): `‹  Seite 2 von 5 · Bild 10–18 von 41  ›`. Die Pfeile rufen `setPage` mit `withAnimation(.smooth(duration: 0.3))`.
   - Tasten: **Bild↑ / Bild↓** (`.pageUp`, `.pageDown`) und **⌘← / ⌘→** wechseln die Seite. ← → (und Leertaste) laufen über `step(_:)` unverändert Bild für Bild und überschreiten die Seitengrenze von selbst, weil die Seite aus dem Index folgt. Die bestehende Hilfezeile unten um „Bild↑↓ Seite“ ergänzen, wenn `pageCount > 1`.
   - **`tileFrames` aufräumen**, sobald sich die Seite ändert: nur Einträge der aktuellen Seite behalten. Sonst bestimmen veraltete Rahmen `referenceTile`, die Prozentanzeige und den Zoompunkt.
   - Zoom und Ausschnitt (`zoom`, `center`) bleiben beim Seitenwechsel stehen.
   - Beim Seitenwechsel die Kacheln mit einer kurzen Überblendung ersetzen (z. B. `.id(state.page)` auf der Kachelgruppe plus `.transition(.opacity)`). Das große Aufblättern (`UnfoldEffect`) nur beim Öffnen, nicht bei jedem Seitenwechsel.
   - **Vorladen:** `.task(id: state.pageIDs)` lädt nur die Bilder der aktuellen Seite (höchstens 9, unter dem Cache-Limit 12). Im Modus „Blättern“ zusätzlich das jeweils vorige und nächste Bild (`GalleryImages.image(for:)`).
3. `SeriesCanvas.layout`: Rückfall absichern. Findet keine Aufteilung (alle Zellen < 20 pt), nimm `columns = Int(ceil(sqrt(Double(count))))` mit dem dort berechneten Maß statt 1 × 1. Das ändert für bisherige Fälle (höchstens vier Serienbilder) nichts.
4. Modus „Blättern“ (`mode == .flip`): der Filmstreifen zeigt die neun Bilder der Seite. Er soll in die Leiste passen (9 × 54 pt + Abstände, die Leiste ist `fixedSize` im `HStack`). Prüfe die Breite bei schmalem Fenster (Mindestbreite des Fensters beachten). Falls nötig, Vorschaugröße auf 46 pt verkleinern.
5. „Vergleichen“ mit vielen markierten Bildern (`gallery.compare(_:)`) läuft über denselben Viewer und profitiert davon. Nichts extra tun.

Nicht ändern: das Hauptraster der Galerie (Stapel als eine Kachel), `SeriesCanvas` im Modus „Serien“ (höchstens vier Bilder).

Abnahme (Testkopie, Stapel mit 25 Bildern; legt dir dafür Katalogeinträge an, die auf vorhandene Bilddateien zeigen – oder lass den Nutzer einen großen Stapel markieren):
- Seitenaufteilung 9 · 9 · 7. In Raster, Synchron-Zoom und Blättern sind höchstens neun Bilder zu sehen, nichts ragt aus der Leiste.
- ← → läuft über die Seitengrenze; Pager und Tasten wechseln die Seite; der Zoom bleibt; die Prozentanzeige stimmt nach dem Wechsel.
- Speicher: Beim Durchblättern wächst der Speicher nicht mit der Stapelgröße.
- Der Nutzer soll beim Test **einen** großen Stapel im Fenster sehen. Logge den Seitenwechsel (Seite, Index, Zahl der Kacheln) über einen vorübergehenden Hook und entferne ihn danach.

---

## 5 · Bug II – Tags und Charaktere als Dropdown mit Mehrfachauswahl

**Dateien:** neue Datei `Views/MultiSelectDropdown.swift`, `Views/Gallery/LibraryPicker.swift`.

### Komponente
```swift
struct DropdownOption<ID: Hashable>: Identifiable {
    var id: ID
    var title: String
    var count: Int
}

struct MultiSelectDropdown<ID: Hashable, Leading: View>: View {
    let title: String              // „Tags“, „Charaktere“
    let symbol: String             // SF Symbol des Knopfs
    let options: [DropdownOption<ID>]
    @Binding var selection: Set<ID>
    var matchAll: Binding<Bool>? = nil     // nur für Tags: „einer davon“ / „alle“
    @ViewBuilder var leading: (DropdownOption<ID>) -> Leading
}
```
Verhalten:
- Knopf (Stil `.bordered`, `controlSize(.small)`): Symbol, Titel, bei Auswahl der Zähler („Tags · 2“; bei genau einer Auswahl deren Name, gekürzt).
- Darunter ein **Popover** (kein `Menu`, denn `Menu` schließt bei jedem Klick): Liste mit Häkchen-Kästchen (`toggleStyle(.checkbox)`), je Zeile `leading`, Titel, Anzahl rechts (`monospacedDigit`, `.secondary`). **Suchfeld oben ab acht Einträgen.** Höhe begrenzt (z. B. maximal 260 pt, scrollt). Unten „Auswahl aufheben“ (deaktiviert ohne Auswahl) und, falls `matchAll` gesetzt, ein segmentierter Umschalter „Bilder mit: einem davon · allen“.
- Leerzustand: „Noch keine Tags.“ bzw. „Noch keine Charaktere.“ (Text über Parameter).
- Tastatur und Zugänglichkeit: Knopf hat `accessibilityLabel`, Popover schließt mit Esc.

### Einbau in `LibraryPicker`
1. Aus der Seitenleiste (`sidebar(_:)`) die Sektionen **„Charaktere“** und **„Tags“** entfernen. Die Sektionen „Bibliothek“, „Projekte“ und „Datum“ bleiben.
2. Neuer Zustand: `@State private var selectedTags: Set<String>`, `@State private var tagsMatchAll = false`, `@State private var selectedPersonas: Set<UUID>`.
3. Eine **schmale Filterzeile** über dem Raster (im rechten Teil, unter dem Kopf, über `content(_:)`): zwei `MultiSelectDropdown` (Tags, Charaktere), rechts daneben ein „Zurücksetzen“-Link, wenn etwas gewählt ist. Charaktere mit `PersonaAvatar(persona:size:18)` als `leading`. Anzahlen = Bilder dieser Auswahl unter **allen** Bildern (wie bisher in der Seitenleiste).
4. `LibraryPickerScope`: Fälle `.persona` und `.tag` entfallen (samt Zählung und `matches`). Die verbleibenden Fälle sind `all, picks, rated, project, day`.
5. `filtered(_:)`/`matches`: Zusätzlich zur Sammlung links gilt
   - Charaktere: `item.personaIDs` enthält **mindestens einen** der gewählten (wie `Gallery.filter.personaIDs`, siehe `Gallery.swift` ca. Zeile 508).
   - Tags: mit „einer davon“ mindestens einer der gewählten, mit „alle“ alle (wie `Gallery.filter.tags`/`requiresAllTags`; sieh dir dort die Umsetzung an und spiegle sie).
6. Die Auswahl bleibt beim Wechsel der Sammlung links erhalten (sie liegt außerhalb von `scope`).
7. Nach dem Schließen eines Popovers `gridFocused = true`, damit Pfeiltasten, Leertaste und ↩ im Raster weiter funktionieren.
8. Fußzeile zählt weiter die angezeigten Bilder (`shown.count`).

Nicht im Umfang: `GalleryFilterPopover`, `TagFilterSection`. Sie haben Umbenennen und Löschen von Tags.

Abnahme: Seitenleiste des Pickers ohne Tag- und Charakterliste. Zwei Dropdowns mit Mehrfachauswahl, Zähler am Knopf, Popover bleibt beim Anklicken offen, Suchfeld ab acht Einträgen. Filter wirken zusammen mit der Sammlung links. Referenzplatz-Picker und Story-Picker (`StoryPage.swift`) verhalten sich ansonsten wie vorher.

---

## 6 · Story IV – Minibild-Bibliothek in der Foto-Leiste der Charaktere

**Was der Nutzer will (am 21.10.2026 selbst geklärt):** Beim Anlegen eines Charakters gibt es auf der Charakterseite die Leiste „Fotos“ (`CharacterPage.PhotosSection`). Dort lädt man Bilder in verschiedenen Perspektiven (frontal, nach rechts, nach links, Profil, Ganzkörper). Heute geht das nur über den Finder-Dialog oder Ziehen. Es soll **genau derselbe Minibibliotheks-Picker** zur Verfügung stehen **wie bei den Referenzen** (`LibraryPicker`), um Bilder aus der Bibliothek zu übernehmen.

Das heißt: gleiche Ansicht, gleiches Verhalten (Seitenleiste, Suche, Kachelgröße, Klick wählt, Doppelklick oder ↩ übernimmt, Leertaste zeigt groß). Die **einzige** Erweiterung ist die optionale Mehrfachauswahl, weil man mehrere Perspektiven braucht. Baue **keine** festen Plätze je Perspektive und ändere nicht, wie die Perspektive bestimmt wird (Vision schlägt sie vor, das Menü „Ansicht“ je Foto ändert sie).

**Dateien:** `Views/Gallery/LibraryPicker.swift`, `Views/Gallery/CharacterPage.swift` (`PhotosSection`, `AddPhotoCard`), `Views/Gallery/GallerySidebar.swift` (Kontextmenü `PersonaRow`), `Model/Studio+Characters.swift` (`addGalleryItems` existiert, `choosePersonaPhotos` ebenso).

Schritte:
1. `LibraryPicker` bekommt eine **optionale Mehrfachauswahl**. Die bestehende Einzelwahl (`onPick: (GalleryItem) -> Void`, genutzt in `ReferencesPanel` und `StoryPage`) bleibt unverändert nutzbar.
   - Neue Parameter: `var allowsMultiple = false`, `var onPickMany: (([GalleryItem]) -> Void)? = nil`.
   - `selectedID: UUID?` wird zu `selectedIDs: Set<UUID>` (Einzelwahl: höchstens ein Element). ⌘-Klick schaltet ein Bild an und aus, ⇧-Klick wählt einen Bereich (in der Reihenfolge des Rasters), nur wenn `allowsMultiple`.
   - Mehrfach: Knopf „Übernehmen (n)“, deaktiviert ohne Auswahl. Doppelklick auf eine Kachel übernimmt bei höchstens einem gewählten Bild nur dieses (also genau wie in den Referenzen), sonst die ganze Auswahl. ↩ übernimmt die Auswahl. Gewählte Kacheln tragen ein kleines Häkchen oben rechts.
   - Ohne `allowsMultiple` darf sich am Picker **nichts** ändern. Prüfe, dass Referenzplätze und Story-Auswahl weiter wie vorher arbeiten.
   - Leertaste (große Ansicht) und Pfeiltasten bleiben; die große Ansicht zeigt das zuletzt angeklickte Bild.
2. `CharacterPage.PhotosSection`: der Knopf „Fotos hinzufügen …“ wird ein `Menu` mit **„Aus der Bibliothek …“** (öffnet ein Sheet mit `LibraryPicker`, Titel „Fotos für „<Name>“ aus der Bibliothek“, Untertitel „Ansicht (frontal, ¾, Profil …) erkennt die App, du kannst sie je Foto ändern“) und **„Aus Dateien …“** (ruft das vorhandene `studio.choosePersonaPhotos(for:)`). Übernahme mit `studio.addGalleryItems(ids, toPersona: persona.id)`.
3. `AddPhotoCard` (gestrichelte Kachel): ein Klick bietet dieselbe Auswahl (kleines Menü) statt direkt den Finder-Dialog zu öffnen. Drag & Drop bleibt unverändert.
4. Kontextmenü des Charakters in der Seitenleiste: ein zusätzlicher Eintrag **„Fotos aus der Bibliothek …“**. Ein Sheet lässt sich nicht aus dem Kontextmenü selbst zeigen. Setze dort `gallery.collection = .persona(persona.id)` und löse über einen kleinen Zustand (`studio.personaLibraryRequest: UUID?`) das Sheet auf der Charakterseite aus.
5. Fotos landen über `addGalleryItems` als Kopien unter `Charaktere/<ID>/`. Die Funktion existiert, ändere sie nicht.

Abnahme: Auf der Charakterseite (auch bei einem frisch angelegten, leeren Charakter) öffnet „Aus der Bibliothek …“ denselben Picker wie bei den Referenzen, mit zusätzlicher Mehrfachauswahl. Gewählte Bilder erscheinen als Fotos in der Leiste, die Ansicht schlägt Vision vor (je Foto änderbar). „Aus Dateien …“ und Ziehen gehen wie vorher. Einzelwahl in Referenzplätzen und Stories ist unverändert.

Test: **keine echten Charakterfotos** in Screenshots oder Logs. Die Testkopie enthält Kopien davon und wird gelöscht.

---

## 7 · Story VI – Besseres Response-Verhalten beim Bearbeiten (**Deutung unsicher**)

Der Nutzer erinnert sich nicht mehr, was gemeint war. **Annahme:** Die Oberfläche reagiert im Modus „Bearbeiten“ beim Optimieren und Tippen im Prompt zu träge. **Nicht gemeint (nicht anfassen):** die Gemma-Vorlagen in `Services/PromptTemplates.swift`. Diesen Schritt machst du **zuletzt**, zeitlich begrenzt. Er darf mit „nichts gefunden, nichts geändert“ enden.

### Vorgehen: erst messen, dann ändern
1. Messung in der Testkopie mit einem vorübergehenden Hook (`DTS_EDIT_TIMING`, danach entfernen): Bild mit der längsten Kante über 3000 px in „Bearbeiten“, `ContinuousClock` um
   - den synchronen Teil von `Studio.optimizePrompt()` bis zur ersten möglichen Zeichnung,
   - `ImageTools.dataURL(image)`,
   - einen Tastendruck im Prompt (`builder.editPrompt` bis zum Ende von `save()`).
   Alles über 50 ms (Klick) bzw. 16 ms (Taste) ist ein Befund. Schreibe die Zahlen in den Bericht.
2. Nur dann ändern, wenn die Messung es stützt. Verdachtsstellen:
   - **`Studio+Gemma.swift`, `optimizePrompt()`:** `ImageTools.dataURL(image)` (verkleinern, JPEG, Base64) läuft im Modus „Bearbeiten“ **auf dem Main-Thread vor** dem `Task`. Verschiebe die Kodierung in den `Task` (`Task.detached` oder `await Task.detached { … }.value`) und lege das Ergebnis in einen kleinen Zwischenspeicher (letzte 2 Einträge, Schlüssel: Version-ID und `maxSide`), der beim Wechsel von `currentID` nicht geleert werden muss, weil die Version-ID im Schlüssel steckt. Gilt auch für den Zweig `.series` und die Referenzbilder.
   - **`IdentityComposite.render`** vor jeder Optimierung mit Gesichtsreferenz: prüfen, ob es vom Main-Thread läuft, und das Ergebnis je (Bild, Charakter, Größenstufe) zwischenspeichern.
   - **`ensureLMReady()`** lädt ein noch nicht geladenes Modell (`lmStatus = .loading`). Zeige in der `OptimizerCard` einen Satz dazu („Gemma wird geladen …“), solange `lmStatus == .loading`. Bisher sieht der Nutzer nur „Gemma schreibt …“.
   - **Tippen:** Prüfe, ob beim Tippen im Prompt Bereiche der Seitenleiste neu berechnet werden, die nichts mit dem Prompt zu tun haben (`@Observable` verfolgt je Eigenschaft: Wo liest eine große Ansicht `builder.prompt`?). Nur ändern, wenn die Messung eine Verzögerung zeigt.
3. Ändere **kein** Verhalten, das der Nutzer sehen kann (Reihenfolge, Texte, Ergebnis). Gemma bekommt dieselben Eingaben wie vorher.

Abnahme: Klick auf „Optimieren“ zeigt die Karte „Gemma schreibt …“ sofort, ohne Ruckeln, auch mit großem Bild. Messwerte vorher/nachher im Bericht. Oder: „Nichts gefunden, nichts geändert“ mit Zahlen.

---

## Abschluss

1. **`swift build`** ohne Warnung und `./build.sh` (Bundle bauen). **Nicht** installieren, **nicht** neu starten.
2. Alle vorübergehenden Hooks entfernt (`grep -rn "DTS_" Sources` zeigt nur das, was vorher schon da war). Fake-Home gelöscht.
3. **README.md** aktualisieren (deutsch, im bestehenden Stil, mit Datum 21.10.2026 wo es das Muster gibt):
   - Galerie: Projekte, Stories und Charaktere einklappbar (Zustand bleibt, auf zugeklappte Sektion lässt sich nichts ziehen).
   - Galerie/Studio: Zurück in die Galerie (Toolbar, ⌘G) leert Prompt und Bausteine, „Bild › Prompt wiederherstellen“.
   - Galerie/Studio: markiertes Bild wird beim Wechsel in „Bearbeiten“, „Referenzen“ und „Serien“ mitgenommen (Regeln wie oben, in zwei Sätzen).
   - Vergleichen: Stapel und Vergleiche in Seiten zu je 9 Bildern, Pager, Tasten.
   - Mit Referenzen arbeiten: Bibliotheksauswahl mit Dropdowns für Tags und Charaktere.
   - Charaktere: Fotos aus der Bibliothek (derselbe Picker wie bei den Referenzen, mit Mehrfachauswahl).
   - Falls Story VI etwas geändert hat: ein Satz.
   - Die Zeile zu „Zuletzt hinzugefügt“ ist schon da und bleibt.
4. **Bericht** an den Nutzer (deutsch, knapp), je Eintrag ein Block:
   - Status: erledigt / teilweise / nicht gemacht.
   - Geänderte Dateien (Markdown-Links `[Datei](Pfad)`).
   - Wie geprüft (Build, Hook, Testkopie) und was **nicht** geprüft werden konnte.
   - Abweichungen von dieser Anweisung und warum.
   - Am Ende **„Offene Punkte“**: Story VI (Annahme, Messwerte), Eigenheit bei Story III im Modus „Referenzen“, Story I bei mehreren markierten Bildern, Story IV (feste Plätze je Perspektive wurden bewusst nicht gebaut).
5. Nichts über diese Liste hinaus bauen. Fällt dir beim Arbeiten etwas auf, das nicht dazugehört, nenne es im Bericht in einem Satz und lass es.
