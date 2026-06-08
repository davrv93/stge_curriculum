#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"

echo "==> Buscando archivo que genera la orientación unknown"

TARGET_FILE="$(grep -R -l "Puedo ayudarte a buscar información en sílabos" backend 2>/dev/null | head -1 || true)"

if [ -z "$TARGET_FILE" ]; then
  TARGET_FILE="$(grep -R -l "visible_intent.*Orientación\|Orientación" backend 2>/dev/null | head -1 || true)"
fi

if [ -z "$TARGET_FILE" ]; then
  echo "ERROR: No encontré el archivo que genera la orientación."
  echo "Ejecuta:"
  echo "grep -R \"Puedo ayudarte a buscar\" -n backend"
  echo "grep -R \"Orientación\" -n backend"
  exit 1
fi

echo "Archivo detectado: $TARGET_FILE"
cp "$TARGET_FILE" "$TARGET_FILE.bak.$TS"
echo "Backup: $TARGET_FILE.bak.$TS"

echo "==> Parcheando clasificador/controller para datos académicos"

python3 - "$TARGET_FILE" <<'PY'
from pathlib import Path
import sys
import re

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

helper = r'''
    private function looksLikeAcademicLoadedDataQuestion(string $question): bool
    {
        $q = Support::normalize($question);

        $actionTokens = [
            'que', 'qué', 'cuales', 'cuáles', 'lista', 'listar', 'listame',
            'listarme', 'muestrame', 'muéstrame', 'mostrar', 'dame', 'ver',
            'cuantos', 'cuántos', 'cuantas', 'cuántas', 'consulta', 'consultar',
            'grafico', 'gráfico', 'grafica', 'gráfica'
        ];

        $domainTokens = [
            'carrera', 'carreras', 'programa', 'programas', 'escuela', 'escuelas',
            'curso', 'cursos', 'silabo', 'sílabo', 'silabos', 'sílabos',
            'facultad', 'facultades', 'ciclo', 'ciclos', 'credito', 'crédito',
            'creditos', 'créditos', 'hora', 'horas', 'sumilla', 'sumillas',
            'enfermeria', 'enfermería', 'sistemas', 'administracion',
            'administración', 'negocios internacionales', 'malla', 'mallas',
            'plan de estudios'
        ];

        $loadedTokens = [
            'cargada', 'cargadas', 'cargado', 'cargados', 'tienes',
            'registrada', 'registradas', 'registrado', 'registrados',
            'disponible', 'disponibles', 'en la base', 'en duckdb'
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

    private function academicLoadedDataIntent(string $question): array
    {
        $q = Support::normalize($question);

        $isChart = false;
        foreach (['grafico', 'gráfico', 'grafica', 'gráfica', 'barras', 'pie', 'pastel', 'torta'] as $token) {
            if (str_contains($q, Support::normalize($token))) {
                $isChart = true;
                break;
            }
        }

        return [
            'ok' => true,
            'intent' => $isChart ? 'chart' : 'statistics',
            'visible_intent' => $isChart ? 'Generar gráfico' : 'Consultar datos académicos',
            'mode' => $isChart ? 'chart' : 'data',
            'collection' => Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge',
            'confidence' => 0.98,
            'summary' => 'Consulta académica estructurada detectada. Se usará DuckDB/FastIntent y, si no alcanza, RAG con JoMelAI.',
            'answer' => '',
            'suggestions' => [],
        ];
    }

'''

# 1) Insertar helpers antes del último cierre de clase, si no existen.
if "looksLikeAcademicLoadedDataQuestion" not in s:
    last_brace = s.rfind("}")
    if last_brace == -1:
        raise SystemExit("No encontré cierre de clase para insertar helpers.")
    s = s[:last_brace] + "\n" + helper + "\n" + s[last_brace:]
    print("OK helpers insertados")
else:
    print("OK helpers ya existían")

