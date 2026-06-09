#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"
TARGET_MODEL="${1:-qwen2.5:3b}"

echo "=================================================="
echo " Fix syllabus institutional guide + friendly UI + Qwen"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "TARGET_MODEL=$TARGET_MODEL"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: ejecuta este script desde la carpeta donde esta docker-compose.yml o compose.yml"
  exit 1
fi

BACKUP_DIR="backups/fix_syllabus_institutional_guide_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
mkdir -p public

echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Verificando modelo Qwen =="

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
  echo "WARN: no detecte contenedor Ollama. En local ejecuta manualmente:"
  echo "  ollama pull $TARGET_MODEL"
fi

echo
echo "== 2) Localizando archivos PHP fuente con jm_handle_syllabus_stream =="

mapfile -t PHP_FILES < <(find . \
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
  2>/dev/null || true)

if [ "${#PHP_FILES[@]}" -eq 0 ]; then
  echo "ERROR: no encontre ningun PHP con jm_handle_syllabus_stream."
  exit 1
fi

printf "%s\n" "${PHP_FILES[@]}" | nl -ba

echo
echo "== 3) Parchando endpoint con guia institucional de silabos =="

patch_php_file() {
  local PHP_FILE="$1"

  echo "Parchando: $PHP_FILE"
  mkdir -p "$BACKUP_DIR/$(dirname "$PHP_FILE")"
  cp "$PHP_FILE" "$BACKUP_DIR/$PHP_FILE.bak" 2>/dev/null || cp "$PHP_FILE" "$BACKUP_DIR/$(basename "$PHP_FILE").bak"

  python3 - "$PHP_FILE" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8", errors="ignore")

for block in [
    "JOMELAI_INST_SYLLABUS_V5",
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
/* JOMELAI_INST_SYLLABUS_V5_START */

function jm_inst_syl_read_dotenv_value($key)
{
    $key = trim((string)$key);
    if ($key === '') return null;

    $dirs = [];
    $dir = __DIR__;

    for ($i = 0; $i < 10; $i++) {
        if (!$dir || $dir === '/' || in_array($dir, $dirs, true)) break;
        $dirs[] = $dir;
        $parent = dirname($dir);
        if ($parent === $dir) break;
        $dir = $parent;
    }

    foreach ($dirs as $d) {
        $file = rtrim($d, '/') . '/.env';
        if (!is_file($file) || !is_readable($file)) continue;

        $lines = @file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if (!is_array($lines)) continue;

        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || strpos($line, '#') === 0 || strpos($line, '=') === false) continue;

            list($k, $v) = explode('=', $line, 2);
            if (trim($k) === $key) return trim(trim($v), "\"'");
        }
    }

    return null;
}

function jm_inst_syl_env($key, $default = '')
{
    $value = getenv($key);
    if ($value !== false && $value !== '') return $value;
    if (isset($_ENV[$key]) && $_ENV[$key] !== '') return $_ENV[$key];
    if (isset($_SERVER[$key]) && $_SERVER[$key] !== '') return $_SERVER[$key];

    $dotenv = jm_inst_syl_read_dotenv_value($key);
    if ($dotenv !== null && $dotenv !== '') return $dotenv;

    return $default;
}

function jm_inst_syl_bool($key, $default = false)
{
    $raw = strtolower(trim((string)jm_inst_syl_env($key, $default ? '1' : '0')));
    return in_array($raw, ['1', 'true', 'yes', 'si', 'sí', 'on'], true);
}

function jm_inst_syl_model($requestModel = '')
{
    $requestModel = trim((string)$requestModel);
    $envModel = trim((string)jm_inst_syl_env('SYLLABUS_OLLAMA_MODEL', 'qwen2.5:3b'));
    $allowOverride = jm_inst_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false);

    if ($allowOverride && $requestModel !== '') return $requestModel;
    return $envModel !== '' ? $envModel : 'qwen2.5:3b';
}

