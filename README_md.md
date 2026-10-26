# Anwesenheitsliste – Vorlage

Browser-Werkzeug, das eine Kinderliste pflegt und daraus eine druckfertige
A4-Anwesenheitsliste als PDF erzeugt. Ursprung: Werkzeug „Anwesenheitsliste“
der Gruppe 7 Werkstatt (Repo `son1x/kita-picturemod`, Ordner
`anwesenheitsliste/`, Stand Commit `e40a2ac`).

Eine einzige `index.html` mit Vanilla JS: kein Build-Schritt, kein Backend, keine
Datenbank.

## Inhalt

```
anwesenheitsliste-vorlage/
├── index.html        Das komplette Werkzeug (HTML, CSS, JS)
├── fonts/
│   ├── Carlito-Regular.ttf
│   ├── Carlito-Bold.ttf
│   ├── Carlito-BoldItalic.ttf
│   └── OFL.txt       Lizenz der Schrift – muss beiliegen
└── README.md         Diese Datei
```

## Funktionen

- Bis zu 25 Kinder, immer alphabetisch nach Vornamen sortiert (`Intl.Collator("de")`).
- Pro Kind ein Kürzel (TK, RK oder keins) und drei Spalten A, F, M. Jedes Feld
  wird entweder blau gefüllt oder leer (zum Ankreuzen) gedruckt.
- RK/TK und Spalte M sind gekoppelt: RK = M blau, TK = M leer. Ändert man
  eines, ändert sich das andere mit.
- Gruppenname als Feld (Standard „Gruppe 7“), steht oben rechts im PDF.
- Mehrere Kinder auf einmal einfügen (ein Kind pro Zeile, optional `TK `/`RK ` davor).
- PDF für einen Tag oder eine Woche (Mo–Fr, 5 Seiten). Das Datum bleibt
  standardmäßig leer (zum Eintragen von Hand).
- Unten rechts im PDF: „Stand: HH:MM Uhr – TT.MM.JJJJ“ (Erstellungszeit).
- Leere Zeilen werden leer gedruckt; es sind immer 25 Zeilen auf dem Blatt.

## Datenspeicherung

- Kinderliste und Gruppenname liegen nur im Browser (`localStorage`), also pro
  Gerät und Browser. Nichts davon geht an einen Server.
- „Liste als Datei speichern“ / „Liste aus Datei laden“ exportiert bzw.
  importiert eine JSON-Datei, als Sicherung oder für ein anderes Gerät:

```json
{
  "gruppe": "Gruppe 7",
  "kinder": [
    { "k": "RK", "name": "Mia Beispiel", "f": [false, false, true] },
    { "k": "TK", "name": "Ben Muster",   "f": [false, false, false] }
  ]
}
```

`k` = Kürzel (`"TK"`, `"RK"` oder `""`), `f` = Felder `[A, F, M]` (true = blau).

Achtung: Safari (iPad/iPhone) kann Website-Daten nach rund einer Woche ohne
Besuch löschen. Wer die Liste behalten will, speichert sie regelmäßig als Datei.

## Benutzen / Testen

Die Datei **nicht per Doppelklick** öffnen (`file://`): Dann blockiert der
Browser das Laden der Schriftdateien und das PDF fällt auf Helvetica zurück.
Stattdessen über einen Webserver, z. B.:

```bash
cd anwesenheitsliste-vorlage
python3 -m http.server 8000
# dann im Browser: http://localhost:8000/
```

Für den Betrieb reicht jeder statische Webspace (Apache, nginx, GitHub Pages …).
Der Ordner `fonts/` muss neben der `index.html` liegen.

Externe Abhängigkeiten (per CDN, Internet nötig):

- pdf-lib 1.17.1 – `cdnjs.cloudflare.com`
- @pdf-lib/fontkit 1.1.1 – `cdn.jsdelivr.net`
- Carlito-Webfont für die Bildschirmanzeige – Google Fonts

## Aufbau der `index.html`

