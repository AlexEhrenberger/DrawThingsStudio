# DrawThings Studio

Persönliche macOS-App (SwiftUI, macOS 26) als Erweiterung für Draw Things:
Bilder generieren, bearbeiten, analysieren – mit Prompt Builder und Gemma als Prompt-Optimierer.

## Bauen & starten

Kein Xcode nötig, die Command Line Tools reichen.

```bash
./build.sh            # baut build/DrawThings Studio.app
./build.sh install    # zusätzlich nach ~/Applications kopieren
open "build/DrawThings Studio.app"
```

Zum schnellen Entwickeln geht auch `swift run`.

## Voraussetzungen

- **Draw Things**: Einstellungen › API-Server › Protokoll **HTTP**, Port **7860**.
- **LM Studio** auf `http://127.0.0.1:1234` mit `gemma-4-e4b-uncensored-hauhaucs-aggressive` (Vision nötig).
- Beides lässt sich unter *DrawThings Studio › Einstellungen* ändern.

## Aufbau

| Bereich | Inhalt |
|---|---|
| Links – Prompt Builder | Promptfeld, Gemma-Optimierung, Bibliothek, aufklappbare Bausteine (Motiv, Kamera, Bildkomposition, Text im Bild; beim Bearbeiten zusätzlich „Format“ und „Bearbeitung“) |
| Mitte – Canvas | Format und Größe (Klein · Normal · Groß), Bild, Zoom, Vorher/Nachher, Versionen, Fortschritt – im Modus „Serien“ das Raster aller Varianten |
| Rechts – Inspector | Anpassen, Zuschneiden & Ausrichten, Auswahl, Analyse, Referenzen, Serie, Verlauf |
| Toolbar | Nur Symbole (Name im Tooltip): Galerie · Generieren · Bearbeiten · Referenzen · Serien · Labs, Status Gemma (Gehirn) und Draw Things (Palette) mit Ampelpunkt, Generieren |

Code: `Sources/DrawThingsStudio/` – `Model/` (Zustand, Prompt-Zusammenbau), `Services/` (LM Studio, Draw Things, Prompt-Vorlagen, Bildwerkzeuge), `Views/`.
Die Bausteine stehen in `Resources/Catalog.json` (Texte aus ThePromptEngineer).
Die Gemma-Anweisungen für Qwen Image 1.0 und Qwen Image Edit 2511 stehen in `Services/PromptTemplates.swift`.

## Darstellung

Unter *Einstellungen › Darstellung*: **Matt** (wie gewohnt) oder **Glas** – Seitenleiste und Inspector als Liquid Glass,
der Schreibtisch hinter dem Fenster färbt sie leicht ein. Arbeitsfläche und Galerie bleiben deckend.

## Bibliotheken

Alles liegt in **einem normalen Ordner** – nichts versteckt in `~/Library`:

```
Kunde A/
  2026-10-11/…        Bilder und Videos, nach Tagen
  Charaktere/<ID>/…   Fotos der Charaktere
  Assets/<Kategorie>/… Kleidung, Schuhe, Orte, Gesamtreferenzen …
  Katalog/            gallery.json, characters.json, assets.json, building-blocks.json (Prompt-Bausteine),
                      saved-prompts.json, prompt-draft.json (Entwurf), series.json, character-test.json, Vorschaubilder/, Labs/
```

Alles, was sich anpassen lässt, gehört zur Bibliothek: Prompt-Bausteine samt eigener Bereiche und Kategorien, Asset-Kategorien,
gespeicherte Prompts, der Prompt-Entwurf und die Serien-Werte. **Eine neue Bibliothek beginnt bei null** – mit den mitgelieferten
Bausteinen und Asset-Kategorien. Bei der App bleiben nur Verbindungen, Modelle, Darstellung und Fenster (Einstellungen der App).

- Mehrere Bibliotheken, z. B. je Kunde oder Auftrag: unten links in der Galerie (Menü mit dem Bibliotheksnamen), im Menü *Ablage › Bibliothek* oder unter *Einstellungen › Bibliotheken*.
- Pfade im Katalog stehen relativ – Ordner auf eine SD-Karte kopieren und dort öffnen. Fehlt das Laufwerk, zeigt die Galerie das an und lädt von selbst, sobald es wieder steckt. Gesichert wird dann nirgendwo anders.
- **Bibliothek löschen** (Menü unten links): löscht den Ordner sofort und endgültig (nicht in den Papierkorb), dazu Bilder, die aus ihr noch im Papierkorb liegen, und die Vorschaubilder von Quick Look. Ist sie geöffnet, wird auch das Studio geleert (Bild, Verlauf, Referenzen, Prompt, Serien-Werte). Zur Bestätigung den Namen eintippen.
  Nicht erfasst: Exporte an anderen Orten, Time-Machine-Backups und der Verlauf in Draw Things selbst.
