#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/jomelai}"

OLLAMA_VERSION="${OLLAMA_VERSION:-0.5.7}"
LATERAL_MODEL="${LATERAL_MODEL:-qwen2.5:0.5b}"
LATERAL_FALLBACK_MODEL="${LATERAL_FALLBACK_MODEL:-tinyllama:latest}"

LATERAL_NUM_CTX="${LATERAL_NUM_CTX:-1024}"
LATERAL_NUM_PREDICT="${LATERAL_NUM_PREDICT:-220}"
LATERAL_TIMEOUT="${LATERAL_TIMEOUT:-90}"
LATERAL_N_RESULTS="${LATERAL_N_RESULTS:-2}"
LATERAL_MAX_CONTEXT_CHARS="${LATERAL_MAX_CONTEXT_CHARS:-2600}"
LATERAL_KEEP_ALIVE="${LATERAL_KEEP_ALIVE:-20m}"

cd "$PROJECT_DIR"

echo "=================================================="
echo " REPAIR JoMelAi Chat Lateral V2 SAFE"
echo "=================================================="
echo "Proyecto: $PROJECT_DIR"

echo
echo "== 0) Ignorando script roto anterior =="
if [ -f upgrade_chat_lateral_v2_full.sh ]; then
  mv upgrade_chat_lateral_v2_full.sh "upgrade_chat_lateral_v2_full.sh.broken.$(date +%Y%m%d_%H%M%S)" || true
fi

echo
echo "== 1) Detectando servicios Docker =="
OLLAMA_SERVICE="$(docker compose config --services | grep -i '^ollama$' || true)"
if [ -z "$OLLAMA_SERVICE" ]; then
  OLLAMA_SERVICE="$(docker compose config --services | grep -i 'ollama' | head -1 || true)"
fi

if [ -z "$OLLAMA_SERVICE" ]; then
  echo "ERROR: no encontré servicio Ollama."
  docker compose config --services
  exit 1
fi

echo "Servicio Ollama: $OLLAMA_SERVICE"

echo
echo "== 2) Configurando .env para chat lateral =="
touch .env

set_env() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|g" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_env "DATA_ENGINE_URL" "http://data-engine:8000"
set_env "OLLAMA_LATERAL_MODEL" "$LATERAL_MODEL"
set_env "OLLAMA_LATERAL_FALLBACK_MODEL" "$LATERAL_FALLBACK_MODEL"
set_env "OLLAMA_LATERAL_NUM_CTX" "$LATERAL_NUM_CTX"
set_env "OLLAMA_LATERAL_NUM_PREDICT" "$LATERAL_NUM_PREDICT"
set_env "OLLAMA_LATERAL_TIMEOUT" "$LATERAL_TIMEOUT"
set_env "OLLAMA_LATERAL_N_RESULTS" "$LATERAL_N_RESULTS"
set_env "OLLAMA_LATERAL_MAX_CONTEXT_CHARS" "$LATERAL_MAX_CONTEXT_CHARS"
set_env "OLLAMA_LATERAL_KEEP_ALIVE" "$LATERAL_KEEP_ALIVE"
set_env "OLLAMA_LATERAL_FORCE_LIGHT" "true"

echo
echo "== 3) Fijando Ollama a versión estable =="
if [ -f docker-compose.override.yml ]; then
  cp docker-compose.override.yml "docker-compose.override.yml.bak.repair.$(date +%Y%m%d_%H%M%S)"
fi

cat > docker-compose.override.yml <<YAML
services:
  $OLLAMA_SERVICE:
    image: ollama/ollama:$OLLAMA_VERSION
    environment:
      OLLAMA_HOST: "0.0.0.0:11434"
      OLLAMA_NUM_PARALLEL: "1"
      OLLAMA_MAX_LOADED_MODELS: "1"
      OLLAMA_KEEP_ALIVE: "$LATERAL_KEEP_ALIVE"
YAML

docker builder prune -af || true
docker image prune -af || true
docker container prune -f || true

docker compose pull "$OLLAMA_SERVICE"
docker compose up -d --force-recreate "$OLLAMA_SERVICE"

sleep 8

OLLAMA_CONTAINER="$(docker compose ps -q "$OLLAMA_SERVICE")"
if [ -z "$OLLAMA_CONTAINER" ]; then
  echo "ERROR: no pude obtener contenedor Ollama."
  docker compose ps
  exit 1
fi

echo "Contenedor Ollama: $OLLAMA_CONTAINER"
docker exec "$OLLAMA_CONTAINER" ollama --version || true

