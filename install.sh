#!/bin/bash
# install.sh - One-Click Setup für anwesenheitsliste.ministo.de
# Führt das gesamte V-Server Setup vollautomatisch aus.
# Aufruf: sudo bash install.sh [Domain] [Admin-Email]

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Bitte als root ausführen (sudo bash install.sh)." >&2
    exit 1
fi

DOMAIN="${1:-anwesenheitsliste.ministo.de}"
EMAIL="${2:-}"
APP_DIR="/var/www/pwa-anwesenheitsliste"
REPO_URL="git@github.com:son1x/pwa-anwesenheitsliste.git"
BRANCH="main"
DEPLOY_KEY="${DEPLOY_KEY:-/root/.ssh/pwa_anwesenheitsliste_deploy_key}"

echo "== 1. Deploy-Key erzeugen =="
if [ ! -f "$DEPLOY_KEY" ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    ssh-keygen -q -t ed25519 -f "$DEPLOY_KEY" -N "" -C "vserver-deploy-pwa-anwesenheitsliste"
fi
export GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

echo "== 2. Repository klonen nach $APP_DIR =="
mkdir -p /var/www
if [ ! -d "$APP_DIR/.git" ]; then
    rm -rf "$APP_DIR"
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
    git checkout "$BRANCH"
else
    cd "$APP_DIR"
    git fetch origin "$BRANCH"
    git reset -q --hard "origin/$BRANCH"
fi
chown -R root:www-data "$APP_DIR"
chmod -R u+rwX,go+rX,go-w "$APP_DIR"
mkdir -p "$APP_DIR/data"
chmod 775 "$APP_DIR/data"
chown -R www-data:www-data "$APP_DIR/data"
chmod 755 "$APP_DIR/deploy/vserver-pull.sh"

echo "== 3. Starte vserver-setup.sh für $DOMAIN ==="
bash "$APP_DIR/deploy/vserver-setup.sh" "$DOMAIN" "$EMAIL"

echo ""
echo "🚀 Installation erfolgreich abgeschlossen!"
echo "🌐 URL: https://$DOMAIN"