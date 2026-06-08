#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"

ORCH_FILE="$(find backend -type f -name "*.php" 2>/dev/null | xargs grep -l "final class JoMelAiOrchestrator" 2>/dev/null | head -1 || true)"

if [ -z "$ORCH_FILE" ]; then
  echo "ERROR: No encontré JoMelAiOrchestrator en backend/"
  exit 1
fi

echo "==> Orquestador: $ORCH_FILE"
cp "$ORCH_FILE" "$ORCH_FILE.bak.$TS"
echo "Backup: $ORCH_FILE.bak.$TS"

python3 - "$ORCH_FILE" <<'PY'
from pathlib import Path
import sys
import re

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

old_execute = r'''    public function execute(array $intent, string $question, array $options = []): array
    {
        $fastEligible = in_array((string)($intent['intent'] ?? ''), ['chart', 'statistics', 'report', 'curriculum_grid'], true);
        if ($fastEligible || $this->looksLikeStructuredQuestion($question)) {
            $fast = $this->runFastIntent($question, (string)($options['table'] ?? 'silabos'));
            if (($fast['ok'] ?? false) && (float)($fast['confidence'] ?? 0) >= 0.75) {
                return $fast;
            }
        }

        if ($this->looksLikeProposalAnalysis($question)) {
            return $this->runProposalSemanticAnalysis($question);
        }

        $fn = match ($intent['intent']) {
            'chart'               => fn() => $this->runChart($question),
            'statistics'          => fn() => $this->runStatistics($question),
            'semantic_search'     => fn() => $this->runSemanticSearch($question, $intent['collection']),
            'course_lookup'       => fn() => $this->runCourseHybrid($question, $intent['collection']),
            'comparison'          => fn() => $this->runComparison($question, $intent['collection']),
            'syllabus_generation' => fn() => $this->runSyllabusGeneration($question),
            'study_plan'          => fn() => $this->runStudyPlan($question),
            'curriculum_grid'     => fn() => $this->runCurriculumGrid($question),
            'report'              => fn() => $this->runReport($question, $intent['collection']),
            'dataset_quality'     => fn() => $this->runDatasetQuality($question),
            default               => fn() => $this->runUnknown($question),
        };

        return $fn();
    }
'''

new_execute = r'''    public function execute(array $intent, string $question, array $options = []): array
    {
        $intentName = (string)($intent['intent'] ?? '');
        $collection = $intent['collection'] ?? null;
        $table = (string)($options['table'] ?? 'silabos');

        /*
         * Política nueva:
         * 1) FastIntent solo se usa primero para preguntas estructuradas de datos.
         * 2) Si FastIntent falla, es débil o genera algo genérico, pasamos a RAG + Ollama.
         * 3) La orientación estática ya no es la respuesta por defecto.
         * 4) Todo fallback semántico usa la colección jomelai_knowledge.
         */
        if ($this->shouldTryFastFirst($question, $intentName)) {
            $fast = $this->runFastIntent($question, $table);

            if ($this->isStrongFastResult($fast, $question)) {
                return $this->decorateFastResult($fast, $question);
            }

            // Si era una pregunta de datos pero el fast no pudo resolver bien,
            // Ollama debe responder usando RAG como contexto, no orientación repetitiva.
            return $this->runRagGuidedAssistant($question, $collection, $fast);
        }

        if ($this->looksLikeProposalAnalysis($question)) {
            $semantic = $this->runProposalSemanticAnalysis($question);

            // Si el analizador rápido responde vacío o débil, enriquecer con RAG + Ollama.
            if (!($semantic['ok'] ?? false) || empty($semantic['answer'])) {
                return $this->runRagGuidedAssistant($question, $collection, $semantic);
            }

            return $semantic;
        }

        $fn = match ($intentName) {
            'chart'               => fn() => $this->runChart($question),
            'statistics'          => fn() => $this->runSmartStatistics($question, $collection),
            'semantic_search'     => fn() => $this->runSemanticSearch($question, $collection),
            'course_lookup'       => fn() => $this->runCourseHybrid($question, $collection),
            'comparison'          => fn() => $this->runComparison($question, $collection),
            'syllabus_generation' => fn() => $this->runSyllabusGeneration($question),
            'study_plan'          => fn() => $this->runStudyPlan($question),
            'curriculum_grid'     => fn() => $this->runCurriculumGrid($question),
            'report'              => fn() => $this->runReport($question, $collection),
            'dataset_quality'     => fn() => $this->runDatasetQuality($question),
            default               => fn() => $this->runRagGuidedAssistant($question, $collection),
        };

        return $fn();
    }
'''

