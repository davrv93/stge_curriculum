#!/usr/bin/env bash
set -euo pipefail

CSV_PATH="${1:-lamb_curriculo_upeu_10000_preguntas.csv}"
COLLECTION="${2:-jomelai_memory}"
BATCH_SIZE="${3:-32}"

if [ ! -f "$CSV_PATH" ]; then
  echo "ERROR: No existe el CSV: $CSV_PATH"
  echo ""
  echo "Uso:"
  echo "  ./import_lamb_curriculo_csv_to_memory.sh lamb_curriculo_upeu_10000_preguntas.csv"
  echo "  ./import_lamb_curriculo_csv_to_memory.sh lamb_curriculo_upeu_10000_preguntas.csv jomelai_memory 32"
  exit 1
fi

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

echo "==> Verificando data-engine..."
CONTAINER_ID="$($DC ps -q data-engine)"

if [ -z "$CONTAINER_ID" ]; then
  echo "ERROR: El servicio data-engine no está corriendo."
  echo "Ejecuta:"
  echo "  docker compose up -d data-engine"
  exit 1
fi

echo "==> Copiando CSV al contenedor data-engine..."
docker cp "$CSV_PATH" "$CONTAINER_ID:/tmp/lamb_curriculo_upeu_10000_preguntas.csv"

echo "==> Importando CSV a colección: $COLLECTION"
echo "==> Batch size: $BATCH_SIZE"

$DC exec -T data-engine sh -lc "cd /app && python - '$COLLECTION' '$BATCH_SIZE' <<'PY'
import csv
import hashlib
import json
import re
import sys
import time
import unicodedata
from pathlib import Path
from typing import Any, Dict, List, Optional

import pandas as pd

from app import chroma_collection, embed_many, now_str

CSV_FILE = Path('/tmp/lamb_curriculo_upeu_10000_preguntas.csv')
COLLECTION = sys.argv[1] if len(sys.argv) > 1 else 'jomelai_memory'
BATCH_SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 32

if not CSV_FILE.is_file():
    raise SystemExit('No existe /tmp/lamb_curriculo_upeu_10000_preguntas.csv dentro del contenedor.')

def strip_accents(value: str) -> str:
    return ''.join(
        c for c in unicodedata.normalize('NFD', str(value or ''))
        if unicodedata.category(c) != 'Mn'
    )

def norm(value: str) -> str:
    value = strip_accents(value).lower().strip()
    value = re.sub(r'[^a-z0-9]+', '_', value).strip('_')
    return value

def norm_text(value: str) -> str:
    value = strip_accents(value).lower().strip()
    value = re.sub(r'[^a-z0-9áéíóúüñ ]+', ' ', value)
    return re.sub(r'\s+', ' ', value).strip()

def detect_encoding(path: Path) -> str:
    data = path.read_bytes()[:262144]
    if data.startswith(b'\xef\xbb\xbf'):
        return 'utf-8-sig'
    for enc in ['utf-8', 'utf-8-sig', 'latin-1', 'windows-1252']:
        try:
            data.decode(enc)
            return enc
        except Exception:
            pass
    return 'latin-1'

def detect_delimiter(path: Path, encoding: str) -> str:
    sample = path.read_text(encoding=encoding, errors='replace')[:262144]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=[',', ';', '\t', '|'])
        return dialect.delimiter
    except Exception:
        pass

    lines = [x for x in sample.splitlines() if x.strip()][:100]
    candidates = [',', ';', '\t', '|']
    best = ','
    best_score = -1

    for cand in candidates:
        counts = [line.count(cand) for line in lines]
        positives = [c for c in counts if c > 0]
        if not positives:
            continue
        avg = sum(positives) / len(positives)
        score = avg * len(positives)
        if score > best_score:
            best_score = score
            best = cand

    return best

def pick_column(columns: List[str], candidates: List[str]) -> Optional[str]:
    normalized = {norm(c): c for c in columns}

    for cand in candidates:
        key = norm(cand)
        if key in normalized:
            return normalized[key]

    for c in columns:
        nc = norm(c)
        for cand in candidates:
            if norm(cand) in nc:
                return c

    return None

def clean(value: Any) -> str:
    value = '' if value is None else str(value)
    value = value.replace('\r\n', '\n').replace('\r', '\n')
    value = re.sub(r'\n{3,}', '\n\n', value)
    return value.strip()

