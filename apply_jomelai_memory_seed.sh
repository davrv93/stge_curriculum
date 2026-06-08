#!/usr/bin/env bash
set -euo pipefail

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

APP="data-engine/app.py"
JOMELAI_CONTROLLER="$(find backend -name 'JoMelAiController.php' | head -1)"

if [ ! -f "$APP" ]; then
  echo "ERROR: No existe $APP"
  exit 1
fi

if [ -z "$JOMELAI_CONTROLLER" ] || [ ! -f "$JOMELAI_CONTROLLER" ]; then
  echo "ERROR: No encontré JoMelAiController.php"
  exit 1
fi

echo "==> Data engine: $APP"
echo "==> JoMelAI controller: $JOMELAI_CONTROLLER"

cp "$APP" "${APP}.bak_memory_$(date +%Y%m%d_%H%M%S)"
cp "$JOMELAI_CONTROLLER" "${JOMELAI_CONTROLLER}.bak_memory_$(date +%Y%m%d_%H%M%S)"

echo "==> Parcheando data-engine con endpoints de memoria..."

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("data-engine/app.py")
text = path.read_text(encoding="utf-8")

# 1) Agregar modelos Pydantic si no existen.
models = r'''

class MemoryUpsertRequest(BaseModel):
    question: str
    answer: str
    collection: str = Field(default="jomelai_memory")
    intent: str = Field(default="curricular_advice")
    topic: str = Field(default="")
    artifact_type: str = Field(default="generated_answer")
    approved: bool = Field(default=True)
    metadata: Dict[str, Any] = Field(default_factory=dict)


class MemorySearchRequest(BaseModel):
    query: str
    collection: str = Field(default="jomelai_memory")
    n_results: int = Field(default=5, ge=1, le=20)

'''

if "class MemoryUpsertRequest" not in text:
    marker = "class RagSearchRequest(BaseModel):"
    if marker not in text:
        print("ERROR: No encontré class RagSearchRequest(BaseModel).")
        sys.exit(1)
    text = text.replace(marker, models + "\n" + marker, 1)
    print("OK: modelos MemoryUpsertRequest/MemorySearchRequest agregados.")
else:
    print("INFO: modelos de memoria ya existen.")

# 2) Agregar endpoints antes de templates o al final antes de alguna ruta.
endpoints = r'''

@api.post("/memory/upsert")
def memory_upsert(req: MemoryUpsertRequest) -> Dict[str, Any]:
    if chromadb is None:
        raise HTTPException(status_code=500, detail="ChromaDB no esta disponible.")

    question = (req.question or "").strip()
    answer = (req.answer or "").strip()

    if not question or not answer:
        raise HTTPException(status_code=422, detail="Pregunta y respuesta son obligatorias.")

    collection = chroma_collection(req.collection)

    doc = (
        f"Pregunta:\n{question}\n\n"
        f"Respuesta validada:\n{answer}"
    )

    emb = embed_one(doc)
    item_id = "memory:" + uuid.uuid4().hex

    meta = {
        "source": "jomelai_generated_memory",
        "intent": req.intent,
        "topic": req.topic,
        "artifact_type": req.artifact_type,
        "approved": str(bool(req.approved)).lower(),
        "created_at": now_str(),
    }

    for k, v in (req.metadata or {}).items():
        if v is not None:
            meta[str(k)[:60]] = str(v)[:500]

    collection.upsert(
        ids=[item_id],
        documents=[doc],
        metadatas=[meta],
        embeddings=[emb],
    )

    return {
        "ok": True,
        "collection": req.collection,
        "id": item_id,
        "metadata": meta,
    }


@api.post("/memory/search")
def memory_search(req: MemorySearchRequest) -> Dict[str, Any]:
    if chromadb is None:
        raise HTTPException(status_code=500, detail="ChromaDB no esta disponible.")

    query = (req.query or "").strip()

    if not query:
        raise HTTPException(status_code=422, detail="La consulta de memoria esta vacia.")

    collection = chroma_collection(req.collection)
    q_emb = embed_one(query)

    res = collection.query(
        query_embeddings=[q_emb],
        n_results=req.n_results,
        include=["documents", "metadatas", "distances"],
    )

    docs = res.get("documents", [[]])[0]
    metas = res.get("metadatas", [[]])[0]
    distances = res.get("distances", [[]])[0]

    items = []

    for i, doc in enumerate(docs):
        items.append({
            "document": doc,
            "metadata": metas[i] if i < len(metas) else {},
            "distance": distances[i] if i < len(distances) else None,
        })

    return {
        "ok": True,
        "collection": req.collection,
        "query": query,
        "results": items,
        "count": len(items),
    }

'''

