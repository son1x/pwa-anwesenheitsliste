#!/bin/bash
# vserver-setup.sh - Richtet die PWA anwesenheitsliste.ministo.de auf dem vServer ein.
# Idempotent: kann beliebig oft laufen (z.B. nachdem der Deploy-Key bei GitHub
# hinterlegt oder die Cloudflare-Credentials angelegt wurden).
#
#   Apache (TLS, anwesenheitsliste.ministo.de, mpm_event)
#     └─ Docroot: /var/www/pwa-anwesenheitsliste   (Git-Checkout, gehört root)
#          └─ *.php → PHP-FPM (User www-data)
#               ├─ Daten:  /var/lib/pwa-anwesenheitsliste   (SQLite, außerhalb des Docroots)
#               └─ Config: /etc/pwa-anwesenheitsliste.ini    (App-PIN, chmod 640)
#
# PHP läuft bewusst über PHP-FPM statt mod_php: mod_php erzwingt server-weit
# mpm_prefork und würde damit auch beller/gruppe7/portfolio umstellen.
#
# TLS wie bei den anderen Subdomains über Certbots Cloudflare-DNS-01-Plugin
# (/root/.secrets/cloudflare.ini). Fehlt die Datei, wird HTTP-01 (webroot)
# versucht - das klappt nur, wenn Port 80 direkt erreichbar ist.
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
DATA_DIR="/var/lib/pwa-anwesenheitsliste"
CONFIG="/etc/pwa-anwesenheitsliste.ini"
SITE="/etc/apache2/sites-available/anwesenheitsliste.conf"
SITE_SSL="/etc/apache2/sites-available/anwesenheitsliste-ssl.conf"
ACME_DIR="/var/www/letsencrypt"
REPO_URL="${REPO_URL:-git@github.com:son1x/pwa-anwesenheitsliste.git}"
BRANCH="${BRANCH:-main}"
DEPLOY_KEY="${DEPLOY_KEY:-/root/.ssh/pwa_anwesenheitsliste_deploy_key}"
CF_CREDENTIALS="${CF_CREDENTIALS:-/root/.secrets/cloudflare.ini}"
DEPLOY_LOG="/var/log/pwa-anwesenheitsliste-deploy.log"

export DEBIAN_FRONTEND=noninteractive

# Wechsel des MPM (prefork → event) braucht einen echten Neustart; ein
# "reload" kann außerdem abgebrochen werden, wenn apt gerade selbst einen
# Neustart angestoßen hat ("Job for apache2.service canceled").
APACHE_NEUSTART=0
apache_laden() {
    if [ "$APACHE_NEUSTART" = 1 ]; then
        systemctl restart apache2
        APACHE_NEUSTART=0
        return
    fi
    systemctl reload apache2 || { sleep 3; systemctl restart apache2; }
}

