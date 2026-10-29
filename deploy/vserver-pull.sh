#!/bin/bash
# vserver-pull.sh - Pull-Deployment für anwesenheitsliste.ministo.de
# Läuft per Cron alle 5 Minuten als root
# (/etc/cron.d/pwa-anwesenheitsliste, eingerichtet von deploy/vserver-setup.sh).
#
# Holt Branch main; bei neuem Commit "git reset --hard", version.json neu
# schreiben und Apache neu laden. Keine npm-Abhängigkeiten - kein "npm ci" nötig.
#
# Code und Daten sind getrennt: die Datenbank liegt im Docroot/data/
# und wird hier nie berührt. Die Apache-Vorlage in deploy/apache/ wendet NUR
# das Setup-Skript an, nie dieses Skript.
#
#   vserver-pull.sh                 normaler Lauf (Cron)
#   vserver-pull.sh --nur-version   nur version.json schreiben (Setup)

set -euo pipefail

REPO_DIR="${REPO_DIR:-/var/www/pwa-anwesenheitsliste}"
BRANCH="${BRANCH:-main}"
DEPLOY_KEY="${DEPLOY_KEY:-/root/.ssh/pwa_anwesenheitsliste_deploy_key}"
LOG_FILE="${LOG_FILE:-/var/log/pwa-anwesenheitsliste-deploy.log}"
VERSION_FILE="$REPO_DIR/version.json"

export GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

version_schreiben() {
    local tmp="$VERSION_FILE.tmp"
    cat > "$tmp" <<EOF
{
  "commit": "$(git -C "$REPO_DIR" rev-parse --short HEAD)",
  "commitDate": "$(git -C "$REPO_DIR" log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M')",
  "deployedAt": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
    chmod 644 "$tmp"
    mv "$tmp" "$VERSION_FILE"
}

# Alles in einer Funktion: bash hat das Skript damit komplett gelesen, bevor
# "git reset --hard" diese Datei womöglich ersetzt.
main() {
    cd "$REPO_DIR" || { echo "REPO_DIR nicht gefunden: $REPO_DIR" >&2; exit 1; }

    if [ "${1:-}" = "--nur-version" ]; then
        version_schreiben
        return
    fi

    # Nicht zweimal gleichzeitig (Cron + Setup)
    exec 9>/run/pwa-anwesenheitsliste-pull.lock
    flock -n 9 || return 0

    # Log klein halten
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 5000 ]; then
        tail -n 2000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi

    if ! git fetch -q origin "$BRANCH" >> "$LOG_FILE" 2>&1; then
        log "git fetch fehlgeschlagen (Deploy-Key/Netz?)"
        exit 1
    fi

    local lokal remote
    lokal=$(git rev-parse HEAD)
    remote=$(git rev-parse "origin/$BRANCH")
    if [ "$lokal" != "$remote" ]; then
        log "Neue Version $remote gefunden, aktualisiere von $lokal ..."
        git reset -q --hard "origin/$BRANCH" >> "$LOG_FILE" 2>&1
        chmod -R u+rwX,go+rX,go-w "$REPO_DIR"
        version_schreiben
        systemctl reload apache2 >> "$LOG_FILE" 2>&1 || log "Reload von apache2 fehlgeschlagen (systemctl reload apache2)"
        log "Deploy abgeschlossen: $(git rev-parse --short HEAD)"
    elif [ ! -f "$VERSION_FILE" ]; then
        version_schreiben
    fi
}

main "$@"