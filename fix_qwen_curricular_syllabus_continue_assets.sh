#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"
TARGET_MODEL="${1:-qwen2.5:1.5b}"

echo "=================================================="
echo " Fix Qwen curricular syllabus + continue button + assets"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "TARGET_MODEL=$TARGET_MODEL"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: ejecuta este script desde la carpeta donde esta docker-compose.yml o compose.yml"
  exit 1
fi

BACKUP_DIR="backups/fix_qwen_curricular_syllabus_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
mkdir -p public

echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Instalando/verificando modelo Qwen en Ollama =="

OLLAMA_CONTAINER="$(docker ps --format '{{.Names}} {{.Image}}' | grep -Ei 'ollama' | head -1 | awk '{print $1}' || true)"

if [ -n "$OLLAMA_CONTAINER" ]; then
  echo "OLLAMA_CONTAINER=$OLLAMA_CONTAINER"

  docker exec "$OLLAMA_CONTAINER" sh -lc "
    if ollama list | awk '{print \$1}' | grep -Fxq '$TARGET_MODEL'; then
      echo '$TARGET_MODEL ya existe.'
    else
      echo 'Descargando $TARGET_MODEL...'
      ollama pull '$TARGET_MODEL'
    fi

    ollama list | grep -E 'qwen|llama' || true
  "
else
  echo "WARN: no detecte contenedor Ollama. Si corres Ollama local fuera de Docker, ejecuta:"
  echo "  ollama pull $TARGET_MODEL"
fi

echo
echo "== 2) Buscando PHP real del stream, excluyendo exports/backups =="

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
  echo "  PHP_FILE_OVERRIDE=./public/jomelai_stream_routes.php ./fix_qwen_curricular_syllabus_continue_assets.sh $TARGET_MODEL"
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
echo "== 3) Reemplazando endpoint por Qwen curricular V4 con boton continuar =="

python3 - "$PHP_FILE" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

