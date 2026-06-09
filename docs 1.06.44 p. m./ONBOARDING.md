# Onboarding funcional

## Flujo recomendado

1. Inicia la app con `./scripts/start_ui.sh`.
2. Ingresa como admin.
3. Abre **Configurar desde UI**.
4. Revisa el estado operativo.
5. Usa **Detectar CSVs en volumen** para elegir un archivo disponible.
6. Ejecuta **Perfilar CSV y sugerir columnas**. Revisa columnas de filtro y columnas textuales.
7. Instala modelos base.
8. Convierte a DuckDB.
9. Crea RAG por colecciones de muestra con 2,000 filas.
10. Prueba preguntas y gráficos.
11. Si todo está bien, crea RAG por colecciones completo con límite 0.

## Qué usar según necesidad

- DuckDB: estadísticas, filtros, conteos, tablas, gráficos.
- RAG simple: consultas por significado curricular en una sola colección.
- RAG por colecciones: recomendado para 700 MB porque separa competencias, sumillas, contenidos y bibliografía.
- Portal usuario: preguntas finales en interfaz simplificada.
- Nuevo sílabo: borrador curricular con enfoque académico e identidad adventista sobria.

## CSV de 700 MB

No se recomienda leerlo completo con pandas ni enviarlo al modelo. DuckDB y Chroma procesan por disco/chunks. Para servidores EC2, suele ser más estable copiar el archivo directamente al volumen `data/syllabi/silabos.csv` y luego usar la UI para convertirlo.


## Colecciones RAG recomendadas

- `silabos_general`: preguntas amplias.
- `silabos_competencias`: competencias, resultados de aprendizaje, perfil, capacidades.
- `silabos_sumillas`: sumillas, descripciones y presentación del curso.
- `silabos_contenidos`: unidades, temas, semanas y actividades.
- `silabos_bibliografia`: referencias, libros, artículos y recursos.

El portal usuario decide automáticamente qué colección usar cuando el usuario hace preguntas semánticas.

## Perfilado automático

El perfilador no carga el CSV completo. Lee una muestra configurable, detecta delimitador, estima filas y propone columnas para filtros SQL y RAG. Es el paso recomendado antes de crear el índice completo.

## Wizard curricular, malla y plan de estudios

1. Ingresa al panel administrativo.
2. Abre **Wizard curricular**.
3. Crea un proyecto con facultad, programa, modalidad, ciclos y créditos meta.
4. Escribe el perfil de egreso o propósito formativo.
5. Genera el plan de estudios.
6. Revisa la malla visual por ciclos.
7. Guarda la propuesta como una nueva versión.
8. Cuando haya varias versiones, usa comparación para identificar cursos agregados, retirados o modificados.
9. Publica solo la versión validada por las instancias académicas correspondientes.

El wizard usa lenguaje curricular sobrio, alineación por resultados/evidencias/actividades e integración fe-aprendizaje pertinente al contexto adventista.