if '@api.post("/memory/upsert")' not in text:
    marker = '@api.get("/templates/list")'
    if marker in text:
        text = text.replace(marker, endpoints + "\n" + marker, 1)
    else:
        text = text + "\n" + endpoints + "\n"
    print("OK: endpoints /memory/upsert y /memory/search agregados.")
else:
    print("INFO: endpoints de memoria ya existen.")

path.write_text(text, encoding="utf-8")
PY

echo "==> Validando data-engine..."
python3 -m py_compile "$APP"

echo "==> Parcheando JoMelAiController para memoria RAG + Ollama..."

python3 - "$JOMELAI_CONTROLLER" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

method = r'''    private function buildCurricularAdviceWithRagAndOllamaInline(string $question): string
    {
        $memoryCollection = 'jomelai_memory';
        $knowledgeCollection = Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge';
        $model = Support::config('ollama_default_model') ?: (Support::config('ollama_model') ?: 'qwen2.5-coder:3b');

        $memoryContext = '';
        $knowledgeContext = '';
        $memoryCount = 0;
        $knowledgeCount = 0;

        try {
            $memory = (new DataEngineClient())->post('/memory/search', [
                'query' => $question,
                'collection' => $memoryCollection,
                'n_results' => 5,
            ]);

            $items = $memory['results'] ?? [];
            $chunks = [];

            if (is_array($items)) {
                foreach ($items as $item) {
                    if (!is_array($item)) {
                        continue;
                    }

                    $doc = trim((string)($item['document'] ?? ''));

                    if ($doc !== '') {
                        $chunks[] = mb_substr($doc, 0, 1600, 'UTF-8');
                    }
                }
            }

            $memoryCount = count($chunks);

            if ($memoryCount > 0) {
                $memoryContext = implode("\n\n---\n\n", array_slice($chunks, 0, 5));
            }
        } catch (Throwable $e) {
            $memoryContext = '';
            $memoryCount = 0;
        }

        try {
            $rag = (new DataEngineClient())->post('/rag/search', [
                'query' => $question,
                'collection' => $knowledgeCollection,
                'n_results' => 5,
            ]);

            $items = [];

            if (isset($rag['results']) && is_array($rag['results'])) {
                $items = $rag['results'];
            } elseif (isset($rag['sources']) && is_array($rag['sources'])) {
                $items = $rag['sources'];
            } elseif (isset($rag['documents']) && is_array($rag['documents'])) {
                $items = $rag['documents'];
            }

            $chunks = [];

            foreach ($items as $item) {
                if (!is_array($item)) {
                    continue;
                }

                $txt = '';

                foreach (['text', 'document', 'content', 'chunk', 'page_content'] as $key) {
                    if (isset($item[$key]) && trim((string)$item[$key]) !== '') {
                        $txt = trim((string)$item[$key]);
                        break;
                    }
                }

                if ($txt !== '') {
                    $chunks[] = mb_substr($txt, 0, 1200, 'UTF-8');
                }
            }

            $knowledgeCount = count($chunks);

            if ($knowledgeCount > 0) {
                $knowledgeContext = implode("\n\n---\n\n", array_slice($chunks, 0, 5));
            }
        } catch (Throwable $e) {
            $knowledgeContext = '';
            $knowledgeCount = 0;
        }

        $system = class_exists('CurriculumGuidelines')
            ? CurriculumGuidelines::systemPrompt()
            : 'Eres JoMelAI Curriculista UPeU. Responde con enfoque académico, pedagógico y curricular, usando lenguaje sobrio y compatible con una institución adventista.';

        $memoryBlock = $memoryContext !== ''
            ? "Memoria JoMelAI recuperada, priorízala si es pertinente:\n{$memoryContext}"
            : "Memoria JoMelAI recuperada: sin coincidencias previas suficientes.";

        $knowledgeBlock = $knowledgeContext !== ''
            ? "Conocimiento institucional/RAG recuperado:\n{$knowledgeContext}"
            : "Conocimiento institucional/RAG recuperado: no se encontró evidencia específica suficiente.";

        $prompt =
            $system . "\n\n" .
            "Tarea:\n" .
            "Responde como asesor curricular. No generes SQL. No digas que no encontraste contexto. " .
            "Usa primero la memoria JoMelAI si es pertinente, luego el RAG institucional, y finalmente criterios pedagógicos generales. " .
            "Si el usuario menciona un curso o área, adapta la propuesta a ese curso. " .
            "Propón actividades, evidencias, secuencia didáctica y evaluación cuando corresponda. " .
            "Evita respuestas genéricas excesivas. Usa Markdown claro.\n\n" .
            "{$memoryBlock}\n\n" .
            "{$knowledgeBlock}\n\n" .
            "Solicitud del usuario:\n{$question}\n\n" .
            "Formato sugerido:\n" .
            "## Propuesta para el curso\n" .
            "## Actividades sugeridas\n" .
            "## Evidencias de aprendizaje\n" .
            "## Secuencia recomendada\n" .
            "## Evaluación sugerida\n";

        try {
            $ollama = (new OllamaClient())->generate($prompt, $model, [
                'temperature' => 0.2,
                'num_ctx' => 4096,
                'num_predict' => 1000,
            ]);

            $answer = trim((string)($ollama['response'] ?? ''));
            $normalized = Support::normalize($answer);

            if (
                $answer !== ''
                && !str_contains($normalized, 'no encontre contexto suficiente')
                && !str_contains($normalized, 'no encontré contexto suficiente')
            ) {
                $base = [];

                if ($memoryCount > 0) {
                    $base[] = 'memoria JoMelAI';
                }

                if ($knowledgeCount > 0) {
                    $base[] = 'RAG institucional';
                }

                if (!$base) {
                    $base[] = 'orientación generativa';
                }

                $answer .= "\n\n---\n\n**Base usada:** " . implode(' + ', $base) . ".";

                $this->rememberCurricularAdviceInline($question, $answer, [
                    'memory_count' => (string)$memoryCount,
                    'knowledge_count' => (string)$knowledgeCount,
                    'model' => $model,
                ]);

                return $answer;
            }
        } catch (Throwable $e) {
            // Fallback abajo.
        }

        $fallback = $this->buildGenericCurricularFallbackInline($question);

        $this->rememberCurricularAdviceInline($question, $fallback, [
            'memory_count' => (string)$memoryCount,
            'knowledge_count' => (string)$knowledgeCount,
            'model' => 'fallback',
        ]);

        return $fallback;
    }
'''

