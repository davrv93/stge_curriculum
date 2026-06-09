#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"
TARGET_MODEL="${1:-llama3.2:1b}"

echo "=================================================="
echo " Upgrade syllabus: curricular depth + progress + JS assets"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "TARGET_MODEL=$TARGET_MODEL"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: ejecuta este script desde la carpeta donde esta docker-compose.yml o compose.yml"
  exit 1
fi

BACKUP_DIR="backups/upgrade_syllabus_curricular_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
mkdir -p public

echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Detectando PHP real del stream, excluyendo exports/backups =="

PHP_FILE="${PHP_FILE_OVERRIDE:-}"

if [ -z "$PHP_FILE" ]; then
  PHP_FILE="$(find . \
    -type f \
    -name '*.php' \
    ! -path './.git/*' \
    ! -path './vendor/*' \
    ! -path './node_modules/*' \
    ! -path './backups/*' \
    ! -path './data/*' \
    ! -path './datasets/*' \
    ! -path './sync_docker_to_host_*/*' \
    ! -path './_docker_runtime_export*/*' \
    ! -path './_runtime_*/*' \
    -exec grep -l "function jm_handle_syllabus_stream" {} \; \
    2>/dev/null | head -1 || true)"
fi

if [ -z "$PHP_FILE" ] || [ ! -f "$PHP_FILE" ]; then
  echo "ERROR: no encontre el PHP real con jm_handle_syllabus_stream."
  echo "Puedes forzar:"
  echo "  PHP_FILE_OVERRIDE=./public/jomelai_stream_routes.php ./upgrade_syllabus_curricular_depth_progress_assets.sh"
  exit 1
fi

if echo "$PHP_FILE" | grep -qE 'sync_docker_to_host_|_docker_runtime_export|backups/'; then
  echo "ERROR: el PHP detectado parece export/backup:"
  echo "  $PHP_FILE"
  echo "Usa PHP_FILE_OVERRIDE con la ruta real."
  exit 1
fi

echo "PHP_FILE=$PHP_FILE"
mkdir -p "$BACKUP_DIR/$(dirname "$PHP_FILE")"
cp "$PHP_FILE" "$BACKUP_DIR/$PHP_FILE.bak" 2>/dev/null || cp "$PHP_FILE" "$BACKUP_DIR/$(basename "$PHP_FILE").bak"

echo
echo "== 2) Reemplazando endpoint por version curricular avanzada con progreso =="

python3 - "$PHP_FILE" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

# Quitar bloques nuestros anteriores si existen.
for block in [
    "JOMELAI_CURRICULAR_SYLLABUS_V3",
    "JOMELAI_DYNAMIC_SYLLABUS_V2",
    "JOMELAI_REAL_SYLLABUS_V2",
    "JOMELAI_SYNC_SYLLABUS_MODEL",
    "JOMELAI_FORCE_SYLLABUS_MODEL_ENV",
]:
    text = re.sub(
        r"\n/\* " + re.escape(block) + r"_START \*/.*?/\* " + re.escape(block) + r"_END \*/\n",
        "\n",
        text,
        flags=re.S,
    )

