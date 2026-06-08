#!/usr/bin/env sh
set -eu
printf 'Host frontend/index.html: '
ls -lh frontend/index.html
printf '\nNginx container frontend mount:\n'
docker compose exec nginx sh -lc 'ls -lh /usr/share/nginx/html/index.html /usr/share/nginx/html/favicon.ico 2>/dev/null || true; nginx -T | sed -n "1,180p"'