- Die erste Bibliothek ist der bisherige Ablageordner `~/Pictures/DrawThings Studio`; Katalog, Vorschaubilder und Charakterfotos sind beim ersten Start aus Application Support dorthin umgezogen.
  Auch Bausteine, gespeicherte Prompts, Prompt-Entwurf und Serien-Werte sind mit umgezogen – Application Support ist danach leer.
  Nachsehen: *Einstellungen › Bibliotheken › Außerhalb der Bibliotheken* (Knöpfe „Im Finder zeigen“).

## Galerie (⌘G)

Die App startet in der Galerie – wie die Bibliothek in Lightroom. Sie zeigt alle Bilder und Videos der Bibliothek, nach Tagen gruppiert.

- **Zoomen:** mit zwei Fingern auf dem Trackpad aufziehen (Pinch), ⌘+ / ⌘−, + / − oder der Regler unten. Ab großen Kacheln lädt die volle Auflösung.
- **Filter** unten: Kästchen *Bilder* / *Videos*, dazu „Filter“ für Seitenverhältnis (die Draw-Things-Formate 1:2 … 9:16, „Freie Formate“), Tags und Charaktere.
- **Datum** (Kästchen unten oder *Darstellung › Datum in der Galerie ein-/ausblenden*): ohne Datum liegen alle Kacheln am Stück, ohne Tagesüberschriften und halb leere Zeilen. Das Datum steht dann im Tooltip der Kachel.
- **Fokusmodus** (F, ⇧⌘F oder der Knopf oben rechts): Vollbild, schwarz, nur die Bilder. Pinch zoomt, Doppelklick zeigt ein Bild ganz ohne Leisten, Rechtsklick bietet alle Aktionen.
  Oben links blenden kleine Knöpfe die Seitenleiste (Projekte, Stories, Charaktere, Assets) und die Info ein; sie verschwinden, solange die Maus ruht. Esc beendet.
- **Seitenleiste einklappen** (seit 21.10.2026): Projekte, Stories, Charaktere und Assets klappen mit dem Pfeil im Titel zu und auf. Der Zustand bleibt beim nächsten Start; das + klappt eine zugeklappte Sektion auf.
  Auf eine zugeklappte Sektion lassen sich keine Bilder ziehen. Eine dort gewählte Sammlung bleibt gewählt.
- **Zurück in die Galerie** (Toolbar oder ⌘G, seit 21.10.2026) leert im Studio Prompt, Bausteine, den Wunsch an Gemma, Gemmas offenen Vorschlag und die Asset-Auswahl.
  *Bild › Prompt wiederherstellen* holt Prompt und Bausteine zurück (nur im Speicher, bis zum nächsten Leeren oder Wechsel der Bibliothek). Abkürzungen mitten im Arbeiten – „Assets verwalten …“, „Charaktere verwalten …“ – leeren nichts.
  In „Referenzen“ stehen danach weiter die Sätze der noch belegten Referenzplätze im Prompt: Sie stammen aus den Referenzbildern, nicht aus den Bausteinen.
- **Markiertes Bild mitnehmen** (seit 21.10.2026): Wer aus der Galerie per Toolbar oder ⌘1–⌘4 ins Studio wechselt, nimmt das markierte Bild mit – in der Lupe oder einem offenen Stapel das gezeigte, sonst die Auswahl im Raster (Videos zählen nicht).
  Ein Bild: in „Bearbeiten“ liegt es auf dem Canvas, in „Serien“ ist es das Ausgangsbild, in „Referenzen“ liegt es im ersten freien Platz. Mehrere Bilder: nur „Referenzen“ (bis zu drei, in Rasterreihenfolge, nichts wird überschrieben).
  Das gilt je Modus einmal und endet mit dem nächsten Gang in die Galerie. „Als Referenz verwenden“, „Im Studio bearbeiten“ und „Im Studio verwenden“ (Charakter) bleiben gezielte Wege und nehmen nichts zusätzlich mit.
- **Videos:** MP4, MOV und M4V aus dem Finder auf die Galerie ziehen oder *Ablage › Bilder & Videos importieren …* (⇧⌘O) – sie werden in die Bibliothek kopiert. Doppelklick spielt ab.

