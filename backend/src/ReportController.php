<?php
final class ReportController
{
    public function summary(): void
    {
        Support::requireAuth();
        $pdo = Database::pdo();
        $repo = new SyllabusRepository();
        $stats = $repo->stats();
        $byProgram = $pdo->query("SELECT COALESCE(NULLIF(programa, ''), 'Sin programa') AS programa, COUNT(*) AS total FROM syllabi GROUP BY programa ORDER BY total DESC LIMIT 20")->fetchAll();
        $byCycle = $pdo->query("SELECT COALESCE(NULLIF(ciclo, ''), 'Sin ciclo') AS ciclo, COUNT(*) AS total FROM syllabi GROUP BY ciclo ORDER BY ciclo ASC LIMIT 30")->fetchAll();
        $quality = $pdo->query("SELECT
            SUM(CASE WHEN competencia IS NULL OR competencia = '' THEN 1 ELSE 0 END) AS sin_competencia,
            SUM(CASE WHEN sumilla IS NULL OR sumilla = '' THEN 1 ELSE 0 END) AS sin_sumilla,
            SUM(CASE WHEN evaluacion IS NULL OR evaluacion = '' THEN 1 ELSE 0 END) AS sin_evaluacion,
            SUM(CASE WHEN bibliografia IS NULL OR bibliografia = '' THEN 1 ELSE 0 END) AS sin_bibliografia
            FROM syllabi")->fetch();

        $markdown = $this->buildMarkdown($stats, $byProgram, $byCycle, $quality ?: []);
        Support::json([
            'ok' => true,
            'stats' => $stats,
            'by_program' => $byProgram,
            'by_cycle' => $byCycle,
            'quality' => $quality,
            'markdown' => $markdown,
        ]);
    }

    private function buildMarkdown(array $stats, array $byProgram, array $byCycle, array $quality): string
    {
        $lines = [];
        $lines[] = '# Reporte curricular preliminar de sílabos';
        $lines[] = '';
        $lines[] = '## Resumen';
        $lines[] = '- Sílabos indexados: ' . ($stats['total'] ?? 0);
        $lines[] = '- Programas detectados: ' . ($stats['programs'] ?? 0);
        $lines[] = '- Cursos distintos detectados: ' . ($stats['courses'] ?? 0);
        $lines[] = '';
        $lines[] = '## Calidad mínima de campos';
        $lines[] = '- Sin competencia registrada: ' . ($quality['sin_competencia'] ?? 0);
        $lines[] = '- Sin sumilla registrada: ' . ($quality['sin_sumilla'] ?? 0);
        $lines[] = '- Sin evaluación registrada: ' . ($quality['sin_evaluacion'] ?? 0);
        $lines[] = '- Sin bibliografía registrada: ' . ($quality['sin_bibliografia'] ?? 0);
        $lines[] = '';
        $lines[] = '## Top programas';
        foreach ($byProgram as $row) {
            $lines[] = '- ' . $row['programa'] . ': ' . $row['total'];
        }
        $lines[] = '';
        $lines[] = '## Distribución por ciclo';
        foreach ($byCycle as $row) {
            $lines[] = '- ' . $row['ciclo'] . ': ' . $row['total'];
        }
        $lines[] = '';
        $lines[] = '## Lectura curricular';
        $lines[] = 'Este reporte no reemplaza la revisión de comité curricular. Debe usarse como insumo para detectar vacíos de alineación entre competencia, resultados, evidencias, metodología y evaluación.';
        return implode("\n", $lines);
    }
}
