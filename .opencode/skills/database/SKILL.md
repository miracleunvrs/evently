---
name: database
description: Design Evently schema, constraints, indexes, and migrations with Drizzle. Use when changing users, events, registrations, tickets, favorites, check-ins, capacity, or moving toward PostgreSQL.
---

# Database — Evently

## Current truth
`db/schema.ts` (Drizzle SQLite/D1) + `drizzle.config.ts` + `drizzle/*.sql`. Tables per SPEC §6: `users, categories, events, event_images, registrations, tickets, favorites, check_ins`. Target: PostgreSQL (SPEC §5) — write portable Drizzle (no SQLite-only SQL in app code).

## Invariants (never weaken)
- `users.email` unique; `role ∈ visitor|organizer|admin`.
- `events`: `organizer_id` required + indexed; `status ∈ draft|published|hidden`; `capacity` default 100, CHECK `capacity>=1`.
- `event_images.event_id` indexed, `sort` for order.
- `registrations`: `UNIQUE(event_id,user_id)` — 1 user = 1 registration. Indexes on both columns. `status` default `confirmed`.
- `tickets`: `UNIQUE(registration_id)` (1:1) + `UNIQUE(code)` (QR payload). `status ∈ active|used`, default `active`. Code generated server-side (CSPRNG) in real backend.
- `favorites`: `UNIQUE(user_id,event_id)`.
- `check_ins`: append-only log `{ticket_id,event_id,checked_by,result ok|duplicate}`. Repeat scan inserts `duplicate`, never flips `used` back. Indexes on `ticket_id,event_id`.

## Rules
1. Capacity is DB-guaranteed: count+insert in one transaction (PG: `SELECT … FOR UPDATE` on event row or advisory lock; D1/SQLite: single `BEGIN IMMEDIATE` txn). App-level `occupied()` check alone is insufficient.
2. Verify ticket atomically: `UPDATE tickets SET status='used' WHERE code=? AND status='active'` → if `rowcount==0`, read reason (unknown vs used) + insert `check_ins` accordingly.
3. Migrations: edit `db/schema.ts` → `npm run db:generate` → review SQL → apply locally via wrangler `d1 execute` (see README "Local D1 migrations"). One logical change per migration file. Never edit applied `drizzle/*.sql` or `_journal.json` by hand.
4. Indexes for catalog: `(status, starts_at)`, `(category_id)`, `(organizer_id)`. Search by title/city → PG `trigram`/D1 `LIKE` + index note in migration comment.
5. Seeds: keep `seedEvents` in `app/page.tsx` and DB seeds consistent on categories (`Дизайн/Технологии/Нетворкинг/Музыка/Наука`).

## Review checklist
- Unique/index present? Downgrade `uniqueIndex→index` is BLOCKER.
- Nullability/defaults match app (`cover_url default ''`, `price default 0`)?
- Migration reversible or forward-only documented? Data backfill for non-null adds?
