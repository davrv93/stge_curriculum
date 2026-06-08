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


def find_method_bounds(src: str, method_name: str):
    m = re.search(rf"\bpublic\s+function\s+{re.escape(method_name)}\s*\(", src)
    if not m:
        m = re.search(rf"\bprivate\s+function\s+{re.escape(method_name)}\s*\(", src)
    if not m:
        return None

    brace = src.find("{", m.start())
    if brace == -1:
        return None

    depth = 0
    i = brace
    in_single = False
    in_double = False
    escape = False

    while i < len(src):
        ch = src[i]

        if escape:
            escape = False
            i += 1
            continue

        if ch == "\\":
            escape = True
            i += 1
            continue

        if ch == "'" and not in_double:
            in_single = not in_single
            i += 1
            continue

        if ch == '"' and not in_single:
            in_double = not in_double
            i += 1
            continue

        if in_single or in_double:
            i += 1
            continue

        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return (m.start(), i + 1)

        i += 1

    return None


def replace_method(src: str, method_name: str, new_method: str) -> str:
    bounds = find_method_bounds(src, method_name)
    if not bounds:
        raise SystemExit(f"No encontré el método {method_name}().")
    a, b = bounds
    return src[:a] + new_method.rstrip() + "\n" + src[b:]


new_execute = r'''
    public function execute(array $intent, string $question, array $options = []): array
    {
        $intentName = (string)($intent['intent'] ?? '');
        $collection = $intent['collection'] ?? null;
        $table = (string)($options['table'] ?? 'silabos');

        /*
         * Política de orquestación:
         * - FastIntent/DuckDB solo para datos exactos.
         * - Si FastIntent falla, es débil o no aplica, pasar a RAG + Ollama.
         * - Unknown ya no responde orientación repetitiva.
         * - La colección semántica por defecto es jomelai_knowledge.
         */

        if ($this->shouldTryFastFirst($question, $intentName)) {
            $fast = $this->runFastIntent($question, $table);

            if ($this->isStrongFastResult($fast, $question)) {
                return $this->decorateFastResult($fast, $question);
            }

            return $this->runRagGuidedAssistant($question, $collection, $fast);
        }

        if ($this->looksLikeProposalAnalysis($question)) {
            $semantic = $this->runProposalSemanticAnalysis($question);

            if (($semantic['ok'] ?? false) && !empty($semantic['answer'])) {
                return $semantic;
            }

            return $this->runRagGuidedAssistant($question, $collection, $semantic);
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

s = replace_method(s, "execute", new_execute)


# runUnknown: reemplazar siempre por fallback RAG.
if "private function runUnknown" in s:
    new_unknown = r'''
    private function runUnknown(string $question): array
    {
        return $this->runRagGuidedAssistant($question, null);
    }
