# Implementierungsplan – Epic I: Verbesserungen II

Stand: 21.10.2026 · Code: `Sources/DrawThingsStudio/` (SwiftUI, macOS 26, SwiftPM ohne Xcode, rund 25 600 Zeilen)

## 1. Überblick

| # | Eintrag | Status | Kern der Änderung | Aufwand | Risiko |
|---|---|---|---|---|---|
| 1 | **Story V** – Projekte, Stories, Charaktere einklappbar | offen | `Section(isExpanded:)` wie bei „Assets“ | klein | gering |
| 2 | **Story III** – Zurück in die Galerie leert Prompt und Bausteine | offen | neuer Einstieg `enterGallery()`, nur für Toolbar und ⌘G | klein | mittel (Datenverlust, Nebenwege) |
| 3 | **Story I** – markiertes Bild wird Bearbeitungs- und Referenzquelle | offen | „Marke“ beim Verlassen der Galerie, je Modus lazy einlösen | mittel | mittel (Zustand, Nebenwirkungen) |
| 4 | **Bug I** – Stapel in Seiten zu je 9 (Raster, Zoom, Blättern) | offen | Paging in `GalleryViewerState` + `GalleryViewer` | mittel bis groß | mittel (Layout, Zoom, Vorladen) |
| 5 | **Bug II** – Tags und Charaktere als Dropdown mit Mehrfachauswahl | offen | neue Komponente `MultiSelectDropdown`, Einbau in `LibraryPicker` | mittel | gering |
| 6 | **Story IV** – Minibild-Bibliothek in der Foto-Leiste der Charaktere | offen (Sinn am 21.10.2026 vom Nutzer geklärt) | derselbe `LibraryPicker` wie bei den Referenzen, auf der Charakterseite erreichbar | klein bis mittel | gering |
| 7 | **Story VI** – besseres Response-Verhalten der Prompts beim Bearbeiten | offen, **Deutung unklar** | messen, dann nur gesicherte Verbesserungen | klein bis mittel | gering |
| – | **Story II** – Submenü „Zuletzt hinzugefügt“ | **bereits umgesetzt** | `GalleryCollection.recent`, Seitenleiste, `addedAt` | – | – |

Reihenfolge = Ausführungsreihenfolge. Bug II und Story IV ändern beide `Views/Gallery/LibraryPicker.swift` und laufen deshalb nacheinander, nicht parallel. Alle sieben Schritte gehören in **eine** Sitzung.

## 2. Befunde im Code und Entscheidungen

### Story V – Einklappen
- `GallerySidebar.swift` hat für **Assets** schon `Section(isExpanded: $assetsExpanded)` mit `@AppStorage("sidebar.assetsExpanded")`. Projekte, Stories und Charaktere sind normale `Section { } header: { }`.
- Entscheidung: dasselbe Muster mit eigenen Schlüsseln (`sidebar.projectsExpanded`, `sidebar.storiesExpanded`, `sidebar.personasExpanded`), Standard „aufgeklappt“. Der „+“-Knopf klappt die Sektion auf, damit das neue Objekt sichtbar ist.
- Bekannte Folge: Auf eine zugeklappte Sektion lassen sich keine Bilder ziehen. Das ist so gewollt und kommt in die README.

### Story III – Prompt leeren beim Zurückwechseln
- Der Wechsel passiert an drei Stellen direkt über `studio.showGallery = true`: Toolbar-Umschalter (`MainView.swift`, `ModeSwitcher`), Menü „Galerie“ (⌘G, `DrawThingsStudioApp.swift`) und mehrere **Abkürzungen mitten im Arbeiten**: „Assets verwalten …“, „Charaktere verwalten …“, „Assets anlegen“ (`PromptBuilderSidebar`, `ReferencesPanel`).
- Entscheidung: **nur** Toolbar und ⌘G leeren. Die Abkürzungen nicht, sonst verliert man beim Anlegen eines Assets den Prompt. Dafür kommt ein neuer Einstieg `Studio.enterGallery()`.
- Geleert wird nur beim Wechsel aus dem Studio (nicht aus Labs, dort ist der Prompt-Baukasten nicht sichtbar).
- Vorhandener Baustein: `builder.reset()` und `gemmaWish = ""` (so macht es `resetWorkspace(clearPrompt:)`). Dazu Gemmas offener Vorschlag (`optimizer`) und `selectedAssetIDs`.
- Sicherheitsnetz: ein Rückgängig-Schritt („Bild › Prompt wiederherstellen“), weil ein versehentlicher Klick auf „Galerie“ sonst einen langen Prompt vernichtet.
- Bekannte Eigenheit: `PromptBuilder.reset()` ruft am Ende `recompose()` auf. Im Modus „Referenzen“ stehen deshalb die Sätze der noch belegten Referenzplätze sofort wieder im Prompt. Das sind keine eingegebenen Bausteine, sondern Ableitungen aus den Referenzbildern. Wir lassen es so und halten es fest.

