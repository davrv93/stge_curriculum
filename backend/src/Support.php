<?php
final class Support
{
    public static array $config = [];

    public static function config(?string $key = null, mixed $default = null): mixed
    {
        if ($key === null) {
            return self::$config;
        }
        return self::$config[$key] ?? $default;
    }

    public static function bootstrap(): void
    {
        self::$config = require __DIR__ . '/../config/app.php';
        foreach (['session_path', 'upload_path', 'report_path', 'shared_csv_dir'] as $dirKey) {
            self::ensureDir((string)self::$config[$dirKey]);
        }
        self::ensureDir(dirname((string)self::$config['db_path']));
        ini_set('session.save_path', self::$config['session_path']);
        ini_set('session.cookie_httponly', '1');
        ini_set('session.cookie_samesite', 'Lax');
        session_name(self::$config['session_name']);
        session_start();
    }


    public static function ensureDir(string $path): void
    {
        if ($path === '') {
            throw new RuntimeException('Ruta de almacenamiento vacía.');
        }
        if (!is_dir($path)) {
            if (!mkdir($path, 0775, true) && !is_dir($path)) {
                throw new RuntimeException('No se pudo crear el directorio requerido: ' . $path);
            }
        }
        @chmod($path, 0775);
        if (!is_writable($path)) {
            throw new RuntimeException('El directorio no tiene permisos de escritura: ' . $path);
        }
    }

    public static function json(mixed $payload, int $status = 200): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
    }

    public static function readJson(): array
    {
        $raw = file_get_contents('php://input');
        if ($raw === false || trim($raw) === '') {
            return [];
        }
        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : [];
    }

    public static function user(): ?array
    {
        return $_SESSION['user'] ?? null;
    }

    public static function requireAuth(): array
    {
        $user = self::user();
        if (!$user) {
            self::json(['ok' => false, 'message' => 'No autenticado.'], 401);
            exit;
        }
        return $user;
    }

    public static function requireAdmin(): array
    {
        $user = self::requireAuth();
        if (($user['role'] ?? '') !== 'admin') {
            self::json(['ok' => false, 'message' => 'Solo el administrador puede ejecutar esta acción.'], 403);
            exit;
        }
        return $user;
    }

    public static function normalize(?string $value): string
    {
        $value = trim((string)$value);
        $value = mb_strtolower($value, 'UTF-8');
        $from = ['á','é','í','ó','ú','ü','ñ','Á','É','Í','Ó','Ú','Ü','Ñ'];
        $to = ['a','e','i','o','u','u','n','a','e','i','o','u','u','n'];
        $value = str_replace($from, $to, $value);
        $value = preg_replace('/[^a-z0-9]+/u', '_', $value) ?: '';
        return trim($value, '_');
    }

    public static function now(): string
    {
        return date('Y-m-d H:i:s');
    }

    public static function strLimit(string $value, int $limit): string
    {
        if (mb_strlen($value, 'UTF-8') <= $limit) {
            return $value;
        }
        return mb_substr($value, 0, $limit, 'UTF-8') . '...';
    }

    public static function safeText(mixed $value): string
    {
        if (is_array($value)) {
            $value = implode(' ', array_map([self::class, 'safeText'], $value));
        }
        $value = (string)$value;
        $value = preg_replace('/\s+/u', ' ', $value) ?: '';
        return trim($value);
    }
}
