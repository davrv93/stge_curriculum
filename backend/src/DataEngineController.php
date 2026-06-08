<?php

final class DataEngineController
{
    public function health(): void
    {
        Support::requireAuth();
        Support::json((new DataEngineClient())->get('/health'));
    }

    public function tables(): void
    {
        Support::requireAuth();
        Support::json((new DataEngineClient())->get('/duckdb/tables'));
    }

    public function schema(): void
    {
        Support::requireAuth();
        $table = trim((string)($_GET['table'] ?? 'silabos'));
        Support::json((new DataEngineClient())->get('/duckdb/schema', ['table' => $table]));
    }

    public function preview(): void
    {
        Support::requireAuth();
        $table = trim((string)($_GET['table'] ?? 'silabos'));
        $limit = (int)($_GET['limit'] ?? 10);
        Support::json((new DataEngineClient())->get('/duckdb/preview', ['table' => $table, 'limit' => $limit]));
    }

    public function profileCsv(): void
    {
        Support::requireAuth();
        $data = Support::readJson();
        $payload = [
            'file_path' => trim((string)($data['file_path'] ?? Support::config('default_csv_path'))),
            'delimiter' => $this->nullableString($data['delimiter'] ?? null),
            'encoding' => $this->nullableString($data['encoding'] ?? null),
            'sample_rows' => (int)($data['sample_rows'] ?? 5000),
        ];
        $res = (new DataEngineClient())->post('/csv/profile', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function importDuckdb(): void
    {
        Support::requireAdmin();
        $data = Support::readJson();
        $payload = [
            'file_path' => trim((string)($data['file_path'] ?? Support::config('default_csv_path'))),
            'table' => trim((string)($data['table'] ?? 'silabos')),
            'delimiter' => ($data['delimiter'] ?? null) === '' ? null : ($data['delimiter'] ?? null),
            'encoding' => ($data['encoding'] ?? null) === '' ? null : ($data['encoding'] ?? null),
            'quote' => ($data['quote'] ?? null) === '' ? null : ($data['quote'] ?? '"'),
            'escape' => ($data['escape'] ?? null) === '' ? null : ($data['escape'] ?? '"'),
            'skip_rows' => (int)($data['skip_rows'] ?? 0),
            'strict_mode' => (bool)($data['strict_mode'] ?? false),
            'null_padding' => (bool)($data['null_padding'] ?? true),
            'max_line_size' => (int)($data['max_line_size'] ?? 10000000),
            'replace' => (bool)($data['replace'] ?? true),
            'sample_size' => (int)($data['sample_size'] ?? 20000),
            'normalize_columns' => (bool)($data['normalize_columns'] ?? true),
        ];
        $res = (new DataEngineClient())->post('/duckdb/import', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function queryDuckdb(): void
    {
        Support::requireAuth();
        $data = Support::readJson();
        $payload = [
            'sql' => (string)($data['sql'] ?? ''),
            'limit' => (int)($data['limit'] ?? 100),
        ];
        $res = (new DataEngineClient())->post('/duckdb/query', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function chartSql(): void
    {
        Support::requireAuth();
        $data = Support::readJson();
        $payload = [
            'sql' => (string)($data['sql'] ?? ''),
            'chart_type' => trim((string)($data['chart_type'] ?? 'bar')),
            'title' => trim((string)($data['title'] ?? 'Reporte curricular')),
            'x' => $this->nullableString($data['x'] ?? null),
            'y' => $this->nullableString($data['y'] ?? null),
            'limit' => (int)($data['limit'] ?? 200),
        ];
        $res = (new DataEngineClient())->post('/duckdb/chart', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function naturalChart(): void
    {
        $user = Support::requireAuth();
        $data = Support::readJson();
        $question = trim((string)($data['question'] ?? ''));
        $table = trim((string)($data['table'] ?? 'silabos'));
        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));

        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe qué gráfico necesitas.'], 422);
            return;
        }

        $chartSpec = $this->generateChartSpec($question, $table, $model);

        if (!($chartSpec['ok'] ?? false)) {
            Support::json($chartSpec, 422);
            return;
        }

        $res = (new DataEngineClient())->post('/duckdb/chart', [
            'sql' => $chartSpec['sql'],
            'chart_type' => $chartSpec['chart_type'] ?? 'bar',
            'title' => $chartSpec['title'] ?? 'Reporte curricular',
            'x' => $chartSpec['x'] ?? null,
            'y' => $chartSpec['y'] ?? null,
            'limit' => (int)($data['limit'] ?? 200),
        ]);

        $this->saveRun((int)$user['id'], $model, 'natural_chart', $question, json_encode($chartSpec, JSON_UNESCAPED_UNICODE), ['chart' => $res]);

        Support::json([
            'ok' => (bool)($res['ok'] ?? false),
            'model' => $model,
            'question' => $question,
            'spec' => $chartSpec,
            'chart' => $res,
        ], ($res['ok'] ?? false) ? 200 : 422);
    }

    public function naturalSql(): void
    {
        $user = Support::requireAuth();
        $data = Support::readJson();
        $question = trim((string)($data['question'] ?? ''));
        $table = trim((string)($data['table'] ?? 'silabos'));
        $limit = (int)($data['limit'] ?? 100);
        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));

        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe una pregunta para generar SQL.'], 422);
            return;
        }

        $result = $this->generateAndRunSql($question, $table, $limit, $model);
        $this->saveRun((int)$user['id'], $model, 'natural_sql', $question, (string)($result['model_response'] ?? ''), $result);

        Support::json($result, ($result['ok'] ?? false) ? 200 : 422);
    }
    public function userAskStream(): void
    {
        ini_set('max_execution_time', '0');

        $user = Support::requireAuth();
        $data = Support::readJson();

        $question = trim((string)($data['question'] ?? ''));
        $context = trim((string)($data['context'] ?? 'chat'));

        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe tu pregunta.'], 422);
            return;
        }

        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));
        if ($model === '' || str_contains($model, '0.5b')) {
            $model = 'qwen2.5-coder:3b';
        }