for block in [
    "JOMELAI_QWEN_CURRICULAR_SYLLABUS_V4",
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
'''

m = re.search(r'function\s+jm_handle_syllabus_stream\s*\([^)]*\)\s*\{', text)
if not m:
    raise SystemExit("No se encontro function jm_handle_syllabus_stream().")

start = m.start()
brace_start = text.find("{", m.end() - 1)
depth = 0
end = None

for i in range(brace_start, len(text)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break

if end is None:
    raise SystemExit("No se pudo ubicar cierre de jm_handle_syllabus_stream().")

text = text[:start] + helpers + "\n\n" + text[start:]

m = re.search(r'function\s+jm_handle_syllabus_stream\s*\([^)]*\)\s*\{', text)
start = m.start()
brace_start = text.find("{", m.end() - 1)
depth = 0
end = None

for i in range(brace_start, len(text)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break

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
'''

text = text[:start] + new_func + text[end:]
p.write_text(text, encoding="utf-8")
PY

echo
echo "== 4) Validando PHP =="
if command -v php >/dev/null 2>&1; then
  php -l "$PHP_FILE"
else
  echo "PHP no esta instalado en host; se validara en runtime."
fi

echo
echo "== 5) Actualizando .env portable =="

touch .env
cp .env "$BACKUP_DIR/.env.bak"

python3 - "$TARGET_MODEL" <<'PY'
from pathlib import Path
import sys

target_model = sys.argv[1]
env_path = Path(".env")

updates = {
    "SYLLABUS_OLLAMA_MODEL": target_model,
    "VITE_SYLLABUS_OLLAMA_MODEL": target_model,
    "VITE_DEFAULT_SYLLABUS_MODEL": target_model,
    "SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE": "0",
    "SYLLABUS_QUALITY_REPAIR": "1",
    "SYLLABUS_NUM_CTX": "8192",
    "SYLLABUS_NUM_PREDICT": "7200",
    "SYLLABUS_TEMPERATURE": "0.28",
    "SYLLABUS_TOP_P": "0.86",
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

for key, value in updates.items():
    print(f"{key}={value}")
PY

PHP_DIR="$(dirname "$PHP_FILE")"
if [ "$PHP_DIR" != "." ]; then
  cp .env "$PHP_DIR/.env" || true
fi

echo
echo "== 6) Creando frontend: progreso + continuar + renderer + assets 404 =="

cat > public/jomelai-syllabus-qwen-v4.js <<'JS'
(function () {
  var MODEL = window.JOMELAI_SYLLABUS_MODEL || "qwen2.5:1.5b";
  var lastRequestPayload = null;
  var lastRawResponse = "";

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
    if (document.getElementById("jm-qwen-syl-v4-css")) return;

    var s = document.createElement("style");
    s.id = "jm-qwen-syl-v4-css";
    s.textContent = `
      .jm-qwen-progress{
        margin:16px 0;
        padding:16px;
        border:1px solid #e4ebf3;
        border-radius:18px;
        background:#fff;
        box-shadow:0 12px 32px rgba(15,42,75,.08);
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-qwen-progress-top{
        display:flex;
        align-items:center;
        justify-content:space-between;
        gap:12px;
        margin-bottom:10px;
      }
      .jm-qwen-stage{
        font-weight:900;
        color:#0f2a4b;
      }
      .jm-qwen-percent{
        font-weight:900;
        color:#0f2a4b;
        background:#eef5ff;
        border-radius:999px;
        padding:6px 10px;
      }
      .jm-qwen-bar{
        height:12px;
        border-radius:999px;
        overflow:hidden;
        background:#edf2f7;
      }
      .jm-qwen-fill{
        height:100%;
        width:0%;
        background:linear-gradient(90deg,#0f2a4b,#2c6aa0);
        transition:width .25s ease;
      }
      .jm-qwen-msg{
        margin-top:8px;
        color:#536174;
        font-size:13px;
      }
      .jm-qwen-doc{
        margin:18px 0;
        background:#f3f6fa;
        border-radius:24px;
        padding:18px;
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-qwen-paper{
        max-width:1180px;
        margin:0 auto;
        background:white;
        border-radius:22px;
        box-shadow:0 18px 50px rgba(15,42,75,.13);
        overflow:hidden;
        border:1px solid rgba(15,42,75,.08);
      }
      .jm-qwen-head{
        background:linear-gradient(135deg,#0f2a4b,#173e6f);
        color:#fff;
        padding:26px 30px;
      }
      .jm-qwen-tag{
        display:inline-block;
        padding:5px 10px;
        border-radius:999px;
        background:rgba(214,174,92,.18);
        border:1px solid rgba(214,174,92,.4);
        color:#ffe1a1;
        font-size:12px;
        margin-bottom:10px;
      }
      .jm-qwen-head h2{
        margin:0;
        font-size:26px;
      }
      .jm-qwen-head p{
        margin:8px 0 0;
        color:#dce9f8;
      }
      .jm-qwen-section{
        padding:22px 30px;
        border-bottom:1px solid #edf1f5;
      }
      .jm-qwen-section h3{
        margin:0 0 14px;
        color:#0f2a4b;
        font-size:18px;
      }
      .jm-qwen-section p,
      .jm-qwen-section li{
        color:#2d3f53;
        line-height:1.6;
      }
      .jm-qwen-data{
        display:grid;
        grid-template-columns:repeat(4,minmax(0,1fr));
        gap:10px;
      }
      .jm-qwen-item{
        background:#f7f9fc;
        border:1px solid #edf1f5;
        border-radius:14px;
        padding:12px;
      }
      .jm-qwen-label{
        display:block;
        color:#66758a;
        font-size:11px;
        text-transform:uppercase;
        letter-spacing:.04em;
        margin-bottom:4px;
      }
      .jm-qwen-value{
        color:#152b46;
        font-weight:800;
        font-size:13px;
      }
      .jm-qwen-table-wrap{
        overflow-x:auto;
        margin-top:12px;
      }
      .jm-qwen-table{
        width:100%;
        border-collapse:collapse;
        font-size:13px;
      }
      .jm-qwen-table th{
        text-align:left;
        background:#0f2a4b;
        color:white;
        padding:10px;
        font-weight:800;
        white-space:nowrap;
      }
      .jm-qwen-table td{
        border-bottom:1px solid #edf1f5;
        padding:10px;
        vertical-align:top;
        color:#2d3f53;
      }
      .jm-qwen-unit{
        border:1px solid #e4ebf3;
        border-radius:18px;
        overflow:hidden;
        margin:16px 0;
        background:#fff;
      }
      .jm-qwen-unit-title{
        padding:16px 18px;
        background:#f8fafc;
        border-bottom:1px solid #e4ebf3;
      }
      .jm-qwen-unit-title strong{
        color:#0f2a4b;
        font-size:16px;
      }
      .jm-qwen-unit-body{
        padding:16px 18px;
      }
      .jm-qwen-chip{
        display:inline-flex;
        margin:3px 5px 3px 0;
        padding:5px 9px;
        border-radius:999px;
        background:#eef5ff;
        color:#24517e;
        font-size:12px;
        font-weight:700;
      }
      .jm-qwen-actions{
        display:flex;
        flex-wrap:wrap;
        gap:8px;
        justify-content:flex-end;
        padding:14px 30px;
        background:#f8fafc;
      }
      .jm-qwen-actions button{
        border:0;
        border-radius:12px;
        padding:10px 14px;
        font-weight:900;
        cursor:pointer;
        background:#0f2a4b;
        color:white;
      }
      .jm-qwen-actions button.secondary{
        background:#6b7280;
      }
      .jm-qwen-warning{
        margin:14px 0;
        padding:12px;
        border-radius:14px;
        background:#fff7ed;
        border:1px solid #fed7aa;
        color:#9a3412;
        font-size:13px;
      }
      @media(max-width:760px){
        .jm-qwen-data{grid-template-columns:1fr;}
        .jm-qwen-head,.jm-qwen-section{padding:18px;}
      }
    `;
    document.head.appendChild(s);
  }

  function root() {
    return document.querySelector("#silabos") ||
      document.querySelector("[data-page='silabos']") ||
      document.querySelector(".page-silabos") ||
      document.querySelector("main") ||
      document.body;
  }

  function ensureUi() {
    css();

    var r = root();

    if (!document.getElementById("jm-qwen-progress")) {
      var p = document.createElement("div");
      p.id = "jm-qwen-progress";
      p.className = "jm-qwen-progress";
      p.innerHTML = `
        <div class="jm-qwen-progress-top">
          <div>
            <div class="jm-qwen-stage" id="jm-qwen-stage">Esperando generación</div>
            <div class="jm-qwen-msg" id="jm-qwen-msg">Completa el formulario y genera el sílabo.</div>
          </div>
          <div class="jm-qwen-percent" id="jm-qwen-percent">0%</div>
        </div>
        <div class="jm-qwen-bar"><div class="jm-qwen-fill" id="jm-qwen-fill"></div></div>
      `;
      r.insertBefore(p, r.firstChild || null);
    }

    if (!document.getElementById("jomelai-syllabus-pretty-output")) {
      var out = document.createElement("div");
      out.id = "jomelai-syllabus-pretty-output";
      r.appendChild(out);
    }
  }

  function setProgress(percent, stage, message) {
    ensureUi();

    percent = Math.max(0, Math.min(100, Number(percent || 0)));

    var pct = document.getElementById("jm-qwen-percent");
    var fill = document.getElementById("jm-qwen-fill");
    var st = document.getElementById("jm-qwen-stage");
    var msg = document.getElementById("jm-qwen-msg");

    if (pct) pct.textContent = Math.round(percent) + "%";
    if (fill) fill.style.width = percent + "%";
    if (st && stage) st.textContent = stage;
    if (msg && message) msg.textContent = message;
  }

  function extractJson(text) {
    if (!text) return null;
    if (typeof text === "object") return text;

    try {
      return JSON.parse(text);
    } catch (e) {}

    var s = String(text);
    var a = s.indexOf("{");
    var b = s.lastIndexOf("}");

    if (a >= 0 && b > a) {
      try {
        return JSON.parse(s.slice(a, b + 1));
      } catch (e) {}
    }

    return null;
  }

  function renderRaw(markdown, payload) {
    var out = document.getElementById("jomelai-syllabus-pretty-output");
    if (!out) return;

    var issues = payload && Array.isArray(payload.quality_issues) ? payload.quality_issues : [];

    out.innerHTML = `
      <div class="jm-qwen-doc">
        <div class="jm-qwen-paper">
          <div class="jm-qwen-head">
            <span class="jm-qwen-tag">Sílabo incompleto</span>
            <h2>La generación necesita completarse</h2>
            <p>El modelo devolvió JSON incompleto o baja calidad curricular. Puedes continuar la generación con Qwen.</p>
          </div>
          <div class="jm-qwen-section">
            <h3>Observaciones</h3>
            <div class="jm-qwen-warning">
              ${issues.length ? "<ul>" + issues.map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ul>" : "La respuesta quedó incompleta o no pudo convertirse a JSON válido."}
            </div>
            <pre style="white-space:pre-wrap;max-height:340px;overflow:auto;background:#0f172a;color:#e5e7eb;padding:14px;border-radius:14px;">${esc(markdown || "")}</pre>
          </div>
          <div class="jm-qwen-actions">
            <button type="button" id="jm-qwen-continue">Continuar generación</button>
            <button type="button" class="secondary" id="jm-qwen-copy-raw">Copiar borrador</button>
          </div>
        </div>
      </div>
    `;

    var btn = document.getElementById("jm-qwen-continue");
    var copy = document.getElementById("jm-qwen-copy-raw");

    if (copy) {
      copy.onclick = function () {
        navigator.clipboard.writeText(markdown || "");
      };
    }

    if (btn) {
      btn.onclick = function () {
        if (!lastRequestPayload) {
          alert("No encontré el payload anterior para continuar.");
          return;
        }

        var next = {};
        Object.keys(lastRequestPayload).forEach(function (k) {
          next[k] = lastRequestPayload[k];
        });

        next.model = MODEL;
        next.continue_generation = true;
        next.previous_raw = lastRawResponse || markdown || "";
        next.max_tokens = 7200;
        next.num_ctx = 8192;
        next.render_mode = "syllabus_qwen_curricular_v4";

        setProgress(3, "Continuando generación", "Reconstruyendo el sílabo completo con Qwen.");

        fetch("/api/assistant/generate-syllabus-stream", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(next)
        });
      };
    }
  }

  function renderSyllabus(syl, markdown, payload) {
    ensureUi();

    if (!syl) {
      renderRaw(markdown, payload);
      return;
    }

    var out = document.getElementById("jomelai-syllabus-pretty-output");
    if (!out) return;

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
        <div class="jm-qwen-item">
          <span class="jm-qwen-label">${esc(it[0])}</span>
          <span class="jm-qwen-value">${esc(it[1] || "")}</span>
        </div>
      `;
    }).join("");

    var raHtml = list(syl.resultados_curso).map(function (r) {
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
      var contents = list(u.contenidos).map(function (c) {
        return '<span class="jm-qwen-chip">' + esc(c) + '</span>';
      }).join("");

      var sessions = list(u.sesiones).map(function (s) {
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
        <div class="jm-qwen-unit">
          <div class="jm-qwen-unit-title">
            <strong>Unidad ${esc(u.unidad || "")}: ${esc(u.titulo || "")}</strong>
            <div style="margin-top:6px;color:#66758a;font-size:12px;">
              Semanas: ${esc(Array.isArray(u.semanas) ? u.semanas.join(", ") : (u.semanas || ""))}
              | RA: ${esc(Array.isArray(u.resultados_curso_vinculados) ? u.resultados_curso_vinculados.join(", ") : (u.resultados_curso_vinculados || ""))}
              | Nivel: ${esc(u.nivel_taxonomico_dominante || "")}
            </div>
          </div>
          <div class="jm-qwen-unit-body">
            <p><strong>Resultado de unidad:</strong> ${esc(u.resultado_unidad || "")}</p>
            <p><strong>Metodología:</strong> ${esc(u.metodologia_unidad || "")}</p>
            <p><strong>Justificación:</strong> ${esc(u.justificacion_metodologica || "")}</p>
            <div>${contents}</div>
            <div class="jm-qwen-table-wrap">
              <table class="jm-qwen-table">
                <thead><tr><th>Semana</th><th>Sesión</th><th>Tema</th><th>RA</th><th>Nivel</th><th>Actividad</th><th>Producto</th><th>Aporte</th></tr></thead>
                <tbody>${sessions}</tbody>
              </table>
            </div>
            <p><strong>Producto integrador:</strong> ${esc(u.producto_unidad || "")}</p>
          </div>
        </div>
      `;
    }).join("");

    var traceHtml = list(syl.matriz_trazabilidad).map(function (t) {
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

    var metHtml = list(syl.metodologias).map(function (m) {
      return "<li><strong>" + esc(m.nombre || "") + ":</strong> " + esc(m.aplicacion || "") + " " + esc(m.justificacion || "") + "</li>";
    }).join("");

    var refHtml = list(syl.referencias).map(function (r) {
      return "<li>" + esc((r.autor || "") + " (" + (r.anio || "") + "). " + (r.titulo || "") + ". " + (r.fuente || "") + (r.url ? ". " + r.url : "")) + "</li>";
    }).join("");

    var needs = payload && payload.needs_continue;

    out.innerHTML = `
      <div class="jm-qwen-doc">
        <div class="jm-qwen-paper">
          <div class="jm-qwen-head">
            <span class="jm-qwen-tag">Sílabo curricular Qwen</span>
            <h2>${esc(dg.curso || "Sílabo")}</h2>
            <p>${esc(dg.programa || "")}</p>
          </div>

          ${needs ? '<div class="jm-qwen-section"><div class="jm-qwen-warning">El sistema detectó que aún puede mejorar. Puedes usar “Continuar generación”.</div></div>' : ''}

          <div class="jm-qwen-section">
            <h3>I. Datos generales</h3>
            <div class="jm-qwen-data">${dataHtml}</div>
          </div>

          <div class="jm-qwen-section">
            <h3>II. Sumilla</h3>
            <p>${esc(syl.sumilla || "")}</p>
          </div>

          <div class="jm-qwen-section">
            <h3>III. Competencia del curso</h3>
            <p>${esc(syl.competencia_curso || "")}</p>
          </div>

          <div class="jm-qwen-section">
            <h3>IV. Resultados de aprendizaje y taxonomía</h3>
            <div class="jm-qwen-table-wrap">
              <table class="jm-qwen-table">
                <thead><tr><th>Código</th><th>Resultado</th><th>Nivel</th><th>Verbo</th><th>Evidencia</th></tr></thead>
                <tbody>${raHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-qwen-section">
            <h3>V. Unidades y sesiones</h3>
            ${unidadesHtml}
          </div>

          <div class="jm-qwen-section">
            <h3>VI. Matriz de trazabilidad curricular</h3>
            <div class="jm-qwen-table-wrap">
              <table class="jm-qwen-table">
                <thead><tr><th>RA</th><th>Unidad</th><th>Sesiones</th><th>Producto</th><th>Evaluación</th><th>Criterio</th></tr></thead>
                <tbody>${traceHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-qwen-section">
            <h3>VII. Evaluación</h3>
            <div class="jm-qwen-table-wrap">
              <table class="jm-qwen-table">
                <thead><tr><th>Tipo</th><th>Descripción</th><th>Evidencia</th><th>Instrumento</th><th>RA</th><th>Semana</th><th>Puntaje</th></tr></thead>
                <tbody>${evalHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-qwen-section">
            <h3>VIII. Metodologías</h3>
            <ul>${metHtml}</ul>
          </div>

          <div class="jm-qwen-section">
            <h3>IX. Referencias</h3>
            <ul>${refHtml}</ul>
          </div>

          <div class="jm-qwen-actions">
            ${needs ? '<button type="button" id="jm-qwen-continue">Continuar generación</button>' : ''}
            <button type="button" id="jm-qwen-copy-md">Copiar Markdown</button>
            <button type="button" class="secondary" id="jm-qwen-copy-json">Copiar JSON</button>
          </div>
        </div>
      </div>
    `;

    var mdBtn = document.getElementById("jm-qwen-copy-md");
    var jsonBtn = document.getElementById("jm-qwen-copy-json");
    var continueBtn = document.getElementById("jm-qwen-continue");

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

    if (continueBtn) {
      continueBtn.onclick = function () {
        var next = {};
        Object.keys(lastRequestPayload || {}).forEach(function (k) {
          next[k] = lastRequestPayload[k];
        });

        next.model = MODEL;
        next.continue_generation = true;
        next.previous_raw = lastRawResponse || JSON.stringify(syl, null, 2);
        next.max_tokens = 7200;
        next.num_ctx = 8192;
        next.render_mode = "syllabus_qwen_curricular_v4";

        setProgress(3, "Continuando generación", "Reconstruyendo el sílabo completo con Qwen.");

        fetch("/api/assistant/generate-syllabus-stream", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(next)
        });
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
    } catch (e) {}

    if (eventName === "progress" && data) {
      setProgress(data.percent, data.stage, data.message);
      return;
    }

    if (eventName === "config" && data) {
      setProgress(10, "Configuración", data.message || "Configurando generación curricular.");
      return;
    }

    if ((eventName === "syllabus" || eventName === "final") && data) {
      lastRawResponse = data.raw_response || data.response || data.answer || lastRawResponse;
      var syl = data.syllabus || extractJson(data.raw_response) || extractJson(data.response) || extractJson(data.answer);
      var md = data.markdown || data.answer || data.response || "";
      renderSyllabus(syl, md, data);

      if (eventName === "final" && !data.needs_continue) {
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
    if (!window.fetch || window.fetch.__jmQwenSylV4) return;

    var originalFetch = window.fetch;

    window.fetch = function (input, init) {
      if (!isSyllabusUrl(input)) {
        return originalFetch.apply(this, arguments);
      }

      ensureUi();
      setProgress(2, "Inicio", "Enviando solicitud al generador curricular Qwen.");

      var opts = {};
      init = init || {};
      Object.keys(init).forEach(function (k) { opts[k] = init[k]; });

      try {
        if (typeof opts.body === "string" && opts.body.trim().charAt(0) === "{") {
          var payload = JSON.parse(opts.body);
          payload.model = MODEL;
          payload.max_tokens = payload.max_tokens || 7200;
          payload.num_ctx = payload.num_ctx || 8192;
          payload.temperature = payload.temperature || 0.28;
          payload.top_p = payload.top_p || 0.86;
          payload.render_mode = "syllabus_qwen_curricular_v4";
          lastRequestPayload = payload;
          opts.body = JSON.stringify(payload);
        }
      } catch (e) {}

      return originalFetch.call(this, input, opts).then(function (resp) {
        if (!resp.body || !resp.body.tee) {
          resp.clone().text().then(function (text) {
            parseSseBuffer(text + "\n\n", handleEvent);
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
              parseSseBuffer(buffer + "\n\n", handleEvent);
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

    window.fetch.__jmQwenSylV4 = true;
  }

  function init() {
    ensureUi();
    patchFetch();
    console.log("[JoMelAi] Qwen syllabus curricular v4 activo. Modelo:", MODEL);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
JS

# Shims para eliminar 404 del index actual.
cat > public/jomelai-syllabus-pretty-v7-live.js <<'JS'
(function(){console.log("[JoMelAi] jomelai-syllabus-pretty-v7-live compatibility activo");window.JOMELAI_SYLLABUS_PRETTY_READY=true;})();
JS

cat > public/chat-lateral-v2-client.js <<'JS'
(function(){console.log("[JoMelAi] chat-lateral-v2-client compatibility activo");window.JOMELAI_CHAT_LATERAL_READY=true;})();
JS

cat > public/chat-panel-renderer-final.js <<'JS'
(function(){console.log("[JoMelAi] chat-panel-renderer-final compatibility activo");window.JOMELAI_CHAT_PANEL_RENDERER_READY=true;})();
JS

cat > public/chat-pie-image-override.js <<'JS'
(function(){console.log("[JoMelAi] chat-pie-image-override compatibility activo");window.JOMELAI_CHAT_PIE_OVERRIDE_READY=true;})();
JS

for f in \
  jomelai-syllabus-qwen-v4.js \
  jomelai-syllabus-pretty-v7-live.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js
do
  cp "public/$f" "./$f"
done

# Copiar tambien a carpetas public internas comunes para que sobreviva build.
for d in ./frontend/public ./front/public ./client/public ./app/public ./web/public; do
  if [ -d "$d" ]; then
    echo "sincronizando assets en $d"
    cp public/jomelai-syllabus-qwen-v4.js "$d/jomelai-syllabus-qwen-v4.js" || true
    cp public/jomelai-syllabus-pretty-v7-live.js "$d/jomelai-syllabus-pretty-v7-live.js" || true
    cp public/chat-lateral-v2-client.js "$d/chat-lateral-v2-client.js" || true
    cp public/chat-panel-renderer-final.js "$d/chat-panel-renderer-final.js" || true
    cp public/chat-pie-image-override.js "$d/chat-pie-image-override.js" || true
  fi
done

echo
echo "== 7) Inyectando JS Qwen V4 en index.html locales =="

python3 <<'PY'
from pathlib import Path
import re

files = [
    Path("index.html"),
    Path("public/index.html"),
    Path("dist/index.html"),
    Path("build/index.html"),
    Path("frontend/index.html"),
    Path("frontend/dist/index.html"),
    Path("frontend/public/index.html"),
    Path("client/index.html"),
    Path("client/dist/index.html"),
]

script = "jomelai-syllabus-qwen-v4.js"
tag = f'  <script src="/{script}?v=qwen-curricular-v4"></script>'

for p in files:
    if not p.exists():
        continue

    text = p.read_text(encoding="utf-8", errors="ignore")
    text = re.sub(
        r'\s*<script[^>]+src=["\']/?' + re.escape(script) + r'(?:\?[^"\']*)?["\'][^>]*></script>',
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
echo "== 8) Rebuild/restart sin borrar volumenes =="
docker compose up -d --build

sleep 8

echo
echo "== 9) Copiando PHP y JS al runtime activo para garantizar que no corra version vieja =="

BACKEND_CONTAINER=""
for svc in backend api php laravel app server; do
  cid="$(docker compose ps -q "$svc" 2>/dev/null | head -1 || true)"
  if [ -n "$cid" ]; then
    name="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##' || true)"
    if [ -n "$name" ]; then
      BACKEND_CONTAINER="$name"
      break
    fi
  fi
done

if [ -z "$BACKEND_CONTAINER" ]; then
  BACKEND_CONTAINER="$(docker ps --format '{{.Names}} {{.Image}}' \
    | grep -Ei 'backend|laravel|php|apache|nginx' \
    | grep -vi 'frontend' \
    | head -1 \
    | awk '{print $1}' || true)"
fi

if [ -n "$BACKEND_CONTAINER" ]; then
  echo "BACKEND_CONTAINER=$BACKEND_CONTAINER"

  RUNTIME_PHP_LIST="$(docker exec "$BACKEND_CONTAINER" sh -lc "
    for d in /var/www/html /app /srv/app /var/www /usr/share/nginx/html; do
      [ -d \"\$d\" ] && grep -Rsl 'function jm_handle_syllabus_stream' \"\$d\" 2>/dev/null || true
    done
  " || true)"

  if [ -n "$RUNTIME_PHP_LIST" ]; then
    echo "$RUNTIME_PHP_LIST" | while read runtime_php; do
      [ -n "$runtime_php" ] || continue
      echo "copiando PHP runtime: $runtime_php"
      docker cp "$PHP_FILE" "$BACKEND_CONTAINER:$runtime_php"
      runtime_dir="$(dirname "$runtime_php")"
      docker cp .env "$BACKEND_CONTAINER:$runtime_dir/.env" || true
    done
  else
    echo "WARN: no encontre PHP runtime dentro del backend."
  fi
else
  echo "WARN: no detecte backend container."
fi

FRONT_CONTAINER=""
for svc in frontend front web nginx client; do
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
    jomelai-syllabus-qwen-v4.js \
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

script = "jomelai-syllabus-qwen-v4.js"
tag = f'  <script src="/{script}?v=qwen-curricular-v4"></script>'

text = re.sub(
    r'\s*<script[^>]+src=["\']/?' + re.escape(script) + r'(?:\?[^"\']*)?["\'][^>]*></script>',
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
  echo "WARN: no detecte frontend container."
fi

echo
echo "== 10) Verificando HTTP y endpoint =="

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

echo "APP_PORT=$APP_PORT"

for f in \
  jomelai-syllabus-qwen-v4.js \
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
echo "---- endpoint model/config ----"
curl -sS -N -m 220 -X POST "http://localhost:${APP_PORT}/api/assistant/generate-syllabus-stream" \
  -H "Content-Type: application/json" \
  -d '{
    "course": "Cálculo 2",
    "program": "Ingeniería Civil",
    "credits": "4",
    "cycle": "3",
    "weeks": "16",
    "modality": "Presencial",
    "graduate_profile": "Modela, analiza y resuelve problemas de ingeniería civil con fundamentos matemáticos, criterios técnicos y comunicación rigurosa.",
    "competency": "Aplica métodos del cálculo integral y sus extensiones para modelar, resolver e interpretar problemas de acumulación, áreas, volúmenes, trabajo y comportamiento de sistemas en contextos de ingeniería civil.",
    "sessions_per_week": "1"
  }' | grep -E "model_resolved|config|syllabus_qwen_curricular_v4|qwen_curricular_traceability_continue_v4|num_ctx|num_predict|needs_continue|quality_issues|parse_ok" | head -80 || true

echo
echo
echo "== 11) Git status =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Debe aparecer en el stream:"
echo "  render_mode: syllabus_qwen_curricular_v4"
echo "  strategy: qwen_curricular_traceability_continue_v4"
echo "  model: $TARGET_MODEL"
echo "  num_ctx: 8192"
echo "  num_predict: 7200"
echo
echo "Debe desaparecer el stream viejo:"
echo "  syllabus_pretty_dynamic"
echo "  semantic_discipline_inference_no_static_rules"
echo "  num_predict: 3200"
echo
echo "En navegador:"
echo "  Ctrl + Shift + R"
echo
echo "En consola debe salir:"
echo "  [JoMelAi] Qwen syllabus curricular v4 activo"
echo
echo "Si parse_ok=false o hay baja calidad, ahora debe salir boton:"
echo "  Continuar generacion"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