- **Serien liegen als Stapel.** Ein Klick fächert den Stapel auf: alle Varianten nebeneinander. ⌘-Klick wählt nur aus.
- **Vergleichen** in drei Ansichten (oben umschaltbar, Tasten G · Z · B):
  - *Raster* – alle Bilder nebeneinander, Doppelklick öffnet eines groß.
  - *Synchron-Zoom* – Pinch, ⌘-Scrollen oder Doppelklick zoomt alle Bilder an derselben Stelle, Ziehen verschiebt alle.
  - *Blättern* – ein Bild groß mit Filmstreifen, ← → wechselt; Zoom und Ausschnitt bleiben dabei stehen.
  - „Ausgangsbild“ nimmt das Bild dazu, aus dem die Serie entstanden ist.
  - **Seiten zu je 9 Bildern** (seit 21.10.2026): Stapel und Vergleiche mit mehr Bildern blättern seitenweise – oben „‹ Seite 2 von 5 · Bild 10–18 von 41 ›“, **Bild↑ / Bild↓** oder **⌘← / ⌘→** wechseln die Seite.
    ← → läuft weiter Bild für Bild und überschreitet die Seitengrenze von selbst. Zoom und Ausschnitt bleiben beim Seitenwechsel stehen; der Filmstreifen beim Blättern zeigt die neun Bilder der Seite und lädt nur sie (plus das vorige und nächste Bild) vor.
- Mehrere Bilder auswählen (⌘/⇧-Klick) und „Vergleichen“ (C) – oder „Als Stapel gruppieren“.
- **Markieren und Bewerten** wie in Lightroom: P behalten, X verwerfen, U ohne Markierung, 0–5 Sterne. Links filtern nach Behalten, Bewertet, Verworfen; unten nach Mindestbewertung. (Die Tage stehen seit 16.10.2026 nicht mehr in der Seitenleiste – das Raster ist ohnehin nach Tagen gruppiert.)
- Leertaste zeigt ein Bild groß, ← → blättert durch die Galerie, Esc führt zurück.
- Suche oben rechts durchsucht die Prompts (und Tags).
- „Im Studio bearbeiten“, „Als Ausgangsbild für eine Serie“, „Als Referenz verwenden“, „Prompt übernehmen“ holen ein Bild ins Studio; „Als Asset sichern“ legt es in den Asset-Baukasten.
- ⌘⌫ legt Bilder nach Rückfrage in den Papierkorb.

### Tags

- Jedes Bild kann beliebige **Tags** tragen, z. B. „Strand“, „Kampagne Herbst“. Vergeben rechts in der Info (Taste **T** fokussiert das Feld) –
  mehrere mit Komma trennen, vorhandene Tags werden beim Tippen vorgeschlagen, die häufigsten stehen darunter zum Anklicken.
  Groß-/Kleinschreibung übernimmt die App vom vorhandenen Tag („strand“ wird „Strand“).
- Für mehrere Bilder oder einen Stapel gilt das Feld für alle; gestrichelte Tags tragen nur manche – ein Klick gibt sie allen.
- Rechtsklick › **Tags** hakt Tags für das Bild bzw. die Auswahl an und ab.
- **Filtern:** „Filter“ unten › *Tags* – mehrere gewählt: Bilder mit *einem davon* oder mit *allen*. Rechtsklick auf ein Tag in der Info: „Alle Bilder mit … zeigen“.
- Im Filter benennt ein Doppelklick (oder Rechtsklick › Umbenennen) ein Tag überall um – heißt schon eins so, werden beide zusammengelegt. „Von allen Bildern entfernen“ löscht es.
- Kacheln mit Tags tragen unten ein kleines Etikett; die Tags stehen im Katalog (`Katalog/gallery.json`), nicht in den Bilddateien.

### Notizen & To-dos

- Zu jedem Bild rechts im Inspector: **To-do** (zum Abhaken), **Gefällt** oder **Gefällt nicht**. Taste N öffnet das Feld, Doppelklick auf eine Notiz bearbeitet sie.
- Kacheln mit offenen To-dos tragen eine orange Zahl, die Seitenleiste zählt alle offenen To-dos.
- **„Notizen & To-dos“** in der Seitenleiste zeigt alle Bilder mit ihren Notizen – Filter Offen · Erledigt · Alle und nach Projekt; die Suche findet auch Notiztexte.
- **„Umsetzen“** bei einem To-do öffnet das Bild in „Bearbeiten“, das To-do wird zum Prompt und Gemma schreibt daraus die Anweisung für Qwen Image Edit.
  Oben auf dem Canvas steht, woran du arbeitest; was dabei entsteht, hängt sich als Ergebnis an das To-do. „Erledigt“ hakt es ab.
- Im Studio zeigt der Verlauf die Notizen des Bildes, das aus der Galerie kommt.

### Projekte

- Wie Sammlungen in Lightroom: Ein Bild kann in mehreren Projekten liegen. Anlegen mit + in der Seitenleiste (nimmt die Auswahl gleich mit), umbenennen über das Kontextmenü.
- Bilder auf ein Projekt ziehen (die ganze Auswahl bzw. der ganze Stapel kommt mit) oder über „Projekt“ im Kontextmenü und im Inspector zuordnen.
- **Aktives Projekt** (Kontextmenü des Projekts): Jedes neue Bild landet automatisch darin; der Fenstertitel zeigt es an.

