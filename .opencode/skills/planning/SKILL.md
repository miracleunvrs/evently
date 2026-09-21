---
name: planning
description: Brainstorm and plan Evently features before coding. Use when designing registration, ticket issue, check-in, capacity, roles, or any multi-file change. Use ONLY for planning, not implementation.
---

# Planning — Evently

## Trigger
Any task touching >1 view, >1 DB table, or critical flow: `регистрация → билет → check-in → защита от повтора`, capacity, roles, publishing, favorites, analytics.

## Process (no code until step 5)
1. **Restate goal in 2 sentences.** Link SPEC.md §4/§7 item. Example: "Посетитель регистрируется → получает 1 QR → организатор сканирует → повтор блокируется".
2. **Read current truth:** `SPEC.md`, `app/page.tsx` functions (`register`, `verify`, `cancelReg`, `occupied`), `db/schema.ts` tables + indexes.
3. **Design:**
   - Data: which tables (`registrations`, `tickets`, `check_ins`), constraints (unique `(event_id,user_id)`, unique `code`, `status active/used`).
   - Logic: capacity check `occupied >= capacity`, idempotency (repeat register → go to tickets, no duplicate), cancel rule (only if `!used`), verify rule (unknown code → "не найден", `used` → log `duplicate` + block, else mark `used` + log `ok`).
   - Roles: who can call (visitor self-register, organizer verify own events, admin moderate). Ownership via `events.organizer_id`.
   - Edge cases (mandatory list): 100/100 sold out, double-click register, repeat QR scan, чужое мероприятие, отмена использованного билета, скрытое событие для visitor.
4. **Break into tickets:** each ≤1 view or ≤1 table migration. Format: `1. [view/table] что сделать → acceptance`. Example: `1. [Discover] disable register at soldout → acceptance: кнопка disabled + pill Sold out`.
5. **Acceptance checklist** (copy into PR): happy path 1-6 из SPEC §7 + all edge cases + role matrix.

## Output format
```md
## Goal
## Current (files:lines)
## Design (data/logic/roles)
## Edge cases
## Tickets
## Acceptance
```

## Anti-rules
- No new entities without mapping to SPEC §6 (`users/categories/events/event_images/registrations/tickets/favorites/check_ins`).
- No `EventServiceFactoryManager` — one function per domain action (`register`, `verify`, `cancelReg`).
- If capacity or ticket single-use logic changes, must update both `app/page.tsx` and `db/schema.ts` reasoning in plan.
