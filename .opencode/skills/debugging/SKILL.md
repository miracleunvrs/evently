---
name: debugging
description: Diagnose Evently failures in dev, tests, Docker, or Wrangler/Miniflare. Use when integration breaks, build fails, preview is blank, D1 migration fails, or service worker misbehaves.
---

# Debugging — Evently

## Loop (do not skip)
1. **Reproduce (1 command):** `npm run dev` (Vinext :5173) or `npm run build` or `npm start` (Wrangler local). Record exact URL, role, view, code entered. Screenshot/console text verbatim.
2. **Narrow:** UI (`app/page.tsx` view/state) vs data (`localStorage evently-v1`, `db/schema.ts`, `drizzle/`) vs infra (Vite/Vinext/Wrangler/Miniflare/SW `/sw.js`).
3. **Read evidence:** DevTools console + Network, `vinext` terminal output, `.wrangler/logs`, `drizzle/meta/_journal.json`. `localStorage.getItem('evently-v1')` for regs/state bugs. Never guess — quote log line.
4. **Fix minimal:** one hypothesis → one change → re-run reproduce command + `npm run lint`.

## Project traps
- **Two servers:** `vinext dev` (5173, HMR) vs `npm start` (built Worker via Wrangler). Test HMR issues on dev, D1/R2 issues on start. Stale `.vinext` lock → kill process, delete lock, restart. Do not run two installers simultaneously.
- **Blank preview:** check `app/layout.tsx` + `app/globals.css` import, Vinext RSC errors in terminal, `next-env.d.ts` drift.
- **SW stale:** `navigator.serviceWorker.register('/sw.js')` in `app/page.tsx` caches aggressively → hard-reload / unregister in DevTools → Application → Service Workers during debug.
- **D1 local:** migrations via `npm run db:generate` → apply with `wrangler d1 execute DB --local --config dist/server/wrangler.json --persist-to .wrangler/state --file drizzle/XXXX.sql`. Never replay applied migration; check `_journal.json`. Prod migrations separate.
- **State bugs:** `regs: Record<string,Reg>` keyed by `String(event.id)`; `verify` uppercases input; `genCode` demo-random — duplicate codes in tests mean fixture collision, not DB bug.
- **macOS Seatbelt:** `vite.config.ts` enables polling when `CODEX_SANDBOX=seatbelt` — HMR slow is expected, not a bug.

## Output
`Symptom → Evidence (log line) → Root cause (file:line) → Fix → Verified by (command + result)`. If blocked, state what command to run next and what output is needed.