helpers = r'''
/* JOMELAI_CURRICULAR_SYLLABUS_V3_START */

function jm_cur_syl_read_dotenv_value($key)
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

function jm_cur_syl_env($key, $default = '')
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

    $dotenv = jm_cur_syl_read_dotenv_value($key);

    if ($dotenv !== null && $dotenv !== '') {
        return $dotenv;
    }

    return $default;
}

function jm_cur_syl_bool($key, $default = false)
{
    $raw = strtolower(trim((string)jm_cur_syl_env($key, $default ? '1' : '0')));

    return in_array($raw, ['1', 'true', 'yes', 'si', 'sí', 'on'], true);
}

function jm_cur_syl_model($requestModel = '')
{
    $requestModel = trim((string)$requestModel);
    $envModel = trim((string)jm_cur_syl_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'));
    $allowOverride = jm_cur_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false);

    if ($allowOverride && $requestModel !== '') {
        return $requestModel;
    }

    return $envModel !== '' ? $envModel : 'llama3.2:1b';
}

function jm_cur_syl_text($value)
{
    if ($value === null) {
        return '';
    }

    if (is_array($value)) {
        return trim(json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    return trim((string)$value);
}

function jm_cur_syl_list($value)
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

function jm_cur_syl_extract_json($text)
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

function jm_cur_syl_contains_bad_fillers($text)
{
    $badMarkers = [
        'resultado de aprendizaje real',
        'contenido real',
        'tema real',
        'actividad concreta',
        'producto o evidencia',
        'criterio real',
        'producto integrador real',
        'semana o fecha',
        'fecha o semana sugerida',
        'Juan Pérez',
        'Juan Perez',
        'Editorial de Matemáticas',
        'Editorial de Matematicas',
        'recursoenlinea.com',
        'construyendo',
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

function jm_cur_syl_needs_curricular_repair($syllabus)
{
    if (!is_array($syllabus)) {
        return true;
    }

    if (empty($syllabus['matriz_trazabilidad']) || !is_array($syllabus['matriz_trazabilidad'])) {
        return true;
    }

    if (empty($syllabus['resultados_curso']) || !is_array($syllabus['resultados_curso'])) {
        return true;
    }

    $firstRa = $syllabus['resultados_curso'][0] ?? null;

    if (!is_array($firstRa)) {
        return true;
    }

    if (empty($firstRa['codigo']) || empty($firstRa['nivel_taxonomico']) || empty($firstRa['verbo_observable'])) {
        return true;
    }

    if (empty($syllabus['unidades']) || !is_array($syllabus['unidades'])) {
        return true;
    }

    $firstUnit = $syllabus['unidades'][0] ?? null;

    if (!is_array($firstUnit)) {
        return true;
    }

    if (empty($firstUnit['resultados_curso_vinculados']) || empty($firstUnit['metodologia_unidad']) || empty($firstUnit['sesiones'])) {
        return true;
    }

    $firstSession = is_array($firstUnit['sesiones']) ? ($firstUnit['sesiones'][0] ?? null) : null;

    if (!is_array($firstSession)) {
        return true;
    }

    if (empty($firstSession['aporte_a_resultado_unidad']) || empty($firstSession['nivel_taxonomico']) || empty($firstSession['resultado_curso_vinculado'])) {
        return true;
    }

    return false;
}

function jm_cur_syl_to_markdown($syl, $raw = '')
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
        'fecha_fin' => 'Fecha de finalización',
        'sistema_evaluacion' => 'Sistema de evaluación',
    ];

    foreach ($fields as $key => $label) {
        if (isset($dg[$key]) && jm_cur_syl_text($dg[$key]) !== '') {
            $lines[] = '| ' . $label . ' | ' . jm_cur_syl_text($dg[$key]) . ' |';
        }
    }

    $lines[] = '';
    $lines[] = '## II. Sumilla';
    $lines[] = '';
    $lines[] = jm_cur_syl_text($syl['sumilla'] ?? '');

    $lines[] = '';
    $lines[] = '## III. Competencia del curso';
    $lines[] = '';
    $lines[] = jm_cur_syl_text($syl['competencia_curso'] ?? '');

    $lines[] = '';
    $lines[] = '## IV. Resultados de aprendizaje con taxonomía';
    $lines[] = '';
    $lines[] = '| Código | Resultado | Nivel taxonómico | Verbo | Evidencia integradora |';
    $lines[] = '|---|---|---|---|---|';

    foreach (jm_cur_syl_list($syl['resultados_curso'] ?? []) as $ra) {
        if (is_array($ra)) {
            $lines[] =
                '| ' . jm_cur_syl_text($ra['codigo'] ?? '') .
                ' | ' . jm_cur_syl_text($ra['descripcion'] ?? '') .
                ' | ' . jm_cur_syl_text($ra['nivel_taxonomico'] ?? '') .
                ' | ' . jm_cur_syl_text($ra['verbo_observable'] ?? '') .
                ' | ' . jm_cur_syl_text($ra['evidencia_integradora'] ?? '') .
                ' |';
        } else {
            $lines[] = '|  | ' . jm_cur_syl_text($ra) . ' |  |  |  |';
        }
    }

    $lines[] = '';
    $lines[] = '## V. Organización de unidades y sesiones';

    foreach (jm_cur_syl_list($syl['unidades'] ?? []) as $unit) {
        if (!is_array($unit)) {
            continue;
        }

        $unidad = jm_cur_syl_text($unit['unidad'] ?? '');
        $titulo = jm_cur_syl_text($unit['titulo'] ?? '');

        $lines[] = '';
        $lines[] = '### Unidad ' . $unidad . ': ' . $titulo;
        $lines[] = '';

        if (isset($unit['semanas'])) {
            $semanas = is_array($unit['semanas']) ? implode(', ', $unit['semanas']) : jm_cur_syl_text($unit['semanas']);
            $lines[] = '- **Semanas:** ' . $semanas;
        }

        $lines[] = '- **Resultados vinculados:** ' . jm_cur_syl_text($unit['resultados_curso_vinculados'] ?? '');
        $lines[] = '- **Nivel taxonómico dominante:** ' . jm_cur_syl_text($unit['nivel_taxonomico_dominante'] ?? '');
        $lines[] = '- **Resultado de unidad:** ' . jm_cur_syl_text($unit['resultado_unidad'] ?? '');
        $lines[] = '- **Metodología de unidad:** ' . jm_cur_syl_text($unit['metodologia_unidad'] ?? '');
        $lines[] = '- **Justificación metodológica:** ' . jm_cur_syl_text($unit['justificacion_metodologica'] ?? '');

        $contenidos = jm_cur_syl_list($unit['contenidos'] ?? []);
        if ($contenidos) {
            $lines[] = '- **Contenidos:**';
            foreach ($contenidos as $c) {
                $lines[] = '  - ' . jm_cur_syl_text($c);
            }
        }

        $sesiones = jm_cur_syl_list($unit['sesiones'] ?? []);
        if ($sesiones) {
            $lines[] = '';
            $lines[] = '| Semana | Sesión | Tema | RA | Nivel | Actividad | Evidencia | Aporte a unidad |';
            $lines[] = '|---:|---:|---|---|---|---|---|---|';

            foreach ($sesiones as $ses) {
                if (!is_array($ses)) {
                    continue;
                }

                $lines[] =
                    '| ' . jm_cur_syl_text($ses['semana'] ?? '') .
                    ' | ' . jm_cur_syl_text($ses['sesion'] ?? '') .
                    ' | ' . jm_cur_syl_text($ses['titulo'] ?? '') .
                    ' | ' . jm_cur_syl_text($ses['resultado_curso_vinculado'] ?? '') .
                    ' | ' . jm_cur_syl_text($ses['nivel_taxonomico'] ?? '') .
                    ' | ' . jm_cur_syl_text($ses['actividad_aprendizaje'] ?? '') .
                    ' | ' . jm_cur_syl_text($ses['producto'] ?? '') .
                    ' | ' . jm_cur_syl_text($ses['aporte_a_resultado_unidad'] ?? '') .
                    ' |';
            }
        }

        if (!empty($unit['producto_unidad'])) {
            $lines[] = '';
            $lines[] = '- **Producto integrador:** ' . jm_cur_syl_text($unit['producto_unidad']);
        }
    }

    $lines[] = '';
    $lines[] = '## VI. Matriz de trazabilidad curricular';
    $lines[] = '';
    $lines[] = '| RA | Unidad | Sesiones | Producto | Evaluación | Criterio de logro |';
    $lines[] = '|---|---|---|---|---|---|';

    foreach (jm_cur_syl_list($syl['matriz_trazabilidad'] ?? []) as $tr) {
        if (!is_array($tr)) {
            continue;
        }

        $lines[] =
            '| ' . jm_cur_syl_text($tr['resultado_curso'] ?? '') .
            ' | ' . jm_cur_syl_text($tr['unidad'] ?? '') .
            ' | ' . jm_cur_syl_text($tr['sesiones'] ?? '') .
            ' | ' . jm_cur_syl_text($tr['producto'] ?? '') .
            ' | ' . jm_cur_syl_text($tr['evaluacion'] ?? '') .
            ' | ' . jm_cur_syl_text($tr['criterio_logro'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## VII. Evaluación';
    $lines[] = '';
    $lines[] = '| Tipo | Descripción | Evidencia | Instrumento | RA vinculados | Semana | Puntaje |';
    $lines[] = '|---|---|---|---|---|---:|---:|';

    foreach (jm_cur_syl_list($syl['evaluaciones'] ?? []) as $ev) {
        if (!is_array($ev)) {
            continue;
        }

        $lines[] =
            '| ' . jm_cur_syl_text($ev['tipo'] ?? '') .
            ' | ' . jm_cur_syl_text($ev['descripcion'] ?? '') .
            ' | ' . jm_cur_syl_text($ev['evidencia'] ?? '') .
            ' | ' . jm_cur_syl_text($ev['instrumento'] ?? '') .
            ' | ' . jm_cur_syl_text($ev['resultados_vinculados'] ?? '') .
            ' | ' . jm_cur_syl_text($ev['semana'] ?? '') .
            ' | ' . jm_cur_syl_text($ev['puntaje_vigesimal'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## VIII. Metodologías';
    $lines[] = '';

    foreach (jm_cur_syl_list($syl['metodologias'] ?? []) as $m) {
        if (is_array($m)) {
            $lines[] = '- **' . jm_cur_syl_text($m['nombre'] ?? '') . ':** ' . jm_cur_syl_text($m['aplicacion'] ?? '') . ' ' . jm_cur_syl_text($m['justificacion'] ?? '');
        } else {
            $lines[] = '- ' . jm_cur_syl_text($m);
        }
    }

    $lines[] = '';
    $lines[] = '## IX. Referencias';
    $lines[] = '';

    foreach (jm_cur_syl_list($syl['referencias'] ?? []) as $ref) {
        if (is_array($ref)) {
            $lines[] = '- ' . jm_cur_syl_text($ref['autor'] ?? '') . ' (' . jm_cur_syl_text($ref['anio'] ?? '') . '). ' . jm_cur_syl_text($ref['titulo'] ?? '') . '. ' . jm_cur_syl_text($ref['fuente'] ?? '') . '. ' . jm_cur_syl_text($ref['url'] ?? '');
        } else {
            $lines[] = '- ' . jm_cur_syl_text($ref);
        }
    }

    $lines[] = '';
    $lines[] = '## X. Recursos y enlaces';
    $lines[] = '';

    foreach (jm_cur_syl_list($syl['enlaces'] ?? []) as $en) {
        if (is_array($en)) {
            $lines[] = '- ' . jm_cur_syl_text($en['titulo'] ?? '') . ': ' . jm_cur_syl_text($en['url'] ?? '') . ' — ' . jm_cur_syl_text($en['uso'] ?? '');
        }
    }

    return trim(implode("\n", $lines));
}

function jm_cur_syl_generate($model, $prompt, $options, $onToken)
{
    if (function_exists('jm_syllabus_llm_stream_generate') && jm_cur_syl_bool('LLM_REMOTE_ENABLED', false)) {
        return jm_syllabus_llm_stream_generate($model, $prompt, $options, $onToken);
    }

    return jm_ollama_stream_generate($model, $prompt, $options, $onToken);
}

/* JOMELAI_CURRICULAR_SYLLABUS_V3_END */
'''

idx = text.find("function jm_handle_syllabus_stream()")
if idx == -1:
    raise SystemExit("No se encontro function jm_handle_syllabus_stream().")

text = text[:idx] + helpers + "\n\n" + text[idx:]

start = text.find("function jm_handle_syllabus_stream()")
markers = [
    "\n$__jm_path = jm_stream_path();",
    "\nif ($__jm_path === '/api/ask-stream')",
]

