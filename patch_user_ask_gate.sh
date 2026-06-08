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
    private function looksLikeAcademicLoadedDataQuestion(string $question): bool
    {
        $q = Support::normalize($question);

        $actionTokens = [
            'que', 'qué', 'cuales', 'cuáles',
            'lista', 'listar', 'listame', 'listarme',
            'muestrame', 'muéstrame', 'mostrar',
            'dame', 'ver', 'consulta', 'consultar',
            'cuantos', 'cuántos', 'cuantas', 'cuántas',
            'grafico', 'gráfico', 'grafica', 'gráfica',
            'barras', 'pie', 'pastel', 'torta'
        ];

        $domainTokens = [
            'carrera', 'carreras', 'programa', 'programas',
            'escuela', 'escuelas', 'facultad', 'facultades',
            'curso', 'cursos', 'asignatura', 'asignaturas',
            'silabo', 'sílabo', 'silabos', 'sílabos',
            'ciclo', 'ciclos', 'credito', 'crédito',
            'creditos', 'créditos', 'hora', 'horas',
            'sumilla', 'sumillas', 'malla', 'mallas',
            'plan de estudios', 'enfermeria', 'enfermería',
            'sistemas', 'administracion', 'administración',
            'negocios internacionales', 'contabilidad',
            'psicologia', 'psicología', 'medicina',
            'nutricion', 'nutrición', 'teologia', 'teología',
            'arquitectura', 'civil', 'ambiental'
        ];

        $loadedTokens = [
            'cargada', 'cargadas', 'cargado', 'cargados',
            'tienes', 'registrada', 'registradas',
            'registrado', 'registrados', 'disponible',
            'disponibles', 'base', 'duckdb'
        ];

        $hasAction = false;
        foreach ($actionTokens as $token) {
            if (str_contains($q, Support::normalize($token))) {
                $hasAction = true;
                break;
            }
        }

        $hasDomain = false;
        foreach ($domainTokens as $token) {
            if (str_contains($q, Support::normalize($token))) {
                $hasDomain = true;
                break;
            }
        }

        $hasLoaded = false;
        foreach ($loadedTokens as $token) {
            if (str_contains($q, Support::normalize($token))) {
                $hasLoaded = true;
                break;
            }
        }

        return ($hasAction && $hasDomain) || ($hasLoaded && $hasDomain);
    }


    private function answerAcademicLoadedDataQuestion(string $question, string $table = 'silabos'): array
    {
        $engine = new DataEngineClient();

        $spec = $engine->post('/intent/resolve', [
            'question' => $question,
            'table' => $table ?: 'silabos',
        ]);

        if (!($spec['ok'] ?? false) || empty($spec['sql'])) {
            return [
                'ok' => false,
                'message' => 'No se pudo resolver la consulta académica estructurada.',
                'spec' => $spec,
            ];
        }

        $mode = (string)($spec['mode'] ?? 'sql');

        if ($mode === 'chart') {
            $chart = $engine->post('/duckdb/chart', [
                'sql' => $spec['sql'],
                'chart_type' => $spec['chart_type'] ?? 'bar',
                'title' => $spec['title'] ?? 'Reporte académico',
                'x' => $spec['x'] ?? null,
                'y' => $spec['y'] ?? null,
                'limit' => 200,
            ]);

            return [
                'ok' => (bool)($chart['ok'] ?? false),
                'mode' => 'chart',
                'answer' => 'Gráfico generado con DuckDB sobre la base académica cargada.',
                'chart' => $chart,
                'spec' => $spec,
                'sql' => $spec['sql'],
                '_engine' => 'user_ask_academic_gate_chart',
                '_model' => 'no_ollama',
            ];
        }

        $query = $engine->post('/duckdb/query', [
            'sql' => $spec['sql'],
            'limit' => 300,
        ]);

        return [
            'ok' => (bool)($query['ok'] ?? false),
            'mode' => 'sql',
            'answer' => 'Consulta resuelta con DuckDB sobre la base académica cargada.',
            'query' => $query,
            'spec' => $spec,
            'sql' => $spec['sql'],
            '_engine' => 'user_ask_academic_gate_sql',
            '_model' => 'no_ollama',
        ];
    }