### Story I – markiertes Bild als Quelle
- Heute wechselt `Studio.show(_ mode:)` nur den Modus. Das markierte Galeriebild wird ignoriert; „Im Studio bearbeiten“ und „Als Referenz verwenden“ sind getrennte Wege.
- „Markiert“ heißt: ein Bild in der geöffneten Lupe/Stapelansicht (`gallery.viewer?.currentID`), sonst die Auswahl im Raster (`gallery.selection`, bei Stapeln das Deckbild `GalleryEntry.cover`). Videos zählen nicht.
- Entscheidungen:
  - **Genau ein Bild markiert:** Bearbeiten nimmt es als aktuelles Bild, Serien als Ausgangsbild, Referenzen setzt es in den ersten freien Platz.
  - **Mehrere markiert:** nur Referenzen (bis zu drei, in Rasterreihenfolge). Bearbeiten und Serien bleiben unverändert.
  - Kein freier Referenzplatz: nichts überschreiben.
  - Ein Bild, das schon in einem Platz liegt, nicht doppelt einsetzen (dafür bekommt `ReferenceSlot` ein Feld `galleryItemID`).
  - Die Marke wird **je Modus einmal eingelöst** und gilt, bis man wieder in die Galerie geht oder ein anderer Weg ein Bild ins Studio holt. So dient dasselbe Bild nacheinander als Bearbeitungs- und Referenzquelle, ohne dass beim Moduswechsel heimlich Gemma-Beschreibungen für Referenzen anlaufen.
- **Wichtig:** Die Logik hängt an einem neuen Einstieg `Studio.switchTo(_ mode:)`, den nur Toolbar und ⌘1–4 nutzen. `show(_:)` bleibt unverändert, weil es auch von „Als Referenz verwenden“, „Im Studio verwenden“ (Charakter) und dem Asset-Browser aufgerufen wird. Sonst landet bei einer gezielten Aktion zusätzlich das markierte Bild irgendwo.

### Bug I – Stapel mit vielen Bildern
- Ursache in `GalleryViewer.swift`: `tiles(...)` legt **alle** Bilder des Stapels in ein Raster. `SeriesCanvas.layout(count:…)` verwirft jede Aufteilung, bei der eine Zelle unter 20 pt fällt, und fällt dann auf eine 1×1-Größe zurück. Die Anzeige bricht. Der Filmstreifen beim Blättern zeigt ebenfalls alle Bilder (54 pt je Bild, läuft aus der Leiste). `.task(id: state.displayIDs)` lädt außerdem **alle** Bilder in voller Größe vor, der Cache (`GalleryImages.fullImages`) fasst nur 12 – bei großen Stapeln wird er ständig verdrängt.
- Entscheidung: Die Seite ergibt sich aus dem Index des markierten Bildes (`page = index / 9`). Damit bleiben Pfeiltasten, Filmstreifen, Inspector und Seitenwechsel automatisch konsistent. Ein Pager („‹ Seite 2 von 5 ›“) setzt den Index auf das erste Bild der Seite.
- Gilt in allen drei Ansichten (Raster, Synchron-Zoom, Blättern). Zoom und Ausschnitt bleiben beim Seitenwechsel stehen (wie beim Blättern heute).
- Die Rastergröße bleibt über alle Seiten gleich (Layout für `min(Gesamtzahl, 9)` Bilder), damit die Kacheln beim Blättern nicht springen.
- Vorladen nur für die aktuelle Seite (höchstens 9, unter dem Cache-Limit von 12).
- Betrifft auch „Vergleichen“ mit vielen markierten Bildern (`gallery.compare(_:)`), weil dort derselbe Viewer läuft.

