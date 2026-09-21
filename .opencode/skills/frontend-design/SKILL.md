---
name: frontend-design
description: Production-grade React/Next.js UI for Evently. Use when building catalog, event cards, event page, organizer dashboard, admin panel, QR-ticket screen, check-in screen, or any mobile UI.
---

# Frontend Design — Evently

## Stack reality
- Current: React 19 + Next.js 16 + Vinext + Tailwind 4 + shadcn + lucide-react. Code lives in `app/page.tsx` (single-client MVP), styles in `app/globals.css`.
- Target from SPEC.md §5: React + Vite. Keep components portable: no Next-only APIs inside UI components.

## Visual system (Do not reinvent)
- Colors: bg `#f4f2ec`, ink `#16151c`, cobalt `#5638ef`, lime `#d8ff45`, coral `#ff6846`.
- Type: large editorial headlines, small caps kickers (`section-kicker`), pill filters.
- Layout: dark `.sidebar` + light `.content`. Cards: large cover + `date-tile` + `tag-row` + capacity bar.
- Mobile priority: QR-ticket (`ticket-card`, `QrGrid`) and check-in (`scanner-card`) must work one-handed at 360px.

## Rules
1. Reuse existing CSS classes and tokens in `app/globals.css` before adding new ones. New styles go to same file, no CSS-in-JS sprawl.
2. Reuse shadcn primitives from `components/` and icons from `lucide-react`. No emoji icons.
3. Client state shape is fixed: `Persisted = { role, favorites, regs, extra, statusOv, log }` in `app/page.tsx`. Persist key `evently-v1`. Do not rename without migration.
4. Views: `discover | tickets | cabinet | events | create | studio | guests | checkin | analytics | admin`. Role gating: visitor sees only `discover/tickets/cabinet`; organizer adds events/create/studio/guests/checkin/analytics; admin adds `admin`. Keep gating in `Sidebar`, hide unpublished events from visitors (`status !== published`).
5. Capacity UI: always render `occupied / capacity` bar via `occupied(event, regs)`. Sold out = `occupied >= capacity` → disable register button, show `Sold out` pill. Registered = show `Билет есть` + code.
6. QR: `QrGrid({code})` is placeholder. Real QR comes from backend later — keep `code` as single string prop so swap is trivial. Never render ticket without `CONFIRMED/USED` badge and "повторный проход запрещён" hint.
7. Forms (`CreateView`): controlled inputs, `capacity` min 1 max 5000, default tone `cobalt`. On submit → `extra` + go to `events`.
8. Accessibility: buttons have `aria-label` (RU), inputs have placeholders/labels, QR wrapper has `aria-label="QR {code}"`. Keyboard: fav toggle handles Enter.
9. No new routes without need — MVP is single `app/page.tsx` view-switcher. New page = new `View` + Sidebar item + role rule.

## When building a screen
1. Read `app/page.tsx` section for that view + relevant CSS in `app/globals.css`.
2. Keep copy in Russian, tone from existing screens.
3. Mobile check: 360px, sidebar becomes drawer (`menuOpen` + `.scrim`), topbar search collapses.
4. Verify: `npm run lint`, `npm run build`. Visual: open `npm run dev` → port 5173, switch roles visitor/organizer/admin.
