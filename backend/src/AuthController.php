<?php
final class AuthController
{
    public function login(): void
    {
        $data = Support::readJson();
        $email = trim((string)($data['email'] ?? ''));
        $password = (string)($data['password'] ?? '');

        if ($email === '' || $password === '') {
            Support::json(['ok' => false, 'message' => 'Correo y contraseña son obligatorios.'], 422);
            return;
        }

        $pdo = Database::pdo();
        $stmt = $pdo->prepare('SELECT * FROM users WHERE email = ? AND status = ? LIMIT 1');
        $stmt->execute([$email, 'active']);
        $user = $stmt->fetch();

        if (!$user || !password_verify($password, $user['password_hash'])) {
            Support::json(['ok' => false, 'message' => 'Credenciales inválidas.'], 401);
            return;
        }

        session_regenerate_id(true);
        $_SESSION['user'] = [
            'id' => (int)$user['id'],
            'name' => $user['name'],
            'email' => $user['email'],
            'role' => $user['role'],
        ];
        $pdo->prepare('UPDATE users SET last_login_at = ? WHERE id = ?')->execute([Support::now(), $user['id']]);
        Support::json(['ok' => true, 'user' => $_SESSION['user']]);
    }

    public function me(): void
    {
        $user = Support::user();
        Support::json(['ok' => true, 'authenticated' => (bool)$user, 'user' => $user]);
    }

    public function logout(): void
    {
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $params = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $params['path'], $params['domain'], $params['secure'], $params['httponly']);
        }
        session_destroy();
        Support::json(['ok' => true, 'message' => 'Sesión cerrada.']);
    }

    public function demoCredentials(): void
    {
        Support::json([
            'ok' => true,
            'credentials' => [
                'role' => 'admin',
                'email' => 'admin@upeu.edu.pe',
                'password' => 'Admin12345!',
                'note' => 'Credenciales de prueba. Cambiar antes de producción.',
            ],
        ]);
    }
}
