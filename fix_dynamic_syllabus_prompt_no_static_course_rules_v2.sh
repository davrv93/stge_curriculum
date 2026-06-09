#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"

echo "=================================================="
echo " Fix dynamic syllabus prompt V2 - no static rules"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: ejecuta este script desde la carpeta donde esta docker-compose.yml o compose.yml"
  exit 1
fi

TARGET_MODEL="${1:-llama3.2:1b}"
BACKUP_DIR="backups/fix_dynamic_syllabus_prompt_v2_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "TARGET_MODEL=$TARGET_MODEL"
echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Buscando PHP real, excluyendo exports/backups =="

PHP_FILE="${PHP_FILE_OVERRIDE:-}"

if [ -z "$PHP_FILE" ]; then
  CANDIDATES=""

  while IFS= read -r f; do
    if grep -q "function jm_handle_syllabus_stream" "$f" 2>/dev/null; then
      CANDIDATES="${CANDIDATES}${f}
"
    fi
  done < <(find . \
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
    2>/dev/null)

  echo "Candidatos encontrados:"
  printf "%s\n" "$CANDIDATES" | sed '/^$/d' | nl -ba || true

  for preferred in \
    "./public/jomelai_stream_routes.php" \
    "./backend/public/jomelai_stream_routes.php" \
    "./docker_backend_public/jomelai_stream_routes.php" \
    "./jomelai_stream_routes.php"
  do
    if printf "%s\n" "$CANDIDATES" | grep -Fxq "$preferred"; then
      PHP_FILE="$preferred"
      break
    fi
  done

  if [ -z "$PHP_FILE" ]; then
    PHP_FILE="$(printf "%s\n" "$CANDIDATES" | sed '/^$/d' | head -1 || true)"
  fi
fi

if [ -z "$PHP_FILE" ] || [ ! -f "$PHP_FILE" ]; then
  echo "ERROR: no encontre el PHP real con jm_handle_syllabus_stream."
  echo
  echo "Puedes forzarlo asi:"
  echo "  PHP_FILE_OVERRIDE=./ruta/real/jomelai_stream_routes.php ./fix_dynamic_syllabus_prompt_no_static_course_rules_v2.sh"
  exit 1
fi

echo "PHP_FILE=$PHP_FILE"

if echo "$PHP_FILE" | grep -qE 'sync_docker_to_host_|_docker_runtime_export|backups/'; then
  echo "ERROR: el archivo detectado parece export/backup, no fuente real:"
  echo "  $PHP_FILE"
  echo "Usa PHP_FILE_OVERRIDE con la ruta real del proyecto."
  exit 1
fi

mkdir -p "$BACKUP_DIR/$(dirname "$PHP_FILE")"
cp "$PHP_FILE" "$BACKUP_DIR/$PHP_FILE.bak" 2>/dev/null || cp "$PHP_FILE" "$BACKUP_DIR/$(basename "$PHP_FILE").bak"

echo
echo "== 2) Reemplazando jm_handle_syllabus_stream por version dinamica =="

python3 - "$PHP_FILE" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

# Quitar versiones anteriores de helpers nuestros.
for block in [
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
/* JOMELAI_DYNAMIC_SYLLABUS_V2_START */

function jm_dyn_syl_read_dotenv_value($key)
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

function jm_dyn_syl_env($key, $default = '')
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

    $dotenv = jm_dyn_syl_read_dotenv_value($key);

    if ($dotenv !== null && $dotenv !== '') {
        return $dotenv;
    }

    return $default;
}

function jm_dyn_syl_bool($key, $default = false)
{
    $raw = strtolower(trim((string)jm_dyn_syl_env($key, $default ? '1' : '0')));

    return in_array($raw, ['1', 'true', 'yes', 'si', 'sí', 'on'], true);
}

function jm_dyn_syl_model($requestModel = '')
{
    $requestModel = trim((string)$requestModel);
    $envModel = trim((string)jm_dyn_syl_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'));
    $allowOverride = jm_dyn_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false);

    if ($allowOverride && $requestModel !== '') {
        return $requestModel;
    }

    if ($envModel !== '') {
        return $envModel;
    }

    return 'llama3.2:1b';
}

