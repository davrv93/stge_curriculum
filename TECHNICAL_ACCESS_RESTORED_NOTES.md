# Patch: restauración de Acceso Técnico DuckDB/RAG/Reportes

Este patch restaura el acceso técnico desde la UI para:

- Subir datasets curriculares al volumen compartido `/data/syllabi`.
- Perfilar CSV/TSV antes de importarlo.
- Importar sílabos, mallas, planes, recursos o evidencias a DuckDB mediante jobs asíncronos.
- Construir RAG general o RAG por colecciones mediante jobs asíncronos.
- Consultar estado de DuckDB, Chroma/RAG, Ollama y jobs.
- Cancelar jobs en cola/ejecución desde la UI.
- Generar reportes dinámicos con texto libre usando FastIntentEngine antes de Ollama.

## Seguridad de datos

No incluye ni modifica datos de estos volúmenes:

- `data/ollama`
- `data/duckdb`
- `data/syllabi`
- `data/backend/storage`

## Despliegue seguro

```bash
docker compose up -d --build
```

No usar:

```bash
docker compose down -v
```

## Ruta en UI

Sidebar → **Acceso técnico**.

## Flujo recomendado

1. Subir archivo.
2. Perfilar CSV.
3. Importar a DuckDB con tabla destino: `silabos`, `malla_curricular`, `plan_estudios`, `recurso_aprendizaje` o `sunedu_evidencia_curricular`.
4. Crear RAG general o por secciones.
5. Probar reportes dinámicos desde la misma pantalla.
