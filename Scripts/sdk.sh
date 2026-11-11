#!/bin/bash
# Waehlt ein SDK, mit dem sich SwiftUI uebersetzen laesst, und setzt SDKROOT.
#
# Hintergrund: Ein SDK-Wechsel kann @State, @Environment und @Bindable zu Makros
# machen. Deren Umsetzung (libSwiftUIMacros.dylib) liefert Apple nur mit Xcode
# aus - ohne Xcode bricht der Bau dann mit
#   "plugin for module 'SwiftUIMacros' not found"
# ab, obwohl am Code nichts falsch ist. Genau das ist mit den Command Line Tools
# vom 11.09.2026 passiert.
#
# Statt eine SDK-Version fest einzutragen - die naechste Aktualisierung
# verschoebe sie wieder - wird einmal probeweise uebersetzt und das Ergebnis
# gemerkt. Liefert Apple das Plugin nach oder wird Xcode installiert, waehlt die
# Probe von selbst wieder das Standard-SDK.

select_sdk() {
    # Eine von aussen gesetzte Vorgabe hat Vorrang.
    [[ -n "${SDKROOT:-}" ]] && return 0

    local cache="${BUILD_CACHE:-$ROOT/.build}/sdk-auswahl"
    if [[ -f "$cache" ]]; then
        local cached
        cached="$(cat "$cache")"
        if [[ "$cached" == "standard" ]]; then return 0; fi
        if [[ -d "$cached" ]]; then export SDKROOT="$cached"; return 0; fi
    fi

    local probe_dir probe
    probe_dir="$(mktemp -d)"
    probe="$probe_dir/probe.swift"
    cat > "$probe" <<'PROBE'
import SwiftUI
struct Probe: View {
    @State private var value = 0
    var body: some View { Text("\(value)") }
}
PROBE

    mkdir -p "${BUILD_CACHE:-$ROOT/.build}"

    if swiftc -typecheck "$probe" >/dev/null 2>&1; then
        printf 'standard' > "$cache"
        rm -rf "$probe_dir"
        return 0
    fi

    local sdk
    for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -Vr); do
        if SDKROOT="$sdk" swiftc -typecheck "$probe" >/dev/null 2>&1; then
            export SDKROOT="$sdk"
            printf '%s' "$sdk" > "$cache"
            echo "==> SDK: $(basename "$sdk") — das Standard-SDK braucht ein Xcode-Plugin, das hier fehlt"
            rm -rf "$probe_dir"
            return 0
        fi
    done

    rm -rf "$probe_dir"
    echo "Kein SDK gefunden, mit dem sich SwiftUI uebersetzen laesst." >&2
    return 1
}
