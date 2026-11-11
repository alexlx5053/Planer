#!/bin/bash
# Prueft, dass nichts Persoenliches im Repository steht.
#
#   ./Scripts/privacy_check.sh          prueft alles, was Git veroeffentlichen wuerde
#
# Laeuft automatisch vor jedem Commit und vor jedem Push, sobald die Haken mit
# ./Scripts/install_hooks.sh eingerichtet sind. Schlaegt eine Pruefung an, bricht
# der Commit ab - es geht nichts hinaus, was hier haengen bleibt.
#
# Geprueft wird:
#   1. Pfade ins Benutzerverzeichnis        (verraten den Kontonamen des Rechners)
#   2. Mail-Adressen
#   3. Datendateien des Planers             (dashboard*.json, Sicherungen)
#   4. Netzwerkzugriffe im Quelltext        (die App verspricht, keine zu machen)
#   5. eigene Sperrwoerter                  (.privacy.local, eine Zeile je Muster)
#   6. Eintraege aus dem eigenen Bestand    (Titel, Raeume, Notizen - damit kein
#                                            echter Termin als Testbeispiel endet)
#
# Die Datei .privacy.local wird nie eingecheckt. Dort stehen die Woerter, die
# auf einen selbst zurueckfuehren - Nachname, Kontoname, Mail - und die deshalb
# gerade nicht in einem oeffentlichen Skript stehen duerfen.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() { printf '  ✘ %s\n' "$1"; FAILED=1; }
ok()   { printf '  ✔ %s\n' "$1"; }

# Was Git veroeffentlichen wuerde: Eingechecktes und Vorgemerktes. Ausserhalb
# eines Repositorys alles, was nicht ignoriert waere.
list_files() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        { git ls-files; git ls-files --others --exclude-standard; } | sort -u
    else
        find . -type f -not -path './.build/*' -not -path './.git/*' -not -name '.DS_Store' \
            -not -name '*.local' | sed 's|^\./||'
    fi
}

# Nur Textdateien durchsuchen - in einem Bild steht kein Nachname.
TEXT_FILES=()
ALL_FILES=()
while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    ALL_FILES+=("$file")
    case "$file" in
        *.swift|*.sh|*.md|*.plist|*.entitlements|*.json|*.yml|*.yaml|*.txt|.gitignore|LICENSE)
            TEXT_FILES+=("$file") ;;
    esac
done < <(list_files)

echo "Datenschutz-Pruefung: ${#ALL_FILES[@]} Dateien"

# Dieses Skript nennt die Muster selbst und nimmt sich deshalb aus.
SELF="Scripts/privacy_check.sh"

search() { # search <muster> -> Fundstellen
    local pattern="$1" file
    for file in "${TEXT_FILES[@]}"; do
        [[ "$file" == "$SELF" ]] && continue
        grep -nIiE -- "$pattern" "$file" 2>/dev/null | sed "s|^|$file:|" | cut -c1-140
    done
}

# 1. Pfade ins Benutzerverzeichnis
hits="$(search '/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/')"
if [[ -n "$hits" ]]; then fail "Pfad in ein Benutzerverzeichnis:"; echo "$hits" | sed 's/^/      /'
else ok "keine Pfade in ein Benutzerverzeichnis"; fi

# 2. Mail-Adressen. Ausgenommen: die anonymen Adressen von GitHub - sie sind dafuer
#    da, oeffentlich zu sein - und Bildnamen wie icon@2x.png.
hits="$(search '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | grep -viE 'noreply\.github\.com|noreply@anthropic\.com|@[0-9]x\.(png|jpg|pdf)')"
if [[ -n "$hits" ]]; then fail "Mail-Adresse:"; echo "$hits" | sed 's/^/      /'
else ok "keine Mail-Adressen"; fi

