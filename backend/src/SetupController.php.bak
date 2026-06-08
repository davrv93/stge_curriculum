<?php
final class SetupController
{
    public function status(): void
    {
        Support::requireAuth();
        $csvPath = trim((string)($_GET['file_path'] ?? Support::config('default_csv_path')));
        $collection = trim((string)($_GET['collection'] ?? 'silabos'));
        $csv = [
            'path' => $csvPath,
            'exists' => is_file($csvPath),
            'size_bytes' => is_file($csvPath) ? filesize($csvPath) : 0,
            'size_mb' => is_file($csvPath) ? round(filesize($csvPath) / 1024 / 1024, 2) : 0,
        ];
        $engine = (new DataEngineClient())->get('/fs/status', ['file_path' => $csvPath, 'collection' => $collection]);
        $jobs = (new DataEngineClient())->get('/jobs', ['limit' => 10]);
        $ollama = (new OllamaClient())->health();
        Support::json([
            'ok' => true,
            'csv' => $csv,
            'engine' => $engine,
            'jobs' => $jobs['jobs'] ?? [],
            'ollama' => $ollama,
            'default_csv_path' => Support::config('default_csv_path'),
            'recommended_models' => [
                'qwen2.5-coder:3b',
                'deepseek-coder:1.5b',
                'nomic-embed-text',
                'qwen2.5-coder:7b'
            ],
        ]);
    }

    public function pullModelJob(): void
    {
        Support::requireAdmin();
        $data = Support::readJson();
        $model = trim((string)($data['model'] ?? 'qwen2.5-coder:3b'));
        $res = (new DataEngineClient())->post('/jobs/ollama-pull', ['model' => $model]);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function csvFiles(): void
    {
        Support::requireAuth();
        $res = (new DataEngineClient())->get('/fs/syllabi-files');
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function profileCsv(): void
    {
        Support::requireAuth();
        $data = Support::readJson();
        $payload = [
            'file_path' => trim((string)($data['file_path'] ?? Support::config('default_csv_path'))),
            'delimiter' => ($data['delimiter'] ?? null) === '' ? null : ($data['delimiter'] ?? null),
            'encoding' => ($data['encoding'] ?? null) === '' ? null : ($data['encoding'] ?? null),
            'sample_rows' => (int)($data['sample_rows'] ?? 5000),
        ];
        $res = (new DataEngineClient())->post('/csv/profile', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function duckdbJob(): void
    {
        Support::requireAdmin();
        $data = Support::readJson();
        $payload = [
            'file_path' => trim((string)($data['file_path'] ?? Support::config('default_csv_path'))),
            'table' => trim((string)($data['table'] ?? 'silabos')),
            'delimiter' => ($data['delimiter'] ?? null) === '' ? null : ($data['delimiter'] ?? null),
            'encoding' => ($data['encoding'] ?? null) === '' ? null : ($data['encoding'] ?? null),
            'quote' => ($data['quote'] ?? null) === '' ? null : ($data['quote'] ?? '"'),
            'escape' => ($data['escape'] ?? null) === '' ? null : ($data['escape'] ?? '"'),
            'skip_rows' => (int)($data['skip_rows'] ?? 0),
            'strict_mode' => (bool)($data['strict_mode'] ?? false),
            'null_padding' => (bool)($data['null_padding'] ?? true),
            'max_line_size' => (int)($data['max_line_size'] ?? 10000000),
            'replace' => (bool)($data['replace'] ?? true),
            'sample_size' => (int)($data['sample_size'] ?? 20000),
            'normalize_columns' => (bool)($data['normalize_columns'] ?? true),
        ];
        $res = (new DataEngineClient())->post('/jobs/duckdb-import', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function ragJob(): void
    {
        Support::requireAdmin();
        $data = Support::readJson();
        $payload = [
            'file_path' => trim((string)($data['file_path'] ?? Support::config('default_csv_path'))),
            'collection' => trim((string)($data['collection'] ?? 'silabos')),
            'delimiter' => ($data['delimiter'] ?? null) === '' ? null : ($data['delimiter'] ?? null),
            'encoding' => ($data['encoding'] ?? null) === '' ? null : ($data['encoding'] ?? null),
            'chunk_size_rows' => (int)($data['chunk_size_rows'] ?? 1000),
            'row_limit' => (int)($data['row_limit'] ?? 2000),
            'text_columns' => $this->csvList($data['text_columns'] ?? []),
            'metadata_columns' => $this->csvList($data['metadata_columns'] ?? []),
            'document_chars' => (int)($data['document_chars'] ?? 1300),
            'overlap_chars' => (int)($data['overlap_chars'] ?? 150),
            'embed_batch_size' => (int)($data['embed_batch_size'] ?? 16),
            'reset_collection' => (bool)($data['reset_collection'] ?? false),
        ];
        $res = (new DataEngineClient())->post('/jobs/rag-build', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function ragCollectionsJob(): void
    {
        Support::requireAdmin();
        $data = Support::readJson();
        $payload = [
            'file_path' => trim((string)($data['file_path'] ?? Support::config('default_csv_path'))),
            'collection_prefix' => trim((string)($data['collection_prefix'] ?? 'silabos')),
            'delimiter' => ($data['delimiter'] ?? null) === '' ? null : ($data['delimiter'] ?? null),
            'encoding' => ($data['encoding'] ?? null) === '' ? null : ($data['encoding'] ?? null),
            'chunk_size_rows' => (int)($data['chunk_size_rows'] ?? 1000),
            'row_limit' => (int)($data['row_limit'] ?? 2000),
            'metadata_columns' => $this->csvList($data['metadata_columns'] ?? []),
            'document_chars' => (int)($data['document_chars'] ?? 1300),
            'overlap_chars' => (int)($data['overlap_chars'] ?? 150),
            'embed_batch_size' => (int)($data['embed_batch_size'] ?? 16),
            'reset_collections' => (bool)($data['reset_collections'] ?? false),
            'collections' => $this->csvList($data['collections'] ?? []),
        ];
        $res = (new DataEngineClient())->post('/jobs/rag-build-collections', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function jobs(): void
    {
        Support::requireAuth();
        $limit = (int)($_GET['limit'] ?? 20);
        $res = (new DataEngineClient())->get('/jobs', ['limit' => $limit]);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function job(array $params): void
    {
        Support::requireAuth();
        $id = (string)($params['id'] ?? '');
        $res = (new DataEngineClient())->get('/jobs/' . rawurlencode($id));
        Support::json($res, ($res['ok'] ?? false) ? 200 : 404);
    }


    public function cancelJob(array $params): void
    {
        Support::requireAdmin();
        $id = (string)($params['id'] ?? '');
        $res = (new DataEngineClient())->post('/jobs/' . rawurlencode($id) . '/cancel', []);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function cancelAllJobs(): void
    {
        Support::requireAdmin();
        $res = (new DataEngineClient())->post('/jobs/cancel-all', []);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    private function csvList(mixed $value): array
    {
        if (is_array($value)) {
            return array_values(array_filter(array_map('trim', array_map('strval', $value))));
        }
        return array_values(array_filter(array_map('trim', explode(',', (string)$value))));
    }
}
