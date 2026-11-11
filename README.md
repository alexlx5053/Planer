# Planer

Ein ruhiger Tagesplaner für den Mac: Termine, Aufgaben, Gewohnheiten und Stundenplan in einem Fenster. Alles bleibt auf dem eigenen Rechner – kein Konto, keine Cloud, keine Netzwerkverbindung.

*A calm day planner for macOS – appointments, tasks, habits and a class timetable. Fully local: no account, no cloud, no network access. The interface is in German.*

![Tagesansicht](docs/tag.png)

## Was er kann

- **Tag, Woche, Stundenplan** – drei Ansichten auf dieselben Einträge.
- **Termine, Aufgaben, Gewohnheiten** – mit Wiederholungen, Abhaken, Fortschrittsring und Serie.
- **Stundenplan** – Kurse mit Anfang und Ende, wöchentlich oder in geraden/ungeraden Kalenderwochen, begrenzt auf das Semester. Kurse werden nicht abgehakt und zählen in keine Kennzahl: Ein Vorlesungstag ist kein halb erledigter Tag.
- **Freie Zeit sehen** – beim Anlegen eines Termins zeigt ein Belegungsstreifen, was schon steht, und warnt bei Überschneidungen.
- **Aus Text anlegen** – eine Mail, Nachricht oder Liste einfügen; daraus werden Entwürfe für Termine und Aufgaben. Angelegt wird erst nach Bestätigung.
- **Menüleiste** – Tagesfortschritt und die nächsten Einträge, ohne das Fenster zu öffnen.
- **Notizen** – ein Zettel neben dem Kalender, an keinen Tag gebunden.
- **Feiertage** – gesetzliche Feiertage in Bayern.

| Stundenplan | Woche |
|---|---|
| ![Stundenplan](docs/stundenplan.png) | ![Woche](docs/woche.png) |

![Aus Text anlegen](docs/aus-text.png)

## Datenschutz

Der Planer ist so gebaut, dass es nichts gibt, was abfließen könnte.

- **Kein Netzwerk.** Im Quelltext steht kein einziger Netzwerkzugriff. Ein Prüfskript stellt das vor jedem Commit sicher (`Scripts/privacy_check.sh`).
- **Eine Datei, lokal.** Alles liegt in `~/Library/Application Support/Planer/dashboard.json` – lesbares JSON, das einem selbst gehört. Ordner und Dateien sind nur für den eigenen Benutzer lesbar (Rechte `700`/`600`).
- **Sicherungen.** Beim Start entsteht höchstens eine Tagessicherung, 14 Stände werden aufbewahrt. Eine beschädigte Datei wird beiseitegelegt statt überschrieben.
- **Texterkennung auf dem Gerät.** „Aus Text anlegen" nutzt, wenn vorhanden, das Sprachmodell von Apple, das auf dem Mac selbst läuft (Apple Intelligence, ab macOS 26). Der Text verlässt den Rechner nicht; es gibt keinen Schlüssel und keine Kosten. Ohne das Modell lesen feste Regeln den Text.
- **Das Modell rechnet nicht.** Datum, Uhrzeit und Dauer bestimmen immer die Regeln. Das Modell benennt nur – und was es nennt, wird gegen den Text geprüft, bevor es übernommen wird.
- **Keine Telemetrie, keine Absturzberichte, keine Aktualisierungsprüfung.**

Mehr dazu in [SECURITY.md](SECURITY.md).

## Bauen und installieren

Voraussetzungen: macOS 14 oder neuer und die Command Line Tools (`xcode-select --install`). Xcode wird nicht gebraucht.

```bash
./Scripts/install.sh
```

Das baut die App, signiert sie lokal und legt sie nach `/Applications/Planer.app`.

Nur bauen, ohne zu installieren:

```bash
./Scripts/build_app.sh
```

Tests:

```bash
./Scripts/test.sh
```

## Tastenkürzel

| Kürzel | Wirkung |
|---|---|
| ⌘N · ⌥⌘N · ⌃⌘N · ⇧⌘N | Neuer Termin · Aufgabe · Gewohnheit · Kurs |
| ⇧⌘V | Aus Text anlegen |
| ⌘1 · ⌘2 · ⌘3 | Tag · Woche · Stundenplan |
| ⌘← · ⌘→ | Zurück · weiter |
| ⌘T | Heute |
| ⇧⌘M · ⇧⌘L · ⇧⌘J | Monatsübersicht · alle Termine · Notizen |
| ⌘F | Suchen |
| ⌘Z | Löschen widerrufen |

## Aufbau

```
Sources/
  PlanerCore/     Reine Logik ohne Oberfläche: Modell, Wiederholungen, Statistik,
                  Stundenplan, Textleser. Vollständig durch Tests abgedeckt.
  PlanerData/     Speichern, Sicherungen, Zwischenspeicher.
  Planer/         Die App (SwiftUI).
  PlanerWidget/   Widget für den Schreibtisch (siehe unten).
Tests/            Über 230 Tests (Swift Testing).
Scripts/          Bauen, Installieren, Testen, Datenschutz-Prüfung.
```

Das Projekt ist ein reines Swift-Paket und wird ohne Xcode-Projekt gebaut; das App-Bundle setzt `Scripts/build_app.sh` zusammen.

## Bekannte Grenzen

- **Widget.** Der Code ist vollständig, macOS zeigt Widgets aber nur aus Apps mit einem Entwicklerzertifikat von Apple an. Mit lokaler Signatur bleibt es unsichtbar.
- **Keine Sandbox.** Die App ist lokal signiert und läuft ohne Sandbox. Sie greift ausschließlich auf ihren eigenen Datenordner zu.
- **Oberfläche nur auf Deutsch**, Feiertage nur für Bayern.
- **Kein Abgleich** zwischen Geräten – das ist Absicht, nicht Versäumnis.

## Mitmachen

Nach dem Klonen einmal die Git-Haken einrichten:

```bash
./Scripts/install_hooks.sh
```

Sie prüfen vor jedem Commit und Push, dass keine persönlichen Daten, Pfade oder Mail-Adressen im Repository landen und dass der Quelltext netzwerkfrei bleibt.

## Lizenz

[MIT](LICENSE)
