#!/bin/bash
# Zieht Bilder der Oberflaeche.
#   ./Scripts/snapshot.sh <zielordner> [--view name] [--size BxH]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_CACHE="${TMPDIR:-/tmp}planer-bau"
mkdir -p "$BUILD_CACHE"

source "$ROOT/Scripts/sdk.sh"
select_sdk

TARGET="${1:?Zielordner fehlt}"
shift

swift build --scratch-path "$BUILD_CACHE" >/dev/null
BIN="$(swift build --scratch-path "$BUILD_CACHE" --show-bin-path)/Planer"

rm -rf "$TARGET"
"$BIN" --snapshot "$TARGET" "$@"
