#!/bin/bash
# Zieht Bilder der Oberflaeche.
#   ./Scripts/snapshot.sh <zielordner> [--view name] [--size BxH]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_ROOT="${TMPDIR:-/tmp}"
BUILD_CACHE="${TMP_ROOT%/}/planer-bau"
mkdir -p "$BUILD_CACHE"

source "$ROOT/Scripts/sdk.sh"
select_sdk

TARGET="${1:?Zielordner fehlt}"
shift

swift build --scratch-path "$BUILD_CACHE" >/dev/null
BIN="$(swift build --scratch-path "$BUILD_CACHE" --show-bin-path)/Planer"

# Nur alte Bilder ersetzen, nie einen Ordner mit anderem Inhalt leeren:
# Ein vertippter Zielordner wie "." oder "docs" darf nichts loeschen.
if [[ -e "$TARGET" ]]; then
    [[ -d "$TARGET" ]] || { echo "Kein Ordner: $TARGET" >&2; exit 1; }
    if find "$TARGET" -mindepth 1 \( -type d -o \( -type f -not -name '*.png' \) \) -print -quit | grep -q .; then
        echo "Abbruch: $TARGET enthaelt mehr als Bilder. Bitte einen leeren oder neuen Ordner angeben." >&2
        exit 1
    fi
    find "$TARGET" -mindepth 1 -maxdepth 1 -type f -name '*.png' -delete
fi
"$BIN" --snapshot "$TARGET" "$@"
