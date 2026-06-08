#!/usr/bin/env bash
set -euo pipefail

APP_FILE="data-engine/app.py"
TS="$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$APP_FILE" ]; then
  echo "ERROR: No existe $APP_FILE"
  echo "Ejecuta este script desde la raíz del proyecto."
  exit 1
fi

echo "==> Backup"
cp "$APP_FILE" "$APP_FILE.bak.$TS"
echo "Backup creado: $APP_FILE.bak.$TS"

echo "==> Parcheando $APP_FILE"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("data-engine/app.py")
text = path.read_text(encoding="utf-8")

patch_block = '''
def _duckdb_numeric_expr(col: str) -> str:
    """
    Convierte columnas VARCHAR institucionales a DOUBLE de forma tolerante.
    Soporta números con coma decimal, símbolos, espacios y valores vacíos.
    """
    ident = q_ident(col)
    return (
        f"TRY_CAST(NULLIF("
        f"REPLACE("
        f"REGEXP_REPLACE(CAST({ident} AS VARCHAR), '[^0-9,.-]', '', 'g'), "
        f"',', '.'"
        f"), "
        f"''"
        f") AS DOUBLE)"
    )


def _table_column_names(table: str) -> List[str]:
    try:
        return [str(c.get("name")) for c in table_columns(table)]
    except Exception:
        return []


def _norm_identifier(value: str) -> str:
    repl = str.maketrans("áéíóúüñÁÉÍÓÚÜÑ", "aeiouunAEIOUUN")
    value = str(value or "").strip().lower().translate(repl)
    value = re.sub(r"[^a-z0-9]+", "_", value).strip("_")
    return value


def _column_lookup(table: str) -> Dict[str, str]:
    cols = _table_column_names(table)
    return {_norm_identifier(c): c for c in cols}


def repair_sql_for_table(sql: str, table: str = DEFAULT_TABLE) -> str:
    """
    Repara SQL generado por Ollama/FastIntent cuando inventa nombres de columnas.
    Ejemplo: creditos_practicas -> horas_practicas si existe.
    """
    repaired = str(sql or "")
    lookup = _column_lookup(table)

    alias_candidates = {
        "creditos_practica": ["horas_practicas", "creditos"],
        "creditos_practicas": ["horas_practicas", "creditos"],
        "creditos_practico": ["horas_practicas", "creditos"],
        "creditos_practicos": ["horas_practicas", "creditos"],

        "creditos_teorica": ["horas_teoricas", "creditos"],
        "creditos_teoricas": ["horas_teoricas", "creditos"],
        "creditos_teorico": ["horas_teoricas", "creditos"],
        "creditos_teoricos": ["horas_teoricas", "creditos"],

        "escuela": ["programa_estudio", "programa", "carrera", "facultad"],
        "carrera": ["programa_estudio", "programa", "escuela", "facultad"],
        "programa": ["programa_estudio", "programa", "carrera", "facultad"],

        "horas_total": ["horas_totales", "horas_total", "horas_practicas", "horas_teoricas"],
        "horas_totales": ["horas_totales", "horas_total", "horas_practicas", "horas_teoricas"],
        "total_creditos": ["creditos"],
    }

    for wrong, candidates in alias_candidates.items():
        replacement = None
        for cand in candidates:
            cand_norm = _norm_identifier(cand)
            if cand_norm in lookup:
                replacement = lookup[cand_norm]
                break

        if not replacement:
            continue

        repaired = re.sub(rf"\\b{re.escape(wrong)}\\b", replacement, repaired, flags=re.I)
        repaired = re.sub(rf'"{re.escape(wrong)}"', q_ident(replacement), repaired, flags=re.I)

    return repaired


def patch_numeric_sql(sql: str, table: str = DEFAULT_TABLE) -> str:
    """
    Fuerza agregaciones numéricas seguras en DuckDB:
      SUM(creditos) -> SUM(TRY_CAST(... AS DOUBLE))
      AVG(horas_practicas) -> AVG(TRY_CAST(... AS DOUBLE))
    """
    patched = str(sql or "")
    cols = _table_column_names(table)

    numeric_like = []
    for c in cols:
        n = _norm_identifier(c)
        if (
            "credito" in n
            or "hora" in n
            or n in {"ciclo", "semestre", "nivel", "orden", "cantidad", "total"}
            or n.startswith("nro")
            or n.startswith("num")
        ):
            numeric_like.append(c)

    for c in [
        "creditos",
        "horas_teoricas",
        "horas_practicas",
        "horas_totales",
        "horas_total",
        "ciclo",
    ]:
        if c not in numeric_like:
            numeric_like.append(c)

    for col in sorted(set(numeric_like), key=len, reverse=True):
        expr = _duckdb_numeric_expr(col)

        for fn in ["SUM", "AVG", "MIN", "MAX"]:
            patched = re.sub(
                rf"\\b{fn}\\s*\\(\\s*{re.escape(col)}\\s*\\)",
                f"{fn}({expr})",
                patched,
                flags=re.I,
            )
            patched = re.sub(
                rf'\\b{fn}\\s*\\(\\s*"{re.escape(col)}"\\s*\\)',
                f"{fn}({expr})",
                patched,
                flags=re.I,
            )

        for op in [">=", "<=", ">", "<"]:
            patched = re.sub(
                rf"\\b{re.escape(col)}\\s*{re.escape(op)}\\s*('?\\d+(?:[.,]\\d+)?'?)",
                lambda m, expr=expr, op=op: f"{expr} {op} {m.group(1)}",
                patched,
                flags=re.I,
            )

    return patched
'''.strip()