if old_execute not in s:
    raise SystemExit("No encontré el execute() original esperado. Revisa si ya fue modificado.")
s = s.replace(old_execute, new_execute)

# Reemplazar default de colección RAG.
s = s.replace(
    "$col    = $collection ?? 'silabos_general';",
    "$col    = $collection ?? $this->defaultRagCollection();"
)
s = s.replace(
    "$col = $collection ?? 'silabos_general';",
    "$col = $collection ?? $this->defaultRagCollection();"
)

# Reemplazar runUnknown estático por fallback RAG + Ollama.
old_unknown = r'''    /** unknown → orientación */
    private function runUnknown(string $question): array
    {
        return [
            'ok'      => true,
            'answer'  => 'Puedo ayudarte a buscar información en sílabos, generar gráficos, comparar cursos, crear propuestas de sílabo, revisar mallas curriculares o generar reportes. Reformula tu solicitud indicando qué deseas obtener.',
            '_engine' => 'assistant',
            '_model'  => $this->model,
        ];
    }
'''

new_unknown = r'''    /** unknown → RAG + Ollama; la orientación estática solo queda como último fallback. */
    private function runUnknown(string $question): array
    {
        return $this->runRagGuidedAssistant($question, null);
    }
'''

if old_unknown in s:
    s = s.replace(old_unknown, new_unknown)
else:
    print("AVISO: No encontré runUnknown original; no se reemplazó.")

