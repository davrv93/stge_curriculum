#!/usr/bin/env bash
set -euo pipefail

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

TARGET="backend/src/DataEngineController.php"

if [ ! -f "$TARGET" ]; then
  TARGET="$(grep -R "class DataEngineController" -n backend 2>/dev/null | head -1 | cut -d: -f1 || true)"
fi

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  echo "ERROR: No encontré DataEngineController.php"
  exit 1
fi

echo "==> Archivo: $TARGET"
BACKUP="${TARGET}.bak_curricular_advice_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "==> Backup: $BACKUP"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

guard = """        if ($mode === 'auto' && $this->looksLikeCurricularAdvisoryQuestion($question)) {
            $advisory = $this->answerCurricularAdvisoryQuestion($question, $model, $collection);

            $this->saveRun(
                (int)$user['id'],
                (string)($advisory['model'] ?? 'no_ollama'),
                'user_curricular_advice',
                $question,
                (string)($advisory['answer'] ?? 'Asesoría curricular resuelta.'),
                $advisory
            );

            Support::json($advisory, ($advisory['ok'] ?? false) ? 200 : 422);
            return;
        }

"""

needle = "        if ($mode === 'auto' && $this->looksLikeAcademicLoadedDataQuestion($question)) {"

if "looksLikeCurricularAdvisoryQuestion($question)" not in text:
    if needle not in text:
        print("ERROR: No encontré el punto de inserción en userAsk().")
        sys.exit(1)
    text = text.replace(needle, guard + needle, 1)
    print("OK: Compuerta curricular insertada en userAsk().")
else:
    print("INFO: La compuerta curricular ya existía.")