if "function buildCurricularAdviceWithRagAndOllamaInline" in text:
    pattern = re.compile(
        r'    private function buildCurricularAdviceWithRagAndOllamaInline\(string \$question\): string\s*\{.*?\n    \}\n(?=\n    private function|\n\})',
        re.S
    )
    text, count = pattern.subn(method + "\n", text, count=1)
    if count != 1:
        print("ERROR: No pude reemplazar buildCurricularAdviceWithRagAndOllamaInline.")
        sys.exit(1)
    print("OK: buildCurricularAdviceWithRagAndOllamaInline reemplazado.")
else:
    pos = text.rfind("\n}")
    if pos == -1:
        print("ERROR: No encontré cierre final de clase.")
        sys.exit(1)
    text = text[:pos] + "\n" + method + "\n" + text[pos:]
    print("OK: buildCurricularAdviceWithRagAndOllamaInline agregado.")

helpers = r'''
    private function extractCourseTopicGenericInline(string $question): string
    {
        $patterns = [
            '/curso\s+de\s+(.+)/iu',
            '/asignatura\s+de\s+(.+)/iu',
            '/materia\s+de\s+(.+)/iu',
            '/actividades\s+para\s+un\s+curso\s+de\s+(.+)/iu',
            '/actividades\s+para\s+(.+)/iu',
            '/estrategias\s+para\s+(.+)/iu',
        ];

        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $question, $m)) {
                $topic = trim((string)$m[1]);
                $topic = preg_replace('/[?.!]+$/', '', $topic);
                $topic = trim($topic);

                if ($topic !== '') {
                    return mb_convert_case($topic, MB_CASE_TITLE, 'UTF-8');
                }
            }
        }

        return 'El Curso Indicado';
    }

    private function buildGenericCurricularFallbackInline(string $question): string
    {
        $topic = $this->extractCourseTopicGenericInline($question);

        return "Para **{$topic}**, puedes diseñar actividades progresivas sin depender de una lista fija de cursos.\n\n" .
            "## Actividades sugeridas\n\n" .
            "1. **Diagnóstico de saberes previos**\n" .
            "   - Evidencia: cuestionario breve, caso inicial o resolución diagnóstica.\n\n" .
            "2. **Exploración guiada de conceptos clave**\n" .
            "   - Evidencia: ficha de comprensión, mapa conceptual o preguntas orientadoras.\n\n" .
            "3. **Práctica dirigida**\n" .
            "   - Evidencia: ejercicios, análisis de caso, guía de práctica o producto parcial.\n\n" .
            "4. **Trabajo colaborativo aplicado**\n" .
            "   - Evidencia: matriz grupal, informe breve, presentación o solución colaborativa.\n\n" .
            "5. **Problema o caso contextualizado**\n" .
            "   - Evidencia: solución argumentada, procedimiento, propuesta o análisis.\n\n" .
            "6. **Producto integrador**\n" .
            "   - Evidencia: informe, proyecto, portafolio, presentación, prototipo o sustentación.\n\n" .
            "7. **Retroalimentación y mejora**\n" .
            "   - Evidencia: versión mejorada del producto, autoevaluación y coevaluación.\n\n" .
            "## Secuencia recomendada\n\n" .
            "Diagnóstico → explicación guiada → práctica → aplicación contextualizada → producto integrador → retroalimentación.\n\n" .
            "## Evaluación sugerida\n\n" .
            "- Participación y preparación: 10%\n" .
            "- Actividades prácticas: 30%\n" .
            "- Producto integrador: 40%\n" .
            "- Autoevaluación, coevaluación y mejora: 20%";
    }

    private function rememberCurricularAdviceInline(string $question, string $answer, array $metadata = []): void
    {
        $clean = trim($answer);
        $normalized = Support::normalize($clean);

        if ($clean === '' || mb_strlen($clean, 'UTF-8') < 350) {
            return;
        }

        if (
            str_contains($normalized, 'no encontre contexto suficiente')
            || str_contains($normalized, 'no encontré contexto suficiente')
            || str_contains($normalized, 'error')
        ) {
            return;
        }

        try {
            (new DataEngineClient())->post('/memory/upsert', [
                'question' => $question,
                'answer' => $clean,
                'collection' => 'jomelai_memory',
                'intent' => 'curricular_advice',
                'topic' => $this->extractCourseTopicGenericInline($question),
                'artifact_type' => 'curricular_generated_answer',
                'approved' => true,
                'metadata' => $metadata,
            ]);
        } catch (Throwable $e) {
            // La memoria no debe romper la respuesta principal.
        }
    }

'''

