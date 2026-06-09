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

function jm_ollama_stream_generate($model, $prompt, $options, $onToken, $format = null)
{
    if (!function_exists('curl_init')) {
        throw new RuntimeException('La extension curl de PHP no esta disponible.');
    }

    $payload = [
        'model' => $model,
        'prompt' => $prompt,
        'stream' => true,
        'keep_alive' => getenv('SYLLABUS_KEEP_ALIVE') ?: '30m',
        'options' => $options,
    ];

    if ($format !== null && $format !== '') {
        $payload['format'] = $format;
    }

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

    $model = trim((string)($data['model'] ?? jm_stream_config('ollama_default_model', 'qwen2.5-coder:3b')));
    if ($model === '') {
        $model = 'qwen2.5-coder:3b';
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


/* JOMELAI_SYLLABUS_FORMAT_HELPERS_START */

function jm_syllabus_extract_json($text)
{
    $text = trim((string)$text);

    if ($text === '') {
        return null;
    }

    $decoded = json_decode($text, true);
    if (is_array($decoded)) {
        return $decoded;
    }

    $start = strpos($text, '{');
    $end = strrpos($text, '}');

    if ($start === false || $end === false || $end <= $start) {
        return null;
    }

    $candidate = substr($text, $start, $end - $start + 1);
    $decoded = json_decode($candidate, true);

    return is_array($decoded) ? $decoded : null;
}

function jm_syllabus_text($value)
{
    if ($value === null) {
        return '';
    }

    if (is_array($value)) {
        return trim(json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    return trim((string)$value);
}

function jm_syllabus_list($value)
{
    if (is_array($value)) {
        return $value;
    }

    $value = trim((string)$value);
    if ($value === '') {
        return [];
    }

    return array_values(array_filter(array_map('trim', preg_split('/\n|;|\|/', $value))));
}

function jm_syllabus_to_markdown($syl, $raw = '')
{
    if (!is_array($syl)) {
        return trim((string)$raw);
    }

    $dg = isset($syl['datos_generales']) && is_array($syl['datos_generales'])
        ? $syl['datos_generales']
        : [];

    $lines = [];
    $lines[] = '# Sílabo académico';
    $lines[] = '';
    $lines[] = '## I. Datos generales';
    $lines[] = '';
    $lines[] = '| Campo | Información |';
    $lines[] = '|---|---|';

    $fields = [
        'curso' => 'Curso',
        'programa' => 'Programa',
        'creditos' => 'Créditos',
        'ciclo' => 'Ciclo',
        'semanas' => 'Semanas',
        'sesiones_por_semana' => 'Sesiones por semana',
        'modalidad' => 'Modalidad',
        'fecha_inicio' => 'Fecha de inicio',
        'fecha_fin' => 'Fecha de fin',
        'sistema_evaluacion' => 'Sistema de evaluación',
    ];

    foreach ($fields as $key => $label) {
        $value = $dg[$key] ?? '';
        if ($value !== '' && $value !== null) {
            $lines[] = '| ' . $label . ' | ' . jm_syllabus_text($value) . ' |';
        }
    }

    $lines[] = '';
    $lines[] = '## II. Sumilla';
    $lines[] = '';
    $lines[] = jm_syllabus_text($syl['sumilla'] ?? '');

    $lines[] = '';
    $lines[] = '## III. Competencia del curso';
    $lines[] = '';
    $lines[] = jm_syllabus_text($syl['competencia_curso'] ?? '');

    $lines[] = '';
    $lines[] = '## IV. Resultados de aprendizaje';
    $lines[] = '';

    foreach (jm_syllabus_list($syl['resultados_curso'] ?? []) as $i => $item) {
        $lines[] = ($i + 1) . '. ' . jm_syllabus_text($item);
    }

    $lines[] = '';
    $lines[] = '## V. Unidades de aprendizaje';

    foreach (jm_syllabus_list($syl['unidades'] ?? []) as $u) {
        if (!is_array($u)) {
            continue;
        }

        $unidad = jm_syllabus_text($u['unidad'] ?? '');
        $titulo = jm_syllabus_text($u['titulo'] ?? ('Unidad ' . $unidad));

        $lines[] = '';
        $lines[] = '### Unidad ' . $unidad . ': ' . $titulo;
        $lines[] = '';

        if (isset($u['semanas'])) {
            $semanas = is_array($u['semanas']) ? implode(', ', $u['semanas']) : jm_syllabus_text($u['semanas']);
            $lines[] = '- Semanas: ' . $semanas;
        }

        if (!empty($u['resultado_unidad'])) {
            $lines[] = '- Resultado de unidad: ' . jm_syllabus_text($u['resultado_unidad']);
        }

        $contenidos = jm_syllabus_list($u['contenidos'] ?? []);
        if ($contenidos) {
            $lines[] = '- Contenidos:';
            foreach ($contenidos as $c) {
                $lines[] = '  - ' . jm_syllabus_text($c);
            }
        }

        $sesiones = jm_syllabus_list($u['sesiones'] ?? []);
        if ($sesiones) {
            $lines[] = '';
            $lines[] = '| Semana | Sesión | Título | Actividad | Producto |';
            $lines[] = '|---:|---:|---|---|---|';
            foreach ($sesiones as $ses) {
                if (!is_array($ses)) {
                    continue;
                }
                $lines[] =
                    '| ' . jm_syllabus_text($ses['semana'] ?? '') .
                    ' | ' . jm_syllabus_text($ses['sesion'] ?? '') .
                    ' | ' . jm_syllabus_text($ses['titulo'] ?? '') .
                    ' | ' . jm_syllabus_text($ses['actividad_aprendizaje'] ?? '') .
                    ' | ' . jm_syllabus_text($ses['producto'] ?? '') .
                    ' |';
            }
        }

        if (!empty($u['producto_unidad'])) {
            $lines[] = '';
            $lines[] = '- Producto de unidad: ' . jm_syllabus_text($u['producto_unidad']);
        }
    }

    $lines[] = '';
    $lines[] = '## VI. Evaluaciones';
    $lines[] = '';
    $lines[] = '| Tipo | Descripción | Evidencia | Semana | Puntaje |';
    $lines[] = '|---|---|---|---:|---:|';

    foreach (jm_syllabus_list($syl['evaluaciones'] ?? []) as $ev) {
        if (!is_array($ev)) {
            continue;
        }

        $lines[] =
            '| ' . jm_syllabus_text($ev['tipo'] ?? '') .
            ' | ' . jm_syllabus_text($ev['descripcion'] ?? '') .
            ' | ' . jm_syllabus_text($ev['evidencia'] ?? '') .
            ' | ' . jm_syllabus_text($ev['semana'] ?? '') .
            ' | ' . jm_syllabus_text($ev['puntaje_vigesimal'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## VII. Metodologías';
    $lines[] = '';

    foreach (jm_syllabus_list($syl['metodologias'] ?? []) as $m) {
        $lines[] = '- ' . jm_syllabus_text($m);
    }

    $lines[] = '';
    $lines[] = '## VIII. Referencias';
    $lines[] = '';
    $lines[] = '| Autor | Año | Título | Fuente | URL/DOI | Utilidad |';
    $lines[] = '|---|---|---|---|---|---|';

    foreach (jm_syllabus_list($syl['referencias'] ?? []) as $ref) {
        if (!is_array($ref)) {
            continue;
        }

        $lines[] =
            '| ' . jm_syllabus_text($ref['autor'] ?? '') .
            ' | ' . jm_syllabus_text($ref['anio'] ?? '') .
            ' | ' . jm_syllabus_text($ref['titulo'] ?? '') .
            ' | ' . jm_syllabus_text($ref['fuente'] ?? '') .
            ' | ' . jm_syllabus_text($ref['url'] ?? '') .
            ' | ' . jm_syllabus_text($ref['utilidad'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## IX. Enlaces';
    $lines[] = '';

    foreach (jm_syllabus_list($syl['enlaces'] ?? []) as $en) {
        if (is_array($en)) {
            $lines[] = '- [' . jm_syllabus_text($en['titulo'] ?? 'Recurso') . '](' . jm_syllabus_text($en['url'] ?? '#') . '): ' . jm_syllabus_text($en['uso'] ?? '');
        }
    }

    return trim(implode("\n", $lines));
}

/* JOMELAI_SYLLABUS_FORMAT_HELPERS_END */



/* JOMELAI_SYLLABUS_MODEL_ENV_HELPERS_START */

function jm_syllabus_read_dotenv_value($key)
{
    $key = trim((string)$key);

    if ($key === '') {
        return null;
    }

    $dirs = [];
    $dir = __DIR__;

    for ($i = 0; $i < 8; $i++) {
        if (!$dir || $dir === '/' || in_array($dir, $dirs, true)) {
            break;
        }

        $dirs[] = $dir;
        $parent = dirname($dir);

        if ($parent === $dir) {
            break;
        }

        $dir = $parent;
    }

    foreach ($dirs as $d) {
        $file = rtrim($d, '/') . '/.env';

        if (!is_file($file) || !is_readable($file)) {
            continue;
        }

        $lines = @file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

        if (!is_array($lines)) {
            continue;
        }

        foreach ($lines as $line) {
            $line = trim($line);

            if ($line === '' || strpos($line, '#') === 0) {
                continue;
            }

            if (strpos($line, '=') === false) {
                continue;
            }

            [$k, $v] = explode('=', $line, 2);

            $k = trim($k);
            $v = trim($v);

            if ($k !== $key) {
                continue;
            }

            $v = trim($v, "\"'");

            return $v;
        }
    }

    return null;
}

function jm_syllabus_env_value($key, $default = '')
{
    $key = trim((string)$key);

    if ($key === '') {
        return $default;
    }

    $value = getenv($key);

    if ($value !== false && $value !== '') {
        return $value;
    }

    if (isset($_ENV[$key]) && $_ENV[$key] !== '') {
        return $_ENV[$key];
    }

    if (isset($_SERVER[$key]) && $_SERVER[$key] !== '') {
        return $_SERVER[$key];
    }

    if (function_exists('jm_stream_config')) {
        try {
            $configKey = strtolower($key);
            $value = jm_stream_config($configKey, '');

            if ($value !== null && $value !== '') {
                return $value;
            }
        } catch (Throwable $e) {
            // fallback
        }
    }

    $value = jm_syllabus_read_dotenv_value($key);

    if ($value !== null && $value !== '') {
        return $value;
    }

    return $default;
}

function jm_syllabus_env_bool($key, $default = false)
{
    $raw = strtolower(trim((string)jm_syllabus_env_value($key, $default ? '1' : '0')));

    return in_array($raw, ['1', 'true', 'yes', 'si', 'sí', 'on'], true);
}

function jm_syllabus_selected_model($requestModel = '')
{
    /*
     * Regla:
     * - Por defecto manda .env: SYLLABUS_OLLAMA_MODEL
     * - Si quieres que el frontend pueda sobrescribir modelo:
     *   SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE=1
     */
    $envModel = trim((string)jm_syllabus_env_value('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'));
    $requestModel = trim((string)$requestModel);
    $allowOverride = jm_syllabus_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false);

    if ($allowOverride && $requestModel !== '') {
        return $requestModel;
    }

    if ($envModel !== '') {
        return $envModel;
    }

    if ($requestModel !== '') {
        return $requestModel;
    }

    return 'llama3.2:1b';
}

/* JOMELAI_SYLLABUS_MODEL_ENV_HELPERS_END */



/* JOMELAI_SYNC_SYLLABUS_MODEL_START */

function jm_sync_read_dotenv_value($key)
{
    $key = trim((string)$key);

    if ($key === '') {
        return null;
    }

    $dirs = [];
    $dir = __DIR__;

    for ($i = 0; $i < 10; $i++) {
        if (!$dir || $dir === '/' || in_array($dir, $dirs, true)) {
            break;
        }

        $dirs[] = $dir;
        $parent = dirname($dir);

        if ($parent === $dir) {
            break;
        }

        $dir = $parent;
    }

    foreach ($dirs as $d) {
        $file = rtrim($d, '/') . '/.env';

        if (!is_file($file) || !is_readable($file)) {
            continue;
        }

        $lines = @file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

        if (!is_array($lines)) {
            continue;
        }

        foreach ($lines as $line) {
            $line = trim($line);

            if ($line === '' || strpos($line, '#') === 0) {
                continue;
            }

            if (strpos($line, '=') === false) {
                continue;
            }

            [$k, $v] = explode('=', $line, 2);

            $k = trim($k);
            $v = trim($v);

            if ($k !== $key) {
                continue;
            }

            return trim($v, "\"'");
        }
    }

    return null;
}

function jm_sync_env($key, $default = '')
{
    $value = getenv($key);

    if ($value !== false && $value !== '') {
        return $value;
    }

    if (isset($_ENV[$key]) && $_ENV[$key] !== '') {
        return $_ENV[$key];
    }

    if (isset($_SERVER[$key]) && $_SERVER[$key] !== '') {
        return $_SERVER[$key];
    }

    $dotenv = jm_sync_read_dotenv_value($key);

    if ($dotenv !== null && $dotenv !== '') {
        return $dotenv;
    }

    return $default;
}

function jm_sync_env_bool($key, $default = false)
{
    $raw = strtolower(trim((string)jm_sync_env($key, $default ? '1' : '0')));

    return in_array($raw, ['1', 'true', 'yes', 'si', 'sí', 'on'], true);
}

function jm_sync_syllabus_model($requestModel = '')
{
    $requestModel = trim((string)$requestModel);
    $envModel = trim((string)jm_sync_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'));
    $allowOverride = jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false);

    if ($allowOverride && $requestModel !== '') {
        return $requestModel;
    }

    if ($envModel !== '') {
        return $envModel;
    }

    return 'llama3.2:1b';
}

/* JOMELAI_SYNC_SYLLABUS_MODEL_END */


function jm_handle_syllabus_stream()
{
    if (jm_stream_method() !== 'POST') {
        jm_stream_json_response(['ok' => false, 'message' => 'Metodo no permitido.'], 405);
    }

    jm_stream_auth_unlock();

    $data = jm_stream_read_json();

    $course = trim((string)($data['course'] ?? $data['curso'] ?? $data['asignatura'] ?? ''));

    if ($course === '') {
        jm_stream_json_response(['ok' => false, 'message' => 'El nombre del curso es obligatorio.'], 422);
    }

    $requestModel = trim((string)($data['model'] ?? ''));
    $model = jm_sync_syllabus_model($requestModel);

    

    $program = trim((string)($data['program'] ?? $data['programa'] ?? $data['programa_estudio'] ?? ''));
    $credits = trim((string)($data['credits'] ?? $data['creditos'] ?? ''));
    $cycle = trim((string)($data['cycle'] ?? $data['ciclo'] ?? ''));
    $weeks = max(4, min((int)($data['weeks'] ?? $data['semanas'] ?? 16), 20));
    $modality = trim((string)($data['modality'] ?? $data['modalidad'] ?? 'Presencial'));
    $profile = trim((string)($data['graduate_profile'] ?? $data['perfil_egreso'] ?? ''));
    $competency = trim((string)($data['competency'] ?? $data['competencia'] ?? ''));
    $startDate = trim((string)($data['start_date'] ?? $data['fecha_inicio'] ?? ''));
    $sessionsPerWeek = max(1, min((int)($data['sessions_per_week'] ?? $data['sesiones_por_semana'] ?? 1), 3));

    $maxTokens = (int)($data['max_tokens'] ?? getenv('SYLLABUS_MAX_TOKENS') ?: 1500);
    $maxTokens = max(900, min($maxTokens, 1900));

    $numCtx = (int)($data['num_ctx'] ?? getenv('SYLLABUS_NUM_CTX') ?: 1536);
    $numCtx = max(1024, min($numCtx, 2048));

    $temperature = (float)($data['temperature'] ?? getenv('SYLLABUS_TEMPERATURE') ?: 0.18);
    $temperature = max(0.05, min($temperature, 0.45));

    $topP = (float)($data['top_p'] ?? getenv('SYLLABUS_TOP_P') ?: 0.80);
    $topP = max(0.50, min($topP, 0.90));

    $includeDates = !empty($startDate);
    $totalSessions = $weeks * $sessionsPerWeek;

    $tokensConfig = [
        'model' => $model,
        'model_env' => jm_sync_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'request_model_override' => jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'model_env' => jm_syllabus_env_value('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),
        'request_model_override' => jm_syllabus_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'num_ctx' => $numCtx,
        'num_predict' => $maxTokens,
        'n_results' => 0,
        'temperature' => $temperature,
        'top_p' => $topP,
        'stream' => true,
        'format' => 'json',
        'optimized' => true,
        'render_mode' => 'syllabus_formatted',
    ];

    $prompt =
        "Eres JoMelAI Curriculista, diseñador curricular universitario.\\n" .
        "Genera contenido dinámico, específico y útil para un sílabo universitario.\\n" .
        "Responde SOLO JSON válido. No uses markdown. No agregues texto fuera del JSON.\\n" .
        "No uses placeholders como contenido 1, referencia 1, título real o autor real.\\n" .
        "Si no conoces URL exacta, usa URL institucional no especificada o DOI no identificado.\\n\\n" .

        "DATOS:\\n" .
        "- curso: {$course}\\n" .
        "- programa: {$program}\\n" .
        "- creditos: {$credits}\\n" .
        "- ciclo: {$cycle}\\n" .
        "- semanas: {$weeks}\\n" .
        "- sesiones_por_semana: {$sessionsPerWeek}\\n" .
        "- total_sesiones_maximo: {$totalSessions}\\n" .
        "- modalidad: {$modality}\\n" .
        "- fecha_inicio: {$startDate}\\n" .
        "- perfil_egreso: {$profile}\\n" .
        "- competencia_esperada: {$competency}\\n\\n" .

        "REGLAS:\\n" .
        "- Divide el curso en 4 unidades equilibradas.\\n" .
        "- Genera exactamente 4 resultados_curso.\\n" .
        "- Cada unidad debe incluir unidad, titulo, semanas, resultado_unidad, contenidos, sesiones, producto_unidad y evaluacion_producto_unidad.\\n" .
        "- Las sesiones no deben exceder {$totalSessions}.\\n" .
        "- Genera evaluaciones globales: producto_unidad, resultado_aprendizaje y competencia.\\n" .
        "- Usa sistema vigesimal 0 a 20.\\n" .
        "- Genera 5 referencias y 4 enlaces académicos o institucionales.\\n" .
        "- Mantén textos concretos y no excesivamente largos.\\n" .
        ($includeDates ? "- Calcula fecha_inicio y fecha_fin aproximadas cuando sea posible.\\n" : "- Si no hay fecha de inicio, usa Semana N como fecha_sugerida.\\n") .
        "\\n" .

        "DEVUELVE UN JSON CON ESTAS CLAVES EXACTAS:\\n" .
        "datos_generales, sumilla, competencia_curso, resultados_curso, unidades, evaluaciones, metodologias, referencias, enlaces.\\n\\n" .
        "datos_generales debe incluir: curso, programa, creditos, ciclo, semanas, sesiones_por_semana, modalidad, fecha_inicio, fecha_fin, sistema_evaluacion.\\n" .
        "Cada unidad debe incluir: unidad, titulo, semanas, resultado_unidad, contenidos, sesiones, producto_unidad, evaluacion_producto_unidad.\\n" .
        "Cada sesion debe incluir: semana, sesion, titulo, resultado_sesion, contenidos, actividad_aprendizaje, producto, fecha_sugerida.\\n" .
        "Cada evaluacion debe incluir: tipo, descripcion, evidencia, criterios, puntaje_vigesimal, semana, fecha_sugerida.\\n" .
        "Cada referencia debe incluir: autor, anio, titulo, fuente, url, utilidad.\\n" .
        "Cada enlace debe incluir: titulo, url, uso.\\n\\n" .
        "Genera ahora el JSON completo para {$course}.";

    jm_sse_start();

    jm_sse_send('model_resolved', [
        'ok' => true,
        'event' => 'model_resolved',
        'provider' => 'ollama_local',
        'model' => $model,
        'model_env' => jm_sync_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'request_model_override' => jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'verification' => 'Confirmar con Ollama /api/ps mientras genera.',
    ]);

    jm_sse_send('config', [
        'ok' => true,
        'tokens_config' => $tokensConfig,
        'message' => "Generando sílabo dinámico optimizado con {$model}.",
        'render_mode' => 'syllabus_formatted',
    ]);

    $answer = '';

    try {
        $answer = jm_ollama_stream_generate(
            $model,
            $prompt,
            [
                'temperature' => $temperature,
                'top_p' => $topP,
                'repeat_penalty' => 1.06,
                'num_ctx' => $numCtx,
                'num_predict' => $maxTokens,
                'num_thread' => (int)(getenv('SYLLABUS_NUM_THREAD') ?: 4),
            ],
            function ($piece) {
                jm_sse_send('token', ['text' => $piece]);
            },
            'json'
        );
    } catch (Throwable $e) {
        jm_sse_send('token', ['text' => "\\n\\n⚠️ " . $e->getMessage()]);
        jm_sse_send('final', [
            'ok' => false,
            'mode' => 'syllabus_stream',
            'response' => $answer,
            'answer' => $answer,
            'message' => $e->getMessage(),
            'tokens_config' => $tokensConfig,
            'render_mode' => 'syllabus_formatted',
        ]);
        exit;
    }

    $syllabus = jm_syllabus_extract_json($answer);
    $markdown = jm_syllabus_to_markdown($syllabus, $answer);
    $parseOk = is_array($syllabus);

    jm_sse_send('syllabus', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'render_mode' => 'syllabus_formatted',
        'parse_ok' => $parseOk,
        'syllabus' => $syllabus,
        'markdown' => $markdown,
        'raw_response' => $answer,
        'tokens_config' => $tokensConfig,
    ]);

    jm_sse_send('final', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'model' => $model,
        'response' => $answer,
        'raw_response' => $answer,
        'answer' => $markdown,
        'markdown' => $markdown,
        'syllabus' => $syllabus,
        'parse_ok' => $parseOk,
        'render_mode' => 'syllabus_formatted',
        'tokens_config' => $tokensConfig,
        'optimized' => true,
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
