<?php
// api.php - Backend für Anwesenheitsliste (PHP / SQLite)
header('Content-Type: application/json; charset=utf-8');

$dbFile = __DIR__ . '/data/database.sqlite';
if (!file_exists(__DIR__ . '/data')) {
    mkdir(__DIR__ . '/data', 0755, true);
}

try {
    $pdo = new PDO('sqlite:' . $dbFile);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // Tabellen initialisieren
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
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];
$path = isset($_GET['path']) ? trim($_GET['path'], '/') : '';
$segments = explode('/', $path);

$resource = $segments[0] ?? '';
$id = $segments[1] ?? null;
$subresource = $segments[2] ?? null;

if ($resource === 'teilnehmer') {
    if ($method === 'GET') {
        $stmt = $pdo->query('SELECT * FROM teilnehmer ORDER BY name');
        echo json_encode($stmt->fetchAll(PDO::FETCH_ASSOC));
    } elseif ($method === 'POST') {
        $input = json_decode(file_get_contents('php://input'), true);
        $stmt = $pdo->prepare('INSERT INTO teilnehmer (name, email) VALUES (?, ?)');
        $stmt->execute([$input['name'] ?? '', $input['email'] ?? '']);
        echo json_encode(['id' => $pdo->lastInsertRowid()]);
    }
} elseif ($resource === 'events') {
    if ($id && $subresource === 'anwesenheit') {
        if ($method === 'GET') {
            $stmt = $pdo->prepare('SELECT teilnehmer_id FROM anwesenheit WHERE event_id = ?');
            $stmt->execute([$id]);
            echo json_encode($stmt->fetchAll(PDO::FETCH_ASSOC));
        } elseif ($method === 'POST') {
            $input = json_decode(file_get_contents('php://input'), true);
            $pdo->beginTransaction();
            $del = $pdo->prepare('DELETE FROM anwesenheit WHERE event_id = ?');
            $del->execute([$id]);
            $ins = $pdo->prepare('INSERT INTO anwesenheit (event_id, teilnehmer_id) VALUES (?, ?)');
            foreach ($input['teilnehmer_ids'] ?? [] as $tId) {
                $ins->execute([$id, $tId]);
            }
            $pdo->commit();
            echo json_encode(['success' => true]);
        }
    } else {
        if ($method === 'GET') {
            $stmt = $pdo->query('SELECT * FROM events ORDER BY datum DESC');
            echo json_encode($stmt->fetchAll(PDO::FETCH_ASSOC));
        } elseif ($method === 'POST') {
            $input = json_decode(file_get_contents('php://input'), true);
            $stmt = $pdo->prepare('INSERT INTO events (name, datum) VALUES (?, ?)');
            $stmt->execute([$input['name'] ?? '', $input['datum'] ?? '']);
            echo json_encode(['id' => $pdo->lastInsertRowid()]);
        }
    }
} else {
    http_response_code(404);
    echo json_encode(['error' => 'Not found']);
}
