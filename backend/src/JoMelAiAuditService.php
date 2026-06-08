<?php
/**
 * JoMelAiAuditService
 * Registers every Motor JoMelAi query for administrative review.
 * Visible only to ADMIN users.
 */
final class JoMelAiAuditService
{
    private const TABLE = 'jomelai_audit';

    public static function ensureTable(): void
    {
        Database::pdo()->exec("CREATE TABLE IF NOT EXISTS " . self::TABLE . " (
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
        Database::pdo()->exec("CREATE INDEX IF NOT EXISTS idx_jomelai_audit_user ON " . self::TABLE . "(user_id)");
        Database::pdo()->exec("CREATE INDEX IF NOT EXISTS idx_jomelai_audit_intent ON " . self::TABLE . "(intent)");
        Database::pdo()->exec("CREATE INDEX IF NOT EXISTS idx_jomelai_audit_created ON " . self::TABLE . "(created_at)");
    }

    public function log(
        array  $user,
        string $question,
        array  $intentResult,
        array  $engineResult,
        int    $durationMs
    ): void {
        self::ensureTable();
        $pdo  = Database::pdo();
        $stmt = $pdo->prepare(
            "INSERT INTO " . self::TABLE . "
            (user_id, user_email, role, question, intent, visible_intent,
             internal_engine, sql_executed, rag_collection, model_used,
             response_status, duration_ms, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        );
        $stmt->execute([
            $user['id']   ?? null,
            $user['email'] ?? null,
            $user['role']  ?? null,
            Support::strLimit($question, 2000),
            $intentResult['intent']         ?? null,
            $intentResult['visible_intent'] ?? null,
            $intentResult['engine']         ?? null,                  // internal only
            Support::strLimit((string)($engineResult['_sql'] ?? ''), 2000),
            $intentResult['collection'] ?? null,
            $engineResult['_model'] ?? null,
            ($engineResult['ok'] ?? true) ? 'ok' : 'error',
            $durationMs,
            Support::now(),
        ]);
    }

    public function getLog(int $limit = 200, int $offset = 0): array
    {
        self::ensureTable();
        $pdo  = Database::pdo();
        $rows = $pdo->prepare(
            "SELECT id, user_email, role, question, intent, visible_intent,
                    response_status, duration_ms, created_at
             FROM " . self::TABLE . "
             ORDER BY created_at DESC LIMIT ? OFFSET ?"
        );
        $rows->execute([$limit, $offset]);
        return $rows->fetchAll();
    }

    public function getStats(): array
    {
        self::ensureTable();
        $pdo = Database::pdo();
        $total     = (int)$pdo->query("SELECT COUNT(*) FROM " . self::TABLE)->fetchColumn();
        $byIntent  = $pdo->query(
            "SELECT intent, COUNT(*) AS total FROM " . self::TABLE . " GROUP BY intent ORDER BY total DESC"
        )->fetchAll();
        $avgMs     = (float)$pdo->query(
            "SELECT AVG(duration_ms) FROM " . self::TABLE
        )->fetchColumn();
        $errors    = (int)$pdo->query(
            "SELECT COUNT(*) FROM " . self::TABLE . " WHERE response_status = 'error'"
        )->fetchColumn();

        return [
            'total_queries'    => $total,
            'error_count'      => $errors,
            'avg_duration_ms'  => round($avgMs),
            'by_intent'        => $byIntent,
        ];
    }
}
