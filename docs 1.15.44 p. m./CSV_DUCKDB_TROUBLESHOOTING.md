# Solución de errores CSV -> DuckDB

Si aparece un error como:

```text
Invalid Input Error: Error when sniffing file ... It was not possible to automatically detect the CSV parsing dialect
```

significa que DuckDB no pudo inferir automáticamente separador, comillas, encoding o estructura del CSV. Esto es normal en archivos institucionales grandes exportados desde sistemas académicos.

## Flujo recomendado desde la UI

1. Entrar a **Configurar desde UI**.
2. Seleccionar o registrar `/data/syllabi/silabos.csv`.
3. Ejecutar **Perfilar CSV y sugerir columnas**.
4. Revisar los campos detectados:
   - delimitador
   - encoding
   - cantidad de columnas
   - alertas
5. En **Preparar bases**, dejar que la UI copie automáticamente delimitador y encoding detectados.
6. Ejecutar **Convertir CSV a DuckDB**.

## Parámetros tolerantes aplicados

La conversión actual usa modo tolerante:

- `strict_mode=false`
- `null_padding=true`
- `ignore_errors=true`
- `all_varchar=true`
- `max_line_size=10000000`
- detección de `encoding`
- reintentos con delimitadores comunes: `;`, `,`, `|`, tab
- reintentos con encodings comunes: `utf-8-sig`, `utf-8`, `latin-1`, `windows-1252`

## Casos comunes

### CSV separado por punto y coma

Usar delimitador:

```text
;
```

### CSV con tildes o caracteres raros

Probar encoding:

```text
latin-1
```

o:

```text
windows-1252
```

### CSV con filas iniciales antes del encabezado

Usar **Saltar líneas iniciales** en la UI. Por ejemplo:

```text
1
```

### Líneas muy largas

La app ya usa `max_line_size=10000000`. Si aun falla, revisar si el CSV trae campos de texto gigantes con saltos de línea no escapados.

## Comando de respaldo

```bash
./scripts/upeu_silabo_ai.sh duckdb
```

O dentro del contenedor data-engine:

```bash
docker compose exec data-engine python cli.py duckdb /data/syllabi/silabos.csv --delimiter ';' --encoding latin-1
```
