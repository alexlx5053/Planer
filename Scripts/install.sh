#!/bin/bash
# Baut die App und legt sie in /Applications ab.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP_ROOT="${TMPDIR:-/tmp}"
STAGE="${TMP_ROOT%/}/planer-build"
TARGET="/Applications/Planer.app"

# „Planer" ist ein gaengiger Name. Liegt dort eine andere App, wird sie nicht
# ueberschrieben - geprueft wird die Kennung, nicht der Name.
PLISTBUDDY=/usr/libexec/PlistBuddy
OWN_ID="$("$PLISTBUDDY" -c "Print :CFBundleIdentifier" "$ROOT/Resources/Info.plist")"
if [[ -e "$TARGET" ]]; then
    FOUND_ID="$("$PLISTBUDDY" -c "Print :CFBundleIdentifier" "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$FOUND_ID" != "$OWN_ID" ]]; then
        echo "Abbruch: $TARGET gehoert zu einer anderen App (${FOUND_ID:-ohne Kennung}). Bitte selbst entfernen oder umbenennen." >&2
        exit 1
    fi
fi

"$ROOT/Scripts/build_app.sh" "$@"

echo "==> Installiere nach $TARGET"
rm -rf "$TARGET"
cp -R "$STAGE/Planer.app" "$TARGET"

# Das Zwischenverzeichnis wieder raeumen.
#
# Sonst bleibt neben der installierten App eine zweite, gleich benannte Kopie
# liegen - Spotlight und das Launchpad zeigen dann mehrere „Planer" an, und man
# weiss nicht mehr, welcher der echte ist.
rm -rf "$STAGE"

# Launch Services den neuen Stand mitteilen, sonst bleibt ein altes Icon haengen.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$TARGET" 2>/dev/null || true

echo "==> Fertig. Start mit: open '$TARGET'"