methods = r'''
    private function looksLikeCurricularAdvisoryQuestion(string $question): bool
    {
        $q = Support::normalize($question);

        $hardDataTokens = [
            'cuantos', 'cuantas', 'cantidad', 'conteo', 'total de',
            'lista', 'listar', 'listame', 'muestrame',
            'grafico', 'grafica', 'barras', 'pie', 'pastel',
            'ranking', 'top', 'por sede', 'por facultad', 'por programa'
        ];

        $curricularTokens = [
            'como distribuir creditos',
            'distribuir creditos',
            'malla de 10 ciclos',
            'malla curricular',
            'plan de estudios',
            'perfil de egreso',
            'alinear el perfil',
            'alinear perfil',
            'resultados de aprendizaje',
            'resultado de aprendizaje',
            'verbos usar',
            'verbos para',
            'taxonomia',
            'rubrica',
            'rúbrica',
            'trabajo en equipo',
            'ensenanza semipresencial',
            'enseñanza semipresencial',
            'semipresencial',
            'estrategias de enseñanza',
            'estrategias para enseñanza',
            'evaluacion formativa',
            'evaluación formativa',
            'competencias',
            'competencia del curso',
            'sumilla',
            'sesion de aprendizaje',
            'sesión de aprendizaje',
            'alineacion constructiva',
            'alineación constructiva',
            'mapa curricular',
            'matriz curricular',
            'prerrequisitos',
            'creditos por ciclo',
            'créditos por ciclo'
        ];

        foreach ($curricularTokens as $token) {
            if (str_contains($q, Support::normalize($token))) {
                return true;
            }
        }

        // Preguntas abiertas con "cómo" sobre currículo deben ser asesoría, no SQL/gráfico.
        if (str_contains($q, 'como ') || str_contains($q, 'cómo ')) {
            foreach ([
                'curso', 'cursos', 'malla', 'perfil', 'egreso', 'competencia',
                'competencias', 'creditos', 'créditos', 'aprendizaje',
                'ensenanza', 'enseñanza', 'evaluacion', 'evaluación'
            ] as $domain) {
                if (str_contains($q, Support::normalize($domain))) {
                    return true;
                }
            }
        }

        // Si es claramente pregunta numérica/listado/gráfico, no tomarla aquí.
        foreach ($hardDataTokens as $token) {
            if (str_contains($q, Support::normalize($token))) {
                return false;
            }
        }

        return false;
    }

    private function answerCurricularAdvisoryQuestion(string $question, string $model, string $collection): array
    {
        if ($collection === '' || $collection === 'auto' || $collection === 'silabos') {
            $collection = Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge';
        }

        $rag = null;

        try {
            $rag = (new DataEngineClient())->post('/rag/answer', [
                'question' => $question,
                'collection' => $collection,
                'model' => $model,
                'n_results' => 5,
            ]);
        } catch (Throwable $e) {
            $rag = [
                'ok' => false,
                'message' => $e->getMessage(),
                'sources' => [],
                'evidence' => [],
                'count' => 0,
            ];
        }

        $ragAnswer = trim((string)($rag['answer'] ?? ''));
        $count = (int)($rag['count'] ?? 0);

        if ($count <= 0 && isset($rag['sources']) && is_array($rag['sources'])) {
            $count = count($rag['sources']);
        }

        $ragIsUseful = (
            ($rag['ok'] ?? false)
            && $count > 0
            && $ragAnswer !== ''
            && !str_contains(Support::normalize($ragAnswer), 'no encontre contexto suficiente')
            && !str_contains(Support::normalize($ragAnswer), 'no encontré contexto suficiente')
        );

        if ($ragIsUseful) {
            return [
                'ok' => true,
                'mode' => 'curricular_advice',
                'visible_intent' => 'Asesoría curricular',
                'answer' => $ragAnswer,
                'summary' => 'Respondí usando orientación curricular y contexto recuperado.',
                'model' => $model,
                'collection' => $collection,
                'evidence' => $rag['sources'] ?? $rag['evidence'] ?? [],
                'rag' => $rag,
                'actions' => [
                    ['label' => 'Convertir en plantilla', 'type' => 'template'],
                    ['label' => 'Generar ejemplo aplicado', 'type' => 'example'],
                ],
            ];
        }

        $answer = $this->buildDeterministicCurricularAdvice($question);

        return [
            'ok' => true,
            'mode' => 'curricular_advice_fallback',
            'visible_intent' => 'Asesoría curricular',
            'answer' => $answer,
            'summary' => 'Respondí con una guía curricular determinística porque no hubo contexto RAG suficiente.',
            'model' => 'no_ollama',
            'collection' => $collection,
            'evidence' => [],
            'rag' => $rag,
            'actions' => [
                ['label' => 'Pedir ejemplo por carrera', 'type' => 'example'],
                ['label' => 'Convertir en formato institucional', 'type' => 'template'],
            ],
        ];
    }

    private function buildDeterministicCurricularAdvice(string $question): string
    {
        $q = Support::normalize($question);

        if (str_contains($q, 'distribuir creditos') || str_contains($q, 'creditos por ciclo') || str_contains($q, 'malla de 10 ciclos')) {
            return "Para distribuir créditos en una malla de 10 ciclos, conviene trabajar con una progresión académica equilibrada y verificable.\n\n" .
                "## Criterio recomendado\n\n" .
                "- Define primero el total meta de créditos del programa.\n" .
                "- Distribuye la carga por ciclos evitando picos excesivos.\n" .
                "- Ubica formación general y ciencias básicas en los primeros ciclos.\n" .
                "- Incrementa cursos de especialidad desde ciclos intermedios.\n" .
                "- Reserva práctica preprofesional, investigación aplicada e integración final para los últimos ciclos.\n\n" .
                "## Patrón sugerido para 10 ciclos\n\n" .
                "| Bloque | Ciclos | Enfoque | Créditos orientativos |\n" .
                "|---|---:|---|---:|\n" .
                "| Base universitaria | 1-2 | Comunicación, matemática, identidad, vida saludable, fundamentos | 18-20 por ciclo |\n" .
                "| Base disciplinar | 3-4 | Ciencias básicas, fundamentos de carrera, primeros laboratorios | 19-21 por ciclo |\n" .
                "| Especialidad progresiva | 5-7 | Cursos troncales, métodos, integración y evaluación | 20-22 por ciclo |\n" .
                "| Profundización y práctica | 8-9 | Prácticas, proyectos, investigación aplicada | 18-22 por ciclo |\n" .
                "| Cierre formativo | 10 | Internado, trabajo final, ética, servicio y titulación | 16-20 créditos |\n\n" .
                "## Regla de control\n\n" .
                "Cada ciclo debe tener coherencia horizontal; cada año debe mostrar progresión vertical; y cada bloque debe aportar al perfil de egreso.";
        }

        if (str_contains($q, 'verbos') || str_contains($q, 'resultado de aprendizaje') || str_contains($q, 'resultados de aprendizaje')) {
            return "Para resultados de aprendizaje usa verbos observables, evaluables y alineados al nivel cognitivo esperado.\n\n" .
                "## Verbos recomendados por nivel\n\n" .
                "| Nivel | Verbos útiles |\n" .
                "|---|---|\n" .
                "| Recordar | identifica, enumera, reconoce, describe |\n" .
                "| Comprender | explica, interpreta, resume, clasifica |\n" .
                "| Aplicar | aplica, resuelve, utiliza, desarrolla |\n" .
                "| Analizar | compara, diferencia, organiza, diagnostica |\n" .
                "| Evaluar | valora, justifica, argumenta, verifica |\n" .
                "| Crear | diseña, formula, propone, elabora, construye |\n\n" .
                "## Fórmula práctica\n\n" .
                "**Verbo observable + objeto de aprendizaje + condición/contexto + criterio de calidad.**\n\n" .
                "Ejemplo: *Diseña una propuesta de intervención nutricional comunitaria, considerando evidencia científica, diagnóstico poblacional y criterios éticos de servicio.*";
        }

        if (str_contains($q, 'rubrica') || str_contains($q, 'rúbrica') || str_contains($q, 'trabajo en equipo')) {
            return "Aquí tienes una rúbrica base para evaluar trabajo en equipo.\n\n" .
                "| Criterio | Inicial | En proceso | Logrado | Destacado |\n" .
                "|---|---|---|---|---|\n" .
                "| Participación | Participa poco o de forma aislada | Participa cuando se le solicita | Participa activamente y cumple tareas | Lidera aportes sin desplazar al equipo |\n" .
                "| Responsabilidad | Incumple entregables | Cumple parcialmente | Cumple en tiempo y forma | Anticipa riesgos y apoya a otros |\n" .
                "| Comunicación | Presenta dificultades para coordinar | Comunica avances de forma irregular | Comunica ideas y avances con claridad | Facilita acuerdos y escucha activa |\n" .
                "| Colaboración | Trabaja de forma individualista | Coopera en tareas específicas | Coopera y contribuye al logro común | Integra aportes y fortalece el clima del equipo |\n" .
                "| Resolución de conflictos | Evita o agrava conflictos | Acepta mediación externa | Propone soluciones respetuosas | Previene conflictos y promueve consensos |\n\n" .
                "Puedes ponderarla así: participación 20%, responsabilidad 25%, comunicación 20%, colaboración 25%, resolución de conflictos 10%.";
        }

        if (str_contains($q, 'alinear') || str_contains($q, 'perfil de egreso') || str_contains($q, 'mapa curricular') || str_contains($q, 'matriz curricular')) {
            return "Para alinear el perfil de egreso con los cursos, usa una matriz de trazabilidad curricular.\n\n" .
                "## Procedimiento recomendado\n\n" .
                "1. Descompón el perfil de egreso en competencias verificables.\n" .
                "2. Define resultados de aprendizaje por competencia.\n" .
                "3. Asigna cada curso a uno de tres niveles: introduce, desarrolla o consolida.\n" .
                "4. Verifica que cada competencia tenga progresión desde ciclos iniciales hasta ciclos finales.\n" .
                "5. Relaciona evidencias: proyectos, prácticas, informes, sustentaciones, casos o productos.\n\n" .
                "## Matriz mínima\n\n" .
                "| Competencia del perfil | Curso | Ciclo | Nivel | Evidencia |\n" .
                "|---|---|---:|---|---|\n" .
                "| Competencia 1 | Curso base | 1-2 | Introduce | Actividad diagnóstica |\n" .
                "| Competencia 1 | Curso disciplinar | 3-6 | Desarrolla | Proyecto o caso |\n" .
                "| Competencia 1 | Práctica/Integrador | 7-10 | Consolida | Producto integrador |\n\n" .
                "La regla de calidad es simple: ninguna competencia debe quedar sin curso, sin progresión o sin evidencia evaluable.";
        }

        if (str_contains($q, 'semipresencial') || str_contains($q, 'ensenanza') || str_contains($q, 'enseñanza') || str_contains($q, 'estrategias')) {
            return "Para enseñanza semipresencial, organiza el curso combinando actividades asincrónicas, sesiones sincrónicas y evidencias prácticas.\n\n" .
                "## Estrategias recomendadas\n\n" .
                "- Usa aula invertida: lectura, video o guía antes de la sesión presencial/sincrónica.\n" .
                "- Reserva el encuentro presencial para discusión, resolución de casos, laboratorio, práctica o retroalimentación.\n" .
                "- Diseña actividades asincrónicas breves con producto verificable.\n" .
                "- Mantén una secuencia semanal: preparación, interacción, aplicación y evidencia.\n" .
                "- Aplica evaluación formativa con rúbricas simples y retroalimentación frecuente.\n\n" .
                "## Estructura semanal sugerida\n\n" .
                "| Momento | Actividad | Evidencia |\n" .
                "|---|---|---|\n" .
                "| Antes | Lectura, video, cuestionario diagnóstico | Respuestas breves |\n" .
                "| Durante | Caso, debate, práctica guiada | Producto colaborativo |\n" .
                "| Después | Aplicación individual o grupal | Informe, reflexión o entrega |\n\n" .
                "La clave es que lo virtual no sea repositorio de archivos, sino preparación y seguimiento; y lo presencial/sincrónico sea aplicación guiada.";
        }

        return "Puedo orientarte curricularmente con una respuesta estructurada. Para trabajar esta solicitud, recomiendo organizarla en cuatro partes: propósito formativo, criterios académicos, propuesta operativa y evidencias de logro. Si se trata de una malla, revisa créditos, ciclos, prerrequisitos y progresión; si se trata de un curso, revisa competencia, resultados, metodología, evaluación y bibliografía.";
    }

'''

