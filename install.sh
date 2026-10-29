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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}.$")" 2>/dev/null && pwd || pwd)"
if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "." ]; then
    SCRIPT_DIR="/var/www/pwa-anwesenheitsliste"
fi
APP_DIR="/var/www/pwa-anwesenheitsliste"

echo "== 1. Verschiebe Projekt nach $APP_DIR == "
if [ "$SCRIPT_DIR" != "$APP_DIR" ]; then
    mkdir -p /var/www
    rm -rf "$APP_DIR"
    cp -r "$SCRIPT_DIR" "$APP_DIR"
fi

echo "== 2. Starte vserver-setup.sh für $DOMAIN ==="
bash "$APP_DIR/deploy/vserver-setup.sh" "$DOMAIN" "$EMAIL"

echo ""
echo "🚀 Installation erfolgreich abgeschlossen!"
echo "🌐 URL: https://$DOMAIN"
