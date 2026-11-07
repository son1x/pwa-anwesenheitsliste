# Anwesenheitsliste (PWA)

PHP + SQLite, ausgeliefert von Apache über PHP-FPM unter
`https://anwesenheitsliste.ministo.de`.

## Installation auf dem vServer

```bash
sudo bash install.sh [domain] [email]
```

Beim ersten Lauf wird ein Deploy-Key erzeugt und ausgegeben – bei GitHub unter
*Settings → Deploy keys* (read-only) eintragen und `install.sh` erneut starten.
Liegt das Repo schon auf dem Server, reicht `sudo bash deploy/vserver-setup.sh`.

TLS wie bei den anderen Subdomains über Cloudflare DNS-01
(`/root/.secrets/cloudflare.ini`); ohne diese Datei wird HTTP-01 versucht.

| Was | Wo |
| --- | --- |
| Code (Git-Checkout, Docroot) | `/var/www/pwa-anwesenheitsliste` |
| Datenbank | `/var/lib/pwa-anwesenheitsliste/database.sqlite` |
| Config (App-PIN) | `/etc/pwa-anwesenheitsliste.ini` |
| Deploy-Log | `/var/log/pwa-anwesenheitsliste-deploy.log` |

Updates: `/etc/cron.d/pwa-anwesenheitsliste` ruft alle 5 Minuten
`deploy/vserver-pull.sh` auf und holt Branch `main`.

## Lokal testen

```bash
php -S 127.0.0.1:8080 deploy/dev-router.php   # ohne PIN, Daten in ./data
```