function jm_dyn_syl_text($value)
{
    if ($value === null) {
        return '';
    }

    if (is_array($value)) {
        return trim(json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    return trim((string)$value);
}

function jm_dyn_syl_list($value)
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

function jm_dyn_syl_extract_json($text)
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

function jm_dyn_syl_contains_bad_fillers($text)
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

function jm_dyn_syl_to_markdown($syl, $raw = '')
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
        if (isset($dg[$key]) && jm_dyn_syl_text($dg[$key]) !== '') {
            $lines[] = '| ' . $label . ' | ' . jm_dyn_syl_text($dg[$key]) . ' |';
        }
    }

    $lines[] = '';
    $lines[] = '## II. Sumilla';
    $lines[] = '';
    $lines[] = jm_dyn_syl_text($syl['sumilla'] ?? '');

    $lines[] = '';
    $lines[] = '## III. Competencia del curso';
    $lines[] = '';
    $lines[] = jm_dyn_syl_text($syl['competencia_curso'] ?? '');

    $lines[] = '';
    $lines[] = '## IV. Resultados de aprendizaje';
    $lines[] = '';

    foreach (jm_dyn_syl_list($syl['resultados_curso'] ?? []) as $i => $item) {
        $lines[] = ($i + 1) . '. ' . jm_dyn_syl_text($item);
    }

    $lines[] = '';
    $lines[] = '## V. Organización de unidades';

    foreach (jm_dyn_syl_list($syl['unidades'] ?? []) as $unit) {
        if (!is_array($unit)) {
            continue;
        }

        $unidad = jm_dyn_syl_text($unit['unidad'] ?? '');
        $titulo = jm_dyn_syl_text($unit['titulo'] ?? '');

        $lines[] = '';
        $lines[] = '### Unidad ' . $unidad . ': ' . $titulo;
        $lines[] = '';

        if (isset($unit['semanas'])) {
            $semanas = is_array($unit['semanas']) ? implode(', ', $unit['semanas']) : jm_dyn_syl_text($unit['semanas']);
            $lines[] = '- **Semanas:** ' . $semanas;
        }

        if (!empty($unit['resultado_unidad'])) {
            $lines[] = '- **Resultado de unidad:** ' . jm_dyn_syl_text($unit['resultado_unidad']);
        }

        $contenidos = jm_dyn_syl_list($unit['contenidos'] ?? []);
        if ($contenidos) {
            $lines[] = '- **Contenidos:**';
            foreach ($contenidos as $c) {
                $lines[] = '  - ' . jm_dyn_syl_text($c);
            }
        }

        $sesiones = jm_dyn_syl_list($unit['sesiones'] ?? []);
        if ($sesiones) {
            $lines[] = '';
            $lines[] = '| Semana | Sesión | Tema | Actividad | Producto |';
            $lines[] = '|---:|---:|---|---|---|';

            foreach ($sesiones as $ses) {
                if (!is_array($ses)) {
                    continue;
                }

                $lines[] =
                    '| ' . jm_dyn_syl_text($ses['semana'] ?? '') .
                    ' | ' . jm_dyn_syl_text($ses['sesion'] ?? '') .
                    ' | ' . jm_dyn_syl_text($ses['titulo'] ?? '') .
                    ' | ' . jm_dyn_syl_text($ses['actividad_aprendizaje'] ?? '') .
                    ' | ' . jm_dyn_syl_text($ses['producto'] ?? '') .
                    ' |';
            }
        }

        if (!empty($unit['producto_unidad'])) {
            $lines[] = '';
            $lines[] = '- **Producto integrador:** ' . jm_dyn_syl_text($unit['producto_unidad']);
        }
    }

    $lines[] = '';
    $lines[] = '## VI. Evaluación';
    $lines[] = '';
    $lines[] = '| Tipo | Descripción | Evidencia | Semana | Puntaje |';
    $lines[] = '|---|---|---|---:|---:|';

    foreach (jm_dyn_syl_list($syl['evaluaciones'] ?? []) as $ev) {
        if (!is_array($ev)) {
            continue;
        }

        $lines[] =
            '| ' . jm_dyn_syl_text($ev['tipo'] ?? '') .
            ' | ' . jm_dyn_syl_text($ev['descripcion'] ?? '') .
            ' | ' . jm_dyn_syl_text($ev['evidencia'] ?? '') .
            ' | ' . jm_dyn_syl_text($ev['semana'] ?? '') .
            ' | ' . jm_dyn_syl_text($ev['puntaje_vigesimal'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## VII. Estrategias metodológicas';
    $lines[] = '';

    foreach (jm_dyn_syl_list($syl['metodologias'] ?? []) as $m) {
        $lines[] = '- ' . jm_dyn_syl_text($m);
    }

    $lines[] = '';
    $lines[] = '## VIII. Referencias';
    $lines[] = '';

    foreach (jm_dyn_syl_list($syl['referencias'] ?? []) as $ref) {
        if (is_array($ref)) {
            $lines[] = '- ' . jm_dyn_syl_text($ref['autor'] ?? '') . ' (' . jm_dyn_syl_text($ref['anio'] ?? '') . '). ' . jm_dyn_syl_text($ref['titulo'] ?? '') . '. ' . jm_dyn_syl_text($ref['fuente'] ?? '') . '. ' . jm_dyn_syl_text($ref['url'] ?? '');
        } else {
            $lines[] = '- ' . jm_dyn_syl_text($ref);
        }
    }

    $lines[] = '';
    $lines[] = '## IX. Recursos y enlaces';
    $lines[] = '';

    foreach (jm_dyn_syl_list($syl['enlaces'] ?? []) as $en) {
        if (is_array($en)) {
            $lines[] = '- ' . jm_dyn_syl_text($en['titulo'] ?? '') . ': ' . jm_dyn_syl_text($en['url'] ?? '') . ' — ' . jm_dyn_syl_text($en['uso'] ?? '');
        }
    }

    return trim(implode("\n", $lines));
}

function jm_dyn_syl_generate($model, $prompt, $options, $onToken)
{
    if (function_exists('jm_syllabus_llm_stream_generate') && jm_dyn_syl_bool('LLM_REMOTE_ENABLED', false)) {
        return jm_syllabus_llm_stream_generate($model, $prompt, $options, $onToken);
    }

    return jm_ollama_stream_generate($model, $prompt, $options, $onToken);
}

/* JOMELAI_DYNAMIC_SYLLABUS_V2_END */
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
    $model = jm_dyn_syl_model($requestModel);

    $program = trim((string)($data['program'] ?? $data['programa'] ?? $data['programa_estudio'] ?? ''));
    $credits = trim((string)($data['credits'] ?? $data['creditos'] ?? ''));
    $cycle = trim((string)($data['cycle'] ?? $data['ciclo'] ?? ''));
    $weeks = max(4, min((int)($data['weeks'] ?? $data['semanas'] ?? 16), 24));
    $modality = trim((string)($data['modality'] ?? $data['modalidad'] ?? 'Presencial'));
    $profile = trim((string)($data['graduate_profile'] ?? $data['perfil_egreso'] ?? ''));
    $competency = trim((string)($data['competency'] ?? $data['competencia'] ?? ''));
    $startDate = trim((string)($data['start_date'] ?? $data['fecha_inicio'] ?? ''));
    $sessionsPerWeek = max(1, min((int)($data['sessions_per_week'] ?? $data['sesiones_por_semana'] ?? 1), 4));

    $numCtx = (int)($data['num_ctx'] ?? jm_dyn_syl_env('SYLLABUS_NUM_CTX', '4096'));
    $numCtx = max(2048, min($numCtx, 8192));

    $numPredict = (int)($data['max_tokens'] ?? $data['num_predict'] ?? jm_dyn_syl_env('SYLLABUS_NUM_PREDICT', '3200'));
    $numPredict = max(1800, min($numPredict, 6000));

    $temperature = (float)($data['temperature'] ?? jm_dyn_syl_env('SYLLABUS_TEMPERATURE', '0.34'));
    $temperature = max(0.10, min($temperature, 0.65));

    $topP = (float)($data['top_p'] ?? jm_dyn_syl_env('SYLLABUS_TOP_P', '0.90'));
    $topP = max(0.70, min($topP, 0.95));

    $numThread = (int)jm_dyn_syl_env('SYLLABUS_NUM_THREAD', '2');
    $numThread = max(1, min($numThread, 8));

    $tokensConfig = [
        'model' => $model,
        'model_env' => jm_dyn_syl_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_dyn_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'num_ctx' => $numCtx,
        'num_predict' => $numPredict,
        'temperature' => $temperature,
        'top_p' => $topP,
        'num_thread' => $numThread,
        'stream' => true,
        'render_mode' => 'syllabus_pretty_dynamic',
        'strategy' => 'semantic_discipline_inference_no_static_rules',
    ];

    $profilePrompt = $profile !== ''
        ? "Perfil de egreso seleccionado o escrito por el usuario: {$profile}\n"
        : "Perfil de egreso no especificado; infiere una articulacion razonable con el programa sin inventar datos institucionales.\n";

    $competencyPrompt = $competency !== ''
        ? "Competencia seleccionada o escrita por el usuario: {$competency}\n"
        : "Competencia no especificada; formula una competencia de curso observable y evaluable.\n";

    $disciplineInstruction =
        "INFERENCIA DISCIPLINAR DINAMICA:\n" .
        "No uses reglas hardcodeadas por nombre de curso. No uses condiciones del tipo: si el curso contiene una palabra, entonces usar una lista fija de temas.\n" .
        "Analiza semanticamente el nombre exacto del curso, el programa, el ciclo, los creditos, el perfil de egreso y la competencia declarada.\n" .
        "Antes de redactar, identifica internamente: campo disciplinar, subcampo, prerrequisitos probables, progresion logica, habilidades esperadas, aplicaciones profesionales y productos evaluables.\n" .
        "No escribas ese analisis interno; usalo solo para construir el silabo.\n" .
        "Si el curso es ambiguo, desambigua usando programa, ciclo, perfil y competencia.\n" .
        "Cada unidad, sesion, actividad, producto, evaluacion y referencia debe corresponder al curso solicitado, no a otro campo.\n";

    $prompt =
        "Eres JoMelAI Curriculista universitario. Genera un silabo con contenido academico real, especifico y util.\n" .
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

        "REGLAS CRITICAS DE CALIDAD:\n" .
        "1. Prohibido usar textos de relleno, plantillas visibles o placeholders.\n" .
        "2. Prohibido escribir frases como: resultado de aprendizaje real, contenido real, tema real, actividad concreta, producto o evidencia, criterio real, producto integrador real, semana o fecha, fecha o semana sugerida.\n" .
        "3. No uses nombres de autores ficticios, editoriales falsas ni URLs inventadas.\n" .
        "4. Cada unidad debe tener contenidos disciplinares concretos del curso solicitado, con progresion de menor a mayor complejidad.\n" .
        "5. Cada sesion debe tener un tema academico especifico, actividad aplicable y producto verificable.\n" .
        "6. Las evaluaciones deben medir desempeno real con criterios observables.\n" .
        "7. Si no conoces una URL exacta de referencia o recurso, deja url como cadena vacia.\n" .
        "8. Si el usuario dio perfil de egreso y competencia, articula todo el silabo con esos textos.\n" .
        "9. Usa espanol academico claro, especifico y contextualizado.\n\n" .

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
        "  \"resultados_curso\": [string,string,string,string],\n" .
        "  \"unidades\": [\n" .
        "    {\n" .
        "      \"unidad\": number,\n" .
        "      \"titulo\": string,\n" .
        "      \"semanas\": [number],\n" .
        "      \"resultado_unidad\": string,\n" .
        "      \"contenidos\": [string,string,string,string],\n" .
        "      \"sesiones\": [\n" .
        "        {\n" .
        "          \"semana\": number,\n" .
        "          \"sesion\": number,\n" .
        "          \"titulo\": string,\n" .
        "          \"resultado_sesion\": string,\n" .
        "          \"contenidos\": [string,string],\n" .
        "          \"actividad_aprendizaje\": string,\n" .
        "          \"producto\": string,\n" .
        "          \"fecha_sugerida\": string\n" .
        "        }\n" .
        "      ],\n" .
        "      \"producto_unidad\": string,\n" .
        "      \"evaluacion_producto_unidad\": {\n" .
        "        \"descripcion\": string,\n" .
        "        \"criterios\": [string,string,string],\n" .
        "        \"puntaje_vigesimal\": 20,\n" .
        "        \"fecha_sugerida\": string\n" .
        "      }\n" .
        "    }\n" .
        "  ],\n" .
        "  \"evaluaciones\": [\n" .
        "    {\n" .
        "      \"tipo\": string,\n" .
        "      \"descripcion\": string,\n" .
        "      \"evidencia\": string,\n" .
        "      \"criterios\": [string,string,string],\n" .
        "      \"puntaje_vigesimal\": 20,\n" .
        "      \"semana\": number,\n" .
        "      \"fecha_sugerida\": string\n" .
        "    }\n" .
        "  ],\n" .
        "  \"metodologias\": [string,string,string,string,string],\n" .
        "  \"referencias\": [\n" .
        "    {\"autor\": string, \"anio\": string, \"titulo\": string, \"fuente\": string, \"url\": string, \"utilidad\": string}\n" .
        "  ],\n" .
        "  \"enlaces\": [\n" .
        "    {\"titulo\": string, \"url\": string, \"uso\": string}\n" .
        "  ]\n" .
        "}\n\n" .

        "CANTIDAD:\n" .
        "- Genera exactamente 4 unidades.\n" .
        "- En cada unidad genera 2 sesiones representativas como minimo.\n" .
        "- Genera exactamente 4 resultados de curso.\n" .
        "- Genera al menos 4 evaluaciones.\n" .
        "- Genera 5 metodologias.\n" .
        "- Genera 4 referencias academicas.\n" .
        "- Genera 3 enlaces o recursos, sin URLs falsas.\n\n" .

        "Genera ahora el JSON final con contenido real, dinamico y coherente.";

    jm_sse_start();

    jm_sse_send('model_resolved', [
        'ok' => true,
        'provider' => jm_dyn_syl_bool('LLM_REMOTE_ENABLED', false) ? 'remote_llm' : 'ollama_local',
        'model' => $model,
        'model_env' => jm_dyn_syl_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_dyn_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'render_mode' => 'syllabus_pretty_dynamic',
    ]);

    jm_sse_send('config', [
        'ok' => true,
        'tokens_config' => $tokensConfig,
        'message' => "Generando silabo academico dinamico con {$model}.",
        'render_mode' => 'syllabus_pretty_dynamic',
    ]);

    $answer = '';

    try {
        $answer = jm_dyn_syl_generate(
            $model,
            $prompt,
            [
                'temperature' => $temperature,
                'top_p' => $topP,
                'repeat_penalty' => 1.12,
                'num_ctx' => $numCtx,
                'num_predict' => $numPredict,
                'num_thread' => $numThread,
            ],
            function ($piece) {
                jm_sse_send('token', ['text' => $piece]);
            }
        );

        if (jm_dyn_syl_contains_bad_fillers($answer) && jm_dyn_syl_bool('SYLLABUS_QUALITY_REPAIR', true)) {
            jm_sse_send('quality_repair', [
                'ok' => true,
                'message' => 'Se detecto relleno. Reescribiendo con inferencia disciplinar dinamica.',
            ]);

            $repairPrompt =
                "Reescribe el siguiente JSON de silabo conservando exactamente la estructura JSON.\n" .
                "Elimina todo relleno, placeholder, autores ficticios y URLs inventadas.\n" .
                "No uses reglas hardcodeadas por nombre de curso.\n" .
                "Infiere semanticamente la disciplina con estos datos:\n" .
                "Curso: {$course}\n" .
                "Programa: {$program}\n" .
                "Creditos: {$credits}\n" .
                "Ciclo: {$cycle}\n" .
                "Semanas: {$weeks}\n" .
                $profilePrompt .
                $competencyPrompt .
                $disciplineInstruction .
                "\nJSON defectuoso:\n" .
                $answer .
                "\n\nDevuelve SOLO JSON valido corregido.";

            $answer = jm_dyn_syl_generate(
                $model,
                $repairPrompt,
                [
                    'temperature' => max(0.18, min($temperature, 0.40)),
                    'top_p' => $topP,
                    'repeat_penalty' => 1.15,
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

    $syllabus = jm_dyn_syl_extract_json($answer);
    $parseOk = is_array($syllabus);
    $markdown = $parseOk ? jm_dyn_syl_to_markdown($syllabus, $answer) : $answer;

    jm_sse_send('syllabus', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'parse_ok' => $parseOk,
        'render_mode' => 'syllabus_pretty_dynamic',
        'syllabus' => $syllabus,
        'markdown' => $markdown,
        'raw_response' => $answer,
        'tokens_config' => $tokensConfig,
    ]);

    jm_sse_send('final', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'model' => $model,
        'parse_ok' => $parseOk,
        'render_mode' => 'syllabus_pretty_dynamic',
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
echo "== 3) Verificando que NO exista logica estatica por curso =="
if grep -n "courseLower\|domainHint\|strpos(\$courseLower" "$PHP_FILE"; then
  echo "ERROR: aun existe logica estatica por curso."
  exit 1
else
  echo "OK: no se detecto courseLower/domainHint/strpos(courseLower)."
fi

echo
echo "== 4) Validando PHP =="
if command -v php >/dev/null 2>&1; then
  php -l "$PHP_FILE"
else
  echo "PHP no esta instalado en host; se validara en runtime."
fi

echo
echo "== 5) Actualizando .env =="
touch .env
cp .env "$BACKUP_DIR/.env.bak"

set_env() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s#^${key}=.*#${key}=${value}#g" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_env "SYLLABUS_OLLAMA_MODEL" "$TARGET_MODEL"
set_env "SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE" "0"
set_env "SYLLABUS_QUALITY_REPAIR" "1"
set_env "SYLLABUS_NUM_CTX" "4096"
set_env "SYLLABUS_NUM_PREDICT" "3200"
set_env "SYLLABUS_TEMPERATURE" "0.34"
set_env "SYLLABUS_TOP_P" "0.90"
set_env "SYLLABUS_NUM_THREAD" "2"
set_env "SYLLABUS_KEEP_ALIVE" "30m"

PHP_DIR="$(dirname "$PHP_FILE")"
if [ "$PHP_DIR" != "." ]; then
  cp .env "$PHP_DIR/.env" || true
fi

echo
echo "== 6) Rebuild/restart sin borrar volumenes =="
docker compose up -d --build

sleep 6

echo
echo "== 7) Test rapido =="
APP_PORT="$(grep -E '^APP_PORT=' .env 2>/dev/null | tail -1 | cut -d= -f2- || true)"
APP_PORT="${APP_PORT:-3000}"

time curl -sS -N -m 260 -X POST "http://localhost:${APP_PORT}/api/assistant/generate-syllabus-stream" \
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
    "start_date": "",
    "sessions_per_week": "1"
  }' | grep -E "model_resolved|config|quality_repair|semantic_discipline|contenido real|resultado de aprendizaje real|tema real|Juan|teoria de los numeros|teoría de los números|deriv|limite|límite|funcion|función|optimiz" | head -100 || true

echo
echo
echo "== 8) Git status =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "PHP corregido:"
echo "  $PHP_FILE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Ya no usa:"
echo "  courseLower"
echo "  domainHint"
echo "  strpos(\$courseLower, ...)"
echo
echo "Estrategia actual:"
echo "  semantic_discipline_inference_no_static_rules"
echo
echo "Si el detector encuentra relleno, dispara:"
echo "  event: quality_repair"