positions = []
for marker in markers:
    pos = text.find(marker, start)
    if pos != -1:
        positions.append(pos)

if not positions:
    raise SystemExit("No se pudo detectar el final de jm_handle_syllabus_stream().")

end = min(positions)

new_func = r'''function jm_handle_syllabus_stream()
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
    $model = jm_cur_syl_model($requestModel);

    $program = trim((string)($data['program'] ?? $data['programa'] ?? $data['programa_estudio'] ?? ''));
    $credits = trim((string)($data['credits'] ?? $data['creditos'] ?? ''));
    $cycle = trim((string)($data['cycle'] ?? $data['ciclo'] ?? ''));
    $weeks = max(4, min((int)($data['weeks'] ?? $data['semanas'] ?? 16), 24));
    $modality = trim((string)($data['modality'] ?? $data['modalidad'] ?? 'Presencial'));
    $profile = trim((string)($data['graduate_profile'] ?? $data['perfil_egreso'] ?? ''));
    $competency = trim((string)($data['competency'] ?? $data['competencia'] ?? ''));
    $startDate = trim((string)($data['start_date'] ?? $data['fecha_inicio'] ?? ''));
    $sessionsPerWeek = max(1, min((int)($data['sessions_per_week'] ?? $data['sesiones_por_semana'] ?? 1), 4));

    $numCtx = (int)($data['num_ctx'] ?? jm_cur_syl_env('SYLLABUS_NUM_CTX', '8192'));
    $numCtx = max(4096, min($numCtx, 16384));

    $numPredict = (int)($data['max_tokens'] ?? $data['num_predict'] ?? jm_cur_syl_env('SYLLABUS_NUM_PREDICT', '6200'));
    $numPredict = max(3200, min($numPredict, 9000));

    $temperature = (float)($data['temperature'] ?? jm_cur_syl_env('SYLLABUS_TEMPERATURE', '0.38'));
    $temperature = max(0.12, min($temperature, 0.70));

    $topP = (float)($data['top_p'] ?? jm_cur_syl_env('SYLLABUS_TOP_P', '0.92'));
    $topP = max(0.70, min($topP, 0.97));

    $numThread = (int)jm_cur_syl_env('SYLLABUS_NUM_THREAD', '2');
    $numThread = max(1, min($numThread, 8));

    $tokensConfig = [
        'model' => $model,
        'model_env' => jm_cur_syl_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_cur_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'num_ctx' => $numCtx,
        'num_predict' => $numPredict,
        'temperature' => $temperature,
        'top_p' => $topP,
        'num_thread' => $numThread,
        'stream' => true,
        'render_mode' => 'syllabus_curricular_traceability',
        'strategy' => 'curricular_taxonomy_methodology_traceability_v3',
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
        "Analiza semanticamente el nombre exacto del curso, el programa, el ciclo, los creditos, el perfil de egreso y la competencia.\n" .
        "Identifica internamente campo disciplinar, subcampo, prerrequisitos probables, progresion conceptual, desempenos esperados, aplicaciones profesionales y productos evaluables.\n" .
        "No escribas ese analisis interno. Usalo para construir un silabo curricular coherente.\n";

    $prompt =
        "Eres JoMelAI Curriculista universitario senior. Genera un silabo curricularmente defendible, no una lista basica de temas.\n" .
        "Responde SOLO JSON valido. No uses markdown. No agregues explicaciones fuera del JSON.\n\n" .

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
        "1. Usa alineamiento constructivo: competencia del curso -> resultados de aprendizaje -> unidades -> sesiones -> evidencias -> evaluaciones.\n" .
        "2. Usa taxonomia cognitiva en cada resultado y sesion: recordar, comprender, aplicar, analizar, evaluar o crear.\n" .
        "3. Cada resultado debe usar verbo observable y evaluable. Evita verbos vagos aislados como conocer, entender o comprender sin desempeno verificable.\n" .
        "4. Cada unidad debe explicar como contribuye a los resultados de curso.\n" .
        "5. Cada sesion debe declarar su aporte al resultado de unidad y al resultado de curso.\n" .
        "6. Cada metodologia debe estar justificada: aprendizaje basado en problemas, estudio de caso, laboratorio/taller, proyecto, simulacion, discusion guiada, aprendizaje colaborativo u otra pertinente al curso.\n" .
        "7. La evaluacion debe tener instrumento, evidencia, criterios observables y resultado vinculado.\n" .
        "8. La matriz de trazabilidad debe permitir ver claramente que cada resultado se desarrolla y evalua.\n\n" .

        "PROHIBICIONES:\n" .
        "- No uses placeholders ni textos de relleno.\n" .
        "- Prohibido escribir: resultado de aprendizaje real, contenido real, tema real, actividad concreta, producto o evidencia, criterio real, producto integrador real, construyendo, semana o fecha, fecha o semana sugerida.\n" .
        "- No inventes URLs falsas. Si no sabes una URL exacta, usa cadena vacia.\n" .
        "- No inventes autores tipo Juan Perez ni editoriales ficticias.\n\n" .

        "ESTRUCTURA JSON OBLIGATORIA:\n" .
        "{\n" .
        "  \"datos_generales\": {\n" .
        "    \"curso\": string,\n" .
        "    \"programa\": string,\n" .
        "    \"creditos\": string,\n" .
        "    \"ciclo\": string,\n" .
        "    \"semanas\": number,\n" .
        "    \"sesiones_por_semana\": number,\n" .
        "    \"modalidad\": string,\n" .
        "    \"fecha_inicio\": string,\n" .
        "    \"fecha_fin\": string,\n" .
        "    \"sistema_evaluacion\": \"Sistema vigesimal de 0 a 20\"\n" .
        "  },\n" .
        "  \"sumilla\": string,\n" .
        "  \"competencia_curso\": string,\n" .
        "  \"resultados_curso\": [\n" .
        "    {\"codigo\": \"RA1\", \"descripcion\": string, \"nivel_taxonomico\": string, \"verbo_observable\": string, \"evidencia_integradora\": string},\n" .
        "    {\"codigo\": \"RA2\", \"descripcion\": string, \"nivel_taxonomico\": string, \"verbo_observable\": string, \"evidencia_integradora\": string},\n" .
        "    {\"codigo\": \"RA3\", \"descripcion\": string, \"nivel_taxonomico\": string, \"verbo_observable\": string, \"evidencia_integradora\": string},\n" .
        "    {\"codigo\": \"RA4\", \"descripcion\": string, \"nivel_taxonomico\": string, \"verbo_observable\": string, \"evidencia_integradora\": string}\n" .
        "  ],\n" .
        "  \"unidades\": [\n" .
        "    {\n" .
        "      \"unidad\": number,\n" .
        "      \"titulo\": string,\n" .
        "      \"semanas\": [number],\n" .
        "      \"resultados_curso_vinculados\": [\"RA1\"],\n" .
        "      \"nivel_taxonomico_dominante\": string,\n" .
        "      \"resultado_unidad\": string,\n" .
        "      \"metodologia_unidad\": string,\n" .
        "      \"justificacion_metodologica\": string,\n" .
        "      \"contenidos\": [string,string,string,string,string],\n" .
        "      \"sesiones\": [\n" .
        "        {\n" .
        "          \"semana\": number,\n" .
        "          \"sesion\": number,\n" .
        "          \"titulo\": string,\n" .
        "          \"resultado_curso_vinculado\": \"RA1\",\n" .
        "          \"resultado_sesion\": string,\n" .
        "          \"aporte_a_resultado_unidad\": string,\n" .
        "          \"nivel_taxonomico\": string,\n" .
        "          \"contenidos\": [string,string,string],\n" .
        "          \"metodo\": string,\n" .
        "          \"actividad_aprendizaje\": string,\n" .
        "          \"producto\": string,\n" .
        "          \"criterio_logro\": string,\n" .
        "          \"fecha_sugerida\": string\n" .
        "        }\n" .
        "      ],\n" .
        "      \"producto_unidad\": string,\n" .
        "      \"evaluacion_producto_unidad\": {\n" .
        "        \"descripcion\": string,\n" .
        "        \"instrumento\": string,\n" .
        "        \"criterios\": [string,string,string,string],\n" .
        "        \"resultados_vinculados\": [\"RA1\"],\n" .
        "        \"puntaje_vigesimal\": 20,\n" .
        "        \"fecha_sugerida\": string\n" .
        "      }\n" .
        "    }\n" .
        "  ],\n" .
        "  \"matriz_trazabilidad\": [\n" .
        "    {\"resultado_curso\": \"RA1\", \"unidad\": number, \"sesiones\": [number], \"producto\": string, \"evaluacion\": string, \"criterio_logro\": string}\n" .
        "  ],\n" .
        "  \"evaluaciones\": [\n" .
        "    {\"tipo\": string, \"descripcion\": string, \"evidencia\": string, \"instrumento\": string, \"criterios\": [string,string,string,string], \"resultados_vinculados\": [\"RA1\"], \"puntaje_vigesimal\": number, \"semana\": number, \"fecha_sugerida\": string}\n" .
        "  ],\n" .
        "  \"metodologias\": [\n" .
        "    {\"nombre\": string, \"aplicacion\": string, \"justificacion\": string}\n" .
        "  ],\n" .
        "  \"referencias\": [\n" .
        "    {\"autor\": string, \"anio\": string, \"titulo\": string, \"fuente\": string, \"url\": string, \"utilidad\": string}\n" .
        "  ],\n" .
        "  \"enlaces\": [\n" .
        "    {\"titulo\": string, \"url\": string, \"uso\": string}\n" .
        "  ]\n" .
        "}\n\n" .

        "CANTIDAD MINIMA:\n" .
        "- Exactamente 4 resultados de curso.\n" .
        "- Exactamente 4 unidades.\n" .
        "- Cada unidad debe tener minimo 3 sesiones representativas.\n" .
        "- Cada unidad debe tener minimo 5 contenidos especificos.\n" .
        "- Minimo 4 filas de matriz de trazabilidad.\n" .
        "- Minimo 4 evaluaciones.\n" .
        "- Minimo 5 metodologias con justificacion.\n" .
        "- Minimo 4 referencias academicas.\n" .
        "- Minimo 3 recursos o enlaces.\n\n" .

        "Genera ahora el JSON final curricularmente defendible.";

    jm_sse_start();

    jm_sse_send('progress', ['percent' => 3, 'stage' => 'Inicio', 'message' => 'Preparando generación curricular.']);
    jm_sse_send('model_resolved', [
        'ok' => true,
        'provider' => jm_cur_syl_bool('LLM_REMOTE_ENABLED', false) ? 'remote_llm' : 'ollama_local',
        'model' => $model,
        'model_env' => jm_cur_syl_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_cur_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'render_mode' => 'syllabus_curricular_traceability',
    ]);

    jm_sse_send('config', [
        'ok' => true,
        'tokens_config' => $tokensConfig,
        'message' => "Generando sílabo curricular avanzado con {$model}.",
        'render_mode' => 'syllabus_curricular_traceability',
    ]);

    jm_sse_send('progress', ['percent' => 8, 'stage' => 'Análisis curricular', 'message' => 'Analizando curso, programa, perfil y competencia.']);
    jm_sse_send('progress', ['percent' => 14, 'stage' => 'Alineamiento', 'message' => 'Construyendo alineamiento competencia-resultado-unidad-sesión.']);

    $answer = '';
    $streamPieces = 0;
    $lastPercent = 14;
    $lastProgressTime = microtime(true);

    try {
        $answer = jm_cur_syl_generate(
            $model,
            $prompt,
            [
                'temperature' => $temperature,
                'top_p' => $topP,
                'repeat_penalty' => 1.15,
                'num_ctx' => $numCtx,
                'num_predict' => $numPredict,
                'num_thread' => $numThread,
            ],
            function ($piece) use (&$streamPieces, &$lastPercent, &$lastProgressTime, $numPredict) {
                $streamPieces++;
                jm_sse_send('token', ['text' => $piece]);

                $estimated = 14 + (int)min(68, floor(($streamPieces / max(1, $numPredict)) * 68));
                $now = microtime(true);

                if ($estimated > $lastPercent + 1 || ($now - $lastProgressTime) > 1.25) {
                    $lastPercent = min(82, max($lastPercent, $estimated));
                    $lastProgressTime = $now;

                    $stage = 'Construcción curricular';
                    $message = 'Construyendo unidades, sesiones, metodología, evaluación y trazabilidad.';

                    if ($lastPercent >= 30 && $lastPercent < 50) {
                        $stage = 'Unidades';
                        $message = 'Desarrollando unidades y resultados vinculados.';
                    } elseif ($lastPercent >= 50 && $lastPercent < 68) {
                        $stage = 'Sesiones';
                        $message = 'Construyendo sesiones y evidencias de aprendizaje.';
                    } elseif ($lastPercent >= 68) {
                        $stage = 'Evaluación';
                        $message = 'Armando evaluación, criterios y matriz de trazabilidad.';
                    }

                    jm_sse_send('progress', [
                        'percent' => $lastPercent,
                        'stage' => $stage,
                        'message' => $message,
                    ]);
                }
            }
        );

        jm_sse_send('progress', ['percent' => 84, 'stage' => 'Validación', 'message' => 'Validando estructura JSON y calidad curricular.']);

        $firstParse = jm_cur_syl_extract_json($answer);
        $needsRepair = jm_cur_syl_contains_bad_fillers($answer) || jm_cur_syl_needs_curricular_repair($firstParse);

        if ($needsRepair && jm_cur_syl_bool('SYLLABUS_QUALITY_REPAIR', true)) {
            jm_sse_send('quality_repair', [
                'ok' => true,
                'message' => 'Se detectó salida básica o sin trazabilidad suficiente. Reescribiendo con mayor profundidad curricular.',
            ]);

            jm_sse_send('progress', ['percent' => 88, 'stage' => 'Reparación curricular', 'message' => 'Profundizando taxonomía, metodología y trazabilidad.']);

            $repairPrompt =
                "Reescribe el siguiente JSON de sílabo conservando estructura JSON valida.\n" .
                "Debe mejorar profundidad curricular, taxonomia, metodologia, trazabilidad y alineamiento.\n" .
                "Obligatorio: resultados con codigo RA, nivel taxonomico, verbo observable, evidencia integradora; unidades vinculadas a RA; sesiones con aporte al resultado de unidad; matriz de trazabilidad; evaluaciones con criterios e instrumentos.\n" .
                "Elimina todo relleno, placeholder, conceptos basicos sin progresion, autores ficticios y URLs inventadas.\n" .
                "No uses reglas hardcodeadas por nombre de curso.\n" .
                "Curso: {$course}\n" .
                "Programa: {$program}\n" .
                "Creditos: {$credits}\n" .
                "Ciclo: {$cycle}\n" .
                "Semanas: {$weeks}\n" .
                $profilePrompt .
                $competencyPrompt .
                $disciplineInstruction .
                "\nJSON a mejorar:\n" .
                $answer .
                "\n\nDevuelve SOLO JSON valido, completo y curricularmente defendible.";

            $answer = jm_cur_syl_generate(
                $model,
                $repairPrompt,
                [
                    'temperature' => max(0.18, min($temperature, 0.42)),
                    'top_p' => $topP,
                    'repeat_penalty' => 1.18,
                    'num_ctx' => $numCtx,
                    'num_predict' => $numPredict,
                    'num_thread' => $numThread,
                ],
                function ($piece) {
                    jm_sse_send('token', ['text' => $piece]);
                }
            );
        }

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

    jm_sse_send('progress', ['percent' => 94, 'stage' => 'Renderizado', 'message' => 'Preparando formato visual del sílabo.']);

    $syllabus = jm_cur_syl_extract_json($answer);
    $parseOk = is_array($syllabus);
    $markdown = $parseOk ? jm_cur_syl_to_markdown($syllabus, $answer) : $answer;

    jm_sse_send('syllabus', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'parse_ok' => $parseOk,
        'render_mode' => 'syllabus_curricular_traceability',
        'syllabus' => $syllabus,
        'markdown' => $markdown,
        'raw_response' => $answer,
        'tokens_config' => $tokensConfig,
    ]);

    jm_sse_send('progress', ['percent' => 100, 'stage' => 'Completado', 'message' => 'Sílabo curricular generado y listo para revisión.']);

    jm_sse_send('final', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'model' => $model,
        'parse_ok' => $parseOk,
        'render_mode' => 'syllabus_curricular_traceability',
        'syllabus' => $syllabus,
        'markdown' => $markdown,
        'answer' => $markdown,
        'response' => $answer,
        'raw_response' => $answer,
        'tokens_config' => $tokensConfig,
    ]);

    exit;
}
'''

