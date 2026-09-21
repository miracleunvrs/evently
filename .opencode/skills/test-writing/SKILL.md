---
name: test-writing
description: Tests for Evently domain invariants. Use when adding registration, capacity, tickets, check-in, roles, favorites, or auth refresh flow. Covers vitest for Next.js MVP and pytest for future FastAPI.
---

# Test Writing — Evently

## Current gap
No test runner in `package.json`. Default: add `vitest` (unit) + keep e2e manual via `npm run dev`. Future FastAPI backend: `pytest + httpx`. Do not mix runners in one file.

## MVP (vitest) — extract pure logic first
Functions under test live in `app/page.tsx`: `occupied`, `register`, `verify`, `cancelReg`, `genCode`, visibility filter. Extract to `lib/evently.ts` if file grows, keep signatures identical.

Mandatory cases (each is a test, names in RU or EN but stable):
1. `capacity 100/100` → `register` no-op, UI soldout. Setup: `attendees=100, capacity=100` → expect `regs` unchanged.
2. `повторная регистрация` → second `register(sameId)` does not create second code, redirects to tickets.
3. `повторный QR scan` → `verify(code)` twice: 1st `Проход разрешён` + `used=true` + log `ok`; 2nd `Уже использован` + log `duplicate`, `used` stays true.
4. `неизвестный код` → `verify('EVT-9-XXXX')` → `Билет не найден`, no state change.
5. `отмена использованного` → `cancelReg(usedId)` no-op; отмена активного → key deleted, место освобождено (`occupied` -1).
6. `чужое/скрытое событие` → visitor `visible` excludes `status!=published`; `toggleStatus` flips `published↔hidden`.
7. `избранное` → `toggleFav` add/remove idempotent.

Example sketch:
```ts
import { describe, expect, it } from "vitest";
import { occupied } from "./lib/evently";
describe("capacity", () => {
  it("soldout at 100/100 blocks register", () => {
    expect(occupied({ attendees: 100 } as any, {})).toBe(100);
  });
});
```

## Future FastAPI (pytest) — when backend appears
- Endpoints: `POST /events`, `POST /events/{id}/registrations`, `POST /tickets/verify`, `POST /auth/refresh`.
- Cases mirror above +: `401` на истёкший access, `refresh` ротация, `403` organizer чужого event, `409` duplicate registration, `409` capacity full, `409` reuse ticket. Use transactional fixtures, assert DB constraints (`UNIQUE(event,user)`, `UNIQUE(code)`) trigger, not just HTTP codes.
- Concurrency: two parallel `POST registrations` at 99/100 → ровно 1 `201`, 1 `409`.

## Rules
- One behavior per test, no snapshots of whole `page.tsx`.
- Every bugfix ships with failing-first test named after invariant (`duplicate-scan-blocked`).
- Run: `npx vitest run` (after `npm i -D vitest`), plus `npm run lint` + `npm run build`.
