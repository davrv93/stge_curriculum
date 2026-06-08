<?php
final class SyllabusController
{
    public function search(): void
    {
        Support::requireAuth();
        $q = trim((string)($_GET['q'] ?? ''));
        $limit = max(1, min((int)($_GET['limit'] ?? 10), 50));
        if ($q === '') {
            Support::json(['ok' => true, 'results' => []]);
            return;
        }
        $term = str_replace("'", "''", $q);
        $where = "lower(coalesce(curso,'')) LIKE lower('%{$term}%') OR lower(coalesce(programa_estudio,'')) LIKE lower('%{$term}%') OR lower(coalesce(sumilla,'')) LIKE lower('%{$term}%')";
        $sql = "SELECT * FROM silabos WHERE {$where} LIMIT {$limit}";
        try {
            $res = (new DataEngineClient())->post('/duckdb/query', ['sql' => $sql, 'limit' => $limit]);
            Support::json(['ok' => (bool)($res['ok'] ?? false), 'results' => $res['rows'] ?? $res['query']['rows'] ?? [], 'raw' => $res]);
        } catch (Throwable $e) {
            Support::json(['ok' => false, 'message' => 'No se pudo buscar en sílabos.', 'detail' => Support::config('app_env') === 'local' ? $e->getMessage() : null], 422);
        }
    }

    public function show(array $params): void
    {
        Support::requireAuth();
        $id = (int)($params['id'] ?? 0);
        $res = (new DataEngineClient())->post('/duckdb/query', [
            'sql' => 'SELECT * FROM silabos LIMIT 1 OFFSET ' . max(0, $id - 1),
            'limit' => 1,
        ]);
        $rows = $res['rows'] ?? $res['query']['rows'] ?? [];
        Support::json(['ok' => !empty($rows), 'item' => $rows[0] ?? null]);
    }
}