# 2) Insertar guard al inicio de métodos probables: classify, detect, resolve, handle.
method_names = ["classify", "detect", "resolve", "handle", "intent", "analyze"]
inserted = False

guard = r'''
        if (isset($question) && is_string($question) && $this->looksLikeAcademicLoadedDataQuestion($question)) {
            return $this->academicLoadedDataIntent($question);
        }

'''

def find_method_bounds(src: str, method_name: str):
    m = re.search(rf"\b(public|private|protected)\s+function\s+{re.escape(method_name)}\s*\([^)]*\)\s*(?::\s*[^\{{]+)?\s*\{{", src)
    if not m:
        return None

    start_body = src.find("{", m.start())
    return m.start(), start_body + 1

for name in method_names:
    found = find_method_bounds(s, name)
    if not found:
        continue

    _, insert_pos = found

    # Solo insertar si dentro de la función no existe ya el guard cerca.
    window = s[insert_pos:insert_pos + 800]
    if "looksLikeAcademicLoadedDataQuestion" not in window:
        s = s[:insert_pos] + "\n" + guard + s[insert_pos:]
        inserted = True
        print(f"OK guard insertado en método {name}()")
        break

if not inserted:
    print("AVISO: No pude insertar guard en método típico.")
    print("Se aplicaron helpers, pero quizá hay que parchear manualmente el controller.")

p.write_text(s, encoding="utf-8")
PY

echo "==> Asegurando config jomelai_rag_collection"

if [ -f "backend/config/app.php" ]; then
  cp "backend/config/app.php" "backend/config/app.php.bak.$TS"

  python3 - <<'PY'
from pathlib import Path

p = Path("backend/config/app.php")
s = p.read_text(encoding="utf-8")

line = "    'jomelai_rag_collection' => getenv('JOMELAI_RAG_COLLECTION') ?: 'jomelai_knowledge',\n"

if "'jomelai_rag_collection'" not in s:
    pos = s.rfind("];")
    if pos != -1:
        s = s[:pos] + line + s[pos:]
        p.write_text(s, encoding="utf-8")
        print("OK app.php actualizado")
    else:
        print("AVISO: no encontré ]; en app.php")
else:
    print("OK app.php ya tenía jomelai_rag_collection")
PY
fi

echo "==> Agregando JOMELAI_RAG_COLLECTION al .env"

touch .env

if ! grep -q "^JOMELAI_RAG_COLLECTION=" .env; then
  echo "JOMELAI_RAG_COLLECTION=jomelai_knowledge" >> .env
else
  python3 - <<'PY'
from pathlib import Path
p = Path(".env")
s = p.read_text(encoding="utf-8")
lines = []
for line in s.splitlines():
    if line.startswith("JOMELAI_RAG_COLLECTION="):
        lines.append("JOMELAI_RAG_COLLECTION=jomelai_knowledge")
    else:
        lines.append(line)
p.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY
fi

echo "==> Reconstruyendo backend"

docker compose build --no-cache backend
docker compose up -d --force-recreate backend

echo "==> Validando PHP dentro del contenedor"

CONTAINER_TARGET="$(docker compose exec -T backend sh -lc "grep -R -l 'looksLikeAcademicLoadedDataQuestion' /var/www/app /app /var/www/html 2>/dev/null | head -1" || true)"

if [ -n "$CONTAINER_TARGET" ]; then
  docker compose exec -T backend php -l "$CONTAINER_TARGET"
else
  echo "AVISO: No encontré el archivo parcheado dentro del contenedor."
fi

echo "==> Mostrando archivo parcheado"
grep -R "looksLikeAcademicLoadedDataQuestion\|academicLoadedDataIntent" -n backend | head -20 || true

echo ""
echo "============================================================"
echo "Patch aplicado."
echo "Prueba otra vez:"
echo '{"question":"que carreras tienes cargadas","context":"user","options":{"table":"silabos"}}'
echo "============================================================"