'''

if "answerAcademicLoadedDataQuestion" not in s:
    last = s.rfind("}")
    if last == -1:
        raise SystemExit("No encontré cierre de clase")
    s = s[:last] + "\n" + helpers + "\n" + s[last:]


needle = """        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe tu pregunta.'], 422);
            return;
        }
"""

insert = """        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe tu pregunta.'], 422);
            return;
        }

        if ($mode === 'auto' && $this->looksLikeAcademicLoadedDataQuestion($question)) {
            $academic = $this->answerAcademicLoadedDataQuestion($question, $table);

            if (($academic['ok'] ?? false)) {
                $this->saveRun(
                    (int)$user['id'],
                    'no_ollama',
                    'user_academic_data',
                    $question,
                    (string)($academic['answer'] ?? 'Consulta académica resuelta.'),
                    $academic
                );

                Support::json($academic);
                return;
            }
        }
"""

if needle in s and "user_academic_data" not in s:
    s = s.replace(needle, insert)
elif "user_academic_data" in s:
    print("OK gate académico ya existía")
else:
    raise SystemExit("No encontré bloque de validación question === ''")


s = s.replace(
    "$collection = trim((string)($data['collection'] ?? 'silabos'));",
    "$collection = trim((string)($data['collection'] ?? 'jomelai_knowledge'));"
)

s = s.replace(
    "if ($collection === 'silabos' || $collection === '') {\n            $collection = $this->decideCollection($question);\n        }",
    "if ($collection === 'silabos' || $collection === '' || $collection === 'auto') {\n            $collection = Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge';\n        }"
)

s = s.replace(
    "$rag = (new DataEngineClient())->post('/rag/search', [\n            'query' => $question,\n            'collection' => $collection,\n            'n_results' => (int)($data['n_results'] ?? 5),\n        ]);",
    "$rag = (new DataEngineClient())->post('/rag/answer', [\n            'question' => $question,\n            'collection' => $collection,\n            'model' => $model,\n            'n_results' => (int)($data['n_results'] ?? 5),\n        ]);"
)

old_prompt_block = """        $prompt = CurriculumGuidelines::systemPrompt() . "\\n\\nResponde a un usuario academico usando solo los fragmentos recuperados como evidencia. Si faltan datos, dilo con claridad. Mantén lenguaje compatible con identidad adventista y evita términos ajenos al marco institucional.\\n\\nFragmentos:\\n" . json_encode($rag['results'] ?? [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT) . "\\n\\nPregunta:\\n{$question}";
        $ollama = (new OllamaClient())->generate($prompt, $model, ['temperature' => 0.12]);
        $answer = (string)($ollama['response'] ?? 'No se pudo generar respuesta.');

        $this->saveRun((int)$user['id'], $model, 'user_rag', $question, $answer, ['rag' => $rag]);

        Support::json([
            'ok' => true,
            'mode' => 'rag',
            'collection' => $collection,
            'answer' => $answer,
            'rag' => $rag,
        ]);
"""

new_prompt_block = """        $answer = (string)($rag['answer'] ?? '');

        if ($answer === '') {
            $answer = 'No encontré contexto suficiente en la colección seleccionada.';
        }

        $this->saveRun((int)$user['id'], $model, 'user_rag_answer', $question, $answer, ['rag' => $rag]);

        Support::json([
            'ok' => true,
            'mode' => 'rag',
            'collection' => $collection,
            'answer' => $answer,
            'rag' => $rag,
            'evidence' => $rag['sources'] ?? $rag['evidence'] ?? [],
        ]);
"""

if old_prompt_block in s:
    s = s.replace(old_prompt_block, new_prompt_block)
else:
    print("AVISO: no encontré bloque de prompt RAG antiguo; quizá ya está modificado.")


p.write_text(s, encoding="utf-8")
print("OK userAsk parchado")
PY

docker compose build --no-cache backend
docker compose up -d --force-recreate backend

CONTAINER_TARGET="$(docker compose exec -T backend sh -lc "grep -R -l 'user_academic_data' /var/www/app /app /var/www/html 2>/dev/null | head -1" || true)"

if [ -n "$CONTAINER_TARGET" ]; then
  docker compose exec -T backend php -l "$CONTAINER_TARGET"
else
  echo "AVISO: No encontré user_academic_data dentro del contenedor"
fi

echo "Patch aplicado. Prueba userAsk otra vez."
