#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMIT="2000"
if [ "${1:-}" != "" ]; then
  case "$1" in
    *[!0-9]*) LIMIT="${2:-2000}" ;;
    *) LIMIT="$1" ;;
  esac
fi
"$DIR/upeu_silabo_ai.sh" rag-sample "$LIMIT"
