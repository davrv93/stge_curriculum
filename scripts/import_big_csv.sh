#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/upeu_silabo_ai.sh" duckdb "${1:-/data/syllabi/silabos.csv}"
