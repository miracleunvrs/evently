# AGENTS.md — Evently

Web3 event platform: React 19 + Vinext frontend, Ruby on Rails API, PostgreSQL and non-transferable Token-2022 tickets on Solana Devnet.

## Commands
- `npm run dev` — Vinext HMR preview (:5173). `npm run build` — prod build. `npm start` — built Worker via Wrangler local.
- `npm run lint` — eslint. `npm run db:generate` — drizzle migration from `db/schema.ts`.
- `cd backend && bundle exec rails test` — Rails/Solana tests. `bundle exec rubocop` — Ruby style.
- D1 local apply: `node --import ./scripts/sites-env.mjs ./node_modules/wrangler/bin/wrangler.js d1 execute DB --local --config dist/server/wrangler.json --persist-to .wrangler/state --file drizzle/XXXX.sql`

## Invariants (do not break)
- 1 пара (event,user) = 1 регистрация (`UNIQUE`), 1 регистрация = 1 билет (`UNIQUE code`), билет single-use `active→used`, повторный скан → `check_ins{duplicate}` + блок.
- Online registration requires a verified Phantom wallet and a confirmed non-transferable Token-2022 mint on Devnet. Never store a user's private key.
- Capacity: `occupied(event,regs) >= capacity` → sold out, регистрация блокируется. Отмена только если `!used`.
- Роли `visitor|organizer|admin`; visitor видит только `published`. Владение через `events.organizer_id`.
- Состояние клиента `Persisted` в `app/page.tsx`, ключ `evently-v1`. QR `code` — одна строка (потом заменится backend-QR).

## Skills (`.opencode/skills/*/SKILL.md`)
- `frontend-design` — каталог, карточки, event page, dashboards, QR/check-in, mobile.
- `planning` — сначала план (данные/логика/роли/edge cases), потом код. Без кода на этапе плана.
- `security-review` — JWT/роли/ownership/загрузки/QR, атомарный verify.
- `test-writing` — vitest for client rules and Rails tests for auth, ticket verification and Solana services.
- `code-review` — Standards + Spec, вердикт APPROVE/FIX-THEN-MERGE/BLOCKED.
- `debugging` — reproduce → evidence → fix; dev vs start, SW, D1, localStorage.
- `database` — Drizzle constraints/indexes/migrations, транзакционный capacity/verify, путь к Postgres.
- `docker-ci` — compose (Rails API/web/Postgres), healthchecks, `.env.example`, GitHub Actions lint→build→test→docker.
