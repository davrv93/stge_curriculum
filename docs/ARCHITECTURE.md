# Arquitectura UPeU Sílabo AI v2

## Diseño general

```text
Usuario -> Nginx :80 -> Frontend estático
                   -> /api/* -> Backend PHP :8080 -> SQLite operativo
                                             -> Data Engine :8090 -> DuckDB / ChromaDB
                                             -> Ollama :11434 -> LLM / embeddings
```

El navegador nunca llama directamente a Ollama ni a Data Engine. Todo pasa por el backend para mantener sesión, control de rol y proxy same-origin.

## Capas de datos

### SQLite operativo

Usado para usuarios, sesiones, historial, importaciones e índice básico FTS.

### DuckDB analítico

Usado para convertir el CSV gigante a una base local en disco. Permite filtros, agregaciones y consultas SQL sin cargar 750 MB en memoria.

La app obliga a que las consultas enviadas desde el frontend sean `SELECT` o `WITH`. Las consultas generadas por Ollama también pasan por esa validación.

### ChromaDB vectorial

Usado para RAG. El CSV se procesa por chunks de Pandas; cada fila se convierte en texto curricular y se fragmenta. Los embeddings se generan vía Ollama con `nomic-embed-text` y se almacenan de forma persistente.

## Proxy Nginx

`location ^~ /api/` apunta a `http://backend:8080`. El frontend usa rutas relativas `/api/...`, por lo que no hay CORS ni exposición de puertos internos.

## Seguridad mínima incluida

- Sesión PHP HTTP-only.
- Cookies SameSite=Lax.
- Rutas protegidas por `Support::requireAuth()`.
- Importación/indexación protegida por `Support::requireAdmin()`.
- SQL restringido a consultas de lectura.
- Ollama y data-engine no exponen puertos públicos.

## Producción recomendada

- Cambiar credenciales demo.
- Usar HTTPS.
- Añadir colas para indexación RAG completa.
- Añadir auditoría de consultas SQL y respuestas generadas.
- Migrar backend ligero a Laravel completo si se necesita Sanctum, policies, jobs y notificaciones.

## Mejora aplicada: jobs, perfilado y RAG por colecciones

La versión actual incorpora un flujo recomendado para CSV de 700 MB:

1. **Perfilado por muestra**: `POST /api/setup/profile-csv` delega a `data-engine:/csv/profile`. Lee solo una muestra configurable, detecta delimitador, estima filas y recomienda columnas de filtro/texto.
2. **Jobs con progreso**: descargas Ollama, conversión DuckDB y RAG se ejecutan como trabajos persistidos en `data/jobs/jobs.json`.
3. **DuckDB en disco**: la tabla `silabos` queda en `data/duckdb/silabos.duckdb` y se consulta con SQL seguro solo `SELECT/WITH`.
4. **RAG por colecciones**: una sola pasada por CSV puede crear colecciones separadas para `general`, `competencias`, `sumillas`, `contenidos` y `bibliografia`.
5. **Portal usuario**: el modo automático decide entre gráfico, SQL o RAG. Para RAG el backend selecciona colección según palabras clave de la pregunta.
6. **Gráficos exportables**: matplotlib genera PNG y la UI permite descargar PNG/CSV de soporte.

Ollama, Data Engine y Chroma no se publican hacia Internet; solo Nginx expone el frontend y `/api` por same-origin.