### Stories

Wie ein Projekt, nur **geordnet**: Bild 1 ist der Anfang, das letzte Bild das Ende.

- **Anlegen** mit + bei „Stories“ in der Seitenleiste (nimmt die Auswahl mit), Bilder auf die Story ziehen, im Kontextmenü „Story ›“
  oder auf der Story-Seite das Symbol „Bild hinzufügen“ (Bibliotheksauswahl). Neue Bilder kommen ans Ende – mehrere auf einmal in der Reihenfolge, in der sie entstanden sind.
  Videos gehören nicht in eine Story, jedes Bild steht höchstens einmal darin.
- **Storyboard:** die Bilder mit Nummer, „Anfang“ und „Ende“. Ziehen sortiert um, ⌘← / ⌘→ schiebt die Auswahl, Rechtsklick › An den Anfang / Ans Ende,
  „Umdrehen“ unten kehrt die Reihenfolge um. Zoomen wie in der Galerie (Pinch, + / −, Regler). ⌫ nimmt Bilder aus der Story (sie bleiben in der Galerie), ⌘⌫ legt sie in den Papierkorb.
- **Präsentieren** (Knopf oben rechts, ⌥⌘P): wie eine Diashow vom Anfang bis zum Ende – im **Vollbild** oder **im Fenster**, mit **einem Bild** oder einem Raster aus **2** bzw. **4 Bildern** je Seite.
  Der Knopf startet mit der zuletzt gewählten Art, der Pfeil daneben bietet alle sechs; Rechtsklick auf ein Bild › „Ab hier präsentieren“.
  → / Leertaste / Klick blättert, ← zurück, Pos1 / Ende springen, 1 · 2 · 4 wechselt das Raster, F Vollbild ↔ Fenster, Esc beendet. Die Leiste unten verschwindet, solange die Maus ruht.
- **Video** (Umschalter oben): Je zwei benachbarte Bilder werden ein Clip – Bild n ist das Startbild, Bild n+1 das Endbild. Gemma schreibt die Prompts dafür, generiert wird außerhalb der App.
  - **Videomodell** (Preset): bisher **Gemini Omni** (Google). Gemma ist darauf eingestellt – nach Googles Prompt-Anleitung für Omni (Stand 16.10.2026):
    Start- und Endbild, ein durchgehender Shot („One continuous shot, no cuts.“), Kamera mit klaren Begriffen (static, push in, dolly, orbit …), am Ende genau das, was das Endbild zeigt,
    keine Qualitätsfloskeln, Ausschlüsse als kurze Sätze. Omni erzeugt immer Ton – deshalb steht unter jedem Prompt „Sound design: …“ (und je nach Einstellung „Music: …“, sonst „No music. No dialogue.“).
  - Einstellungen: Format (Auto = wie die meisten Bilder, 16:9 oder 9:16), Länge je Clip (4–10 s, einzelne Clips abweichend), Ton (Nur Geräusche · Geräusche & Musik · Gemma entscheidet).
  - „Worum geht es?“ (optional, Deutsch). **Story schreiben**: Gemma sieht sich erst alle Bilder an (bei vielen eine gleichmäßige Auswahl von 8) und schreibt die **Handlung** –
    ein paar Sätze und eine Zeile je Bild, bearbeitbar. Danach schreibt sie jeden Clip einzeln mit Start- und Endbild, Handlung und Nachbar-Clips.
  - Je Clip: „Was soll passieren?“ (optional; Gesprochenes in Anführungszeichen landet als Dialog im Prompt), Gemmas Prompt (bearbeitbar), ihre Zusammenfassung auf Deutsch, „Neu schreiben“, „Prompt kopieren“.
    Start- und Endbild lassen sich direkt in Gemini oder Flow im Browser ziehen oder kopieren.
  - Prompts hängen an den beiden Bildern: Nach dem Umsortieren fehlen nur die Clips neuer Nachbarn, die anderen bleiben. Hat sich die Reihenfolge seit der Handlung geändert, weist die App darauf hin.
  - „Alle Prompts kopieren“ oder **Exportieren …**: ein Ordner mit den Bildern in Story-Reihenfolge (`01.png`, `02.png` …) und `Prompts.txt`.
  - Die Anweisungen an Gemma stehen in `Services/StoryPromptTemplates.swift`, das Preset in `Model/VideoPreset.swift`.

### Charaktere

Für Bilder, auf denen eine bestimmte Person gleich aussieht (nur mit ihrem Einverständnis – die Seite hat ein Feld dafür).

