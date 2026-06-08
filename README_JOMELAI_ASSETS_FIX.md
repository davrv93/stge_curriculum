# JoMelAi layered frontend assets fix

Corrige el error:

```text
Uncaught SyntaxError: Unexpected token '<' (at app.js:1:1)
```

Causa: Nginx estaba devolviendo `index.html` para `app.js`, `jomelai.js`, `tech-routes.js` y/o CSS porque el contenedor solo montaba `index.html`, no los assets separados.

Cambios:

- `frontend/index.html`
- `frontend/styles.css`
- `frontend/jomelai.css`
- `frontend/jomelai.js`
- `frontend/app.js`
- `frontend/tech-routes.js`
- `frontend/nginx.conf` con 404 real para assets faltantes
- `frontend/Dockerfile` copiando assets separados
- `docker-compose.yml` usando `build: ./frontend` para que los assets entren al contenedor

Aplicación:

```bash
unzip -o jomelai_layered_assets_nginx_fix_patch.zip -d .
docker compose build --no-cache frontend
docker compose up -d frontend
```

Verificación:

```bash
docker exec jomelai_frontend sh -lc 'head -1 /usr/share/nginx/html/app.js && head -1 /usr/share/nginx/html/jomelai.js && head -1 /usr/share/nginx/html/tech-routes.js'
curl -s http://localhost:${FRONTEND_PORT:-3000}/app.js | head -1
```

La salida NO debe iniciar con `<`.

No toca volúmenes persistentes: `data/ollama`, `data/duckdb`, `data/syllabi`, `data/backend/storage`.
