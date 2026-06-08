<?php
final class CompatibilityController
{
    public function syllabiStats(): void { Support::requireAuth(); Support::json((new DataEngineClient())->get('/fs/status')); }
    public function enginePing(): void { Support::requireAuth(); Support::json((new DataEngineClient())->get('/health')); }
    public function engineTables(): void { Support::requireAuth(); Support::json((new DataEngineClient())->get('/duckdb/tables')); }
    public function setupStatus(): void { (new SetupController())->status(); }
    public function listCsv(): void { (new SetupController())->csvFiles(); }
    public function profileCsv(): void { (new SetupController())->profileCsv(); }
    public function uploadCsv(): void { (new DatasetController())->upload(); }
    public function pullModel(): void { (new SetupController())->pullModelJob(); }
    public function pullBaseModels(): void
    {
        Support::requireAdmin();
        Support::json(['ok' => true, 'message' => 'Usa Acceso técnico para descargar modelos uno por uno. No se reinstalan modelos existentes.']);
    }
    public function duckImport(): void { (new SetupController())->duckdbJob(); }
    public function duckQuery(): void { (new DataEngineController())->queryDuckdb(); }
    public function naturalSql(): void { (new DataEngineController())->naturalSql(); }
    public function ragBuild(): void { (new SetupController())->ragJob(); }
    public function ragBuildCollections(): void { (new SetupController())->ragCollectionsJob(); }
    public function ragSearch(): void { (new DataEngineController())->searchRag(); }
    public function ragAnswer(): void { (new DataEngineController())->ragAnswer(); }
    public function ollamaModels(): void { Support::requireAuth(); Support::json((new OllamaClient())->models()); }
    public function notImplemented(string $what): void { Support::requireAuth(); Support::json(['ok' => false, 'message' => 'Aún no implementado: ' . $what], 422); }
}