### Bug II – Dropdowns mit Mehrfachauswahl
- „Picker“ = `LibraryPicker` („Die Bibliothek im Kleinen“, genutzt in Referenzplätzen und Stories). Seine Seitenleiste listet **alle** Charaktere und **alle** Tags untereinander.
- Entscheidung: neue wiederverwendbare Komponente `MultiSelectDropdown` (Knopf mit Zähler, darunter ein Popover mit Häkchenliste und Suchfeld ab 8 Einträgen, bleibt beim Anklicken offen). Im `LibraryPicker` verschwinden die Sektionen „Charaktere“ und „Tags“ aus der Seitenleiste; zwei Dropdowns sitzen in einer schmalen Filterzeile über dem Raster.
- Semantik wie im Galerie-Filter: Charaktere = mindestens einer der gewählten; Tags = „einer davon“ oder „alle“ (Umschalter im Popover). Die Filter wirken zusätzlich zur Sammlung links.
- Nicht im Umfang: der Galerie-Filter-Popover (`GalleryFilterPopover`). Er hat Umbenennen/Löschen von Tags und eigene Logik. Wenn gewünscht, später mit derselben Komponente.

### Story IV – Minibild-Bibliothek in der Foto-Leiste der Charaktere
- Vom Nutzer am 21.10.2026 geklärt: Beim Anlegen eines Charakters gibt es die Leiste „Fotos“ (`CharacterPage.PhotosSection`), in die Bilder in verschiedenen Perspektiven geladen werden (frontal, ¾ nach links/rechts, Profil, Ganzkörper; je Foto wählt ein Menü „Ansicht“, Vision schlägt sie vor). Heute geht das nur über den Finder-Dialog (`Studio.choosePersonaPhotos`) oder Ziehen. Gewünscht ist **derselbe Minibibliotheks-Picker wie bei den Referenzen** (`LibraryPicker`), um Bilder aus der Bibliothek zu übernehmen.
- Entscheidung: „Fotos hinzufügen …“ wird zur Auswahl „Aus der Bibliothek …“ / „Aus Dateien …“, ebenso die gestrichelte Kachel in der Leiste. Zusätzlich ein Eintrag im Kontextmenü des Charakters in der Seitenleiste.
- Der Picker bleibt **optisch und im Verhalten derselbe** (Klick wählt, Doppelklick oder ↩ übernimmt, Leertaste zeigt groß). Einzige Erweiterung: optional **Mehrfachauswahl** (⌘-/⇧-Klick), weil ein Charakter mehrere Perspektiven braucht und man den Picker sonst für jedes Foto neu öffnen müsste. Ohne Mehrfachauswahl verhält sich ein Doppelklick wie bisher (nimmt genau dieses Bild).
- Übernommen wird über das vorhandene `Studio.addGalleryItems(_:toPersona:)`. Die Perspektive bestimmt wie bisher Vision, änderbar je Foto über das Menü „Ansicht“. Feste Plätze je Perspektive sind **nicht** im Umfang. Falls gewünscht, wäre das ein eigener Schritt.

### Story VI – Response-Verhalten beim Bearbeiten (Deutung unklar, Annahme)
- Ebenfalls nicht mehr rekonstruierbar. Zwei Lesarten: (a) die App reagiert beim Bearbeiten-Prompt träge, (b) Gemmas Antworten auf Bearbeiten-Prompts sind inhaltlich nicht gut genug.
- Umsetzung nur für (a), und nur nach Messung. Gefundene Verdachtsstellen:
  - `Studio.optimizePrompt()` (`Studio+Gemma.swift`) kodiert im Modus „Bearbeiten“ das aktuelle Bild (`ImageTools.dataURL`: verkleinern, JPEG, Base64) **auf dem Main-Thread, bevor** die Karte „Gemma schreibt …“ gezeichnet werden kann. Das wird bei jedem Klick wiederholt.
  - Mit Gesichtsreferenz rendert `IdentityComposite.render` vor jeder Optimierung neu.
  - `ensureLMReady()` lädt ein nicht geladenes Modell, ohne dass das in der Karte sichtbar wird.
- Lesart (b) (Texte in `Services/PromptTemplates.swift`) bleibt unangetastet. Ohne klare Vorgabe wäre das Raten an einer feinjustierten Vorlage.
- Das ist der letzte Schritt und darf mit „nichts gefunden, nichts geändert“ enden.

## 3. Modellempfehlung

**Empfohlen: Claude Sonnet 5.5** (`claude-sonnet-5-5`) für die gesamte Ausführung.

Warum:
- Alle Einträge sind lokale SwiftUI-Änderungen an bekannten Mustern (Sektion einklappen, neuer Einstieg, Paging, Filter-Dropdown). Die Anweisung gibt Dateien, Funktionen und Abnahmekriterien vor. Das braucht saubere Umsetzung, keine offene Architekturarbeit.
- Der Aufwand ist hoch genug (rund 15 Dateien, ein großer Viewer), dass sich ein schnelleres, günstigeres Modell lohnt. Rückfragen entstehen hier eher durch fehlende Information als durch fehlende Tiefe.
- Die Prüfung läuft über `swift build` und eine isolierte Testkopie. Das Modell muss also diszipliniert in Etappen arbeiten und nicht grübeln.

