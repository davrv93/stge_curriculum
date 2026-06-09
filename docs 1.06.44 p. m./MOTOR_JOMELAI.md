# Motor JoMelAi

**Sistema Integral de Sílabos Académicos UPeU**  
Versión: 1.0 · Módulo de orquestación inteligente

---

## ¿Qué es el Motor JoMelAi?

Motor JoMelAi es la capa de abstracción inteligente del Sistema de Sílabos UPeU. Permite que cualquier usuario —sin conocimientos técnicos— acceda a todas las capacidades del sistema mediante lenguaje natural.

El usuario escribe lo que necesita. El motor decide automáticamente cómo obtenerlo.

**Nombre técnico:** `JoMelAiEngine`  
**Mascota:** JoMel (robot académico con birrete)  
**Endpoint principal:** `POST /api/ask`

---

## ¿Qué problema resuelve?

El sistema cuenta con múltiples motores internos:

| Motor interno     | Tecnología     | Uso ideal                          |
|-------------------|----------------|------------------------------------|
| Análisis de datos | DuckDB         | Consultas estructuradas, gráficos  |
| Búsqueda inteligente | ChromaDB + Embeddings | Contenido semántico de sílabos |
| Asistente         | Ollama / Qwen  | Generación y síntesis de texto     |
| Curricular        | Módulo propio  | Planes y mallas curriculares       |

Sin Motor JoMelAi, el usuario tendría que elegir manualmente entre RAG, DuckDB, wizard curricular y reportes. Con él, solo escribe su pregunta.

---

## Clasificación de intenciones

El `JoMelAiIntentClassifier` analiza la pregunta y devuelve una de estas intenciones:

| Intención              | Visible para el usuario     | Motor interno    |
|------------------------|-----------------------------|------------------|
| `chart`                | Generar gráfico             | Análisis de datos |
| `statistics`           | Consultar datos académicos  | Análisis de datos |
| `semantic_search`      | Búsqueda en sílabos         | Búsqueda inteligente |
| `course_lookup`        | Búsqueda de curso           | Híbrido          |
| `comparison`           | Comparar cursos             | Híbrido          |
| `syllabus_generation`  | Crear propuesta de sílabo   | Asistente        |
| `study_plan`           | Diseñar plan de estudios    | Curricular       |
| `curriculum_grid`      | Revisar malla curricular    | Curricular       |
| `report`               | Generar informe             | Híbrido          |
| `dataset_quality`      | Revisar calidad del dataset | Análisis de datos |
| `unknown`              | Orientación                 | Asistente        |

La clasificación usa coincidencia de palabras clave con sistema de prioridad y puntuación de confianza.

---

## Flujo de una consulta

```
Usuario escribe pregunta
        ↓
JoMelAiIntentClassifier
  → devuelve: intent, engine, confidence, collection
        ↓
JoMelAiOrchestrator
  → redirige al motor correcto:
    chart       → /charts/natural (DuckDB + matplotlib)
    statistics  → /duckdb/query (SQL generado por AI)
    semantic    → /rag/answer (ChromaDB + Ollama)
    comparison  → DuckDB + RAG + resumen AI
    report      → DuckDB + RAG + gráfico + síntesis AI
    …
        ↓
JoMelAiResponseFormatter
  → elimina tecnicismos
  → formatea evidencias, acciones, bloques
        ↓
JoMelAiAuditService
  → registra en jomelai_audit
        ↓
Respuesta JSON al frontend
        ↓
jomelai.js renderiza bloques:
  Resumen · Gráfico · Tabla · Respuesta · Evidencias · Acciones
```

---

## Ocultar tecnicismos al usuario final

El `JoMelAiResponseFormatter` aplica estas sustituciones en todas las respuestas:

| Término técnico     | Texto visible para el usuario   |
|---------------------|---------------------------------|
| DuckDB              | análisis de datos               |
| RAG                 | búsqueda inteligente            |
| ChromaDB / Chroma   | índice de conocimiento          |
| embeddings          | preparación de búsqueda         |
| SQL / query         | consulta                        |
| LLM                 | asistente                       |
| vectorial           | inteligente                     |
| collection          | área de análisis                |
| chunks              | fragmentos                      |
| tokens              | unidades de análisis            |

---

## Modo avanzado para ADMIN

Los usuarios con rol `admin` pueden activar "Detalle avanzado" en la interfaz. Al activarlo, la solicitud incluye `"include_debug": true` y la respuesta agrega:

```json
{
  "debug": {
    "engine":      "data_analysis",
    "sql":         "SELECT facultad, COUNT(*) AS total ...",
    "collection":  "silabos_competencias",
    "model":       "qwen2.5-coder:3b",
    "duration_ms": 1820,
    "confidence":  0.88,
    "reason":      "La solicitud pide visualizar datos como gráfico."
  }
}
```

