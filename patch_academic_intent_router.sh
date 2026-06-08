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

echo "==> Insertando router académico determinístico"

python3 - <<'PY'
from pathlib import Path

p = Path("data-engine/app.py")
s = p.read_text(encoding="utf-8")

router_code = r'''

def _sql_num(col: str) -> str:
    return _duckdb_numeric_expr(col)


def _sql_literal(value: str) -> str:
    return q_str(str(value or ""))


def _has_col(table: str, col: str) -> bool:
    lookup = _column_lookup(table)
    return _norm_identifier(col) in lookup


def _real_col(table: str, preferred: str, fallback: Optional[str] = None) -> str:
    lookup = _column_lookup(table)
    n = _norm_identifier(preferred)
    if n in lookup:
        return lookup[n]
    if fallback:
        nf = _norm_identifier(fallback)
        if nf in lookup:
            return lookup[nf]
    return preferred


def _distinct_values(table: str, col: str, limit: int = 500) -> List[str]:
    col = _real_col(table, col)
    cx = con()
    try:
        rows = cx.execute(
            f"SELECT DISTINCT {q_ident(col)} FROM {q_ident(table)} "
            f"WHERE {q_ident(col)} IS NOT NULL AND TRIM(CAST({q_ident(col)} AS VARCHAR)) <> '' "
            f"LIMIT {int(limit)}"
        ).fetchall()
    except Exception:
        rows = []
    finally:
        cx.close()
    return [str(r[0]) for r in rows if r and r[0] is not None]


def _contains_any(q: str, words: List[str]) -> bool:
    return any(w in q for w in words)


def _detect_chart_type(q: str) -> str:
    if _contains_any(q, ["pie", "pastel", "torta", "circular", "proporcion", "proporcion", "porcentaje", "%"]):
        return "pie"
    if _contains_any(q, ["linea", "lineal", "tendencia"]):
        return "line"
    if _contains_any(q, ["horizontal"]):
        return "horizontal_bar"
    return "bar"


def _wants_chart(q: str) -> bool:
    return _contains_any(q, [
        "grafico", "grafica", "chart", "visualiza", "visualizar", "diagrama",
        "barras", "barra", "pie", "pastel", "torta", "circular", "linea"
    ])


def _wants_list(q: str) -> bool:
    return _contains_any(q, [
        "lista", "listar", "listame", "listarme", "muestrame", "mostrar",
        "ver cursos", "detalle", "detallame", "dame los cursos", "cursos que tienes",
        "cursos cargados", "que cursos", "cuáles cursos", "cuales cursos"
    ])


def _wants_count(q: str) -> bool:
    return _contains_any(q, [
        "cuantos", "cuantas", "cantidad", "conteo", "contador", "numero", "nro",
        "total de silabos", "total de cursos", "cuantos silabos", "cuantos cursos"
    ])


def _wants_sum(q: str) -> bool:
    return _contains_any(q, ["suma", "sumatoria", "total de creditos", "total creditos", "total de horas", "total horas"])


def _wants_avg(q: str) -> bool:
    return _contains_any(q, ["promedio", "media", "average"])


def _detect_dimension(q: str, table: str) -> str:
    if _contains_any(q, ["ciclo", "ciclos", "semestre", "semestres"]):
        return _real_col(table, "ciclo")
    if _contains_any(q, ["carrera", "carreras", "escuela", "escuelas", "programa", "programas"]):
        return _real_col(table, "programa_estudio")
    if _contains_any(q, ["facultad", "facultades"]):
        return _real_col(table, "facultad")
    if _contains_any(q, ["sede", "sedes", "campus", "filial"]):
        return _real_col(table, "sede")
    if _contains_any(q, ["modalidad", "modalidades"]):
        return _real_col(table, "modalidad_estudio")
    if _contains_any(q, ["curso", "cursos", "asignatura", "asignaturas"]):
        return _real_col(table, "curso")
    return _real_col(table, "programa_estudio")


def _detect_metric(q: str, table: str) -> Tuple[str, str]:
    """
    Retorna: (columna_real, etiqueta)
    Nota: si piden creditos prácticos/teóricos pero no existen columnas separadas,
    se usan horas_practicas/horas_teoricas porque son las columnas reales del dataset.
    """
    if _contains_any(q, ["practico", "practicos", "practica", "practicas", "hp"]):
        if _has_col(table, "creditos_practicos"):
            return _real_col(table, "creditos_practicos"), "créditos prácticos"
        if _has_col(table, "creditos_practicas"):
            return _real_col(table, "creditos_practicas"), "créditos prácticos"
        return _real_col(table, "horas_practicas"), "horas prácticas"

    if _contains_any(q, ["teorico", "teoricos", "teorica", "teoricas", "ht"]):
        if _has_col(table, "creditos_teoricos"):
            return _real_col(table, "creditos_teoricos"), "créditos teóricos"
        if _has_col(table, "creditos_teoricas"):
            return _real_col(table, "creditos_teoricas"), "créditos teóricos"
        return _real_col(table, "horas_teoricas"), "horas teóricas"

    if _contains_any(q, ["credito", "creditos", "crd"]):
        return _real_col(table, "creditos"), "créditos"

    if _contains_any(q, ["hora", "horas"]):
        if _has_col(table, "horas_totales"):
            return _real_col(table, "horas_totales"), "horas totales"
        return _real_col(table, "horas_practicas"), "horas"

    return _real_col(table, "creditos"), "créditos"


def _detect_program_filter(question: str, table: str) -> Optional[Tuple[str, str]]:
    """
    Detecta cualquier carrera/programa cargado en DuckDB comparando contra
    DISTINCT programa_estudio. No hardcodea solo Sistemas.
    """
    q = _norm_question(question)
    program_col = _real_col(table, "programa_estudio")

    values = _distinct_values(table, program_col, limit=1000)

    # Alias comunes para que "sistemas" matchee "Ingeniería de Sistemas".
    aliases = {
        "sistemas": "sistemas",
        "ingenieria de sistemas": "sistemas",
        "enfermeria": "enfermeria",
        "administracion": "administracion",
        "negocios internacionales": "negocios internacionales",
    }

    for alias, token in aliases.items():
        if alias in q:
            for value in values:
                nv = _norm_question(value)
                if token in nv:
                    return program_col, value

    # Match genérico: si todas las palabras significativas de una carrera aparecen en la pregunta.
    stop = {"de", "del", "la", "el", "y", "en", "a", "por", "para", "con"}
    for value in values:
        nv = _norm_question(value)
        words = [w for w in nv.split() if len(w) >= 4 and w not in stop]
        if words and all(w in q for w in words[:3]):
            return program_col, value

    return None


def _build_where(question: str, table: str) -> Tuple[str, List[Dict[str, str]]]:
    q = _norm_question(question)
    clauses: List[str] = []
    filters: List[Dict[str, str]] = []

    detected_program = _detect_program_filter(question, table)
    if detected_program:
        col, value = detected_program
        clauses.append(f"{q_ident(col)} ILIKE {q_str('%' + value + '%')}")
        filters.append({"column": col, "operator": "ILIKE", "value": f"%{value}%"})

    sede_col = _real_col(table, "sede")
    for sede in ["juliaca", "lima", "tarapoto"]:
        if sede in q and _has_col(table, sede_col):
            clauses.append(f"{q_ident(sede_col)} ILIKE {q_str('%' + sede + '%')}")
            filters.append({"column": sede_col, "operator": "ILIKE", "value": f"%{sede}%"})

    ciclo_col = _real_col(table, "ciclo")
    m = re.search(r"(?:ciclo|semestre)\s*(\d+)", q)
    if m and _has_col(table, ciclo_col):
        clauses.append(f"CAST({q_ident(ciclo_col)} AS VARCHAR) = {q_str(m.group(1))}")
        filters.append({"column": ciclo_col, "operator": "=", "value": m.group(1)})

    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    return where, filters


def _forced_academic_intent(question: str, table: str) -> Optional[Dict[str, Any]]:
    """
    Router académico determinístico para JoMelAI:
    - Prioriza LISTADOS sobre gráficos.
    - Usa columnas reales del DuckDB.
    - No inventa creditos_practicos si solo existen horas_practicas.
    - Soporta carreras/programas cargados dinámicamente.
    """
    q = _norm_question(question)
    if not q:
        return None

    # Solo intervenir en consultas del dominio académico/sílabos.
    domain_hit = _contains_any(q, [
        "silabo", "silabos", "curso", "cursos", "carrera", "carreras", "programa",
        "programas", "facultad", "facultades", "ciclo", "ciclos", "credito",
        "creditos", "hora", "horas", "sumilla", "unidad", "sesion", "sistemas",
        "enfermeria", "administracion", "modalidad", "sede"
    ])

    if not domain_hit:
        return None

    where, filters = _build_where(question, table)

    curso_col = _real_col(table, "curso")
    ciclo_col = _real_col(table, "ciclo")
    programa_col = _real_col(table, "programa_estudio")
    facultad_col = _real_col(table, "facultad")
    modalidad_col = _real_col(table, "modalidad_estudio")
    sede_col = _real_col(table, "sede")
    creditos_col = _real_col(table, "creditos")
    ht_col = _real_col(table, "horas_teoricas")
    hp_col = _real_col(table, "horas_practicas")
    sumilla_col = _real_col(table, "sumilla")

    # 1) LISTADOS: siempre gana sobre gráfico/conteo.
    if _wants_list(q):
        selected_cols = [
            programa_col,
            ciclo_col,
            curso_col,
            creditos_col,
            ht_col,
            hp_col,
        ]

        if "sumilla" in q and _has_col(table, sumilla_col):
            selected_cols.append(sumilla_col)

        # Evita columnas repetidas.
        selected_cols_unique = []
        for c in selected_cols:
            if c not in selected_cols_unique and _has_col(table, c):
                selected_cols_unique.append(c)

        select_sql = ", ".join(q_ident(c) for c in selected_cols_unique)
        order_parts = []
        if _has_col(table, ciclo_col):
            order_parts.append(_sql_num(ciclo_col))
        if _has_col(table, curso_col):
            order_parts.append(q_ident(curso_col))
        order_sql = " ORDER BY " + ", ".join(order_parts) if order_parts else ""

        sql = f"SELECT DISTINCT {select_sql} FROM {q_ident(table)}{where}{order_sql} LIMIT 300"

        return {
            "ok": True,
            "mode": "sql",
            "report_intent": "list_courses",
            "chart_type": None,
            "confidence": 0.99,
            "table": table,
            "dimensions": [],
            "metrics": [],
            "filters": filters,
            "sql": sql,
            "x": None,
            "y": None,
            "title": "Listado de cursos",
            "engine": "forced_academic_router"
        }

    # 2) ATRIBUTOS / SUMILLA de cursos.
    if _contains_any(q, ["sumilla", "sumillas", "atributo", "atributos", "detalle del curso", "datos del curso"]):
        selected_cols = [
            programa_col,
            ciclo_col,
            curso_col,
            creditos_col,
            ht_col,
            hp_col,
            sumilla_col,
        ]
        selected_cols_unique = []
        for c in selected_cols:
            if c not in selected_cols_unique and _has_col(table, c):
                selected_cols_unique.append(c)

        select_sql = ", ".join(q_ident(c) for c in selected_cols_unique)
        order_sql = f" ORDER BY {_sql_num(ciclo_col)}, {q_ident(curso_col)}" if _has_col(table, ciclo_col) and _has_col(table, curso_col) else ""

        sql = f"SELECT DISTINCT {select_sql} FROM {q_ident(table)}{where}{order_sql} LIMIT 200"

        return {
            "ok": True,
            "mode": "sql",
            "report_intent": "course_attributes",
            "chart_type": None,
            "confidence": 0.98,
            "table": table,
            "dimensions": [],
            "metrics": [],
            "filters": filters,
            "sql": sql,
            "x": None,
            "y": None,
            "title": "Atributos de cursos",
            "engine": "forced_academic_router"
        }

    # 3) CONTEOS.
    if _wants_count(q) and not _wants_chart(q):
        # Si pregunta "cuántos cursos/sílabos tiene X", devolver total filtrado.
        sql = f"SELECT COUNT(*) AS total FROM {q_ident(table)}{where}"

        return {
            "ok": True,
            "mode": "sql",
            "report_intent": "count",
            "chart_type": None,
            "confidence": 0.98,
            "table": table,
            "dimensions": [],
            "metrics": ["COUNT(*)"],
            "filters": filters,
            "sql": sql,
            "x": None,
            "y": "total",
            "title": "Conteo académico",
            "engine": "forced_academic_router"
        }

    # 4) GRÁFICOS / AGREGACIONES.
    if _wants_chart(q) or _wants_sum(q) or _wants_avg(q):
        chart_type = _detect_chart_type(q)
        dimension = _detect_dimension(q, table)
        metric_col, metric_label = _detect_metric(q, table)

        # Para pie, siempre debe haber categoría + total.
        if chart_type == "pie":
            # Si no especifica dimensión clara, usar ciclo si habla de ciclo; si no, carrera/programa.
            if _contains_any(q, ["ciclo", "ciclos", "semestre", "semestres"]):
                dimension = ciclo_col
            elif _contains_any(q, ["carrera", "carreras", "escuela", "programa", "programas"]):
                dimension = programa_col

        agg = "AVG" if _wants_avg(q) else "SUM"

        # Si pide porcentaje, calcular participación del total filtrado.
        wants_percent = _contains_any(q, ["%", "porcentaje", "porcentual"])
        if wants_percent:
            numerator = f"{agg}({_sql_num(metric_col)})"
            denominator = f"SUM({agg}({_sql_num(metric_col)})) OVER ()"
            value_expr = f"CASE WHEN {denominator} = 0 THEN 0 ELSE ({numerator} / {denominator}) * 100 END"
            y_name = "porcentaje"
            title = f"Porcentaje de {metric_label} por {dimension}"
        else:
            value_expr = f"{agg}({_sql_num(metric_col)})"
            y_name = "total"
            title = f"{metric_label.capitalize()} por {dimension}"

        order_expr = _sql_num(dimension) if _norm_identifier(dimension) in {"ciclo", "semestre", "nivel"} else y_name

        sql = (
            f"SELECT {q_ident(dimension)} AS categoria, {value_expr} AS {q_ident(y_name)} "
            f"FROM {q_ident(table)}{where} "
            f"GROUP BY {q_ident(dimension)} "
            f"ORDER BY {order_expr} {'ASC' if _norm_identifier(dimension) in {'ciclo','semestre','nivel'} else 'DESC'} "
            f"LIMIT 50"
        )

        return {
            "ok": True,
            "mode": "chart",
            "report_intent": "academic_aggregate_chart",
            "chart_type": chart_type,
            "confidence": 0.98,
            "table": table,
            "dimensions": [dimension],
            "metrics": [metric_col],
            "filters": filters,
            "sql": sql,
            "x": "categoria",
            "y": y_name,
            "title": title,
            "engine": "forced_academic_router"
        }

    return None
'''.strip()