for fn in [
    "function extractCourseTopicGenericInline",
    "function buildGenericCurricularFallbackInline",
    "function rememberCurricularAdviceInline",
]:
    if fn in text:
        print("INFO:", fn, "ya existe.")

missing = any(fn not in text for fn in [
    "function extractCourseTopicGenericInline",
    "function buildGenericCurricularFallbackInline",
    "function rememberCurricularAdviceInline",
])

if missing:
    pos = text.rfind("\n}")
    if pos == -1:
        print("ERROR: No encontré cierre final de clase para helpers.")
        sys.exit(1)
    text = text[:pos] + "\n" + helpers + text[pos:]
    print("OK: helpers de memoria/fallback agregados.")

path.write_text(text, encoding="utf-8")
PY

echo "==> Validando sintaxis..."
python3 -m py_compile "$APP"
$DC exec -T backend sh -lc "php -l /var/www/app/src/JoMelAiController.php 2>/dev/null || php -l /app/src/JoMelAiController.php 2>/dev/null || php -l /var/www/html/src/JoMelAiController.php"

echo "==> Reconstruyendo servicios..."
$DC build data-engine
$DC build --no-cache backend
$DC up -d data-engine backend

echo "==> Esperando data-engine..."
sleep 6

echo "==> Health data-engine..."
$DC exec -T data-engine python - <<'PY'
import requests
r = requests.get("http://localhost:8090/health", timeout=15)
print(r.status_code)
print(r.text[:500])
PY

