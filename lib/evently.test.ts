import { describe, expect, it } from "vitest";
import {
  applyCancel,
  applyCheckIn,
  applyRegister,
  filterVisible,
  occupied,
  toggleEventStatus,
  toggleFavorite,
  type EventLike,
} from "./evently";

const evt = (over: Partial<EventLike> = {}): EventLike => ({
  id: 1,
  attendees: 0,
  capacity: 100,
  status: "published",
  ...over,
});

describe("capacity", () => {
  it("soldout 100/100 блокирует регистрацию", () => {
    const e = evt({ attendees: 100, capacity: 100 });
    expect(occupied(e, {})).toBe(100);
    expect(applyRegister(e, {}, "EVT-1-AAAA")).toBeTypeOf("object");
    // no-op: возвращается тот же объект
    const regs = {};
    expect(applyRegister(e, regs, "EVT-1-AAAA")).toBe(regs);
  });
});

describe("повторная регистрация", () => {
  it("второй register тот же id не создаёт второй код", () => {
    const e = evt({ attendees: 10 });
    const r1 = applyRegister(e, {}, "EVT-1-AAAA");
    const r2 = applyRegister(e, r1, "EVT-1-BBBB");
    expect(r2).toBe(r1);
    expect(r1["1"].code).toBe("EVT-1-AAAA");
  });
});

describe("повторный QR scan", () => {
  it("1-й ok + used, 2-й duplicate, used остаётся", () => {
    const e = evt();
    const regs = applyRegister(e, {}, "EVT-1-AB12");
    const first = applyCheckIn(regs, [], "evt-1-ab12", "2026-01-01T00:00:00.000Z");
    expect(first.kind).toBe("ok");
    expect(first.regs["1"].used).toBe(true);
    expect(first.log).toEqual([{ label: "EVT-1-AB12", result: "ok", at: "2026-01-01T00:00:00.000Z" }]);
    const second = applyCheckIn(first.regs, first.log, "EVT-1-AB12", "2026-01-01T00:01:00.000Z");
    expect(second.kind).toBe("duplicate");
    expect(second.regs["1"].used).toBe(true);
    expect(second.log.filter((l) => l.result === "duplicate")).toHaveLength(1);
  });
});

describe("неизвестный код", () => {
  it("EVT-9-XXXX → not-found без изменения состояния", () => {
    const regs = {};
    const res = applyCheckIn(regs, [], "EVT-9-XXXX");
    expect(res.kind).toBe("not-found");
    expect(res.message).toBe("Билет не найден");
    expect(res.regs).toBe(regs);
    expect(res.log).toHaveLength(0);
  });
});

describe("отмена регистрации", () => {
  it("used → no-op, active → удаляется и место освобождается", () => {
    const e = evt({ attendees: 50 });
    const active = applyRegister(e, {}, "EVT-1-AAAA");
    expect(occupied(e, active)).toBe(51);
    const cancelled = applyCancel(active, 1);
    expect(cancelled["1"]).toBeUndefined();
    expect(occupied(e, cancelled)).toBe(50);

    const used = { "1": { code: "EVT-1-AAAA", used: true } };
    expect(applyCancel(used, 1)).toBe(used);
  });
});

describe("скрытое/чужое событие", () => {
  it("visitor не видит hidden/draft, toggleStatus flips", () => {
    const events = [evt({ id: 1, status: "published" }), evt({ id: 2, status: "hidden" }), evt({ id: 3, status: "draft" })];
    expect(filterVisible(events, "visitor", "").map((e) => e.id)).toEqual([1]);
    expect(filterVisible(events, "organizer", "").map((e) => e.id)).toEqual([1, 2, 3]);
    expect(toggleEventStatus("published")).toBe("hidden");
    expect(toggleEventStatus("hidden")).toBe("published");
  });
});

describe("избранное", () => {
  it("toggle идемпотентен", () => {
    expect(toggleFavorite([], 1)).toEqual([1]);
    expect(toggleFavorite([1], 1)).toEqual([]);
    expect(toggleFavorite([1, 2], 1)).toEqual([2]);
  });
});
