<?php
/* JOMELAI_STREAM_ROUTES_V1
   Rutas reales:
   - POST /api/ask-stream
   - POST /api/assistant/generate-syllabus-stream
*/

function jm_stream_path()
{
    return parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
}

function jm_stream_method()
{
    return strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
}

function jm_stream_json_response($payload, $status = 200)
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function jm_stream_read_json()
{
    $raw = file_get_contents('php://input');
    $data = json_decode($raw ?: '{}', true);
    return is_array($data) ? $data : [];
}

function jm_stream_auth_unlock()
{
    if (class_exists('Support')) {
        try {
            Support::requireAuth();
        } catch (Throwable $e) {
            jm_stream_json_response([
                'ok' => false,
                'message' => 'No autorizado.',
                'detail' => $e->getMessage(),
            ], 401);
        }
    }

    if (session_status() === PHP_SESSION_ACTIVE) {
        session_write_close();
    }
}

function jm_stream_config($key, $default = null)
{
    if (class_exists('Support')) {
        try {
            $value = Support::config($key);
            if ($value !== null && $value !== '') {
                return $value;
            }
        } catch (Throwable $e) {
            // fallback abajo
        }
    }

    $env = getenv(strtoupper($key));
    return ($env !== false && $env !== '') ? $env : $default;
}

function jm_ollama_base_url()
{
    $base = jm_stream_config('ollama_base_url', '');
    if ($base === '') {
        $base = getenv('OLLAMA_BASE_URL') ?: '';
    }
    if ($base === '') {
        $base = 'http://jomelai_ollama:11434';
    }
    return rtrim($base, '/');
}

function jm_sse_start()
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
    echo 'data: ' . json_encode(['ok' => true], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n\n";

    @ob_flush();
    @flush();
}

function jm_sse_send($event, $data)
{
    echo "event: {$event}\n";
    echo 'data: ' . json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n\n";
    @ob_flush();
    @flush();
}