main() {

echo "== Pakete (Apache, certbot, git, PHP-FPM) =="
apt-get update -y
apt-get install -y apache2 certbot python3-certbot-dns-cloudflare openssl curl git \
    ca-certificates openssh-client php-fpm php-sqlite3 php-mbstring

echo "== mod_php entfernen, falls von einem früheren Lauf installiert =="
# Ältere Versionen dieses Skripts haben libapache2-mod-php installiert, was
# Apache server-weit auf mpm_prefork umstellt.
if ls /etc/apache2/mods-enabled/php*.load >/dev/null 2>&1; then
    for mod in /etc/apache2/mods-enabled/php*.load; do
        a2dismod -q "$(basename "$mod" .load)"
    done
    if [ -e /etc/apache2/mods-enabled/mpm_prefork.load ]; then
        a2dismod -q mpm_prefork
        a2enmod -q mpm_event
        APACHE_NEUSTART=1
    fi
fi
MOD_PHP_PAKETE=$(dpkg-query -W -f='${Package} ${db:Status-Abbrev}\n' 'libapache2-mod-php*' 2>/dev/null \
    | awk '$2 ~ /^ii/ {print $1}' || true)
if [ -n "$MOD_PHP_PAKETE" ]; then
    # shellcheck disable=SC2086
    apt-get remove -y $MOD_PHP_PAKETE
fi

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
    echo "!! GitHub-Zugriff fehlgeschlagen. Diesen Public Key bei GitHub unter" >&2
    echo "!! son1x/pwa-anwesenheitsliste -> Settings -> Deploy keys (read-only) eintragen:" >&2
    echo "" >&2
    cat "${DEPLOY_KEY}.pub" >&2
    echo "" >&2
    echo "!! Danach dieses Skript einfach erneut ausführen." >&2
    exit 1
fi
git reset -q --hard "origin/$BRANCH"
chown -R root:root "$APP_DIR"
chmod -R u+rwX,go+rX,go-w "$APP_DIR"
chmod 755 "$APP_DIR/deploy/vserver-pull.sh"
"$APP_DIR/deploy/vserver-pull.sh" --nur-version

echo "== Datenverzeichnis $DATA_DIR (außerhalb des Docroots) =="
mkdir -p "$DATA_DIR"
# Datenbank aus der alten Ablage im Docroot übernehmen
if [ -f "$APP_DIR/data/database.sqlite" ]; then
    if [ ! -f "$DATA_DIR/database.sqlite" ]; then
        echo "Übernehme bestehende Datenbank aus $APP_DIR/data/"
        mv "$APP_DIR/data/"database.sqlite* "$DATA_DIR/"
    else
        echo "!! $APP_DIR/data/database.sqlite existiert noch, $DATA_DIR/database.sqlite ebenfalls." >&2
        echo "!! Alte Datei bleibt liegen (per Apache gesperrt) - bitte von Hand prüfen." >&2
    fi
fi
rmdir "$APP_DIR/data" 2>/dev/null || true
chown -R www-data:www-data "$DATA_DIR"
chmod 750 "$DATA_DIR"

echo "== Konfiguration $CONFIG =="
if [ ! -f "$CONFIG" ]; then
    GEN_PIN=$(shuf -i 100000-999999 -n 1 --random-source=/dev/urandom)
    cat > "$CONFIG" <<EOF
; Konfiguration für pwa-anwesenheitsliste ($DOMAIN).
; Wird bei jeder Anfrage neu gelesen - kein Neustart nötig.

; Zugangs-PIN für die App (serverseitig geprüft)
app_pin = "${GEN_PIN}"

; Ablage der SQLite-Datenbank (außerhalb des Webroots)
data_dir = "${DATA_DIR}"
EOF
    echo "Neu angelegt - generierte App-PIN: ${GEN_PIN}"
fi
chown root:www-data "$CONFIG"
chmod 640 "$CONFIG"

echo "== PHP-FPM =="
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
systemctl enable --now "php${PHP_VER}-fpm"

echo "== Apache-Module =="
a2enmod -q proxy_fcgi setenvif headers ssl rewrite alias
a2enconf -q "php${PHP_VER}-fpm"

RENDERN="$APP_DIR/deploy/apache/rendern.sh"
mkdir -p "$ACME_DIR"

echo "== Apache: Port 80 =="
bash "$RENDERN" "$APP_DIR/deploy/apache/anwesenheitsliste.conf.in" DOMAIN="$DOMAIN" HTTP_PORT=80 ACME_DIR="$ACME_DIR" > "$SITE.neu"
mv "$SITE.neu" "$SITE"
a2ensite -q anwesenheitsliste
apache2ctl configtest
apache_laden

echo "== TLS-Zertifikat (Let's Encrypt) =="
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
if [ ! -f "$CERT" ]; then
    EMAIL_ARG=(--register-unsafely-without-email)
    [ -n "$ADMIN_EMAIL" ] && EMAIL_ARG=(-m "$ADMIN_EMAIL")
    if [ -f "$CF_CREDENTIALS" ]; then
        echo "DNS-01 über Cloudflare ($CF_CREDENTIALS)"
        certbot certonly --dns-cloudflare --dns-cloudflare-credentials "$CF_CREDENTIALS" \
            -d "$DOMAIN" --non-interactive --agree-tos "${EMAIL_ARG[@]}"
    else
        echo "Keine Cloudflare-Credentials unter $CF_CREDENTIALS - versuche HTTP-01 (webroot)."
        if ! certbot certonly --webroot -w "$ACME_DIR" -d "$DOMAIN" --non-interactive --agree-tos "${EMAIL_ARG[@]}"; then
            echo "" >&2
            echo "!! Zertifikat konnte nicht per HTTP-01 geholt werden (Cloudflare-Proxy/HTTPS-Zwang?)." >&2
            echo "!! Wie bei den anderen Subdomains Cloudflare-Token hinterlegen und Skript erneut ausführen:" >&2
            echo "!!   mkdir -p $(dirname "$CF_CREDENTIALS")" >&2
            # shellcheck disable=SC2028  # \n soll wörtlich ausgegeben werden
            echo "!!   printf 'dns_cloudflare_api_token = <token>\\n' > $CF_CREDENTIALS && chmod 600 $CF_CREDENTIALS" >&2
            exit 1
        fi
    fi
fi
RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN}.conf"
if [ -f "$RENEWAL_CONF" ] && ! grep -q "renew_hook" "$RENEWAL_CONF"; then
    sed -i '/\[renewalparams\]/a renew_hook = systemctl reload apache2' "$RENEWAL_CONF"
fi

SSL_OPTS=""
[ -f /etc/letsencrypt/options-ssl-apache.conf ] && SSL_OPTS="Include /etc/letsencrypt/options-ssl-apache.conf"

echo "== Apache: Port 443 (HTTPS) =="
bash "$RENDERN" "$APP_DIR/deploy/apache/anwesenheitsliste-ssl.conf.in" \
    DOMAIN="$DOMAIN" HTTPS_PORT=443 DOCROOT="$APP_DIR" \
    CERT="$CERT" CERT_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
    SSL_OPTS="$SSL_OPTS" LOG_DIR='${APACHE_LOG_DIR}' > "$SITE_SSL.neu"
mv "$SITE_SSL.neu" "$SITE_SSL"
a2ensite -q anwesenheitsliste-ssl
apache2ctl configtest
apache_laden

echo "== Cronjob: alle 5 Minuten Updates holen =="
touch "$DEPLOY_LOG"
chmod 640 "$DEPLOY_LOG"
cp "$APP_DIR/deploy/cron.d-pwa-anwesenheitsliste" /etc/cron.d/pwa-anwesenheitsliste
chmod 644 /etc/cron.d/pwa-anwesenheitsliste

echo ""
echo "== Fertig: https://$DOMAIN =="
echo "App-PIN:   $(sed -n 's/^app_pin *= *"\(.*\)"/\1/p' "$CONFIG")   (ändern in $CONFIG)"
echo "Daten:     $DATA_DIR/database.sqlite"
echo "Updates:   alle 5 Minuten per /etc/cron.d/pwa-anwesenheitsliste (Log: $DEPLOY_LOG)"
echo "Test:      curl -s -H 'X-App-Pin: <PIN>' https://$DOMAIN/api/events"
}

main "$@"
