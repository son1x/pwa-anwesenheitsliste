<?php
// Nur für lokale Tests mit dem PHP-Entwicklungsserver (ersetzt die .htaccess):
//   php -S 127.0.0.1:8080 deploy/dev-router.php
// Ohne /etc/pwa-anwesenheitsliste.ini: keine PIN, Datenbank in ./data
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if (preg_match('#^/api/(.*)$#', $uri, $m)) {
    $_GET['path'] = $m[1];
    chdir(dirname(__DIR__));
    require dirname(__DIR__) . '/api.php';
    return true;
}
if (preg_match('#(^|/)(\.|deploy/|data/)#', $uri)) {
    http_response_code(404);
    return true;
}
return false;