text = text[:start] + new_func + "\n\n" + text[end:].lstrip("\n")
p.write_text(text, encoding="utf-8")
PY

echo
echo "== 3) Validando PHP =="
if command -v php >/dev/null 2>&1; then
  php -l "$PHP_FILE"
else
  echo "PHP no esta instalado en host; se validara en runtime."
fi

echo
echo "== 4) Actualizando .env portable sin sed =="

touch .env
cp .env "$BACKUP_DIR/.env.bak"

python3 - "$TARGET_MODEL" <<'PY'
from pathlib import Path
import sys

target_model = sys.argv[1]
env_path = Path(".env")

updates = {
    "SYLLABUS_OLLAMA_MODEL": target_model,
    "SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE": "0",
    "SYLLABUS_QUALITY_REPAIR": "1",
    "SYLLABUS_NUM_CTX": "8192",
    "SYLLABUS_NUM_PREDICT": "6200",
    "SYLLABUS_TEMPERATURE": "0.38",
    "SYLLABUS_TOP_P": "0.92",
    "SYLLABUS_NUM_THREAD": "2",
    "SYLLABUS_KEEP_ALIVE": "30m",
}

lines = []
if env_path.exists():
    lines = env_path.read_text(encoding="utf-8", errors="ignore").splitlines()

