#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# JoMelAI - Script unico de setup/fix
# ============================================================
# Hace:
# 1) Crea resources/knowledge_inbox
# 2) Corrige data-engine: embeddings /api/embed
# 3) Agrega endpoint /rag/answer si falta
# 4) Convierte ZIP/CSV/MD/TXT a data/syllabi/jomelai_knowledge_docs.csv
# 5) Reconstruye data-engine
# 6) Espera health real de FastAPI
# 7) Indexa RAG en ChromaDB con Ollama embeddings
# 8) Cambia orquestador PHP para usar jomelai_knowledge por defecto
#
# NO ejecuta docker compose down -v.
# NO borra modelos Ollama.
# NO borra DuckDB.
# NO borra data/syllabi.
# ============================================================

ROOT_DIR="${1:-$(pwd)}"
cd "$ROOT_DIR"

TS="$(date +%Y%m%d_%H%M%S)"

APP_FILE="data-engine/app.py"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
INBOX_DIR="resources/knowledge_inbox"
WORK_DIR="data/knowledge"
EXTRACT_DIR="$WORK_DIR/extracted"
OUT_CSV="data/syllabi/jomelai_knowledge_docs.csv"
COLLECTION="jomelai_knowledge"

log() {
  echo ""
  echo "==> $1"
}

fail() {
  echo "ERROR: $1"
  exit 1
}

backup() {
  if [ -f "$1" ]; then
    cp "$1" "$1.bak.$TS"
    echo "Backup: $1.bak.$TS"
  fi
}

wait_data_engine() {
  log "Esperando data-engine /health"

  for i in $(seq 1 90); do
    if docker compose exec -T data-engine python - <<'PY' >/dev/null 2>&1
import requests
try:
    r = requests.get("http://localhost:8090/health", timeout=2)
    raise SystemExit(0 if r.status_code == 200 else 1)
except Exception:
    raise SystemExit(1)
PY
    then
      echo "data-engine listo."
      return 0
    fi

    if [ "$i" -eq 90 ]; then
      echo "ERROR: data-engine no respondió."
      docker compose logs --tail=200 data-engine || true
      exit 1
    fi

    sleep 2
  done
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Falta comando requerido: $1"
}

require docker
require python3
require curl

[ -f "$COMPOSE_FILE" ] || fail "No encuentro docker-compose.yml. Ejecuta desde la raíz del proyecto."
[ -f "$APP_FILE" ] || fail "No encuentro $APP_FILE."

log "Creando carpetas"
mkdir -p "$INBOX_DIR" "$WORK_DIR" "$EXTRACT_DIR" "data/syllabi"

log "Backups"
touch "$ENV_FILE"
backup "$ENV_FILE"
backup "$APP_FILE"

ORCH_FILE="$(find backend -type f -name "*.php" 2>/dev/null | xargs grep -l "final class JoMelAiOrchestrator" 2>/dev/null | head -1 || true)"
if [ -n "$ORCH_FILE" ]; then
  backup "$ORCH_FILE"
  echo "Orquestador detectado: $ORCH_FILE"
else
  echo "AVISO: no encontré JoMelAiOrchestrator.php. Se saltará patch PHP."
fi

log "Actualizando .env"
python3 - <<'PY'
from pathlib import Path

path = Path(".env")
raw = path.read_text(encoding="utf-8") if path.exists() else ""

updates = {
    "OLLAMA_BASE_URL": "http://ollama:11434",
    "OLLAMA_MODEL": "qwen2.5-coder:3b",
    "OLLAMA_DEFAULT_MODEL": "qwen2.5-coder:3b",
    "OLLAMA_HTTP_TIMEOUT": "180",
    "OLLAMA_PLAN_TIMEOUT": "180",
    "OLLAMA_PLAN_CTX": "2048",
    "OLLAMA_PLAN_PREDICT": "160",
    "OLLAMA_KEEP_ALIVE": "10m",
    "EMBED_MODEL": "nomic-embed-text",
    "INTENT_ENGINE_MODE": "auto",
    "OLLAMA_INTENT_MODEL": "qwen2.5-coder:3b",
    "OLLAMA_INTENT_TIMEOUT": "180",
    "FAST_INTENT_MIN_CONFIDENCE": "0.90",
    "JOMELAI_RAG_COLLECTION": "jomelai_knowledge",
}

