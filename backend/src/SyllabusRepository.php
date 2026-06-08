<?php
final class SyllabusRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::pdo();
    }

    public function stats(): array
    {
        $total = (int)$this->pdo->query('SELECT COUNT(*) AS c FROM syllabi')->fetch()['c'];
        $programs = (int)$this->pdo->query("SELECT COUNT(DISTINCT NULLIF(programa, '')) AS c FROM syllabi")->fetch()['c'];
        $courses = (int)$this->pdo->query("SELECT COUNT(DISTINCT NULLIF(curso, '')) AS c FROM syllabi")->fetch()['c'];
        $lastImport = $this->pdo->query('SELECT * FROM imports ORDER BY id DESC LIMIT 1')->fetch() ?: null;
        $topPrograms = $this->pdo->query("SELECT COALESCE(NULLIF(programa, ''), 'Sin programa') AS label, COUNT(*) AS total FROM syllabi GROUP BY label ORDER BY total DESC LIMIT 12")->fetchAll();
        return compact('total', 'programs', 'courses', 'lastImport', 'topPrograms');
    }

    public function search(string $query, int $limit = 8): array
    {
        $query = trim($query);
        $limit = max(1, min($limit, 30));
        if ($query === '') {
            $stmt = $this->pdo->prepare('SELECT * FROM syllabi ORDER BY id DESC LIMIT ?');
            $stmt->bindValue(1, $limit, PDO::PARAM_INT);
            $stmt->execute();
            return $stmt->fetchAll();
        }

        try {
            $ftsQuery = $this->toFtsQuery($query);
            $sql = "SELECT s.*, bm25(syllabi_fts) AS score
                    FROM syllabi_fts
                    JOIN syllabi s ON s.id = syllabi_fts.rowid
                    WHERE syllabi_fts MATCH :q
                    ORDER BY score
                    LIMIT :limit";
            $stmt = $this->pdo->prepare($sql);
            $stmt->bindValue(':q', $ftsQuery, PDO::PARAM_STR);
            $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
            $stmt->execute();
            $rows = $stmt->fetchAll();
            if ($rows) {
                return $rows;
            }
        } catch (Throwable $e) {
            // Fallback below.
        }

        $like = '%' . $query . '%';
        $sql = "SELECT * FROM syllabi
                WHERE curso LIKE :q OR programa LIKE :q OR competencia LIKE :q OR sumilla LIKE :q OR contenidos LIKE :q OR bibliografia LIKE :q OR normalized_text LIKE :q
                ORDER BY id DESC LIMIT :limit";
        $stmt = $this->pdo->prepare($sql);
        $stmt->bindValue(':q', $like, PDO::PARAM_STR);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        return $stmt->fetchAll();
    }

    private function toFtsQuery(string $query): string
    {
        $words = preg_split('/\s+/u', trim($query)) ?: [];
        $parts = [];
        foreach ($words as $word) {
            $normalized = Support::normalize($word);
            if (mb_strlen($normalized, 'UTF-8') >= 2) {
                $parts[] = $normalized;
            }
        }
        if (!$parts) {
            return '"' . str_replace('\"', '""', $query) . '"';
        }
        return implode(' OR ', array_map(fn($p) => $p . '*', $parts));
    }


    public function contextForPrompt(string $query, int $limit = 6): array
    {
        $rows = $this->search($query, $limit);
        return array_map(function (array $row) {
            return [
                'id' => (int)$row['id'],
                'curso' => $row['curso'],
                'programa' => $row['programa'],
                'codigo' => $row['codigo'],
                'ciclo' => $row['ciclo'],
                'creditos' => $row['creditos'],
                'competencia' => Support::strLimit($row['competencia'] ?? '', 900),
                'sumilla' => Support::strLimit($row['sumilla'] ?? '', 900),
                'contenidos' => Support::strLimit($row['contenidos'] ?? '', 1200),
                'evaluacion' => Support::strLimit($row['evaluacion'] ?? '', 800),
                'bibliografia' => Support::strLimit($row['bibliografia'] ?? '', 800),
            ];
        }, $rows);
    }
}
