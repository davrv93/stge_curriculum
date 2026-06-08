<?php
/**
 * JoMelAiOrchestrator
 * Routes classified intents to the correct internal engine(s).
 * All engine names are internal; the user never sees them.
 */
final class JoMelAiOrchestrator
{
    private DataEngineClient $engine;
    private OllamaClient     $ollama;
    private string           $model;

    private const BLOCKED_SQL = [
        'drop', 'delete', 'update', 'insert', 'create', 'alter', 'truncate',
        'copy', 'attach', 'install', 'load', 'read_csv', 'read_parquet',
        'shell', 'export', 'pragma',
    ];

    public function __construct()
    {
        $this->engine = new DataEngineClient();
        $this->ollama = new OllamaClient();
        $this->model  = Support::config('ollama_default_model');
    }

    
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



    private function looksLikeStructuredQuestion(string $question): bool
    {
        $q = Support::normalize($question);
        $tokens = ['cuantos', 'cuantas', 'cantidad', 'conteo', 'total', 'promedio', 'suma', 'ranking', 'top', 'grafico', 'grafica', 'barras', 'pastel', 'pie', 'torta', 'distribucion', 'por ciclo', 'por facultad', 'por programa', 'por carrera', 'por escuela', 'por sede', 'creditos', 'horas', 'lista', 'listar', 'listame', 'listarme', 'muestrame', 'mostrar', 'cursos', 'curso', 'carreras', 'carrera', 'programas', 'programa', 'malla', 'mallas', 'sumilla', 'sumillas', 'tienes cargadas', 'tienes cargados', 'cargadas', 'cargados'];
        foreach ($tokens as $t) {
            if (str_contains($q, $t)) {
                return true;
            }
        }
        return false;
    }

    private function looksLikeProposalAnalysis(string $question): bool
    {
        $q = Support::normalize($question);
        $tokens = ['analiza propuesta', 'analizar propuesta', 'evaluar propuesta', 'validar propuesta', 'revision curricular', 'cumple sunedu', 'formato', 'plantilla', 'contextualizar'];
        foreach ($tokens as $t) {
            if (str_contains($q, $t)) {
                return true;
            }
        }
        return false;
    }

    /** FastIntentEngine: resuelve conteos, rankings, agrupaciones y gráficos sin Ollama. */
    private function runFastIntent(string $question, string $table = 'silabos'): array
    {
        try {
            $resolved = $this->engine->post('/intent/resolve', [
                'question' => $question,
                'table' => $table ?: 'silabos',
            ]);
        } catch (Throwable $e) {
            return ['ok' => false, 'message' => 'FastIntentEngine no disponible.', '_engine' => 'fast_intent'];
        }

        if (!($resolved['ok'] ?? false) || empty($resolved['sql'])) {
            $resolved['_engine'] = 'fast_intent_router';
            return $resolved;
        }

        $mode = (string)($resolved['mode'] ?? 'sql');
        if ($mode === 'chart') {
            $chart = $this->engine->post('/duckdb/chart', [
                'sql' => $resolved['sql'],
                'chart_type' => $resolved['chart_type'] ?? 'bar',
                'title' => $resolved['title'] ?? 'Reporte curricular',
                'x' => $resolved['x'] ?? null,
                'y' => $resolved['y'] ?? null,
                'limit' => 200,
            ]);
            return [
                'ok' => (bool)($chart['ok'] ?? false),
                'answer' => 'Reporte generado sin Ollama usando el motor rápido de intención y DuckDB.',
                'chart' => $chart,
                'spec' => $resolved,
                'sql' => $resolved['sql'],
                'confidence' => (float)($resolved['confidence'] ?? 0),
                '_engine' => 'fast_intent_chart',
                '_model' => 'no_ollama',
            ];
        }

        $query = $this->engine->post('/duckdb/query', [
            'sql' => $resolved['sql'],
            'limit' => 100,
        ]);
        return [
            'ok' => (bool)($query['ok'] ?? false),
            'answer' => 'Consulta generada sin Ollama usando el motor rápido de intención y DuckDB.',
            'query' => $query,
            'spec' => $resolved,
            'sql' => $resolved['sql'],
            'confidence' => (float)($resolved['confidence'] ?? 0),
            '_engine' => 'fast_intent_sql',
            '_model' => 'no_ollama',
        ];
    }

    /** Analizador semántico rápido de propuestas/formats sin LLM. */
    private function runProposalSemanticAnalysis(string $question): array
    {
        $result = $this->engine->post('/semantic/analyze-proposal', [
            'text' => $question,
            'institution_profile' => 'adventista',
            'artifact_type' => 'auto',
        ]);
        $result['_engine'] = 'semantic_proposal_analyzer';
        $result['_model'] = 'no_ollama';
        if (($result['ok'] ?? false) && empty($result['answer'])) {
            $rec = $result['recommendations'] ?? [];
            $result['answer'] = 'Análisis semántico rápido completado. Confianza: ' . (string)($result['confidence'] ?? '0') . '. ' . implode(' ', array_slice($rec, 0, 3));
        }
        return $result;
    }