intent_marker = '@api.post("/intent/resolve")'
idx = s.find(intent_marker)
if idx == -1:
    raise SystemExit('No encontré @api.post("/intent/resolve")')

# Inserta el router solo si no existe.
if "def _forced_academic_intent(" not in s:
    s = s[:idx] + router_code + "\n\n\n" + s[idx:]

old_block = '''@api.post("/intent/resolve")
def intent_resolve(req: IntentResolveRequest) -> Dict[str, Any]:
    question = (req.question or "").strip()
    if not question:
        raise HTTPException(status_code=422, detail="La pregunta esta vacia.")

    table = req.table or DEFAULT_TABLE
    result = resolve_intent_by_policy(question, table)

    sql = result.get("sql")
    if sql:
        result["sql"] = patch_numeric_sql(repair_sql_for_table(safe_select_sql(str(sql)), req.table or DEFAULT_TABLE), req.table or DEFAULT_TABLE)

    return result
'''

new_block = '''@api.post("/intent/resolve")
def intent_resolve(req: IntentResolveRequest) -> Dict[str, Any]:
    question = (req.question or "").strip()
    if not question:
        raise HTTPException(status_code=422, detail="La pregunta esta vacia.")

    table = req.table or DEFAULT_TABLE

    forced = _forced_academic_intent(question, table)
    if forced:
        result = forced
    else:
        result = resolve_intent_by_policy(question, table)

    sql = result.get("sql")
    if sql:
        result["sql"] = patch_numeric_sql(
            repair_sql_for_table(safe_select_sql(str(sql)), table),
            table
        )

    return result
'''