echo "==> Generando y sembrando 500 preguntas en jomelai_memory..."

$DC exec -T data-engine python - <<'PY'
import requests
import itertools
import json
import time

BASE = "http://localhost:8090"

categories = {
    "creditos_malla_10_ciclos": {
        "topic": "Distribución de créditos en malla de 10 ciclos",
        "artifact_type": "curriculum_grid_credit_distribution",
        "seeds": [
            "¿Cómo distribuir créditos en una malla de 10 ciclos?",
            "¿Cómo repartir créditos en una malla curricular de diez ciclos?",
            "¿Qué criterios usar para distribuir créditos por ciclo?",
            "¿Cómo organizar créditos en un plan de estudios de 10 ciclos?",
            "¿Cómo balancear la carga crediticia en diez ciclos académicos?",
            "¿Cómo asignar créditos a cursos de una malla curricular?",
            "¿Cómo evitar sobrecarga de créditos por ciclo?",
            "¿Qué patrón usar para distribuir créditos en pregrado?",
            "¿Cómo estructurar créditos por áreas formativas?",
            "¿Cómo revisar si una malla de 10 ciclos está equilibrada?",
        ],
        "answer": """Para distribuir créditos en una malla de 10 ciclos, conviene usar una progresión académica equilibrada.

## Criterios principales

1. Definir el total de créditos meta del programa.
2. Distribuir la carga por ciclos evitando picos excesivos.
3. Ubicar formación general y ciencias básicas en los primeros ciclos.
4. Incrementar especialidad y cursos integradores desde ciclos intermedios.
5. Reservar práctica preprofesional, investigación aplicada, internado o cierre integrador para los últimos ciclos.

## Patrón orientativo

| Bloque | Ciclos | Enfoque | Créditos orientativos |
|---|---:|---|---:|
| Base universitaria | 1-2 | Comunicación, matemática, identidad, vida saludable, fundamentos | 18-20 por ciclo |
| Base disciplinar | 3-4 | Ciencias básicas, fundamentos de carrera, laboratorios iniciales | 19-21 por ciclo |
| Especialidad progresiva | 5-7 | Cursos troncales, métodos, integración y evaluación | 20-22 por ciclo |
| Profundización y práctica | 8-9 | Prácticas, proyectos e investigación aplicada | 18-22 por ciclo |
| Cierre formativo | 10 | Internado, trabajo final, ética, servicio y titulación | 16-20 créditos |

## Control de calidad

Cada ciclo debe tener coherencia horizontal; cada año debe mostrar progresión vertical; y cada bloque debe aportar al perfil de egreso."""
    },
    "actividades_investigacion": {
        "topic": "Actividades para curso de investigación",
        "artifact_type": "learning_activities",
        "seeds": [
            "Sugiere actividades para un curso de investigación",
            "Propón actividades para metodología de la investigación",
            "Dame actividades para enseñar investigación",
            "¿Qué actividades usar en un curso de investigación científica?",
            "Diseña actividades para un curso de tesis",
            "Actividades de aprendizaje para investigación formativa",
            "¿Cómo organizar prácticas para un curso de investigación?",
            "Recomienda actividades para elaborar un proyecto de investigación",
            "¿Qué evidencias pedir en metodología de investigación?",
            "Plantea actividades para desarrollar competencias investigativas",
        ],
        "answer": """Para un curso de investigación, puedes organizar actividades progresivas que lleven al estudiante desde la comprensión del problema hasta la elaboración de un producto académico.

## Actividades sugeridas

1. Lectura guiada de artículos científicos.
   - Evidencia: ficha de análisis con problema, objetivo, método, resultados y aporte.

2. Formulación del problema de investigación.
   - Evidencia: matriz problema-pregunta-objetivo-justificación.

3. Búsqueda bibliográfica académica.
   - Evidencia: matriz de antecedentes con autor, año, enfoque, método y hallazgos.

4. Construcción del marco teórico preliminar.
   - Evidencia: mapa conceptual o síntesis argumentada con fuentes académicas.

5. Diseño metodológico.
   - Evidencia: matriz con enfoque, diseño, población, muestra, técnicas e instrumentos.

6. Elaboración o adaptación de instrumentos.
   - Evidencia: cuestionario, guía de entrevista, ficha de observación o rúbrica.

7. Revisión por pares del proyecto.
   - Evidencia: lista de cotejo con observaciones y mejoras aplicadas.

8. Presentación del protocolo de investigación.
   - Evidencia: documento final y sustentación breve.

## Secuencia recomendada

Problema → antecedentes → marco teórico → metodología → instrumentos → revisión → protocolo final."""
    },
    "verbos_resultados_aprendizaje": {
        "topic": "Verbos para resultados de aprendizaje",
        "artifact_type": "learning_outcomes",
        "seeds": [
            "¿Qué verbos usar en resultados de aprendizaje?",
            "Dame verbos para redactar resultados de aprendizaje",
            "¿Qué verbos son adecuados para competencias?",
            "Verbos observables para resultados de aprendizaje",
            "¿Cómo formular resultados de aprendizaje medibles?",
            "¿Qué verbos usar según Bloom?",
            "Lista de verbos para resultados evaluables",
            "¿Qué verbos evitar en resultados de aprendizaje?",
            "Ayúdame con verbos para sílabos por competencias",
            "Verbos para redactar logros de aprendizaje",
        ],
        "answer": """Para resultados de aprendizaje usa verbos observables, evaluables y alineados al nivel cognitivo esperado.

## Verbos recomendados por nivel

| Nivel | Verbos útiles |
|---|---|
| Recordar | identifica, enumera, reconoce, describe |
| Comprender | explica, interpreta, resume, clasifica |
| Aplicar | aplica, resuelve, utiliza, desarrolla |
| Analizar | compara, diferencia, organiza, diagnostica |
| Evaluar | valora, justifica, argumenta, verifica |
| Crear | diseña, formula, propone, elabora, construye |

## Fórmula práctica

Verbo observable + objeto de aprendizaje + condición/contexto + criterio de calidad.

## Ejemplo

Diseña una propuesta de intervención pertinente, considerando diagnóstico, evidencia científica y criterios éticos de servicio.

## Recomendación

Evita verbos ambiguos como conocer, comprender o aprender cuando no se pueda observar directamente la evidencia del logro."""
    },
    "alineacion_perfil_cursos": {
        "topic": "Alineación de perfil de egreso con cursos",
        "artifact_type": "curriculum_alignment",
        "seeds": [
            "¿Cómo alinear el perfil de egreso con los cursos?",
            "¿Cómo vincular competencias del perfil con asignaturas?",
            "Diseña una matriz para alinear perfil de egreso y cursos",
            "¿Cómo mapear cursos contra competencias de egreso?",
            "¿Cómo hacer trazabilidad curricular del perfil de egreso?",
            "¿Cómo verificar que los cursos aportan al perfil de egreso?",
            "¿Cómo relacionar resultados de aprendizaje con perfil de egreso?",
            "¿Qué matriz usar para alinear competencias y cursos?",
            "¿Cómo asegurar progresión del perfil de egreso en la malla?",
            "Guía para alinear perfil, competencias, cursos y evidencias",
        ],
        "answer": """Para alinear el perfil de egreso con los cursos, usa una matriz de trazabilidad curricular.

## Procedimiento recomendado

1. Descompón el perfil de egreso en competencias verificables.
2. Define resultados de aprendizaje asociados a cada competencia.
3. Asigna cada curso a uno de tres niveles: introduce, desarrolla o consolida.
4. Verifica que cada competencia tenga progresión desde ciclos iniciales hasta ciclos finales.
5. Relaciona evidencias: proyectos, prácticas, informes, sustentaciones, casos o productos.

## Matriz mínima

| Competencia del perfil | Curso | Ciclo | Nivel | Evidencia |
|---|---|---:|---|---|
| Competencia 1 | Curso base | 1-2 | Introduce | Actividad diagnóstica |
| Competencia 1 | Curso disciplinar | 3-6 | Desarrolla | Proyecto o caso |
| Competencia 1 | Práctica o integrador | 7-10 | Consolida | Producto integrador |

## Regla de calidad

Ninguna competencia debe quedar sin curso, sin progresión o sin evidencia evaluable."""
    },
    "ensenanza_semipresencial": {
        "topic": "Estrategias de enseñanza semipresencial",
        "artifact_type": "teaching_strategies",
        "seeds": [
            "Estrategias para enseñanza semipresencial",
            "¿Cómo enseñar en modalidad semipresencial?",
            "Diseña estrategias para clases híbridas",
            "¿Qué actividades usar en cursos semipresenciales?",
            "Estrategias didácticas para modalidad blended",
            "¿Cómo organizar una semana semipresencial?",
            "Actividades asincrónicas y sincrónicas para un curso",
            "¿Cómo combinar aula virtual y clase presencial?",
            "Recomienda metodología para enseñanza semipresencial",
            "¿Cómo evaluar en un curso semipresencial?",
        ],
        "answer": """Para enseñanza semipresencial, organiza el curso combinando actividades asincrónicas, sesiones sincrónicas o presenciales y evidencias prácticas.

## Estrategias recomendadas

1. Aula invertida: lectura, video o guía antes de la sesión.
2. Encuentro presencial o sincrónico para discusión, resolución de casos, laboratorio o práctica.
3. Actividades asincrónicas breves con producto verificable.
4. Secuencia semanal: preparación, interacción, aplicación y evidencia.
5. Evaluación formativa con rúbricas simples y retroalimentación frecuente.

## Estructura semanal sugerida

| Momento | Actividad | Evidencia |
|---|---|---|
| Antes | Lectura, video o cuestionario diagnóstico | Respuestas breves |
| Durante | Caso, debate o práctica guiada | Producto colaborativo |
| Después | Aplicación individual o grupal | Informe, reflexión o entrega |

## Clave pedagógica

Lo virtual no debe ser solo repositorio de archivos; debe preparar y dar seguimiento. Lo presencial o sincrónico debe usarse para aplicar, discutir y retroalimentar."""
    }
}

