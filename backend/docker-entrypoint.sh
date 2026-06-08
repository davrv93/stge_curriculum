#!/usr/bin/env sh
set -eu

# JoMelAI safe storage bootstrap
# This script only creates missing folders/files in bind-mounted storage.
# It never removes DuckDB, Ollama models, syllabi or backend data.

APP_STORAGE="${APP_STORAGE:-/var/www/app/storage}"
SHARED_CSV_DIR="${SHARED_CSV_DIR:-/data/syllabi}"

mkdir -p \
  "$APP_STORAGE" \
  "$APP_STORAGE/db" \
  "$APP_STORAGE/sessions" \
  "$APP_STORAGE/uploads" \
  "$APP_STORAGE/reports" \
  "$APP_STORAGE/cache" \
  "$APP_STORAGE/jobs" \
  "$APP_STORAGE/rag" \
  "$APP_STORAGE/tmp" \
  "$SHARED_CSV_DIR"

# Ensure SQLite file exists. Do not overwrite it if it already has data.
if [ ! -f "$APP_STORAGE/db/app.sqlite" ]; then
  touch "$APP_STORAGE/db/app.sqlite"
fi

# Make bind-mounted storage writable inside the PHP container.
# chown may fail on some host filesystems; chmod fallback still helps.
chown -R www-data:www-data "$APP_STORAGE" "$SHARED_CSV_DIR" 2>/dev/null || true
chmod -R ug+rwX "$APP_STORAGE" "$SHARED_CSV_DIR" 2>/dev/null || true

exec "$@"
