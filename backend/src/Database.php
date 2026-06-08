<?php
final class Database
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }
        $dbPath = Support::config('db_path');
        $dir = dirname($dbPath);
        Support::ensureDir($dir);
        if (!file_exists($dbPath)) {
            if (@touch($dbPath) === false) {
                throw new RuntimeException('No se pudo crear la base SQLite en: ' . $dbPath);
            }
            @chmod($dbPath, 0664);
        }
        if (!is_writable($dbPath)) {
            throw new RuntimeException('La base SQLite no tiene permisos de escritura: ' . $dbPath);
        }
        self::$pdo = new PDO('sqlite:' . $dbPath, null, null, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        self::$pdo->exec('PRAGMA journal_mode=WAL');
        self::$pdo->exec('PRAGMA synchronous=NORMAL');
        self::$pdo->exec('PRAGMA temp_store=MEMORY');
        self::migrate();
        return self::$pdo;
    }

    private static function migrate(): void
    {
        $pdo = self::$pdo;
        $pdo->exec("CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'admin',
            status TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL,
            last_login_at TEXT
        )");

        $pdo->exec("CREATE TABLE IF NOT EXISTS imports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            status TEXT NOT NULL,
            file_path TEXT NOT NULL,
            delimiter TEXT NOT NULL,
            total_rows INTEGER NOT NULL DEFAULT 0,
            indexed_rows INTEGER NOT NULL DEFAULT 0,
            headers_json TEXT,
            message TEXT,
            created_at TEXT NOT NULL,
            finished_at TEXT
        )");

        $pdo->exec("CREATE TABLE IF NOT EXISTS syllabi (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_file TEXT,
            row_number INTEGER,
            facultad TEXT,
            escuela TEXT,
            programa TEXT,
            codigo TEXT,
            curso TEXT,
            ciclo TEXT,
            creditos TEXT,
            horas_teoricas TEXT,
            horas_practicas TEXT,
            competencia TEXT,
            sumilla TEXT,
            contenidos TEXT,
            evaluacion TEXT,
            bibliografia TEXT,
            raw_json TEXT,
            normalized_text TEXT,
            created_at TEXT NOT NULL
        )");

        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_syllabi_curso ON syllabi(curso)");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_syllabi_programa ON syllabi(programa)");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_syllabi_codigo ON syllabi(codigo)");

        try {
            $pdo->exec("CREATE VIRTUAL TABLE IF NOT EXISTS syllabi_fts USING fts5(
                curso, programa, competencia, sumilla, contenidos, bibliografia, normalized_text,
                content='syllabi', content_rowid='id'
            )");
        } catch (Throwable $e) {
            // Fallback LIKE search is used if FTS5 is unavailable.
        }

        $pdo->exec("CREATE TABLE IF NOT EXISTS assistant_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            model TEXT NOT NULL,
            task_type TEXT NOT NULL,
            prompt TEXT NOT NULL,
            response TEXT,
            context_json TEXT,
            created_at TEXT NOT NULL
        )");

        $pdo->exec("CREATE TABLE IF NOT EXISTS curriculum_projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            faculty TEXT NOT NULL,
            program TEXT NOT NULL,
            degree TEXT,
            modality TEXT,
            cycles INTEGER NOT NULL DEFAULT 10,
            target_credits INTEGER NOT NULL DEFAULT 200,
            profile_text TEXT,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'draft',
            created_by INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )");

        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_curriculum_projects_program ON curriculum_projects(program)");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_curriculum_projects_status ON curriculum_projects(status)");

        $pdo->exec("CREATE TABLE IF NOT EXISTS curriculum_versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER NOT NULL,
            version_no INTEGER NOT NULL,
            title TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'draft',
            plan_json TEXT NOT NULL,
            plan_markdown TEXT,
            change_summary TEXT,
            created_by INTEGER,
            created_at TEXT NOT NULL,
            published_at TEXT,
            UNIQUE(project_id, version_no),
            FOREIGN KEY(project_id) REFERENCES curriculum_projects(id)
        )");

        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_curriculum_versions_project ON curriculum_versions(project_id)");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_curriculum_versions_status ON curriculum_versions(status)");

        $pdo->exec("CREATE TABLE IF NOT EXISTS curriculum_audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            action TEXT NOT NULL,
            payload_json TEXT,
            created_at TEXT NOT NULL
        )");


        $pdo->exec("CREATE TABLE IF NOT EXISTS curriculum_generation_cache (
            cache_key TEXT PRIMARY KEY,
            request_hash TEXT NOT NULL,
            program TEXT,
            faculty TEXT,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL
        )");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_curriculum_generation_cache_expires ON curriculum_generation_cache(expires_at)");

        $pdo->exec("CREATE TABLE IF NOT EXISTS curriculum_semantic_memory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_type TEXT NOT NULL,
            source_key TEXT NOT NULL,
            title TEXT,
            content TEXT NOT NULL,
            normalized_text TEXT,
            tags_json TEXT,
            created_at TEXT NOT NULL,
            UNIQUE(source_type, source_key)
        )");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_curriculum_semantic_memory_source ON curriculum_semantic_memory(source_type, source_key)");

        // Motor JoMelAi audit table
        $pdo->exec("CREATE TABLE IF NOT EXISTS jomelai_audit (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id          INTEGER,
            user_email       TEXT,
            role             TEXT,
            question         TEXT NOT NULL,
            intent           TEXT,
            visible_intent   TEXT,
            internal_engine  TEXT,
            sql_executed     TEXT,
            rag_collection   TEXT,
            model_used       TEXT,
            response_status  TEXT NOT NULL DEFAULT 'ok',
            duration_ms      INTEGER,
            created_at       TEXT NOT NULL
        )");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_jomelai_audit_user    ON jomelai_audit(user_id)");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_jomelai_audit_intent  ON jomelai_audit(intent)");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_jomelai_audit_created ON jomelai_audit(created_at)");

        self::seedAdmin();
    }

    private static function seedAdmin(): void
    {
        $pdo = self::$pdo;
        $email = 'admin@upeu.edu.pe';
        $stmt = $pdo->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
        $stmt->execute([$email]);
        if ($stmt->fetch()) {
            return;
        }
        $hash = password_hash('Admin12345!', PASSWORD_DEFAULT);
        $insert = $pdo->prepare('INSERT INTO users (name, email, password_hash, role, status, created_at) VALUES (?, ?, ?, ?, ?, ?)');
        $insert->execute(['Administrador Curricular UPeU', $email, $hash, 'admin', 'active', Support::now()]);
    }
}