    // ─── Engines ──────────────────────────────────────────────────────────────

    /** chart → data_analysis engine (natural chart) */
    private function runChart(string $question): array
    {
        $result = $this->engine->post('/charts/natural', [
            'question' => $question,
            'table'    => 'silabos',
            'model'    => $this->model,
        ]);
        $result['_engine'] = 'chart_analysis';
        $result['_model']  = $this->model;
        return $result;
    }

    /** statistics → structured DuckDB query via AI */
    private function runStatistics(string $question): array
    {
        $schema = $this->engine->get('/duckdb/schema', ['table' => 'silabos']);
        if (!($schema['ok'] ?? false)) {
            return array_merge($schema, ['_engine' => 'data_analysis']);
        }

        $columns = implode(', ', array_map(
            fn($c) => $c['name'] . ' ' . $c['type'],
            $schema['columns'] ?? []
        ));

        $prompt = "Eres un asistente que genera SQL para DuckDB. Responde SOLO JSON: {\"sql\":\"...\",\"explanation\":\"...\"}\n" .
            "Solo SELECT o WITH. Sin DROP/DELETE/UPDATE. Agrega LIMIT 200 si no hay LIMIT.\n" .
            "Tabla: silabos. Columnas: $columns\n" .
            "Solicitud: $question";

        $ai  = $this->ollama->generate($prompt, $this->model, ['temperature' => 0.1]);
        $raw = (string)($ai['response'] ?? '');
        $parsed = $this->extractJson($raw);
        $sql = trim((string)($parsed['sql'] ?? ''));

        if ($sql === '' || !$this->isSafeSql($sql)) {
            return [
                'ok'      => false,
                'message' => 'No se pudo generar una consulta válida para esta solicitud.',
                '_engine' => 'data_analysis',
                '_model'  => $this->model,
            ];
        }

        $sql = $this->addLimitIfMissing($sql, 200);
        $query = $this->engine->post('/duckdb/query', ['sql' => $sql, 'limit' => 200]);
        return array_merge($query, [
            '_engine'      => 'data_analysis',
            '_sql'         => $sql,
            '_model'       => $this->model,
            'explanation'  => $this->sanitizeExplanation((string)($parsed['explanation'] ?? '')),
        ]);
    }

