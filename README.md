# ⚡ JoMelAi Curriculista

**Plataforma de diseño curricular potenciada por inteligencia artificial**  
Motor JoMelAi · 2026

---

## 🚀 Inicio rápido

```bash
# 1. Descomprime y entra al proyecto
cd JoMelAi-Curriculista

# 2. Configura variables de entorno
cp .env.example .env
# Edita .env y pon tu imagen real de data-engine en DATA_ENGINE_IMAGE

# 3. Levanta todo
docker compose up -d --build

# 4. (Primera vez) Descarga el modelo LLM
docker exec jomelai_ollama ollama pull qwen2.5-coder:3b

# 5. Abre la plataforma
# http://localhost:3000
```

---

## 💾 Persistencia de datos — MUY IMPORTANTE

Todos los datos viven en la carpeta **`./data/`** de este proyecto.  
Son **bind mounts**, no volúmenes Docker anónimos.  
**`docker compose down -v` NO borra tus datos.**

```
data/
├── duckdb/           ← 🔴 Base de datos DuckDB (NO BORRAR)
│   └── jomelai.duckdb
├── syllabi/          ← CSVs de sílabos importados
├── backend/
│   └── storage/
│       ├── db/       ← SQLite (usuarios, proyectos, audit log)
│       ├── sessions/ ← Sesiones PHP activas
│       ├── uploads/  ← Archivos subidos
│       └── reports/  ← Reportes generados
└── ollama/           ← Modelos LLM (evita re-descargar)
```

### Respaldo rápido

```bash
# Respalda TODO tus datos en un solo comando:
tar czf backup-jomelai-$(date +%Y%m%d).tar.gz data/
```

### Migración a otro servidor

```bash
# En el servidor origen:
tar czf backup-jomelai.tar.gz data/

# En el servidor destino:
tar xzf backup-jomelai.tar.gz
docker compose up -d --build
# ← Ya tiene todos tus datos
```

---

## 🏗 Arquitectura

```
JoMelAi-Curriculista/
├── frontend/            ← SPA curriculista (Nginx)
│   ├── index.html       ← Login + 4 módulos + panel JoMelAi
│   ├── nginx.conf       ← Proxy /api/* → backend
│   └── Dockerfile
├── backend/             ← PHP 8.2
│   ├── src/
│   │   ├── JoMelAiController.php     ← POST /api/ask
│   │   ├── JoMelAiOrchestrator.php   ← Motor de intenciones
│   │   ├── CurriculumController.php  ← Malla y plan
│   │   ├── AssistantController.php   ← Sílabos
│   │   └── ...
│   └── Dockerfile
├── data/                ← ⚡ DATOS PERSISTENTES (bind mounts)
│   ├── duckdb/          ← jomelai.duckdb ← NO TOCAR
│   ├── syllabi/         ← CSVs
│   ├── backend/storage/ ← SQLite, sesiones, uploads
│   └── ollama/          ← Modelos LLM
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## 🤖 Motor JoMelAi — Endpoints clave

| Endpoint | Descripción |
|---|---|
| `POST /api/ask` | Consulta unificada (clasifica intención automáticamente) |
| `POST /api/curriculum/generate-plan` | Genera malla / plan de estudios |
| `POST /api/assistant/generate-syllabus` | Genera sílabo académico |
| `GET /api/syllabi/search` | Busca en repositorio de sílabos |
| `GET /api/curriculum/projects` | Lista proyectos curriculares |
| `GET /api/jomelai/stats` | Estadísticas del motor |
| `GET /api/duckdb/tables` | Tablas en DuckDB |

---

## 🔐 Credenciales demo

```
Email:    admin@upeu.edu.pe
Password: Admin12345!
```
> ⚠️ Cambiar antes de producción

---

*JoMelAi Curriculista · Motor curricular IA · 2026*
# stge_curriculum