'''
    s = replace_method(s, "runUnknown", new_unknown)


# runSemanticSearch: asegurar colección por defecto jomelai_knowledge.
s = s.replace(
    "$col    = $collection ?? 'silabos_general';",
    "$col    = $collection ?? $this->defaultRagCollection();"
)
s = s.replace(
    "$col = $collection ?? 'silabos_general';",
    "$col = $collection ?? $this->defaultRagCollection();"
)
s = s.replace(
    "$col    = $collection ?? 'jomelai_knowledge';",
    "$col    = $collection ?? $this->defaultRagCollection();"
)
s = s.replace(
    "$col = $collection ?? 'jomelai_knowledge';",
    "$col = $collection ?? $this->defaultRagCollection();"
)


helpers = r'''
    private function defaultRagCollection(): string
    {
        return Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge';
    }

    private function shouldTryFastFirst(string $question, string $intentName): bool
    {
        $q = Support::normalize($question);

        $semanticTokens = [
            'explica', 'explicame', 'analiza', 'analizar', 'compara', 'comparar',
            'interpreta', 'interpretar', 'recomienda', 'recomendar', 'propone',
            'proponer', 'genera propuesta', 'redacta', 'sustenta', 'justifica',
            'mejora', 'diseña', 'disena', 'elabora informe', 'informe curricular',
            'que opinas', 'orientame', 'guíame', 'guiame'
        ];

        foreach ($semanticTokens as $token) {
            if (str_contains($q, $token)) {
                return false;
            }
        }

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

        if ($sql === '' && empty($fast['query']) && empty($fast['chart'])) {
            return false;
        }

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

        $previousJson = $previous ? json_encode($previous, JSON_UNESCAPED_UNICODE) : '{}';

        $prompt = "Eres JoMelAI Curriculista UPeU. Responde en español, de forma útil y concreta.\n" .
            "La pregunta no pudo resolverse de forma exacta con DuckDB/FastIntent o no tuvo contexto suficiente en RAG.\n" .
            "No repitas una orientación genérica. Propón rutas concretas que el usuario puede pedir, usando ejemplos académicos.\n\n" .
            "Pregunta del usuario: {$question}\n\n" .
            "Resultado previo del motor de datos, si existe:\n{$previousJson}\n\n" .
            "Respuesta:";

        $answer = $this->aiSummarize($prompt, 500);

        if (trim($answer) === '' || str_contains($answer, 'No se pudo generar')) {
            $answer = "Puedo ayudarte con rutas concretas: listar cursos por carrera o ciclo, contar sílabos cargados, generar gráficos de créditos u horas, consultar sumillas, comparar mallas o construir un informe curricular usando la colección {$col}.";
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


# Elimina helpers duplicados si ya existían, para evitar redeclare.
for name in [
    "defaultRagCollection",
    "shouldTryFastFirst",
    "isStrongFastResult",
    "decorateFastResult",
    "looksLikeAcademicDataQuestion",
    "runSmartStatistics",
    "runRagGuidedAssistant",
]:
    while True:
        bounds = find_method_bounds(s, name)
        if not bounds:
            break
        a, b = bounds
        s = s[:a] + s[b:]


marker = "    // ─── Helpers"
idx = s.find(marker)
if idx == -1:
    # fallback: insertar antes de mergeHybrid
    idx = s.find("    private function mergeHybrid")
if idx == -1:
    raise SystemExit("No encontré dónde insertar helpers.")

s = s[:idx] + helpers + "\n" + s[idx:]


# Ampliar tokens de looksLikeStructuredQuestion.
pattern = r"\$tokens\s*=\s*\[[^\]]*\];"
m = re.search(pattern, s)
if m and "looksLikeStructuredQuestion" in s[:m.start()]:
    tokens_line = "$tokens = ['cuantos', 'cuantas', 'cantidad', 'conteo', 'total', 'promedio', 'suma', 'ranking', 'top', 'grafico', 'grafica', 'barras', 'pastel', 'pie', 'torta', 'distribucion', 'por ciclo', 'por facultad', 'por programa', 'por carrera', 'por escuela', 'por sede', 'creditos', 'horas', 'lista', 'listar', 'listame', 'listarme', 'muestrame', 'mostrar', 'cursos', 'curso', 'carreras', 'carrera', 'programas', 'programa', 'malla', 'mallas', 'sumilla', 'sumillas', 'tienes cargadas', 'tienes cargados', 'cargadas', 'cargados'];"
    # Reemplaza solo la primera lista de tokens después del método.
    start_method = s.find("private function looksLikeStructuredQuestion")
    if start_method != -1:
        m2 = re.search(pattern, s[start_method:])
        if m2:
            a = start_method + m2.start()
            b = start_method + m2.end()
            s = s[:a] + tokens_line + s[b:]


p.write_text(s, encoding="utf-8")
print("OK: orquestador parcheado de forma idempotente.")
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

echo "==> Verificando funciones aplicadas"
grep -R "runRagGuidedAssistant\|defaultRagCollection\|shouldTryFastFirst" -n backend | head -20 || true

echo ""
echo "============================================================"
echo "Patch v2 aplicado."
echo "Ahora prueba desde la web:"
echo "- listame los cursos de enfermeria"
echo "- que carreras tienes cargadas"
echo "- explicame la malla de sistemas"
echo "============================================================"