        $maxTokens = (int)($data['max_tokens'] ?? 420);
        $maxTokens = max(120, min($maxTokens, 700));

        $numCtx = (int)($data['num_ctx'] ?? 2048);
        $numCtx = max(1024, min($numCtx, 4096));

        $nResults = (int)($data['n_results'] ?? 2);
        $nResults = max(0, min($nResults, 3));

        $temperature = (float)($data['temperature'] ?? 0.22);
        $temperature = max(0.05, min($temperature, 0.7));

        $topP = (float)($data['top_p'] ?? 0.85);
        $topP = max(0.3, min($topP, 0.95));

        $tokensConfig = [
            'model' => $model,
            'num_ctx' => $numCtx,
            'num_predict' => $maxTokens,
            'n_results' => $nResults,
            'temperature' => $temperature,
            'top_p' => $topP,
            'stream' => true,
        ];

        $this->sseStart();

        $this->sseSend('config', [
            'ok' => true,
            'tokens_config' => $tokensConfig,
            'message' => "Modelo {$model}, contexto {$numCtx}, salida {$maxTokens} tokens, RAG {$nResults}.",
        ]);

        /*
     * Si la pregunta es académica estructurada, no conviene pasar por Ollama.
     * Responde rápido como evento final.
     */
        if ($this->looksLikeAcademicLoadedDataQuestion($question)) {
            $academic = $this->answerAcademicLoadedDataQuestion($question, 'silabos');

            if (($academic['ok'] ?? false)) {
                $answer = (string)($academic['answer'] ?? 'Consulta académica resuelta.');

                $this->saveRun(
                    (int)$user['id'],
                    'no_ollama',
                    'user_ask_stream_academic',
                    $question,
                    $answer,
                    ['academic' => $academic, 'tokens_config' => $tokensConfig]
                );

                $this->sseSend('token', ['text' => $answer]);

                $this->sseSend('final', [
                    'ok' => true,
                    'mode' => $academic['mode'] ?? 'sql',
                    'answer' => $answer,
                    'tokens_config' => $tokensConfig,
                    'data' => $academic,
                ]);

                return;
            }
        }

        $sources = [];
        $ragContext = '';

        if ($nResults > 0) {
            try {
                $collection = trim((string)($data['collection'] ?? 'jomelai_knowledge'));
                if ($collection === '' || $collection === 'auto' || $collection === 'silabos') {
                    $collection = Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge';
                }

                $rag = (new DataEngineClient())->post('/rag/search', [
                    'query' => $question,
                    'collection' => $collection,
                    'n_results' => $nResults,
                ]);

                $sources = $rag['results'] ?? $rag['sources'] ?? $rag['evidence'] ?? [];

                if (!empty($sources)) {
                    $ragContext = json_encode(
                        array_slice($sources, 0, $nResults),
                        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT
                    );
                }
            } catch (Throwable $e) {
                $sources = [];
                $ragContext = '';
            }
        }

