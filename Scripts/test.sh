#!/bin/bash
# Fuehrt die Testsuite aus.
#
# Ohne Xcode liegt Swift Testing zwar in den Command Line Tools, aber ausserhalb
# der Standard-Suchpfade - deshalb die zusaetzlichen Framework- und rpath-Angaben.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Auch das Bauverzeichnis liegt ausserhalb des Projekts.
#
# Aus demselben Grund wie das App-Bundle: Der Projektordner liegt unter
# ~/Documents und bekommt vom System laufend erweiterte Attribute angehaengt.
# `codesign` - das SwiftPM auch fuer Test-Bundles aufruft - lehnt die ab.
TMP_ROOT="${TMPDIR:-/tmp}"
BUILD_CACHE="${TMP_ROOT%/}/planer-bau"
mkdir -p "$BUILD_CACHE"

source "$ROOT/Scripts/sdk.sh"
select_sdk

FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
INTEROP="$(xcode-select -p)/Library/Developer/usr/lib"

# Das Makro-Plugin von Swift Testing liegt in einem Unterordner, den der
# Uebersetzer nur findet, wenn das Standard-SDK benutzt wird. Sobald wir auf ein
# anderes SDK ausweichen, muss der Pfad ausdruecklich mitgegeben werden.
TESTING_PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"

swift test \
  --scratch-path "$BUILD_CACHE" \
  -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS" \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$INTEROP" \
  "$@"