- **Anlegen:** + bei „Charaktere“ in der Seitenleiste, dann Fotos hineinziehen (Finder oder Galerie) oder „Fotos hinzufügen …“.
  Das Menü bietet **„Aus der Bibliothek …“** und „Aus Dateien …“ (ebenso die gestrichelte Kachel und, seit 21.10.2026, das Kontextmenü des Charakters: „Fotos aus der Bibliothek …“).
  „Aus der Bibliothek“ ist dieselbe Auswahl wie bei den Referenzen, zusätzlich mit **Mehrfachauswahl**: ⌘-Klick schaltet ein Bild an und aus, ⇧-Klick wählt einen Bereich, „Übernehmen (n)“ oder ↩ nimmt alle,
  ein Doppelklick auf ein gewähltes Bild bei mehreren Gewählten ebenfalls. Die Bilder werden als Kopien Fotos des Charakters; die Ansicht schlägt Vision vor.
  Am besten frontal, ¾ von beiden Seiten, Profil und eine Ganzkörperaufnahme – gleichmäßiges Licht, neutraler Ausdruck, ohne Sonnenbrille.
- Apples Vision findet das Gesicht und schlägt die Ansicht vor (an der Kopfdrehung); sie lässt sich je Foto ändern. Das erste Frontalfoto ist das **Hauptbild**.
- **Referenz für Draw Things:** Über die HTTP-API kommt nur ein Bild verlässlich an. Deshalb setzt die App die Ansichten zu einem **Raster** in einem Bild zusammen:
  großes Frontalporträt, daneben bis zu drei Ansichten, Gesichter eng auf Kopf und Schultern zugeschnitten, ohne Beschriftung.
  Das Raster entsteht bei jedem Bild neu im Format des Bildes. Alternative: **Einzelfoto** (nur das Hauptbild, so groß wie möglich).
- Gemma beschreibt das Aussehen (nach dem ersten Foto automatisch) – diese Beschreibung kommt als Text-Anker in den Prompt.
- **Verwenden:** „Im Studio verwenden“ setzt den Charakter als Bild 1 in „Mit Referenzen arbeiten“; dort lässt er sich je Platz auch über „Charakter“ wählen.
  Jedes Bild, das so entsteht, steht danach auf der Seite des Charakters.
- **Test Raster gegen Einzelfoto:** dieselbe Szene zweimal mit gleichem Seed in 3:4 – die beiden Bilder liegen als Stapel „Charaktertest“ in der Galerie
  und öffnen sich mit „Vergleichen“ gleich im Synchron-Zoom. Danach unter „Referenz für Draw Things“ festlegen, was besser funktioniert.
  Der Szenentext gehört zur Bibliothek (`Katalog/character-test.json`); bis 12.10.2026 stand er in den Einstellungen der App und ist einmalig in die damals geöffnete Bibliothek umgezogen.
- **Ist auf dem Bild:** Kontextmenü *Charakter* oder Info rechts – für den Filter und die Gesichtsreferenz. Bilder, in die ein Charakter als Referenz eingeflossen ist, sind automatisch zugeordnet.
- **Gesichtsreferenz beim Bearbeiten:** Liegt ein Bild mit Charakter in „Bearbeiten“, schlägt die App vor, Frontal- und Seitenansicht mitzuschicken.
  Dann geht an Draw Things ein Raster: das Bild groß links, rechts zwei Ansichten des Charakters. Gemma schreibt die Anweisung für das große Feld, die App schneidet es danach wieder heraus.
  Hilft, wenn Qwen sonst ein Gesicht erfinden müsste (z. B. Kopf zur Kamera drehen). Experimentell: Die App prüft, ob die Referenzspalte im Ergebnis gleich geblieben ist, und warnt sonst;
  „Raster“ zeigt, was gesendet wurde und was zurückkam. Das ganze Raster hat eine der Draw-Things-Größen (siehe *Formate*, gewählte Stufe) – das Bild darin wird dafür kleiner als bei einer normalen Bearbeitung,
  das Ergebnis also auch. Die App nimmt das Format, in dem das Bild am größten bleibt und rechts mindestens ⅓ der Höhe für die Gesichter frei ist. Ein- und ausschalten auch links unter *Bearbeitung › Gesichtsreferenz*.
- Fotos und Beschreibungen liegen in der Bibliothek unter `Charaktere/` und `Katalog/characters.json`.
- Im Modus „Serien“ ist das Ausgangsbild schon Bild 1 – ein Charakter lässt sich dort nicht als zweites Bild mitschicken.

### Assets

Der **Asset-Baukasten** – wie die Prompt-Bausteine, nur mit Bildern: Kleidung, Schuhe, Accessoires, Orte, Objekte, Posen, Stile und **Gesamtreferenzen** (ganze Bilder, die du oft als Referenz nimmst).