        $system = "Eres JoMelAi, asistente curricular universitario. Responde en español con claridad, estructura y tono académico sobrio. " .
            "Si el usuario pide recursos de aprendizaje, responde como documento editable con título, propósito, instrucciones, secuencia, producto esperado, criterios de evaluación y recomendaciones. " .
            "Si es chat general, responde con secciones breves. No inventes datos institucionales específicos.";

        try {
            $system = CurriculumGuidelines::systemPrompt() . "\n\n" . $system;
        } catch (Throwable $e) {
            // Mantener prompt local.
        }

        $prompt =
            $system . "\n\n" .
            "CONFIGURACIÓN ACTIVA:\n" .
            "- Modelo: {$model}\n" .
            "- Contexto máximo: {$numCtx} tokens\n" .
            "- Salida máxima: {$maxTokens} tokens\n" .
            "- Fragmentos RAG: {$nResults}\n\n" .
            ($ragContext !== '' ? "CONTEXTO RAG RECUPERADO:\n{$ragContext}\n\n" : "") .
            "CONTEXTO UI: {$context}\n\n" .
            "PREGUNTA DEL USUARIO:\n{$question}\n\n" .
            "RESPUESTA:";

        $answer = '';

        try {
            $this->streamOllamaGenerate(
                $model,
                $prompt,
                [
                    'temperature' => $temperature,
                    'top_p' => $topP,
                    'repeat_penalty' => 1.08,
                    'num_ctx' => $numCtx,
                    'num_predict' => $maxTokens,
                    'num_thread' => 4,
                ],
                function (string $piece) use (&$answer) {
                    $answer .= $piece;
                    $this->sseSend('token', ['text' => $piece]);
                }
            );
        } catch (Throwable $e) {
            $errorText = "\n\nNo pude completar la generación por streaming: " . $e->getMessage();
            $answer .= $errorText;
            $this->sseSend('token', ['text' => $errorText]);
        }

        $answer = trim($answer);

        if ($answer === '') {
            $answer = 'No se obtuvo contenido del modelo. Intenta nuevamente con una pregunta más específica.';
            $this->sseSend('token', ['text' => $answer]);
        }

        $this->saveRun(
            (int)$user['id'],
            $model,
            'user_ask_stream',
            $question,
            $answer,
            [
                'tokens_config' => $tokensConfig,
                'sources' => $sources,
            ]
        );