def infer_artifact_type(question: str, answer: str, row: Dict[str, Any]) -> str:
    full = norm_text(' '.join([
        question,
        answer,
        ' '.join(str(v) for v in row.values() if v is not None)
    ]))

    if any(x in full for x in ['distribuir credito', 'distribuir creditos', 'repartir credito', 'malla de 10 ciclos', 'carga crediticia']):
        return 'curriculum_grid_credit_distribution'

    if any(x in full for x in ['resultado de aprendizaje', 'verbos', 'verbo observable', 'bloom']):
        return 'learning_outcomes'

    if any(x in full for x in ['perfil de egreso', 'alinear perfil', 'trazabilidad curricular', 'matriz curricular']):
        return 'curriculum_alignment'

    if any(x in full for x in ['rubrica', 'niveles de desempeno', 'criterios de evaluacion']):
        return 'rubric'

    if any(x in full for x in ['lectura guiada', 'ficha de lectura']):
        return 'guided_reading'

    if any(x in full for x in ['caso practico', 'caso práctico', 'analisis de caso']):
        return 'practical_case'

    if any(x in full for x in ['actividad de aprendizaje', 'actividades sugeridas', 'secuencia didactica']):
        return 'learning_activities'

    if any(x in full for x in ['semipresencial', 'aula invertida', 'estrategia didactica']):
        return 'teaching_strategies'

    if any(x in full for x in ['silabo', 'sumilla', 'competencia', 'unidad', 'sesion']):
        return 'syllabus_support'

    return 'curricular_knowledge'

def infer_topic(question: str, row: Dict[str, Any]) -> str:
    topic_cols = [
        'tema', 'topico', 'tópico', 'topic',
        'curso', 'asignatura', 'materia',
        'categoria', 'category', 'tipo'
    ]

    for col in topic_cols:
        for k, v in row.items():
            if norm(k) == norm(col) and clean(v):
                return clean(v)[:120]

    patterns = [
        r'curso\s+\"([^\"]+)\"',
        r'curso\s+de\s+([^?.]+)',
        r'asignatura\s+de\s+([^?.]+)',
        r'materia\s+de\s+([^?.]+)',
        r'para\s+el\s+curso\s+([^?.]+)',
        r'para\s+un\s+curso\s+de\s+([^?.]+)',
    ]

    for p in patterns:
        m = re.search(p, question, flags=re.I)
        if m:
            return clean(m.group(1))[:120]

    return ''

def row_to_answer(row: Dict[str, Any], skip_cols: List[str]) -> str:
    parts = []
    for k, v in row.items():
        if k in skip_cols:
            continue
        cv = clean(v)
        if cv:
            parts.append(f'{k}: {cv}')
    return '\n'.join(parts).strip()

def make_doc(question: str, answer: str) -> str:
    return f'Pregunta:\n{question}\n\nRespuesta validada:\n{answer}'

def metadata_value(value: Any) -> str:
    value = '' if value is None else str(value)
    return value[:500]

started = time.time()
encoding = detect_encoding(CSV_FILE)
delimiter = detect_delimiter(CSV_FILE, encoding)

print('CSV:', CSV_FILE)
print('Encoding:', encoding)
print('Delimiter:', repr(delimiter))

df = pd.read_csv(
    CSV_FILE,
    sep=delimiter,
    encoding=encoding,
    dtype=str,
    keep_default_na=False,
    engine='python',
    on_bad_lines='skip'
)

df.columns = [str(c).strip() for c in df.columns]
columns = list(df.columns)

print('Filas leídas:', len(df))
print('Columnas:', columns)

question_col = pick_column(columns, [
    'pregunta', 'question', 'consulta', 'query',
    'prompt', 'input', 'entrada', 'instruccion', 'instrucción',
    'user_question', 'user_prompt', 'mensaje'
])

answer_col = pick_column(columns, [
    'respuesta', 'answer', 'completion', 'output',
    'salida', 'respuesta_validada', 'expected_answer',
    'contenido', 'content', 'markdown', 'recurso',
    'texto', 'solucion', 'solución'
])

intent_col = pick_column(columns, ['intent', 'intencion', 'intención'])
artifact_col = pick_column(columns, ['artifact_type', 'tipo_artefacto', 'tipo', 'categoria', 'category'])
topic_col = pick_column(columns, ['topic', 'topico', 'tópico', 'tema', 'curso', 'asignatura', 'materia'])

print('Columna pregunta detectada:', question_col)
print('Columna respuesta detectada:', answer_col)
print('Columna intent detectada:', intent_col)
print('Columna artifact_type detectada:', artifact_col)
print('Columna topic detectada:', topic_col)

if not question_col:
    # Fallback: usar la primera columna textual larga como pregunta/título.
    question_col = columns[0]
    print('WARN: No se detectó columna pregunta. Usaré:', question_col)

collection = chroma_collection(COLLECTION)

ids = []
docs = []
metas = []

ok_rows = 0
skipped = 0

