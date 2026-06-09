#!/usr/bin/env bash
set -Eeuo pipefail

cd /home/ubuntu/jomelai

echo "=================================================="
echo " Optimize generate-syllabus-stream + formatter UI"
echo "=================================================="

BACKUP_DIR="backups/optimize_syllabus_formatter_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "== 1) Buscando archivo PHP del stream =="
PHP_FILE="$(grep -Rsl "function jm_handle_syllabus_stream" . \
  --include='*.php' \
  --exclude-dir=.git \
  --exclude-dir=vendor \
  --exclude-dir=node_modules \
  --exclude-dir=data \
  --exclude='*.bak*' \
  | head -1 || true)"

if [ -z "$PHP_FILE" ] || [ ! -f "$PHP_FILE" ]; then
  echo "ERROR: no encontré el PHP con jm_handle_syllabus_stream."
  grep -R "function jm_handle_syllabus_stream" -n . --include='*.php' || true
  exit 1
fi

echo "PHP_FILE=$PHP_FILE"
cp "$PHP_FILE" "$BACKUP_DIR/$(basename "$PHP_FILE").bak"

echo
echo "== 2) Parcheando PHP: Ollama JSON + final formateable =="
python3 - "$PHP_FILE" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

# ------------------------------------------------------------
# jm_ollama_stream_generate: agregar keep_alive y format=json
# ------------------------------------------------------------
if "function jm_ollama_stream_generate($model, $prompt, $options, $onToken, $format = null)" not in text:
    text = text.replace(
        "function jm_ollama_stream_generate($model, $prompt, $options, $onToken)",
        "function jm_ollama_stream_generate($model, $prompt, $options, $onToken, $format = null)"
    )

old_payload = """    $payload = [
        'model' => $model,
        'prompt' => $prompt,
        'stream' => true,
        'options' => $options,
    ];"""

new_payload = """    $payload = [
        'model' => $model,
        'prompt' => $prompt,
        'stream' => true,
        'keep_alive' => getenv('SYLLABUS_KEEP_ALIVE') ?: '30m',
        'options' => $options,
    ];

    if ($format !== null && $format !== '') {
        $payload['format'] = $format;
    }"""

if old_payload in text:
    text = text.replace(old_payload, new_payload)

# ------------------------------------------------------------
# Quitar helpers antiguos si existieran
# ------------------------------------------------------------
text = re.sub(
    r"\n/\* JOMELAI_SYLLABUS_FORMAT_HELPERS_START \*/.*?/\* JOMELAI_SYLLABUS_FORMAT_HELPERS_END \*/\n",
    "\n",
    text,
    flags=re.S
)

helpers = r'''
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
'''

# Insertar helpers antes de la función.
idx = text.find("function jm_handle_syllabus_stream()")
if idx == -1:
    raise SystemExit("No encontré function jm_handle_syllabus_stream().")

