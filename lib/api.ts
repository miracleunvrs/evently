// Клиент Evently API. Токены — в localStorage (решение по грилю).
// При недоступном API фронт работает на локальных данных (fallback).

// Vinext replaces NEXT_PUBLIC_* at build time. A typeof process guard must not
// wrap it: browsers have no process global, so that guard forced the hosted app
// to use localhost instead of the production API.
export const API_URL = process.env.NEXT_PUBLIC_API_URL ||
  (process.env.NODE_ENV === "production"
    ? "https://evently-api-production-1056.up.railway.app"
    : "http://127.0.0.1:8000");

const TOKENS_KEY = "evently-tokens";

export type Tokens = { access_token: string; refresh_token: string };
export type ApiUser = { id: number; name: string; email: string; role: string; wallet_address?: string | null; wallet_verified_at?: string | null };
export type ServerEvent = {
  id: number;
  organizer_id: number;
  title: string;
  description: string;
  city: string;
  place: string;
  starts_at: string;
  category: string | null;
  capacity: number;
  occupied: number;
  price: number;
  status: string;
  cover_url: string;
  visits?: number;
};
export type ServerTicket = {
  id: number;
  code: string;
  status: string;
  event_id: number;
  event_title: string;
  event: ServerEvent;
  registration_id: number;
  wallet_address: string | null;
  solana_signature: string | null;
  token_address: string | null;
  blockchain_status: "pending" | "confirmed" | "failed" | "used";
  explorer_url: string | null;
  checked_in_at: string | null;
};
export type ServerWaitlist = {
  registration_id: number;
  event_id: number;
  event_title: string;
  status: "waitlisted";
  position: number;
};

export class ApiError extends Error {
  status: number;
  code?: string;
  constructor(status: number, message: string, code?: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function loadTokens(): Tokens | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(TOKENS_KEY);
    return raw ? (JSON.parse(raw) as Tokens) : null;
  } catch {
    return null;
  }
}

export function saveTokens(t: Tokens) {
  window.localStorage.setItem(TOKENS_KEY, JSON.stringify(t));
}

export function clearTokens() {
  window.localStorage.removeItem(TOKENS_KEY);
}

async function refreshAccess(): Promise<string | null> {
  const t = loadTokens();
  if (!t) return null;
  const r = await fetch(`${API_URL}/auth/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: t.refresh_token }),
  });
  if (!r.ok) {
    if (r.status === 401 || r.status === 403) clearTokens();
    return null;
  }
  const next = (await r.json()) as Tokens;
  saveTokens(next);
  return next.access_token;
}

export async function apiFetch(path: string, init: RequestInit = {}, retry = true): Promise<Response> {
  const t = loadTokens();
  const r = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", ...(t ? { Authorization: `Bearer ${t.access_token}` } : {}), ...init.headers },
  });
  if (r.status === 401 && t && retry && !path.startsWith("/auth/login") && !path.startsWith("/auth/register")) {
    const access = await refreshAccess();
    if (access) return apiFetch(path, init, false);
  }
  return r;
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const r = await apiFetch(path, init);
  if (!r.ok) {
    let message = `HTTP ${r.status}`;
    let code: string | undefined;
    try {
      const body = (await r.json()) as { detail?: unknown; code?: unknown };
      message = typeof body.detail === "string" ? body.detail : message;
      code = typeof body.code === "string" ? body.code : undefined;
    } catch { /* ignore */ }
    throw new ApiError(r.status, typeof message === "string" ? message : `HTTP ${r.status}`, code);
  }
  if (r.status === 204) return undefined as T;
  return (await r.json()) as T;
}

export async function health(): Promise<boolean> {
  try {
    const r = await fetch(`${API_URL}/health`, { signal: AbortSignal.timeout(2500) });
    return r.ok;
  } catch {
    return false;
  }
}

export const Auth = {
  async register(name: string, email: string, password: string, password_confirmation: string) {
    const t = await api<Tokens & { user: ApiUser }>("/auth/register", {
      method: "POST",
      body: JSON.stringify({ name, email, password, password_confirmation }),
    });
    saveTokens(t);
    return t;
  },
  async login(email: string, password: string) {
    const t = await api<Tokens & { user: ApiUser }>("/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
    saveTokens(t);
    return t;
  },
  me() {
    return api<ApiUser>("/auth/me");
  },
};

export const Wallet = {
  challenge(wallet_address: string) {
    return api<{ message: string; expires_at: string }>("/wallet/challenge", {
      method: "POST",
      body: JSON.stringify({ wallet_address }),
    });
  },
  verify(wallet_address: string, message: string, signature: string) {
    return api<{ wallet_address: string; verified: boolean }>("/wallet/verify", {
      method: "POST",
      body: JSON.stringify({ wallet_address, message, signature }),
    });
  },
};

export const Events = {
  managed() {
    return api<ServerEvent[]>("/me/events");
  },
  guests(id: number) {
    return api<{ name: string; email: string; status: string; event_title: string; code: string | null; used: boolean; blockchain_status: string | null }[]>(`/events/${id}/guests`);
  },
  list(params: { q?: string; category?: string; city?: string } = {}) {
    const qs = new URLSearchParams();
    if (params.q) qs.set("q", params.q);
    if (params.category) qs.set("category", params.category);
    if (params.city) qs.set("city", params.city);
    const s = qs.toString();
    return api<ServerEvent[]>(`/events${s ? `?${s}` : ""}`);
  },
  create(body: Record<string, unknown>) {
    return api<ServerEvent>("/events", { method: "POST", body: JSON.stringify(body) });
  },
  patch(id: number, body: Record<string, unknown>) {
    return api<ServerEvent>(`/events/${id}`, { method: "PATCH", body: JSON.stringify(body) });
  },
  register(id: number) {
    return api<ServerTicket>(`/events/${id}/register`, { method: "POST" });
  },
  confirmBlockchain(ticketId: number, solana_signature: string, token_address: string) {
    return api<ServerTicket>(`/tickets/${ticketId}/blockchain`, {
      method: "POST",
      body: JSON.stringify({ solana_signature, token_address }),
    });
  },
  joinWaitlist(id: number) {
    return api<ServerWaitlist>(`/events/${id}/waitlist`, { method: "POST" });
  },
  cancelRegistration(regId: number) {
    return api<void>(`/registrations/${regId}`, { method: "DELETE" });
  },
  prepareCheckIn(code: string) {
    return api<{ ticket_id: number; event_id: number; memo: string }>("/check-in/prepare", {
      method: "POST",
      body: JSON.stringify({ code }),
    });
  },
  checkIn(code: string, check_in_signature: string) {
    return api<{ result: string; event_id: number; event_title: string; check_in_signature: string; explorer_url: string }>("/check-in", {
      method: "POST",
      body: JSON.stringify({ code, check_in_signature }),
    });
  },
  myTickets() {
    return api<ServerTicket[]>("/me/tickets");
  },
  myWaitlist() {
    return api<ServerWaitlist[]>("/me/waitlist");
  },
  myFavorites() {
    return api<number[]>("/me/favorites");
  },
  addFavorite(event_id: number) {
    return api<{ ok: boolean }>("/me/favorites", { method: "POST", body: JSON.stringify({ event_id }) });
  },
  removeFavorite(event_id: number) {
    return api<void>(`/me/favorites/${event_id}`, { method: "DELETE" });
  },
  overview() {
    return api<{ events: number; users: number; registrations: number; visits: number }>("/admin/overview");
  },
};

export const Categories = {
  list() {
    return api<{ id: number; slug: string; title: string }[]>("/categories");
  },
};