test_model() {
  local model="$1"

  echo
  echo "== Probando modelo: $model =="
  docker exec "$OLLAMA_CONTAINER" ollama pull "$model"

  set +e
  timeout 90 docker exec "$OLLAMA_CONTAINER" ollama run "$model" "Responde solo: OK"
  local status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "OK: $model funciona."
    return 0
  fi

  echo "FALLÓ: $model"
  docker logs --tail=120 "$OLLAMA_CONTAINER" || true
  return 1
}

FINAL_MODEL=""
if test_model "$LATERAL_MODEL"; then
  FINAL_MODEL="$LATERAL_MODEL"
else
  if test_model "$LATERAL_FALLBACK_MODEL"; then
    FINAL_MODEL="$LATERAL_FALLBACK_MODEL"
  else
    echo "ERROR: fallaron ambos modelos laterales."
    docker logs --tail=200 "$OLLAMA_CONTAINER" || true
    exit 1
  fi
fi

set_env "OLLAMA_LATERAL_MODEL" "$FINAL_MODEL"

echo
echo "Modelo final para CHAT LATERAL: $FINAL_MODEL"

echo
echo "== 4) Detectando Data Engine real SOLO en .py =="
ENGINE_FILE="$(find . \
  -type f \
  -name "*.py" \
  ! -path "./.git/*" \
  ! -path "./data/*" \
  ! -path "./node_modules/*" \
  ! -path "./vendor/*" \
  ! -name "*.bak*" \
  -print0 | xargs -0 grep -sl '@api.post("/rag/answer")' | head -1 || true)"

if [ -z "$ENGINE_FILE" ]; then
  ENGINE_FILE="$(find . \
    -type f \
    -name "*.py" \
    ! -path "./.git/*" \
    ! -path "./data/*" \
    ! -path "./node_modules/*" \
    ! -path "./vendor/*" \
    ! -name "*.bak*" \
    -print0 | xargs -0 grep -sl 'FastAPI' | head -1 || true)"
fi

if [ -z "$ENGINE_FILE" ]; then
  echo "ERROR: no encontré archivo Python del Data Engine."
  echo "Archivos .py disponibles:"
  find . -type f -name "*.py" ! -path "./data/*" ! -path "./.git/*" | head -80
  exit 1
fi

echo "Data Engine real: $ENGINE_FILE"

if [[ "$ENGINE_FILE" == *.sh ]]; then
  echo "ERROR: detector volvió a tomar un .sh. Abortando por seguridad."
  exit 1
fi

cp "$ENGINE_FILE" "${ENGINE_FILE}.bak.chatv2safe.$(date +%Y%m%d_%H%M%S)"

echo
echo "== 5) Parcheando Data Engine con APIs nuevas =="
python3 - "$ENGINE_FILE" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "from fastapi.responses import StreamingResponse" not in text:
    text = text.replace(
        "from fastapi import FastAPI, HTTPException",
        "from fastapi import FastAPI, HTTPException\nfrom fastapi.responses import StreamingResponse"
    )

start = "# === CHAT LATERAL V2 SAFE START ==="
end = "# === CHAT LATERAL V2 SAFE END ==="

patch = r'''
# === CHAT LATERAL V2 SAFE START ===

class ChatLateralAskRequest(BaseModel):
    question: str
    table: str = Field(default=DEFAULT_TABLE)
    collection: str = Field(default="silabos")
    model: Optional[str] = Field(default=None)
    n_results: int = Field(default=2, ge=1, le=5)
    stream: bool = Field(default=False)
    prefer_duckdb: bool = Field(default=True)
    prefer_rag: bool = Field(default=True)
    allow_ollama: bool = Field(default=True)
    chart: bool = Field(default=True)
    limit: int = Field(default=100, ge=1, le=MAX_QUERY_LIMIT)


def _cl_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except Exception:
        return default


def _cl_bool(name: str, default: bool) -> bool:
    raw = str(os.getenv(name, "true" if default else "false")).strip().lower()
    return raw in {"1", "true", "yes", "si", "sí", "on"}


OLLAMA_LATERAL_MODEL = os.getenv("OLLAMA_LATERAL_MODEL", "qwen2.5:0.5b").strip()
OLLAMA_LATERAL_FALLBACK_MODEL = os.getenv("OLLAMA_LATERAL_FALLBACK_MODEL", "tinyllama:latest").strip()
OLLAMA_LATERAL_NUM_CTX = _cl_int("OLLAMA_LATERAL_NUM_CTX", 1024)
OLLAMA_LATERAL_NUM_PREDICT = _cl_int("OLLAMA_LATERAL_NUM_PREDICT", 220)
OLLAMA_LATERAL_TIMEOUT = _cl_int("OLLAMA_LATERAL_TIMEOUT", 90)
OLLAMA_LATERAL_N_RESULTS = _cl_int("OLLAMA_LATERAL_N_RESULTS", 2)
OLLAMA_LATERAL_MAX_CONTEXT_CHARS = _cl_int("OLLAMA_LATERAL_MAX_CONTEXT_CHARS", 2600)
OLLAMA_LATERAL_KEEP_ALIVE = os.getenv("OLLAMA_LATERAL_KEEP_ALIVE", "20m").strip()
OLLAMA_LATERAL_FORCE_LIGHT = _cl_bool("OLLAMA_LATERAL_FORCE_LIGHT", True)


def _cl_sse(event: str, data: Dict[str, Any]) -> str:
    payload = json.dumps(data, ensure_ascii=False, default=str)
    return "event: " + event + "\n" + "data: " + payload + "\n\n"


def _cl_fast_answer(rows: List[Dict[str, Any]], title: str = "Resultado") -> str:
    if not rows:
        return "No encontré registros para esa consulta."

    if len(rows) == 1:
        row = rows[0]
        if "total" in row:
            return f"{title}: {row.get('total')}."
        if "valor" in row:
            return f"{title}: {row.get('valor')}."
        pairs = [f"{k}: {v}" for k, v in row.items()]
        return title + ": " + ", ".join(pairs[:8]) + "."

    return f"{title}: encontré {len(rows)} registros. Revisa la tabla de resultados."


def _cl_route(req: ChatLateralAskRequest) -> Dict[str, Any]:
    question = (req.question or "").strip()
    if not question:
        raise HTTPException(status_code=422, detail="La pregunta está vacía.")

    started = time.time()

    route = {
        "ok": True,
        "question": question,
        "table": req.table,
        "collection": req.collection,
        "route": "rag_ollama_light",
        "reason": "default_rag_first_then_light_ollama",
        "intent": None,
        "sql": None,
        "chart_type": None,
        "engine": "chat_lateral_v2_safe",
        "seconds": 0,
    }

    try:
        intent = intent_resolve(IntentResolveRequest(question=question, table=req.table))
        route["intent"] = intent
    except Exception as exc:
        intent = None
        route["intent_error"] = str(exc)

    if isinstance(intent, dict):
        sql = intent.get("sql")
        mode = str(intent.get("mode") or "").lower()
        chart_type = intent.get("chart_type")
        report_intent = str(intent.get("report_intent") or "").lower()

        if req.prefer_duckdb and sql and mode == "chart" and req.chart:
            route.update({
                "route": "duckdb_chart",
                "reason": "intent_mode_chart",
                "sql": sql,
                "chart_type": chart_type or "bar",
            })
            route["seconds"] = round(time.time() - started, 3)
            return route

        if req.prefer_duckdb and sql and mode == "sql":
            route.update({
                "route": "duckdb_sql",
                "reason": "intent_mode_sql",
                "sql": sql,
            })
            route["seconds"] = round(time.time() - started, 3)
            return route

        if report_intent in {"list_courses", "list_programs", "count", "course_attributes"} and sql:
            route.update({
                "route": "duckdb_sql",
                "reason": "academic_data_intent",
                "sql": sql,
            })
            route["seconds"] = round(time.time() - started, 3)
            return route

        if mode == "assistant":
            route.update({
                "route": "rag_ollama_light",
                "reason": "assistant_curricular_advice",
            })
            route["seconds"] = round(time.time() - started, 3)
            return route

    route["seconds"] = round(time.time() - started, 3)
    return route


def _cl_rag_context(question: str, collection: str, n_results: int) -> Tuple[str, List[Dict[str, Any]]]:
    try:
        rag = rag_search(RagSearchRequest(
            query=question,
            collection=collection,
            n_results=max(1, min(int(n_results or OLLAMA_LATERAL_N_RESULTS), 5))
        ))
    except Exception:
        rag = {"results": []}

    results = rag.get("results") or []
    evidence = []
    parts = []

    for i, item in enumerate(results[:max(1, OLLAMA_LATERAL_N_RESULTS)]):
        doc = str(item.get("document") or "").strip()
        meta = item.get("metadata") or {}
        if not doc:
            continue

        title = meta.get("curso") or meta.get("programa_estudio") or meta.get("source_file") or f"Fuente {i + 1}"
        parts.append(f"[Fuente {i + 1}: {title}]\n{doc}")
        evidence.append(item)

    context = "\n\n".join(parts)
    context = context[:max(800, int(OLLAMA_LATERAL_MAX_CONTEXT_CHARS or 2600))]

    return context, evidence


def _cl_generate(question: str, context: str, requested_model: Optional[str] = None, stream: bool = False):
    selected_model = (
        OLLAMA_LATERAL_MODEL
        if OLLAMA_LATERAL_FORCE_LIGHT
        else ((requested_model or "").strip() or OLLAMA_LATERAL_MODEL)
    )

    prompt = f"""
Eres JoMelAI Curriculista. Responde en español, breve, académico y directo.
Usa primero el contexto recuperado. Si el contexto no alcanza, dilo explícitamente.
No inventes cifras. Para conteos exactos, usa DuckDB o indica que se consulte DuckDB.

Contexto:
{context}

Pregunta:
{question}

Respuesta breve:
""".strip()

    payload = {
        "model": selected_model,
        "prompt": prompt,
        "stream": stream,
        "keep_alive": OLLAMA_LATERAL_KEEP_ALIVE,
        "options": {
            "temperature": 0.18,
            "top_p": 0.80,
            "num_ctx": OLLAMA_LATERAL_NUM_CTX,
            "num_predict": OLLAMA_LATERAL_NUM_PREDICT,
        },
    }

    return selected_model, payload


@api.post("/chat-lateral/route")
def chat_lateral_route(req: ChatLateralAskRequest) -> Dict[str, Any]:
    return _cl_route(req)


@api.post("/chat-lateral/ask")
def chat_lateral_ask(req: ChatLateralAskRequest) -> Dict[str, Any]:
    started = time.time()
    route = _cl_route(req)

    if route["route"] == "duckdb_sql":
        sql_result = duck_query(DuckQueryRequest(sql=str(route["sql"]), limit=req.limit))
        rows = sql_result.get("rows") or []
        return {
            "ok": True,
            "mode": "duckdb_sql",
            "answer": _cl_fast_answer(rows, route.get("intent", {}).get("title") or "Resultado"),
            "route": route,
            "sql": sql_result.get("sql"),
            "rows": rows,
            "row_count": sql_result.get("row_count", len(rows)),
            "seconds": round(time.time() - started, 3),
            "ollama_used": False,
            "chat_lateral_v2": True,
        }

    if route["route"] == "duckdb_chart":
        intent = route.get("intent") or {}
        chart_result = duck_chart(ChartRequest(
            sql=str(route["sql"]),
            chart_type=str(route.get("chart_type") or intent.get("chart_type") or "bar"),
            title=str(intent.get("title") or "Reporte curricular"),
            x=intent.get("x") or "categoria",
            y=intent.get("y") or "total",
            limit=min(req.limit, MAX_CHART_ROWS),
        ))
        return {
            "ok": True,
            "mode": "duckdb_chart",
            "answer": "Generé el gráfico solicitado desde DuckDB.",
            "route": route,
            **chart_result,
            "seconds": round(time.time() - started, 3),
            "ollama_used": False,
            "chat_lateral_v2": True,
        }

    context, evidence = _cl_rag_context(req.question, req.collection, req.n_results)

    if not req.allow_ollama:
        return {
            "ok": True,
            "mode": "rag_only",
            "answer": "Encontré fuentes relacionadas. Ollama está desactivado para esta solicitud.",
            "route": route,
            "sources": evidence,
            "evidence": evidence,
            "count": len(evidence),
            "seconds": round(time.time() - started, 3),
            "ollama_used": False,
            "chat_lateral_v2": True,
        }

    if not context.strip():
        context = "No se recuperó contexto suficiente desde RAG."

    selected_model, payload = _cl_generate(req.question, context, req.model, stream=False)

    try:
        r = requests.post(f"{OLLAMA_BASE_URL}/api/generate", json=payload, timeout=OLLAMA_LATERAL_TIMEOUT)

        if r.status_code >= 400 and selected_model != OLLAMA_LATERAL_FALLBACK_MODEL:
            selected_model = OLLAMA_LATERAL_FALLBACK_MODEL
            payload["model"] = selected_model
            r = requests.post(f"{OLLAMA_BASE_URL}/api/generate", json=payload, timeout=OLLAMA_LATERAL_TIMEOUT)

        r.raise_for_status()
        answer = str(r.json().get("response") or "").strip()
        ollama_ok = True
        ollama_error = None
    except Exception as exc:
        answer = (
            "Encontré contexto relacionado, pero Ollama no respondió correctamente. "
            "Revisa las fuentes recuperadas o intenta una pregunta más específica."
        )
        ollama_ok = False
        ollama_error = str(exc)

    return {
        "ok": True,
        "mode": "rag_ollama_light",
        "answer": answer,
        "route": route,
        "sources": evidence,
        "evidence": evidence,
        "count": len(evidence),
        "ollama_used": True,
        "ollama_ok": ollama_ok,
        "ollama_error": ollama_error,
        "model_used": selected_model,
        "seconds": round(time.time() - started, 3),
        "chat_lateral_v2": True,
    }


@api.post("/chat-lateral/ask-stream")
def chat_lateral_ask_stream(req: ChatLateralAskRequest):
    def gen():
        started = time.time()
        yield _cl_sse("ready", {"ok": True, "chat_lateral_v2": True})

        try:
            route = _cl_route(req)

            yield _cl_sse("config", {
                "ok": True,
                "route": route.get("route"),
                "reason": route.get("reason"),
                "model": OLLAMA_LATERAL_MODEL,
                "fallback_model": OLLAMA_LATERAL_FALLBACK_MODEL,
                "num_ctx": OLLAMA_LATERAL_NUM_CTX,
                "num_predict": OLLAMA_LATERAL_NUM_PREDICT,
                "n_results": min(req.n_results, OLLAMA_LATERAL_N_RESULTS),
                "chat_lateral_v2": True,
            })

            if route["route"] == "duckdb_sql":
                sql_result = duck_query(DuckQueryRequest(sql=str(route["sql"]), limit=req.limit))
                rows = sql_result.get("rows") or []
                answer = _cl_fast_answer(rows, route.get("intent", {}).get("title") or "Resultado")

                yield _cl_sse("token", {"text": answer})
                yield _cl_sse("final", {
                    "ok": True,
                    "mode": "duckdb_sql",
                    "answer": answer,
                    "route": route,
                    "sql": sql_result.get("sql"),
                    "rows": rows,
                    "row_count": sql_result.get("row_count", len(rows)),
                    "seconds": round(time.time() - started, 3),
                    "ollama_used": False,
                    "chat_lateral_v2": True,
                })
                return

            if route["route"] == "duckdb_chart":
                intent = route.get("intent") or {}
                chart_result = duck_chart(ChartRequest(
                    sql=str(route["sql"]),
                    chart_type=str(route.get("chart_type") or intent.get("chart_type") or "bar"),
                    title=str(intent.get("title") or "Reporte curricular"),
                    x=intent.get("x") or "categoria",
                    y=intent.get("y") or "total",
                    limit=min(req.limit, MAX_CHART_ROWS),
                ))

                answer = "Generé el gráfico solicitado desde DuckDB."
                yield _cl_sse("token", {"text": answer})
                yield _cl_sse("final", {
                    "ok": True,
                    "mode": "duckdb_chart",
                    "answer": answer,
                    "route": route,
                    **chart_result,
                    "seconds": round(time.time() - started, 3),
                    "ollama_used": False,
                    "chat_lateral_v2": True,
                })
                return

            context, evidence = _cl_rag_context(req.question, req.collection, req.n_results)

            if not context.strip():
                context = "No se recuperó contexto suficiente desde RAG."

            if not req.allow_ollama:
                yield _cl_sse("final", {
                    "ok": True,
                    "mode": "rag_only",
                    "answer": "Encontré fuentes relacionadas. Ollama está desactivado para esta solicitud.",
                    "route": route,
                    "sources": evidence,
                    "evidence": evidence,
                    "count": len(evidence),
                    "seconds": round(time.time() - started, 3),
                    "ollama_used": False,
                    "chat_lateral_v2": True,
                })
                return

            selected_model, payload = _cl_generate(req.question, context, req.model, stream=True)
            answer_parts = []

            try:
                r = requests.post(
                    f"{OLLAMA_BASE_URL}/api/generate",
                    json=payload,
                    stream=True,
                    timeout=OLLAMA_LATERAL_TIMEOUT,
                )

                if r.status_code >= 400 and selected_model != OLLAMA_LATERAL_FALLBACK_MODEL:
                    selected_model = OLLAMA_LATERAL_FALLBACK_MODEL
                    payload["model"] = selected_model
                    r = requests.post(
                        f"{OLLAMA_BASE_URL}/api/generate",
                        json=payload,
                        stream=True,
                        timeout=OLLAMA_LATERAL_TIMEOUT,
                    )

                if r.status_code >= 400:
                    raise RuntimeError(f"Ollama respondió HTTP {r.status_code}: {r.text[:300]}")

                for raw in r.iter_lines():
                    if not raw:
                        continue
                    try:
                        item = json.loads(raw.decode("utf-8"))
                    except Exception:
                        continue

                    token = str(item.get("response") or "")
                    if token:
                        answer_parts.append(token)
                        yield _cl_sse("token", {"text": token})

                    if item.get("done"):
                        break

                answer = "".join(answer_parts).strip()

                yield _cl_sse("final", {
                    "ok": True,
                    "mode": "rag_ollama_light_stream",
                    "answer": answer,
                    "route": route,
                    "sources": evidence,
                    "evidence": evidence,
                    "count": len(evidence),
                    "ollama_used": True,
                    "model_used": selected_model,
                    "seconds": round(time.time() - started, 3),
                    "chat_lateral_v2": True,
                })

            except Exception as exc:
                answer = (
                    "Encontré contexto relacionado, pero Ollama no respondió correctamente. "
                    "Revisa las fuentes recuperadas o intenta una pregunta más específica."
                )
                yield _cl_sse("token", {"text": answer})
                yield _cl_sse("final", {
                    "ok": False,
                    "mode": "rag_ollama_light_stream",
                    "answer": answer,
                    "route": route,
                    "sources": evidence,
                    "evidence": evidence,
                    "count": len(evidence),
                    "ollama_used": True,
                    "model_used": selected_model,
                    "error": str(exc),
                    "seconds": round(time.time() - started, 3),
                    "chat_lateral_v2": True,
                })

        except Exception as exc:
            yield _cl_sse("final", {
                "ok": False,
                "mode": "chat_lateral_error",
                "answer": "",
                "message": str(exc),
                "seconds": round(time.time() - started, 3),
                "chat_lateral_v2": True,
            })

    return StreamingResponse(gen(), media_type="text/event-stream")


# === CHAT LATERAL V2 SAFE END ===
'''

if start in text and end in text:
    text = re.sub(re.escape(start) + r".*?" + re.escape(end), patch.strip(), text, flags=re.S)
else:
    text = text.rstrip() + "\n\n\n" + patch.strip() + "\n"

path.write_text(text, encoding="utf-8")
PY

python3 -m py_compile "$ENGINE_FILE"

echo
echo "== 6) Agregando proxy backend si existe routes/api.php =="
ROUTES_FILE=""
for f in routes/api.php backend/routes/api.php app/routes/api.php; do
  if [ -f "$f" ]; then
    ROUTES_FILE="$f"
    break
  fi
done

if [ -n "$ROUTES_FILE" ]; then
  echo "Rutas Laravel detectadas: $ROUTES_FILE"
  cp "$ROUTES_FILE" "${ROUTES_FILE}.bak.chatv2safe.$(date +%Y%m%d_%H%M%S)"

  if ! grep -q "CHAT LATERAL V2 SAFE PROXY START" "$ROUTES_FILE"; then
    cat >> "$ROUTES_FILE" <<'PHP'

// === CHAT LATERAL V2 SAFE PROXY START ===
Route::post('/chat-lateral/route', function (\Illuminate\Http\Request $request) {
    $base = rtrim(env('DATA_ENGINE_URL', env('SILABO_ENGINE_URL', 'http://data-engine:8000')), '/');
    $response = \Illuminate\Support\Facades\Http::timeout(90)
        ->post($base . '/chat-lateral/route', $request->all());

    return response($response->body(), $response->status())
        ->header('Content-Type', $response->header('Content-Type') ?: 'application/json');
});

Route::post('/chat-lateral/ask', function (\Illuminate\Http\Request $request) {
    $base = rtrim(env('DATA_ENGINE_URL', env('SILABO_ENGINE_URL', 'http://data-engine:8000')), '/');
    $response = \Illuminate\Support\Facades\Http::timeout(180)
        ->post($base . '/chat-lateral/ask', $request->all());

    return response($response->body(), $response->status())
        ->header('Content-Type', $response->header('Content-Type') ?: 'application/json');
});

Route::post('/chat-lateral/ask-stream', function (\Illuminate\Http\Request $request) {
    $base = rtrim(env('DATA_ENGINE_URL', env('SILABO_ENGINE_URL', 'http://data-engine:8000')), '/');
    $payload = json_encode($request->all(), JSON_UNESCAPED_UNICODE);

    return response()->stream(function () use ($base, $payload) {
        $ch = curl_init($base . '/chat-lateral/ask-stream');

        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_RETURNTRANSFER => false,
            CURLOPT_WRITEFUNCTION => function ($ch, $data) {
                echo $data;
                if (ob_get_level() > 0) {
                    @ob_flush();
                }
                flush();
                return strlen($data);
            },
            CURLOPT_TIMEOUT => 180,
        ]);

        curl_exec($ch);
        curl_close($ch);
    }, 200, [
        'Content-Type' => 'text/event-stream',
        'Cache-Control' => 'no-cache',
        'X-Accel-Buffering' => 'no',
        'Connection' => 'keep-alive',
    ]);
});
// === CHAT LATERAL V2 SAFE PROXY END ===
PHP
  fi
else
  echo "No encontré routes/api.php. Saltando proxy Laravel."
fi

echo
echo "== 7) Frontend: agregando cliente V2 y parcheando endpoints =="
FRONT_DIR=""
for d in public frontend/public frontend/src src app; do
  if [ -d "$d" ]; then
    FRONT_DIR="$d"
    break
  fi
done

if [ -z "$FRONT_DIR" ]; then
  FRONT_DIR="public"
  mkdir -p "$FRONT_DIR"
fi

echo "Frontend dir: $FRONT_DIR"

cat > "$FRONT_DIR/chat-lateral-v2-client.js" <<'JS'
(function () {
  const STREAM_ENDPOINTS = [
    '/api/chat-lateral/ask-stream',
    '/chat-lateral/ask-stream'
  ];

  async function askStream(question, handlers, options) {
    handlers = handlers || {};
    options = options || {};

    const payload = {
      question: question,
      table: options.table || 'silabos',
      collection: options.collection || 'silabos',
      n_results: options.n_results || 2,
      stream: true,
      prefer_duckdb: true,
      prefer_rag: true,
      allow_ollama: options.allow_ollama !== false,
      chart: true,
      limit: options.limit || 100
    };

    let lastError = null;

    for (const url of STREAM_ENDPOINTS) {
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify(payload)
        });

        if (!res.ok) {
          throw new Error('HTTP ' + res.status + ' en ' + url);
        }

        const reader = res.body.getReader();
        const decoder = new TextDecoder('utf-8');
        let buffer = '';
        let finalData = null;

        while (true) {
          const read = await reader.read();
          if (read.done) break;

          buffer += decoder.decode(read.value, {stream: true});
          const chunks = buffer.split('\n\n');
          buffer = chunks.pop() || '';

          for (const chunk of chunks) {
            const lines = chunk.split('\n');
            let event = 'message';
            let data = '';

            for (const line of lines) {
              if (line.startsWith('event:')) event = line.slice(6).trim();
              if (line.startsWith('data:')) data += line.slice(5).trim();
            }

            if (!data) continue;

            let parsed = {};
            try {
              parsed = JSON.parse(data);
            } catch (e) {
              parsed = {raw: data};
            }

            if (event === 'ready' && handlers.onReady) handlers.onReady(parsed);
            if (event === 'config' && handlers.onConfig) handlers.onConfig(parsed);
            if (event === 'token' && handlers.onToken) handlers.onToken(parsed.text || '', parsed);
            if (event === 'final') {
              finalData = parsed;
              if (handlers.onFinal) handlers.onFinal(parsed);
            }
          }
        }

        return finalData || {ok: true};
      } catch (err) {
        lastError = err;
      }
    }

    throw lastError || new Error('No se pudo conectar al chat lateral v2');
  }

  window.JoMelAiChatLateralV2 = { askStream };
  window.jomelaiChatLateralAskStream = askStream;
})();
JS

for html in index.html public/index.html frontend/index.html frontend/public/index.html; do
  if [ -f "$html" ]; then
    if ! grep -q "chat-lateral-v2-client.js" "$html"; then
      cp "$html" "${html}.bak.chatv2safe.$(date +%Y%m%d_%H%M%S)"
      sed -i 's#</body>#  <script src="/chat-lateral-v2-client.js"></script>\n</body>#' "$html" || true
      echo "Cliente inyectado en $html"
    fi
  fi
done

python3 - <<'PY'
from pathlib import Path

roots = [Path("frontend"), Path("public"), Path("src"), Path("app")]
patterns = ["*.js", "*.ts", "*.jsx", "*.tsx", "*.html"]

replacements = {
    "qwen2.5-coder:3b": "qwen2.5:0.5b",
    "qwen2.5-coder:1.5b": "qwen2.5:0.5b",
    "/api/ask_stream": "/api/chat-lateral/ask-stream",
    "/ask_stream": "/api/chat-lateral/ask-stream",
    "/api/rag/answer": "/api/chat-lateral/ask",
    "/rag/answer": "/api/chat-lateral/ask",
}

for root in roots:
    if not root.exists():
        continue
    for pattern in patterns:
        for file in root.rglob(pattern):
            p = str(file)
            if ".git" in p or "node_modules" in p or ".bak" in p:
                continue
            try:
                text = file.read_text(encoding="utf-8")
            except Exception:
                continue

            new = text
            for a, b in replacements.items():
                new = new.replace(a, b)

            new = new.replace("num_predict: 700", "num_predict: 220")
            new = new.replace("num_ctx: 4096", "num_ctx: 1024")
            new = new.replace("num_ctx: 2048", "num_ctx: 1024")

            if new != text:
                backup = file.with_suffix(file.suffix + ".bak.chatv2safe")
                backup.write_text(text, encoding="utf-8")
                file.write_text(new, encoding="utf-8")
                print("Parcheado frontend:", file)
PY

echo
echo "== 8) Rebuild/restart =="
docker compose down
docker compose up -d --build

echo
echo "== 9) Detectando servicio Data Engine para pruebas =="
DATA_ENGINE_SERVICE="$(docker compose config --services | grep -Ei 'data-engine|data_engine|engine|silabo|api' | head -1 || true)"
if [ -z "$DATA_ENGINE_SERVICE" ]; then
  echo "No detecté servicio Data Engine por nombre. Servicios:"
  docker compose config --services
  echo "El parche quedó aplicado en: $ENGINE_FILE"
  exit 0
fi

DATA_ENGINE_CONTAINER="$(docker compose ps -q "$DATA_ENGINE_SERVICE" || true)"
if [ -z "$DATA_ENGINE_CONTAINER" ]; then
  echo "No detecté contenedor Data Engine. Estado:"
  docker compose ps
  exit 0
fi

echo "Data Engine service: $DATA_ENGINE_SERVICE"
echo "Data Engine container: $DATA_ENGINE_CONTAINER"

echo
echo "== 10) Test interno DuckDB rápido =="
docker exec "$DATA_ENGINE_CONTAINER" python3 - <<'PYTEST1' || true
import json
import time
import urllib.request

payload = json.dumps({
    "question": "qué carreras tienes cargadas",
    "table": "silabos",
    "collection": "silabos",
    "n_results": 2,
    "limit": 20
}).encode("utf-8")

req = urllib.request.Request(
    "http://127.0.0.1:8000/chat-lateral/ask",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST"
)

t = time.time()
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read().decode("utf-8", errors="replace")
        print("SECONDS", round(time.time() - t, 3))
        print(body[:2500])
except Exception as e:
    print("ERROR_DUCKDB_TEST", repr(e))
PYTEST1

echo
echo "== 11) Test interno Stream/RAG/Ollama ligero =="
docker exec "$DATA_ENGINE_CONTAINER" python3 - <<'PYTEST2' || true
import json
import time
import urllib.request

payload = json.dumps({
    "question": "sugiere brevemente una actividad para un curso de investigación",
    "table": "silabos",
    "collection": "silabos",
    "n_results": 2,
    "limit": 20
}).encode("utf-8")

req = urllib.request.Request(
    "http://127.0.0.1:8000/chat-lateral/ask-stream",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST"
)

t = time.time()
try:
    with urllib.request.urlopen(req, timeout=120) as r:
        body = r.read(5000).decode("utf-8", errors="replace")
        print("SECONDS_FIRST_READ", round(time.time() - t, 3))
        print(body)
except Exception as e:
    print("ERROR_STREAM_TEST", repr(e))
PYTEST2

echo
echo "== 12) Estado final =="
docker compose ps

echo
echo "== Referencias activas al modelo pesado =="
grep -R "qwen2.5-coder:3b" -n . \
  --exclude-dir=.git \
  --exclude-dir=data \
  --exclude-dir=node_modules \
  --exclude-dir=vendor \
  --exclude='*.bak*' \
  --exclude='*.broken*' \
  2>/dev/null | head -80 || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Data Engine parcheado: $ENGINE_FILE"
echo "APIs nuevas:"
echo "  POST /chat-lateral/route"
echo "  POST /chat-lateral/ask"
echo "  POST /chat-lateral/ask-stream"
echo
echo "Si Laravel fue detectado:"
echo "  POST /api/chat-lateral/route"
echo "  POST /api/chat-lateral/ask"
echo "  POST /api/chat-lateral/ask-stream"
echo
echo "Modelo lateral final: $FINAL_MODEL"
echo "num_ctx: $LATERAL_NUM_CTX"
echo "num_predict: $LATERAL_NUM_PREDICT"
