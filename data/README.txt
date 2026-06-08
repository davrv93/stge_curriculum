# Este directorio contiene los datos persistentes de JoMelAi.
# NUNCA borres esta carpeta — aquí vive tu base DuckDB, sílabos y SQLite.
#
# data/
# ├── duckdb/        ← Base de datos DuckDB (tablas de sílabos, análisis)
# ├── syllabi/       ← CSVs de sílabos importados
# ├── backend/
# │   └── storage/
# │       ├── db/       ← SQLite (usuarios, proyectos curriculares, audit)
# │       ├── sessions/ ← Sesiones PHP
# │       ├── uploads/  ← Archivos subidos
# │       └── reports/  ← Reportes generados
# └── ollama/        ← Modelos LLM descargados

