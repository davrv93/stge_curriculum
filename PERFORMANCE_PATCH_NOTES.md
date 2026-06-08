# Patch de rendimiento JoMelAI vNext

Objetivo: que la generación de plan de estudios no bloquee la API ni dependa de una única llamada larga a Ollama.

## Cambios aplicados

- `CurriculumController::generatePlan()` ahora usa estrategia `template_first`:
  - genera plan determinístico enriquecido en milisegundos;
  - usa referencias locales de mallas UPeU cuando encuentra coincidencia por programa;
  - llama a Ollama solo para una revisión corta, no para construir toda la malla;
  - timeout duro configurable para Ollama (`OLLAMA_PLAN_TIMEOUT`, por defecto 12 s);
  - cache SQLite por 24 h para solicitudes repetidas.
- `OllamaClient` ahora acepta timeout por llamada y método `generateFast()` con:
  - `num_ctx` bajo;
  - `num_predict` limitado;
  - temperatura baja;
  - corte rápido si Ollama se cuelga.
- `/api/ask` / `JoMelAiOrchestrator::runStudyPlan()` también pasa a generación rápida:
  - plantilla primero;
  - cursos de referencia local;
  - revisión IA corta y no bloqueante.
- Se agregaron tablas SQLite:
  - `curriculum_generation_cache`
  - `curriculum_semantic_memory`
- Se agregaron recursos semánticos locales:
  - mallas curriculares UPeU en Markdown;
  - reporte de intents UPeU 700;
  - ZIP de sílabos de referencia.

## Variables recomendadas

```env
OLLAMA_HTTP_TIMEOUT=15
OLLAMA_PLAN_TIMEOUT=12
OLLAMA_PLAN_CTX=2048
OLLAMA_PLAN_PREDICT=420
CURRICULUM_CACHE_TTL_SECONDS=86400
```

## Regla crítica de despliegue

No ejecutar:

```bash
docker compose down -v
```

Sí ejecutar:

```bash
docker compose up -d --build
```

Este patch no incluye ni modifica `data/ollama`, `data/duckdb`, `data/syllabi` ni `data/backend/storage`.