lines = raw.splitlines()
out = []
seen = set()

for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in line:
        out.append(line)
        continue
    key = line.split("=", 1)[0].strip()
    if key in updates:
        out.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        out.append(line)

if out and out[-1].strip():
    out.append("")

out.append("# JoMelAI unified setup")
for k, v in updates.items():
    if k not in seen:
        out.append(f"{k}={v}")

path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
print("OK .env")
PY

log "Corrigiendo data-engine/app.py"
python3 - <<'PY'
from pathlib import Path
import re

p = Path("data-engine/app.py")
s = p.read_text(encoding="utf-8")

# ------------------------------------------------------------
# 1) Corregir embed_one a Ollama /api/embed
# ------------------------------------------------------------
embed_one_new = '''def embed_one(text: str) -> List[float]:
    payload = {
        "model": EMBED_MODEL,
        "input": text
    }

    r = requests.post(f"{OLLAMA_BASE_URL}/api/embed", json=payload, timeout=180)
    r.raise_for_status()

    data = r.json()
    embeddings = data.get("embeddings")

    if not isinstance(embeddings, list) or not embeddings:
        raise RuntimeError("Ollama no devolvio embeddings.")

    emb = embeddings[0]

    if not isinstance(emb, list):
        raise RuntimeError("Ollama devolvio un embedding invalido.")

    return [float(x) for x in emb]
'''

pattern = r"def embed_one\(text: str\) -> List\[float\]:\n.*?(?=\ndef embed_many\()"
s2, count = re.subn(pattern, embed_one_new + "\n", s, flags=re.S)
if count:
    s = s2
    print("OK embed_one -> /api/embed")
else:
    print("AVISO: no se encontró embed_one para reemplazar")

# ------------------------------------------------------------
# 2) Agregar RagAnswerRequest si no existe
# ------------------------------------------------------------
if "class RagAnswerRequest" not in s:
    marker = "class RagSearchRequest(BaseModel):"
    idx = s.find(marker)
    if idx == -1:
        raise SystemExit("No encontré class RagSearchRequest(BaseModel).")
    insert = '''class RagAnswerRequest(BaseModel):
    question: str
    collection: str = Field(default="jomelai_knowledge")
    model: str = Field(default=os.getenv("OLLAMA_MODEL", "qwen2.5-coder:3b"))
    n_results: int = Field(default=5, ge=1, le=20)


'''
    s = s[:idx] + insert + s[idx:]
    print("OK RagAnswerRequest agregado")

# ------------------------------------------------------------
# 3) Agregar /rag/answer si no existe
# ------------------------------------------------------------
endpoint = r'''

@api.post("/rag/answer")
def rag_answer(req: RagAnswerRequest) -> Dict[str, Any]:
    query = (req.question or "").strip()
    if not query:
        raise HTTPException(status_code=422, detail="La pregunta RAG esta vacia.")

    collection = chroma_collection(req.collection)
    q_emb = embed_one(query)

    res = collection.query(
        query_embeddings=[q_emb],
        n_results=req.n_results,
        include=["documents", "metadatas", "distances"]
    )

    docs = res.get("documents", [[]])[0]
    metas = res.get("metadatas", [[]])[0]
    distances = res.get("distances", [[]])[0]

    sources = []
    context_parts = []

    for i, doc in enumerate(docs):
        meta = metas[i] if i < len(metas) else {}
        dist = distances[i] if i < len(distances) else None

        sources.append({
            "document": doc,
            "metadata": meta,
            "distance": dist,
        })

        title = meta.get("title") or meta.get("source_file") or f"Fuente {i + 1}"
        context_parts.append(f"[Fuente {i + 1}: {title}]\\n{doc}")

    context = "\\n\\n".join(context_parts)

    if not context.strip():
        return {
            "ok": True,
            "collection": req.collection,
            "question": query,
            "answer": "No encontré contexto suficiente en la colección indicada.",
            "sources": [],
            "evidence": [],
            "count": 0,
        }

    prompt = f"""
Eres JoMelAI Curriculista. Responde en español, de forma académica, clara y útil.
Usa el contexto recuperado. Si el contexto no alcanza, dilo explícitamente.
No inventes datos numéricos. Para conteos exactos, recomienda usar DuckDB.

Contexto recuperado:
{context}

Pregunta:
{query}

Respuesta:
""".strip()

    try:
        r = requests.post(
            f"{OLLAMA_BASE_URL}/api/generate",
            json={
                "model": req.model,
                "prompt": prompt,
                "stream": False,
                "keep_alive": "10m",
                "options": {
                    "temperature": 0.20,
                    "top_p": 0.85,
                    "num_ctx": 4096,
                    "num_predict": 700
                }
            },
            timeout=180
        )
        r.raise_for_status()
        answer = str(r.json().get("response") or "").strip()
    except Exception as exc:
        answer = (
            "Encontré contexto relacionado, pero no pude generar una síntesis con Ollama. "
            "Revisa las fuentes recuperadas."
        )

    return {
        "ok": True,
        "collection": req.collection,
        "question": query,
        "answer": answer,
        "sources": sources,
        "evidence": sources,
        "count": len(sources),
    }
'''