if old_block not in s:
    raise SystemExit("No encontré el bloque intent_resolve esperado. Revisa si ya fue modificado.")
s = s.replace(old_block, new_block)

# Mejora aliases comunes en repair_sql_for_table.
old_alias = '''        "escuela": ["programa_estudio", "programa", "carrera", "facultad"],
        "carrera": ["programa_estudio", "programa", "escuela", "facultad"],
        "programa": ["programa_estudio", "programa", "carrera", "facultad"],'''

new_alias = '''        "program_estudio": ["programa_estudio"],
        "programaestudio": ["programa_estudio"],
        "programa_de_estudio": ["programa_estudio"],
        "programa_estudios": ["programa_estudio"],
        "study_program": ["programa_estudio"],
        "escuela": ["programa_estudio", "programa", "carrera", "facultad"],
        "carrera": ["programa_estudio", "programa", "escuela", "facultad"],
        "programa": ["programa_estudio", "programa", "carrera", "facultad"],'''

if old_alias in s:
    s = s.replace(old_alias, new_alias)

p.write_text(s, encoding="utf-8")
print("OK: router académico insertado y intent_resolve actualizado.")
PY

echo "==> Validando sintaxis"
python3 -m py_compile "$APP_FILE"

echo "==> Reconstruyendo data-engine"
docker compose build --no-cache data-engine
docker compose up -d --force-recreate data-engine