    /** semantic_search → knowledge index (RAG) */
    private function runSemanticSearch(string $question, ?string $collection): array
    {
        $col    = $collection ?? (Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge');
        $result = $this->engine->post('/rag/answer', [
            'question'   => $question,
            'collection' => $col,
            'model'      => $this->model,
            'n_results'  => 5,
        ]);
        return array_merge($result, [
            '_engine'     => 'knowledge_index',
            '_model'      => $this->model,
            'answer'      => $result['answer'] ?? $result['response'] ?? '',
            'evidence'    => $result['sources'] ?? $result['evidence'] ?? [],
        ]);
    }

    /** course_lookup → DuckDB stats + RAG content (hybrid) */
    private function runCourseHybrid(string $question, ?string $collection): array
    {
        $dataResult = $this->runStatistics($question);
        $ragResult  = $this->runSemanticSearch($question, $collection);

        $combined = $this->mergeHybrid($dataResult, $ragResult, $question);
        $combined['_engine'] = 'hybrid';
        return $combined;
    }

    /** comparison → DuckDB filter + RAG content (hybrid) */
    private function runComparison(string $question, ?string $collection): array
    {
        $dataResult = $this->runStatistics($question);
        $ragResult  = $this->runSemanticSearch($question, $collection);
        $combined   = $this->mergeHybrid($dataResult, $ragResult, $question);

        // Ask AI to produce comparison summary
        $context  = $this->buildContext($dataResult, $ragResult);
        $summary  = $this->aiSummarize(
            "Compara los siguientes elementos curriculares. Sé conciso y académico.\n\n$context\n\nPregunta: $question",
            650
        );

        $combined['answer']  = $summary;
        $combined['_engine'] = 'hybrid';
        return $combined;
    }

    /** syllabus_generation → AI + RAG context */
    private function runSyllabusGeneration(string $question): array
    {
        $ragResult = $this->runSemanticSearch($question, 'silabos_competencias');
        $context   = $this->buildContext([], $ragResult);

        $prompt = "Eres un especialista en diseño curricular universitario bajo estándares SINEACE y SUNEDU.\n" .
            "Usa el contexto disponible para generar un sílabo académico completo y estructurado.\n" .
            "Incluye: competencias, sumilla, contenidos por unidades, metodología, evaluación y bibliografía sugerida.\n" .
            "Contexto disponible:\n$context\n\n" .
            "Solicitud: $question\n\n" .
            "Responde con el sílabo en formato académico claro y detallado.";

        $answer = $this->aiSummarize($prompt, 1500);
        return [
            'ok'       => true,
            'answer'   => $answer,
            'evidence' => $ragResult['evidence'] ?? [],
            '_engine'  => 'assistant',
            '_model'   => $this->model,
        ];
    }

    /** study_plan → curriculum framework + AI */
    private function runStudyPlan(string $question): array
    {
        $prompt = "Eres un experto en diseño curricular universitario. Genera un plan de estudios detallado.\n" .
            "Organiza por ciclos académicos, incluye créditos estimados y prerrequisitos.\n" .
            "Solicitud: $question\n\n" .
            "Responde con el plan de estudios estructurado.";
        $answer = $this->aiSummarize($prompt, 1500);
        return ['ok' => true, 'answer' => $answer, '_engine' => 'curriculum', '_model' => $this->model];
    }

    /** curriculum_grid → DuckDB grouped data */
    private function runCurriculumGrid(string $question): array
    {
        $result = $this->runStatistics($question);
        $result['_engine'] = 'curriculum';
        return $result;
    }

    /** report → DuckDB + RAG + optional chart */
    private function runReport(string $question, ?string $collection): array
    {
        $dataResult = $this->runStatistics($question);
        $ragResult  = $this->runSemanticSearch($question, $collection);
        $context    = $this->buildContext($dataResult, $ragResult);

        $summary = $this->aiSummarize(
            "Genera un informe académico conciso y claro basado en los datos siguientes.\n\n" .
            "$context\n\nSolicitud original: $question",
            1200
        );

        // Attempt to generate a chart for the report
        $chartResult = $this->runChart($question . ' (reporte)');

        $result = [
            'ok'       => true,
            'answer'   => $summary,
            'evidence' => $ragResult['evidence'] ?? [],
            '_engine'  => 'hybrid',
            '_model'   => $this->model,
        ];
        if (!empty($chartResult['chart_url'])) {
            $result['chart_url'] = $chartResult['chart_url'];
            $result['data_url']  = $chartResult['data_url'] ?? null;
        }
        return $result;
    }

    /** dataset_quality → CSV profiler */
    private function runDatasetQuality(string $question): array
    {
        $result = $this->engine->post('/csv/profile', [
            'file_path'   => Support::config('default_csv_path'),
            'sample_rows' => 5000,
        ]);
        return array_merge($result, ['_engine' => 'data_analysis', '_model' => $this->model]);
    }

    /** unknown → RAG + Ollama; la orientación estática solo queda como último fallback. */
    
    private function runUnknown(string $question): array
    {
        return $this->runRagGuidedAssistant($question, null);
    }



    

    

    

    

    

    

    



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


    // ─── Helpers ──────────────────────────────────────────────────────────────

    private function mergeHybrid(array $data, array $rag, string $question): array
    {
        $rows     = $data['query']['rows'] ?? $data['rows'] ?? [];
        $evidence = $rag['evidence'] ?? [];
        $ragText  = $rag['answer'] ?? '';

        $context  = '';
        if (!empty($rows)) {
            $context .= "Datos estructurados:\n" . json_encode(array_slice($rows, 0, 10), JSON_UNESCAPED_UNICODE) . "\n\n";
        }
        if ($ragText !== '') {
            $context .= "Contenido curricular:\n$ragText\n";
        }

        $answer = $this->aiSummarize(
            "Responde de forma concisa y académica usando los datos disponibles.\n\n$context\nPregunta: $question",
            700
        );

        return [
            'ok'       => true,
            'answer'   => $answer,
            'evidence' => $evidence,
            'table'    => !empty($rows) ? ['rows' => array_slice($rows, 0, 30), 'columns' => array_keys($rows[0] ?? [])] : null,
            '_sql'     => $data['_sql'] ?? null,
            '_model'   => $this->model,
        ];
    }

    private function buildContext(array $data, array $rag): string
    {
        $parts = [];
        $rows  = $data['query']['rows'] ?? $data['rows'] ?? [];
        if (!empty($rows)) {
            $parts[] = "Datos:\n" . json_encode(array_slice($rows, 0, 15), JSON_UNESCAPED_UNICODE);
        }
        $ragText = $rag['answer'] ?? '';
        if ($ragText !== '') {
            $parts[] = "Contenido:\n$ragText";
        }
        return implode("\n\n", $parts);
    }

    private function extractProgramName(string $question): string
    {
        $q = Support::normalize($question);
        $known = ['ingenieria de sistemas', 'ingenieria civil', 'ingenieria ambiental', 'arquitectura', 'administracion', 'contabilidad', 'psicologia', 'enfermeria', 'medicina', 'nutricion', 'teologia', 'educacion'];
        foreach ($known as $k) {
            if (str_contains($q, Support::normalize($k))) return mb_convert_case($k, MB_CASE_TITLE, 'UTF-8');
        }
        return 'Programa académico';
    }

    private function referenceCoursesForProgram(string $program): array
    {
        $dir = __DIR__ . '/../resources/curriculum_reference/mallas';
        $norm = Support::normalize($program);
        $fallback = ['Comunicación Académica', 'Matemática Básica', 'Cosmovisión Bíblico-Cristiana', 'Metodología de la Investigación', 'Fundamentos de la Profesión', 'Ética Profesional y Servicio', 'Práctica Preprofesional', 'Trabajo de Investigación'];
        if (!is_dir($dir)) return $fallback;
        $best = null; $scoreBest = 0;
        foreach (glob($dir . '/*.md') ?: [] as $file) {
            $base = Support::normalize(basename($file, '.md'));
            $score = 0;
            foreach (preg_split('/[^a-z0-9]+/', $norm) ?: [] as $token) {
                if (strlen($token) > 3 && str_contains($base, $token)) $score++;
            }
            if ($score > $scoreBest) { $scoreBest = $score; $best = $file; }
        }
        if (!$best) return $fallback;
        $text = (string)file_get_contents($best);
        preg_match_all('/\|\s*([^|\n]{4,80})\s*\|\s*(\d+)\s*\|/u', $text, $m);
        $out = [];
        foreach (($m[1] ?? []) as $name) {
            $name = trim(strip_tags($name));
            if ($name !== '' && !in_array($name, $out, true)) $out[] = $name;
        }
        return $out ?: $fallback;
    }

    private function deterministicStudyPlanMarkdown(string $program, int $cycles, array $courses): string
    {
        $md = "# Plan de estudios preliminar: {$program}\n\n";
        $md .= "Generación rápida basada en plantilla curricular, referencias locales y revisión posterior por comité.\n\n";
        $i = 0;
        for ($c = 1; $c <= $cycles; $c++) {
            $md .= "## Ciclo {$c}\n";
            for ($j = 0; $j < 4 && $i < count($courses); $j++, $i++) {
                $credits = ($j === 0) ? 4 : 3;
                $md .= "- {$courses[$i]} ({$credits} créditos)\n";
            }
            $md .= "\n";
        }
        $md .= "## Lineamientos\n- Validar créditos, horas, prerrequisitos y denominación oficial según normativa peruana y criterios SUNEDU aplicables.\n";
        $md .= "- Mantener integración fe-aprendizaje sobria, bíblica y pertinente al curso, sin lenguaje new age.\n";
        return $md;
    }

    private function aiSummarize(string $prompt, int $maxTokens = 600): string
    {
        try {
            $result = $this->ollama->generate($prompt, $this->model, [
                'temperature' => 0.25,
                'num_predict' => min($maxTokens, 700),
                'num_ctx' => 3072,
            ], (int)Support::config('ollama_http_timeout'));
            return trim((string)($result['response'] ?? ''));
        } catch (Throwable $e) {
            return 'No se pudo generar una respuesta en este momento. Verifique la disponibilidad del asistente.';
        }
    }

    private function sanitizeExplanation(string $text): string
    {
        return trim($text);
    }

    private function isSafeSql(string $sql): bool
    {
        $lower = strtolower(trim($sql));
        if (!str_starts_with($lower, 'select') && !str_starts_with($lower, 'with')) {
            return false;
        }
        foreach (self::BLOCKED_SQL as $word) {
            if (preg_match('/\b' . preg_quote($word, '/') . '\b/', $lower)) {
                return false;
            }
        }
        return true;
    }

    private function addLimitIfMissing(string $sql, int $limit): string
    {
        if (stripos($sql, 'limit') === false) {
            return rtrim(trim($sql), ';') . " LIMIT $limit";
        }
        return $sql;
    }

    private function extractJson(string $raw): array
    {
        $text = preg_replace('/^```(?:json)?/i', '', trim($raw)) ?? $raw;
        $text = preg_replace('/```$/', '', trim($text)) ?? $text;
        $decoded = json_decode(trim($text), true);
        if (is_array($decoded)) {
            return $decoded;
        }
        if (preg_match('/\{.*\}/s', $raw, $m)) {
            $decoded = json_decode($m[0], true);
            if (is_array($decoded)) {
                return $decoded;
            }
        }
        return [];
    }
}
