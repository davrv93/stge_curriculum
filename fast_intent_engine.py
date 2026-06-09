import re
import unicodedata

def _norm(text):
    text = str(text or "").lower()
    text = "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")
    text = re.sub(r"[^a-z0-9_ %.-]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()

def _safe_ident(name, default="silabos"):
    name = str(name or default).strip()
    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
        return default
    return name

def resolve_intent(*args, **kwargs):
    question = kwargs.get("question") or kwargs.get("userAsk") or kwargs.get("ask") or ""
    table = _safe_ident(kwargs.get("table") or "silabos")
    q = _norm(question)

    dimensions = {
        "facultad": ["facultad", "facultades"],
        "programa_estudio": ["programa", "programa de estudio", "carrera", "escuela", "especialidad"],
        "sede": ["sede", "campus", "filial", "juliaca", "lima", "tarapoto"],
        "modalidad_estudio": ["modalidad", "presencial", "virtual", "semipresencial", "distancia"],
        "ciclo": ["ciclo", "semestre", "nivel"],
        "curso": ["curso", "asignatura", "materia"],
    }

    metrics = {
        "creditos": ["credito", "creditos", "crd", "peso academico"],
        "horas_teoricas": ["horas teoricas", "teoria", "ht"],
        "horas_practicas": ["horas practicas", "practica", "hp"],
        "horas_totales": ["horas totales", "total horas", "carga horaria", "horas de clase"],
        "total_creditos": ["total creditos", "creditos totales"],
    }

    dimension = None
    for col, aliases in dimensions.items():
        if col in q or any(a in q for a in aliases):
            dimension = col
            break

    metric = None
    for col, aliases in metrics.items():
        if col in q or any(a in q for a in aliases):
            metric = col
            break

    filters = []
    if "juliaca" in q:
        filters.append("sede ILIKE '%Juliaca%'")
    if "lima" in q:
        filters.append("sede ILIKE '%Lima%'")
    if "tarapoto" in q:
        filters.append("sede ILIKE '%Tarapoto%'")
    if "sistemas" in q:
        filters.append("programa_estudio ILIKE '%Sistemas%'")
    if "c1" in q:
        filters.append("codigo_formato ILIKE '%C1%'")
    if "c2" in q:
        filters.append("codigo_formato ILIKE '%C2%'")
    if "pendiente" in q or "pendientes" in q:
        filters.append("estado_validacion ILIKE '%pendiente%'")

    where = (" WHERE " + " AND ".join(filters)) if filters else ""

    wants_chart = any(x in q for x in ["grafico", "grafica", "pastel", "barras", "chart", "visualizar", "diagrama"])
    wants_pie = any(x in q for x in ["pastel", "pie", "torta", "circular", "porcentaje", "proporcion"])
    wants_scatter = any(x in q for x in ["scatter", "dispersion", "dispercion", "correlacion", " vs ", " versus "])
    wants_sum = any(x in q for x in ["suma", "sumatoria", "total creditos", "total horas"])
    wants_avg = any(x in q for x in ["promedio", "media"])
    wants_list = any(x in q for x in ["lista", "listar", "muestrame", "mostrar", "detalle", "ver "])
    wants_count = any(x in q for x in ["cuantos", "cantidad", "conteo", "contador", "numero", "nro", "distribucion", "frecuencia", "por "])

    chart_type = "pie" if wants_pie else ("scatter" if wants_scatter else "bar")

    if wants_scatter:
        x = "TRY_CAST(creditos AS DOUBLE)"
        y = "TRY_CAST(horas_totales AS DOUBLE)"
        sql = f"SELECT {x} AS x, {y} AS y FROM {table} WHERE {x} IS NOT NULL AND {y} IS NOT NULL LIMIT 300"
        return {"ok": True, "mode": "chart", "report_intent": "scatter", "chart_type": "scatter", "confidence": 0.78, "table": table, "dimensions": [], "metrics": ["creditos", "horas_totales"], "filters": filters, "sql": sql, "x": "x", "y": "y", "title": "Dispersión créditos vs horas"}

    if wants_sum or wants_avg:
        metric = metric or "creditos"
        agg = "AVG" if wants_avg else "SUM"
        expr = f"TRY_CAST({metric} AS DOUBLE)"
        if dimension:
            sql = f"SELECT {dimension} AS categoria, {agg}({expr}) AS valor FROM {table}{where} GROUP BY {dimension} ORDER BY valor DESC LIMIT 50"
        else:
            sql = f"SELECT {agg}({expr}) AS valor FROM {table}{where} LIMIT 1"
        return {"ok": True, "mode": "chart" if wants_chart or dimension else "sql", "report_intent": "aggregate", "chart_type": chart_type, "confidence": 0.80, "table": table, "dimensions": [dimension] if dimension else [], "metrics": [metric], "filters": filters, "sql": sql, "x": "categoria" if dimension else None, "y": "valor", "title": f"{agg} de {metric}"}

    if wants_list and not wants_count:
        sql = f"SELECT * FROM {table}{where} LIMIT 100"
        return {"ok": True, "mode": "sql", "report_intent": "list", "chart_type": None, "confidence": 0.76, "table": table, "dimensions": [], "metrics": [], "filters": filters, "sql": sql, "title": "Listado"}

    dimension = dimension or ("programa_estudio" if "programa" in q or "carrera" in q else "facultad")
    limit = 8 if chart_type == "pie" else 50
    sql = f"SELECT {dimension} AS categoria, COUNT(*) AS total FROM {table}{where} GROUP BY {dimension} ORDER BY total DESC LIMIT {limit}"
    return {"ok": True, "mode": "chart" if wants_chart or wants_count else "sql", "report_intent": "count", "chart_type": chart_type, "confidence": 0.82, "table": table, "dimensions": [dimension], "metrics": [], "filters": filters, "sql": sql, "x": "categoria", "y": "total", "title": f"Conteo por {dimension}"}