| Zeilen ca. | Teil | Typische Anpassung |
|---|---|---|
| 1–270 | `<head>`, Styles | Farben in `:root` (Kita-CD: Blau `#003885`, Gelb `#FFD302`), `--fill` = Blau der gefüllten Felder |
| 270–365 | Seitenaufbau: Kopfleiste, Schritt 1 (Kinder), Schritt 2 (PDF), Fußzeile | Texte, Logo/Kopfleiste, Adresse im Footer |
| 366–425 | Konfiguration & Daten | siehe unten |
| 426–530 | Tabelle am Bildschirm, Kinder hinzufügen/entfernen | meist unverändert |
| 533–590 | `saveFile()`: Datei speichern, JSON-Export/-Import | unverändert nutzbar |
| 590–720 | PDF-Erzeugung (`buildPdf`) | Maße, Kopf- und Fußzeile |
| 720–Ende | Datum, Buttons, Start | – |

### Wichtige Stellschrauben

```js
var MAX_KIDS = 25;                          // Zeilen pro Blatt
var COLS = ["A", "F", "M"];                 // Spaltenköpfe
var STORAGE_KEY = "anwesenheitsliste_kinder_v1";
var GROUP_KEY   = "anwesenheitsliste_gruppe_v1";
var GROUP_DEFAULT = "Gruppe 7";

// PDF-Maße in mm (A4 = 210 × 297)
var LEFT = 16, RIGHT = 194;                 // Tabellenränder
var COL_W = [11, 56, 13, 13, 13];           // Kürzel, Name, A, F, M – Rest: Bemerkungen
var TABLE_TOP = 27, HEAD_H = 8.5, ROW_H = 9.4, FOOT_H = 10;
```

- **Mehr oder weniger Zeilen:** `MAX_KIDS` und `ROW_H` zusammen ändern, sodass
  `TABLE_TOP + HEAD_H + MAX_KIDS * ROW_H + FOOT_H` unter ca. 285 mm bleibt.
- **Andere Spalten:** `COLS` und `COL_W` anpassen. Außerdem muss das Feld-Array `f`
  in `sanitize()`, `addKid()` und `render()` die gleiche Länge haben.
- **Kopplung RK ↔ M:** steckt in `linkFromKuerzel()` / `linkFromM()` sowie in
  `sanitize()` (gleicht gespeicherte Listen beim Laden an). Für ein Projekt ohne
  diese Regel: die beiden Aufrufe entfernen und in `sanitize()` einfach `!!f[2]` nehmen.

## Stolperfallen

1. **Speicher-Schlüssel ändern.** Laufen zwei Projekte auf derselben Domain,
   teilen sie sich sonst die gespeicherte Liste. Also `STORAGE_KEY` und `GROUP_KEY`
   umbenennen.
2. **`FONT_OPTS` nicht ändern:**
   `{ subset: false, features: { liga: false, clig: false, dlig: false } }`.
   - Mit `subset: true` fehlen im PDF Buchstaben (pdf-lib-Fehler mit Carlito).
   - Mit Ligaturen wird z. B. „ti“ in „Zlatina“ falsch gesetzt.
   - Folge: Ein PDF ist ca. 0,9 MB groß, weil die Schrift komplett eingebettet wird.
3. **Schriftlizenz.** Carlito steht unter der SIL Open Font License 1.1.
   - Die TTF-Dateien unverändert lassen (kein Subsetting, keine Umbenennung).
   - `OFL.txt` muss beiliegen.
   - Die erzeugten PDFs selbst sind frei.
4. **Fallback ohne Schrift.** Fehlen die Schriftdateien, entsteht trotzdem ein
   PDF, dann in Helvetica.
5. **Datenschutz.** Keine echten Kindernamen fest in den Code schreiben, wenn
   die Seite öffentlich erreichbar ist. Die Namen gehören nur in den
   Browser-Speicher bzw. die Export-Datei.

## Speichern von Dateien

`saveFile()` nutzt zuerst die Download-Funktion von claude.ai-Artifacts
(`window.claude.use("downloads")`), falls vorhanden. Sonst lädt es klassisch über
einen `<a download>`-Link herunter. Auf einer normalen Webseite greift immer
der zweite Weg. Der erste Block kann bleiben oder entfernt werden.
