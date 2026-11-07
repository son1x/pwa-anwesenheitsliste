#!/bin/bash
# install.sh - One-Click Setup für anwesenheitsliste.ministo.de
# Holt das Repo nach /var/www/pwa-anwesenheitsliste und startet dann
# deploy/vserver-setup.sh. Funktioniert auch per Pipe (curl ... | sudo bash).
#
# Aufruf: sudo bash install.sh [Domain] [Admin-Email]
#
# Beim ersten Lauf wird ein Deploy-Key erzeugt und ausgegeben: diesen bei
# GitHub als Deploy Key (read-only) eintragen und install.sh erneut starten.
#
# Bestehende Daten werden nie gelöscht (kein rm -rf; die Datenbank liegt in
# /var/lib/pwa-anwesenheitsliste).

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Bitte als root ausführen (sudo bash install.sh)." >&2
    exit 1
fi

DOMAIN="${1:-anwesenheitsliste.ministo.de}"
EMAIL="${2:-}"
APP_DIR="/var/www/pwa-anwesenheitsliste"
REPO_URL="${REPO_URL:-git@github.com:son1x/pwa-anwesenheitsliste.git}"
BRANCH="${BRANCH:-main}"
DEPLOY_KEY="${DEPLOY_KEY:-/root/.ssh/pwa_anwesenheitsliste_deploy_key}"

main() {
    echo "== 1. Pakete für den Checkout (git, ssh) =="
    if ! command -v git >/dev/null 2>&1 || ! command -v ssh >/dev/null 2>&1; then
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y git openssh-client ca-certificates
    fi

    echo "== 2. Deploy-Key =="
    if [ ! -f "$DEPLOY_KEY" ]; then
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        ssh-keygen -q -t ed25519 -f "$DEPLOY_KEY" -N "" -C "vserver-deploy-pwa-anwesenheitsliste"
    fi
    export GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

    echo "== 3. Repository holen ($BRANCH) nach $APP_DIR =="
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    [ -d .git ] || { git init -q; git remote add origin "$REPO_URL"; }
    git remote set-url origin "$REPO_URL"
    if ! git fetch -q origin "$BRANCH"; then
        echo "" >&2
        echo "!! GitHub-Zugriff fehlgeschlagen. Diesen Public Key bei GitHub unter" >&2
        echo "!! son1x/pwa-anwesenheitsliste -> Settings -> Deploy keys (read-only) eintragen:" >&2
        echo "" >&2
        cat "${DEPLOY_KEY}.pub" >&2
        echo "" >&2
        echo "!! Danach install.sh einfach erneut ausführen." >&2
        exit 1
    fi
    git reset -q --hard "origin/$BRANCH"

    echo "== 4. Starte vserver-setup.sh für $DOMAIN =="
    REPO_URL="$REPO_URL" BRANCH="$BRANCH" DEPLOY_KEY="$DEPLOY_KEY" \
        bash "$APP_DIR/deploy/vserver-setup.sh" "$DOMAIN" "$EMAIL"

    echo ""
    echo "Installation abgeschlossen: https://$DOMAIN"
}

# In einer Funktion, damit bash bei "curl | bash" das ganze Skript gelesen hat.
main "$@"
