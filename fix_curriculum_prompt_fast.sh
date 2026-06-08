#!/usr/bin/env bash
set -euo pipefail

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

echo "==> Buscando CurriculumController.php..."

CANDIDATES="
backend/api/CurriculumController.php
backend/api/Controllers.php
backend/src/CurriculumController.php
api/CurriculumController.php
src/CurriculumController.php
"

TARGET=""

for f in $CANDIDATES; do
  if [ -f "$f" ] && grep -q "class CurriculumController" "$f"; then
    TARGET="$f"
    break
  fi
done

if [ -z "$TARGET" ]; then
  TARGET="$(grep -R "class CurriculumController" -n backend api src 2>/dev/null | head -1 | cut -d: -f1 || true)"
fi

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  echo "ERROR: No encontré el archivo que contiene class CurriculumController."
  echo "Ejecuta:"
  echo "grep -R \"class CurriculumController\" -n ."
  exit 1
fi

echo "==> Archivo encontrado: $TARGET"

if grep -q "function buildPlanReviewPromptFast" "$TARGET"; then
  echo "OK: El método buildPlanReviewPromptFast ya existe. No se modifica."
else
  BACKUP="${TARGET}.bak_$(date +%Y%m%d_%H%M%S)"
  cp "$TARGET" "$BACKUP"
  echo "==> Backup creado: $BACKUP"

  python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

method = r'''
    /**
     * Prompt rápido para revisión generativa de planes curriculares.
     *
     * Este método existe como versión compacta para evitar timeouts largos
     * en Ollama y para no bloquear la API. Acepta argumentos variables porque
     * distintas versiones del controlador pueden llamarlo con firmas diferentes.
     */
    private function buildPlanReviewPromptFast(...$args): string
    {
        $payload = [];

        foreach ($args as $index => $arg) {
            if (is_array($arg) || is_object($arg)) {
                $payload['arg_' . $index] = $arg;
            } else {
                $payload['arg_' . $index] = (string)$arg;
            }
        }

        $json = json_encode(
            $payload,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT
        );

        if ($json === false || trim((string)$json) === '') {
            $json = '{}';
        }

        return
            "Eres JoMelAI Curriculista UPeU. Revisa el siguiente plan curricular de forma breve, técnica y accionable.\n\n" .
            "Criterios obligatorios:\n" .
            "1. No inventes datos que no estén en el payload.\n" .
            "2. Identifica fortalezas curriculares.\n" .
            "3. Identifica riesgos o vacíos: créditos, horas, ciclos, prerrequisitos, progresión, perfil de egreso, competencias y evidencias.\n" .
            "4. Sugiere mejoras concretas y priorizadas.\n" .
            "5. Usa lenguaje académico sobrio, compatible con una institución adventista.\n" .
            "6. Responde máximo en 900 palabras.\n\n" .
            "Formato de respuesta:\n" .
            "## Revisión rápida del plan\n" .
            "### Fortalezas\n" .
            "### Alertas curriculares\n" .
            "### Recomendaciones priorizadas\n" .
            "### Siguiente acción sugerida\n\n" .
            "Payload del plan:\n" .
            $json;
    }

'''

# Insertar antes del último cierre de la clase.
pos = text.rfind("\n}")
if pos == -1:
    print("ERROR: No pude ubicar el cierre final de la clase.")
    sys.exit(1)

new_text = text[:pos] + "\n" + method + text[pos:]
path.write_text(new_text, encoding="utf-8")
print("OK: Método buildPlanReviewPromptFast insertado.")
PY
fi

echo "==> Validando sintaxis PHP local..."
php -l "$TARGET"

echo "==> Reconstruyendo backend..."
$DC build backend

echo "==> Reiniciando backend..."
$DC up -d backend

echo "==> Validando que el método exista dentro del contenedor..."
$DC exec -T backend sh -lc "grep -R 'function buildPlanReviewPromptFast' -n /var/www/app /app /var/www/html 2>/dev/null | head -20"

echo "==> Últimos logs backend..."
$DC logs --tail=80 backend

echo "==> FIX COMPLETADO."