for idx, row in df.iterrows():
    raw = {c: clean(row.get(c, '')) for c in columns}

    question = clean(raw.get(question_col, ''))

    if not question:
        skipped += 1
        continue

    if answer_col and clean(raw.get(answer_col, '')):
        answer = clean(raw.get(answer_col, ''))
    else:
        answer = row_to_answer(raw, skip_cols=[question_col])

    if not answer:
        # Si el CSV solo trae preguntas, al menos guardar pregunta como conocimiento.
        answer = 'Pregunta curricular registrada para recuperación semántica. Requiere respuesta generativa con JoMelAI y contexto institucional.'

    artifact_type = clean(raw.get(artifact_col, '')) if artifact_col else ''
    if not artifact_type:
        artifact_type = infer_artifact_type(question, answer, raw)

    topic = clean(raw.get(topic_col, '')) if topic_col else ''
    if not topic:
        topic = infer_topic(question, raw)

    intent = clean(raw.get(intent_col, '')) if intent_col else 'curricular_advice'

    doc = make_doc(question, answer)

    # Evitar documentos absurdamente largos.
    if len(doc) > 12000:
        doc = doc[:12000]

    stable = hashlib.sha1((COLLECTION + '|' + question + '|' + answer[:1000]).encode('utf-8', errors='ignore')).hexdigest()
    item_id = 'lamb:' + stable

    meta = {
        'source': 'lamb_curriculo_upeu_10000_preguntas.csv',
        'intent': intent or 'curricular_advice',
        'topic': topic,
        'artifact_type': artifact_type,
        'approved': 'true',
        'row_index': str(idx),
        'created_at': now_str(),
    }

    # Agregar algunas columnas útiles como metadata.
    for k in ['facultad', 'programa', 'programa_estudio', 'carrera', 'curso', 'asignatura', 'categoria', 'category', 'tipo']:
        if k in raw and raw[k]:
            meta[norm(k)[:60]] = metadata_value(raw[k])

    ids.append(item_id)
    docs.append(doc)
    metas.append(meta)
    ok_rows += 1

print('Registros preparados:', ok_rows)
print('Registros omitidos:', skipped)

inserted = 0

for start in range(0, len(docs), BATCH_SIZE):
    batch_docs = docs[start:start+BATCH_SIZE]
    batch_ids = ids[start:start+BATCH_SIZE]
    batch_metas = metas[start:start+BATCH_SIZE]

    embeddings = embed_many(batch_docs)

    collection.upsert(
        ids=batch_ids,
        documents=batch_docs,
        metadatas=batch_metas,
        embeddings=embeddings,
    )

    inserted += len(batch_docs)

    if inserted % max(BATCH_SIZE * 5, 100) == 0 or inserted == len(docs):
        print(f'Progreso: {inserted}/{len(docs)}')

seconds = round(time.time() - started, 2)

print(json.dumps({
    'ok': True,
    'collection': COLLECTION,
    'rows_read': int(len(df)),
    'prepared': ok_rows,
    'skipped': skipped,
    'inserted_or_updated': inserted,
    'seconds': seconds,
    'question_col': question_col,
    'answer_col': answer_col,
    'artifact_col': artifact_col,
    'topic_col': topic_col,
}, ensure_ascii=False, indent=2))

print('\\nPruebas de búsqueda:')

tests = [
    'Cómo distribuir créditos en una malla de 10 ciclos',
    'Sugiere actividades para un curso de investigación',
    'Qué verbos usar en resultados de aprendizaje',
    'Cómo alinear el perfil de egreso con los cursos',
    'rúbrica de evaluación',
    'lectura guiada',
    'caso práctico',
]

for q in tests:
    q_emb = embed_many([q])[0]
    res = collection.query(
        query_embeddings=[q_emb],
        n_results=3,
        include=['documents', 'metadatas', 'distances'],
    )

    print('\\nQUERY:', q)
    docs0 = res.get('documents', [[]])[0]
    metas0 = res.get('metadatas', [[]])[0]
    distances0 = res.get('distances', [[]])[0]

    for i, doc in enumerate(docs0):
        meta = metas0[i] if i < len(metas0) else {}
        dist = distances0[i] if i < len(distances0) else None
        print(' - distance:', dist, 'artifact:', meta.get('artifact_type'), 'topic:', meta.get('topic'))
        print('   ', doc[:260].replace('\\n', ' ') + '...')
PY"

echo "==> Importación terminada."
echo ""
echo "Prueba desde el backend:"
echo "docker compose exec -T data-engine python - <<'PY'"
echo "import requests, json"
echo "r = requests.post('http://localhost:8090/memory/search', json={'query':'Sugiere actividades para un curso de investigación','collection':'$COLLECTION','n_results':5}, timeout=60)"
echo "print(json.dumps(r.json(), ensure_ascii=False, indent=2)[:3000])"
echo "PY"
