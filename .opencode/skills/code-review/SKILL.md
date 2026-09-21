---
name: code-review
description: Review Evently diffs for bugs, race conditions, security, and architecture. Use after any feature, before merge, or when asked to review branch, PR, or work-in-progress.
---

# Code Review — Evently

## Scope
`git status`, `git diff --stat`, `git diff`, `git log --oneline -10`. Review full diff, not just last commit. Base: SPEC.md §4/§7 + `app/page.tsx` invariants + `db/schema.ts` constraints.

## Axes (report side by side)
1. **Correctness:** `register` (idempotent, capacity gate), `verify` (unknown/used/ok + `check_ins` log), `cancelReg` (only `!used`), `occupied` math, `visible` filter (visitor hides non-published), `toggleStatus`.
2. **Races:** capacity TOCTOU, double-click register, parallel verify same code — must be atomic/idempotent. Flag any check-then-act without txn/lock.
3. **Security:** see `security-review` skill — ownership (`organizer_id`), role escalation, code guessing (`genCode`), XSS (`contentEditable`), search injection.
4. **Architecture / AI-bloat:** reject `*ServiceFactoryManager`, duplicated Event types, new state shapes paralleling `Persisted`, CSS duplicates of existing classes. One function per action, reuse `EventItem/Reg/CheckLog` types.
5. **UI consistency:** tokens `#f4f2ec/#16151c/#5638ef/#d8ff45/#ff6846`, existing classes, RU copy, 360px mobile, `aria-label`s, lucide icons.

## Output
```md
## Standards (repo conventions)
- [BLOCKER/WARNING/OK] file:line — what + fix
## Spec (SPEC.md §4/§7)
- [PASS/FAIL] scenario 1-6 + edge cases
## Verdict: APPROVE / FIX-THEN-MERGE / BLOCKED
```
Max 5 blockers sorted by risk (data loss / double-spend ticket / auth bypass first). Each with minimal fix sketch. No praise fluff.

## Must verify
- `npm run lint` clean, `npm run build` passes.
- No secrets in diff, no `localStorage` key rename without migration, no weakened Drizzle unique/index.