- In der Galerie unter „Assets“: Bilder aus dem Finder oder der Galerie auf eine Kategorie ziehen, „Bilder hinzufügen …“ oder im Kontextmenü eines Bildes „Als Asset sichern“. Die Bilder werden in die Bibliothek kopiert.
- Gemma beschreibt jedes Asset passend zur Kategorie (englisch, bearbeitbar).
- **Bereiche und Kategorien** wie bei den Bausteinen – Stand 0: *Mode* (Kleidung, Schuhe, Accessoires), *Orte & Dinge* (Orte, Objekte & Produkte),
  *Pose & Stil* (Posen, Stile & Looks), *Referenzen* (Gesamtreferenzen). + in der Seitenleiste legt eine Kategorie oder einen Bereich an;
  Name, Symbol, Bedeutung und Bereich per Rechtsklick, Reihenfolge per Ziehen. Ein Klick auf den Bereich zeigt alle seine Kategorien.
  „Gilt als“ ist eine der Rollen (Kleidung, Ort …) oder ein **eigenes Thema** auf Englisch – für „Frisuren“ schlägt Gemma z. B. „hairstyle“ vor.
  Dann beschreibt Gemma nur die Frisur, und im Prompt steht „Picture 1 shows the hairstyle …“.
- **Im Studio:** links unter „Assets“ als Bausteine. In „Referenzen“ setzt ein Klick das Bild in den nächsten freien Referenzplatz (mit passender Rolle); in den anderen Modi kommt Gemmas Beschreibung in den Prompt, und Gemma sieht beim Optimieren das Bild.
  In jedem Referenzplatz gibt es außerdem das Menü „Asset“. Oft benutzte Assets stehen vorne.

Der Katalog (Serien, Markierungen, Bewertungen, Notizen, Projekte, Stories samt Video-Prompts) steht in `Katalog/gallery.json` der Bibliothek,
Vorschaubilder daneben in `Katalog/Vorschaubilder/`. Beim Start und mit dem Pfeil unten links liest die Galerie die Bibliothek neu ein.
Jede PNG trägt die Serien-Angaben zusätzlich im Kommentar (`series: <ID>, variant: 2, value: …`) – so lassen sich Stapel
auch ohne Katalog wiederherstellen. Ältere Serienbilder ohne diese Angaben stapelt die Galerie nach Zeitabstand (bis zu vier Bilder).

## Mit Referenzen arbeiten (⌘3)

Bis zu drei Referenzbilder, jedes mit einer Rolle (Person, Kleidung, Ort …). Ein Platz lässt sich füllen durch Hineinziehen, Klick (Datei),
„Canvas-Bild“, „Charakter“, „Asset“ – oder **„Bibliothek“**: Das öffnet die Bibliothek im Kleinen, wie die Fotoauswahl in macOS.
Links Alle Bilder, Behalten, Bewertet, Projekte und Tage, oben die Suche (Prompt und Tags), unten die Kachelgröße.
Über dem Raster stehen zwei Dropdowns mit Mehrfachauswahl (seit 21.10.2026): **Tags** (Bilder mit einem davon oder mit allen) und **Charaktere** (mindestens einer); ab acht Einträgen gibt es ein Suchfeld, „Zurücksetzen“ hebt beide auf.
Sie wirken zusammen mit der Sammlung links und bleiben beim Wechsel der Sammlung stehen; die Zahlen zählen die Bilder der ganzen Bibliothek.
Klick wählt, Doppelklick oder ↩ übernimmt, Leertaste zeigt das Bild groß (← → blättern). Rechtsklick auf einen belegten Platz: „Durch Bild aus der Bibliothek ersetzen …“.

## Serien (⌘4)

Aus einem Ausgangsbild entstehen bis zu vier Varianten, die sich nur in **einer Variable** unterscheiden
(Kleidung, Pose, Hintergrund, Farben, Beleuchtung, Mimik, Frisur, Perspektive, Stil oder eine eigene).

1. Ausgangsbild wählen – beim Wechsel in den Modus wird das aktuelle Bild übernommen.
2. Variable wählen und bis zu vier Zustände eintragen (kurz auf Deutsch reicht, Bausteine aus dem Katalog gehen auch).
3. „Serie starten“ (⌘↩): Gemma schreibt zuerst für jede Variante einen Prompt für Qwen Image Edit 2511 (mit Blick aufs Ausgangsbild),
   danach rendert Draw Things ein Bild nach dem anderen – Gemma und Draw Things laufen nie gleichzeitig.
4. Die Ergebnisse stehen als Raster nebeneinander (Klick vergrößert), landen im Verlauf und in der Bibliothek (`…-series.png`).

Der Prompt in der Seitenleiste gilt zusätzlich für jedes Bild. Standardmäßig nutzen alle Bilder denselben Seed,
damit sie sich wirklich nur durch die Variable unterscheiden. Einzelne Bilder lassen sich mit neuem Seed oder geändertem
Prompt neu rendern. Ist Gemma nicht erreichbar, nimmt die Serie einfache Vorlagen-Prompts.

## Labs (⌘5)

