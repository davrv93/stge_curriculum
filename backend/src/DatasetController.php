<?php
final class DatasetController
{
    public function status(): void
    {
        Support::requireAuth();
        $repo = new SyllabusRepository();
        $pdo = Database::pdo();
        $imports = $pdo->query('SELECT * FROM imports ORDER BY id DESC LIMIT 10')->fetchAll();
        Support::json(['ok' => true, 'stats' => $repo->stats(), 'imports' => $imports]);
    }

    public function upload(): void
    {
        Support::requireAdmin();
        $file = $_FILES['csv'] ?? $_FILES['file'] ?? null;
        if (!$file) {
            Support::json(['ok' => false, 'message' => 'Adjunta un archivo con el campo csv o file.'], 422);
            return;
        }
        if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            Support::json(['ok' => false, 'message' => 'Error al subir el archivo.', 'code' => $file['error'] ?? null], 422);
            return;
        }
        $original = $file['name'] ?? 'dataset.csv';
        $name = preg_replace('/[^a-zA-Z0-9._-]/', '_', $original) ?: 'dataset.csv';
        $kind = preg_replace('/[^a-zA-Z0-9_-]/', '_', (string)($_POST['kind'] ?? $_POST['table'] ?? 'dataset')) ?: 'dataset';
        $sharedDir = rtrim((string)Support::config('shared_csv_dir', '/data/syllabi'), '/');
        if (!is_dir($sharedDir)) {
            mkdir($sharedDir, 0775, true);
        }
        $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
        $allowed = ['csv', 'txt', 'tsv', 'json', 'md'];
        if (!in_array($ext, $allowed, true)) {
            Support::json(['ok' => false, 'message' => 'Formato no soportado para carga directa. Usa CSV/TSV/TXT/JSON/MD. Para ZIP, descomprímelo antes o conviértelo a CSV.'], 422);
            return;
        }
        // Conserva compatibilidad: si suben silabos.csv sin tabla explicita, actualiza el alias historico /data/syllabi/silabos.csv.
        $forceDefault = ($kind === 'silabos' || $kind === 'silabo') && $ext === 'csv';
        $targetName = $forceDefault ? 'silabos.csv' : date('Ymd_His') . '_' . $kind . '_' . $name;
        $target = $sharedDir . '/' . $targetName;
        $backup = null;
        if ($forceDefault && is_file($target)) {
            $backup = $sharedDir . '/' . date('Ymd_His') . '_backup_' . $name;
            @rename($target, $backup);
        }
        if (!move_uploaded_file($file['tmp_name'], $target)) {
            Support::json(['ok' => false, 'message' => 'No se pudo guardar el archivo en el volumen compartido /data/syllabi. Revisa permisos del directorio data/.'], 500);
            return;
        }
        Support::json([
            'ok' => true,
            'file_path' => $target,
            'name' => basename($target),
            'kind' => $kind,
            'size_mb' => round(filesize($target) / 1024 / 1024, 2),
            'backup_previous' => $backup,
            'message' => 'Archivo cargado correctamente al volumen compartido. Ya puedes perfilarlo, importarlo a DuckDB o crear RAG desde Acceso técnico.'
        ]);
    }

    public function import(): void
    {
        Support::requireAdmin();
        $data = Support::readJson();
        $filePath = trim((string)($data['file_path'] ?? $data['path'] ?? Support::config('default_csv_path')));
        $delimiter = (string)($data['delimiter'] ?? Support::config('default_csv_delimiter'));
        $chunk = (int)($data['chunk_size'] ?? Support::config('default_csv_chunk'));
        $replace = (bool)($data['replace'] ?? false);
        $result = (new CsvImporter())->import($filePath, $delimiter, $chunk, $replace);
        Support::json(['ok' => true, 'result' => $result]);
    }

    public function sampleImport(): void
    {
        Support::requireAdmin();
        $path = __DIR__ . '/../storage/uploads/sample_silabos.csv';
        if (!is_file($path)) {
            copy(__DIR__ . '/../scripts/sample_silabos.csv', $path);
        }
        $result = (new CsvImporter())->import($path, ',', 100, true);
        Support::json(['ok' => true, 'result' => $result, 'message' => 'Data demo importada.']);
    }
}
