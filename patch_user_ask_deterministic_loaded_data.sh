#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"

TARGET="$(grep -R -l "public function userAsk" backend 2>/dev/null | head -1 || true)"

if [ -z "$TARGET" ]; then
  echo "ERROR: No encontré public function userAsk en backend/"
  exit 1
fi

echo "Archivo userAsk: $TARGET"
cp "$TARGET" "$TARGET.bak.$TS"
echo "Backup: $TARGET.bak.$TS"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

helpers = r'''
    private function normalizeAskText(string $text): string
    {
        return Support::normalize($text);
    }

    private function isLoadedProgramsQuestion(string $question): bool
    {
        $q = $this->normalizeAskText($question);

        $asksLoaded = str_contains($q, 'cargada')
            || str_contains($q, 'cargadas')
            || str_contains($q, 'cargado')
            || str_contains($q, 'cargados')
            || str_contains($q, 'tienes')
            || str_contains($q, 'disponible')
            || str_contains($q, 'disponibles')
            || str_contains($q, 'registrada')
            || str_contains($q, 'registradas');

        $asksPrograms = str_contains($q, 'carrera')
            || str_contains($q, 'carreras')
            || str_contains($q, 'programa')
            || str_contains($q, 'programas')
            || str_contains($q, 'escuela')
            || str_contains($q, 'escuelas');

        $asksWhat = str_contains($q, 'que')
            || str_contains($q, 'cuales')
            || str_contains($q, 'lista')
            || str_contains($q, 'listar')
            || str_contains($q, 'muestrame')
            || str_contains($q, 'mostrar')
            || str_contains($q, 'dame');

        return $asksPrograms && ($asksLoaded || $asksWhat);
    }

    private function answerLoadedProgramsQuestion(string $table = 'silabos'): array
    {
        $sql = "SELECT DISTINCT programa_estudio, facultad, modalidad_estudio, sede " .
            "FROM {$table} " .
            "WHERE programa_estudio IS NOT NULL " .
            "AND TRIM(CAST(programa_estudio AS VARCHAR)) <> '' " .
            "ORDER BY programa_estudio " .
            "LIMIT 300";

        $query = (new DataEngineClient())->post('/duckdb/query', [
            'sql' => $sql,
            'limit' => 300,
        ]);

        $rows = $query['rows'] ?? [];
        $columns = [];

        if (is_array($rows) && !empty($rows) && is_array($rows[0] ?? null)) {
            $columns = array_keys($rows[0]);
        }

        return [
            'ok' => (bool)($query['ok'] ?? false),
            'intent' => 'statistics',
            'visible_intent' => 'Consultar datos académicos',
            'mode' => 'sql',
            'message' => '',
            'summary' => 'Carreras cargadas en la base académica.',
            'answer' => 'Encontré las carreras cargadas en la base académica.',
            'chart_url' => null,
            'data_url' => null,
            'chart' => null,
            'table' => [
                'columns' => $columns,
                'rows' => $rows,
                'row_count' => $query['row_count'] ?? count($rows),
            ],
            'query' => $query,
            'sql' => $sql,
            'evidence' => [],
            'actions' => [],
            'suggestions' => [
                'Listar cursos de una carrera',
                'Generar gráfico por carrera',
                'Comparar créditos por ciclo'
            ],
            '_engine' => 'user_ask_deterministic_loaded_programs',
            '_model' => 'no_ollama',
        ];
    }
'''

if "isLoadedProgramsQuestion" not in s:
    last = s.rfind("}")
    if last == -1:
        raise SystemExit("No encontré cierre de clase.")
    s = s[:last] + "\n" + helpers + "\n" + s[last:]
    print("OK helpers agregados")
else:
    print("OK helpers ya existían")

needle = """        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe tu pregunta.'], 422);
            return;
        }
"""

insert = """        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe tu pregunta.'], 422);
            return;
        }

        /*
         * Regla determinística crítica:
         * "qué carreras tienes cargadas" NO debe ir a Ollama ni a FastIntent abierto.
         * Debe listar DISTINCT programa_estudio desde DuckDB.
         */
        if ($mode === 'auto' && $this->isLoadedProgramsQuestion($question)) {
            $loadedPrograms = $this->answerLoadedProgramsQuestion($table);

            if (($loadedPrograms['ok'] ?? false)) {
                $this->saveRun(
                    (int)$user['id'],
                    'no_ollama',
                    'user_loaded_programs',
                    $question,
                    (string)($loadedPrograms['answer'] ?? 'Carreras cargadas consultadas.'),
                    $loadedPrograms
                );

                Support::json($loadedPrograms);
                return;
            }
        }
"""

if "user_loaded_programs" not in s:
    if needle not in s:
        raise SystemExit("No encontré el bloque de validación question === ''.")
    s = s.replace(needle, insert)
    print("OK gate deterministic agregado")
else:
    print("OK gate deterministic ya existía")

p.write_text(s, encoding="utf-8")
print("OK userAsk parchado:", p)
PY

echo "==> Reconstruyendo backend"
docker compose build --no-cache backend
docker compose up -d --force-recreate backend

echo "==> Validando que el contenedor tenga el patch"
docker compose exec -T backend sh -lc "grep -R 'user_loaded_programs\|isLoadedProgramsQuestion' -n /var/www/app /app /var/www/html 2>/dev/null | head -40" || true

echo ""
echo "============================================================"
echo "Patch aplicado."
echo "Prueba:"
echo '{"question":"que carreras tienes cargadas","mode":"auto","table":"silabos"}'
echo "============================================================"