function jm_ollama_stream_generate($model, $prompt, $options, $onToken)
{
    if (!function_exists('curl_init')) {
        throw new RuntimeException('La extension curl de PHP no esta disponible.');
    }

    $payload = [
        'model' => $model,
        'prompt' => $prompt,
        'stream' => true,
        'options' => $options,
    ];

    $base = jm_ollama_base_url();
    $ch = curl_init($base . '/api/generate');

    $buffer = '';
    $answer = '';

    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        CURLOPT_RETURNTRANSFER => false,
        CURLOPT_HEADER => false,
        CURLOPT_TIMEOUT => 0,
        CURLOPT_WRITEFUNCTION => function ($ch, $chunk) use (&$buffer, &$answer, $onToken) {
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
                    $answer .= $piece;
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

    if ($status < 200 || $status >= 300) {
        throw new RuntimeException('Ollama respondio HTTP ' . $status);
    }

    return $answer;
}

function jm_handle_ask_stream()
{
    if (jm_stream_method() !== 'POST') {
        jm_stream_json_response(['ok' => false, 'message' => 'Metodo no permitido.'], 405);
    }

    jm_stream_auth_unlock();

    $data = jm_stream_read_json();

    $question = trim((string)($data['question'] ?? ''));

    if ($question === '') {
        jm_stream_json_response(['ok' => false, 'message' => 'Escribe tu pregunta.'], 422);
    }

    $model = trim((string)($data['model'] ?? jm_stream_config('ollama_default_model', 'qwen2.5-coder:1.5b')));
    if ($model === '') {
        $model = 'qwen2.5-coder:1.5b';
    }

    $maxTokens = (int)($data['max_tokens'] ?? 700);
    $maxTokens = max(120, min($maxTokens, 1800));

    $numCtx = (int)($data['num_ctx'] ?? 2048);
    $numCtx = max(1024, min($numCtx, 3072));

    $nResults = (int)($data['n_results'] ?? 0);
    $nResults = max(0, min($nResults, 4));

    $temperature = (float)($data['temperature'] ?? 0.22);
    $temperature = max(0.05, min($temperature, 0.8));

    $topP = (float)($data['top_p'] ?? 0.85);
    $topP = max(0.3, min($topP, 0.95));

    $context = trim((string)($data['context'] ?? 'chat'));

    $tokensConfig = [
        'model' => $model,
        'num_ctx' => $numCtx,
        'num_predict' => $maxTokens,
        'n_results' => $nResults,
        'temperature' => $temperature,
        'top_p' => $topP,
        'stream' => true,
    ];

    $prompt =
        "Eres JoMelAi, asistente curricular universitario. Responde en español, con tono academico sobrio, claro y util.\n" .
        "No inventes datos institucionales especificos si no fueron proporcionados.\n" .
        "Si el usuario pide un recurso de aprendizaje, entrega un documento estructurado, editable y completo.\n" .
        "Si la solicitud es una continuacion, devuelve solo contenido nuevo y evita repetir secciones ya dadas.\n\n" .
        "CONTEXTO UI: {$context}\n\n" .
        "SOLICITUD DEL USUARIO:\n{$question}\n\n" .
        "RESPUESTA:";

    jm_sse_start();
    jm_sse_send('config', [
        'ok' => true,
        'tokens_config' => $tokensConfig,
        'message' => "Modelo {$model}, ctx {$numCtx}, salida {$maxTokens} tokens.",
    ]);

    $answer = '';

    try {
        $answer = jm_ollama_stream_generate(
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
            function ($piece) {
                jm_sse_send('token', ['text' => $piece]);
            }
        );
    } catch (Throwable $e) {
        jm_sse_send('token', ['text' => "\n\n⚠️ " . $e->getMessage()]);
        jm_sse_send('final', [
            'ok' => false,
            'mode' => 'ask_stream',
            'answer' => $answer,
            'message' => $e->getMessage(),
            'tokens_config' => $tokensConfig,
        ]);
        exit;
    }

    jm_sse_send('final', [
        'ok' => true,
        'mode' => 'ask_stream',
        'answer' => $answer,
        'tokens_config' => $tokensConfig,
    ]);

    exit;
}

function jm_handle_syllabus_stream()
{
    if (jm_stream_method() !== 'POST') {
        jm_stream_json_response(['ok' => false, 'message' => 'Metodo no permitido.'], 405);
    }

    jm_stream_auth_unlock();

    $data = jm_stream_read_json();

    $course = trim((string)($data['course'] ?? ''));

    if ($course === '') {
        jm_stream_json_response(['ok' => false, 'message' => 'El nombre del curso es obligatorio.'], 422);
    }

    $model = trim((string)($data['model'] ?? jm_stream_config('ollama_default_model', 'qwen2.5-coder:1.5b')));
    if ($model === '') {
        $model = 'qwen2.5-coder:1.5b';
    }

    $program = trim((string)($data['program'] ?? ''));
    $credits = trim((string)($data['credits'] ?? ''));
    $cycle = trim((string)($data['cycle'] ?? ''));
    $weeks = max(1, min((int)($data['weeks'] ?? 16), 24));
    $modality = trim((string)($data['modality'] ?? 'Presencial'));
    $profile = trim((string)($data['graduate_profile'] ?? ''));
    $competency = trim((string)($data['competency'] ?? ''));
    $startDate = trim((string)($data['start_date'] ?? ''));
    $sessionsPerWeek = max(1, min((int)($data['sessions_per_week'] ?? 1), 4));

    $maxTokens = (int)($data['max_tokens'] ?? 2200);
    $maxTokens = max(1200, min($maxTokens, 2800));

    $numCtx = (int)($data['num_ctx'] ?? 2048);
    $numCtx = max(1024, min($numCtx, 3072));

    $temperature = (float)($data['temperature'] ?? 0.22);

    $tokensConfig = [
        'model' => $model,
        'num_ctx' => $numCtx,
        'num_predict' => $maxTokens,
        'n_results' => 0,
        'temperature' => $temperature,
        'top_p' => 0.85,
        'stream' => true,
    ];

    $prompt =
        "Eres un disenador curricular universitario experto.\n\n" .
        "Genera contenido REAL, especifico y util para un silabo universitario.\n" .
        "Responde SOLO JSON valido. No uses Markdown. No uses placeholders. No uses textos genericos como titulo 1, contenido 1, referencia 1, autor 1 o url 1.\n\n" .

        "DATOS DEL CURSO:\n" .
        "ASIGNATURA: {$course}\n" .
        "PROGRAMA: {$program}\n" .
        "CREDITOS: {$credits}\n" .
        "CICLO: {$cycle}\n" .
        "SEMANAS: {$weeks}\n" .
        "SESIONES POR SEMANA: {$sessionsPerWeek}\n" .
        "MODALIDAD: {$modality}\n" .
        "FECHA DE INICIO SUGERIDA: {$startDate}\n" .
        "PERFIL DE EGRESO/APORTE: {$profile}\n" .
        "COMPETENCIA ESPERADA: {$competency}\n\n" .

        "REGLAS OBLIGATORIAS:\n" .
        "- Considera exactamente {$weeks} semanas.\n" .
        "- Divide el curso en 4 unidades academicas equilibradas.\n" .
        "- Genera sesiones sin sobrepasar el total de semanas ni el numero de sesiones por semana.\n" .
        "- Propone fecha_inicio y fecha_fin cuando sea posible. Si no hay fecha_inicio, usa fechas sugeridas relativas por semana.\n" .
        "- Incluye sumilla, competencia del curso, resultados de aprendizaje de la asignatura, unidades, resultado de aprendizaje de cada unidad, sesiones, evaluaciones y referencias.\n" .
        "- Las evaluaciones deben usar sistema numerico vigesimal de 0 a 20.\n" .
        "- Incluye evaluacion de producto de unidad, evaluacion de resultados de aprendizaje y evaluacion de competencia.\n" .
        "- Las referencias deben ser reales o institucionales reconocibles; si no conoces URL exacta, usa \"DOI no identificado\" o \"URL institucional no especificada\".\n\n" .

        "DEVUELVE EXACTAMENTE ESTE JSON:\n" .
        "{\n" .
        "  \"datos_generales\": {\n" .
        "    \"curso\": \"{$course}\",\n" .
        "    \"programa\": \"{$program}\",\n" .
        "    \"creditos\": \"{$credits}\",\n" .
        "    \"ciclo\": \"{$cycle}\",\n" .
        "    \"semanas\": {$weeks},\n" .
        "    \"sesiones_por_semana\": {$sessionsPerWeek},\n" .
        "    \"modalidad\": \"{$modality}\",\n" .
        "    \"fecha_inicio\": \"fecha sugerida\",\n" .
        "    \"fecha_fin\": \"fecha sugerida\",\n" .
        "    \"sistema_evaluacion\": \"Sistema numerico vigesimal: 0 a 20\"\n" .
        "  },\n" .
        "  \"sumilla\": \"sumilla real de 100 a 140 palabras sobre la asignatura\",\n" .
        "  \"competencia_curso\": \"competencia observable y especifica de la asignatura\",\n" .
        "  \"resultados_curso\": [\n" .
        "    \"resultado de aprendizaje real 1\",\n" .
        "    \"resultado de aprendizaje real 2\",\n" .
        "    \"resultado de aprendizaje real 3\",\n" .
        "    \"resultado de aprendizaje real 4\"\n" .
        "  ],\n" .
        "  \"unidades\": [\n" .
        "    {\n" .
        "      \"unidad\": 1,\n" .
        "      \"titulo\": \"titulo real de unidad\",\n" .
        "      \"semanas\": [1,2,3,4],\n" .
        "      \"resultado_unidad\": \"resultado de aprendizaje real de la unidad\",\n" .
        "      \"contenidos\": [\"contenido real 1\", \"contenido real 2\", \"contenido real 3\", \"contenido real 4\"],\n" .
        "      \"sesiones\": [\n" .
        "        {\n" .
        "          \"semana\": 1,\n" .
        "          \"sesion\": 1,\n" .
        "          \"titulo\": \"titulo real de sesion\",\n" .
        "          \"resultado_sesion\": \"resultado observable de la sesion\",\n" .
        "          \"contenidos\": [\"tema real\", \"tema real\"],\n" .
        "          \"actividad_aprendizaje\": \"actividad concreta\",\n" .
        "          \"producto\": \"producto o evidencia\",\n" .
        "          \"fecha_sugerida\": \"fecha o semana sugerida\"\n" .
        "        }\n" .
        "      ],\n" .
        "      \"producto_unidad\": \"producto integrador real\",\n" .
        "      \"evaluacion_producto_unidad\": {\n" .
        "        \"descripcion\": \"evaluacion del producto de unidad\",\n" .
        "        \"criterios\": [\"criterio real 1\", \"criterio real 2\", \"criterio real 3\"],\n" .
        "        \"puntaje_vigesimal\": 20,\n" .
        "        \"fecha_sugerida\": \"semana o fecha\"\n" .
        "      }\n" .
        "    }\n" .
        "  ],\n" .
        "  \"evaluaciones\": [\n" .
        "    {\n" .
        "      \"tipo\": \"producto_unidad\",\n" .
        "      \"descripcion\": \"evaluacion concreta\",\n" .
        "      \"evidencia\": \"producto o evidencia evaluable\",\n" .
        "      \"criterios\": [\"criterio real 1\", \"criterio real 2\"],\n" .
        "      \"puntaje_vigesimal\": 20,\n" .
        "      \"semana\": 4,\n" .
        "      \"fecha_sugerida\": \"fecha o semana\"\n" .
        "    },\n" .
        "    {\n" .
        "      \"tipo\": \"resultado_aprendizaje\",\n" .
        "      \"descripcion\": \"evaluacion de resultado de aprendizaje\",\n" .
        "      \"evidencia\": \"evidencia evaluable\",\n" .
        "      \"criterios\": [\"criterio real 1\", \"criterio real 2\"],\n" .
        "      \"puntaje_vigesimal\": 20,\n" .
        "      \"semana\": 8,\n" .
        "      \"fecha_sugerida\": \"fecha o semana\"\n" .
        "    },\n" .
        "    {\n" .
        "      \"tipo\": \"competencia\",\n" .
        "      \"descripcion\": \"evaluacion integradora de competencia\",\n" .
        "      \"evidencia\": \"evidencia integradora\",\n" .
        "      \"criterios\": [\"criterio real 1\", \"criterio real 2\"],\n" .
        "      \"puntaje_vigesimal\": 20,\n" .
        "      \"semana\": {$weeks},\n" .
        "      \"fecha_sugerida\": \"fecha o semana\"\n" .
        "    }\n" .
        "  ],\n" .
        "  \"metodologias\": [\"metodologia real 1\", \"metodologia real 2\", \"metodologia real 3\", \"metodologia real 4\"],\n" .
        "  \"referencias\": [\n" .
        "    {\"autor\":\"autor real o institucion\", \"anio\":\"anio\", \"titulo\":\"titulo real\", \"fuente\":\"editorial, revista o institucion\", \"url\":\"URL real, DOI o DOI no identificado\", \"utilidad\":\"utilidad para el curso\"}\n" .
        "  ],\n" .
        "  \"enlaces\": [\n" .
        "    {\"titulo\":\"recurso real\", \"url\":\"URL real\", \"uso\":\"uso academico\"}\n" .
        "  ]\n" .
        "}\n\n" .
        "CANTIDADES OBLIGATORIAS:\n" .
        "- 4 resultados_curso.\n" .
        "- 4 unidades.\n" .
        "- Cada unidad debe tener contenidos reales y sesiones.\n" .
        "- El total de sesiones no debe exceder semanas x sesiones_por_semana.\n" .
        "- Minimo 3 evaluaciones globales: producto_unidad, resultado_aprendizaje y competencia.\n" .
        "- 5 referencias.\n" .
        "- 4 enlaces.\n\n" .
        "Genera ahora el JSON completo para la asignatura {$course}.";

    jm_sse_start();

    jm_sse_send('config', [
        'ok' => true,
        'tokens_config' => $tokensConfig,
        'message' => "Generando silabo completo con {$model}.",
    ]);

    $answer = '';

    try {
        $answer = jm_ollama_stream_generate(
            $model,
            $prompt,
            [
                'temperature' => $temperature,
                'top_p' => 0.85,
                'repeat_penalty' => 1.08,
                'num_ctx' => $numCtx,
                'num_predict' => $maxTokens,
                'num_thread' => 4,
            ],
            function ($piece) {
                jm_sse_send('token', ['text' => $piece]);
            }
        );
    } catch (Throwable $e) {
        jm_sse_send('token', ['text' => "\n\n⚠️ " . $e->getMessage()]);
        jm_sse_send('final', [
            'ok' => false,
            'mode' => 'syllabus_stream',
            'response' => $answer,
            'message' => $e->getMessage(),
            'tokens_config' => $tokensConfig,
        ]);
        exit;
    }

    jm_sse_send('final', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'model' => $model,
        'response' => $answer,
        'answer' => $answer,
        'tokens_config' => $tokensConfig,
    ]);

    exit;
}

$__jm_path = jm_stream_path();

if ($__jm_path === '/api/ask-stream') {
    jm_handle_ask_stream();
}

if ($__jm_path === '/api/assistant/generate-syllabus-stream') {
    jm_handle_syllabus_stream();
}
