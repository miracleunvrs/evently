// Pure domain logic Evently (SPEC.md §10). Зеркалит app/page.tsx без React,
// чтобы покрыть инварианты vitest. UI должен использовать эти функции.

export type Role = "visitor" | "organizer" | "admin";
export type EventStatus = "published" | "hidden" | "draft";
export type EventLike = {
  id: number;
  attendees: number;
  capacity: number;
  status: EventStatus;
  title?: string;
  company?: string;
  city?: string;
  category?: string;
};
export type Reg = { code: string; used: boolean };
export type Regs = Record<string, Reg>;
export type CheckLog = { label: string; result: "ok" | "duplicate"; at: string };

export function occupied(event: EventLike, regs: Regs): number {
  return event.attendees + (regs[String(event.id)] ? 1 : 0);
}

export function isSoldout(event: EventLike, regs: Regs): boolean {
  return occupied(event, regs) >= event.capacity;
}

// Чистая регистрация: возвращает новые regs или те же (no-op при дубле/soldout).
export function applyRegister(event: EventLike, regs: Regs, code: string): Regs {
  const key = String(event.id);
  if (regs[key] || occupied(event, regs) >= event.capacity) return regs;
  return { ...regs, [key]: { code, used: false } };
}

export type CheckInResult = {
  regs: Regs;
  log: CheckLog[];
  message: string;
  kind: "empty" | "not-found" | "duplicate" | "ok";
};

// Зеркало checkIn из app/page.tsx: upper-case кодов, EVT-* неизвестный → not-found,
// повтор label с ok → duplicate, иначе ok (+used=true для билетов).
export function applyCheckIn(regs: Regs, log: CheckLog[], raw: string, now = new Date().toISOString()): CheckInResult {
  const input = raw.trim();
  if (!input) return { regs, log, message: "Введите код билета или выберите гостя", kind: "empty" };
  const entry = Object.entries(regs).find(([, r]) => r.code === input.toUpperCase());
  if (!entry && /^EVT-/i.test(input)) {
    return { regs, log, message: "Билет не найден", kind: "not-found" };
  }
  const label = entry ? entry[1].code : input;
  if (log.some((l) => l.label === label && l.result === "ok")) {
    return {
      regs,
      log: [...log, { label, result: "duplicate", at: now }],
      message: "Уже отмечен — повторный проход запрещён",
      kind: "duplicate",
    };
  }
  const nextRegs = { ...regs };
  if (entry) nextRegs[entry[0]] = { ...entry[1], used: true };
  return {
    regs: nextRegs,
    log: [...log, { label, result: "ok", at: now }],
    message: "Проход разрешён",
    kind: "ok",
  };
}

// Отмена только активного билета (used → no-op).
export function applyCancel(regs: Regs, id: number): Regs {
  const key = String(id);
  if (!regs[key] || regs[key].used) return regs;
  const next = { ...regs };
  delete next[key];
  return next;
}

export function toggleFavorite(favorites: number[], id: number): number[] {
  return favorites.includes(id) ? favorites.filter((f) => f !== id) : [...favorites, id];
}

export function filterVisible(events: EventLike[], role: Role, query: string): EventLike[] {
  const q = query.trim().toLowerCase();
  return events.filter((e) => {
    if (role === "visitor" && e.status !== "published") return false;
    if (!q) return true;
    return `${e.title ?? ""} ${e.company ?? ""} ${e.city ?? ""} ${e.category ?? ""}`
      .toLowerCase()
      .includes(q);
  });
}

export function toggleEventStatus(current: EventStatus): EventStatus {
  return current === "published" ? "hidden" : "published";
}