function jm_inst_syl_text($value)
{
    if ($value === null) return '';
    if (is_array($value)) return trim(json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    return trim((string)$value);
}

function jm_inst_syl_list($value)
{
    if (is_array($value)) return $value;
    $value = trim((string)$value);
    if ($value === '') return [];
    return array_values(array_filter(array_map('trim', preg_split('/\n|;|\|/', $value))));
}

function jm_inst_syl_extract_json($text)
{
    $text = trim((string)$text);
    if ($text === '') return null;

    $decoded = json_decode($text, true);
    if (is_array($decoded)) return $decoded;

    $start = strpos($text, '{');
    $end = strrpos($text, '}');

    if ($start === false || $end === false || $end <= $start) return null;

    $candidate = substr($text, $start, $end - $start + 1);
    $decoded = json_decode($candidate, true);

    return is_array($decoded) ? $decoded : null;
}

function jm_inst_syl_bad_quality($raw)
{
    $markers = [
        'generando resultado',
        'generando producto',
        'resultado de aprendizaje real',
        'contenido real',
        'tema real',
        'actividad concreta',
        'producto o evidencia',
        'construyendo',
        'json inválido',
        'json invalido',
        'técnicas de numeración',
        'tecnicas de numeracion',
        'referencias académicas',
        'referencias academicas',
        'metodologías',
        'metodologias',
        'cálculo básico',
        'calculo basico',
        'cálculo simple',
        'calculo simple',
        'revisión de conceptos teóricos',
        'revision de conceptos teoricos',
        '"resultado_sesion": ""',
        'recursoenlinea.com',
        'juan perez',
        'juan pérez',
    ];

    $lower = function_exists('mb_strtolower')
        ? mb_strtolower((string)$raw, 'UTF-8')
        : strtolower((string)$raw);

    foreach ($markers as $m) {
        $needle = function_exists('mb_strtolower') ? mb_strtolower($m, 'UTF-8') : strtolower($m);
        if (strpos($lower, $needle) !== false) return true;
    }

    return false;
}

function jm_inst_syl_quality_issues($syl, $raw)
{
    $issues = [];

    if (!is_array($syl)) {
        $issues[] = 'La generación quedó incompleta y necesita completarse.';
        return $issues;
    }

    if (empty($syl['sumilla']) || empty($syl['competencia_curso'])) {
        $issues[] = 'Falta completar la sumilla o la competencia del curso.';
    }

    if (empty($syl['resultados_aprendizaje']) || !is_array($syl['resultados_aprendizaje']) || count($syl['resultados_aprendizaje']) < 3) {
        $issues[] = 'Falta completar los resultados de aprendizaje.';
    }

    if (empty($syl['unidades']) || !is_array($syl['unidades']) || count($syl['unidades']) !== 4) {
        $issues[] = 'Faltan las cuatro unidades formativas.';
    } else {
        foreach ($syl['unidades'] as $u) {
            if (!is_array($u)) continue;

            if (empty($u['resultado_aprendizaje_unidad']) || empty($u['producto_unidad']) || empty($u['sesiones'])) {
                $issues[] = 'Hay unidades sin resultado, producto o sesiones.';
            }

            if (!empty($u['titulo']) && preg_match('/referencias|metodolog|evaluaci[oó]n|bibliograf/i', jm_inst_syl_text($u['titulo']))) {
                $issues[] = 'Hay unidades con títulos administrativos en vez de ejes disciplinares.';
            }

            $sessions = isset($u['sesiones']) && is_array($u['sesiones']) ? $u['sesiones'] : [];
            if (count($sessions) < 3) {
                $issues[] = 'Hay unidades con pocas sesiones.';
            }

            foreach ($sessions as $s) {
                if (!is_array($s)) continue;
                if (empty($s['momentos']) || empty($s['resultado_sesion']) || empty($s['aporte_a_rau'])) {
                    $issues[] = 'Hay sesiones sin momentos pedagógicos o trazabilidad.';
                }
            }
        }
    }

    if (empty($syl['matriz_trazabilidad']) || !is_array($syl['matriz_trazabilidad'])) {
        $issues[] = 'Falta la matriz de trazabilidad académica.';
    }

    if (empty($syl['sistema_evaluacion']) || !is_array($syl['sistema_evaluacion'])) {
        $issues[] = 'Falta el sistema de evaluación C1, EP, C2 y EF.';
    }

    if (jm_inst_syl_bad_quality($raw)) {
        $issues[] = 'Se detectó contenido preliminar que requiere mejora curricular.';
    }

    return array_values(array_unique($issues));
}

function jm_inst_syl_to_markdown($syl, $raw = '')
{
    if (!is_array($syl)) return trim((string)$raw);

    $dg = isset($syl['datos_generales']) && is_array($syl['datos_generales']) ? $syl['datos_generales'] : [];

    $lines = [];
    $lines[] = '# Sílabo por competencias';
    $lines[] = '';
    $lines[] = '## I. Datos generales';
    $lines[] = '';
    $lines[] = '| Campo | Información |';
    $lines[] = '|---|---|';

    foreach ([
        'curso' => 'Curso',
        'programa' => 'Programa',
        'creditos' => 'Créditos',
        'ciclo' => 'Ciclo',
        'semanas' => 'Semanas',
        'sesiones_por_semana' => 'Sesiones por semana',
        'modalidad' => 'Modalidad',
        'area_curricular' => 'Área curricular',
        'naturaleza' => 'Naturaleza',
        'prerrequisito' => 'Prerrequisito',
    ] as $key => $label) {
        if (isset($dg[$key]) && jm_inst_syl_text($dg[$key]) !== '') {
            $lines[] = '| ' . $label . ' | ' . jm_inst_syl_text($dg[$key]) . ' |';
        }
    }

    $lines[] = '';
    $lines[] = '## II. Sumilla';
    $lines[] = '';
    $lines[] = jm_inst_syl_text($syl['sumilla'] ?? '');

    $lines[] = '';
    $lines[] = '## III. Competencia del curso';
    $lines[] = '';
    $lines[] = jm_inst_syl_text($syl['competencia_curso'] ?? '');

    $lines[] = '';
    $lines[] = '## IV. Resultados de aprendizaje';
    $lines[] = '';
    $lines[] = '| Código | Resultado | Nivel Bloom | Verbo | Evidencia |';
    $lines[] = '|---|---|---|---|---|';

    foreach (jm_inst_syl_list($syl['resultados_aprendizaje'] ?? []) as $ra) {
        if (!is_array($ra)) continue;
        $lines[] =
            '| ' . jm_inst_syl_text($ra['codigo'] ?? '') .
            ' | ' . jm_inst_syl_text($ra['redaccion'] ?? '') .
            ' | ' . jm_inst_syl_text($ra['nivel_bloom'] ?? '') .
            ' | ' . jm_inst_syl_text($ra['verbo_observable'] ?? '') .
            ' | ' . jm_inst_syl_text($ra['evidencia'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## V. Unidades y sesiones';

    foreach (jm_inst_syl_list($syl['unidades'] ?? []) as $u) {
        if (!is_array($u)) continue;

        $lines[] = '';
        $lines[] = '### Unidad ' . jm_inst_syl_text($u['numero'] ?? '') . ': ' . jm_inst_syl_text($u['titulo'] ?? '');
        $lines[] = '';
        $lines[] = '- **Semanas:** ' . jm_inst_syl_text($u['semanas'] ?? '');
        $lines[] = '- **RA vinculado:** ' . jm_inst_syl_text($u['ra_vinculado'] ?? '');
        $lines[] = '- **RAU:** ' . jm_inst_syl_text($u['resultado_aprendizaje_unidad'] ?? '');
        $lines[] = '- **Producto de unidad:** ' . jm_inst_syl_text($u['producto_unidad'] ?? '');
        $lines[] = '- **Metodología dominante:** ' . jm_inst_syl_text($u['metodologia_dominante'] ?? '');

        $lines[] = '';
        $lines[] = '| Semana | Sesión | Tema | Resultado de sesión | Antes | Inicio | Desarrollo | Cierre | Evidencia |';
        $lines[] = '|---:|---:|---|---|---|---|---|---|---|';

        foreach (jm_inst_syl_list($u['sesiones'] ?? []) as $s) {
            if (!is_array($s)) continue;
            $m = isset($s['momentos']) && is_array($s['momentos']) ? $s['momentos'] : [];
            $lines[] =
                '| ' . jm_inst_syl_text($s['semana'] ?? '') .
                ' | ' . jm_inst_syl_text($s['sesion'] ?? '') .
                ' | ' . jm_inst_syl_text($s['tema'] ?? '') .
                ' | ' . jm_inst_syl_text($s['resultado_sesion'] ?? '') .
                ' | ' . jm_inst_syl_text($m['antes_clase'] ?? '') .
                ' | ' . jm_inst_syl_text($m['inicio_clase'] ?? '') .
                ' | ' . jm_inst_syl_text($m['desarrollo'] ?? '') .
                ' | ' . jm_inst_syl_text($m['cierre'] ?? '') .
                ' | ' . jm_inst_syl_text($s['evidencia_sesion'] ?? '') .
                ' |';
        }
    }

    $lines[] = '';
    $lines[] = '## VI. Matriz de trazabilidad';
    $lines[] = '';
    $lines[] = '| RA | Unidad | Sesiones | Producto | Evaluación | Criterio |';
    $lines[] = '|---|---|---|---|---|---|';

    foreach (jm_inst_syl_list($syl['matriz_trazabilidad'] ?? []) as $t) {
        if (!is_array($t)) continue;
        $lines[] =
            '| ' . jm_inst_syl_text($t['ra'] ?? '') .
            ' | ' . jm_inst_syl_text($t['unidad'] ?? '') .
            ' | ' . jm_inst_syl_text($t['sesiones'] ?? '') .
            ' | ' . jm_inst_syl_text($t['producto'] ?? '') .
            ' | ' . jm_inst_syl_text($t['evaluacion'] ?? '') .
            ' | ' . jm_inst_syl_text($t['criterio_logro'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## VII. Sistema de evaluación';
    $lines[] = '';
    $lines[] = '| Código | Evaluación | Semana | Peso | Evidencia | Instrumento |';
    $lines[] = '|---|---|---|---:|---|---|';

    foreach (jm_inst_syl_list($syl['sistema_evaluacion'] ?? []) as $ev) {
        if (!is_array($ev)) continue;
        $lines[] =
            '| ' . jm_inst_syl_text($ev['codigo'] ?? '') .
            ' | ' . jm_inst_syl_text($ev['evaluacion'] ?? '') .
            ' | ' . jm_inst_syl_text($ev['semana_aplicacion'] ?? '') .
            ' | ' . jm_inst_syl_text($ev['peso_porcentaje'] ?? '') .
            ' | ' . jm_inst_syl_text($ev['evidencia'] ?? '') .
            ' | ' . jm_inst_syl_text($ev['instrumento'] ?? '') .
            ' |';
    }

    $lines[] = '';
    $lines[] = '## VIII. Metodologías didácticas';

    foreach (jm_inst_syl_list($syl['metodologias'] ?? []) as $met) {
        if (!is_array($met)) continue;
        $lines[] = '- **' . jm_inst_syl_text($met['nombre'] ?? '') . ':** ' . jm_inst_syl_text($met['uso_en_el_curso'] ?? '') . ' ' . jm_inst_syl_text($met['justificacion'] ?? '');
    }

    $lines[] = '';
    $lines[] = '## IX. Referencias bibliográficas';

    $bib = isset($syl['bibliografia']) && is_array($syl['bibliografia']) ? $syl['bibliografia'] : [];
    foreach (['basicas' => 'Básicas', 'complementarias' => 'Complementarias'] as $k => $label) {
        $lines[] = '';
        $lines[] = '### ' . $label;
        foreach (jm_inst_syl_list($bib[$k] ?? []) as $ref) {
            if (!is_array($ref)) continue;
            $lines[] = '- ' . jm_inst_syl_text($ref['referencia_apa7'] ?? '') . ' ' . jm_inst_syl_text($ref['url_o_doi'] ?? '');
        }
    }

    return trim(implode("\n", $lines));
}

function jm_inst_syl_generate($model, $prompt, $options, $onToken)
{
    if (function_exists('jm_syllabus_llm_stream_generate') && jm_inst_syl_bool('LLM_REMOTE_ENABLED', false)) {
        return jm_syllabus_llm_stream_generate($model, $prompt, $options, $onToken);
    }

    return jm_ollama_stream_generate($model, $prompt, $options, $onToken);
}

/* JOMELAI_INST_SYLLABUS_V5_END */
'''

m = re.search(r'function\s+jm_handle_syllabus_stream\s*\([^)]*\)\s*\{', text)
if not m:
    raise SystemExit("No se encontro jm_handle_syllabus_stream")

start = m.start()
brace_start = text.find("{", m.end() - 1)
depth = 0
end = None
in_str = None
escape = False

for i in range(brace_start, len(text)):
    ch = text[i]

    if in_str:
        if escape:
            escape = False
        elif ch == "\\":
            escape = True
        elif ch == in_str:
            in_str = None
        continue

    if ch in ("'", '"'):
        in_str = ch
        continue

    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break

if end is None:
    raise SystemExit("No se pudo cerrar jm_handle_syllabus_stream")

text = text[:start] + helpers + "\n\n" + text[start:]

m = re.search(r'function\s+jm_handle_syllabus_stream\s*\([^)]*\)\s*\{', text)
start = m.start()
brace_start = text.find("{", m.end() - 1)
depth = 0
end = None
in_str = None
escape = False

for i in range(brace_start, len(text)):
    ch = text[i]

    if in_str:
        if escape:
            escape = False
        elif ch == "\\":
            escape = True
        elif ch == in_str:
            in_str = None
        continue

    if ch in ("'", '"'):
        in_str = ch
        continue

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
    $model = jm_inst_syl_model($requestModel);

    $program = trim((string)($data['program'] ?? $data['programa'] ?? $data['programa_estudio'] ?? ''));
    $credits = trim((string)($data['credits'] ?? $data['creditos'] ?? ''));
    $cycle = trim((string)($data['cycle'] ?? $data['ciclo'] ?? ''));
    $weeks = max(12, min((int)($data['weeks'] ?? $data['semanas'] ?? 16), 18));
    $modality = trim((string)($data['modality'] ?? $data['modalidad'] ?? 'Presencial'));
    $profile = trim((string)($data['graduate_profile'] ?? $data['perfil_egreso'] ?? $data['competencia_perfil'] ?? ''));
    $contribution = trim((string)($data['profile_contribution'] ?? $data['aporte_perfil_egreso'] ?? $data['aporte_perfil'] ?? ''));
    $competency = trim((string)($data['competency'] ?? $data['competencia'] ?? ''));
    $startDate = trim((string)($data['start_date'] ?? $data['fecha_inicio'] ?? ''));
    $sessionsPerWeek = max(1, min((int)($data['sessions_per_week'] ?? $data['sesiones_por_semana'] ?? 1), 4));
    $continueGeneration = !empty($data['continue_generation']);
    $previousRaw = trim((string)($data['previous_raw'] ?? ''));

    $numCtx = (int)($data['num_ctx'] ?? jm_inst_syl_env('SYLLABUS_NUM_CTX', '8192'));
    $numCtx = max(4096, min($numCtx, 16384));

    $numPredict = (int)($data['max_tokens'] ?? $data['num_predict'] ?? jm_inst_syl_env('SYLLABUS_NUM_PREDICT', '7800'));
    $numPredict = max(5200, min($numPredict, 11000));

    $temperature = (float)($data['temperature'] ?? jm_inst_syl_env('SYLLABUS_TEMPERATURE', '0.24'));
    $temperature = max(0.08, min($temperature, 0.45));

    $topP = (float)($data['top_p'] ?? jm_inst_syl_env('SYLLABUS_TOP_P', '0.84'));
    $topP = max(0.65, min($topP, 0.93));

    $numThread = (int)jm_inst_syl_env('SYLLABUS_NUM_THREAD', '2');
    $numThread = max(1, min($numThread, 8));

    $tokensConfig = [
        'model' => $model,
        'model_env' => jm_inst_syl_env('SYLLABUS_OLLAMA_MODEL', 'qwen2.5:3b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_inst_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'num_ctx' => $numCtx,
        'num_predict' => $numPredict,
        'temperature' => $temperature,
        'top_p' => $topP,
        'num_thread' => $numThread,
        'stream' => true,
        'render_mode' => 'syllabus_institutional_competency_v5',
        'strategy' => 'institutional_guide_abet_icacit_sineace_constructive_alignment_v5',
    ];

    $cycleNum = (int)preg_replace('/\D+/', '', $cycle);
    if ($cycleNum <= 0) $cycleNum = 3;

    $bloomRule = 'Ciclos 1 a 3: comprensión y aplicación; verbos sugeridos: identifica, calcula, describe, aplica.';
    if ($cycleNum >= 4 && $cycleNum <= 7) {
        $bloomRule = 'Ciclos 4 a 7: análisis y evaluación; verbos sugeridos: analiza, modela, evalúa, diagnostica, contrasta.';
    } elseif ($cycleNum >= 8) {
        $bloomRule = 'Ciclos 8 a 10: creación; verbos sugeridos: diseña, formula, gestiona, propone, planifica.';
    }

    $profilePrompt = $profile !== ''
        ? "Competencia del perfil de egreso: {$profile}\n"
        : "Competencia del perfil de egreso no especificada. Redacta una tributacion razonable al programa, sin inventar politica institucional.\n";

    $contributionPrompt = $contribution !== ''
        ? "Aporte del curso al perfil de egreso: {$contribution}\n"
        : "Aporte al perfil no especificado. Declara el aporte de forma academica y vinculada al programa.\n";

    $competencyPrompt = $competency !== ''
        ? "Competencia especifica proporcionada: {$competency}\n"
        : "Competencia especifica no proporcionada. Redactala con formula: verbo en presente + objeto de conocimiento + condicion de calidad/contexto + finalidad.\n";

    $continueInstruction = '';

    if ($continueGeneration && $previousRaw !== '') {
        $continueInstruction =
            "MODO COMPLETAR Y MEJORAR:\n" .
            "El intento anterior quedo incompleto o preliminar. No muestres diagnosticos tecnicos al usuario.\n" .
            "Usa el borrador solo para evitar repetir errores. Reconstruye un silabo completo, limpio y valido desde cero.\n" .
            "Borrador anterior:\n{$previousRaw}\n\n";
    }

    $prompt =
        "Eres JoMelAI Curriculista institucional senior. Redacta un SILABO POR COMPETENCIAS riguroso, acreditable y listo para revision curricular.\n" .
        "El silabo debe seguir una guia institucional compatible con alineacion constructiva, ICACIT, ABET y SINEACE.\n" .
        "Responde SOLO JSON valido. No uses markdown. No expliques el proceso.\n\n" .

        $continueInstruction .

        "DATOS DEL CURSO:\n" .
        "Curso: {$course}\n" .
        "Programa profesional: {$program}\n" .
        "Creditos: {$credits}\n" .
        "Ciclo: {$cycle}\n" .
        "Semanas: {$weeks}\n" .
        "Sesiones por semana: {$sessionsPerWeek}\n" .
        "Modalidad: {$modality}\n" .
        "Fecha de inicio: {$startDate}\n" .
        $profilePrompt .
        $contributionPrompt .
        $competencyPrompt .
        "Regla Bloom por ciclo: {$bloomRule}\n\n" .

        "DIRECTIVA INSTITUCIONAL OBLIGATORIA:\n" .
        "1. El silabo es contrato pedagogico y documento legal-academico.\n" .
        "2. Debe seguir alineacion constructiva: Sumilla -> Competencia -> Resultados de Aprendizaje -> Unidades/Sesiones -> Evaluacion.\n" .
        "3. Sumilla: prosa continua, maximo 150 palabras, formula: naturaleza del curso + ubicacion/prerrequisito + proposito general + grandes bloques tematicos.\n" .
        "4. Competencia: verbo presente + objeto de conocimiento + condicion de calidad/contexto + finalidad.\n" .
        "5. Resultados de aprendizaje: 3 a 4 RA, uno por unidad, con verbo observable, contenido y condicion de ejecucion.\n" .
        "6. Calibra los verbos de RA segun ciclo usando la regla Bloom indicada.\n" .
        "7. Cada unidad debe tener RAU, producto de unidad y sesiones que conduzcan al logro del RA.\n" .
        "8. Cada sesion debe incluir cuatro momentos pedagogicos: antes de clase, inicio, desarrollo y cierre.\n" .
        "9. Metodologias institucionales: Aula Invertida transversal; ABP para ciencias e ingenierias; metodo de casos cuando corresponda; ABPro para proyectos, diseno, arquitectura o software.\n" .
        "10. Evaluacion: C1 20%, EP 25%, C2 25%, EF 30%. Ninguna evaluacion debe superar 40%.\n" .
        "11. Toda evaluacion debe tener evidencia, instrumento y criterios de rubrica analitica.\n" .
        "12. Bibliografia: minimo 3 referencias basicas y 2 complementarias en APA 7. Si no conoces URL o DOI exacto, deja url_o_doi vacio.\n\n" .

        "PROHIBICIONES:\n" .
        "- No uses placeholders: generando resultado, generando producto, contenido real, tema real, actividad concreta, construyendo.\n" .
        "- No uses unidades administrativas como Metodologias, Referencias o Evaluacion.\n" .
        "- No uses unidades vagas como Desarrollo de habilidades.\n" .
        "- No uses actividad generica 'Revision de conceptos teoricos'.\n" .
        "- No uses 'calculo basico', 'calculo simple' ni 'tecnicas de numeracion' como ejes curriculares.\n" .
        "- No inventes URLs falsas.\n\n" .

        "ESTRUCTURA JSON OBLIGATORIA:\n" .
        "{\n" .
        "  \"datos_generales\": {\"curso\": string, \"programa\": string, \"creditos\": string, \"ciclo\": string, \"semanas\": number, \"sesiones_por_semana\": number, \"modalidad\": string, \"area_curricular\": string, \"naturaleza\": \"Teorico-practica\", \"prerrequisito\": string, \"sistema_evaluacion\": \"Sistema vigesimal de 0 a 20\"},\n" .
        "  \"sumilla\": string,\n" .
        "  \"competencia_curso\": string,\n" .
        "  \"aporte_al_perfil_egreso\": string,\n" .
        "  \"resultados_aprendizaje\": [{\"codigo\": \"RA1\", \"redaccion\": string, \"nivel_bloom\": string, \"verbo_observable\": string, \"evidencia\": string}],\n" .
        "  \"unidades\": [{\"numero\": number, \"titulo\": string, \"semanas\": [number], \"ra_vinculado\": \"RA1\", \"resultado_aprendizaje_unidad\": string, \"producto_unidad\": string, \"metodologia_dominante\": string, \"contenidos\": [string,string,string,string], \"sesiones\": [{\"semana\": number, \"sesion\": number, \"tema\": string, \"resultado_sesion\": string, \"aporte_a_rau\": string, \"momentos\": {\"antes_clase\": string, \"inicio_clase\": string, \"desarrollo\": string, \"cierre\": string}, \"evidencia_sesion\": string}]}],\n" .
        "  \"matriz_trazabilidad\": [{\"ra\": \"RA1\", \"unidad\": number, \"sesiones\": [number], \"producto\": string, \"evaluacion\": string, \"criterio_logro\": string}],\n" .
        "  \"sistema_evaluacion\": [{\"codigo\": \"C1\", \"evaluacion\": \"Consolidado 1\", \"semana_aplicacion\": \"Semana 4-5\", \"peso_porcentaje\": 20, \"evidencia\": string, \"instrumento\": string, \"criterios_rubrica\": [string,string,string]}],\n" .
        "  \"metodologias\": [{\"nombre\": string, \"uso_en_el_curso\": string, \"justificacion\": string}],\n" .
        "  \"bibliografia\": {\"basicas\": [{\"referencia_apa7\": string, \"url_o_doi\": string, \"antiguedad\": string}], \"complementarias\": [{\"referencia_apa7\": string, \"url_o_doi\": string, \"antiguedad\": string}]}\n" .
        "}\n\n" .

        "CANTIDAD EXACTA PARA EVITAR TRUNCAMIENTO:\n" .
        "- 4 resultados de aprendizaje: RA1, RA2, RA3, RA4.\n" .
        "- 4 unidades, una por RA.\n" .
        "- 4 sesiones por unidad, total 16 sesiones.\n" .
        "- Cada sesion debe tener los 4 momentos pedagogicos.\n" .
        "- 4 filas de matriz de trazabilidad, una por RA.\n" .
        "- 4 evaluaciones: C1 20, EP 25, C2 25, EF 30.\n" .
        "- 5 metodologias.\n" .
        "- 3 bibliografias basicas y 2 complementarias.\n\n" .

        "Redacta contenido disciplinar especifico para el curso y programa. Devuelve JSON completo y valido.";

    jm_sse_start();

    jm_sse_send('progress', ['percent' => 3, 'stage' => 'Inicio', 'message' => 'Preparando el sílabo institucional.']);

    jm_sse_send('model_resolved', [
        'ok' => true,
        'provider' => jm_inst_syl_bool('LLM_REMOTE_ENABLED', false) ? 'remote_llm' : 'ollama_local',
        'model' => $model,
        'model_env' => jm_inst_syl_env('SYLLABUS_OLLAMA_MODEL', 'qwen2.5:3b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_inst_syl_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'render_mode' => 'syllabus_institutional_competency_v5',
    ]);

    jm_sse_send('config', [
        'ok' => true,
        'tokens_config' => $tokensConfig,
        'message' => "Generando sílabo por competencias con {$model}.",
        'render_mode' => 'syllabus_institutional_competency_v5',
    ]);

    jm_sse_send('progress', ['percent' => 12, 'stage' => 'Alineación constructiva', 'message' => 'Articulando sumilla, competencia, resultados, unidades y evaluación.']);
    jm_sse_send('progress', ['percent' => 20, 'stage' => 'Diseño curricular', 'message' => 'Redactando RA, unidades, sesiones y evidencias.']);

    $answer = '';
    $streamPieces = 0;
    $lastPercent = 20;
    $lastProgressTime = microtime(true);

    try {
        $answer = jm_inst_syl_generate(
            $model,
            $prompt,
            [
                'temperature' => $temperature,
                'top_p' => $topP,
                'repeat_penalty' => 1.20,
                'num_ctx' => $numCtx,
                'num_predict' => $numPredict,
                'num_thread' => $numThread,
            ],
            function ($piece) use (&$streamPieces, &$lastPercent, &$lastProgressTime, $numPredict) {
                $streamPieces++;
                jm_sse_send('token', ['text' => $piece]);

                $estimated = 20 + (int)min(70, floor(($streamPieces / max(1, $numPredict)) * 70));
                $now = microtime(true);

                if ($estimated > $lastPercent + 1 || ($now - $lastProgressTime) > 1.25) {
                    $lastPercent = min(90, max($lastPercent, $estimated));
                    $lastProgressTime = $now;

                    $stage = 'Construcción del sílabo';
                    $message = 'Generando unidades, sesiones y evidencias.';

                    if ($lastPercent >= 38 && $lastPercent < 58) {
                        $stage = 'Sesiones';
                        $message = 'Construyendo los momentos pedagógicos de las sesiones.';
                    } elseif ($lastPercent >= 58 && $lastPercent < 78) {
                        $stage = 'Evaluación';
                        $message = 'Armando C1, EP, C2, EF, rúbricas y trazabilidad.';
                    } elseif ($lastPercent >= 78) {
                        $stage = 'Validación';
                        $message = 'Validando coherencia curricular y formato final.';
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

    jm_sse_send('progress', ['percent' => 94, 'stage' => 'Revisión final', 'message' => 'Preparando visualización del sílabo.']);

    $syllabus = jm_inst_syl_extract_json($answer);
    $parseOk = is_array($syllabus);
    $qualityIssues = jm_inst_syl_quality_issues($syllabus, $answer);
    $needsContinue = !$parseOk || count($qualityIssues) > 0;
    $markdown = $parseOk ? jm_inst_syl_to_markdown($syllabus, $answer) : $answer;

    jm_sse_send('syllabus', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'parse_ok' => $parseOk,
        'needs_continue' => $needsContinue,
        'quality_issues' => $qualityIssues,
        'render_mode' => 'syllabus_institutional_competency_v5',
        'syllabus' => $syllabus,
        'markdown' => $markdown,
        'raw_response' => $answer,
        'tokens_config' => $tokensConfig,
    ]);

    jm_sse_send('progress', [
        'percent' => $needsContinue ? 96 : 100,
        'stage' => $needsContinue ? 'Requiere completar' : 'Completado',
        'message' => $needsContinue
            ? 'El sílabo necesita completarse para quedar listo.'
            : 'Sílabo institucional generado y listo para revisión.',
    ]);

    jm_sse_send('final', [
        'ok' => true,
        'mode' => 'syllabus_stream',
        'model' => $model,
        'parse_ok' => $parseOk,
        'needs_continue' => $needsContinue,
        'quality_issues' => $qualityIssues,
        'render_mode' => 'syllabus_institutional_competency_v5',
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
}

for f in "${PHP_FILES[@]}"; do
  patch_php_file "$f"
done

echo
echo "== 4) Validando PHP en host si existe php =="

if command -v php >/dev/null 2>&1; then
  for f in "${PHP_FILES[@]}"; do
    php -l "$f"
  done
else
  echo "PHP no esta instalado en host."
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
    "SYLLABUS_NUM_CTX": "8192",
    "SYLLABUS_NUM_PREDICT": "7800",
    "SYLLABUS_TEMPERATURE": "0.24",
    "SYLLABUS_TOP_P": "0.84",
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

for f in "${PHP_FILES[@]}"; do
  PHP_DIR="$(dirname "$f")"
  if [ "$PHP_DIR" != "." ]; then
    cp .env "$PHP_DIR/.env" || true
  fi
done

echo
echo "== 6) Creando interfaz amigable V5 =="

cat > public/jomelai-syllabus-institutional-v5.js <<'JS'
(function () {
  var MODEL = window.JOMELAI_SYLLABUS_MODEL || "qwen2.5:3b";
  var lastPayload = null;
  var lastRaw = "";

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
    if (document.getElementById("jm-inst-syl-v5-css")) return;

    var s = document.createElement("style");
    s.id = "jm-inst-syl-v5-css";
    s.textContent = `
      .jm-inst-progress{
        margin:16px 0;
        padding:16px;
        border:1px solid #e4ebf3;
        border-radius:18px;
        background:#fff;
        box-shadow:0 12px 32px rgba(15,42,75,.08);
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-inst-progress-top{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:10px;}
      .jm-inst-stage{font-weight:900;color:#0f2a4b;}
      .jm-inst-percent{font-weight:900;color:#0f2a4b;background:#eef5ff;border-radius:999px;padding:6px 10px;}
      .jm-inst-bar{height:12px;border-radius:999px;overflow:hidden;background:#edf2f7;}
      .jm-inst-fill{height:100%;width:0%;background:linear-gradient(90deg,#0f2a4b,#2c6aa0);transition:width .25s ease;}
      .jm-inst-msg{margin-top:8px;color:#536174;font-size:13px;}

      .jm-inst-doc{margin:18px 0;background:#f3f6fa;border-radius:24px;padding:18px;font-family:Inter,Roboto,Arial,sans-serif;}
      .jm-inst-paper{max-width:1180px;margin:0 auto;background:white;border-radius:22px;box-shadow:0 18px 50px rgba(15,42,75,.13);overflow:hidden;border:1px solid rgba(15,42,75,.08);}
      .jm-inst-head{background:linear-gradient(135deg,#0f2a4b,#173e6f);color:#fff;padding:26px 30px;}
      .jm-inst-tag{display:inline-block;padding:5px 10px;border-radius:999px;background:rgba(214,174,92,.18);border:1px solid rgba(214,174,92,.4);color:#ffe1a1;font-size:12px;margin-bottom:10px;}
      .jm-inst-head h2{margin:0;font-size:26px;}
      .jm-inst-head p{margin:8px 0 0;color:#dce9f8;}
      .jm-inst-section{padding:22px 30px;border-bottom:1px solid #edf1f5;}
      .jm-inst-section h3{margin:0 0 14px;color:#0f2a4b;font-size:18px;}
      .jm-inst-section p,.jm-inst-section li{color:#2d3f53;line-height:1.6;}
      .jm-inst-data{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;}
      .jm-inst-item{background:#f7f9fc;border:1px solid #edf1f5;border-radius:14px;padding:12px;}
      .jm-inst-label{display:block;color:#66758a;font-size:11px;text-transform:uppercase;letter-spacing:.04em;margin-bottom:4px;}
      .jm-inst-value{color:#152b46;font-weight:800;font-size:13px;}
      .jm-inst-table-wrap{overflow-x:auto;margin-top:12px;}
      .jm-inst-table{width:100%;border-collapse:collapse;font-size:13px;}
      .jm-inst-table th{text-align:left;background:#0f2a4b;color:white;padding:10px;font-weight:800;white-space:nowrap;}
      .jm-inst-table td{border-bottom:1px solid #edf1f5;padding:10px;vertical-align:top;color:#2d3f53;}
      .jm-inst-unit{border:1px solid #e4ebf3;border-radius:18px;overflow:hidden;margin:16px 0;background:#fff;}
      .jm-inst-unit-title{padding:16px 18px;background:#f8fafc;border-bottom:1px solid #e4ebf3;}
      .jm-inst-unit-title strong{color:#0f2a4b;font-size:16px;}
      .jm-inst-unit-body{padding:16px 18px;}
      .jm-inst-chip{display:inline-flex;margin:3px 5px 3px 0;padding:5px 9px;border-radius:999px;background:#eef5ff;color:#24517e;font-size:12px;font-weight:700;}
      .jm-inst-actions{display:flex;flex-wrap:wrap;gap:8px;justify-content:flex-end;padding:14px 30px;background:#f8fafc;}
      .jm-inst-actions button{border:0;border-radius:12px;padding:10px 14px;font-weight:900;cursor:pointer;background:#0f2a4b;color:white;}
      .jm-inst-actions button.secondary{background:#6b7280;}
      .jm-inst-friendly{margin:14px 0;padding:14px;border-radius:14px;background:#eef5ff;border:1px solid #cfe0f7;color:#173e6f;font-size:14px;}
      .jm-inst-legacy-hidden{display:none!important;}
      @media(max-width:760px){.jm-inst-data{grid-template-columns:1fr}.jm-inst-head,.jm-inst-section{padding:18px}}
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

    if (!document.getElementById("jm-inst-progress")) {
      var p = document.createElement("div");
      p.id = "jm-inst-progress";
      p.className = "jm-inst-progress";
      p.innerHTML = `
        <div class="jm-inst-progress-top">
          <div>
            <div class="jm-inst-stage" id="jm-inst-stage">Esperando generación</div>
            <div class="jm-inst-msg" id="jm-inst-msg">Completa los datos y genera el sílabo.</div>
          </div>
          <div class="jm-inst-percent" id="jm-inst-percent">0%</div>
        </div>
        <div class="jm-inst-bar"><div class="jm-inst-fill" id="jm-inst-fill"></div></div>
      `;
      r.insertBefore(p, r.firstChild || null);
    }

    if (!document.getElementById("jomelai-syllabus-institutional-output")) {
      var out = document.createElement("div");
      out.id = "jomelai-syllabus-institutional-output";
      r.appendChild(out);
    }
  }

  function setProgress(percent, stage, message) {
    ensureUi();
    percent = Math.max(0, Math.min(100, Number(percent || 0)));

    var pct = document.getElementById("jm-inst-percent");
    var fill = document.getElementById("jm-inst-fill");
    var st = document.getElementById("jm-inst-stage");
    var msg = document.getElementById("jm-inst-msg");

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

  function hideLegacyDrafts() {
    var patterns = [
      /Sílabo preliminar/i,
      /JOMELAI\s*·\s*SÍLABO/i,
      /Generando resultado/i,
      /Generando producto/i,
      /Preparando generación en vivo/i,
      /JSON incompleto/i
    ];

    Array.prototype.slice.call(document.querySelectorAll("section,article,div")).forEach(function (el) {
      if (el.closest("#jomelai-syllabus-institutional-output") || el.closest("#jm-inst-progress")) return;

      var txt = (el.innerText || "").slice(0, 1000);
      if (!txt) return;

      var hit = patterns.some(function (p) { return p.test(txt); });
      if (!hit) return;

      var box = el;
      for (var i = 0; i < 4 && box.parentElement; i++) {
        var rect = box.getBoundingClientRect();
        if (rect.width > 500 && rect.height > 250) break;
        box = box.parentElement;
      }

      box.classList.add("jm-inst-legacy-hidden");
    });
  }

  function renderNeedContinue(markdown, payload) {
    ensureUi();
    hideLegacyDrafts();

    var out = document.getElementById("jomelai-syllabus-institutional-output");
    if (!out) return;

    out.innerHTML = `
      <div class="jm-inst-doc">
        <div class="jm-inst-paper">
          <div class="jm-inst-head">
            <span class="jm-inst-tag">Sílabo en construcción</span>
            <h2>El sílabo necesita completarse</h2>
            <p>La generación quedó incompleta. Puedes completarla automáticamente conservando los datos ingresados.</p>
          </div>
          <div class="jm-inst-section">
            <h3>Estado de la generación</h3>
            <div class="jm-inst-friendly">
              El documento aún no está listo para revisión curricular. Presiona <strong>Completar y mejorar sílabo</strong> para reconstruirlo con más coherencia, trazabilidad y sesiones completas.
            </div>
          </div>
          <div class="jm-inst-actions">
            <button type="button" id="jm-inst-continue">Completar y mejorar sílabo</button>
            <button type="button" class="secondary" id="jm-inst-copy-draft">Copiar borrador técnico</button>
          </div>
        </div>
      </div>
    `;

    var btn = document.getElementById("jm-inst-continue");
    var copy = document.getElementById("jm-inst-copy-draft");

    if (copy) {
      copy.onclick = function () {
        navigator.clipboard.writeText(markdown || lastRaw || "");
      };
    }

    if (btn) {
      btn.onclick = function () {
        if (!lastPayload) {
          alert("No se encontró la solicitud anterior. Vuelve a generar el sílabo.");
          return;
        }

        var next = {};
        Object.keys(lastPayload).forEach(function (k) { next[k] = lastPayload[k]; });

        next.model = MODEL;
        next.continue_generation = true;
        next.previous_raw = lastRaw || markdown || "";
        next.max_tokens = 7800;
        next.num_ctx = 8192;
        next.temperature = 0.24;
        next.top_p = 0.84;
        next.render_mode = "syllabus_institutional_competency_v5";

        setProgress(3, "Completando sílabo", "Reconstruyendo el documento con la guía institucional.");

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
    hideLegacyDrafts();

    if (!syl) {
      renderNeedContinue(markdown, payload);
      return;
    }

    var out = document.getElementById("jomelai-syllabus-institutional-output");
    if (!out) return;

    var dg = syl.datos_generales || {};
    var bib = syl.bibliografia || {};

    var dataHtml = [
      ["Curso", dg.curso],
      ["Programa", dg.programa],
      ["Créditos", dg.creditos],
      ["Ciclo", dg.ciclo],
      ["Semanas", dg.semanas],
      ["Modalidad", dg.modalidad],
      ["Área curricular", dg.area_curricular],
      ["Naturaleza", dg.naturaleza]
    ].map(function (it) {
      return `
        <div class="jm-inst-item">
          <span class="jm-inst-label">${esc(it[0])}</span>
          <span class="jm-inst-value">${esc(it[1] || "")}</span>
        </div>
      `;
    }).join("");

    var raHtml = list(syl.resultados_aprendizaje).map(function (r) {
      return `
        <tr>
          <td>${esc(r.codigo || "")}</td>
          <td>${esc(r.redaccion || "")}</td>
          <td>${esc(r.nivel_bloom || "")}</td>
          <td>${esc(r.verbo_observable || "")}</td>
          <td>${esc(r.evidencia || "")}</td>
        </tr>
      `;
    }).join("");

    var unidadesHtml = list(syl.unidades).map(function (u) {
      var contenidos = list(u.contenidos).map(function (c) {
        return '<span class="jm-inst-chip">' + esc(c) + '</span>';
      }).join("");

      var sesiones = list(u.sesiones).map(function (s) {
        var m = s.momentos || {};
        return `
          <tr>
            <td>${esc(s.semana || "")}</td>
            <td>${esc(s.sesion || "")}</td>
            <td>${esc(s.tema || "")}</td>
            <td>${esc(s.resultado_sesion || "")}</td>
            <td>${esc(m.antes_clase || "")}</td>
            <td>${esc(m.inicio_clase || "")}</td>
            <td>${esc(m.desarrollo || "")}</td>
            <td>${esc(m.cierre || "")}</td>
            <td>${esc(s.evidencia_sesion || "")}</td>
          </tr>
        `;
      }).join("");

      return `
        <div class="jm-inst-unit">
          <div class="jm-inst-unit-title">
            <strong>Unidad ${esc(u.numero || "")}: ${esc(u.titulo || "")}</strong>
            <div style="margin-top:6px;color:#66758a;font-size:12px;">
              Semanas: ${esc(Array.isArray(u.semanas) ? u.semanas.join(", ") : (u.semanas || ""))}
              | RA: ${esc(u.ra_vinculado || "")}
              | Método: ${esc(u.metodologia_dominante || "")}
            </div>
          </div>
          <div class="jm-inst-unit-body">
            <p><strong>RAU:</strong> ${esc(u.resultado_aprendizaje_unidad || "")}</p>
            <p><strong>Producto de unidad:</strong> ${esc(u.producto_unidad || "")}</p>
            <div>${contenidos}</div>
            <div class="jm-inst-table-wrap">
              <table class="jm-inst-table">
                <thead>
                  <tr>
                    <th>Semana</th><th>Sesión</th><th>Tema</th><th>Resultado</th><th>Antes</th><th>Inicio</th><th>Desarrollo</th><th>Cierre</th><th>Evidencia</th>
                  </tr>
                </thead>
                <tbody>${sesiones}</tbody>
              </table>
            </div>
          </div>
        </div>
      `;
    }).join("");

    var traceHtml = list(syl.matriz_trazabilidad).map(function (t) {
      return `
        <tr>
          <td>${esc(t.ra || "")}</td>
          <td>${esc(t.unidad || "")}</td>
          <td>${esc(Array.isArray(t.sesiones) ? t.sesiones.join(", ") : (t.sesiones || ""))}</td>
          <td>${esc(t.producto || "")}</td>
          <td>${esc(t.evaluacion || "")}</td>
          <td>${esc(t.criterio_logro || "")}</td>
        </tr>
      `;
    }).join("");

    var evalHtml = list(syl.sistema_evaluacion).map(function (e) {
      return `
        <tr>
          <td>${esc(e.codigo || "")}</td>
          <td>${esc(e.evaluacion || "")}</td>
          <td>${esc(e.semana_aplicacion || "")}</td>
          <td>${esc(e.peso_porcentaje || "")}%</td>
          <td>${esc(e.evidencia || "")}</td>
          <td>${esc(e.instrumento || "")}</td>
        </tr>
      `;
    }).join("");

    var metHtml = list(syl.metodologias).map(function (m) {
      return `<li><strong>${esc(m.nombre || "")}:</strong> ${esc(m.uso_en_el_curso || "")} ${esc(m.justificacion || "")}</li>`;
    }).join("");

    var bibHtml = `
      <h4>Básicas</h4>
      <ul>${list(bib.basicas).map(function (r) { return "<li>" + esc(r.referencia_apa7 || "") + " " + esc(r.url_o_doi || "") + "</li>"; }).join("")}</ul>
      <h4>Complementarias</h4>
      <ul>${list(bib.complementarias).map(function (r) { return "<li>" + esc(r.referencia_apa7 || "") + " " + esc(r.url_o_doi || "") + "</li>"; }).join("")}</ul>
    `;

    var needs = payload && payload.needs_continue;

    out.innerHTML = `
      <div class="jm-inst-doc">
        <div class="jm-inst-paper">
          <div class="jm-inst-head">
            <span class="jm-inst-tag">Sílabo por competencias</span>
            <h2>${esc(dg.curso || "Sílabo")}</h2>
            <p>${esc(dg.programa || "")}</p>
          </div>

          ${needs ? '<div class="jm-inst-section"><div class="jm-inst-friendly">El documento puede completarse con una segunda pasada de mejora curricular.</div></div>' : ''}

          <div class="jm-inst-section">
            <h3>I. Datos generales</h3>
            <div class="jm-inst-data">${dataHtml}</div>
          </div>

          <div class="jm-inst-section">
            <h3>II. Sumilla</h3>
            <p>${esc(syl.sumilla || "")}</p>
          </div>

          <div class="jm-inst-section">
            <h3>III. Competencia del curso</h3>
            <p>${esc(syl.competencia_curso || "")}</p>
            <p><strong>Aporte al perfil:</strong> ${esc(syl.aporte_al_perfil_egreso || "")}</p>
          </div>

          <div class="jm-inst-section">
            <h3>IV. Resultados de aprendizaje</h3>
            <div class="jm-inst-table-wrap">
              <table class="jm-inst-table">
                <thead><tr><th>Código</th><th>Resultado</th><th>Nivel Bloom</th><th>Verbo</th><th>Evidencia</th></tr></thead>
                <tbody>${raHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-inst-section">
            <h3>V. Unidades y sesiones</h3>
            ${unidadesHtml}
          </div>

          <div class="jm-inst-section">
            <h3>VI. Matriz de trazabilidad académica</h3>
            <div class="jm-inst-table-wrap">
              <table class="jm-inst-table">
                <thead><tr><th>RA</th><th>Unidad</th><th>Sesiones</th><th>Producto</th><th>Evaluación</th><th>Criterio</th></tr></thead>
                <tbody>${traceHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-inst-section">
            <h3>VII. Sistema de evaluación</h3>
            <div class="jm-inst-table-wrap">
              <table class="jm-inst-table">
                <thead><tr><th>Código</th><th>Evaluación</th><th>Semana</th><th>Peso</th><th>Evidencia</th><th>Instrumento</th></tr></thead>
                <tbody>${evalHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-inst-section">
            <h3>VIII. Metodologías didácticas</h3>
            <ul>${metHtml}</ul>
          </div>

          <div class="jm-inst-section">
            <h3>IX. Referencias bibliográficas APA 7</h3>
            ${bibHtml}
          </div>

          <div class="jm-inst-actions">
            ${needs ? '<button type="button" id="jm-inst-continue">Completar y mejorar sílabo</button>' : ''}
            <button type="button" id="jm-inst-copy-md">Copiar Markdown</button>
            <button type="button" class="secondary" id="jm-inst-copy-json">Copiar estructura</button>
          </div>
        </div>
      </div>
    `;

    var mdBtn = document.getElementById("jm-inst-copy-md");
    var jsonBtn = document.getElementById("jm-inst-copy-json");
    var contBtn = document.getElementById("jm-inst-continue");

    if (mdBtn) mdBtn.onclick = function () { navigator.clipboard.writeText(markdown || ""); };
    if (jsonBtn) jsonBtn.onclick = function () { navigator.clipboard.writeText(JSON.stringify(syl, null, 2)); };

    if (contBtn) {
      contBtn.onclick = function () {
        var next = {};
        Object.keys(lastPayload || {}).forEach(function (k) { next[k] = lastPayload[k]; });
        next.model = MODEL;
        next.continue_generation = true;
        next.previous_raw = lastRaw || JSON.stringify(syl, null, 2);
        next.max_tokens = 7800;
        next.num_ctx = 8192;
        next.temperature = 0.24;
        next.top_p = 0.84;
        next.render_mode = "syllabus_institutional_competency_v5";

        setProgress(3, "Completando sílabo", "Reconstruyendo el documento con la guía institucional.");

        fetch("/api/assistant/generate-syllabus-stream", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
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
    try { data = JSON.parse(dataText); } catch (e) {}

    if (eventName === "progress" && data) {
      setProgress(data.percent, data.stage, data.message);
      return;
    }

    if (eventName === "config" && data) {
      setProgress(10, "Configuración", data.message || "Configurando generación institucional.");
      return;
    }

    if ((eventName === "syllabus" || eventName === "final") && data) {
      lastRaw = data.raw_response || data.response || data.answer || lastRaw;
      var syl = data.syllabus || extractJson(data.raw_response) || extractJson(data.response) || extractJson(data.answer);
      var md = data.markdown || data.answer || data.response || "";
      renderSyllabus(syl, md, data);

      if (eventName === "final" && !data.needs_continue) {
        setProgress(100, "Completado", "Sílabo institucional generado y listo para revisión.");
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
        if (line.indexOf("event:") === 0) ev = line.slice(6).trim();
        else if (line.indexOf("data:") === 0) data.push(line.slice(5).trim());
      });

      if (data.length) onEvent(ev, data.join("\n"));
    });

    return rest;
  }

  function patchFetch() {
    if (!window.fetch || window.fetch.__jmInstSylV5) return;

    var originalFetch = window.fetch;

    window.fetch = function (input, init) {
      if (!isSyllabusUrl(input)) return originalFetch.apply(this, arguments);

      ensureUi();
      hideLegacyDrafts();
      setProgress(2, "Inicio", "Enviando solicitud al generador institucional.");

      var opts = {};
      init = init || {};
      Object.keys(init).forEach(function (k) { opts[k] = init[k]; });

      try {
        if (typeof opts.body === "string" && opts.body.trim().charAt(0) === "{") {
          var payload = JSON.parse(opts.body);
          payload.model = MODEL;
          payload.max_tokens = payload.max_tokens || 7800;
          payload.num_ctx = payload.num_ctx || 8192;
          payload.temperature = payload.temperature || 0.24;
          payload.top_p = payload.top_p || 0.84;
          payload.render_mode = "syllabus_institutional_competency_v5";
          lastPayload = payload;
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
              hideLegacyDrafts();
              return;
            }

            buffer += decoder.decode(res.value, {stream: true});
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

    window.fetch.__jmInstSylV5 = true;
  }

  function init() {
    ensureUi();
    patchFetch();
    hideLegacyDrafts();
    console.log("[JoMelAi] Sílabo institucional V5 activo. Modelo:", MODEL);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
JS

cat > public/jomelai-syllabus-pretty-v7-live.js <<'JS'
(function(){console.log("[JoMelAi] syllabus pretty compat activo");window.JOMELAI_SYLLABUS_PRETTY_READY=true;})();
JS

cat > public/chat-lateral-v2-client.js <<'JS'
(function(){console.log("[JoMelAi] chat lateral compat activo");window.JOMELAI_CHAT_LATERAL_READY=true;})();
JS

cat > public/chat-panel-renderer-final.js <<'JS'
(function(){console.log("[JoMelAi] chat panel renderer compat activo");window.JOMELAI_CHAT_PANEL_RENDERER_READY=true;})();
JS

cat > public/chat-pie-image-override.js <<'JS'
(function(){console.log("[JoMelAi] chat pie override compat activo");window.JOMELAI_CHAT_PIE_OVERRIDE_READY=true;})();
JS

for f in \
  jomelai-syllabus-institutional-v5.js \
  jomelai-syllabus-pretty-v7-live.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js
do
  cp "public/$f" "./$f"
done

for d in ./frontend/public ./front/public ./client/public ./app/public ./web/public ./src/public; do
  if [ -d "$d" ]; then
    echo "sincronizando assets en $d"
    cp public/*.js "$d/" || true
  fi
done

echo
echo "== 7) Inyectando JS V5 en index.html locales =="

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
    Path("app/index.html"),
]

script = "jomelai-syllabus-institutional-v5.js"
tag = f'  <script src="/{script}?v=institutional-v5"></script>'

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
echo "== 9) Copiando PHP y JS al runtime activo =="

BACKEND_CONTAINERS="$(docker ps --format '{{.Names}} {{.Image}}' | grep -Ei 'backend|laravel|php|apache|api' | grep -vi 'frontend' | awk '{print $1}' || true)"

if [ -n "$BACKEND_CONTAINERS" ]; then
  echo "$BACKEND_CONTAINERS" | while read c; do
    [ -n "$c" ] || continue
    echo "BACKEND_CONTAINER=$c"

    RUNTIME_PHP_LIST="$(docker exec "$c" sh -lc "
      for d in /var/www/html /app /srv/app /var/www /usr/share/nginx/html; do
        [ -d \"\$d\" ] && grep -Rsl 'function jm_handle_syllabus_stream' \"\$d\" 2>/dev/null || true
      done
    " || true)"

    if [ -n "$RUNTIME_PHP_LIST" ]; then
      echo "$RUNTIME_PHP_LIST" | while read runtime_php; do
        [ -n "$runtime_php" ] || continue
        echo "copiando PHP runtime: $runtime_php"
        docker cp "${PHP_FILES[0]}" "$c:$runtime_php"
        runtime_dir="$(dirname "$runtime_php")"
        docker cp .env "$c:$runtime_dir/.env" || true
      done
    fi
  done
else
  echo "WARN: no detecte backend container."
fi

FRONT_CONTAINERS="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' | grep -Ei '3000|frontend|nginx|web|vite|node' | grep -vi 'ollama' | grep -vi 'data_engine' | awk '{print $1}' || true)"

if [ -n "$FRONT_CONTAINERS" ]; then
  echo "$FRONT_CONTAINERS" | while read c; do
    [ -n "$c" ] || continue
    echo "FRONT_CONTAINER=$c"

    ROOTS="$(docker exec "$c" sh -lc '
      for d in /usr/share/nginx/html /app/dist /app/build /app/public /app /var/www/html; do
        [ -d "$d" ] && echo "$d"
      done
    ' || true)"

    if [ -z "$ROOTS" ]; then
      ROOTS="/usr/share/nginx/html"
    fi

    echo "$ROOTS" | while read r; do
      [ -n "$r" ] || continue
      echo "copiando assets a $c:$r"
      docker exec "$c" sh -lc "mkdir -p '$r'" || true
      for f in \
        jomelai-syllabus-institutional-v5.js \
        jomelai-syllabus-pretty-v7-live.js \
        chat-lateral-v2-client.js \
        chat-panel-renderer-final.js \
        chat-pie-image-override.js
      do
        docker cp "public/$f" "$c:$r/$f" || true
      done
    done

    INDEX_FILES="$(docker exec "$c" sh -lc '
      for f in /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html /app/index.html /var/www/html/index.html; do
        [ -f "$f" ] && echo "$f"
      done
    ' || true)"

    echo "$INDEX_FILES" | while read idx; do
      [ -n "$idx" ] || continue
      safe="$(echo "$c$idx" | tr '/:' '__')"
      docker cp "$c:$idx" "$BACKUP_DIR/$safe.bak.html" || true

      python3 - "$BACKUP_DIR/$safe.bak.html" "$BACKUP_DIR/$safe.patched.html" <<'PY'
from pathlib import Path
import re
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

text = src.read_text(encoding="utf-8", errors="ignore")
script = "jomelai-syllabus-institutional-v5.js"
tag = f'  <script src="/{script}?v=institutional-v5"></script>'

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

      docker cp "$BACKUP_DIR/$safe.patched.html" "$c:$idx" || true
    done

    docker exec "$c" sh -lc '
      if command -v nginx >/dev/null 2>&1; then
        nginx -t && nginx -s reload
      fi
    ' || true
  done
else
  echo "WARN: no detecte frontend container."
fi

echo
echo "== 10) Verificando HTTP y stream =="

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
  jomelai-syllabus-institutional-v5.js \
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
echo "---- endpoint config ----"

curl -sS -N -m 180 -X POST "http://localhost:${APP_PORT}/api/assistant/generate-syllabus-stream" \
  -H "Content-Type: application/json" \
  -d '{
    "course": "Calculo 1",
    "program": "Ingenieria Civil",
    "credits": "4",
    "cycle": "3",
    "weeks": "16",
    "modality": "Presencial",
    "graduate_profile": "Resuelve problemas de ingenieria civil aplicando fundamentos matematicos, criterios tecnicos y comunicacion rigurosa.",
    "profile_contribution": "El curso desarrolla bases matematicas para modelar fenomenos de variacion, interpretar resultados y sustentar decisiones tecnicas.",
    "competency": "Aplica conceptos de funciones, limites, derivadas e integrales iniciales para modelar y resolver problemas de variacion en contextos de ingenieria civil.",
    "sessions_per_week": "1"
  }' | grep -E "model_resolved|config|syllabus_institutional_competency_v5|institutional_guide|num_ctx|num_predict|progress|needs_continue|parse_ok" | head -80 || true

echo
echo
echo "== 11) Git status =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Debe aparecer en el stream:"
echo "  render_mode: syllabus_institutional_competency_v5"
echo "  strategy: institutional_guide_abet_icacit_sineace_constructive_alignment_v5"
echo "  model: $TARGET_MODEL"
echo
echo "En navegador:"
echo "  Ctrl + Shift + R"
echo
echo "En consola debe aparecer:"
echo "  [JoMelAi] Sílabo institucional V5 activo"
echo
echo "Si la generacion queda incompleta, el usuario vera:"
echo "  El sílabo necesita completarse"
echo "  Completar y mejorar sílabo"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