Este bloque **nunca se expone** a usuarios no administradores.

---

## Ejemplos de preguntas y flujos internos

### Gráfico por facultad
```
Pregunta:  "Haz un gráfico de sílabos por facultad"
Intención: chart
Motor:     /charts/natural → DuckDB → matplotlib
Respuesta: imagen PNG + CSV descargable
```

### Competencias de ética
```
Pregunta:  "¿Qué competencias éticas aparecen en Ingeniería?"
Intención: semantic_search
Motor:     /rag/answer → silabos_competencias
Respuesta: texto + evidencias de sílabos con score de relevancia
```

### Comparación de cursos
```
Pregunta:  "Compara Programación I con Algoritmos"
Intención: comparison
Motor:     DuckDB (datos) + RAG (contenido) + Ollama (síntesis)
Respuesta: tabla de datos + resumen comparativo + evidencias
```

### Propuesta de sílabo
```
Pregunta:  "Genera una propuesta de sílabo para Inteligencia Artificial"
Intención: syllabus_generation
Motor:     RAG (contexto) + Ollama (generación)
Respuesta: sílabo estructurado con competencias, contenidos, bibliografía
```

### Calidad de datos
```
Pregunta:  "¿Qué cursos tienen bibliografía incompleta?"
Intención: dataset_quality / semantic_search
Motor:     /csv/profile → diagnóstico de columnas y vacíos
Respuesta: diagnóstico de completitud del dataset
```

---

## Seguridad

### Consultas estructuradas (SQL generado por AI)
- Solo se permiten sentencias que comiencen con `SELECT` o `WITH`.
- Palabras bloqueadas: `DROP`, `DELETE`, `UPDATE`, `INSERT`, `CREATE`, `ALTER`, `TRUNCATE`, `COPY`, `ATTACH`, `INSTALL`, `LOAD`, `read_csv`, `read_parquet`, `shell`, `EXPORT`, `PRAGMA`.
- Se agrega `LIMIT 200` automáticamente si el modelo no lo incluye.
- Timeout de 900 segundos máximo por solicitud.

### Respuestas generativas
- Si no hay evidencia suficiente, el sistema responde:  
  _"No encontré evidencia suficiente en los datos disponibles."_
- El asistente no inventa datos que no existan en el dataset.

### Auditoría
- Cada consulta queda registrada en `jomelai_audit`.
- Solo los administradores pueden acceder al registro desde `GET /api/jomelai/audit`.

---

## Rutas del módulo

| Método | Ruta                    | Acceso    | Descripción                        |
|--------|-------------------------|-----------|------------------------------------|
| POST   | `/api/ask`              | Auth      | Endpoint principal del motor       |
| GET    | `/api/jomelai/audit`    | Admin     | Registro de consultas              |
| GET    | `/api/jomelai/stats`    | Admin     | Estadísticas de uso por intención  |

---

## Archivos del módulo

### Backend
```
backend/src/JoMelAiController.php        Controlador principal
backend/src/JoMelAiIntentClassifier.php  Clasificador de intención
backend/src/JoMelAiOrchestrator.php      Orquestador de motores
backend/src/JoMelAiAuditService.php      Registro de auditoría
backend/src/JoMelAiResponseFormatter.php Formateador de respuestas
```

### Frontend
```
frontend/user.html     Portal de usuario rediseñado
frontend/jomelai.js    Lógica de interfaz JoMelAi
frontend/jomelai.css   Estilos del módulo JoMelAi
```

### Base de datos (SQLite)
```
jomelai_audit   Auditoría de consultas
```

---

## Criterios de aceptación

- El usuario final puede preguntar sin elegir RAG, DuckDB ni ningún motor técnico.
- `POST /api/ask` responde con estructura limpia y sin tecnicismos.
- Las preguntas de gráficos generan una imagen descargable.
- Las preguntas estadísticas producen datos tabulares.
- Las preguntas semánticas devuelven evidencias de sílabos con puntaje.
- Las preguntas de comparación usan flujo híbrido con síntesis AI.
- Las propuestas de sílabo se generan con contexto curricular real.
- El ADMIN puede ver detalle avanzado (motor, SQL, modelo, duración).
- Cada consulta queda auditada con usuario, intención y tiempo de respuesta.
- La interfaz es responsiva, sin emojis, sin jerga técnica.
- Los motores existentes (DuckDB, RAG, wizard, gráficos) no se modifican.

---

*Motor JoMelAi — Universidad Peruana Unión · DTI*