if '@api.post("/rag/answer")' not in s:
    s = s.rstrip() + "\n\n" + endpoint + "\n"
    print("OK /rag/answer agregado")
else:
    print("OK /rag/answer ya existía")

p.write_text(s, encoding="utf-8")
PY

log "Validando sintaxis app.py local"
python3 -m py_compile "$APP_FILE"

log "Parcheando orquestador PHP si existe"
if [ -n "$ORCH_FILE" ]; then
python3 - "$ORCH_FILE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

s = s.replace(
    "$col    = $collection ?? 'silabos_general';",
    "$col    = $collection ?? (Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge');"
)

s = s.replace(
    "$col = $collection ?? 'silabos_general';",
    "$col = $collection ?? (Support::config('jomelai_rag_collection') ?: 'jomelai_knowledge');"
)

p.write_text(s, encoding="utf-8")
print("OK orquestador usa jomelai_knowledge por defecto")
PY
fi

log "Intentando agregar config jomelai_rag_collection en backend/config/app.php"
if [ -f "backend/config/app.php" ]; then
  backup "backend/config/app.php"
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
        print("OK config app.php")
    else:
        print("AVISO: no pude insertar en app.php")
else:
    print("OK config ya existía")
PY
fi

log "Extrayendo archivos de conocimiento"
find "$INBOX_DIR" -type f -name "*.zip" | while read -r zipfile; do
  name="$(basename "$zipfile" .zip)"
  target="$EXTRACT_DIR/$name"
  mkdir -p "$target"
  unzip -oq "$zipfile" -d "$target"
  echo "ZIP: $zipfile -> $target"
done

mkdir -p "$EXTRACT_DIR/_plain"
find "$INBOX_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "*.csv" \) -exec cp {} "$EXTRACT_DIR/_plain/" \; || true

log "Generando CSV documental para RAG"
python3 - <<'PY'
from pathlib import Path
import csv
import re

root = Path("data/knowledge/extracted")
out = Path("data/syllabi/jomelai_knowledge_docs.csv")
out.parent.mkdir(parents=True, exist_ok=True)

