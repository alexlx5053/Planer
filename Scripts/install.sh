#!/bin/bash
# Baut die App und legt sie in /Applications ab.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/Scripts/build_app.sh" "$@"

STAGE="${TMPDIR:-/tmp}planer-build"
TARGET="/Applications/Planer.app"

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