Eigener, dunkler Bereich wie der Fokusmodus: **Bild zusammenbauen** für Qwen Image Edit 2511 in Draw Things.
Labs schickt nichts über HTTP – Gemma schreibt den Prompt, du fügst ihn in Draw Things ein und stellst Draw Things selbst ein.

1. **Canvas** – das Bild, das verändert wird (im Prompt „Picture 1“). Daneben bis zu drei **Moodboards** – die belegten heißen der Reihe nach „Picture 2“, „Picture 3“, „Picture 4“.
   So beschriftet Qwen Image Edit die Eingabebilder selbst (Alibabas Referenz-Pipeline: „Picture 1: <Bild> Picture 2: <Bild> …“).
   Bilder hineinziehen (Finder, andere Apps), klicken, ⌘O / ⇧⌘V (nächster freier Platz), über ⋯ aus Zwischenablage, Studio, Assets oder Charakteren –
   oder in der Galerie bzw. bei einem Asset „In Labs verwenden“.
2. Unter jedes Bild auf Deutsch schreiben, was passieren soll – z. B. Canvas „Der Mann in der Mitte bleibt“, Moodboard 1 „Ersetze die Ampel durch diese Laterne“,
   Moodboard 2 „Nimm diesen Himmel“. Darunter optional etwas für das ganze Bild.
3. „Prompt schreiben“ (⌘↩): Gemma sieht alle Bilder und schreibt einen kurzen, direkten englischen Prompt nach Alibabas eigener Umschreib-Anleitung
   („Edit Prompt Enhancer“ in `QwenLM/Qwen-Image`, `src/examples/tools/prompt_utils.py`): „Replace Y with X“ plus Merkmale von X, bei mehreren Bildern
   genau, aus welchem Picture was kommt, Personen in ihren Kernmerkmalen (Gesicht, Alter, Frisur, Hautton, Kleidung …) festgehalten, ein „Keep … unchanged“ am Ende.
   Gemma erfindet nichts dazu; Unklares (z. B. ein Tippfehler) liest sie so, dass sich am wenigsten ändert, und meldet es orange („Gemma war sich nicht sicher“).
   Fehlt der Satz zur Identität, obwohl Personen zu sehen sind, ergänzt ihn die App. Darunter erklärt Gemma auf Deutsch, wie sie dich verstanden hat.
   Die App warnt, wenn der Prompt ein Bild nennt, das es nicht gibt, oder ein Moodboard mit Anweisung fehlt.
4. Prompt bearbeiten, „Nachbessern“ mit einer Korrektur oder „Prompt kopieren“. Die Checkliste „So richtest du Draw Things ein“ zeigt Reihenfolge,
   Format und Kopierknöpfe für jedes Bild (in Draw Things ⌘V); Bilder lassen sich auch direkt aus den Plätzen hinüberziehen.

- Links steht der **Verlauf** aller Prompts – ein Klick holt einen zurück.
- Laut Alibaba ist Qwen Image Edit auf ein bis drei Eingabebilder ausgelegt; mit Canvas und drei Moodboards weist Labs darauf hin.
- Bilder, Anweisungen, Prompt und Verlauf liegen **nur in der jeweiligen Bibliothek** unter `Katalog/Labs/` (`labs.json`, `slot-0.png` …) und überstehen einen Neustart.
  Jede Bibliothek hat ihren eigenen Labs-Stand und Verlauf; nichts davon liegt in Application Support oder den Einstellungen der App.
  Auch die Kopien, die beim Herausziehen eines Bildes entstehen, liegen in der Bibliothek (`Katalog/Labs/Ziehen/`) und werden beim Öffnen und Schließen der Bibliothek gelöscht.

## Bildbearbeitung mit Apples Frameworks (lokal)

- **Core Image:** Auto-Verbessern (wie der Zauberstab in Fotos), Weißabgleich-Pipette, Tonwertkurve, Licht/Farbe, Klarheit, Rauschreduzierung, Filter, Begradigen, 2× hochskalieren.
- **Farbkorrektur (RGB)** unter *Anpassen*: je ein Regler für Rot, Grün und Blau – nach links Cyan, Magenta, Gelb, nach rechts die Farbe selbst.
  Die Kanäle werden verstärkt bzw. abgeschwächt (ganz außen doppelt bzw. halb so stark) und so ausgeglichen, dass die Helligkeit gleich bleibt.
  Wie alle Regler um den Nullpunkt besonders fein (Potenzkurve), ⌥ = noch feiner, Doppelklick = zurücksetzen.