echo "==> Pruebas rápidas"

docker compose exec -T data-engine python - <<'PY'
import requests, json

tests = [
    "puedes listarme los cursos de sistemas que tienes cargados ?",
    "cuantos silabos tiene ingenieria de sistemas ?",
    "puedes generar un grafico de pie que muestre el % de creditos practicos en la carrera de sistemas por ciclo ?",
    "grafico de barras de horas teoricas por carrera",
    "muestrame las sumillas de enfermeria por ciclo",
]

for q in tests:
    r = requests.post(
        "http://localhost:8090/intent/resolve",
        json={"question": q, "table": "silabos"},
        timeout=180
    )
    print("\nQUESTION:", q)
    print("STATUS:", r.status_code)
    try:
        data = r.json()
        print(json.dumps({
            "ok": data.get("ok"),
            "mode": data.get("mode"),
            "report_intent": data.get("report_intent"),
            "chart_type": data.get("chart_type"),
            "engine": data.get("engine"),
            "x": data.get("x"),
            "y": data.get("y"),
            "sql": data.get("sql"),
        }, ensure_ascii=False, indent=2)[:3000])
    except Exception:
        print(r.text[:2000])
PY

echo ""
echo "============================================================"
echo "Patch aplicado."
echo "Ahora prueba desde la web:"
echo "- puedes listarme los cursos de sistemas que tienes cargados ?"
echo "- grafico de pie del % de creditos practicos en sistemas por ciclo"
echo "============================================================"