seen = set()
out = []

for line in lines:
    raw = line.strip()
    if not raw or raw.startswith("#") or "=" not in line:
        out.append(line)
        continue

    key = line.split("=", 1)[0].strip()
    if key in updates:
        out.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        out.append(line)

for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")

env_path.write_text("\n".join(out) + "\n", encoding="utf-8")

print("ENV actualizado")
for key, value in updates.items():
    print(f"{key}={value}")
PY

PHP_DIR="$(dirname "$PHP_FILE")"
if [ "$PHP_DIR" != "." ]; then
  cp .env "$PHP_DIR/.env" || true
fi

echo
echo "== 5) Creando JS de progreso, renderer curricular y shims perdidos =="

cat > public/jomelai-syllabus-stream-progress-v3.js <<'JS'
(function () {
  var MODEL = window.JOMELAI_SYLLABUS_MODEL || "llama3.2:1b";

  function esc(v) {
    return String(v == null ? "" : v)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function list(v) {
    return Array.isArray(v) ? v : [];
  }

  function css() {
    if (document.getElementById("jm-syl-progress-v3-css")) return;

    var s = document.createElement("style");
    s.id = "jm-syl-progress-v3-css";
    s.textContent = `
      .jm-syl-progress-card{
        margin:16px 0;
        padding:16px;
        background:#fff;
        border:1px solid #e4ebf3;
        border-radius:18px;
        box-shadow:0 12px 32px rgba(15,42,75,.08);
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-syl-progress-top{
        display:flex;
        justify-content:space-between;
        gap:12px;
        align-items:center;
        margin-bottom:10px;
      }
      .jm-syl-progress-title{
        font-weight:900;
        color:#0f2a4b;
      }
      .jm-syl-progress-percent{
        font-weight:900;
        color:#0f2a4b;
        background:#eef5ff;
        border-radius:999px;
        padding:6px 10px;
      }
      .jm-syl-progress-bar{
        height:12px;
        background:#edf2f7;
        border-radius:999px;
        overflow:hidden;
      }
      .jm-syl-progress-fill{
        height:100%;
        width:0%;
        background:linear-gradient(90deg,#0f2a4b,#2c6aa0);
        transition:width .25s ease;
      }
      .jm-syl-progress-msg{
        margin-top:9px;
        color:#536174;
        font-size:13px;
      }
      .jm-syl-doc{
        margin:18px 0;
        background:#f3f6fa;
        border-radius:24px;
        padding:18px;
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-syl-paper{
        max-width:1180px;
        margin:0 auto;
        background:white;
        border-radius:22px;
        box-shadow:0 18px 50px rgba(15,42,75,.13);
        overflow:hidden;
        border:1px solid rgba(15,42,75,.08);
      }
      .jm-syl-head{
        background:linear-gradient(135deg,#0f2a4b,#173e6f);
        color:#fff;
        padding:26px 30px;
      }
      .jm-syl-head .tag{
        display:inline-block;
        padding:5px 10px;
        border-radius:999px;
        background:rgba(214,174,92,.18);
        border:1px solid rgba(214,174,92,.4);
        color:#ffe1a1;
        font-size:12px;
        margin-bottom:10px;
      }
      .jm-syl-head h2{
        margin:0;
        font-size:26px;
      }
      .jm-syl-head p{
        margin:8px 0 0;
        color:#dce9f8;
      }
      .jm-syl-section{
        padding:22px 30px;
        border-bottom:1px solid #edf1f5;
      }
      .jm-syl-section h3{
        margin:0 0 14px;
        color:#0f2a4b;
        font-size:18px;
      }
      .jm-syl-section p,
      .jm-syl-section li{
        color:#2d3f53;
        line-height:1.6;
      }
      .jm-syl-data{
        display:grid;
        grid-template-columns:repeat(4,minmax(0,1fr));
        gap:10px;
      }
      .jm-syl-data .item{
        background:#f7f9fc;
        border:1px solid #edf1f5;
        border-radius:14px;
        padding:12px;
      }
      .jm-syl-data .label{
        display:block;
        color:#66758a;
        font-size:11px;
        text-transform:uppercase;
        letter-spacing:.04em;
        margin-bottom:4px;
      }
      .jm-syl-data .value{
        color:#152b46;
        font-weight:800;
        font-size:13px;
      }
      .jm-syl-table-wrap{
        overflow-x:auto;
        margin-top:12px;
      }
      .jm-syl-table{
        width:100%;
        border-collapse:collapse;
        font-size:13px;
      }
      .jm-syl-table th{
        text-align:left;
        background:#0f2a4b;
        color:white;
        padding:10px;
        font-weight:800;
        white-space:nowrap;
      }
      .jm-syl-table td{
        border-bottom:1px solid #edf1f5;
        padding:10px;
        vertical-align:top;
        color:#2d3f53;
      }
      .jm-unit{
        border:1px solid #e4ebf3;
        border-radius:18px;
        overflow:hidden;
        margin:16px 0;
        background:#fff;
      }
      .jm-unit-title{
        padding:16px 18px;
        background:#f8fafc;
        border-bottom:1px solid #e4ebf3;
      }
      .jm-unit-title strong{
        color:#0f2a4b;
        font-size:16px;
      }
      .jm-unit-body{
        padding:16px 18px;
      }
      .jm-chip{
        display:inline-flex;
        margin:3px 5px 3px 0;
        padding:5px 9px;
        border-radius:999px;
        background:#eef5ff;
        color:#24517e;
        font-size:12px;
        font-weight:700;
      }
      .jm-actions{
        display:flex;
        gap:8px;
        justify-content:flex-end;
        padding:14px 30px;
        background:#f8fafc;
      }
      .jm-actions button{
        border:0;
        border-radius:12px;
        padding:10px 14px;
        font-weight:900;
        cursor:pointer;
        background:#0f2a4b;
        color:white;
      }
      @media(max-width:760px){
        .jm-syl-data{grid-template-columns:1fr;}
        .jm-syl-head,.jm-syl-section{padding:18px;}
      }
    `;
    document.head.appendChild(s);
  }

  function getRoot() {
    return document.querySelector("#silabos") ||
      document.querySelector("[data-page='silabos']") ||
      document.querySelector(".page-silabos") ||
      document.querySelector("main") ||
      document.body;
  }

  function ensureProgress() {
    css();

    var root = getRoot();
    var el = document.getElementById("jm-syl-progress-card");

    if (!el) {
      el = document.createElement("div");
      el.id = "jm-syl-progress-card";
      el.className = "jm-syl-progress-card";
      el.innerHTML = `
        <div class="jm-syl-progress-top">
          <div>
            <div class="jm-syl-progress-title" id="jm-syl-progress-stage">Esperando generación</div>
            <div class="jm-syl-progress-msg" id="jm-syl-progress-message">Completa el formulario y genera el sílabo.</div>
          </div>
          <div class="jm-syl-progress-percent" id="jm-syl-progress-percent">0%</div>
        </div>
        <div class="jm-syl-progress-bar"><div class="jm-syl-progress-fill" id="jm-syl-progress-fill"></div></div>
      `;
      root.insertBefore(el, root.firstChild || null);
    }

    var out = document.getElementById("jomelai-syllabus-pretty-output");
    if (!out) {
      out = document.createElement("div");
      out.id = "jomelai-syllabus-pretty-output";
      root.appendChild(out);
    }
  }

  function setProgress(percent, stage, message) {
    ensureProgress();

    percent = Math.max(0, Math.min(100, Number(percent || 0)));

    var pct = document.getElementById("jm-syl-progress-percent");
    var fill = document.getElementById("jm-syl-progress-fill");
    var st = document.getElementById("jm-syl-progress-stage");
    var msg = document.getElementById("jm-syl-progress-message");

    if (pct) pct.textContent = Math.round(percent) + "%";
    if (fill) fill.style.width = percent + "%";
    if (st && stage) st.textContent = stage;
    if (msg && message) msg.textContent = message;
  }

  function extractJson(text) {
    if (!text) return null;
    if (typeof text === "object") return text;

    try { return JSON.parse(text); } catch (e) {}

    var s = String(text);
    var a = s.indexOf("{");
    var b = s.lastIndexOf("}");

    if (a >= 0 && b > a) {
      try { return JSON.parse(s.slice(a, b + 1)); } catch (e) {}
    }

    return null;
  }

  function renderSyllabus(syl, markdown) {
    css();
    ensureProgress();

    var out = document.getElementById("jomelai-syllabus-pretty-output");
    if (!out) return;

    if (!syl) {
      out.innerHTML = `
        <div class="jm-syl-doc">
          <div class="jm-syl-paper">
            <div class="jm-syl-head">
              <span class="tag">Sílabo generado</span>
              <h2>Resultado</h2>
              <p>No se pudo convertir a JSON visual. Se muestra el texto recibido.</p>
            </div>
            <div class="jm-syl-section"><pre>${esc(markdown || "")}</pre></div>
          </div>
        </div>
      `;
      return;
    }

    var dg = syl.datos_generales || {};
    var dataHtml = [
      ["Curso", dg.curso],
      ["Programa", dg.programa],
      ["Créditos", dg.creditos],
      ["Ciclo", dg.ciclo],
      ["Semanas", dg.semanas],
      ["Modalidad", dg.modalidad],
      ["Inicio", dg.fecha_inicio],
      ["Fin", dg.fecha_fin]
    ].map(function (it) {
      return `
        <div class="item">
          <span class="label">${esc(it[0])}</span>
          <span class="value">${esc(it[1] || "")}</span>
        </div>
      `;
    }).join("");

    var resultadosHtml = list(syl.resultados_curso).map(function (r) {
      if (typeof r === "string") {
        return `<tr><td></td><td>${esc(r)}</td><td></td><td></td><td></td></tr>`;
      }

      return `
        <tr>
          <td>${esc(r.codigo || "")}</td>
          <td>${esc(r.descripcion || "")}</td>
          <td>${esc(r.nivel_taxonomico || "")}</td>
          <td>${esc(r.verbo_observable || "")}</td>
          <td>${esc(r.evidencia_integradora || "")}</td>
        </tr>
      `;
    }).join("");

    var unidadesHtml = list(syl.unidades).map(function (u) {
      var contenidos = list(u.contenidos).map(function (c) {
        return '<span class="jm-chip">' + esc(c) + '</span>';
      }).join("");

      var sesiones = list(u.sesiones).map(function (s) {
        return `
          <tr>
            <td>${esc(s.semana || "")}</td>
            <td>${esc(s.sesion || "")}</td>
            <td>${esc(s.titulo || "")}</td>
            <td>${esc(s.resultado_curso_vinculado || "")}</td>
            <td>${esc(s.nivel_taxonomico || "")}</td>
            <td>${esc(s.actividad_aprendizaje || "")}</td>
            <td>${esc(s.producto || "")}</td>
            <td>${esc(s.aporte_a_resultado_unidad || "")}</td>
          </tr>
        `;
      }).join("");

      return `
        <div class="jm-unit">
          <div class="jm-unit-title">
            <strong>Unidad ${esc(u.unidad || "")}: ${esc(u.titulo || "")}</strong>
            <div style="margin-top:6px;color:#66758a;font-size:12px;">
              Semanas: ${esc(Array.isArray(u.semanas) ? u.semanas.join(", ") : (u.semanas || ""))}
              &nbsp; | &nbsp; RA: ${esc(Array.isArray(u.resultados_curso_vinculados) ? u.resultados_curso_vinculados.join(", ") : (u.resultados_curso_vinculados || ""))}
              &nbsp; | &nbsp; Nivel: ${esc(u.nivel_taxonomico_dominante || "")}
            </div>
          </div>
          <div class="jm-unit-body">
            <p><strong>Resultado de unidad:</strong> ${esc(u.resultado_unidad || "")}</p>
            <p><strong>Metodología:</strong> ${esc(u.metodologia_unidad || "")}</p>
            <p><strong>Justificación:</strong> ${esc(u.justificacion_metodologica || "")}</p>
            <div>${contenidos}</div>
            <div class="jm-syl-table-wrap">
              <table class="jm-syl-table">
                <thead>
                  <tr>
                    <th>Semana</th><th>Sesión</th><th>Tema</th><th>RA</th><th>Nivel</th><th>Actividad</th><th>Producto</th><th>Aporte</th>
                  </tr>
                </thead>
                <tbody>${sesiones}</tbody>
              </table>
            </div>
            <p><strong>Producto integrador:</strong> ${esc(u.producto_unidad || "")}</p>
          </div>
        </div>
      `;
    }).join("");

    var trazabilidadHtml = list(syl.matriz_trazabilidad).map(function (t) {
      return `
        <tr>
          <td>${esc(t.resultado_curso || "")}</td>
          <td>${esc(t.unidad || "")}</td>
          <td>${esc(Array.isArray(t.sesiones) ? t.sesiones.join(", ") : (t.sesiones || ""))}</td>
          <td>${esc(t.producto || "")}</td>
          <td>${esc(t.evaluacion || "")}</td>
          <td>${esc(t.criterio_logro || "")}</td>
        </tr>
      `;
    }).join("");

    var evalHtml = list(syl.evaluaciones).map(function (e) {
      return `
        <tr>
          <td>${esc(e.tipo || "")}</td>
          <td>${esc(e.descripcion || "")}</td>
          <td>${esc(e.evidencia || "")}</td>
          <td>${esc(e.instrumento || "")}</td>
          <td>${esc(Array.isArray(e.resultados_vinculados) ? e.resultados_vinculados.join(", ") : (e.resultados_vinculados || ""))}</td>
          <td>${esc(e.semana || "")}</td>
          <td>${esc(e.puntaje_vigesimal || "")}</td>
        </tr>
      `;
    }).join("");

    var metodHtml = list(syl.metodologias).map(function (m) {
      if (typeof m === "string") return "<li>" + esc(m) + "</li>";
      return "<li><strong>" + esc(m.nombre || "") + ":</strong> " + esc(m.aplicacion || "") + " " + esc(m.justificacion || "") + "</li>";
    }).join("");

    var refsHtml = list(syl.referencias).map(function (r) {
      if (typeof r === "string") return "<li>" + esc(r) + "</li>";
      return "<li>" + esc((r.autor || "") + " (" + (r.anio || "") + "). " + (r.titulo || "") + ". " + (r.fuente || "") + (r.url ? ". " + r.url : "")) + "</li>";
    }).join("");

    out.innerHTML = `
      <div class="jm-syl-doc">
        <div class="jm-syl-paper">
          <div class="jm-syl-head">
            <span class="tag">Sílabo curricular con trazabilidad</span>
            <h2>${esc(dg.curso || "Sílabo")}</h2>
            <p>${esc(dg.programa || "")}</p>
          </div>

          <div class="jm-syl-section">
            <h3>I. Datos generales</h3>
            <div class="jm-syl-data">${dataHtml}</div>
          </div>

          <div class="jm-syl-section">
            <h3>II. Sumilla</h3>
            <p>${esc(syl.sumilla || "")}</p>
          </div>

          <div class="jm-syl-section">
            <h3>III. Competencia del curso</h3>
            <p>${esc(syl.competencia_curso || "")}</p>
          </div>

          <div class="jm-syl-section">
            <h3>IV. Resultados de aprendizaje y taxonomía</h3>
            <div class="jm-syl-table-wrap">
              <table class="jm-syl-table">
                <thead><tr><th>Código</th><th>Resultado</th><th>Nivel</th><th>Verbo</th><th>Evidencia</th></tr></thead>
                <tbody>${resultadosHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-syl-section">
            <h3>V. Unidades y sesiones</h3>
            ${unidadesHtml}
          </div>

          <div class="jm-syl-section">
            <h3>VI. Matriz de trazabilidad curricular</h3>
            <div class="jm-syl-table-wrap">
              <table class="jm-syl-table">
                <thead><tr><th>RA</th><th>Unidad</th><th>Sesiones</th><th>Producto</th><th>Evaluación</th><th>Criterio de logro</th></tr></thead>
                <tbody>${trazabilidadHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-syl-section">
            <h3>VII. Evaluación</h3>
            <div class="jm-syl-table-wrap">
              <table class="jm-syl-table">
                <thead><tr><th>Tipo</th><th>Descripción</th><th>Evidencia</th><th>Instrumento</th><th>RA</th><th>Semana</th><th>Puntaje</th></tr></thead>
                <tbody>${evalHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-syl-section">
            <h3>VIII. Metodologías</h3>
            <ul>${metodHtml}</ul>
          </div>

          <div class="jm-syl-section">
            <h3>IX. Referencias</h3>
            <ul>${refsHtml}</ul>
          </div>

          <div class="jm-actions">
            <button type="button" id="jm-copy-syllabus-md">Copiar Markdown</button>
            <button type="button" id="jm-copy-syllabus-json">Copiar JSON</button>
          </div>
        </div>
      </div>
    `;

    var mdBtn = document.getElementById("jm-copy-syllabus-md");
    var jsonBtn = document.getElementById("jm-copy-syllabus-json");

    if (mdBtn) {
      mdBtn.onclick = function () {
        navigator.clipboard.writeText(markdown || "");
      };
    }

    if (jsonBtn) {
      jsonBtn.onclick = function () {
        navigator.clipboard.writeText(JSON.stringify(syl, null, 2));
      };
    }
  }

  function isSyllabusUrl(input) {
    var url = typeof input === "string" ? input : (input && input.url ? input.url : "");
    return url.indexOf("/api/assistant/generate-syllabus-stream") !== -1;
  }

  function handleEvent(eventName, dataText) {
    var data = null;

    try {
      data = JSON.parse(dataText);
    } catch (e) {
      data = null;
    }

    if (eventName === "progress" && data) {
      setProgress(data.percent, data.stage, data.message);
      return;
    }

    if (eventName === "config" && data) {
      setProgress(10, "Configuración", data.message || "Configurando generación curricular.");
      return;
    }

    if (eventName === "quality_repair" && data) {
      setProgress(88, "Reparación curricular", data.message || "Profundizando salida.");
      return;
    }

    if ((eventName === "syllabus" || eventName === "final") && data) {
      var syl = data.syllabus || extractJson(data.raw_response) || extractJson(data.response) || extractJson(data.answer);
      var md = data.markdown || data.answer || "";
      renderSyllabus(syl, md);

      if (eventName === "final") {
        setProgress(100, "Completado", "Sílabo curricular generado y listo para revisión.");
      }
    }
  }

  function parseSseBuffer(buffer, onEvent) {
    var parts = buffer.split(/\r?\n\r?\n/);
    var rest = parts.pop();

    parts.forEach(function (block) {
      var ev = "message";
      var data = [];

      block.split(/\r?\n/).forEach(function (line) {
        if (line.indexOf("event:") === 0) {
          ev = line.slice(6).trim();
        } else if (line.indexOf("data:") === 0) {
          data.push(line.slice(5).trim());
        }
      });

      if (data.length) {
        onEvent(ev, data.join("\n"));
      }
    });

    return rest;
  }

  function patchFetch() {
    if (!window.fetch || window.fetch.__jmSyllabusProgressV3) return;

    var originalFetch = window.fetch;

    window.fetch = function (input, init) {
      if (!isSyllabusUrl(input)) {
        return originalFetch.apply(this, arguments);
      }

      ensureProgress();
      setProgress(2, "Inicio", "Enviando solicitud al generador curricular.");

      var opts = {};
      init = init || {};
      Object.keys(init).forEach(function (k) { opts[k] = init[k]; });

      try {
        if (typeof opts.body === "string" && opts.body.trim().charAt(0) === "{") {
          var payload = JSON.parse(opts.body);
          payload.model = MODEL;
          payload.render_mode = "syllabus_curricular_traceability";
          payload.max_tokens = payload.max_tokens || 6200;
          payload.num_ctx = payload.num_ctx || 8192;
          opts.body = JSON.stringify(payload);
        }
      } catch (e) {}

      return originalFetch.call(this, input, opts).then(function (resp) {
        if (!resp.body || !resp.body.tee) {
          resp.clone().text().then(function (text) {
            var rest = "";
            rest += text;
            parseSseBuffer(rest + "\n\n", handleEvent);
          }).catch(function () {});
          return resp;
        }

        var streams = resp.body.tee();
        var uiStream = streams[0];
        var appStream = streams[1];

        var reader = uiStream.getReader();
        var decoder = new TextDecoder();
        var buffer = "";

        function pump() {
          reader.read().then(function (res) {
            if (res.done) {
              buffer = parseSseBuffer(buffer + "\n\n", handleEvent);
              return;
            }

            buffer += decoder.decode(res.value, { stream: true });
            buffer = parseSseBuffer(buffer, handleEvent);
            pump();
          }).catch(function () {});
        }

        pump();

        return new Response(appStream, {
          status: resp.status,
          statusText: resp.statusText,
          headers: resp.headers
        });
      });
    };

    window.fetch.__jmSyllabusProgressV3 = true;
  }

  function init() {
    css();
    ensureProgress();
    patchFetch();
    console.log("[JoMelAi] Syllabus curricular progress v3 activo");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
JS

# Recuperar JS que el index sigue pidiendo para evitar 404.
cat > public/jomelai-syllabus-pretty-v7-live.js <<'JS'
(function () {
  console.log("[JoMelAi] jomelai-syllabus-pretty-v7-live compatibility activo");
  window.JOMELAI_SYLLABUS_PRETTY_READY = true;
})();
JS

cat > public/chat-lateral-v2-client.js <<'JS'
(function () {
  console.log("[JoMelAi] chat-lateral-v2-client compatibility activo");
  window.JOMELAI_CHAT_LATERAL_READY = true;
})();
JS

cat > public/chat-panel-renderer-final.js <<'JS'
(function () {
  console.log("[JoMelAi] chat-panel-renderer-final compatibility activo");
  window.JOMELAI_CHAT_PANEL_RENDERER_READY = true;
})();
JS

cat > public/chat-pie-image-override.js <<'JS'
(function () {
  console.log("[JoMelAi] chat-pie-image-override compatibility activo");
  window.JOMELAI_CHAT_PIE_OVERRIDE_READY = true;
})();
JS

for f in \
  jomelai-syllabus-stream-progress-v3.js \
  jomelai-syllabus-pretty-v7-live.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js
do
  cp "public/$f" "./$f"
done

echo
echo "== 6) Inyectando JS nuevo en index.html locales =="

python3 <<'PY'
from pathlib import Path
import re

files = [
    Path("index.html"),
    Path("public/index.html"),
    Path("dist/index.html"),
    Path("build/index.html"),
]

script = "jomelai-syllabus-stream-progress-v3.js"
tag = f'  <script src="/{script}?v=curricular-progress-v3"></script>'

for p in files:
    if not p.exists():
        continue

    text = p.read_text(encoding="utf-8", errors="ignore")
    text = re.sub(
        r'\s*<script[^>]+src=["\']/' + re.escape(script) + r'(?:\?[^"\']*)?["\'][^>]*></script>',
        "",
        text,
        flags=re.I
    )

    if "</body>" in text:
        text = text.replace("</body>", tag + "\n</body>", 1)
    elif "</head>" in text:
        text = text.replace("</head>", tag + "\n</head>", 1)
    else:
        text += "\n" + tag + "\n"

    p.write_text(text, encoding="utf-8")
    print("parchado:", p)
PY

echo
echo "== 7) Copiando JS al frontend Docker activo =="

FRONT_CONTAINER=""

for svc in frontend front web nginx app client; do
  cid="$(docker compose ps -q "$svc" 2>/dev/null | head -1 || true)"
  if [ -n "$cid" ]; then
    name="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##' || true)"
    if [ -n "$name" ]; then
      FRONT_CONTAINER="$name"
      break
    fi
  fi
done

if [ -z "$FRONT_CONTAINER" ]; then
  FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
    | grep -Ei '3000|frontend|nginx|web|vite|node' \
    | grep -vi 'data_engine' \
    | grep -vi 'ollama' \
    | head -1 \
    | awk '{print $1}' || true)"
fi

if [ -n "$FRONT_CONTAINER" ]; then
  echo "FRONT_CONTAINER=$FRONT_CONTAINER"

  FRONT_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
    if command -v nginx >/dev/null 2>&1; then
      nginx -T 2>/dev/null | awk "/root / {gsub(\";\", \"\", \$2); print \$2; exit}"
    fi
  ' || true)"

  if [ -z "$FRONT_ROOT" ]; then
    FRONT_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
      for d in /usr/share/nginx/html /app/dist /app/build /app/public /var/www/html /app; do
        [ -d "$d" ] && echo "$d" && exit 0
      done
      echo /usr/share/nginx/html
    ' || true)"
  fi

  echo "FRONT_ROOT=$FRONT_ROOT"

  for f in \
    jomelai-syllabus-stream-progress-v3.js \
    jomelai-syllabus-pretty-v7-live.js \
    chat-lateral-v2-client.js \
    chat-panel-renderer-final.js \
    chat-pie-image-override.js
  do
    docker cp "public/$f" "$FRONT_CONTAINER:$FRONT_ROOT/$f"
    echo "copiado: $FRONT_ROOT/$f"
  done

  INDEX_FILE="$(docker exec "$FRONT_CONTAINER" sh -lc "
    for f in '$FRONT_ROOT/index.html' /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html /app/index.html; do
      [ -f \"\$f\" ] && echo \"\$f\" && exit 0
    done
    exit 0
  " || true)"

  if [ -n "$INDEX_FILE" ]; then
    docker cp "$FRONT_CONTAINER:$INDEX_FILE" "$BACKUP_DIR/index.container.bak.html"

    python3 - "$BACKUP_DIR/index.container.bak.html" "$BACKUP_DIR/index.container.patched.html" <<'PY'
from pathlib import Path
import re
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
text = src.read_text(encoding="utf-8", errors="ignore")

script = "jomelai-syllabus-stream-progress-v3.js"
tag = f'  <script src="/{script}?v=curricular-progress-v3"></script>'

text = re.sub(
    r'\s*<script[^>]+src=["\']/' + re.escape(script) + r'(?:\?[^"\']*)?["\'][^>]*></script>',
    "",
    text,
    flags=re.I
)

if "</body>" in text:
    text = text.replace("</body>", tag + "\n</body>", 1)
elif "</head>" in text:
    text = text.replace("</head>", tag + "\n</head>", 1)
else:
    text += "\n" + tag + "\n"

dst.write_text(text, encoding="utf-8")
PY

    docker cp "$BACKUP_DIR/index.container.patched.html" "$FRONT_CONTAINER:$INDEX_FILE"

    docker exec "$FRONT_CONTAINER" sh -lc '
      if command -v nginx >/dev/null 2>&1; then
        nginx -t && nginx -s reload
      fi
    ' || true
  fi
else
  echo "WARN: no detecte frontend activo. Los JS quedaron en public/ para el proximo build."
fi

echo
echo "== 8) Rebuild/restart sin borrar volumenes =="
docker compose up -d --build

sleep 8

echo
echo "== 9) Verificando JS por HTTP =="
APP_PORT="$(python3 - <<'PY'
from pathlib import Path
port = "3000"
p = Path(".env")
if p.exists():
    for line in p.read_text(errors="ignore").splitlines():
        if line.startswith("APP_PORT="):
            port = line.split("=", 1)[1].strip() or "3000"
print(port)
PY
)"

for f in \
  jomelai-syllabus-stream-progress-v3.js \
  jomelai-syllabus-pretty-v7-live.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js
do
  echo
  echo "---- http://localhost:${APP_PORT}/$f ----"
  curl -sS -I "http://localhost:${APP_PORT}/$f?v=check" | head -5 || true
done

echo
echo "== 10) Test stream con progreso =="
curl -sS -N -m 260 -X POST "http://localhost:${APP_PORT}/api/assistant/generate-syllabus-stream" \
  -H "Content-Type: application/json" \
  -d '{
    "course": "Cálculo Diferencial",
    "program": "Ingeniería de Sistemas",
    "credits": "4",
    "cycle": "3",
    "weeks": "16",
    "modality": "Presencial",
    "graduate_profile": "Analiza problemas de ingeniería, modela situaciones reales y toma decisiones sustentadas con razonamiento matemático y tecnológico.",
    "competency": "Aplica conceptos matemáticos para modelar, analizar y resolver problemas de cambio, variación y optimización en contextos de ingeniería.",
    "sessions_per_week": "1"
  }' | grep -E "event: progress|percent|event: config|curricular_taxonomy|quality_repair|matriz_trazabilidad|nivel_taxonomico|contenido real|resultado de aprendizaje real|tema real" | head -120 || true

echo
echo
echo "== 11) Git status =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Cambios aplicados:"
echo "  - Tokens/contexto: SYLLABUS_NUM_CTX=8192, SYLLABUS_NUM_PREDICT=6200"
echo "  - Prompt curricular: taxonomia + metodologia + trazabilidad"
echo "  - Stream: event: progress con porcentaje"
echo "  - Frontend: barra de progreso y renderer curricular"
echo "  - JS perdidos recuperados para eliminar 404"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "En navegador:"
echo "  Ctrl + Shift + R"
echo
echo "En consola debe aparecer:"
echo "  [JoMelAi] Syllabus curricular progress v3 activo"