Wann auf **Claude Opus 5.5** (`claude-opus-5-5`) wechseln:
- Wenn Bug I (Viewer mit Zoom, Seitenwechsel und Vorladen) nach zwei Anläufen noch flackert, springt oder Zoomzustand verliert.
- Wenn Story I Nebenwirkungen zeigt, die sich nicht eingrenzen lassen (z. B. falsche Bilder in Referenzplätzen).

Nicht empfohlen: **Haiku 5.5** (Swift 6.2 mit Observation, Layout-Feinheiten und viele zusammenhängende Dateien sind zu viel für schnelles Abarbeiten) und **Fable 5.1** (für diesen Zuschnitt überdimensioniert).

## 4. Prüfplan

Nach jedem Eintrag `swift build` (Debug) ohne Warnung. Zum Schluss `./build.sh` (nur Bundle bauen, **nicht** installieren und die laufende App **nicht** neu starten).

UI-Prüfung nur in der **isolierten Testkopie** (Regeln siehe Anweisung, Abschnitt „Regeln“). Vorher ankündigen, wenn der Bildschirm übernommen werden müsste.

| Eintrag | Abnahme |
|---|---|
| V | Drei Sektionen lassen sich ein- und ausklappen, der Zustand bleibt nach Neustart. „+“ klappt auf. |
| III | Toolbar oder ⌘G aus dem Studio: Prompt, Bausteine, Wunsch an Gemma, Gemma-Vorschlag und Asset-Auswahl leer. „Assets verwalten …“ leert **nicht**. „Prompt wiederherstellen“ bringt alles zurück. |
| I | Ein Bild markiert, Toolbar → Bearbeiten: Bild liegt im Canvas. Danach Referenzen: Bild im ersten freien Platz, nicht doppelt. Mehrere markiert: bis zu drei Plätze, Bearbeiten unverändert. „Als Referenz verwenden“ auf Bild A bei markiertem Bild B setzt **nur** A. |
| Bug I | Stapel mit 25 Bildern: 3 Seiten (9 · 9 · 7). Raster, Synchron-Zoom und Blättern zeigen höchstens 9 Bilder. ← → läuft über die Seitengrenze, Pager und Tasten (Bild↑/Bild↓, ⌘←/⌘→) wechseln die Seite, Zoom bleibt. Kacheln behalten ihre Größe. |
| Bug II | Im `LibraryPicker` keine Tag- und Charakterlisten mehr links. Zwei Dropdowns, Mehrfachwahl, Zähler am Knopf, Filter wirken zusammen mit der Sammlung. Auswahl bleibt beim Wechsel der Sammlung erhalten. |
| IV | Charakterseite: „Aus der Bibliothek …“ öffnet den Picker mit Mehrfachauswahl. Gewählte Bilder erscheinen als Fotos des Charakters. Der Finder-Weg funktioniert weiter. |
| VI | Kurzbericht mit Messwerten (vorher/nachher) oder „nichts gefunden“. Hauptthread blockiert beim Klick auf „Optimieren“ nicht mehr spürbar. |

## 5. Risiken

- **Testdaten:** Charakterfotos sind personenbezogene Daten. Die Testkopie enthält Kopien davon und muss danach gelöscht werden.
- **Paralleles Arbeiten:** Der Nutzer arbeitet in der App. Kein `pkill`, kein Neustart, keine zweite Instanz gegen die echte Bibliothek.
- **Stille Nebenwirkungen:** Story I und III hängen sich an den Moduswechsel. Deshalb die getrennten Einstiege `switchTo` und `enterGallery`.
- **Bibliotheksspeicher:** Beim Seitenwechsel dürfen nicht alle Bilder eines Stapels als Vollbild geladen werden.
- **Umfang:** Story VI ist unscharf. Nichts darüber hinaus bauen.

## 6. Offene Punkte für den Nutzer

1. Story VI: Ging es um die Trägheit der Oberfläche oder um die Qualität von Gemmas Bearbeiten-Prompts? (Der Nutzer weiß es nicht mehr; wir setzen nur die Trägheit nach Messung um.)
2. Story I: Soll bei **mehreren** markierten Bildern „Bearbeiten“ das erste nehmen? (Jetzt: nein, nur Referenzen.)
3. Story IV: Reicht „Perspektive automatisch durch Vision, je Foto änderbar“, oder sollen feste Plätze je Perspektive her?