# Insertar helpers antes de // ─── Helpers
helpers = r'''
    private function defaultRagCollection(): string
    {
        return Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge';
    }

    private function shouldTryFastFirst(string $question, string $intentName): bool
    {
        $q = Support::normalize($question);

        // Si el usuario pide redactar, explicar, comparar, analizar o proponer,
        // no conviene cerrarlo con FastIntent.
        $semanticTokens = [
            'explica', 'explicame', 'analiza', 'analizar', 'compara', 'comparar',
            'interpreta', 'interpretar', 'recomienda', 'recomendar', 'propone',
            'proponer', 'genera propuesta', 'redacta', 'sustenta', 'justifica',
            'mejora', 'diseña', 'disena', 'elabora informe', 'informe curricular'
        ];

        foreach ($semanticTokens as $token) {
            if (str_contains($q, $token)) {
                return false;
            }
        }

        // Intents explícitamente estructurados.
        if (in_array($intentName, ['chart', 'statistics', 'curriculum_grid', 'dataset_quality'], true)) {
            return true;
        }

        return $this->looksLikeStructuredQuestion($question) || $this->looksLikeAcademicDataQuestion($question);
    }

    private function isStrongFastResult(array $fast, string $question): bool
    {
        if (!($fast['ok'] ?? false)) {
            return false;
        }

        $confidence = (float)($fast['confidence'] ?? ($fast['spec']['confidence'] ?? 0));
        $mode = (string)($fast['spec']['mode'] ?? $fast['mode'] ?? '');
        $reportIntent = (string)($fast['spec']['report_intent'] ?? $fast['report_intent'] ?? '');
        $sql = (string)($fast['sql'] ?? ($fast['spec']['sql'] ?? ''));

        // Si no hay SQL ni chart/query, no es un resultado fuerte.
        if ($sql === '' && empty($fast['query']) && empty($fast['chart'])) {
            return false;
        }

        // Listados, conteos y gráficos estructurados son aceptables con confianza media.
        if ($mode === 'sql' || $mode === 'chart' || str_contains($reportIntent, 'list')) {
            return $confidence >= 0.60;
        }

        return $confidence >= 0.82;
    }

    private function decorateFastResult(array $fast, string $question): array
    {
        $mode = (string)($fast['spec']['mode'] ?? $fast['mode'] ?? '');
        $reportIntent = (string)($fast['spec']['report_intent'] ?? $fast['report_intent'] ?? '');

        if ($mode === 'chart') {
            $fast['answer'] = 'Generé el gráfico con DuckDB usando datos estructurados. Para interpretación o conclusiones, puedo complementar con contexto RAG.';
        } elseif (str_contains($reportIntent, 'list')) {
            $fast['answer'] = 'Encontré el listado solicitado en la base académica cargada.';
        } else {
            $fast['answer'] = 'Consulta resuelta con DuckDB sobre la base académica cargada.';
        }

        $fast['_routing_policy'] = 'fast_exact_data';
        return $fast;
    }

    private function looksLikeAcademicDataQuestion(string $question): bool
    {
        $q = Support::normalize($question);

        $actionTokens = [
            'lista', 'listar', 'listame', 'listarme', 'muestrame', 'mostrar',
            'ver', 'dame', 'que', 'cuales', 'cuantos', 'cuantas', 'grafico',
            'grafica', 'calcula', 'consulta', 'busca', 'buscar'
        ];

        $domainTokens = [
            'curso', 'cursos', 'silabo', 'silabos', 'carrera', 'carreras',
            'programa', 'programas', 'escuela', 'escuelas', 'facultad',
            'facultades', 'ciclo', 'ciclos', 'credito', 'creditos',
            'hora', 'horas', 'sumilla', 'sumillas', 'enfermeria',
            'sistemas', 'administracion', 'negocios internacionales',
            'malla', 'mallas', 'plan de estudios', 'tienes cargadas',
            'tienes cargados', 'cargadas', 'cargados'
        ];

        $hasAction = false;
        foreach ($actionTokens as $token) {
            if (str_contains($q, $token)) {
                $hasAction = true;
                break;
            }
        }

        $hasDomain = false;
        foreach ($domainTokens as $token) {
            if (str_contains($q, $token)) {
                $hasDomain = true;
                break;
            }
        }

        return $hasAction && $hasDomain;
    }

    private function runSmartStatistics(string $question, ?string $collection): array
    {
        $fast = $this->runFastIntent($question, 'silabos');

        if ($this->isStrongFastResult($fast, $question)) {
            return $this->decorateFastResult($fast, $question);
        }

        return $this->runRagGuidedAssistant($question, $collection, $fast);
    }

    private function runRagGuidedAssistant(string $question, ?string $collection = null, array $previous = []): array
    {
        $col = $collection ?: $this->defaultRagCollection();

        $rag = [];
        try {
            $rag = $this->engine->post('/rag/answer', [
                'question'   => $question,
                'collection' => $col,
                'model'      => $this->model,
                'n_results'  => 6,
            ]);
        } catch (Throwable $e) {
            $rag = [
                'ok' => false,
                'answer' => '',
                'sources' => [],
                'message' => $e->getMessage(),
            ];
        }

        $ragAnswer = trim((string)($rag['answer'] ?? ''));
        $sources = $rag['sources'] ?? $rag['evidence'] ?? [];

        // Si /rag/answer ya generó buena respuesta, úsala.
        if (($rag['ok'] ?? false) && $ragAnswer !== '') {
            return [
                'ok'       => true,
                'answer'   => $ragAnswer,
                'evidence' => $sources,
                '_engine'  => 'rag_guided_assistant',
                '_model'   => $this->model,
                '_collection' => $col,
                '_previous_engine' => $previous['_engine'] ?? null,
            ];
        }

        // Último intento: Ollama con una orientación dinámica, no repetitiva.
        $previousJson = $previous ? json_encode($previous, JSON_UNESCAPED_UNICODE) : '{}';

        $prompt = "Eres JoMelAI Curriculista UPeU. Responde en español, de forma útil y concreta.\n" .
            "La pregunta no pudo resolverse de forma exacta con DuckDB/FastIntent o no tuvo contexto suficiente en RAG.\n" .
            "No repitas una orientación genérica. Propón 3 a 5 rutas concretas que el usuario puede pedir, usando ejemplos académicos.\n\n" .
            "Pregunta del usuario: {$question}\n\n" .
            "Resultado previo del motor de datos, si existe:\n{$previousJson}\n\n" .
            "Respuesta:";

        $answer = $this->aiSummarize($prompt, 500);

        if (trim($answer) === '' || str_contains($answer, 'No se pudo generar')) {
            $answer = "Puedo ayudarte de forma más precisa si eliges una de estas rutas: listar cursos por carrera o ciclo, contar sílabos cargados, generar gráficos de créditos u horas, consultar sumillas, comparar mallas o construir un informe curricular con la colección {$col}.";
        }

        return [
            'ok'       => true,
            'answer'   => $answer,
            'evidence' => $sources,
            '_engine'  => 'rag_or_ollama_fallback',
            '_model'   => $this->model,
            '_collection' => $col,
            '_previous_engine' => $previous['_engine'] ?? null,
        ];
    }

'''

