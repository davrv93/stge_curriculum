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








/* JOMELAI_QWEN_CURRICULAR_SYLLABUS_V4_START */

function jm_qwen_syl_read_dotenv_value($key)
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

            if ($line === '' || strpos($line, '#') === 0 || strpos($line, '=') === false) {
                continue;
            }

            list($k, $v) = explode('=', $line, 2);

            if (trim($k) === $key) {
                return trim(trim($v), "\"'");
            }
        }
    }

    return null;
}

function jm_qwen_syl_env($key, $default = '')
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

    $dotenv = jm_qwen_syl_read_dotenv_value($key);

    if ($dotenv !== null && $dotenv !== '') {
        return $dotenv;
    }

    return $default;
}

function jm_qwen_syl_bool($key, $default = false)
{
    $raw = strtolower(trim((string)jm_qwen_syl_env($key, $default ? '1' : '0')));

    return in_array($raw, ['1', 'true', 'yes', 'si', 'sí', 'on'], true);
}

function jm_qwen_syl_model($requestModel = '')
{
    $requestModel = trim((string)$requestModel);
    $envModel = trim((string)jm_qwen_syl_env('SYLLABUS_OLLAMA_MODEL', 'qwen2.5:1.5b'));
    $allowOverride = jm_qwen_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false);

    if ($allowOverride && $requestModel !== '') {
        return $requestModel;
    }

    return $envModel !== '' ? $envModel : 'qwen2.5:1.5b';
}