if "function looksLikeCurricularAdvisoryQuestion" not in text:
    pos = text.rfind("\n}")
    if pos == -1:
        print("ERROR: No pude ubicar el cierre final de la clase.")
        sys.exit(1)
    text = text[:pos] + "\n" + methods + text[pos:]
    print("OK: Métodos curriculares insertados.")
else:
    print("INFO: Los métodos curriculares ya existían.")

path.write_text(text, encoding="utf-8")
PY

echo "==> Reconstruyendo backend..."
$DC build --no-cache backend

echo "==> Reiniciando backend..."
$DC up -d backend

echo "==> Verificando métodos dentro del contenedor..."
$DC exec -T backend sh -lc "grep -R 'looksLikeCurricularAdvisoryQuestion\|answerCurricularAdvisoryQuestion\|buildDeterministicCurricularAdvice' -n /var/www/app /app /var/www/html 2>/dev/null | head -50"

echo "==> Validando sintaxis..."
$DC exec -T backend sh -lc "php -l /var/www/app/src/DataEngineController.php 2>/dev/null || php -l /app/src/DataEngineController.php 2>/dev/null || php -l /var/www/html/src/DataEngineController.php"

echo "==> Probando preguntas curriculares..."
for q in \
"¿Cómo distribuir créditos en una malla de 10 ciclos?" \
"¿Qué verbos usar en resultados de aprendizaje?" \
"Crea una rúbrica para trabajo en equipo" \
"¿Cómo alinear el perfil de egreso con los cursos?" \
"Estrategias para enseñanza semipresencial"
do
  echo ""
  echo "---- $q"
  curl -s -X POST http://localhost:3000/api/user/ask \
    -H "Content-Type: application/json" \
    -d "{\"question\":\"$q\",\"mode\":\"auto\",\"collection\":\"auto\"}" \
    | python3 -m json.tool | head -80 || true
done

echo ""
echo "==> FIX COMPLETADO."
