# Sicherheit und Datenschutz

## Was der Planer zusichert

| Zusage | Wie sie eingehalten wird |
|---|---|
| Keine Netzwerkverbindung | Im Quelltext der App steht kein Netzwerkzugriff. `Scripts/privacy_check.sh` sucht vor jedem Commit nach `URLSession`, `URLRequest`, `NWConnection`, `WKWebView`, CloudKit und Verwandten und bricht ab, wenn etwas davon auftaucht. |
| Daten bleiben auf dem Gerät | Einziger Speicherort ist `~/Library/Application Support/Planer/`. Es gibt keinen Abgleich, keine Telemetrie, keine Absturzberichte, keine Aktualisierungsprüfung. |
| Nur der eigene Benutzer liest die Daten | Ordner werden mit `700`, Dateien mit `600` angelegt. Die Rechte werden bei jedem Speichern und bei jedem Start neu gesetzt, auch für Sicherungen und exportierte Kopien. |
| Kein Datenverlust durch Fehler | Geschrieben wird atomar. Beim Start entsteht eine Tagessicherung (14 Stände). Eine unlesbare Datei wird beiseitegelegt, nicht überschrieben; die App lädt dann die jüngste lesbare Sicherung. |
| Texterkennung ohne Dritte | „Aus Text anlegen" verwendet ausschließlich das auf dem Mac laufende Sprachmodell von Apple oder, wenn es fehlt, feste Regeln. Kein Text wird übertragen. |

## Umgang mit fremden Eingaben

Zwei Stellen nehmen Inhalte von außen entgegen:

- **Eingefügter Text** („Aus Text anlegen"). Er wird gelesen, nie ausgeführt. Die Länge ist begrenzt. Was das Sprachmodell zurückgibt, wird nur als JSON gelesen und gegen den eingefügten Text geprüft: Ein Eintrag, dessen Titel dort nicht vorkommt, wird verworfen, und das Modell kann weder ein Datum setzen noch eines verschieben. Nichts wird ohne Bestätigung angelegt.
- **Zurückgespielte Sicherung** (Einstellungen → „Zurückspielen"). Die Datei wird nur als JSON in das feste Datenmodell gelesen; unbekannte Felder werden übergangen, übergroße Dateien abgelehnt. Vor dem Ersetzen entsteht immer eine eigene Kopie des bisherigen Stands mit Uhrzeit (`Backups/dashboard-vor-import-…`, die letzten 10 bleiben), unabhängig von der Tagessicherung. Gelingt diese Kopie nicht, wird nichts ersetzt.

## Was die App nicht leistet

- **Keine Verschlüsselung der Datendatei.** Sie ist durch die Dateirechte und, sofern eingeschaltet, durch FileVault geschützt. Wer Zugriff auf das angemeldete Benutzerkonto hat, kann sie lesen. FileVault einzuschalten wird empfohlen.
- **Keine Sandbox.** Die App ist lokal (ad hoc) signiert. Sie liest und schreibt nur in ihrem Datenordner und an Orten, die man beim Sichern oder Zurückspielen selbst auswählt.
- **Backups des Systems.** Time Machine und andere Sicherungsprogramme erfassen den Datenordner wie jeden anderen. Was dort landet, liegt außerhalb der Reichweite der App.

## Eine Schwachstelle melden

Bitte über die Funktion **„Report a vulnerability"** im Reiter *Security* dieses Repositorys (private Meldung an die Betreuer). Für alles, was keine Sicherheitslücke ist, genügt ein gewöhnliches Issue.

Bitte keine echten Daten in Issues oder Pull Requests einfügen – auch nicht als Beispiel. Erfundene Einträge reichen, um einen Fehler nachzustellen.