        $this->sseSend('final', [
            'ok' => true,
            'mode' => 'ask_stream',
            'answer' => $answer,
            'tokens_config' => $tokensConfig,
            'evidence' => $sources,
        ]);
    }

    private function sseStart(): void
    {
        ignore_user_abort(true);
        @set_time_limit(0);

        while (ob_get_level() > 0) {
            @ob_end_flush();
        }

        @ini_set('output_buffering', 'off');
        @ini_set('zlib.output_compression', '0');
        @ini_set('implicit_flush', '1');
        @ob_implicit_flush(true);

        header('Content-Type: text/event-stream; charset=utf-8');
        header('Cache-Control: no-cache, no-transform');
        header('Connection: keep-alive');
        header('X-Accel-Buffering: no');
        header('Content-Encoding: none');

        echo ':' . str_repeat(' ', 4096) . "\n\n";
        echo "event: ready\n";
        echo 'data: ' . json_encode(['ok' => true], JSON_UNESCAPED_UNICODE) . "\n\n";

        @ob_flush();
        @flush();
    }

    private function sseSend(string $event, array $data): void
    {
        echo "event: {$event}\n";
        echo 'data: ' . json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n\n";

        @ob_flush();
        @flush();
    }

    private function streamOllamaGenerate(string $model, string $prompt, array $options, callable $onToken): array
    {
        $baseUrl = '';

        try {
            $baseUrl = rtrim((string)Support::config('ollama_base_url'), '/');
        } catch (Throwable $e) {
            $baseUrl = '';
        }

        if ($baseUrl === '') {
            $baseUrl = 'http://jomelai_ollama:11434';
        }

        $payload = [
            'model' => $model,
            'prompt' => $prompt,
            'stream' => true,
            'options' => $options,
        ];

        $raw = '';
        $buffer = '';

        $ch = curl_init($baseUrl . '/api/generate');

        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
            CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            CURLOPT_RETURNTRANSFER => false,
            CURLOPT_HEADER => false,
            CURLOPT_TIMEOUT => 0,
            CURLOPT_WRITEFUNCTION => function ($ch, string $chunk) use (&$buffer, &$raw, $onToken) {
                $buffer .= $chunk;

                while (($pos = strpos($buffer, "\n")) !== false) {
                    $line = trim(substr($buffer, 0, $pos));
                    $buffer = substr($buffer, $pos + 1);

                    if ($line === '') {
                        continue;
                    }

                    $json = json_decode($line, true);

                    if (!is_array($json)) {
                        continue;
                    }

                    $piece = (string)($json['response'] ?? '');

                    if ($piece !== '') {
                        $raw .= $piece;
                        $onToken($piece);
                    }
                }

                return strlen($chunk);
            },
        ]);

        $ok = curl_exec($ch);

        if ($ok === false) {
            $error = curl_error($ch);
            curl_close($ch);
            throw new RuntimeException('Error conectando con Ollama: ' . $error);
        }

        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        return [
            'ok' => $status >= 200 && $status < 300,
            'status' => $status,
            'response' => $raw,
        ];
    }
    public function userAsk(): void
    {
        $user = Support::requireAuth();
        $data = Support::readJson();
        $question = trim((string)($data['question'] ?? ''));
        $mode = trim((string)($data['mode'] ?? 'auto'));
        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));
        $table = trim((string)($data['table'] ?? 'silabos'));
        $collection = trim((string)($data['collection'] ?? 'jomelai_knowledge'));

        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe tu pregunta.'], 422);
            return;
        }

        if ($mode === 'auto' && $this->looksLikeCurricularAdvisoryQuestion($question)) {
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

        $decision = $mode === 'auto' ? $this->decideMode($question) : $mode;

        if ($decision === 'chart') {
            $chartSpec = $this->generateChartSpec($question, $table, $model);

            if (!($chartSpec['ok'] ?? false)) {
                Support::json($chartSpec, 422);
                return;
            }

            $chart = (new DataEngineClient())->post('/duckdb/chart', [
                'sql' => $chartSpec['sql'],
                'chart_type' => $chartSpec['chart_type'] ?? 'bar',
                'title' => $chartSpec['title'] ?? 'Reporte curricular',
                'x' => $chartSpec['x'] ?? null,
                'y' => $chartSpec['y'] ?? null,
                'limit' => 200,
            ]);

            $answer = 'Generé el gráfico solicitado usando DuckDB sobre la base local. Revisa también la tabla de apoyo debajo del gráfico.';
            $this->saveRun((int)$user['id'], $model, 'user_chart', $question, $answer, ['spec' => $chartSpec, 'chart' => $chart]);

            Support::json([
                'ok' => (bool)($chart['ok'] ?? false),
                'mode' => 'chart',
                'answer' => $answer,
                'chart' => $chart,
                'spec' => $chartSpec,
            ], ($chart['ok'] ?? false) ? 200 : 422);

            return;
        }

        if ($decision === 'sql') {
            $sqlResult = $this->generateAndRunSql($question, $table, 80, $model);

            if (!($sqlResult['ok'] ?? false)) {
                Support::json($sqlResult, 422);
                return;
            }

            $rows = $sqlResult['query']['rows'] ?? [];
            $summaryPrompt = CurriculumGuidelines::systemPrompt() . "\n\nResume en español, con tono academico sobrio, el resultado de esta consulta sobre sílabos. No inventes datos.\nPregunta: {$question}\nSQL: {$sqlResult['sql']}\nFilas: " . json_encode($rows, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            $ollama = (new OllamaClient())->generate($summaryPrompt, $model, ['temperature' => 0.1]);
            $answer = (string)($ollama['response'] ?? 'Consulta ejecutada.');

            $this->saveRun((int)$user['id'], $model, 'user_sql', $question, $answer, $sqlResult);

            Support::json([
                'ok' => true,
                'mode' => 'sql',
                'answer' => $answer,
                'sql' => $sqlResult['sql'],
                'query' => $sqlResult['query'],
            ]);

            return;
        }

        if ($collection === 'silabos' || $collection === '' || $collection === 'auto') {
            $collection = Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge';
        }

        $rag = (new DataEngineClient())->post('/rag/answer', [
            'question' => $question,
            'collection' => $collection,
            'model' => $model,
            'n_results' => (int)($data['n_results'] ?? 5),
        ]);

        if (!($rag['ok'] ?? false)) {
            Support::json($rag, 422);
            return;
        }

        $answer = (string)($rag['answer'] ?? '');

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
    }

    public function buildRag(): void
    {
        Support::requireAdmin();
        $data = Support::readJson();
        $payload = [
            'file_path' => trim((string)($data['file_path'] ?? Support::config('default_csv_path'))),
            'collection' => trim((string)($data['collection'] ?? 'silabos')),
            'delimiter' => ($data['delimiter'] ?? null) === '' ? null : ($data['delimiter'] ?? null),
            'encoding' => ($data['encoding'] ?? null) === '' ? null : ($data['encoding'] ?? null),
            'chunk_size_rows' => (int)($data['chunk_size_rows'] ?? 1000),
            'row_limit' => (int)($data['row_limit'] ?? 0),
            'text_columns' => $this->csvList($data['text_columns'] ?? ''),
            'metadata_columns' => $this->csvList($data['metadata_columns'] ?? ''),
            'document_chars' => (int)($data['document_chars'] ?? 1300),
            'overlap_chars' => (int)($data['overlap_chars'] ?? 150),
            'embed_batch_size' => (int)($data['embed_batch_size'] ?? 16),
            'reset_collection' => (bool)($data['reset_collection'] ?? false),
        ];
        $res = (new DataEngineClient())->post('/rag/build', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function buildRagCollections(): void
    {
        Support::requireAdmin();
        $data = Support::readJson();
        $payload = [
            'file_path' => trim((string)($data['file_path'] ?? Support::config('default_csv_path'))),
            'collection_prefix' => trim((string)($data['collection_prefix'] ?? 'silabos')),
            'delimiter' => $this->nullableString($data['delimiter'] ?? null),
            'encoding' => $this->nullableString($data['encoding'] ?? null),
            'chunk_size_rows' => (int)($data['chunk_size_rows'] ?? 1000),
            'row_limit' => (int)($data['row_limit'] ?? 0),
            'metadata_columns' => $this->csvList($data['metadata_columns'] ?? []),
            'document_chars' => (int)($data['document_chars'] ?? 1300),
            'overlap_chars' => (int)($data['overlap_chars'] ?? 150),
            'embed_batch_size' => (int)($data['embed_batch_size'] ?? 16),
            'reset_collections' => (bool)($data['reset_collections'] ?? false),
            'collections' => $this->csvList($data['collections'] ?? []),
        ];
        $res = (new DataEngineClient())->post('/rag/build-collections', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function searchRag(): void
    {
        Support::requireAuth();
        $data = Support::readJson();
        $payload = [
            'query' => trim((string)($data['query'] ?? '')),
            'collection' => trim((string)($data['collection'] ?? 'silabos')),
            'n_results' => (int)($data['n_results'] ?? 5),
        ];
        $res = (new DataEngineClient())->post('/rag/search', $payload);
        Support::json($res, ($res['ok'] ?? false) ? 200 : 422);
    }

    public function ragAnswer(): void
    {
        $user = Support::requireAuth();
        $data = Support::readJson();
        $question = trim((string)($data['question'] ?? ''));
        $collection = trim((string)($data['collection'] ?? 'jomelai_knowledge'));
        $model = trim((string)($data['model'] ?? Support::config('ollama_default_model')));

        if ($question === '') {
            Support::json(['ok' => false, 'message' => 'Escribe una pregunta curricular.'], 422);
            return;
        }

        $rag = (new DataEngineClient())->post('/rag/answer', [
            'question' => $question,
            'collection' => $collection,
            'model' => $model,
            'n_results' => (int)($data['n_results'] ?? 5),
        ]);

        if (!($rag['ok'] ?? false)) {
            Support::json($rag, 422);
            return;
        }

        $prompt = CurriculumGuidelines::systemPrompt() . "\n\n" .
            "Usa los fragmentos RAG recuperados como evidencia curricular. No inventes datos no presentes. " .
            "Cuando propongas un nuevo silabo, usa diseno inverso, alineacion constructiva, resultados medibles y lenguaje compatible con identidad adventista.\n\n" .
            "Fragmentos recuperados:\n" . json_encode($rag['results'] ?? [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT) . "\n\n" .
            "Pregunta o encargo del usuario:\n{$question}";

        $ollama = (new OllamaClient())->generate($prompt, $model, ['temperature' => 0.15]);
        $response = (string)($ollama['response'] ?? '');

        $this->saveRun((int)$user['id'], $model, 'rag_answer', $question, $response, ['rag' => $rag]);

        Support::json([
            'ok' => true,
            'model' => $model,
            'response' => $response,
            'rag' => $rag,
        ]);
    }

    private function generateAndRunSql(string $question, string $table, int $limit, string $model): array
    {
        $client = new DataEngineClient();
        $fast = $client->post('/intent/resolve', ['question' => $question, 'table' => $table]);
        if (($fast['ok'] ?? false) && !empty($fast['sql']) && (float)($fast['confidence'] ?? 0) >= 0.75) {
            $query = $client->post('/duckdb/query', ['sql' => (string)$fast['sql'], 'limit' => $limit]);
            return [
                'ok' => (bool)($query['ok'] ?? false),
                'model' => 'no_ollama',
                'question' => $question,
                'sql' => (string)$fast['sql'],
                'explanation' => 'Consulta resuelta por FastIntentEngine sin Ollama.',
                'spec' => $fast,
                'query' => $query,
            ];
        }

        $schema = $client->get('/duckdb/schema', ['table' => $table]);

        if (!($schema['ok'] ?? false)) {
            return $schema;
        }

        $columns = array_map(fn($c) => $c['name'] . ' ' . $c['type'], $schema['columns'] ?? []);

        $prompt = "Eres un generador SQL para DuckDB en una app academica UPeU.\n" .
            "Devuelve SOLO JSON valido con esta forma: {\"sql\":\"SELECT ...\",\"explanation\":\"...\"}.\n" .
            "Reglas obligatorias: solo SELECT o WITH; no INSERT, UPDATE, DELETE, CREATE, DROP, COPY, PRAGMA ni multiples sentencias; usa LIMIT {$limit}; no inventes columnas; tabla disponible: {$table}.\n" .
            "Para conteos usa alias claros como total. Para distribuciones usa GROUP BY y ORDER BY total DESC.\n" .
            "Columnas: " . implode(', ', $columns) . "\n" .
            "Pregunta del usuario: {$question}";

        $ollama = (new OllamaClient())->generate($prompt, $model, ['temperature' => 0.05]);
        $raw = (string)($ollama['response'] ?? '');
        $parsed = $this->extractJson($raw);
        $sql = trim((string)($parsed['sql'] ?? ''));

        if ($sql === '') {
            return [
                'ok' => false,
                'message' => 'El modelo no devolvió SQL válido.',
                'model_response' => $raw,
            ];
        }

        $query = $client->post('/duckdb/query', [
            'sql' => $sql,
            'limit' => $limit,
        ]);

        return [
            'ok' => (bool)($query['ok'] ?? false),
            'model' => $model,
            'question' => $question,
            'sql' => $sql,
            'explanation' => (string)($parsed['explanation'] ?? ''),
            'model_response' => $raw,
            'query' => $query,
        ];
    }


    private function generateChartSpec(string $question, string $table, string $model): array
    {
        $client = new DataEngineClient();
        $fast = $client->post('/intent/resolve', ['question' => $question, 'table' => $table]);
        if (($fast['ok'] ?? false) && !empty($fast['sql']) && (float)($fast['confidence'] ?? 0) >= 0.75) {
            return [
                'ok' => true,
                'sql' => (string)$fast['sql'],
                'chart_type' => trim((string)($fast['chart_type'] ?? 'bar')),
                'title' => trim((string)($fast['title'] ?? 'Reporte curricular')),
                'x' => $this->nullableString($fast['x'] ?? null),
                'y' => $this->nullableString($fast['y'] ?? null),
                'model_response' => 'FastIntentEngine sin Ollama',
                'confidence' => (float)($fast['confidence'] ?? 0),
                'spec' => $fast,
            ];
        }

        $schema = $client->get('/duckdb/schema', ['table' => $table]);

        if (!($schema['ok'] ?? false)) {
            return $schema;
        }

        $columns = array_map(fn($c) => $c['name'] . ' ' . $c['type'], $schema['columns'] ?? []);

        $prompt = "Eres un generador de especificaciones de graficos para DuckDB y matplotlib.\n" .
            "Devuelve SOLO JSON valido con esta forma exacta: {\"sql\":\"SELECT categoria, COUNT(*) AS total FROM {$table} GROUP BY categoria ORDER BY total DESC LIMIT 20\",\"chart_type\":\"bar\",\"title\":\"...\",\"x\":\"categoria\",\"y\":\"total\"}.\n" .
            "chart_type debe ser bar, horizontal_bar, line, pie, scatter, area, histogram, boxplot o heatmap. Solo SELECT/WITH. No inventes columnas. Tabla: {$table}. Columnas: " . implode(', ', $columns) . "\n" .
            "IMPORTANTE: todas las columnas del CSV estan importadas como VARCHAR. Para cualquier operacion numerica usa siempre TRY_CAST(columna AS DOUBLE). Nunca uses SUM(creditos), AVG(creditos), MIN(creditos), MAX(creditos), SUM(horas_teoricas) ni SUM(horas_practicas) directamente.\n" .
            "Ejemplo correcto: SUM(TRY_CAST(creditos AS DOUBLE)) AS total_creditos.\n" .
            "Para bar, horizontal_bar, line, area o pie, devuelve una columna de categoria/tiempo y una columna numerica agregada.\n" .
            "Para scatter, devuelve dos columnas numericas casteadas con alias exactos x e y. El JSON debe usar \"x\":\"x\" y \"y\":\"y\".\n" .
            "Para histogram, devuelve una columna numerica casteada con alias value. El JSON debe usar \"x\":\"value\" y \"y\":null.\n" .
            "Para boxplot, devuelve categoria y value. El JSON debe usar \"x\":\"categoria\" y \"y\":\"value\".\n" .
            "Para heatmap, devuelve x, y y value. value debe ser numerico agregado.\n" .
            "Solicitud: {$question}";

        $ollama = (new OllamaClient())->generate($prompt, $model, [
            'temperature' => 0.0,
            'num_predict' => 220,
            'num_ctx' => 2048,
        ]);

        $raw = (string)($ollama['response'] ?? '');
        $parsed = $this->extractJson($raw);
        $sql = trim((string)($parsed['sql'] ?? ''));

        if ($sql === '') {
            return [
                'ok' => false,
                'message' => 'El modelo no devolvió una especificación de gráfico válida.',
                'model_response' => $raw,
            ];
        }

        $sql = $this->patchNumericSql($sql);

        return [
            'ok' => true,
            'sql' => $sql,
            'chart_type' => trim((string)($parsed['chart_type'] ?? 'bar')),
            'title' => trim((string)($parsed['title'] ?? 'Reporte curricular')),
            'x' => $this->nullableString($parsed['x'] ?? null),
            'y' => $this->nullableString($parsed['y'] ?? null),
            'model_response' => $raw,
        ];
    }
    private function patchNumericSql(string $sql): string
    {
        $numericColumns = [
            'creditos',
            'horas_teoricas',
            'horas_practicas',
            'ciclo',
        ];

        foreach ($numericColumns as $col) {
            $q = preg_quote($col, '/');

            $sql = preg_replace(
                '/\bSUM\s*\(\s*' . $q . '\s*\)/i',
                'SUM(TRY_CAST(' . $col . ' AS DOUBLE))',
                $sql
            ) ?? $sql;

            $sql = preg_replace(
                '/\bAVG\s*\(\s*' . $q . '\s*\)/i',
                'AVG(TRY_CAST(' . $col . ' AS DOUBLE))',
                $sql
            ) ?? $sql;

            $sql = preg_replace(
                '/\bMIN\s*\(\s*' . $q . '\s*\)/i',
                'MIN(TRY_CAST(' . $col . ' AS DOUBLE))',
                $sql
            ) ?? $sql;

            $sql = preg_replace(
                '/\bMAX\s*\(\s*' . $q . '\s*\)/i',
                'MAX(TRY_CAST(' . $col . ' AS DOUBLE))',
                $sql
            ) ?? $sql;
        }

        return $sql;
    }

    private function decideMode(string $question): string
    {
        $q = Support::normalize($question);
        $chartTokens = [
            'grafico',
            'grafica',
            'barras',
            'barra',
            'linea',
            'pastel',
            'pie',
            'chart',
            'visualiza',
            'dashboard',
            'scatter',
            'dispersion',
            'area',
            'histograma',
            'histogram',
            'boxplot',
            'caja',
            'bigotes',
            'heatmap',
            'mapa de calor',
            'correlacion',
            'distribucion',
        ];

        foreach ($chartTokens as $token) {
            if (str_contains($q, $token)) {
                return 'chart';
            }
        }

        $sqlTokens = [
            'cuantos',
            'conteo',
            'cantidad',
            'lista',
            'filtra',
            'periodo',
            'facultad',
            'programa',
            'ciclo',
            'creditos',
            'top',
            'ranking',
            'distribucion',
            'porcentaje',
        ];

        foreach ($sqlTokens as $token) {
            if (str_contains($q, $token)) {
                return 'sql';
            }
        }

        return 'rag';
    }

    private function decideCollection(string $question): string
    {
        $q = Support::normalize($question);

        if (str_contains($q, 'bibliografia') || str_contains($q, 'referencia') || str_contains($q, 'libro') || str_contains($q, 'articulo')) {
            return 'silabos_bibliografia';
        }

        if (str_contains($q, 'competencia') || str_contains($q, 'resultado') || str_contains($q, 'aprendizaje') || str_contains($q, 'perfil') || str_contains($q, 'capacidad')) {
            return 'silabos_competencias';
        }

        if (str_contains($q, 'sumilla') || str_contains($q, 'descripcion') || str_contains($q, 'presentacion')) {
            return 'silabos_sumillas';
        }

        if (str_contains($q, 'contenido') || str_contains($q, 'unidad') || str_contains($q, 'tema') || str_contains($q, 'semana')) {
            return 'silabos_contenidos';
        }

        return 'silabos_general';
    }

    private function nullableString(mixed $value): ?string
    {
        $v = trim((string)($value ?? ''));
        return $v === '' ? null : $v;
    }

    private function csvList(mixed $value): array
    {
        if (is_array($value)) {
            return array_values(array_filter(array_map('trim', $value), fn($v) => $v !== ''));
        }

        $parts = preg_split('/[,\n]+/', (string)$value) ?: [];

        return array_values(array_filter(array_map('trim', $parts), fn($v) => $v !== ''));
    }

    private function extractJson(string $raw): array
    {
        $text = trim($raw);
        $text = preg_replace('/^```(?:json)?/i', '', $text) ?? $text;
        $text = preg_replace('/```$/', '', trim($text)) ?? $text;
        $decoded = json_decode($text, true);

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

    private function saveRun(int $userId, string $model, string $taskType, string $prompt, string $response, array $context): void
    {
        $stmt = Database::pdo()->prepare('INSERT INTO assistant_runs (user_id, model, task_type, prompt, response, context_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)');
        $stmt->execute([
            $userId,
            $model,
            $taskType,
            $prompt,
            $response,
            json_encode($context, JSON_UNESCAPED_UNICODE),
            Support::now(),
        ]);
    }


    private function looksLikeAcademicLoadedDataQuestion(string $question): bool
    {
        $q = Support::normalize($question);

        $actionTokens = [
            'que',
            'qué',
            'cuales',
            'cuáles',
            'lista',
            'listar',
            'listame',
            'listarme',
            'muestrame',
            'muéstrame',
            'mostrar',
            'dame',
            'ver',
            'consulta',
            'consultar',
            'cuantos',
            'cuántos',
            'cuantas',
            'cuántas',
            'grafico',
            'gráfico',
            'grafica',
            'gráfica',
            'barras',
            'pie',
            'pastel',
            'torta'
        ];

        $domainTokens = [
            'carrera',
            'carreras',
            'programa',
            'programas',
            'escuela',
            'escuelas',
            'facultad',
            'facultades',
            'curso',
            'cursos',
            'asignatura',
            'asignaturas',
            'silabo',
            'sílabo',
            'silabos',
            'sílabos',
            'ciclo',
            'ciclos',
            'credito',
            'crédito',
            'creditos',
            'créditos',
            'hora',
            'horas',
            'sumilla',
            'sumillas',
            'malla',
            'mallas',
            'plan de estudios',
            'enfermeria',
            'enfermería',
            'sistemas',
            'administracion',
            'administración',
            'negocios internacionales',
            'contabilidad',
            'psicologia',
            'psicología',
            'medicina',
            'nutricion',
            'nutrición',
            'teologia',
            'teología',
            'arquitectura',
            'civil',
            'ambiental'
        ];

        $loadedTokens = [
            'cargada',
            'cargadas',
            'cargado',
            'cargados',
            'tienes',
            'registrada',
            'registradas',
            'registrado',
            'registrados',
            'disponible',
            'disponibles',
            'base',
            'duckdb'
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



    private function looksLikeCurricularAdvisoryQuestion(string $question): bool
    {
        $q = Support::normalize($question);

        $hardDataTokens = [
            'cuantos',
            'cuantas',
            'cantidad',
            'conteo',
            'total de',
            'lista',
            'listar',
            'listame',
            'muestrame',
            'grafico',
            'grafica',
            'barras',
            'pie',
            'pastel',
            'ranking',
            'top',
            'por sede',
            'por facultad',
            'por programa'
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
            foreach (
                [
                    'curso',
                    'cursos',
                    'malla',
                    'perfil',
                    'egreso',
                    'competencia',
                    'competencias',
                    'creditos',
                    'créditos',
                    'aprendizaje',
                    'ensenanza',
                    'enseñanza',
                    'evaluacion',
                    'evaluación'
                ] as $domain
            ) {
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
}
