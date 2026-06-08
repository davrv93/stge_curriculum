# Fix de storage PHP / SQLite / sesiones

Este patch corrige el error:

- `session_start(): open(.../storage/sessions/sess_...) failed: No such file or directory`
- `PDOException: SQLSTATE[HY000] [14] unable to open database file`

## Causa

El volumen bind-mounted `./data/backend/storage:/var/www/app/storage` oculta las carpetas creadas durante el build de la imagen. Si `./data/backend/storage/db` o `./data/backend/storage/sessions` no existen en el host, PHP no puede iniciar sesión ni abrir SQLite.

## Cambios

- Agrega `backend/docker-entrypoint.sh`.
- Crea automáticamente:
  - `/var/www/app/storage/db`
  - `/var/www/app/storage/sessions`
  - `/var/www/app/storage/uploads`
  - `/var/www/app/storage/reports`
  - `/var/www/app/storage/cache`
  - `/var/www/app/storage/jobs`
  - `/var/www/app/storage/rag`
  - `/var/www/app/storage/tmp`
- Crea `app.sqlite` solo si no existe.
- Ajusta permisos sin borrar datos.
- `Support::bootstrap()` ahora valida carpetas antes de `session_start()`.
- `Database::pdo()` ahora valida/corrige la ruta SQLite antes de abrir PDO.
- `docker-compose.yml` ahora incluye `build.context` para backend y data-engine, así `docker compose up -d --build` sí reconstruye los cambios.

## Despliegue seguro

```bash
docker compose up -d --build
```

No usar:

```bash
docker compose down -v
```

## Comando de emergencia si el host quedó con permisos raros

```bash
mkdir -p data/backend/storage/{db,sessions,uploads,reports,cache,jobs,rag,tmp}
touch data/backend/storage/db/app.sqlite
sudo chown -R 33:33 data/backend/storage data/syllabi
sudo chmod -R ug+rwX data/backend/storage data/syllabi
docker compose restart backend
```
