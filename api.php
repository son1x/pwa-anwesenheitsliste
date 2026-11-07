<?php
// api.php - Backend für Anwesenheitsliste (PHP / SQLite)
//
// Konfiguration: /etc/pwa-anwesenheitsliste.ini (angelegt von deploy/vserver-setup.sh)
//   app_pin  = "123456"                           Zugangs-PIN (Header X-App-Pin)
//   data_dir = "/var/lib/pwa-anwesenheitsliste"   Ablage der SQLite-Datenbank
// Die Datenbank liegt bewusst außerhalb des Webroots.
//
// Lokal testen ohne Config: php -S 127.0.0.1:8080 router.php  (keine PIN, Daten in ./data)

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function antwort($daten, int $status = 200): void {
    http_response_code($status);
    echo json_encode($daten, JSON_UNESCAPED_UNICODE);
    exit;
}

function fehler(string $meldung, int $status): void {
    antwort(['error' => $meldung], $status);
}

function eingabe(): array {
    $daten = json_decode(file_get_contents('php://input'), true);
    if (!is_array($daten)) {
        fehler('Ungültiger JSON-Body', 400);
    }
    return $daten;
}

function text($wert, int $max): string {
    $wert = trim(is_string($wert) ? $wert : '');
    return mb_substr($wert, 0, $max);
}

// --- Konfiguration --------------------------------------------------------
$configDatei = getenv('ANWESENHEIT_CONFIG') ?: '/etc/pwa-anwesenheitsliste.ini';
$config = is_readable($configDatei) ? parse_ini_file($configDatei) : false;

if ($config === false) {
    if (PHP_SAPI !== 'cli-server') {
        // Auf dem Server nie ohne PIN laufen
        fehler("Konfiguration fehlt ($configDatei) - deploy/vserver-setup.sh ausführen", 500);
    }
    $config = ['app_pin' => '', 'data_dir' => __DIR__ . '/data'];
}

$pin = (string)($config['app_pin'] ?? '');
$dataDir = rtrim((string)($config['data_dir'] ?? ''), '/');
if ($dataDir === '') {
    fehler('data_dir in der Konfiguration fehlt', 500);
}

// --- Zugangsschutz --------------------------------------------------------
if ($pin !== '') {
    $gesendet = (string)($_SERVER['HTTP_X_APP_PIN'] ?? '');
    if (!hash_equals($pin, $gesendet)) {
        sleep(1); // Durchprobieren bremsen
        fehler('PIN falsch oder fehlt', 401);
    }
}

// --- Datenbank ------------------------------------------------------------
try {
    if (!is_dir($dataDir) && !mkdir($dataDir, 0750, true)) {
        throw new RuntimeException("Datenverzeichnis $dataDir kann nicht angelegt werden");
    }
    $pdo = new PDO('sqlite:' . $dataDir . '/database.sqlite');
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    $pdo->exec('PRAGMA foreign_keys = ON');
    $pdo->exec('PRAGMA busy_timeout = 5000');

    $pdo->exec("
        CREATE TABLE IF NOT EXISTS teilnehmer (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT
        );
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            datum TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS anwesenheit (
            event_id INTEGER,
            teilnehmer_id INTEGER,
            PRIMARY KEY (event_id, teilnehmer_id)
        );
    ");
} catch (Throwable $e) {
    error_log('anwesenheitsliste: ' . $e->getMessage());
    fehler('Datenbank nicht verfügbar', 500);
}

// --- Routing --------------------------------------------------------------
$method = $_SERVER['REQUEST_METHOD'];
$path = isset($_GET['path']) ? trim((string)$_GET['path'], '/') : '';
$segments = $path === '' ? [] : explode('/', $path);

$resource = $segments[0] ?? '';
$id = $segments[1] ?? null;
$subresource = $segments[2] ?? null;

if ($id !== null && !ctype_digit($id)) {
    fehler('Ungültige ID', 400);
}
$id = $id !== null ? (int)$id : null;

try {
    if ($resource === 'teilnehmer' && $id === null) {
        if ($method === 'GET') {
            antwort($pdo->query('SELECT id, name, email FROM teilnehmer ORDER BY name COLLATE NOCASE')->fetchAll());
        } elseif ($method === 'POST') {
            $in = eingabe();
            $name = text($in['name'] ?? '', 200);
            $email = text($in['email'] ?? '', 200);
            if ($name === '') {
                fehler('Name fehlt', 400);
            }
            if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
                fehler('E-Mail-Adresse ungültig', 400);
            }
            $stmt = $pdo->prepare('INSERT INTO teilnehmer (name, email) VALUES (?, ?)');
            $stmt->execute([$name, $email]);
            antwort(['id' => (int)$pdo->lastInsertId()], 201);
        }
        fehler('Methode nicht erlaubt', 405);
    }

    if ($resource === 'events' && $id === null) {
        if ($method === 'GET') {
            antwort($pdo->query('SELECT id, name, datum FROM events ORDER BY datum DESC, id DESC')->fetchAll());
        } elseif ($method === 'POST') {
            $in = eingabe();
            $name = text($in['name'] ?? '', 200);
            $datum = text($in['datum'] ?? '', 10);
            if ($name === '') {
                fehler('Name fehlt', 400);
            }
            $d = DateTime::createFromFormat('!Y-m-d', $datum);
            if (!$d || $d->format('Y-m-d') !== $datum) {
                fehler('Datum ungültig (erwartet JJJJ-MM-TT)', 400);
            }
            $stmt = $pdo->prepare('INSERT INTO events (name, datum) VALUES (?, ?)');
            $stmt->execute([$name, $datum]);
            antwort(['id' => (int)$pdo->lastInsertId()], 201);
        }
        fehler('Methode nicht erlaubt', 405);
    }

    if ($resource === 'events' && $id !== null && $subresource === 'anwesenheit' && count($segments) === 3) {
        $existiert = $pdo->prepare('SELECT 1 FROM events WHERE id = ?');
        $existiert->execute([$id]);
        if (!$existiert->fetchColumn()) {
            fehler('Veranstaltung nicht gefunden', 404);
        }

        if ($method === 'GET') {
            $stmt = $pdo->prepare('SELECT teilnehmer_id FROM anwesenheit WHERE event_id = ?');
            $stmt->execute([$id]);
            $zeilen = array_map(fn($z) => ['teilnehmer_id' => (int)$z['teilnehmer_id']], $stmt->fetchAll());
            antwort($zeilen);
        } elseif ($method === 'POST') {
            $in = eingabe();
            $ids = $in['teilnehmer_ids'] ?? [];
            if (!is_array($ids)) {
                fehler('teilnehmer_ids muss eine Liste sein', 400);
            }
            $ids = array_values(array_unique(array_map('intval', $ids)));

            $pdo->beginTransaction();
            $pdo->prepare('DELETE FROM anwesenheit WHERE event_id = ?')->execute([$id]);
            // Nur existierende Teilnehmer übernehmen
            $ins = $pdo->prepare('INSERT INTO anwesenheit (event_id, teilnehmer_id)
                                  SELECT ?, id FROM teilnehmer WHERE id = ?');
            foreach ($ids as $tId) {
                $ins->execute([$id, $tId]);
            }
            $pdo->commit();
            antwort(['success' => true]);
        }
        fehler('Methode nicht erlaubt', 405);
    }

    fehler('Not found', 404);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('anwesenheitsliste: ' . $e->getMessage());
    fehler('Interner Fehler', 500);
}
