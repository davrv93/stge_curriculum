import argparse
import json
import sys
import requests

BASE = "http://127.0.0.1:8090"

def post(path, payload):
    r = requests.post(BASE + path, json=payload, timeout=3600)
    try:
        data = r.json()
    except Exception:
        print(r.text)
        r.raise_for_status()
        return
    print(json.dumps(data, ensure_ascii=False, indent=2))
    if not r.ok or not data.get("ok", False):
        sys.exit(1)

parser = argparse.ArgumentParser(description="CLI interna UPeU Silabo AI data-engine")
sub = parser.add_subparsers(dest="cmd", required=True)

duck = sub.add_parser("duckdb", help="Convertir CSV a DuckDB")
duck.add_argument("csv", nargs="?", default="/data/syllabi/silabos.csv")
duck.add_argument("--table", default="silabos")
duck.add_argument("--delimiter", default="")
duck.add_argument("--encoding", default="")
duck.add_argument("--skip-rows", type=int, default=0)
duck.add_argument("--sample-size", type=int, default=20000)

rag = sub.add_parser("rag", help="Construir indice RAG")
rag.add_argument("csv", nargs="?", default="/data/syllabi/silabos.csv")
rag.add_argument("--collection", default="silabos")
rag.add_argument("--limit", type=int, default=2000)
rag.add_argument("--chunk", type=int, default=1000)
rag.add_argument("--batch", type=int, default=16)
rag.add_argument("--reset", action="store_true")

chart = sub.add_parser("chart", help="Generar grafico de prueba desde SQL")
chart.add_argument("sql")
chart.add_argument("--type", default="bar")
chart.add_argument("--title", default="Reporte curricular")
chart.add_argument("--x", default="")
chart.add_argument("--y", default="")

args = parser.parse_args()
if args.cmd == "duckdb":
    post("/duckdb/import", {
        "file_path": args.csv,
        "table": args.table,
        "delimiter": args.delimiter or None,
        "encoding": args.encoding or None,
        "skip_rows": args.skip_rows,
        "strict_mode": False,
        "null_padding": True,
        "max_line_size": 10000000,
        "replace": True,
        "sample_size": args.sample_size,
        "normalize_columns": True,
    })
elif args.cmd == "rag":
    post("/rag/build", {
        "file_path": args.csv,
        "collection": args.collection,
        "row_limit": args.limit,
        "chunk_size_rows": args.chunk,
        "embed_batch_size": args.batch,
        "reset_collection": args.reset,
    })
elif args.cmd == "chart":
    post("/duckdb/chart", {
        "sql": args.sql,
        "chart_type": args.type,
        "title": args.title,
        "x": args.x or None,
        "y": args.y or None,
        "limit": 200,
    })