- **Vision:** Motiv bzw. Personen auswählen, Horizont automatisch ausrichten, Zuschnitt auf das Motiv (Saliency), Text erkennen.
- **Auswahl:** per Vision oder Pinsel/Radierer. Damit freistellen (transparentes PNG), Hintergrund weichzeichnen/entsättigen/einfärben – und Qwen-Bearbeitungen nur in der Auswahl übernehmen (die App setzt das Ergebnis per Maske ins Original, weil Draw Things über HTTP keine Masken annimmt).
- Kurzbefehle: ⌥⌘A Motiv auswählen, ⇧⌘I Auswahl umkehren, ⌘D Auswahl aufheben, ⌘K Zuschneiden.

## Formate

Die App kennt nur die Formate, die Draw Things selbst anbietet – in derselben Reihenfolge und mit denselben Größenstufen
(abgelesen aus Draw Things am 12.10.2026, Breite × Höhe in Pixeln):

| Format | Klein | Normal | Groß |
|---|---|---|---|
| 1:2 | 512 × 1024 | 704 × 1408 | 896 × 1792 |
| 2:3 | 512 × 768 | 768 × 1152 | 1024 × 1536 |
| 3:4 | 576 × 768 | 768 × 1024 | 960 × 1280 |
| 4:5 | 704 × 832 | 896 × 1152 | 1024 × 1280 |
| 1:1 | 768 × 768 | 1024 × 1024 | 1280 × 1280 |
| 5:4 | 832 × 704 | 1152 × 896 | 1280 × 1024 |
| 4:3 | 768 × 576 | 1024 × 768 | 1280 × 960 |
| 3:2 | 768 × 512 | 1152 × 768 | 1536 × 1024 |
| 2:1 | 1024 × 512 | 1408 × 704 | 1792 × 896 |
| 16:9 | 1024 × 576 | – | 1728 × 960 |
| 9:16 | 576 × 1024 | – | 960 × 1728 |

- 16:9 und 9:16 gibt es in Draw Things nicht als „Normal“ – wie dort nimmt die App dann „Klein“.
- Die Stufe wählst du unter dem Bild (Menü neben dem Format), beim Anlegen eines Bildes oder unter *Einstellungen › Generieren*. Sie gilt für alle Modi.
- **Jedes Bild geht in genau einer dieser Größen an Draw Things.** Größere Bilder werden vorher verkleinert, kleinere hochgerechnet;
  weicht das Seitenverhältnis ab, wird beschnitten (bei Hochformat eher unten, damit Köpfe drin bleiben).
- **Beim Bearbeiten** steht links der Abschnitt **Format**: „Auto“ (das Format, das dem Bild am nächsten kommt) oder ein festes Format, dazu Klein · Normal · Groß.
  Darunter steht, wie groß das Bild ist, was an Draw Things geht und ob verkleinert oder beschnitten wird. „Bild jetzt auf … bringen“ legt diese Fassung vorher als Version an.
  Unter dem Bild zeigt die Leiste dasselbe (z. B. „4032 × 3024 → 1024 × 768 px“), das Format-Menü dort ist in „Bearbeiten“ dasselbe Format.
  Ein neu geöffnetes Bild beginnt wieder mit „Auto“.
- Auch das Raster der Gesichtsreferenz hat eine dieser Größen – das Bild darin wird dafür kleiner (siehe *Charaktere*).

## Bilder im Prompt: „Picture 1, 2 …“

Alle Modi nennen die Eingabebilder im Prompt **„Picture 1“, „Picture 2“ …** – so beschriftet Qwen Image Edit sie selbst
(Alibabas Referenz-Pipeline übergibt „Picture 1: <Bild> Picture 2: <Bild> …“, ihr „Edit Prompt Enhancer“ schreibt ebenso).
Bis 12.10.2026 schrieb die App „Image 1“; ältere Prompts in Verlauf und Galerie bleiben unverändert.

## Draw-Things-HTTP-API – was getestet ist

- `POST /sdapi/v1/txt2img` und `/sdapi/v1/img2img`; die App sendet nur `prompt`, `width`, `height`, beim Bearbeiten `init_images` (optional `seed`, `model`).
- Unbekannte Felder lehnt Draw Things ab (`Unrecognized keys`). `mask` und `moodboard` gibt es über HTTP nicht.
- `init_images` muss exakt `width` × `height` haben – die App skaliert/beschneidet vorher auf das Draw-Things-Format (siehe *Formate*).
- Mehrere `init_images` werden angenommen, im Test aber nicht zuverlässig als Referenzen genutzt. Deshalb geht im Referenz-Modus nur Bild 1 an Draw Things, die anderen beschreibt Gemma im Prompt (in den Einstellungen umschaltbar).
- Über HTTP gibt es keinen Schrittfortschritt. Der Balken schätzt die Dauer aus dem letzten Durchlauf.
- LoRAs, Sampler und Schritte bleiben, wie sie in Draw Things eingestellt sind.

Ergebnisse landen automatisch in der geöffneten Bibliothek unter `<Datum>/` (Prompt in den PNG-Metadaten).
