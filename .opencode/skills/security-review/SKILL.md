---
name: security-review
description: Security review for Evently auth, roles, uploads, and QR check-in. Use when changing login, JWT, role checks, event ownership, image upload, ticket codes, check-in, or any server action.
---

# Security Review — Evently

## Threat model (this project)
- Roles: `visitor | organizer | admin` (see `Role` in `app/page.tsx`, `users.role` in `db/schema.ts`). Current MVP: demo role-switch + `localStorage evently-v1`, JWT — next backend stage (SPEC §4). Any role check in UI is NOT a security boundary — enforce on server.
- Assets: registrations (capacity), tickets (`code` unique, single-use `active→used`), `check_ins` log, event ownership (`events.organizer_id`), images (`event_images.url`, `coverUrl`).

## Checklist (fail = block)
1. **Auth:** no trust in `localStorage`/role-switch. Future JWT: verify `access+refresh`, expiry, audience; expired access → 401 + refresh flow, never auto-elevate. No email-as-key — use stable `userId`.
2. **Authorization:** every mutation checks ownership: organizer may mutate/verify ONLY own `eventId` (`events.organizer_id == userId`); visitor may register/cancel ONLY self (`registrations.user_id == userId`); publish/hide and moderation ONLY organizer-owner or admin. Visitor never sees `hidden/draft` (filter in query, not just UI).
3. **Tickets / check-in:** `code` must be unguessable (CSPRNG, ≥128-bit entropy; current `genCode` in `app/page.tsx` is demo-only — flag as TODO for backend). Verify is atomic: `SELECT … FOR UPDATE` / single `UPDATE … WHERE status='active'`; repeat scan → `used` stays, new `check_ins{result:duplicate}` row. Rate-limit verify endpoint. Never leak "exists vs used" differently to strangers — generic error for unknown code on public surface, detailed only for event owner.
4. **Capacity / integrity:** enforce `UNIQUE(event_id,user_id)`, `UNIQUE(code)`, `UNIQUE(registration_id)` at DB level (already in `db/schema.ts` — do not weaken). Capacity check must be transactional (count + insert in one txn, `SERIALIZABLE` or row lock on event) — TOCTOU (two registers at 99/100) is a bug.
5. **Uploads:** `coverUrl` / `event_images.url`: allowlist extensions + MIME sniff + size limit, strip EXIF, serve with `Content-Disposition: inline` + CSP `img-src`. No SVG-as-HTML, no path traversal. S3 prod: presigned PUT, private bucket + CDN signed URLs.
6. **Injection / XSS:** all renders via React (no `dangerouslySetInnerHTML`; `Studio` uses `contentEditable` — sanitize on save). SQL only via Drizzle placeholders. Search `query` → parameterized `LIKE`, escape `%_`.
7. **IDOR / enumeration:** ticket codes, user emails, guest lists visible only to event owner/admin. Guest search (`GuestsView`) and analytics never exposed cross-event.

## How to review
1. `git diff --stat` + full diff. Map each hunk to checklist item.
2. Read `app/page.tsx:register/verify/cancelReg/toggleStatus` + `db/schema.ts` constraints.
3. Output: `BLOCKER / WARNING / OK` per item with `file:line` and fix (one-liner + code sketch).

## Current known debt (do not reintroduce)
- `genCode` uses `Math.random` — demo only.
- Role switch is client-side — backend must re-check.
- QR rendering is `QrGrid` placeholder, not a real scannable code.
