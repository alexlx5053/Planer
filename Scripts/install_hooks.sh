#!/bin/bash
# Richtet die Git-Haken ein, die vor jedem Commit und jedem Push pruefen, dass
# nichts Persoenliches hinausgeht.
#
#   ./Scripts/install_hooks.sh
#
# Haken liegen in .git/hooks und werden von Git nicht mitkopiert. Wer das
# Repository frisch klont, fuehrt dieses Skript deshalb einmal aus.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Hier ist kein Git-Repository." >&2
    exit 1
}

HOOKS="$(git rev-parse --git-path hooks)"
mkdir -p "$HOOKS"

write_hook() {
    cat > "$HOOKS/$1" <<'HOOK'
#!/bin/bash
# Von Scripts/install_hooks.sh angelegt.
ROOT="$(git rev-parse --show-toplevel)"

# Die Adresse im Commit ist oeffentlich und laesst sich nachtraeglich nur durch
# Umschreiben der Geschichte entfernen. Erlaubt ist deshalb allein die anonyme
# Adresse von GitHub.
EMAIL="$(git config user.email || true)"
case "$EMAIL" in
    *@users.noreply.github.com) ;;
    *)
        echo "Abgebrochen: Als Absender ist keine anonyme GitHub-Adresse gesetzt." >&2
        echo "  git config user.email \"<nummer>+<konto>@users.noreply.github.com\"" >&2
        exit 1 ;;
esac

exec "$ROOT/Scripts/privacy_check.sh"
HOOK
    chmod +x "$HOOKS/$1"
    echo "eingerichtet: $1"
}

write_hook pre-commit
write_hook pre-push
