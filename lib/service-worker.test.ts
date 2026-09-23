import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { expect, it, vi } from "vitest";

it("does not intercept authenticated API requests or cross-origin data", () => {
  const handlers: Record<string, (event: unknown) => void> = {};
  runInNewContext(readFileSync(new URL("../public/sw.js", import.meta.url), "utf8"), {
    self: { location: { origin: "http://127.0.0.1:8787" }, addEventListener: (type: string, fn: (event: unknown) => void) => { handlers[type] = fn; } },
    URL,
  });
  for (const url of ["http://127.0.0.1:8000/me/tickets", "http://127.0.0.1:8787/auth/me", "https://example.com/avatar.png"]) {
    const respondWith = vi.fn();
    handlers.fetch({ request: { method: "GET", mode: "cors", url }, respondWith });
    expect(respondWith).not.toHaveBeenCalled();
  }
});