if helpers.strip() not in s:
    marker = "    // ─── Helpers"
    idx = s.find(marker)
    if idx == -1:
        raise SystemExit("No encontré marcador // ─── Helpers.")
    s = s[:idx] + helpers + "\n" + s[idx:]

# Ampliar looksLikeStructuredQuestion.
old_tokens = "$tokens = ['cuantos', 'cantidad', 'conteo', 'total', 'promedio', 'suma', 'ranking', 'top', 'grafico', 'grafica', 'barras', 'pastel', 'distribucion', 'por ciclo', 'por facultad', 'por programa', 'por sede', 'creditos', 'horas'];"
new_tokens = "$tokens = ['cuantos', 'cuantas', 'cantidad', 'conteo', 'total', 'promedio', 'suma', 'ranking', 'top', 'grafico', 'grafica', 'barras', 'pastel', 'pie', 'torta', 'distribucion', 'por ciclo', 'por facultad', 'por programa', 'por carrera', 'por escuela', 'por sede', 'creditos', 'horas', 'lista', 'listar', 'listame', 'listarme', 'muestrame', 'mostrar', 'cursos', 'curso', 'carreras', 'carrera', 'programas', 'programa', 'malla', 'mallas', 'sumilla', 'sumillas', 'tienes cargadas', 'tienes cargados', 'cargadas', 'cargados'];"

if old_tokens in s:
    s = s.replace(old_tokens, new_tokens)

p.write_text(s, encoding="utf-8")
print("OK: política RAG/Fast/Ollama aplicada.")
PY

echo "==> Reconstruyendo backend"
docker compose build --no-cache backend
docker compose up -d --force-recreate backend

echo "==> Validando PHP dentro del contenedor backend"
CONTAINER_ORCH="$(docker compose exec -T backend sh -lc "grep -R -l 'final class JoMelAiOrchestrator' /var/www/app /app /var/www/html 2>/dev/null | head -1" || true)"

if [ -n "$CONTAINER_ORCH" ]; then
  docker compose exec -T backend php -l "$CONTAINER_ORCH"
else
  echo "AVISO: No encontré JoMelAiOrchestrator dentro del contenedor. Se omite php -l."
fi

echo "==> Probando colección RAG por defecto desde backend/data-engine"
curl -s http://localhost:3000/api/data-engine/rag/answer \
  -H "Content-Type: application/json" \
  -d '{"question":"qué información tienes cargada sobre ingeniería de sistemas","collection":"jomelai_knowledge","n_results":3}' | python3 -m json.tool || true

echo ""
echo "============================================================"
echo "Patch aplicado."
echo "Cambios clave:"
echo "- FastIntent solo queda como ruta de datos exactos."
echo "- Unknown/orientación ahora usa RAG + Ollama."
echo "- RAG usa jomelai_knowledge por defecto."
echo "- Si FastIntent falla o responde débil, pasa a Ollama con contexto."
echo "============================================================"
