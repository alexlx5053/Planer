#!/bin/bash
# Baut Planer.app aus dem SwiftPM-Paket.
#   ./Scripts/build_app.sh            Release-Build nach build/
#   ./Scripts/build_app.sh --debug    schnellerer Debug-Build
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

CONFIG="release"
[[ "${1:-}" == "--debug" ]] && CONFIG="debug"

APP_NAME="Planer"
BUNDLE_ID="io.github.alexlx5053.planer"
EXECUTABLE="Planer"

# Das Bundle entsteht ausserhalb des Projektordners.
#
# Der Grund: Dateien im Projekt tragen erweiterte Attribute (Herkunftsangaben,
# Dateiprovider-Marker). `codesign` lehnt ein Bundle mit solchen Resten mit
# "resource fork ... not allowed" rundweg ab, und sie lassen sich nicht
# zuverlaessig entfernen, solange das System sie immer wieder anhaengt. Im
# temporaeren Verzeichnis entstehen sie gar nicht erst.
STAGE="${TMP_ROOT%/}/planer-build"
APP="$STAGE/$APP_NAME.app"

echo "==> Kompiliere ($CONFIG)"
swift build -c "$CONFIG" --scratch-path "$BUILD_CACHE"
BIN="$(swift build -c "$CONFIG" --scratch-path "$BUILD_CACHE" --show-bin-path)/$EXECUTABLE"
[[ -x "$BIN" ]] || { echo "Binary nicht gefunden: $BIN" >&2; exit 1; }

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "==> Erzeuge App-Icon"
  swift "$ROOT/Scripts/make_icon.swift" "$ROOT/Resources/AppIcon.icns"
fi

echo "==> Baue Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Widget-Erweiterung einbetten.
#
# Ein Widget ist ein eigenes Programm im Ordner PlugIns der App. Das System
# findet es dort und bietet es in der Widget-Uebersicht an.
WIDGET="$APP/Contents/PlugIns/PlanerWidget.appex"
WIDGET_BIN="$(swift build -c "$CONFIG" --scratch-path "$BUILD_CACHE" --show-bin-path)/PlanerWidget"
if [[ -x "$WIDGET_BIN" ]]; then
  echo "==> Bette Widget ein"
  mkdir -p "$WIDGET/Contents/MacOS"
  cp "$WIDGET_BIN" "$WIDGET/Contents/MacOS/PlanerWidget"
  cp "$ROOT/Resources/WidgetInfo.plist" "$WIDGET/Contents/Info.plist"

  # Ohne diese Angaben nimmt das System die Erweiterung nicht an - sie sind
  # sonst Teil dessen, was Xcode beim Bauen ergaenzt.
  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleSupportedPlatforms array" \
    -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" \
    -c "Add :DTPlatformName string macosx" \
    -c "Add :DTSDKName string macosx" \
    "$WIDGET/Contents/Info.plist" >/dev/null 2>&1 || true
fi

xattr -cr "$APP" 2>/dev/null || true

echo "==> Signiere (ad hoc)"
# Von innen nach aussen: Die aeussere Signatur versiegelt den Inhalt, also muss
# die Erweiterung vorher fertig signiert sein.
if [[ -d "$WIDGET" ]]; then
  codesign --force --sign - --identifier "io.github.alexlx5053.planer.widget" \
    --entitlements "$ROOT/Resources/Widget.entitlements" --timestamp=none "$WIDGET"
fi
codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --strict --deep "$APP"

echo "==> Fertig: $APP"