function jm_qwen_syl_text($value)
{
    if ($value === null) {
        return '';
    }

    if (is_array($value)) {
        return trim(json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    return trim((string)$value);
}

function jm_qwen_syl_list($value)
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

function jm_qwen_syl_extract_json($text)
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

function jm_qwen_syl_contains_bad_quality($text)
{
    $badMarkers = [
        'resultado de aprendizaje real',
        'contenido real',
        'tema real',
        'actividad concreta',
        'producto o evidencia',
        'criterio real',
        'producto integrador real',
        'construyendo',
        'generando resultado',
        'Técnicas de Numeración',
        'Tecnicas de Numeracion',
        'Referencias Académicas',
        'Referencias Academicas',
        'Metodologías',
        'Metodologias',
        'cálculo simple',
        'calculo simple',
        'cálculo básico',
        'calculo basico',
        'Revisión de conceptos teóricos',
        'Revision de conceptos teoricos',
        '"resultado_sesion": ""',
        'Juan Pérez',
        'Juan Perez',
        'recursoenlinea.com',
    ];

    $lower = function_exists('mb_strtolower')
        ? mb_strtolower((string)$text, 'UTF-8')
        : strtolower((string)$text);

    foreach ($badMarkers as $marker) {
        $m = function_exists('mb_strtolower')
            ? mb_strtolower($marker, 'UTF-8')
            : strtolower($marker);

        if (strpos($lower, $m) !== false) {
            return true;
        }
    }

    return false;
}

function jm_qwen_syl_quality_issues($syllabus, $raw)
{
    $issues = [];

    if (!is_array($syllabus)) {
        $issues[] = 'JSON incompleto o inválido.';
        return $issues;
    }

    if (empty($syllabus['resultados_curso']) || !is_array($syllabus['resultados_curso'])) {
        $issues[] = 'Faltan resultados de aprendizaje estructurados.';
    } else {
        $first = $syllabus['resultados_curso'][0] ?? null;

        if (!is_array($first) || empty($first['codigo']) || empty($first['nivel_taxonomico']) || empty($first['verbo_observable'])) {
            $issues[] = 'Los resultados no incluyen taxonomía, código y verbo observable.';
        }
    }

    if (empty($syllabus['unidades']) || !is_array($syllabus['unidades'])) {
        $issues[] = 'Faltan unidades.';
    } else {
        if (count($syllabus['unidades']) !== 4) {
            $issues[] = 'Debe haber exactamente 4 unidades curriculares.';
        }

        foreach ($syllabus['unidades'] as $unit) {
            if (!is_array($unit)) {
                $issues[] = 'Unidad con formato inválido.';
                continue;
            }

            $title = jm_qwen_syl_text($unit['titulo'] ?? '');

            if (preg_match('/referencias|metodolog|evaluaci[oó]n|habilidades$/iu', $title)) {
                $issues[] = 'Hay unidades que son secciones administrativas, no unidades académicas.';
            }

            if (empty($unit['resultado_unidad']) || empty($unit['resultados_curso_vinculados']) || empty($unit['metodologia_unidad'])) {
                $issues[] = 'Unidad sin resultado, RA vinculado o metodología.';
            }

            $sessions = isset($unit['sesiones']) && is_array($unit['sesiones']) ? $unit['sesiones'] : [];

            if (count($sessions) < 2) {
                $issues[] = 'Unidad con menos de 2 sesiones representativas.';
            }

            foreach ($sessions as $ses) {
                if (!is_array($ses)) {
                    continue;
                }

                if (empty($ses['resultado_sesion']) || empty($ses['aporte_a_resultado_unidad']) || empty($ses['resultado_curso_vinculado']) || empty($ses['nivel_taxonomico'])) {
                    $issues[] = 'Sesión sin trazabilidad completa.';
                }
            }
        }
    }

    if (empty($syllabus['matriz_trazabilidad']) || !is_array($syllabus['matriz_trazabilidad'])) {
        $issues[] = 'Falta matriz de trazabilidad curricular.';
    }

    if (empty($syllabus['evaluaciones']) || !is_array($syllabus['evaluaciones'])) {
        $issues[] = 'Faltan evaluaciones.';
    }

    if (jm_qwen_syl_contains_bad_quality($raw)) {
        $issues[] = 'Se detectó contenido genérico, placeholder o baja calidad curricular.';
    }

    return array_values(array_unique($issues));
}

function jm_qwen_syl_to_markdown($syl, $raw = '')
{
    if (!is_array($syl)) {
        return trim((string)$raw);
    }

    $dg = isset($syl['datos_generales']) && is_array($syl['datos_generales'])
        ? $syl['datos_generales']
        : [];

    $lines = [];
    $lines[] = '# Sílabo curricular';
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
        'fecha_fin' => 'Fecha de finalización',
        'sistema_evaluacion' => 'Sistema de evaluación',
    ];

    foreach ($fields as $key => $label) {
        if (isset($dg[$key]) && jm_qwen_syl_text($dg[$key]) !== '') {
            $lines[] = '| ' . $label . ' | ' . jm_qwen_syl_text($dg[$key]) . ' |';
        }
    }

    $lines[] = '';
    $lines[] = '## II. Sumilla';
    $lines[] = '';
    $lines[] = jm_qwen_syl_text($syl['sumilla'] ?? '');

    $lines[] = '';
    $lines[] = '## III. Competencia del curso';
    $lines[] = '';
    $lines[] = jm_qwen_syl_text($syl['competencia_curso'] ?? '');

    $lines[] = '';
    $lines[] = '## IV. Resultados de aprendizaje y taxonomía';
    $lines[] = '';
    $lines[] = '| Código | Resultado | Nivel taxonómico | Verbo | Evidencia integradora |';
    $lines[] = '|---|---|---|---|---|';

    foreach (jm_qwen_syl_list($syl['resultados_curso'] ?? []) as $ra) {
        if (is_array($ra)) {
            $lines[] =
                '| ' . jm_qwen_syl_text($ra['codigo'] ?? '') .
                ' | ' . jm_qwen_syl_text($ra['descripcion'] ?? '') .
                ' | ' . jm_qwen_syl_text($ra['nivel_taxonomico'] ?? '') .
                ' | ' . jm_qwen_syl_text($ra['verbo_observable'] ?? '') .
                ' | ' . jm_qwen_syl_text($ra['evidencia_integradora'] ?? '') .
                ' |';
        }
    }

    $lines[] = '';
    $lines[] = '## V. Unidades y sesiones';

    foreach (jm_qwen_syl_list($syl['unidades'] ?? []) as $unit) {
        if (!is_array($unit)) {
            continue;
        }

        $lines[] = '';
        $lines[] = '### Unidad ' . jm_qwen_syl_text($unit['unidad'] ?? '') . ': ' . jm_qwen_syl_text($unit['titulo'] ?? '');
        $lines[] = '';
        $lines[] = '- **Semanas:** ' . jm_qwen_syl_text($unit['semanas'] ?? '');
        $lines[] = '- **RA vinculados:** ' . jm_qwen_syl_text($unit['resultados_curso_vinculados'] ?? '');
        $lines[] = '- **Nivel dominante:** ' . jm_qwen_syl_text($unit['nivel_taxonomico_dominante'] ?? '');
        $lines[] = '- **Resultado de unidad:** ' . jm_qwen_syl_text($unit['resultado_unidad'] ?? '');
        $lines[] = '- **Metodología:** ' . jm_qwen_syl_text($unit['metodologia_unidad'] ?? '');
        $lines[] = '- **Justificación metodológica:** ' . jm_qwen_syl_text($unit['justificacion_metodologica'] ?? '');

        $contents = jm_qwen_syl_list($unit['contenidos'] ?? []);
        if ($contents) {
            $lines[] = '- **Contenidos:**';
            foreach ($contents as $c) {
                $lines[] = '  - ' . jm_qwen_syl_text($c);
            }
        }

        $lines[] = '';
        $lines[] = '| Semana | Sesión | Tema | RA | Nivel | Actividad | Evidencia | Aporte |';
        $lines[] = '|---:|---:|---|---|---|---|---|---|';

        foreach (jm_qwen_syl_list($unit['sesiones'] ?? []) as $ses) {
            if (!is_array($ses)) {
                continue;
            }

            $lines[] =
                '| ' . jm_qwen_syl_text($ses['semana'] ?? '') .
                ' | ' . jm_qwen_syl_text($ses['sesion'] ?? '') .
                ' | ' . jm_qwen_syl_text($ses['titulo'] ?? '') .
                ' | ' . jm_qwen_syl_text($ses['resultado_curso_vinculado'] ?? '') .
                ' | ' . jm_qwen_syl_text($ses['nivel_taxonomico'] ?? '') .
                ' | ' . jm_qwen_syl_text($ses['actividad_aprendizaje'] ?? '') .
                ' | ' . jm_qwen_syl_text($ses['producto'] ?? '') .
                ' | ' . jm_qwen_syl_text($ses['aporte_a_resultado_unidad'] ?? '') .
                ' |';
        }

        $lines[] = '';
        $lines[] = '- **Producto integrador:** ' . jm_qwen_syl_text($unit['producto_unidad'] ?? '');
    }

    $lines[] = '';
    $lines[] = '## VI. Matriz de trazabilidad curricular';
    $lines[] = '';
    $lines[] = '| RA | Unidad | Sesiones | Producto | Evaluación | Criterio de logro |';
    $lines[] = '|---|---|---|---|---|---|';

    foreach (jm_qwen_syl_list($syl['matriz_trazabilidad'] ?? []) as $tr) {
        if (!is_array($tr)) {
            continue;
        }

        $lines[] =
            '| ' . jm_qwen_syl_text($tr['resultado_curso'] ?? '') .
            ' | ' . jm_qwen_syl_text($tr['unidad'] ?? '') .
            ' | ' . jm_qwen_syl_text($tr['sesiones'] ?? '') .
            ' | ' . jm_qwen_syl_text($tr['producto'] ?? '') .
            ' | ' . jm_qwen_syl_text($tr['evaluacion'] ?? '') .
            ' | ' . jm_qwen_syl_text($tr['criterio_logro'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## VII. Evaluación';

    foreach (jm_qwen_syl_list($syl['evaluaciones'] ?? []) as $ev) {
        if (!is_array($ev)) {
            continue;
        }

        $lines[] = '';
        $lines[] = '- **' . jm_qwen_syl_text($ev['tipo'] ?? '') . ':** ' . jm_qwen_syl_text($ev['descripcion'] ?? '');
        $lines[] = '  - Evidencia: ' . jm_qwen_syl_text($ev['evidencia'] ?? '');
        $lines[] = '  - Instrumento: ' . jm_qwen_syl_text($ev['instrumento'] ?? '');
        $lines[] = '  - RA vinculados: ' . jm_qwen_syl_text($ev['resultados_vinculados'] ?? '');
        $lines[] = '  - Semana: ' . jm_qwen_syl_text($ev['semana'] ?? '');
    }

    $lines[] = '';
    $lines[] = '## VIII. Metodologías';

    foreach (jm_qwen_syl_list($syl['metodologias'] ?? []) as $m) {
        if (is_array($m)) {
            $lines[] = '- **' . jm_qwen_syl_text($m['nombre'] ?? '') . ':** ' . jm_qwen_syl_text($m['aplicacion'] ?? '') . ' ' . jm_qwen_syl_text($m['justificacion'] ?? '');
        } else {
            $lines[] = '- ' . jm_qwen_syl_text($m);
        }
    }

    $lines[] = '';
    $lines[] = '## IX. Referencias';

    foreach (jm_qwen_syl_list($syl['referencias'] ?? []) as $ref) {
        if (is_array($ref)) {
            $lines[] = '- ' . jm_qwen_syl_text($ref['autor'] ?? '') . ' (' . jm_qwen_syl_text($ref['anio'] ?? '') . '). ' . jm_qwen_syl_text($ref['titulo'] ?? '') . '. ' . jm_qwen_syl_text($ref['fuente'] ?? '') . '. ' . jm_qwen_syl_text($ref['url'] ?? '');
        }
    }

    return trim(implode("\n", $lines));
}

function jm_qwen_syl_generate($model, $prompt, $options, $onToken)
{
    if (function_exists('jm_syllabus_llm_stream_generate') && jm_qwen_syl_bool('LLM_REMOTE_ENABLED', false)) {
        return jm_syllabus_llm_stream_generate($model, $prompt, $options, $onToken);
    }

    return jm_ollama_stream_generate($model, $prompt, $options, $onToken);
}

/* JOMELAI_QWEN_CURRICULAR_SYLLABUS_V4_END */


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
    $model = jm_qwen_syl_model($requestModel);

    $program = trim((string)($data['program'] ?? $data['programa'] ?? $data['programa_estudio'] ?? ''));
    $credits = trim((string)($data['credits'] ?? $data['creditos'] ?? ''));
    $cycle = trim((string)($data['cycle'] ?? $data['ciclo'] ?? ''));
    $weeks = max(4, min((int)($data['weeks'] ?? $data['semanas'] ?? 16), 24));
    $modality = trim((string)($data['modality'] ?? $data['modalidad'] ?? 'Presencial'));
    $profile = trim((string)($data['graduate_profile'] ?? $data['perfil_egreso'] ?? ''));
    $competency = trim((string)($data['competency'] ?? $data['competencia'] ?? ''));
    $startDate = trim((string)($data['start_date'] ?? $data['fecha_inicio'] ?? ''));
    $sessionsPerWeek = max(1, min((int)($data['sessions_per_week'] ?? $data['sesiones_por_semana'] ?? 1), 4));
    $continueGeneration = !empty($data['continue_generation']);
    $previousRaw = trim((string)($data['previous_raw'] ?? ''));

    $numCtx = (int)($data['num_ctx'] ?? jm_qwen_syl_env('SYLLABUS_NUM_CTX', '8192'));
    $numCtx = max(4096, min($numCtx, 16384));

    $numPredict = (int)($data['max_tokens'] ?? $data['num_predict'] ?? jm_qwen_syl_env('SYLLABUS_NUM_PREDICT', '7200'));
    $numPredict = max(4200, min($numPredict, 10000));

    $temperature = (float)($data['temperature'] ?? jm_qwen_syl_env('SYLLABUS_TEMPERATURE', '0.28'));
    $temperature = max(0.10, min($temperature, 0.55));

    $topP = (float)($data['top_p'] ?? jm_qwen_syl_env('SYLLABUS_TOP_P', '0.86'));
    $topP = max(0.70, min($topP, 0.95));

    $numThread = (int)jm_qwen_syl_env('SYLLABUS_NUM_THREAD', '2');
    $numThread = max(1, min($numThread, 8));

    $tokensConfig = [
        'model' => $model,
        'model_env' => jm_qwen_syl_env('SYLLABUS_OLLAMA_MODEL', 'qwen2.5:1.5b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_qwen_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'num_ctx' => $numCtx,
        'num_predict' => $numPredict,
        'temperature' => $temperature,
        'top_p' => $topP,
        'num_thread' => $numThread,
        'stream' => true,
        'render_mode' => 'syllabus_qwen_curricular_v4',
        'strategy' => 'qwen_curricular_traceability_continue_v4',
    ];

    $profilePrompt = $profile !== ''
        ? "Perfil de egreso seleccionado o escrito por el usuario: {$profile}\n"
        : "Perfil de egreso no especificado; articula el curso con el programa sin inventar datos institucionales.\n";

    $competencyPrompt = $competency !== ''
        ? "Competencia seleccionada o escrita por el usuario: {$competency}\n"
        : "Competencia no especificada; formula una competencia de curso observable, evaluable y articulada al programa.\n";

    $disciplineInstruction =
        "INFERENCIA DISCIPLINAR DINAMICA:\n" .
        "No uses reglas hardcodeadas por nombre de curso. No uses condiciones del tipo: si el curso contiene una palabra, entonces usar una lista fija.\n" .
        "Analiza semanticamente curso, programa, ciclo, creditos, perfil y competencia.\n" .
        "Identifica internamente campo disciplinar, prerrequisitos, progresion conceptual, desempenos esperados, aplicaciones profesionales y productos evaluables.\n" .
        "No escribas ese analisis interno; usalo para construir el silabo.\n";

    $continueInstruction = '';

    if ($continueGeneration && $previousRaw !== '') {
        $continueInstruction =
            "MODO CONTINUAR/COMPLETAR:\n" .
            "El borrador anterior quedo incompleto, invalido o con baja calidad. No intentes continuar caracter por caracter.\n" .
            "Usalo solo como diagnostico de lo que NO debe repetirse. Reconstruye TODO el silabo completo desde cero en JSON valido, mas compacto y mejor alineado.\n" .
            "Borrador defectuoso anterior:\n" .
            $previousRaw .
            "\n\n";
    }

    $prompt =
        "Eres JoMelAI Curriculista universitario senior. Genera un silabo curricularmente defendible para revision academica.\n" .
        "Responde SOLO JSON valido. No uses markdown. No agregues explicaciones fuera del JSON.\n\n" .

        $continueInstruction .

        "DATOS DEL CURSO:\n" .
        "Curso: {$course}\n" .
        "Programa: {$program}\n" .
        "Creditos: {$credits}\n" .
        "Ciclo: {$cycle}\n" .
        "Semanas: {$weeks}\n" .
        "Sesiones por semana: {$sessionsPerWeek}\n" .
        "Modalidad: {$modality}\n" .
        "Fecha de inicio: {$startDate}\n" .
        $profilePrompt .
        $competencyPrompt .
        $disciplineInstruction .
        "\n" .

        "EXIGENCIA CURRICULAR:\n" .
        "1. Usa alineamiento constructivo: competencia -> resultados de aprendizaje -> unidades -> sesiones -> evidencias -> evaluaciones.\n" .
        "2. Usa taxonomia cognitiva en resultados y sesiones: comprender, aplicar, analizar, evaluar o crear. Evita recordar salvo inicio conceptual.\n" .
        "3. Cada resultado debe tener codigo RA, verbo observable, nivel taxonomico y evidencia integradora.\n" .
        "4. Cada unidad debe indicar RA vinculados, resultado de unidad, metodologia y justificacion.\n" .
        "5. Cada sesion debe indicar resultado de sesion, RA vinculado, nivel taxonomico, actividad, producto y aporte al resultado de unidad.\n" .
        "6. La matriz de trazabilidad debe demostrar que cada RA se desarrolla y se evalua.\n" .
        "7. Las evaluaciones deben tener instrumento, evidencia, criterios observables y RA vinculados.\n" .
        "8. Las metodologias deben ser pertinentes al curso, no una lista decorativa.\n\n" .

        "PROHIBICIONES:\n" .
        "- No uses placeholders ni textos de relleno.\n" .
        "- No uses secciones administrativas como unidades: Referencias, Metodologias, Evaluacion, Desarrollo de habilidades.\n" .
        "- No uses unidades genericas como Introduccion al curso si puedes usar un eje disciplinar concreto.\n" .
        "- Prohibido: resultado de aprendizaje real, contenido real, tema real, actividad concreta, construyendo, generando resultado, revision de conceptos teoricos, calculo basico, calculo simple, tecnicas de numeracion.\n" .
        "- No inventes URLs falsas. Si no sabes una URL exacta, usa cadena vacia.\n\n" .

        "ESTRUCTURA JSON OBLIGATORIA COMPACTA:\n" .
        "{\n" .
        "  \"datos_generales\": {\"curso\": string, \"programa\": string, \"creditos\": string, \"ciclo\": string, \"semanas\": number, \"sesiones_por_semana\": number, \"modalidad\": string, \"fecha_inicio\": string, \"fecha_fin\": string, \"sistema_evaluacion\": \"Sistema vigesimal de 0 a 20\"},\n" .
        "  \"sumilla\": string,\n" .
        "  \"competencia_curso\": string,\n" .
        "  \"resultados_curso\": [\n" .
        "    {\"codigo\": \"RA1\", \"descripcion\": string, \"nivel_taxonomico\": string, \"verbo_observable\": string, \"evidencia_integradora\": string},\n" .
        "    {\"codigo\": \"RA2\", \"descripcion\": string, \"nivel_taxonomico\": string, \"verbo_observable\": string, \"evidencia_integradora\": string},\n" .
        "    {\"codigo\": \"RA3\", \"descripcion\": string, \"nivel_taxonomico\": string, \"verbo_observable\": string, \"evidencia_integradora\": string},\n" .
        "    {\"codigo\": \"RA4\", \"descripcion\": string, \"nivel_taxonomico\": string, \"verbo_observable\": string, \"evidencia_integradora\": string}\n" .
        "  ],\n" .
        "  \"unidades\": [\n" .
        "    {\"unidad\": number, \"titulo\": string, \"semanas\": [number], \"resultados_curso_vinculados\": [\"RA1\"], \"nivel_taxonomico_dominante\": string, \"resultado_unidad\": string, \"metodologia_unidad\": string, \"justificacion_metodologica\": string, \"contenidos\": [string,string,string,string,string], \"sesiones\": [{\"semana\": number, \"sesion\": number, \"titulo\": string, \"resultado_curso_vinculado\": \"RA1\", \"resultado_sesion\": string, \"aporte_a_resultado_unidad\": string, \"nivel_taxonomico\": string, \"contenidos\": [string,string], \"metodo\": string, \"actividad_aprendizaje\": string, \"producto\": string, \"criterio_logro\": string}], \"producto_unidad\": string}\n" .
        "  ],\n" .
        "  \"matriz_trazabilidad\": [{\"resultado_curso\": \"RA1\", \"unidad\": number, \"sesiones\": [number], \"producto\": string, \"evaluacion\": string, \"criterio_logro\": string}],\n" .
        "  \"evaluaciones\": [{\"tipo\": string, \"descripcion\": string, \"evidencia\": string, \"instrumento\": string, \"criterios\": [string,string,string], \"resultados_vinculados\": [\"RA1\"], \"puntaje_vigesimal\": number, \"semana\": number}],\n" .
        "  \"metodologias\": [{\"nombre\": string, \"aplicacion\": string, \"justificacion\": string}],\n" .
        "  \"referencias\": [{\"autor\": string, \"anio\": string, \"titulo\": string, \"fuente\": string, \"url\": string, \"utilidad\": string}],\n" .
        "  \"enlaces\": [{\"titulo\": string, \"url\": string, \"uso\": string}]\n" .
        "}\n\n" .

        "CANTIDAD EXACTA:\n" .
        "- 4 resultados de curso.\n" .
        "- 4 unidades curriculares, no 5 ni 6.\n" .
        "- 2 sesiones representativas por unidad para evitar truncamiento.\n" .
        "- 4 filas de matriz de trazabilidad, una por RA.\n" .
        "- 4 evaluaciones.\n" .
        "- 5 metodologias.\n" .
        "- 4 referencias academicas.\n" .
        "- 3 enlaces o recursos.\n\n" .

        "Devuelve JSON valido, completo, compacto y curricularmente defendible.";

    jm_sse_start();

    jm_sse_send('progress', ['percent' => 3, 'stage' => 'Inicio', 'message' => 'Preparando generación curricular con Qwen.']);

    jm_sse_send('model_resolved', [
        'ok' => true,
        'provider' => jm_qwen_syl_bool('LLM_REMOTE_ENABLED', false) ? 'remote_llm' : 'ollama_local',
        'model' => $model,
        'model_env' => jm_qwen_syl_env('SYLLABUS_OLLAMA_MODEL', 'qwen2.5:1.5b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_qwen_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'render_mode' => 'syllabus_qwen_curricular_v4',
    ]);

    jm_sse_send('config', [
        'ok' => true,
        'tokens_config' => $tokensConfig,
        'message' => "Generando sílabo curricular con {$model}.",
        'render_mode' => 'syllabus_qwen_curricular_v4',
    ]);

    jm_sse_send('progress', ['percent' => 10, 'stage' => 'Análisis curricular', 'message' => 'Analizando curso, programa, perfil y competencia.']);
    jm_sse_send('progress', ['percent' => 18, 'stage' => 'Alineamiento', 'message' => 'Construyendo trazabilidad competencia-RA-unidad-sesión.']);

    $answer = '';
    $streamPieces = 0;
    $lastPercent = 18;
    $lastProgressTime = microtime(true);

    try {
        $answer = jm_qwen_syl_generate(
            $model,
            $prompt,
            [
                'temperature' => $temperature,
                'top_p' => $topP,
                'repeat_penalty' => 1.18,
                'num_ctx' => $numCtx,
                'num_predict' => $numPredict,
                'num_thread' => $numThread,
            ],
            function ($piece) use (&$streamPieces, &$lastPercent, &$lastProgressTime, $numPredict) {
                $streamPieces++;
                jm_sse_send('token', ['text' => $piece]);

                $estimated = 18 + (int)min(70, floor(($streamPieces / max(1, $numPredict)) * 70));
                $now = microtime(true);

                if ($estimated > $lastPercent + 1 || ($now - $lastProgressTime) > 1.25) {
                    $lastPercent = min(88, max($lastPercent, $estimated));
                    $lastProgressTime = $now;

                    $stage = 'Construcción curricular';
                    $message = 'Generando unidades, sesiones, metodología y matriz de trazabilidad.';

                    if ($lastPercent >= 35 && $lastPercent < 55) {
                        $stage = 'Unidades y RA';
                        $message = 'Desarrollando resultados y unidades vinculadas.';
                    } elseif ($lastPercent >= 55 && $lastPercent < 75) {
                        $stage = 'Sesiones y evidencias';
                        $message = 'Construyendo sesiones, productos y criterios de logro.';
                    } elseif ($lastPercent >= 75) {
                        $stage = 'Evaluación';
                        $message = 'Armando instrumentos, criterios y trazabilidad.';
                    }

                    jm_sse_send('progress', [
                        'percent' => $lastPercent,
                        'stage' => $stage,
                        'message' => $message,
                    ]);
                }
            }
        );
    } catch (Throwable $e) {
        jm_sse_send('final', [
            'ok' => false,
            'mode' => 'syllabus_stream',
            'message' => $e->getMessage(),
            'answer' => $answer,
            'response' => $answer,
            'tokens_config' => $tokensConfig,
        ]);
        exit;
    }

    jm_sse_send('progress', ['percent' => 92, 'stage' => 'Validación', 'message' => 'Validando JSON, taxonomía, metodología y trazabilidad.']);

    $syllabus = jm_qwen_syl_extract_json($answer);
    $parseOk = is_array($syllabus);
    $qualityIssues = jm_qwen_syl_quality_issues($syllabus, $answer);
    $needsContinue = !$parseOk || count($qualityIssues) > 0;
    $markdown = $parseOk ? jm_qwen_syl_to_markdown($syllabus, $answer) : $answer;

    jm_sse_send('syllabus', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'parse_ok' => $parseOk,
        'needs_continue' => $needsContinue,
        'quality_issues' => $qualityIssues,
        'render_mode' => 'syllabus_qwen_curricular_v4',
        'syllabus' => $syllabus,
        'markdown' => $markdown,
        'raw_response' => $answer,
        'tokens_config' => $tokensConfig,
    ]);

    jm_sse_send('progress', [
        'percent' => $needsContinue ? 96 : 100,
        'stage' => $needsContinue ? 'Requiere completar' : 'Completado',
        'message' => $needsContinue
            ? 'El sílabo necesita completarse o corregirse. Usa el botón Continuar generación.'
            : 'Sílabo curricular generado y listo para revisión.',
    ]);

    jm_sse_send('final', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'model' => $model,
        'parse_ok' => $parseOk,
        'needs_continue' => $needsContinue,
        'quality_issues' => $qualityIssues,
        'render_mode' => 'syllabus_qwen_curricular_v4',
        'syllabus' => $syllabus,
        'markdown' => $markdown,
        'answer' => $markdown,
        'response' => $answer,
        'raw_response' => $answer,
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
