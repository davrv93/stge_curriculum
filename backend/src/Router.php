<?php
final class Router
{
    private array $routes = [];

    public function add(string $method, string $path, callable $handler): void
    {
        $this->routes[] = [$method, $path, $handler];
    }

    public function dispatch(): void
    {
        $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
        $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

        if ($method === 'OPTIONS') {
            Support::json(['ok' => true]);
            return;
        }

        foreach ($this->routes as [$routeMethod, $routePath, $handler]) {
            $params = [];
            if ($method === $routeMethod && $this->matches($routePath, $path, $params)) {
                try {
                    $handler($params);
                } catch (Throwable $e) {
                    Support::json([
                        'ok' => false,
                        'message' => 'Error interno del servidor.',
                        'detail' => Support::config('app_env') === 'local' ? $e->getMessage() : null,
                    ], 500);
                }
                return;
            }
        }

        Support::json(['ok' => false, 'message' => 'Ruta no encontrada.', 'path' => $path], 404);
    }

    private function matches(string $routePath, string $path, array &$params): bool
    {
        if ($routePath === $path) {
            return true;
        }
        $routeParts = explode('/', trim($routePath, '/'));
        $pathParts = explode('/', trim($path, '/'));
        if (count($routeParts) !== count($pathParts)) {
            return false;
        }
        foreach ($routeParts as $i => $part) {
            if (str_starts_with($part, '{') && str_ends_with($part, '}')) {
                $name = trim($part, '{}');
                $params[$name] = urldecode($pathParts[$i]);
                continue;
            }
            if ($part !== $pathParts[$i]) {
                return false;
            }
        }
        return true;
    }
}