def norm_text(s):
    s = str(s or "").replace("\x00", " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s

def source_type(path):
    p = str(path).lower()
    if "malla" in p:
        return "malla_curricular"
    if "silabo" in p:
        return "silabo"
    if "entrenamiento" in p:
        return "training_examples"
    if "reporte" in p:
        return "report_examples"
    if path.suffix.lower() == ".csv":
        return "csv_rows"
    return "document"

def infer_program(path, text=""):
    raw = (str(path) + " " + text[:700]).lower()
    rules = [
        ("sistemas", "Ingeniería de Sistemas"),
        ("enfermer", "Enfermería"),
        ("administr", "Administración"),
        ("negocios internacionales", "Administración y Negocios Internacionales"),
        ("contabilidad", "Contabilidad"),
        ("psicolog", "Psicología"),
        ("medicina", "Medicina Humana"),
        ("nutric", "Nutrición Humana"),
        ("odontolog", "Odontología"),
        ("teolog", "Teología"),
        ("arquitect", "Arquitectura"),
        ("civil", "Ingeniería Civil"),
        ("ambiental", "Ingeniería Ambiental"),
        ("educacion", "Educación"),
        ("educación", "Educación"),
    ]
    for k, v in rules:
        if k in raw:
            return v
    return ""

def infer_cycle(path, text=""):
    raw = (str(path) + " " + text[:500]).lower()
    m = re.search(r"(?:ciclo|semestre)[_\s-]*(\d{1,2})", raw)
    return m.group(1) if m else ""

def detect_delimiter(sample):
    candidates = [",", ";", "\t", "|"]
    best = ","
    best_score = -1
    lines = [x for x in sample.splitlines() if x.strip()][:30]
    for c in candidates:
        counts = [line.count(c) for line in lines]
        positives = [x for x in counts if x > 0]
        if not positives:
            continue
        score = sum(positives)
        if score > best_score:
            best_score = score
            best = c
    return best

def read_text_file(path):
    for enc in ["utf-8", "utf-8-sig", "latin-1", "windows-1252"]:
        try:
            return path.read_text(encoding=enc, errors="replace")
        except Exception:
            pass
    return ""

rows = []

for path in root.rglob("*"):
    if not path.is_file():
        continue

    suffix = path.suffix.lower()

    if suffix in {".md", ".txt"}:
        text = read_text_file(path)
        parts = re.split(r"(?m)^#{1,4}\s+", text)
        if len(parts) <= 1:
            parts = [text]

        for idx, part in enumerate(parts):
            content = norm_text(part)
            if len(content) < 40:
                continue
            rows.append({
                "source_type": source_type(path),
                "source_file": str(path),
                "title": path.stem.replace("_", " ").replace("-", " "),
                "programa": infer_program(path, content),
                "ciclo": infer_cycle(path, content),
                "section": str(idx),
                "content": content[:6000],
            })

    elif suffix == ".csv":
        raw = read_text_file(path)
        if not raw.strip():
            continue

        delim = detect_delimiter(raw[:10000])

        try:
            reader = csv.DictReader(raw.splitlines(), delimiter=delim)
            for i, row in enumerate(reader, start=1):
                pieces = []
                for k, v in row.items():
                    k = str(k or "").strip()
                    v = str(v or "").strip()
                    if k and v:
                        pieces.append(f"{k}: {v}")
                content = norm_text("\n".join(pieces))
                if len(content) < 30:
                    continue
                rows.append({
                    "source_type": source_type(path),
                    "source_file": str(path),
                    "title": path.stem.replace("_", " ").replace("-", " "),
                    "programa": infer_program(path, content),
                    "ciclo": infer_cycle(path, content),
                    "section": str(i),
                    "content": content[:6000],
                })
        except Exception as exc:
            print(f"AVISO: no pude leer CSV {path}: {exc}")

with out.open("w", newline="", encoding="utf-8") as fh:
    writer = csv.DictWriter(
        fh,
        fieldnames=["source_type", "source_file", "title", "programa", "ciclo", "section", "content"]
    )
    writer.writeheader()
    writer.writerows(rows)

print(f"OK: {out} generado con {len(rows)} documentos.")
if not rows:
    print("AVISO: No se encontraron documentos. Coloca ZIP/CSV/MD/TXT en resources/knowledge_inbox y vuelve a ejecutar.")
PY

log "Levantando Ollama y descargando modelo de embeddings"
docker compose up -d ollama
docker compose exec -T ollama ollama pull nomic-embed-text

log "Reconstruyendo servicios necesarios"
docker compose build --no-cache data-engine

if [ -n "$ORCH_FILE" ]; then
  docker compose build --no-cache backend || true
fi

docker compose up -d --force-recreate data-engine
if [ -n "$ORCH_FILE" ]; then
  docker compose up -d --force-recreate backend || true
fi

wait_data_engine

log "Validando endpoints base"
docker compose exec -T data-engine python - <<'PY'
import requests
for url in ["http://localhost:8090/health", "http://localhost:8090/fs/status"]:
    r = requests.get(url, timeout=15)
    print(url, r.status_code, r.text[:300])
PY

log "Indexando RAG si hay documentos"
DOC_COUNT="$(python3 - <<'PY'
import csv
from pathlib import Path
p = Path("data/syllabi/jomelai_knowledge_docs.csv")
if not p.exists():
    print(0)
else:
    with p.open(encoding="utf-8") as fh:
        print(max(0, sum(1 for _ in fh) - 1))
PY
)"

