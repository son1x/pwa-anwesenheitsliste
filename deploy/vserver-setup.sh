#!/bin/bash
# vserver-setup.sh - Richtet die PWA anwesenheitsliste.ministo.de auf dem vServer ein.
# Idempotent: kann beliebig oft laufen.
#
#   Apache (TLS, anwesenheitsliste.ministo.de)
#     └─ Docroot: /var/www/pwa-anwesenheitsliste (PHP + SQLite)
#
# Nutzung (als root):
#   sudo bash vserver-setup.sh [domain] [email-fuer-letsencrypt]

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Bitte als root ausführen (sudo bash vserver-setup.sh ...)." >&2
    exit 1
fi

DOMAIN="${1:-anwesenheitsliste.ministo.de}"
ADMIN_EMAIL="${2:-}"
APP_DIR="/var/www/pwa-anwesenheitsliste"
SITE="/etc/apache2/sites-available/anwesenheitsliste.conf"
SITE_SSL="/etc/apache2/sites-available/anwesenheitsliste-ssl.conf"
ACME_DIR="/var/www/letsencrypt"
REPO_URL="${REPO_URL:-git@github.com:son1x/pwa-anwesenheitsliste.git}"
BRANCH="${BRANCH:-main}"
DEPLOY_KEY="${DEPLOY_KEY:-/root/.ssh/pwa_anwesenheitsliste_deploy_key}"
CF_CREDENTIALS="${CF_CREDENTIALS:-/root/.secrets/cloudflare.ini}"
DEPLOY_LOG="/var/log/pwa-anwesenheitsliste-deploy.log"

export DEBIAN_FRONTEND=noninteractive

main() {

echo "== Pakete (Apache, certbot, git, PHP) =="
apt-get update -y
apt-get install -y apache2 certbot openssl curl git ca-certificates openssh-client php libapache2-mod-php php-sqlite3

echo "== Deploy-Key =="
if [ ! -f "$DEPLOY_KEY" ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    ssh-keygen -q -t ed25519 -f "$DEPLOY_KEY" -N "" -C "vserver-deploy-pwa-anwesenheitsliste"
fi
export GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

echo "== Code holen ($BRANCH) nach $APP_DIR =="
mkdir -p "$APP_DIR"
cd "$APP_DIR"
[ -d .git ] || { git init -q; git remote add origin "$REPO_URL"; }
git remote set-url origin "$REPO_URL"
if ! git fetch -q origin "$BRANCH"; then
    echo "" >&2
    echo "!! GitHub-Zugriff fehlgeschlagen. Public Key eintragen:" >&2
    cat "${DEPLOY_KEY}.pub" >&2
    exit 1
fi
git reset -q --hard "origin/$BRANCH"
chown -R root:www-data "$APP_DIR"
chmod -R u+rwX,go+rX,go-w "$APP_DIR"
mkdir -p "$APP_DIR/data"
chmod 775 "$APP_DIR/data"
chown -R www-data:www-data "$APP_DIR/data"
chmod 755 "$APP_DIR/deploy/vserver-pull.sh"
"$APP_DIR/deploy/vserver-pull.sh" --nur-version

echo "== Apache-Module =="
a2enmod -q proxy proxy_http headers ssl rewrite alias php*

RENDERN="$APP_DIR/deploy/apache/rendern.sh"
mkdir -p "$ACME_DIR"

echo "== Apache: Port 80 =="
bash "$RENDERN" "$APP_DIR/deploy/apache/anwesenheitsliste.conf.in" DOMAIN="$DOMAIN" HTTP_PORT=80 ACME_DIR="$ACME_DIR" > "$SITE.neu"
mv "$SITE.neu" "$SITE"
a2ensite -q anwesenheitsliste
apache2ctl configtest
systemctl reload apache2

echo "== TLS-Zertifikat (Let's Encrypt) =="
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    EMAIL_ARG=(--register-unsafely-without-email)
    [ -n "$ADMIN_EMAIL" ] && EMAIL_ARG=(-m "$ADMIN_EMAIL")
    certbot certonly --webroot -w "$ACME_DIR" -d "$DOMAIN" --agree-tos -n \
        --deploy-hook "systemctl reload apache2" "${EMAIL_ARG[@]}"
fi

SSL_OPTS=""
[ -f /etc/letsencrypt/options-ssl-apache.conf ] && SSL_OPTS="Include /etc/letsencrypt/options-ssl-apache.conf"

echo "== Apache: Port 443 (HTTPS) =="
bash "$RENDERN" "$APP_DIR/deploy/apache/anwesenheitsliste-ssl.conf.in" \
    DOMAIN="$DOMAIN" HTTPS_PORT=443 DOCROOT="$APP_DIR" \
    CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem" CERT_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
    SSL_OPTS="$SSL_OPTS" LOG_DIR='${APACHE_LOG_DIR}' > "$SITE_SSL.neu"
mv "$SITE_SSL.neu" "$SITE_SSL"
a2ensite -q anwesenheitsliste-ssl
apache2ctl configtest
systemctl reload apache2

echo "== Cronjob: alle 5 Minuten Updates holen =="
touch "$DEPLOY_LOG"
chmod 640 "$DEPLOY_LOG"
cp "$APP_DIR/deploy/cron.d-pwa-anwesenheitsliste" /etc/cron.d/pwa-anwesenheitsliste
chmod 644 /etc/cron.d/pwa-anwesenheitsliste

echo ""
echo "== Fertig: https://$DOMAIN =="
}

main "$@"