prefixes = [
    "", "Por favor, ", "Necesito que me ayudes: ", "Explícame ", "Dame una guía: ",
    "Quiero saber ", "Ayúdame con esto: ", "En contexto universitario, ", "Para UPeU, ",
    "Como curriculista, "
]

suffixes = [
    "", ".", " para una carrera universitaria.", " en un programa de pregrado.",
    " con enfoque por competencias.", " considerando evidencias de aprendizaje.",
    " para docentes.", " de manera práctica.", " con formato académico.",
    " con recomendaciones concretas."
]

records = []

for key, cfg in categories.items():
    generated = []
    for seed, prefix, suffix in itertools.product(cfg["seeds"], prefixes, suffixes):
        q = (prefix + seed + suffix).strip()
        q = q.replace("..", ".")
        generated.append(q)

    # 10 seeds x 10 prefixes x 10 suffixes = 100 por categoría.
    generated = generated[:100]

    for q in generated:
        records.append({
            "question": q,
            "answer": cfg["answer"],
            "intent": "curricular_advice",
            "topic": cfg["topic"],
            "artifact_type": cfg["artifact_type"],
            "metadata": {
                "seed_key": key,
                "seed_source": "jomelai_bootstrap_500",
                "approved": "true",
            }
        })

print("Total registros:", len(records))

