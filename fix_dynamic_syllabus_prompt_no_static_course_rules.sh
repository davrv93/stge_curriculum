#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"

echo "=================================================="
echo " Fix dynamic syllabus prompt: no static course rules"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: ejecuta este script desde la carpeta donde esta docker-compose.yml o compose.yml"
  exit 1
fi

BACKUP_DIR="backups/fix_dynamic_syllabus_prompt_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

TARGET_MODEL="${1:-llama3.2:1b}"

echo "TARGET_MODEL=$TARGET_MODEL"
echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Buscando PHP real del stream de silabo =="

PHP_FILE="$(grep -Rsl "function jm_handle_syllabus_stream" . \
  --include='*.php' \
  --exclude-dir=.git \
  --exclude-dir=vendor \
  --exclude-dir=node_modules \
  --exclude-dir=data \
  --exclude-dir=datasets \
  --exclude-dir=backups \
  --exclude='*.bak*' \
  | head -1 || true)"

if [ -z "$PHP_FILE" ] || [ ! -f "$PHP_FILE" ]; then
  echo "ERROR: no encontre el PHP con jm_handle_syllabus_stream."
  grep -R "function jm_handle_syllabus_stream" -n . --include='*.php' || true
  exit 1
fi

echo "PHP_FILE=$PHP_FILE"
cp "$PHP_FILE" "$BACKUP_DIR/$(basename "$PHP_FILE").bak"

echo
echo "== 2) Eliminando reglas estaticas por nombre de curso =="

python3 - "$PHP_FILE" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

start = text.find("function jm_handle_syllabus_stream()")
if start == -1:
    raise SystemExit("No encontre function jm_handle_syllabus_stream().")

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
    raise SystemExit("No pude detectar el final de jm_handle_syllabus_stream().")

end = min(positions)

before = text[:start]
func = text[start:end]
after = text[end:]

# 1) Quitar bloque estatico:
#    $courseLower = ...
#    $domainHint = ...
#    if (strpos(...)) ...
#    elseif ...
#    else ...
if "$courseLower =" in func and "$profilePrompt =" in func:
    a = func.find("    $courseLower =")
    b = func.find("    $profilePrompt =", a)

    if a != -1 and b != -1 and b > a:
        dynamic_block = r'''    $disciplineInstruction =
        "INFERENCIA DISCIPLINAR DINAMICA:\n" .
        "No uses reglas hardcodeadas por nombre de curso. No dependas de listas internas de cursos.\n" .
        "Analiza semanticamente el nombre del curso, programa, ciclo, creditos, perfil de egreso y competencia declarada.\n" .
        "Primero identifica mentalmente el campo disciplinar, los ejes tematicos naturales, la progresion de aprendizaje y las aplicaciones profesionales.\n" .
        "Luego construye unidades, sesiones, actividades, productos y evaluaciones directamente relacionadas con esa disciplina.\n" .
        "Si el curso es ambiguo, usa el programa y la competencia para desambiguar.\n" .
        "No sustituyas el curso por otro campo. No inventes temas ajenos al nombre del curso.\n";

'''
        func = func[:a] + dynamic_block + func[b:]
    else:
        raise SystemExit("Detecte courseLower, pero no pude ubicar profilePrompt para reemplazar el bloque.")
else:
    if "$disciplineInstruction =" not in func:
        needle = "    $profilePrompt ="
        pos = func.find(needle)
        if pos == -1:
            raise SystemExit("No encontre donde insertar disciplineInstruction.")
        dynamic_block = r'''    $disciplineInstruction =
        "INFERENCIA DISCIPLINAR DINAMICA:\n" .
        "No uses reglas hardcodeadas por nombre de curso. Analiza semanticamente curso, programa, ciclo, creditos, perfil de egreso y competencia.\n" .
        "Identifica campo disciplinar, ejes tematicos, progresion y aplicaciones profesionales. Genera contenido propio de esa asignatura.\n";

'''
        func = func[:pos] + dynamic_block + func[pos:]

# 2) Cambiar usos antiguos de $domainHint.
func = func.replace("$domainHint .", "$disciplineInstruction .")
func = func.replace("$domainHint.", "$disciplineInstruction.")

# 3) Reforzar reglas de calidad en el prompt.
old_rules = '''        "REGLAS CRÍTICAS DE CALIDAD:\\n" .
        "1. Prohibido usar textos de relleno o placeholders.\\n" .
        "2. Prohibido escribir estas frases o variantes: resultado de aprendizaje real, contenido real, tema real, actividad concreta, producto o evidencia, criterio real, producto integrador real, semana o fecha, fecha o semana sugerida, Juan Pérez, Editorial de Matemáticas, recursoenlinea.com.\\n" .
        "3. Cada unidad debe tener contenidos disciplinares concretos del curso.\\n" .
        "4. Cada sesión debe tener un tema académico específico, una actividad de aprendizaje aplicable y un producto verificable.\\n" .
        "5. Las evaluaciones deben medir desempeño real, con criterios observables.\\n" .
        "6. Las referencias deben ser plausibles y académicas. No inventes URL falsas. Si no conoces una URL exacta, deja url como cadena vacía.\\n" .
        "7. Si el usuario dio perfil de egreso y competencia, articula el sílabo con esos textos.\\n" .
        "8. Usa español académico claro, no lenguaje genérico.\\n\\n" .'''

