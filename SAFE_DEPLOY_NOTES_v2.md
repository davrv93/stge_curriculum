# JoMelAi vNext safe patch

## No toca datos persistentes
Este ZIP excluye `data/ollama`, `data/duckdb`, `data/syllabi` y `data/backend/storage` para evitar pérdida de modelos, DuckDB, sílabos o archivos de usuario.

No usar:

```bash
docker compose down -v
rm -rf data/ollama data/duckdb data/syllabi
```

Usar:

```bash
docker compose up -d --build
```

## Cambios aplicados

- UI clara: contenedores blancos, mejor contraste y fondo suave.
- Partículas suaves preservadas en todo el sistema.
- Corrección de error JS por variable duplicada en `generateMalla()`.
- Corrección de `/api/ask`: `JoMelAiResponseFormatter.php` ya no está vacío.
- Respuesta del panel JoMelAi ahora puede mostrar tabla y gráfico si el backend los retorna.
- FastIntentEngine integrado también al orquestador JoMelAi para evitar Ollama en conteos, rankings, agrupaciones y gráficos simples.
- Nuevo análisis semántico rápido de propuestas sin Ollama: `/semantic/analyze-proposal`.
- Registro básico de plantillas: `/templates/list` y `/templates/render`.
- Scripts de modelos verifican si el modelo ya existe antes de descargar.

## Arquitectura de rendimiento

1. Pregunta estructurada frecuente → FastIntentEngine → DuckDB → respuesta rápida.
2. Propuesta/formato/contextualización → SemanticProposalAnalyzer → recomendaciones rápidas.
3. Redacción compleja, interpretación curricular, generación cualitativa → RAG/Ollama fallback.

## Marco adventista

El analizador semántico detecta lenguaje incompatible con el marco institucional adventista y prioriza construcción curricular compatible con Biblia sin apócrifos, identidad IASD, Elena G. de White/La Educación, SUNEDU y modelos curriculares científicamente aceptables sin contradecir principios bíblicos.