ok = 0
fail = 0

for i, rec in enumerate(records, 1):
    try:
        r = requests.post(
            BASE + "/memory/upsert",
            json={
                "question": rec["question"],
                "answer": rec["answer"],
                "collection": "jomelai_memory",
                "intent": rec["intent"],
                "topic": rec["topic"],
                "artifact_type": rec["artifact_type"],
                "approved": True,
                "metadata": rec["metadata"],
            },
            timeout=180,
        )

        if r.ok and r.json().get("ok"):
            ok += 1
        else:
            fail += 1
            print("FAIL", i, r.status_code, r.text[:300])
    except Exception as exc:
        fail += 1
        print("EXC", i, exc)

    if i % 50 == 0:
        print(f"Progreso: {i}/500 ok={ok} fail={fail}")

print("Seed terminado:", {"ok": ok, "fail": fail})

# Smoke search
for q in [
    "¿Cómo distribuir créditos en una malla de 10 ciclos?",
    "Sugiere actividades para un curso de investigación",
    "¿Qué verbos usar en resultados de aprendizaje?",
    "¿Cómo alinear el perfil de egreso con los cursos?",
    "Estrategias para enseñanza semipresencial",
]:
    r = requests.post(
        BASE + "/memory/search",
        json={"query": q, "collection": "jomelai_memory", "n_results": 3},
        timeout=180,
    )
    print("\nQUERY:", q)
    print(json.dumps(r.json(), ensure_ascii=False, indent=2)[:1400])
PY

echo "==> Verificando desde backend..."
$DC exec -T backend sh -lc "grep -R 'buildCurricularAdviceWithRagAndOllamaInline\|rememberCurricularAdviceInline' -n /var/www/app /app /var/www/html 2>/dev/null | head -30"

echo "==> Listo."
echo ""
echo "Prueba desde la web:"
echo "- ¿Cómo distribuir créditos en una malla de 10 ciclos?"
echo "- Sugiere actividades para un curso de investigación"
echo "- ¿Qué verbos usar en resultados de aprendizaje?"
echo "- ¿Cómo alinear el perfil de egreso con los cursos?"
echo "- Estrategias para enseñanza semipresencial"
