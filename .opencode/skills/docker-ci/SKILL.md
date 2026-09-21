---
name: docker-ci
description: Docker, nginx, and GitHub Actions for Evently FastAPI plus React/Vite plus PostgreSQL. Use when adding Dockerfile, compose, healthchecks, volumes, env, production build, or CI pipeline.
---

# Docker / CI — Evently

## Reality check
Current repo is Vinext/Next.js PWA (`npm run dev/build/start`, Wrangler local) with no Dockerfile or compose yet. SPEC §5 target: `FastAPI + React/Vite + PostgreSQL + nginx + GitHub Actions`. This skill covers both: keep current preview working, add target infra incrementally.

## Target topology
```
browser → nginx (:80/443, static Vite + /api proxy) → api (FastAPI/uvicorn :8000) → db (Postgres :5432)
```
- `api`: `Dockerfile` python-slim, `CMD uvicorn main:app`, `HEALTHCHECK CMD python -c "urllib.request.urlopen('http://localhost:8000/health')"`.
- `web`: multi-stage `npm ci → npm run build → nginx:alpine` serving `dist/`, proxy `/api/` to `api:8000`.
- `db`: `postgres:16-alpine`, named volume `pgdata`, `HEALTHCHECK pg_isready`.
- `nginx`: single entrypoint, gzip, cache immutable assets, `client_max_body_size 10m` for covers.

## Rules
1. `compose.yaml`: `services: api/web/db(/nginx)`, `depends_on: condition: service_healthy`, `restart: unless-stopped`, env via `.env` (never commit secrets; provide `.env.example`: `DATABASE_URL, JWT_SECRET, S3_*`). Ports: expose only nginx publicly.
2. Local dev stays `npm run dev` / `npm run start` — Docker is for prod-parity (`docker compose up --build`) and CI, not HMR replacement.
3. CI (`.github/workflows/ci.yml`): jobs `lint (npm run lint) → typecheck/build (npm run build) → tests (vitest / pytest when backend lands) → docker build`. Cache npm + pip + docker layers. `HEALTHCHECK` must pass before marking green. Secrets via GitHub Secrets, not repo files.
4. QR/images: local dev `public/` or volume `./uploads`; prod S3-compatible (R2 per `.openai/hosting.json`) via presigned URLs — no binaries in git.
5. After any infra change verify: `docker compose config`, `docker compose up --build -d`, `curl -f localhost/health && localhost/api/health`, `docker compose logs --tail=50`, then `npm run build` still green standalone.

## Minimal CI sketch
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npm run lint
      - run: npm run build
```
Extend with `setup-python + pytest` and `docker/build-push-action` when backend/Dockerfiles land.