def replace_between(source: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = source.find(start_marker)
    if start == -1:
        raise SystemExit(f"No encontré inicio: {start_marker}")

    end = source.find(end_marker, start)
    if end == -1:
        raise SystemExit(f"No encontré fin: {end_marker}")

    return source[:start] + replacement + "\\n\\n" + source[end:]


# 1) Reemplaza patch_numeric_sql antiguo y conserva chart_png_base64.
text = replace_between(
    text,
    "def patch_numeric_sql",
    "def chart_png_base64",
    patch_block
)

# 2) Asegura que intent_resolve repare columnas inventadas y castee numéricos.
text = text.replace(
    'result["sql"] = safe_select_sql(str(sql))',
    'result["sql"] = patch_numeric_sql(repair_sql_for_table(safe_select_sql(str(sql)), req.table or DEFAULT_TABLE), req.table or DEFAULT_TABLE)'
)

# 3) Asegura que duck_query use reparación + cast.
text = text.replace(
    'sql = patch_numeric_sql(safe_select_sql(req.sql))',
    'sql = patch_numeric_sql(repair_sql_for_table(safe_select_sql(req.sql), DEFAULT_TABLE), DEFAULT_TABLE)'
)

# 4) Asegura que duck_chart use reparación + cast.
text = text.replace(
    'sql = patch_numeric_sql(safe_select_sql(req.sql))',
    'sql = patch_numeric_sql(repair_sql_for_table(safe_select_sql(req.sql), DEFAULT_TABLE), DEFAULT_TABLE)'
)

# 5) Reemplaza duck_query completo con manejo de error JSON.
duck_query_start = text.find('@api.post("/duckdb/query")')
duck_chart_start = text.find('@api.post("/duckdb/chart")')

if duck_query_start != -1 and duck_chart_start != -1 and duck_chart_start > duck_query_start:
    new_duck_query = '''
@api.post("/duckdb/query")
def duck_query(req: DuckQueryRequest) -> Dict[str, Any]:
    sql = patch_numeric_sql(repair_sql_for_table(safe_select_sql(req.sql), DEFAULT_TABLE), DEFAULT_TABLE)
    limit = min(int(req.limit), MAX_QUERY_LIMIT)
    wrapped = f"SELECT * FROM ({sql}) AS q LIMIT {limit}"
    started = time.time()
    cx = con()
    try:
        cur = cx.execute(wrapped)
        rows = cur.fetchall()
        result = rows_to_dicts(cur, rows)
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "DuckDB no pudo ejecutar la consulta.",
                "error": str(exc),
                "sql": sql,
                "columns": _table_column_names(DEFAULT_TABLE),
            },
        )
    finally:
        cx.close()

    return {
        "ok": True,
        "sql": sql,
        "limit": limit,
        "rows": result,
        "row_count": len(result),
        "seconds": round(time.time() - started, 3),
    }


'''.lstrip()

    text = text[:duck_query_start] + new_duck_query + text[duck_chart_start:]

# 6) Reemplaza duck_chart completo hasta duck_preview.
duck_chart_start = text.find('@api.post("/duckdb/chart")')
duck_preview_start = text.find('@api.get("/duckdb/preview")')

if duck_chart_start != -1 and duck_preview_start != -1 and duck_preview_start > duck_chart_start:
    new_duck_chart = '''
@api.post("/duckdb/chart")
def duck_chart(req: ChartRequest) -> Dict[str, Any]:
    sql = patch_numeric_sql(repair_sql_for_table(safe_select_sql(req.sql), DEFAULT_TABLE), DEFAULT_TABLE)
    limit = min(int(req.limit), MAX_CHART_ROWS)
    wrapped = f"SELECT * FROM ({sql}) AS q LIMIT {limit}"
    started = time.time()
    cx = con()

    try:
        df = cx.execute(wrapped).fetchdf()
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "DuckDB no pudo generar el dataset del gráfico.",
                "error": str(exc),
                "sql": sql,
                "columns": _table_column_names(DEFAULT_TABLE),
            },
        )
    finally:
        cx.close()

    try:
        chart = chart_png_base64(df, req.chart_type, req.x, req.y, req.title)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "No se pudo renderizar el gráfico.",
                "error": str(exc),
                "sql": sql,
                "rows": df.head(20).where(pd.notnull(df), None).to_dict(orient="records"),
            },
        )

    rows = df.head(200).where(pd.notnull(df), None).to_dict(orient="records")

    return {
        "ok": True,
        "sql": sql,
        "row_count": int(len(df)),
        "rows": rows,
        "seconds": round(time.time() - started, 3),
        **chart,
    }


'''.lstrip()

    text = text[:duck_chart_start] + new_duck_chart + text[duck_preview_start:]

path.write_text(text, encoding="utf-8")
print("OK app.py parcheado.")
PY

echo "==> Validando sintaxis Python"
python3 -m py_compile "$APP_FILE"

echo "==> Reconstruyendo data-engine"
docker compose build --no-cache data-engine
docker compose up -d --force-recreate data-engine

echo "==> Validando parche dentro del contenedor"
docker compose exec -T data-engine sh -lc 'grep -R "repair_sql_for_table\|_duckdb_numeric_expr\|TRY_CAST" -n /app/app.py | head -40'

echo "==> Probando chart con columna inventada creditos_practicas"
docker compose exec -T data-engine python - <<'PY'
import requests

payload = {
    "sql": "SELECT SUM(creditos_practicas) AS total_creditos_practicos FROM silabos WHERE ciclo = '2'",
    "chart_type": "pie",
    "title": "Proporción de créditos prácticos",
    "x": None,
    "y": "total_creditos_practicos",
    "limit": 100
}

r = requests.post("http://localhost:8090/duckdb/chart", json=payload, timeout=180)
print("STATUS:", r.status_code)
print(r.text[:3000])
PY

echo ""
echo "============================================================"
echo "Fix aplicado. Prueba nuevamente desde la web."
echo "Si falla:"
echo "docker compose logs --tail=120 data-engine"
echo "============================================================"