new_rules = '''        "REGLAS CRITICAS DE CALIDAD:\\n" .
        "1. Prohibido usar textos de relleno, plantillas visibles o placeholders.\\n" .
        "2. Prohibido escribir estas frases o variantes: resultado de aprendizaje real, contenido real, tema real, actividad concreta, producto o evidencia, criterio real, producto integrador real, semana o fecha, fecha o semana sugerida, Juan Perez, Editorial de Matematicas, recursoenlinea.com.\\n" .
        "3. No uses mapas estaticos del tipo: si el curso contiene X entonces usa Y. El contenido debe nacer del analisis semantico del curso y del programa.\\n" .
        "4. Cada unidad debe tener contenidos disciplinares concretos del curso solicitado, con progresion logica de menor a mayor complejidad.\\n" .
        "5. Cada sesion debe tener un tema academico especifico, actividad aplicable y producto verificable.\\n" .
        "6. Las evaluaciones deben medir desempeno real con criterios observables.\\n" .
        "7. Las referencias deben ser plausibles y academicas. No inventes URLs falsas. Si no conoces una URL exacta, deja url como cadena vacia.\\n" .
        "8. Si el usuario dio perfil de egreso y competencia, articula todo el silabo con esos textos.\\n" .
        "9. Usa espanol academico claro, especifico y contextualizado.\\n\\n" .'''

if old_rules in func:
    func = func.replace(old_rules, new_rules)
elif '"REGLAS CRÍTICAS DE CALIDAD' in func or '"REGLAS CRITICAS DE CALIDAD' in func:
    # No tocar si la estructura vario demasiado; agregamos bloque adicional antes de ESTRUCTURA JSON.
    marker = '''        "ESTRUCTURA JSON OBLIGATORIA:\\n" .'''
    if marker in func and "No uses mapas estaticos" not in func:
        extra = '''        "REGLAS ADICIONALES DINAMICAS:\\n" .
        "- No uses mapas estaticos del tipo: si el curso contiene X entonces usa Y.\\n" .
        "- Infiere semanticamente la disciplina desde curso, programa, perfil y competencia.\\n" .
        "- Cada tema, actividad, producto y evaluacion debe ser propio de la asignatura solicitada.\\n\\n" .

'''
        func = func.replace(marker, extra + marker, 1)

# 4) Agregar reparacion automatica si el modelo devuelve placeholders.
repair_marker = "    $syllabus = jm_real_syllabus_extract_json($answer);"

if repair_marker in func and "SYLLABUS_QUALITY_REPAIR" not in func:
    repair_code = r'''    $badMarkers = [
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

    $answerLower = function_exists('mb_strtolower')
        ? mb_strtolower($answer, 'UTF-8')
        : strtolower($answer);

    $needsRepair = false;

    foreach ($badMarkers as $badMarker) {
        $badLower = function_exists('mb_strtolower')
            ? mb_strtolower($badMarker, 'UTF-8')
            : strtolower($badMarker);

        if (strpos($answerLower, $badLower) !== false) {
            $needsRepair = true;
            break;
        }
    }

    if ($needsRepair && jm_real_syllabus_bool('SYLLABUS_QUALITY_REPAIR', true)) {
        jm_sse_send('quality_repair', [
            'ok' => true,
            'message' => 'Se detecto relleno o placeholder. Reescribiendo el silabo con contenido disciplinar real.',
        ]);

        $repairPrompt =
            "Reescribe el siguiente JSON de silabo. Debe conservar la estructura JSON, pero reemplazar todo relleno por contenido academico real.\\n" .
            "No uses placeholders. No uses frases como contenido real, tema real, resultado real, actividad concreta, producto o evidencia, criterio real.\\n" .
            "No uses reglas hardcodeadas por curso. Infiere semanticamente la disciplina desde estos datos:\\n" .
            "Curso: {$course}\\n" .
            "Programa: {$program}\\n" .
            "Creditos: {$credits}\\n" .
            "Ciclo: {$cycle}\\n" .
            "Semanas: {$weeks}\\n" .
            $profilePrompt .
            $competencyPrompt .
            $disciplineInstruction .
            "\\nJSON defectuoso a corregir:\\n" .
            $answer .
            "\\n\\nDevuelve SOLO JSON valido corregido.";

        $answer = jm_real_syllabus_generate(
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

'''
    func = func.replace(repair_marker, repair_code + repair_marker, 1)

text = before + func + after

p.write_text(text, encoding="utf-8")
PY

echo
echo "== 3) Validando que ya no haya logica estatica tipo courseLower/domainHint =="

grep -n "courseLower\|domainHint\|strpos(\$courseLower\|INFERENCIA DISCIPLINAR" "$PHP_FILE" || true

if grep -q "strpos(\$courseLower" "$PHP_FILE"; then
  echo "ERROR: aun existe logica estatica por curso."
  exit 1
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
echo "== 6) Reiniciando/reconstruyendo sin borrar volumenes =="

docker compose up -d --build

sleep 6

echo
echo "== 7) Test rapido del endpoint con curso dinamico =="

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
    "competency": "Aplica límites, continuidad y derivadas para modelar, analizar y resolver problemas de cambio y optimización en contextos de ingeniería.",
    "start_date": "",
    "sessions_per_week": "1"
  }' | grep -E "event: model_resolved|event: config|quality_repair|render_mode|real_academic_content_v2|contenido real|resultado de aprendizaje real|tema real|Juan|teoria de los numeros|teoría de los números|limite|límite|derivada|optimización|funciones" | head -100 || true

echo
echo
echo "== 8) Git status =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Se elimino la inferencia estatica por nombre de curso."
echo
echo "Ahora el prompt usa:"
echo "  INFERENCIA DISCIPLINAR DINAMICA"
echo
echo "Y activa reparacion automatica si aparecen placeholders:"
echo "  SYLLABUS_QUALITY_REPAIR=1"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Haz hard refresh en navegador:"
echo "  Ctrl + Shift + R"