text = text[:idx] + helpers + "\n\n" + text[idx:]

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

    $model = trim((string)($data['model'] ?? jm_stream_config('syllabus_ollama_model', getenv('SYLLABUS_OLLAMA_MODEL') ?: 'qwen2.5:0.5b')));
    if ($model === '') {
        $model = 'qwen2.5:0.5b';
    }

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
'''

start = text.find("function jm_handle_syllabus_stream()")
if start == -1:
    raise SystemExit("No encontré function jm_handle_syllabus_stream().")

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
    raise SystemExit("No pude encontrar el final de jm_handle_syllabus_stream().")

end = min(positions)

text = text[:start] + new_func + "\n\n" + text[end:].lstrip("\n")

p.write_text(text, encoding="utf-8")
PY

echo
echo "== 3) Validando sintaxis PHP en host si existe =="
if command -v php >/dev/null 2>&1; then
  php -l "$PHP_FILE"
else
  echo "PHP no está en host; se validará tras levantar contenedor si aplica."
fi

echo
echo "== 4) Creando renderer frontend para formato de sílabo =="
mkdir -p public

cat > public/jomelai-syllabus-format-renderer.js <<'JS'
(function () {
  if (window.__JOMELAI_SYLLABUS_FORMAT_RENDERER__) return;
  window.__JOMELAI_SYLLABUS_FORMAT_RENDERER__ = true;

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function arr(v) {
    if (Array.isArray(v)) return v;
    if (v == null || v === '') return [];
    return [v];
  }

  function tryJson(text) {
    if (!text || typeof text !== 'string') return null;

    try {
      const direct = JSON.parse(text);
      if (direct && typeof direct === 'object') return direct;
    } catch (e) {}

    const a = text.indexOf('{');
    const b = text.lastIndexOf('}');
    if (a >= 0 && b > a) {
      try {
        const obj = JSON.parse(text.slice(a, b + 1));
        if (obj && typeof obj === 'object') return obj;
      } catch (e) {}
    }

    return null;
  }

  function getSyllabus(payload) {
    if (!payload || typeof payload !== 'object') return null;

    if (payload.syllabus && typeof payload.syllabus === 'object') {
      return payload.syllabus;
    }

    return (
      tryJson(payload.raw_response) ||
      tryJson(payload.response) ||
      tryJson(payload.answer) ||
      null
    );
  }

  function injectStyles() {
    if (document.getElementById('jomelai-syllabus-format-style')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-syllabus-format-style';
    style.textContent = `
      .jomelai-syllabus-card {
        margin: 18px 0;
        padding: 0;
        background: #ffffff;
        border: 1px solid rgba(15, 23, 42, .12);
        border-radius: 18px;
        box-shadow: 0 16px 45px rgba(15, 23, 42, .10);
        overflow: hidden;
        font-family: Inter, Roboto, Arial, sans-serif;
        color: #1f2937;
      }

      .jomelai-syllabus-header {
        padding: 18px 20px;
        background: linear-gradient(135deg, #0f2f57, #174a7c);
        color: #ffffff;
      }

      .jomelai-syllabus-header h2 {
        margin: 0;
        font-size: 20px;
        line-height: 1.2;
        font-weight: 850;
      }

      .jomelai-syllabus-header p {
        margin: 6px 0 0;
        font-size: 13px;
        opacity: .88;
      }

      .jomelai-syllabus-body {
        padding: 18px 20px 22px;
      }

      .jomelai-syllabus-section {
        margin-top: 18px;
        padding-top: 14px;
        border-top: 1px solid #e5e7eb;
      }

      .jomelai-syllabus-section:first-child {
        margin-top: 0;
        padding-top: 0;
        border-top: 0;
      }

      .jomelai-syllabus-section h3 {
        margin: 0 0 10px;
        font-size: 15px;
        color: #0f2f57;
        font-weight: 850;
      }

      .jomelai-syllabus-section h4 {
        margin: 14px 0 8px;
        font-size: 13px;
        color: #174a7c;
        font-weight: 850;
      }

      .jomelai-syllabus-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 10px;
      }

      .jomelai-syllabus-field {
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        padding: 10px 12px;
        background: #f8fafc;
      }

      .jomelai-syllabus-label {
        font-size: 11px;
        color: #64748b;
        font-weight: 750;
        text-transform: uppercase;
        letter-spacing: .04em;
      }

      .jomelai-syllabus-value {
        margin-top: 4px;
        color: #1f2937;
        font-size: 13px;
        font-weight: 650;
      }

      .jomelai-syllabus-p {
        margin: 0;
        font-size: 13px;
        line-height: 1.65;
        color: #334155;
      }

      .jomelai-syllabus-list {
        margin: 0;
        padding-left: 18px;
        color: #334155;
        font-size: 13px;
        line-height: 1.55;
      }

      .jomelai-unit-card {
        margin-top: 12px;
        padding: 14px;
        border: 1px solid #e5e7eb;
        border-radius: 14px;
        background: #fbfdff;
      }

      .jomelai-unit-title {
        font-size: 14px;
        font-weight: 850;
        color: #0f2f57;
        margin-bottom: 8px;
      }

      .jomelai-table-wrap {
        width: 100%;
        overflow: auto;
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        margin-top: 10px;
      }

      .jomelai-syllabus-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        background: #ffffff;
      }

      .jomelai-syllabus-table th {
        background: #f8fafc;
        color: #334155;
        font-weight: 850;
        text-align: left;
        padding: 9px 10px;
        border-bottom: 1px solid #e5e7eb;
        white-space: nowrap;
      }

      .jomelai-syllabus-table td {
        padding: 8px 10px;
        border-bottom: 1px solid #eef2f7;
        vertical-align: top;
        color: #334155;
      }

      .jomelai-syllabus-actions {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        margin-top: 16px;
      }

      .jomelai-syllabus-btn {
        border: 1px solid #dbe3ef;
        background: #ffffff;
        color: #0f2f57;
        border-radius: 999px;
        padding: 8px 12px;
        font-size: 12px;
        font-weight: 800;
        cursor: pointer;
      }

      .jomelai-syllabus-btn:hover {
        background: #f1f5f9;
      }

      @media (max-width: 720px) {
        .jomelai-syllabus-grid {
          grid-template-columns: 1fr;
        }

        .jomelai-syllabus-header,
        .jomelai-syllabus-body {
          padding-left: 14px;
          padding-right: 14px;
        }
      }
    `;
    document.head.appendChild(style);
  }

  function renderList(items) {
    const values = arr(items).filter(x => x != null && String(x).trim() !== '');
    if (!values.length) return '<p class="jomelai-syllabus-p">No especificado.</p>';

    return '<ol class="jomelai-syllabus-list">' +
      values.map(x => '<li>' + esc(typeof x === 'string' ? x : JSON.stringify(x)) + '</li>').join('') +
      '</ol>';
  }

  function table(headers, rows) {
    return `
      <div class="jomelai-table-wrap">
        <table class="jomelai-syllabus-table">
          <thead>
            <tr>${headers.map(h => `<th>${esc(h.label)}</th>`).join('')}</tr>
          </thead>
          <tbody>
            ${rows.map(row => `
              <tr>
                ${headers.map(h => `<td>${esc(row[h.key] == null ? '' : row[h.key])}</td>`).join('')}
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  function renderDatos(dg) {
    dg = dg || {};

    const fields = [
      ['curso', 'Curso'],
      ['programa', 'Programa'],
      ['creditos', 'Créditos'],
      ['ciclo', 'Ciclo'],
      ['semanas', 'Semanas'],
      ['sesiones_por_semana', 'Sesiones por semana'],
      ['modalidad', 'Modalidad'],
      ['fecha_inicio', 'Fecha inicio'],
      ['fecha_fin', 'Fecha fin'],
      ['sistema_evaluacion', 'Sistema evaluación']
    ];

    return `
      <div class="jomelai-syllabus-grid">
        ${fields.map(([key, label]) => `
          <div class="jomelai-syllabus-field">
            <div class="jomelai-syllabus-label">${esc(label)}</div>
            <div class="jomelai-syllabus-value">${esc(dg[key] == null || dg[key] === '' ? 'No especificado' : dg[key])}</div>
          </div>
        `).join('')}
      </div>
    `;
  }

  function renderUnidades(unidades) {
    const list = arr(unidades);
    if (!list.length) return '<p class="jomelai-syllabus-p">No se generaron unidades.</p>';

    return list.map((u, idx) => {
      if (!u || typeof u !== 'object') return '';

      const sesiones = arr(u.sesiones);
      const sesionesTable = sesiones.length ? table(
        [
          { key: 'semana', label: 'Semana' },
          { key: 'sesion', label: 'Sesión' },
          { key: 'titulo', label: 'Título' },
          { key: 'actividad_aprendizaje', label: 'Actividad' },
          { key: 'producto', label: 'Producto' },
          { key: 'fecha_sugerida', label: 'Fecha' }
        ],
        sesiones.filter(x => x && typeof x === 'object')
      ) : '';

      return `
        <div class="jomelai-unit-card">
          <div class="jomelai-unit-title">
            Unidad ${esc(u.unidad || idx + 1)}: ${esc(u.titulo || 'Sin título')}
          </div>

          <p class="jomelai-syllabus-p"><strong>Semanas:</strong> ${esc(Array.isArray(u.semanas) ? u.semanas.join(', ') : (u.semanas || 'No especificado'))}</p>
          <p class="jomelai-syllabus-p"><strong>Resultado:</strong> ${esc(u.resultado_unidad || 'No especificado')}</p>

          <h4>Contenidos</h4>
          ${renderList(u.contenidos)}

          <h4>Sesiones</h4>
          ${sesionesTable || '<p class="jomelai-syllabus-p">No se generaron sesiones.</p>'}

          <h4>Producto de unidad</h4>
          <p class="jomelai-syllabus-p">${esc(u.producto_unidad || 'No especificado')}</p>
        </div>
      `;
    }).join('');
  }

  function renderEvaluaciones(evaluaciones) {
    const rows = arr(evaluaciones).filter(x => x && typeof x === 'object');

    if (!rows.length) return '<p class="jomelai-syllabus-p">No se generaron evaluaciones.</p>';

    return table(
      [
        { key: 'tipo', label: 'Tipo' },
        { key: 'descripcion', label: 'Descripción' },
        { key: 'evidencia', label: 'Evidencia' },
        { key: 'semana', label: 'Semana' },
        { key: 'puntaje_vigesimal', label: 'Puntaje' },
        { key: 'fecha_sugerida', label: 'Fecha' }
      ],
      rows
    );
  }

  function renderReferencias(refs) {
    const rows = arr(refs).filter(x => x && typeof x === 'object');

    if (!rows.length) return '<p class="jomelai-syllabus-p">No se generaron referencias.</p>';

    return table(
      [
        { key: 'autor', label: 'Autor' },
        { key: 'anio', label: 'Año' },
        { key: 'titulo', label: 'Título' },
        { key: 'fuente', label: 'Fuente' },
        { key: 'url', label: 'URL/DOI' },
        { key: 'utilidad', label: 'Utilidad' }
      ],
      rows
    );
  }

  function renderEnlaces(enlaces) {
    const rows = arr(enlaces).filter(x => x && typeof x === 'object');

    if (!rows.length) return '<p class="jomelai-syllabus-p">No se generaron enlaces.</p>';

    return table(
      [
        { key: 'titulo', label: 'Título' },
        { key: 'url', label: 'URL' },
        { key: 'uso', label: 'Uso' }
      ],
      rows
    );
  }

  function findMount() {
    const selectors = [
      '#syllabusResult',
      '#silaboResult',
      '#syllabus-output',
      '#silabo-output',
      '#generatedSyllabus',
      '#generated-syllabus',
      '.syllabus-result',
      '.silabo-result',
      '.syllabus-preview',
      '.silabo-preview',
      '.generated-syllabus',
      '[data-syllabus-output]',
      '[data-silabo-output]',
      '.page.active',
      '.tab-pane.active',
      '.content',
      'main'
    ];

    for (const selector of selectors) {
      const nodes = Array.from(document.querySelectorAll(selector)).filter(el => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });

      if (nodes.length) return nodes[nodes.length - 1];
    }

    return document.body;
  }

  function render(payload) {
    const syl = getSyllabus(payload);
    if (!syl) return false;

    injectStyles();

    const dg = syl.datos_generales || {};
    const course = dg.curso || syl.curso || 'Sílabo generado';
    const program = dg.programa || syl.programa || '';

    const card = document.createElement('div');
    card.className = 'jomelai-syllabus-card';
    card.dataset.jomelaiSyllabusRendered = '1';

    card.innerHTML = `
      <div class="jomelai-syllabus-header">
        <h2>${esc(course)}</h2>
        <p>${esc(program || 'Sílabo académico generado por JoMelAI')}</p>
      </div>

      <div class="jomelai-syllabus-body">
        <section class="jomelai-syllabus-section">
          <h3>I. Datos generales</h3>
          ${renderDatos(dg)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>II. Sumilla</h3>
          <p class="jomelai-syllabus-p">${esc(syl.sumilla || 'No especificado.')}</p>
        </section>

        <section class="jomelai-syllabus-section">
          <h3>III. Competencia del curso</h3>
          <p class="jomelai-syllabus-p">${esc(syl.competencia_curso || 'No especificado.')}</p>
        </section>

        <section class="jomelai-syllabus-section">
          <h3>IV. Resultados de aprendizaje</h3>
          ${renderList(syl.resultados_curso)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>V. Unidades de aprendizaje</h3>
          ${renderUnidades(syl.unidades)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>VI. Evaluaciones</h3>
          ${renderEvaluaciones(syl.evaluaciones)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>VII. Metodologías</h3>
          ${renderList(syl.metodologias)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>VIII. Referencias</h3>
          ${renderReferencias(syl.referencias)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>IX. Enlaces</h3>
          ${renderEnlaces(syl.enlaces)}
        </section>

        <div class="jomelai-syllabus-actions">
          <button class="jomelai-syllabus-btn" type="button" data-copy-syllabus>Copiar JSON</button>
          <button class="jomelai-syllabus-btn" type="button" data-copy-markdown>Copiar Markdown</button>
        </div>
      </div>
    `;

    const mount = findMount();

    Array.from(mount.querySelectorAll('.jomelai-syllabus-card[data-jomelai-syllabus-rendered="1"]')).forEach(x => x.remove());

    mount.appendChild(card);

    const copyJson = card.querySelector('[data-copy-syllabus]');
    if (copyJson) {
      copyJson.addEventListener('click', function () {
        navigator.clipboard && navigator.clipboard.writeText(JSON.stringify(syl, null, 2));
      });
    }

    const copyMd = card.querySelector('[data-copy-markdown]');
    if (copyMd) {
      copyMd.addEventListener('click', function () {
        const md = payload.markdown || payload.answer || '';
        navigator.clipboard && navigator.clipboard.writeText(md);
      });
    }

    try {
      card.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (e) {}

    return true;
  }

  function parseSseChunk(chunk) {
    const eventLine = chunk.split('\n').find(x => x.startsWith('event:'));
    const dataLine = chunk.split('\n').find(x => x.startsWith('data:'));

    if (!dataLine) return null;

    const event = eventLine ? eventLine.slice(6).trim() : 'message';

    try {
      return {
        event,
        data: JSON.parse(dataLine.slice(5).trim())
      };
    } catch (e) {
      return null;
    }
  }

  const oldFetch = window.fetch.bind(window);

  window.fetch = function syllabusFormatFetch(input, init) {
    const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
    const promise = oldFetch(input, init);

    if (url && url.includes('/api/assistant/generate-syllabus-stream')) {
      promise.then(res => {
        try {
          const clone = res.clone();
          const reader = clone.body && clone.body.getReader ? clone.body.getReader() : null;
          if (!reader) return;

          const decoder = new TextDecoder('utf-8');
          let buffer = '';

          function pump() {
            reader.read().then(({ done, value }) => {
              if (done) return;

              buffer += decoder.decode(value, { stream: true });

              const chunks = buffer.split('\n\n');
              buffer = chunks.pop() || '';

              for (const chunk of chunks) {
                const parsed = parseSseChunk(chunk);
                if (!parsed) continue;

                if (parsed.event === 'syllabus' || parsed.event === 'final') {
                  if (parsed.data && parsed.data.render_mode === 'syllabus_formatted') {
                    render(parsed.data);
                  } else if (getSyllabus(parsed.data)) {
                    render(parsed.data);
                  }
                }
              }

              pump();
            }).catch(() => {});
          }

          pump();
        } catch (e) {}
      }).catch(() => {});
    }

    return promise;
  };

  window.JoMelAiSyllabusFormatRenderer = {
    render,
    getSyllabus,
    version: 'v1'
  };

  console.info('[JoMelAi] Syllabus format renderer activo');
})();
JS

echo
echo "== 5) Copiando renderer a directorios públicos locales =="
for d in public frontend/public app/public web public_html; do
  if [ -d "$d" ]; then
    cp public/jomelai-syllabus-format-renderer.js "$d/jomelai-syllabus-format-renderer.js" || true
  fi
done

echo
echo "== 6) Configurando variables de velocidad =="
touch .env
cp .env "$BACKUP_DIR/.env.bak" || true

set_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s#^${key}=.*#${key}=${value}#g" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_env "SYLLABUS_OLLAMA_MODEL" "qwen2.5:0.5b"
set_env "SYLLABUS_NUM_CTX" "1536"
set_env "SYLLABUS_MAX_TOKENS" "1500"
set_env "SYLLABUS_TEMPERATURE" "0.18"
set_env "SYLLABUS_TOP_P" "0.80"
set_env "SYLLABUS_KEEP_ALIVE" "30m"
set_env "SYLLABUS_NUM_THREAD" "4"

echo
echo "== 7) Precalentando modelo Ollama =="
OLLAMA_CONTAINER="$(docker ps --format '{{.Names}} {{.Image}}' | grep -Ei 'ollama' | head -1 | awk '{print $1}' || true)"

if [ -n "$OLLAMA_CONTAINER" ]; then
  echo "OLLAMA_CONTAINER=$OLLAMA_CONTAINER"

  docker exec "$OLLAMA_CONTAINER" sh -lc '
    if ollama list | grep -q "qwen2.5:0.5b"; then
      echo "qwen2.5:0.5b ya existe."
    else
      echo "Descargando qwen2.5:0.5b..."
      ollama pull qwen2.5:0.5b
    fi

    echo "Warm-up..."
    curl -sS http://127.0.0.1:11434/api/generate \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"qwen2.5:0.5b\",\"prompt\":\"Responde OK\",\"stream\":false,\"keep_alive\":\"30m\",\"options\":{\"num_predict\":4}}" \
      | head -c 300 || true
    echo
  ' || true
else
  echo "WARN: no detecté contenedor Ollama."
fi

echo
echo "== 8) Rebuild/restart sin borrar volúmenes =="
docker compose up -d --build

sleep 4

echo
echo "== 9) Detectando frontend activo =="
FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|38764|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "WARN: no pude detectar frontend para inyectar renderer en index activo."
else
  echo "FRONT_CONTAINER=$FRONT_CONTAINER"

  CONTAINER_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
  if command -v nginx >/dev/null 2>&1; then
    nginx -T 2>/dev/null | awk "/root / {gsub(\";\", \"\", \$2); print \$2; exit}"
  fi
  ' || true)"

  if [ -z "$CONTAINER_ROOT" ]; then
    CONTAINER_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
    for d in /usr/share/nginx/html /app/dist /app/build /app/public /app/frontend/dist /app/frontend/public; do
      [ -d "$d" ] && echo "$d" && exit 0
    done
    echo /usr/share/nginx/html
    ' || true)"
  fi

  echo "CONTAINER_ROOT=$CONTAINER_ROOT"

  docker exec "$FRONT_CONTAINER" sh -lc "mkdir -p '$CONTAINER_ROOT'"
  docker cp public/jomelai-syllabus-format-renderer.js "$FRONT_CONTAINER:$CONTAINER_ROOT/jomelai-syllabus-format-renderer.js"

  INDEX_FILE="$(docker exec "$FRONT_CONTAINER" sh -lc "
  for f in '$CONTAINER_ROOT/index.html' /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html; do
    [ -f \"\$f\" ] && echo \"\$f\" && exit 0
  done
  exit 0
  " || true)"

  if [ -n "$INDEX_FILE" ]; then
    echo "INDEX_FILE=$INDEX_FILE"
    docker cp "$FRONT_CONTAINER:$INDEX_FILE" "$BACKUP_DIR/index.active.original.html"
    cp "$BACKUP_DIR/index.active.original.html" "$BACKUP_DIR/index.active.patched.html"

    python3 - "$BACKUP_DIR/index.active.patched.html" <<'PY'
from pathlib import Path
import sys
import time

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

lines = [ln for ln in text.splitlines() if "jomelai-syllabus-format-renderer.js" not in ln]
text = "\n".join(lines)

tag = f'  <script src="/jomelai-syllabus-format-renderer.js?v={int(time.time())}"></script>'

if "</body>" in text:
    text = text.replace("</body>", tag + "\n</body>")
else:
    text += "\n" + tag + "\n"

p.write_text(text, encoding="utf-8")
PY

    docker cp "$BACKUP_DIR/index.active.patched.html" "$FRONT_CONTAINER:$INDEX_FILE"

    docker exec "$FRONT_CONTAINER" sh -lc "grep -n 'jomelai-syllabus-format-renderer' '$INDEX_FILE' || true"

    docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true
  else
    echo "WARN: no encontré index.html activo dentro del frontend."
  fi
fi

echo
echo "== 10) Test público del renderer asset =="
curl -sS -I "http://localhost:3000/jomelai-syllabus-format-renderer.js?v=test" || true

echo
echo
echo "== 11) Test del endpoint real =="
echo "Si responde 401 en curl, es normal si requiere sesión; en navegador autenticado debe funcionar."

time curl -sS -N -m 100 -X POST http://localhost:3000/api/assistant/generate-syllabus-stream \
  -H "Content-Type: application/json" \
  -d '{
    "course": "Investigación",
    "program": "Ingeniería de Sistemas",
    "credits": "3",
    "cycle": "VIII",
    "weeks": 16,
    "sessions_per_week": 1,
    "modality": "Presencial",
    "model": "qwen2.5:0.5b",
    "max_tokens": 1500,
    "num_ctx": 1536,
    "temperature": 0.18
  }' | head -c 3500 || true

echo
echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Ahora haz hard refresh:"
echo "  Ctrl + Shift + R"
echo
echo "En consola del navegador debe aparecer:"
echo "  [JoMelAi] Syllabus format renderer activo"
echo
echo "En Network, el evento final debe traer:"
echo "  render_mode: syllabus_formatted"
echo "  parse_ok: true"
echo "  syllabus: {...}"
echo "  markdown: ..."