# 3. Datendateien
hits=""
for file in "${ALL_FILES[@]}"; do
    case "$(basename "$file")" in
        dashboard*.json|Planer\ *.json) hits+="$file"$'\n' ;;
    esac
    [[ "$file" == *Backups/* ]] && hits+="$file"$'\n'
done
if [[ -n "$hits" ]]; then fail "Datendatei des Planers:"; printf '%s' "$hits" | sed 's/^/      /'
else ok "keine Datendateien"; fi

# 4. Netzwerkzugriffe - nur im Quelltext der App
hits=""
for file in "${TEXT_FILES[@]}"; do
    [[ "$file" == Sources/* ]] || continue
    found="$(grep -nE 'URLSession|URLRequest|NWConnection|NWListener|WKWebView|CFNetwork|CloudKit|NSUbiquit|import Network' "$file" 2>/dev/null)"
    [[ -n "$found" ]] && hits+="$(echo "$found" | sed "s|^|$file:|" | cut -c1-140)"$'\n'
done
if [[ -n "$hits" ]]; then fail "Netzwerkzugriff im Quelltext:"; printf '%s' "$hits" | sed 's/^/      /'
else ok "kein Netzwerkzugriff im Quelltext"; fi

# 5. Eigene Sperrwoerter
if [[ -f .privacy.local ]]; then
    hits=""
    count=0
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        count=$((count + 1))
        found="$(search "$pattern")"
        [[ -n "$found" ]] && hits+="$found"$'\n'
    done < .privacy.local
    if [[ -n "$hits" ]]; then fail "Sperrwort aus .privacy.local:"; printf '%s' "$hits" | sed 's/^/      /'
    else ok "keines der $count eigenen Sperrwoerter"; fi
else
    echo "  – keine .privacy.local (eigene Sperrwoerter nicht geprueft)"
fi

# 6. Eintraege aus dem eigenen Bestand
DATA="$HOME/Library/Application Support/Planer/dashboard.json"
if [[ -f "$DATA" ]] && command -v python3 >/dev/null 2>&1; then
    result="$(python3 - "$DATA" "${TEXT_FILES[@]}" <<'PY'
import json, sys

data_path, files = sys.argv[1], sys.argv[2:]
try:
    state = json.load(open(data_path, encoding="utf-8"))["state"]
except Exception:
    print("UNLESBAR")
    sys.exit(0)

def specific(value):
    """Nur, was auf den Besitzer zeigt: mehrere Woerter oder eine Ziffer.

    Ein einzelnes Alltagswort wie „Zahnarzt" steht in jedem Beispiel und
    verraet niemanden; „Seminar Raum 2.14" schon.
    """
    value = value.strip()
    return len(value) >= 6 and (" " in value or any(c.isdigit() for c in value))

terms = set()
for kind in ("events", "tasks", "habits", "courses"):
    for item in state.get(kind, []):
        for field in ("title", "room", "lecturer", "notes"):
            value = (item.get(field) or "").strip()
            for line in value.splitlines():
                if specific(line):
                    terms.add(line.strip().lower())
for line in (state.get("notes") or "").splitlines():
    if specific(line):
        terms.add(line.strip().lower())

# Zeitfenster der Kurse: Auch ohne Namen zeigen sie, wann jemand wo ist.
slots = set()
for course in state.get("courses", []):
    start, end = course.get("start"), course.get("end")
    if start and end:
        slots.add(f"{start}–{end}")
        slots.add(f"{start}-{end}")

hits = []
for path in files:
    if path == "Scripts/privacy_check.sh":
        continue
    try:
        text = open(path, encoding="utf-8").read()
    except Exception:
        continue
    lowered = text.lower()
    # Bewusst ohne den Treffer selbst auszugeben: Die Meldung landet
    # womoeglich in einem Protokoll, und dort hat der Eintrag nichts verloren.
    if any(term in lowered for term in terms):
        hits.append(f"{path}: enthält einen Eintrag aus deinem Bestand")
    if any(slot in text for slot in slots):
        hits.append(f"{path}: enthält das Zeitfenster eines deiner Kurse")

print(f"ANZAHL {len(terms)} {len(slots) // 2}")
for hit in sorted(set(hits)):
    print(hit)
PY
)"
    summary="$(echo "$result" | head -1)"
    details="$(echo "$result" | tail -n +2)"
    if [[ "$summary" == "UNLESBAR" ]]; then
        echo "  – eigener Bestand nicht lesbar (Abgleich uebersprungen)"
    elif [[ -n "$details" ]]; then
        fail "Eintrag aus dem eigenen Bestand:"; echo "$details" | sed 's/^/      /'
    else
        read -r _ terms slots <<<"$summary"
        ok "keiner der $terms eigenen Eintraege und keines der $slots Kurs-Zeitfenster"
    fi
else
    echo "  – kein eigener Bestand auf diesem Rechner (Abgleich uebersprungen)"
fi

echo
if [[ "$FAILED" -ne 0 ]]; then
    echo "Nicht veroeffentlichen: Es steht etwas Persoenliches im Repository."
    exit 1
fi
echo "Sauber."