if [ "$DOC_COUNT" -gt 0 ]; then
  echo "Documentos a indexar: $DOC_COUNT"

  JOB_RAW="$(curl -s http://localhost:3000/api/data-engine/jobs/rag-build \
    -H "Content-Type: application/json" \
    -d "{
      \"file_path\":\"/data/syllabi/jomelai_knowledge_docs.csv\",
      \"collection\":\"$COLLECTION\",
      \"delimiter\":\",\",
      \"encoding\":\"utf-8\",
      \"chunk_size_rows\":200,
      \"row_limit\":0,
      \"text_columns\":[\"title\",\"programa\",\"ciclo\",\"content\"],
      \"metadata_columns\":[\"source_type\",\"source_file\",\"title\",\"programa\",\"ciclo\",\"section\"],
      \"document_chars\":1300,
      \"overlap_chars\":180,
      \"embed_batch_size\":8,
      \"reset_collection\":true
    }")"

  echo "$JOB_RAW"

  JOB_ID="$(python3 - <<PY
import json
raw = '''$JOB_RAW'''
try:
    data = json.loads(raw)
    print((data.get("job") or {}).get("id") or data.get("job_id") or "")
except Exception:
    print("")
PY
)"

  if [ -n "$JOB_ID" ]; then
    log "Esperando job RAG: $JOB_ID"
    for i in $(seq 1 900); do
      STATUS_RAW="$(curl -s "http://localhost:3000/api/data-engine/jobs/$JOB_ID" || true)"
      STATUS="$(python3 - <<PY
import json
raw = '''$STATUS_RAW'''
try:
    data = json.loads(raw)
    print((data.get("job") or {}).get("status") or "")
except Exception:
    print("")
PY
)"
      PROGRESS="$(python3 - <<PY
import json
raw = '''$STATUS_RAW'''
try:
    data = json.loads(raw)
    print((data.get("job") or {}).get("progress") or "")
except Exception:
    print("")
PY
)"
      echo "RAG status=$STATUS progress=$PROGRESS"

      if [ "$STATUS" = "success" ]; then
        break
      fi

      if [ "$STATUS" = "error" ] || [ "$STATUS" = "cancelled" ]; then
        echo "$STATUS_RAW"
        exit 1
      fi

      sleep 3
    done
  else
    echo "AVISO: no pude obtener JOB_ID. Revisa /jobs manualmente."
  fi
else
  echo "AVISO: $OUT_CSV no tiene documentos. No se indexó RAG."
fi

log "Pruebas finales"

docker compose exec -T data-engine python - <<'PY'
import requests, json

tests = [
    ("intent", "puedes listarme los cursos de sistemas que tienes cargados ?"),
    ("intent", "cuantos silabos tiene ingenieria de sistemas ?"),
    ("rag", "qué información tienes sobre la malla de ingeniería de sistemas"),
]

for kind, q in tests:
    print("\nQUESTION:", q)
    if kind == "intent":
        r = requests.post(
            "http://localhost:8090/intent/resolve",
            json={"question": q, "table": "silabos"},
            timeout=180
        )
    else:
        r = requests.post(
            "http://localhost:8090/rag/answer",
            json={"question": q, "collection": "jomelai_knowledge", "n_results": 5},
            timeout=180
        )

    print("STATUS:", r.status_code)
    try:
        data = r.json()
        mini = {
            "ok": data.get("ok"),
            "mode": data.get("mode"),
            "report_intent": data.get("report_intent"),
            "chart_type": data.get("chart_type"),
            "engine": data.get("engine"),
            "collection": data.get("collection"),
            "count": data.get("count"),
            "sql": data.get("sql"),
            "answer": (data.get("answer") or "")[:400],
        }
        print(json.dumps(mini, ensure_ascii=False, indent=2))
    except Exception:
        print(r.text[:2000])
PY

log "Estado final"
docker compose ps

echo ""
echo "============================================================"
echo "LISTO."
echo ""
echo "Carpeta para meter archivos de conocimiento:"
echo "  $INBOX_DIR"
echo ""
echo "CSV documental generado:"
echo "  $OUT_CSV"
echo ""
echo "Colección RAG:"
echo "  $COLLECTION"
echo ""
echo "Para agregar más archivos:"
echo "  1) copia ZIP/CSV/MD/TXT a $INBOX_DIR"
echo "  2) vuelve a ejecutar: ./jomelai_setup_unico.sh"
echo ""
echo "No se borraron volúmenes."
echo "============================================================"
