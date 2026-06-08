<?php
final class CsvImporter
{
    public function import(string $filePath, string $delimiter = ',', int $chunk = 1000, bool $replace = false): array
    {
        $table = 'silabos';
        return (new DataEngineClient())->post('/duckdb/import', [
            'file_path' => $filePath,
            'table' => $table,
            'delimiter' => $delimiter,
            'replace' => $replace,
            'normalize_columns' => true,
        ]);
    }
}
