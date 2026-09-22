"use client";
/* eslint-disable @next/next/no-img-element -- QR and editor previews use runtime data/blob URLs. */

import {
  ArrowRight,
  BarChart3,
  CalendarDays,
  Check,
  ChevronDown,
  Download,
  ExternalLink,
  Eye,
  FileText,
  Frame,
  Grid2X2,
  Heart,
  ImagePlus,
  MapPin,
  Menu,
  Minus,
  MoreHorizontal,
  Plus,
  QrCode,
  ScanLine,
  Search,
  Send,
  Settings,
  ShieldCheck,
  Sparkles,
  Ticket,
  Type,
  User,
  Users,
  WalletCards,
  X,
} from "lucide-react";
import { type CSSProperties, type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import QRCode from "qrcode";
import {
  ApiError,
  Auth,
  Categories,
  Events,
  clearTokens,
  health,
  loadTokens,
  type ApiUser,
  type ServerEvent,
  type ServerTicket,
} from "../lib/api";
import { EVENT_COVERS, coverForEventId, randomEventCover } from "../lib/event-covers";
import { connectAndVerifyWallet, createCheckInProof, mintNonTransferableTicket, shortWallet } from "../lib/web3";

type Role = "visitor" | "organizer" | "admin";
type View =
  | "discover"
  | "tickets"
  | "cabinet"
  | "events"
  | "create"
  | "studio"
  | "guests"
  | "checkin"
  | "analytics"
  | "admin";

type EventItem = {
  id: number;
  title: string;
  company: string;
  date: string;
  day: string;
  month: string;
  place: string;
  city: string;
  category: string;
  access: string;
  attendees: number;
  capacity: number;
  tone: string;
  image: string;
  status: "published" | "hidden" | "draft";
  past: boolean;
};

type Reg = {
  code: string;
  used: boolean;
  regId?: number;
  ticketId?: number;
  wallet?: string | null;
  blockchainStatus?: "pending" | "confirmed" | "failed" | "used";
  signature?: string | null;
  tokenAddress?: string | null;
  explorerUrl?: string | null;
};
type WaitEntry = { regId?: number; position: number; joinedAt?: string };
type WebMcpTool = { name: string; title: string; description: string; inputSchema: object; annotations?: { readOnlyHint?: boolean; untrustedContentHint?: boolean }; execute: (input: unknown) => unknown | Promise<unknown> };
declare global { interface Document { modelContext?: { registerTool: (tool: WebMcpTool, options?: { signal?: AbortSignal }) => void | Promise<void> } } }
// Единый журнал проходов: label — код билета или имя из ручного списка.
type CheckLog = { label: string; result: "ok" | "duplicate"; at: string };
type Profile = { name: string; email: string };
type GuestRow = { name: string; email: string; status: string };

function guestsToCSV(rows: GuestRow[]) {
  const esc = (v: string) => `"${v.replace(/"/g, '""')}"`;
  return `\uFEFFname,email,status\n${rows.map((g) => [g.name, g.email, g.status].map(esc).join(",")).join("\n")}`;
}

function downloadCSV(filename: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function serverTicketToReg(ticket: ServerTicket): Reg {
  return {
    code: ticket.code,
    used: ticket.status !== "active",
    regId: ticket.registration_id,
    ticketId: ticket.id,
    wallet: ticket.wallet_address,
    blockchainStatus: ticket.blockchain_status,
    signature: ticket.solana_signature,
    tokenAddress: ticket.token_address,
    explorerUrl: ticket.explorer_url,
  };
}

function parseCSV(text: string): GuestRow[] {
  return text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean)
    .filter((l) => !/^"?name"?[,;]/i.test(l))
    .map((line) => {
      const parts = line.split(/[,;]/).map((p) => p.trim().replace(/^"|"$/g, ""));
      return { name: parts[0] ?? "", email: parts[1] ?? "", status: parts[2] || "Приглашён" };
    })
    .filter((g) => g.name && g.email);
}

// Даты сидов — относительные (не протухают): dayOffset от сегодня, past = offset < 0.
function dateFor(offset: number, time: string) {
  const almatyParts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Almaty", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const part = (type: string) => almatyParts.find((entry) => entry.type === type)?.value ?? "";
  const d = new Date(`${part("year")}-${part("month")}-${part("day")}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + offset);
  return {
    date: `${d.toLocaleDateString("ru-RU", { day: "numeric", month: "long", timeZone: "UTC" })} · ${time}`,
    day: String(d.getUTCDate()).padStart(2, "0"),
    month: d.toLocaleDateString("ru-RU", { month: "short", timeZone: "UTC" }).replace(".", "").slice(0, 3).toUpperCase(),
    past: offset < 0,
  };
}

type SeedItem = Omit<EventItem, "date" | "day" | "month" | "past"> & { dayOffset: number; time: string };

const seedEvents: SeedItem[] = [
  {
    id: 1,
    title: "Future of Work / Almaty",
    company: "Orbit Labs",
    dayOffset: 5,
    time: "18:30",
    place: "Terrenkur Hall",
    city: "Алматы",
    category: "Технологии",
    access: "По регистрации",
    attendees: 184,
    capacity: 240,
    tone: "cobalt",
    image: "/covers/01-future-work.jpg",
    status: "published",
  },
  {
    id: 2,
    title: "After Hours: Product People",
    company: "Northstar Collective",
    dayOffset: 8,
    time: "20:00",
    place: "Rooftop 18",
    city: "Астана",
    category: "Нетворкинг",
    access: "Только по приглашению",
    attendees: 76,
    capacity: 90,
    tone: "coral",
    image: "/covers/02-after-dark.jpg",
    status: "published",
  },
  {
    id: 3,
    title: "Design Systems Picnic",
    company: "Forma Bureau",
    dayOffset: 15,
    time: "12:00",
    place: "Ботанический сад",
    city: "Алматы",
    category: "Дизайн",
    access: "Открытое событие",
    attendees: 129,
    capacity: 320,
    tone: "lime",
    image: "/covers/03-creative-play.jpg",
    status: "published",
  },
  {
    id: 4,
    title: "Зимний Jazz / Almaty",
    company: "Northstar Collective",
    dayOffset: -6,
    time: "19:00",
    place: "Rooftop 18",
    city: "Алматы",
    category: "Музыка",
    access: "По регистрации",
    attendees: 88,
    capacity: 120,
    tone: "cobalt",
    image: "/covers/02-after-dark.jpg",
    status: "published",
  },
  {
    id: 5, title: "Soft Signals: Design Night", company: "Forma Bureau",
    dayOffset: 14, time: "19:00", place: "Aspan Gallery", city: "Алматы",
    category: "Дизайн", access: "По регистрации", attendees: 42,
    capacity: 160, tone: "lime", image: "/covers/03-creative-play.jpg", status: "published",
  },
  {
    id: 6, title: "Night Shift: Electronic Sessions", company: "Northstar Collective",
    dayOffset: 18, time: "21:00", place: "Plasma Hall", city: "Астана",
    category: "Музыка", access: "По регистрации", attendees: 61,
    capacity: 280, tone: "coral", image: "/covers/02-after-dark.jpg", status: "published",
  },
  {
    id: 7, title: "Tomorrow Lab / Almaty", company: "Orbit Labs",
    dayOffset: 22, time: "17:30", place: "Tech Garden", city: "Алматы",
    category: "Наука", access: "По регистрации", attendees: 34,
    capacity: 180, tone: "cobalt", image: "/covers/01-future-work.jpg", status: "published",
  },
  {
    id: 8, title: "City Makers Meetup", company: "Urban Common",
    dayOffset: 27, time: "18:00", place: "Creative Hub", city: "Шымкент",
    category: "Нетворкинг", access: "По регистрации", attendees: 27,
    capacity: 120, tone: "lime", image: "/covers/03-creative-play.jpg", status: "published",
  },
  {
    id: 9, title: "New Forms Festival", company: "Forma Bureau",
    dayOffset: 33, time: "15:00", place: "Art Station", city: "Астана",
    category: "Дизайн", access: "По регистрации", attendees: 86,
    capacity: 400, tone: "coral", image: "/covers/02-after-dark.jpg", status: "published",
  },
];

const categories = ["Дизайн", "Технологии", "Нетворкинг", "Музыка", "Наука"];
const roleLabels: Record<Role, string> = { visitor: "Посетитель", organizer: "Организатор", admin: "Админ" };

function genCode(eventId: number) {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let suffix = "";
  for (let i = 0; i < 4; i++) suffix += alphabet[Math.floor(Math.random() * alphabet.length)];
  return `EVT-${eventId}-${suffix}`;
}

// Занятость места: онлайн — счётчик сервера; офлайн — база + моя регистрация (SPEC.md §10).
function occupied(event: EventItem, regs: Record<string, Reg>, online: boolean) {
  return online ? event.attendees : event.attendees + (regs[String(event.id)] ? 1 : 0);
}

const toneByCat: Record<string, string> = {
  Технологии: "cobalt",
  Нетворкинг: "coral",
  Дизайн: "lime",
  Музыка: "coral",
  Наука: "cobalt",
};

// Серверное событие → карточка каталога (оформление — клиентское).
function mapServerEvent(e: ServerEvent, i: number): EventItem {
  const d = new Date(e.starts_at);
  const valid = !isNaN(d.getTime());
  return {
    id: e.id,
    title: e.title,
    company: "Evently",
    date: valid
      ? `${d.toLocaleDateString("ru-RU", { day: "numeric", month: "long" })} · ${d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" })}`
      : e.starts_at || "Дата уточняется",
    day: valid ? String(d.getDate()).padStart(2, "0") : "—",
    month: valid ? d.toLocaleDateString("ru-RU", { month: "short" }).replace(".", "").slice(0, 3).toUpperCase() : "",
    place: e.place || "—",
    city: e.city || "—",
    category: e.category ?? "Разное",
    access: e.price > 0 ? `Билет · ${e.price}` : "По регистрации",
    attendees: e.occupied,
    capacity: e.capacity,
    tone: toneByCat[e.category ?? ""] ?? (i % 2 ? "coral" : "cobalt"),
    image: e.cover_url || coverForEventId(e.id),
    status: (e.status as EventItem["status"]) ?? "published",
    past: valid ? d.getTime() < Date.now() : false,
  };
}

function CoverArt({ image, tone, detail, children }: { image: string; tone: string; detail?: boolean; children: ReactNode }) {
  const base = detail ? "detail-poster" : "event-art";
  if (image.startsWith("gen:")) {
    return <div className={`${base} gen-art ${image.slice(4)}`}>{children}</div>;
  }
  const overlay = detail
    ? "linear-gradient(150deg, transparent, rgba(12,12,20,.4))"
    : "linear-gradient(140deg, transparent, rgba(15,16,28,.26))";
  return <div className={`${base} ${tone}`} style={{ backgroundImage: `${overlay}, url(${image})` }}>{children}</div>;
}

// Своё фото → downscale до 640px + JPEG, чтобы влезть в localStorage/БД демо.
function fileToCover(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const k = Math.min(1, 640 / Math.max(img.width, img.height));
      const c = document.createElement("canvas");
      c.width = Math.max(1, Math.round(img.width * k));
      c.height = Math.max(1, Math.round(img.height * k));
      c.getContext("2d")?.drawImage(img, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url);
      resolve(c.toDataURL("image/jpeg", 0.82));
    };
    img.onerror = reject;
    img.src = url;
  });
}

function RealQr({ code, size = 132 }: { code: string; size?: number }) {
  const [src, setSrc] = useState("");
  useEffect(() => {
    let live = true;
    QRCode.toDataURL(code, { width: 264, margin: 1 })
      .then((url) => { if (live) setSrc(url); })
      .catch(() => undefined);
    return () => { live = false; };
  }, [code]);
  if (!src) return <div className="qr-loading" style={{ width: size, height: size }} />;
  return <img className="qr-img" src={src} width={size} height={size} alt={`QR ${code}`} />;
}

function EventlyMark() {
  return (
    <span className="brand-mark" aria-hidden="true">
      <span>E</span><i /><b />
    </span>
  );
}

function Sidebar({
  view,
  setView,
  open,
  close,
  role,
  setRole,
  ticketCount,
  loggedIn,
}: {
  view: View;
  setView: (v: View) => void;
  open: boolean;
  close: () => void;
  role: Role;
  setRole: (r: Role) => void;
  ticketCount: number;
  loggedIn: boolean;
}) {
  const go = (id: View) => { setView(id); close(); };
  const item = (id: View, label: string, Icon: typeof Ticket, badge?: number) => (
    <button key={id} className={view === id ? "active" : ""} onClick={() => go(id)}>
      <Icon />{label}{typeof badge === "number" && badge > 0 && <em className="nav-badge">{badge}</em>}
    </button>
  );
  return (
    <aside className={`sidebar ${open ? "open" : ""}`}>
      <div className="brand"><EventlyMark /><strong>evently</strong></div>
      <button className="mobile-close" onClick={close} aria-label="Закрыть меню"><X /></button>
      <nav>
        <p className="nav-label">Для меня</p>
        {item("discover", "Афиша", Grid2X2)}
        {item("tickets", "Мои билеты", Ticket, ticketCount)}
        {item("cabinet", "Кабинет", User)}
        {(role === "organizer" || role === "admin") && (
          <>
            <p className="nav-label">Orbit Labs</p>
            {item("events", "События", CalendarDays)}
            {item("create", "Создать", Plus)}
            {item("studio", "Студия приглашений", Frame)}
            {item("guests", "Гости", Users)}
            {item("checkin", "Check-in", ScanLine)}
            {item("analytics", "Аналитика", BarChart3)}
          </>
        )}
        {role === "admin" && (
          <>
            <p className="nav-label">Платформа</p>
            {item("admin", "Админка", ShieldCheck)}
          </>
        )}
      </nav>
      {loggedIn ? (
        <div className="api-note">API · {roleLabels[role]}</div>
      ) : (
        <div className="role-switch" role="group" aria-label="Роль">
          {(["visitor", "organizer", "admin"] as Role[]).map((r) => (
            <button key={r} className={role === r ? "active" : ""} onClick={() => setRole(r)}>
              {r === "visitor" ? "Гость" : r === "organizer" ? "Орг" : "Админ"}
            </button>
          ))}
        </div>
      )}
      <div className="org-switcher">
        <span className="org-avatar">OL</span>
        <span><strong>Orbit Labs</strong><small>12 организаторов</small></span>
        <ChevronDown />
      </div>
    </aside>
  );
}

function Topbar({
  onMenu,
  query,
  setQuery,
  role,
  profile,
  apiUp,
  walletAddress,
  onConnectWallet,
  loggedIn,
  onAccount,
}: {
  onMenu: () => void;
  query: string;
  setQuery: (q: string) => void;
  role: Role;
  profile: Profile | null;
  apiUp: boolean;
  walletAddress: string | null;
  onConnectWallet: () => void;
  loggedIn: boolean;
  onAccount: () => void;
}) {
  const display = profile?.name ?? "Гость";
  const initials = display.split(/\s+/).map((w) => w[0]).join("").slice(0, 2).toUpperCase();
  return (
    <header className="topbar">
      <button className="menu-button" onClick={onMenu} aria-label="Открыть меню"><Menu /></button>
      <span className={apiUp ? "api-dot on" : "api-dot"} title={apiUp ? "API подключён" : "Офлайн-режим"} />
      <label className="search"><Search /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Найти событие, компанию или город" /></label>
      {apiUp && (loggedIn ? <button className={walletAddress ? "wallet-button connected" : "wallet-button"} onClick={onConnectWallet}><WalletCards /> {walletAddress ? shortWallet(walletAddress) : "Connect Phantom"}</button> : <button className="wallet-button login-button" onClick={onAccount}>Войти</button>)}
      <button className="icon-button" aria-label="Настройки"><Settings /></button>
      <button className="profile" onClick={onAccount} aria-label={loggedIn ? "Открыть кабинет" : "Войти или зарегистрироваться"}><span>{initials}</span><span className="profile-copy"><strong>{display}</strong><small>{roleLabels[role]}</small></span><ChevronDown /></button>
    </header>
  );
}

function Discover({
  list,
  selected,
  setSelected,
  regs,
  register,
  favorites,
  toggleFav,
  online,
  waitlist,
  leaveWaitlist,
}: {
  list: EventItem[];
  selected: EventItem;
  setSelected: (e: EventItem) => void;
  regs: Record<string, Reg>;
  register: (id: number) => void;
  favorites: number[];
  toggleFav: (id: number) => void;
  online: boolean;
  waitlist: Record<string, WaitEntry>;
  leaveWaitlist: (id: number) => void;
}) {
  const [filter, setFilter] = useState("Все события");
  const filtered = list.filter((e) => {
    if (filter === "Для моей компании" && e.company !== "Orbit Labs") return false;
    if (!["Все события", "Для моей компании"].includes(filter) && e.category !== filter) return false;
    return true;
  });
  const reg = regs[String(selected.id)];
  const waiting = waitlist[String(selected.id)];
  const soldout = occupied(selected, regs, online) >= selected.capacity;
  return (
    <div className="page-grid">
      <section className="content discover">
        <div className="eyebrow-row"><span>ГОРОДА КАЗАХСТАНА</span><span>АФИША СОБЫТИЙ</span></div>
        <div className="page-title-row">
          <div><h1>Куда пойдём<br />дальше?</h1><p>События от компаний, команд и людей, за которыми хочется следить.</p></div>
          <span className="title-sticker">CURATED<br />FOR YOU <Sparkles /></span>
        </div>
        <div className="filters">
          {["Все события", "Для моей компании", ...categories].map((name) => (
            <button key={name} className={filter === name ? "active" : ""} onClick={() => setFilter(name)}>{name}</button>
          ))}
        </div>
        <div className="event-list">
          {filtered.map((event) => {
            const full = occupied(event, regs, online) >= event.capacity;
            const occ = occupied(event, regs, online);
            const isReg = Boolean(regs[String(event.id)]);
            const isWaiting = Boolean(waitlist[String(event.id)]);
            return (
              <button className={`event-card ${selected.id === event.id ? "selected" : ""}`} key={event.id} onClick={() => setSelected(event)}>
                <CoverArt image={event.image} tone={event.tone}>
                  <span className="date-tile"><b>{event.day}</b><small>{event.month}</small></span>
                  <span className="art-label">{event.company}</span>
                </CoverArt>
                <div className="event-copy">
                  <div className="tag-row"><span>{event.category}</span><span>{event.access}</span>{event.past && <span className="soldout-pill">Завершено</span>}{full && !event.past && <span className="soldout-pill">Sold out</span>}{isReg && <span className="reg-pill">Билет есть</span>}{isWaiting && <span className="wait-pill">Лист ожидания · №{waitlist[String(event.id)].position}</span>}</div>
                  <h2>{event.title}</h2>
                  <p><CalendarDays />{event.date}</p><p><MapPin />{event.place}, {event.city}</p>
                  <div className="capacity"><span><i style={{ width: `${Math.min(100, (occ / event.capacity) * 100)}%` }} /></span><small>{occ} из {event.capacity} мест</small></div>
                </div>
                <span className="card-side">
                  <span
                    role="button"
                    tabIndex={0}
                    aria-label="В избранное"
                    className={`fav-button ${favorites.includes(event.id) ? "on" : ""}`}
                    onClick={(e) => { e.stopPropagation(); toggleFav(event.id); }}
                    onKeyDown={(e) => { if (e.key === "Enter") { e.stopPropagation(); toggleFav(event.id); } }}
                  ><Heart /></span>
                  <ArrowRight className="card-arrow" />
                </span>
              </button>
            );
          })}
          {filtered.length === 0 && (
            <div className="empty-state"><strong>Ничего не найдено</strong><p>Попробуйте другой запрос или фильтр.</p></div>
          )}
        </div>
      </section>
      <aside className="detail-panel">
        <button className="panel-menu" aria-label="Другие действия"><MoreHorizontal /></button>
        <CoverArt image={selected.image} tone={selected.tone} detail>
          <span>{selected.company}</span><strong>{selected.title}</strong><small>{selected.date}</small>
        </CoverArt>
        <div className="detail-content">
          <div className="tag-row"><span>{selected.category}</span><span>{selected.access}</span></div>
          <h2>{selected.title}</h2>
          <p>Разговоры без скучных панелей, новые знакомства и идеи, которые хочется унести с собой.</p>
          <dl><div><dt>Когда</dt><dd>{selected.date}</dd></div><div><dt>Где</dt><dd>{selected.place}<small>{selected.city}</small></dd></div><div><dt>Организатор</dt><dd>{selected.company}<small>Подтверждённая компания</small></dd></div></dl>
          {reg && <p className="ticket-hint">Ваш билет: <b>{reg.code}</b>{reg.used ? " · уже использован" : ""}</p>}
          {waiting && <p className="wait-hint">Вы в листе ожидания под номером <b>{waiting.position}</b>. Когда освободится место, билет появится автоматически.</p>}
          <button className={`register-button ${reg || waiting ? "done" : ""}`} disabled={Boolean(waiting) || (!reg && selected.past)} onClick={() => register(selected.id)}>
            {reg ? <><Check /> Вы зарегистрированы</> : waiting ? <><Check /> Вы в листе ожидания · №{waiting.position}</> : selected.past ? <>Событие прошло</> : soldout ? <>Встать в лист ожидания <ArrowRight /></> : <>Получить билет <ArrowRight /></>}
          </button>
          {waiting && <button className="wait-cancel" onClick={() => leaveWaitlist(selected.id)}>Выйти из листа ожидания</button>}
          <small className="privacy-note">1 человек = 1 билет · очередь продвигается автоматически</small>
        </div>
      </aside>
    </div>
  );
}

async function downloadTicketPNG(event: EventItem, code: string, guest: string) {
  const qrUrl = await QRCode.toDataURL(code, { width: 400, margin: 1 });
  const qrImg = new Image();
  await new Promise((resolve, reject) => {
    qrImg.onload = resolve;
    qrImg.onerror = reject;
    qrImg.src = qrUrl;
  });
  const canvas = document.createElement("canvas");
  canvas.width = 1080;
  canvas.height = 1350;
  const context = canvas.getContext("2d");
  if (!context) return;
  context.fillStyle = "#19181f";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = "#d8ff45";
  context.beginPath();
  context.arc(940, 320, 250, 0, Math.PI * 2);
  context.fill();
  context.fillStyle = "#ffffff";
  context.font = "900 88px Arial";
  context.fillText(event.title.toUpperCase(), 72, 520, 900);
  context.font = "700 34px Arial";
  context.fillText(event.date, 72, 660);
  context.fillText(`${event.place}, ${event.city}`, 72, 720);
  context.font = "700 28px Arial";
  context.fillText(`TICKET — ${code}`, 72, 1120);
  context.fillText(`GUEST — ${guest.toUpperCase()}`, 72, 1170);
  context.drawImage(qrImg, 72, 880, 160, 160);
  const anchor = document.createElement("a");
  anchor.download = `evently-${code}.png`;
  anchor.href = canvas.toDataURL("image/png");
  anchor.click();
}

function TicketView({ regs, events, profile, onCancel }: { regs: Record<string, Reg>; events: EventItem[]; profile: Profile | null; onCancel: (id: number) => void }) {
  const guest = profile?.name ?? "Гость";
  const mine = events.filter((e) => regs[String(e.id)]);
  if (mine.length === 0) {
    return (
      <section className="content ticket-page">
        <span className="section-kicker">МОИ БИЛЕТЫ</span><h1>Пока пусто.</h1>
        <div className="empty-state"><p>Зарегистрируйтесь на событие в афише — билет с QR появится здесь.</p></div>
      </section>
    );
  }
  return (
    <section className="content ticket-page">
      <span className="section-kicker">МОИ БИЛЕТЫ / {String(mine.length).padStart(2, "0")}</span><h1>До встречи<br />на событии.</h1>
      <div className="ticket-list">
        {mine.map((event) => {
          const reg = regs[String(event.id)];
          return (
            <div className="ticket-layout" key={event.id}>
              <article className="ticket-card">
                <div className="ticket-top"><EventlyMark /><span>{reg.used ? "USED" : reg.blockchainStatus === "confirmed" ? "SOLANA VERIFIED" : "PENDING"}</span></div>
                <div><small>ORBIT LABS ПРЕДСТАВЛЯЕТ</small><h2>{event.title}</h2></div>
                <div className="ticket-meta"><span><small>ДАТА</small>{event.date}</span><span><small>МЕСТО</small>{event.place}</span></div>
                <div className="ticket-owner"><span><small>ГОСТЬ</small>{guest}</span><span><small>БИЛЕТ</small>{reg.code}</span></div>
                <div className="ticket-qr-row"><RealQr code={reg.code} /></div>
                <p>{reg.blockchainStatus === "confirmed" || reg.blockchainStatus === "used" ? "Solana Verified ✓ · непередаваемый Token-2022" : "Blockchain confirmation pending"}</p>
              </article>
              <div className="ticket-actions"><h3>Билет готов</h3><p>Сохраните его на телефон или распечатайте. QR-код одинаковый во всех форматах.</p>{reg.wallet && <div className={reg.blockchainStatus === "confirmed" || reg.blockchainStatus === "used" ? "chain-proof" : "chain-proof pending"}><span><ShieldCheck /> {reg.blockchainStatus === "confirmed" || reg.blockchainStatus === "used" ? "Solana Verified" : "Solana Pending"}</span><small>Wallet · {shortWallet(reg.wallet)}</small>{reg.tokenAddress && <small>Token · {shortWallet(reg.tokenAddress)}</small>}{reg.explorerUrl && <a href={reg.explorerUrl} target="_blank" rel="noreferrer">View on Solana Explorer <ExternalLink /></a>}</div>}<button onClick={() => window.print()}><Download /> Скачать PDF</button><button onClick={() => downloadTicketPNG(event, reg.code, guest)}><ImagePlus /> Сохранить PNG</button><a className="ticket-mail" href={`mailto:${profile?.email ?? ""}?subject=${encodeURIComponent(`Билет: ${event.title}`)}&body=${encodeURIComponent(`Ваш билет ${reg.code} на «${event.title}» (${event.date}, ${event.place}, ${event.city}). Покажите QR-код на входе.`)}`}><Send /> Отправить на email</a><button onClick={() => onCancel(event.id)} disabled={reg.used}>{reg.used ? "Билет использован" : "Отменить регистрацию"}</button></div>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function CabinetView({
  regs,
  events,
  favorites,
  toggleFav,
  go,
  profile,
  onSaveProfile,
  server,
  onLogout,
}: {
  regs: Record<string, Reg>;
  events: EventItem[];
  favorites: number[];
  toggleFav: (id: number) => void;
  go: (v: View) => void;
  profile: Profile | null;
  onSaveProfile: (name: string, email: string) => void;
  server: boolean;
  onLogout: () => void;
}) {
  const ticketEvents = events.filter((e) => regs[String(e.id)]);
  const favEvents = events.filter((e) => favorites.includes(e.id));
  const visits = ticketEvents.filter((e) => regs[String(e.id)].used).length;
  const [name, setName] = useState(profile?.name ?? "");
  const [email, setEmail] = useState(profile?.email ?? "");
  return (
    <section className="content data-page">
      <span className="section-kicker">КАБИНЕТ ПОСЕТИТЕЛЯ</span>
      <div className="data-heading"><div><h1>Привет{profile ? `, ${profile.name}` : ""}</h1><p>Билеты, избранное и посещения — всё в одном месте.</p></div><button className="primary" onClick={() => go("discover")}><Ticket /> В афишу</button></div>
      <div className="metric-row">
        <article><small>БИЛЕТЫ</small><strong>{ticketEvents.length}</strong><span>уникальные QR-коды</span></article>
        <article><small>ИЗБРАННОЕ</small><strong>{favEvents.length}</strong><span>сохранённые события</span></article>
        <article><small>ПОСЕЩЕНИЯ</small><strong>{visits}</strong><span>отмечено на входе</span></article>
      </div>
      {server ? (
        <div className="form-card profile-card">
          <div className="form-grid">
            <label>Имя<span className="profile-value">{profile?.name ?? "—"}</span></label>
            <label>Email<span className="profile-value">{profile?.email ?? "—"}</span></label>
          </div>
          <div className="form-actions"><button className="secondary" onClick={onLogout}>Выйти из аккаунта</button></div>
        </div>
      ) : (
      <div className="form-card profile-card">
        <div className="form-grid">
          <label>Имя<input value={name} onChange={(e) => setName(e.target.value)} placeholder="Как вас зовут" /></label>
          <label>Email<input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@mail.com" inputMode="email" /></label>
        </div>
        <div className="form-actions"><button className="primary" onClick={() => { if (name.trim().length >= 2 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) onSaveProfile(name.trim(), email.trim()); }}><Check /> Сохранить профиль</button></div>
      </div>
      )}
      <div className="data-card">
        <div className="data-card-head"><span><Heart /> Избранное</span></div>
        {favEvents.length === 0 && <p className="pad-note">Нажмите на сердечко в каталоге, чтобы сохранить событие.</p>}
        {favEvents.map((event) => (
          <div className="table-row" key={event.id}>
            <span className={`tiny-art ${event.tone}`}>{event.day}</span>
            <span><strong>{event.title}</strong><small>{event.date}</small></span>
            <span><small>БИЛЕТ</small>{regs[String(event.id)] ? regs[String(event.id)].code : "—"}</span>
            <span className="status-pill">Сохранено</span>
            <button aria-label="Убрать из избранного" onClick={() => toggleFav(event.id)}><X /></button>
          </div>
        ))}
      </div>
    </section>
  );
}

function CreateView({ onCreate }: { onCreate: (e: EventItem) => void }) {
  const [title, setTitle] = useState("Новый митап сообщества");
  const [city, setCity] = useState("Алматы");
  const [place, setPlace] = useState("Площадка уточняется");
  const [date, setDate] = useState("12 октября · 19:00");
  const [category, setCategory] = useState(categories[0]);
  const [capacity, setCapacity] = useState(100);
  const [cover, setCover] = useState<string>(randomEventCover);
  const [coverError, setCoverError] = useState("");
  const uploadCover = (file: File | undefined) => {
    if (!file) return;
    setCoverError("");
    fileToCover(file)
      .then(setCover)
      .catch(() => setCoverError("Не получилось прочитать файл"));
  };
  const submit = () => {
    onCreate({
      id: Date.now(),
      title: title.trim() || "Без названия",
      company: "Orbit Labs",
      date,
      day: date.slice(0, 2),
      month: "ОКТ",
      place,
      city,
      category,
      access: "По регистрации",
      attendees: 0,
      capacity: Math.max(1, capacity),
      tone: "cobalt",
      image: cover,
      status: "published",
      past: false,
    });
  };
  return (
    <section className="content data-page">
      <span className="section-kicker">ORBIT LABS / НОВОЕ СОБЫТИЕ</span>
      <div className="data-heading"><div><h1>Создание</h1><p>Заполните поля — событие сразу попадёт в каталог.</p></div></div>
      <div className="form-card">
        <div className="form-grid">
          <label>Название<input value={title} onChange={(e) => setTitle(e.target.value)} /></label>
          <label>Категория<select value={category} onChange={(e) => setCategory(e.target.value)}>{categories.map((c) => <option key={c}>{c}</option>)}</select></label>
          <label>Дата и время<input value={date} onChange={(e) => setDate(e.target.value)} /></label>
          <label>Лимит мест<input type="number" min={1} max={5000} value={capacity} onChange={(e) => setCapacity(Number(e.target.value))} /></label>
          <label>Город<input value={city} onChange={(e) => setCity(e.target.value)} /></label>
          <label>Место<input value={place} onChange={(e) => setPlace(e.target.value)} /></label>
        </div>
        <div className="cover-picker">
          <span className="cover-label">Обложка карточки</span>
          <div className="cover-grid">
            {EVENT_COVERS.map((c) => (
              <button key={c.id} type="button" className={cover === c.id ? "active" : ""} onClick={() => setCover(c.id)} title={c.name}>
                <CoverArt image={c.id} tone="cobalt"><span className="cover-name">{c.name}</span></CoverArt>
              </button>
            ))}
            {cover.startsWith("data:") && (
              <button type="button" className="active" title="Своё фото">
                <CoverArt image={cover} tone="cobalt"><span className="cover-name">Своё фото</span></CoverArt>
              </button>
            )}
            <label className="cover-upload"><ImagePlus />Своя<input type="file" accept="image/*" hidden onChange={(e) => { uploadCover(e.target.files?.[0]); e.target.value = ""; }} /></label>
          </div>
          {coverError && <p className="msg-err">{coverError}</p>}
        </div>
        <div className="form-actions"><button className="primary" onClick={submit}><Plus /> Опубликовать</button></div>
      </div>
    </section>
  );
}

function Studio() {
  const [template, setTemplate] = useState(0);
  const [accent, setAccent] = useState("#d8ff45");
  const [fontSize, setFontSize] = useState(54);
  const [preview, setPreview] = useState(false);
  const [extraTexts, setExtraTexts] = useState<string[]>([]);
  const [photo, setPhoto] = useState<string | null>(null);
  const [showQr, setShowQr] = useState(false);
  const [shape, setShape] = useState(0);
  const templates = ["Pulse", "Afterdark", "Gallery", "Minimal"];
  const addPhoto = (file: File | undefined) => {
    if (!file) return;
    if (photo) URL.revokeObjectURL(photo);
    setPhoto(URL.createObjectURL(file));
  };
  return (
    <div className="studio-shell">
      <header className="studio-head"><div><span className="section-kicker">СТУДИЯ ПРИГЛАШЕНИЙ</span><h1>Future of Work</h1></div><div><button className="secondary" onClick={() => setPreview(true)}><Eye /> Предпросмотр</button><button className="primary"><Check /> Сохранено</button></div></header>
      <div className="studio-workspace">
        <aside className="studio-tools">
          <h3>Шаблоны</h3><div className="template-grid">{templates.map((name, i) => <button key={name} className={template === i ? "active" : ""} onClick={() => setTemplate(i)}><span className={`mini-poster t${i}`} />{name}</button>)}</div>
          <hr /><h3>Добавить</h3><div className="tool-buttons"><button onClick={() => setExtraTexts([...extraTexts, "Новый текст — нажмите и правьте"])}><Type />Текст</button><label className="tool-upload"><ImagePlus />Фото<input type="file" accept="image/*" hidden onChange={(e) => { addPhoto(e.target.files?.[0]); e.target.value = ""; }} /></label><button className={showQr ? "on" : ""} onClick={() => setShowQr(!showQr)}><QrCode />QR-код</button><button className={shape > 0 ? "on" : ""} onClick={() => setShape((shape + 1) % 3)}><Grid2X2 />Фигура</button></div>
        </aside>
        <main className="canvas-wrap">
          <div className="canvas-toolbar"><button><Minus /></button><span>62%</span><button><Plus /></button><span className="divider" /><button>1080 × 1350 <ChevronDown /></button></div>
          <div className={`invite-canvas template-${template}`} style={{ "--invite-accent": accent } as CSSProperties}>
            <span className="invite-orbit">ORBIT LABS</span><span className="invite-index">01 / 04</span>
            <div className="invite-shape" /><div className="invite-ring" />
            <div className="editable-title" style={{ fontSize }} contentEditable suppressContentEditableWarning>FUTURE<br />OF WORK</div>
            <p>24.09 · TERRENKUR HALL<br />ALMATY · 18:30</p>
            {photo && <img className="invite-photo" src={photo} alt="Загруженное фото" />}
            {showQr && <div className="invite-qr"><RealQr code="EVT-1-DEMO" size={96} /></div>}
            {shape > 0 && <div className={`invite-extra-shape s${shape}`} />}
            {extraTexts.map((t, i) => <div key={i} className="invite-extra" contentEditable suppressContentEditableWarning onBlur={(e) => setExtraTexts(extraTexts.map((x, j) => (j === i ? (e.currentTarget.textContent ?? x) : x)))}>{t}</div>)}
            <span className="invite-code">INVITE / {"{{guest_name}}"}</span>
          </div>
        </main>
        <aside className="properties">
          <div className="prop-tabs"><button className="active">Дизайн</button><button>Данные</button></div>
          <label>Текст<input defaultValue="FUTURE OF WORK" /></label>
          <label>Шрифт<select defaultValue="grotesk"><option value="grotesk">Space Grotesk</option><option>Inter</option><option>Georgia</option></select></label>
          <label>Размер<div className="range-row"><input type="range" min="32" max="80" value={fontSize} onChange={(e) => setFontSize(Number(e.target.value))} /><span>{fontSize}</span></div></label>
          <label>Акцент<div className="swatches">{["#d8ff45", "#ff6846", "#6c57ff", "#63e6be"].map((color) => <button key={color} className={accent === color ? "active" : ""} style={{ background: color }} onClick={() => setAccent(color)} aria-label={`Выбрать ${color}`} />)}</div></label>
          <hr /><h3>Слои</h3><button className="layer active"><Type />Заголовок <MoreHorizontal /></button><button className="layer"><QrCode />QR-код <MoreHorizontal /></button><button className="layer"><FileText />Детали <MoreHorizontal /></button>
        </aside>
      </div>
      {preview && (
        <div className="modal-scrim" onClick={() => setPreview(false)}>
          <div className="preview-modal" onClick={(e) => e.stopPropagation()}>
            <div className={`invite-canvas template-${template}`} style={{ "--invite-accent": accent } as CSSProperties}>
              <span className="invite-orbit">ORBIT LABS</span><span className="invite-index">01 / 04</span>
              <div className="invite-shape" /><div className="invite-ring" />
              <div className="editable-title" style={{ fontSize }}>FUTURE<br />OF WORK</div>
              <p>24.09 · TERRENKUR HALL<br />ALMATY · 18:30</p>
              {photo && <img className="invite-photo" src={photo} alt="Загруженное фото" />}
              {showQr && <div className="invite-qr"><RealQr code="EVT-1-DEMO" size={96} /></div>}
              {shape > 0 && <div className={`invite-extra-shape s${shape}`} />}
              {extraTexts.map((t, i) => <div key={i} className="invite-extra">{t}</div>)}
              <span className="invite-code">INVITE / {"{{guest_name}}"}</span>
            </div>
            <button className="primary" onClick={() => setPreview(false)}><Check /> Готово</button>
          </div>
        </div>
      )}
    </div>
  );
}

function EventsView({ events, regs, online, go, toggleStatus }: { events: EventItem[]; regs: Record<string, Reg>; online: boolean; go: (v: View) => void; toggleStatus: (id: number) => void }) {
  const myRegs = Object.values(regs).length;
  const visits = Object.values(regs).filter((r) => r.used).length;
  return (
    <section className="content data-page"><span className="section-kicker">ORBIT LABS / ПАНЕЛЬ</span><div className="data-heading"><div><h1>События</h1><p>Управляйте публикациями, регистрациями и программой.</p></div><button className="primary" onClick={() => go("create")}><Plus /> Создать</button></div>
      <div className="metric-row"><article><small>СОБЫТИЯ</small><strong>{events.length}</strong><span>в каталоге</span></article><article><small>МОИ РЕГИСТРАЦИИ</small><strong>{myRegs}</strong><span>выданные билеты</span></article><article><small>ВИЗИТЫ</small><strong>{visits}</strong><span>отмечено на входе</span></article></div>
      <div className="data-card"><div className="data-card-head"><span><CalendarDays /> Активные события</span><button>Все события <ArrowRight /></button></div>{events.map((event) => <div className="table-row" key={event.id}><span className={`tiny-art ${event.tone}`}>{event.day}</span><span><strong>{event.title}</strong><small>{event.date}</small></span><span><small>ГОСТИ</small>{occupied(event, regs, online)} / {event.capacity}</span><button className={`status-pill ${event.status !== "published" ? "muted" : ""}`} onClick={() => toggleStatus(event.id)}>{event.status === "published" ? "Опубликовано" : "Скрыто"}</button><button aria-label="Меню"><MoreHorizontal /></button></div>)}</div>
    </section>
  );
}

const seededGuests = [
  { name: "Алина Ибраева", email: "alina@orbit.kz", status: "Подтверждён", initials: "АИ" },
  { name: "Марк Соколов", email: "mark@northstar.team", status: "Приглашён", initials: "МС" },
  { name: "Дана Ахметова", email: "dana@forma.studio", status: "Лист ожидания", initials: "ДА" },
  { name: "Илья Ли", email: "ilya@orbit.kz", status: "Подтверждён", initials: "ИЛ" },
];

function initialsOf(name: string) {
  return name.split(/\s+/).map((w) => w[0]).join("").slice(0, 2).toUpperCase();
}

function GuestsView({ profile, guests, onImport }: { profile: Profile | null; guests: GuestRow[]; onImport: (list: GuestRow[]) => void }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("Все статусы");
  const rows = useMemo(() => {
    const me = profile ? [{ name: profile.name, email: profile.email, status: "Подтверждён" }] : [];
    return [...me, ...guests, ...seededGuests].filter((g) => {
      if (status !== "Все статусы" && g.status !== status) return false;
      return `${g.name} ${g.email}`.toLowerCase().includes(query.toLowerCase());
    });
  }, [query, profile, guests, status]);
  const importFile = (file: File | undefined) => {
    if (!file) return;
    file.text().then((text) => onImport(parseCSV(text))).catch(() => undefined);
  };
  return <section className="content data-page"><span className="section-kicker">ORBIT LABS / CRM</span><div className="data-heading"><div><h1>Гости</h1><p>Единый список приглашённых и статусы регистрации.</p></div><label className="primary import-label"><Plus /> Импорт CSV<input type="file" accept=".csv,text/csv,text/plain" hidden onChange={(e) => { importFile(e.target.files?.[0]); e.target.value = ""; }} /></label></div>
    <div className="guest-tools"><label><Search /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Имя или email" /></label><select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Фильтр по статусу">{["Все статусы", "Подтверждён", "Приглашён", "Лист ожидания"].map((s) => <option key={s}>{s}</option>)}</select><button onClick={() => downloadCSV("evently-guests.csv", guestsToCSV(rows))}><Download /> Экспорт</button></div>
    <div className="data-card guest-list"><div className="data-card-head"><span><Users /> {rows.length} гостя</span><button>Настроить поля <ArrowRight /></button></div>{rows.map((guest) => <div className="guest-row" key={guest.email}><span className="guest-avatar">{initialsOf(guest.name)}</span><span><strong>{guest.name}</strong><small>{guest.email}</small></span><span className={`guest-status ${guest.status === "Подтверждён" ? "ok" : ""}`}>{guest.status}</span><button aria-label="Меню гостя"><MoreHorizontal /></button></div>)}</div>
  </section>;
}

type ScannerLike = {
  start: (...args: unknown[]) => Promise<unknown>;
  stop: () => Promise<unknown>;
  clear: () => void;
};

function QrScanner({ onScan, onClose }: { onScan: (text: string) => void; onClose: () => void }) {
  const [error, setError] = useState("");
  const cb = useRef(onScan);
  useEffect(() => {
    cb.current = onScan;
  });
  useEffect(() => {
    let scanner: ScannerLike | null = null;
    let cancelled = false;
    import("html5-qrcode")
      .then((mod) => {
        if (cancelled) return undefined;
        const Ctor = (mod as unknown as { Html5Qrcode: new (id: string) => ScannerLike }).Html5Qrcode;
        scanner = new Ctor("evently-qr-reader");
        return scanner.start({ facingMode: "environment" }, { fps: 10, qrbox: 250 }, (text: unknown) => {
          if (typeof text === "string") cb.current(text);
        });
      })
      .catch(() => {
        if (!cancelled) setError("Камера недоступна — введите код вручную");
      });
    return () => {
      cancelled = true;
      if (scanner) scanner.stop().then(() => scanner?.clear()).catch(() => undefined);
    };
  }, []);
  return (
    <div className="modal-scrim" onClick={onClose}>
      <div className="modal-card" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true" aria-label="Сканер QR">
        <h2>Сканер</h2>
        <p>Наведите камеру на QR-код билета.</p>
        <div id="evently-qr-reader" className="qr-reader" />
        {error && <p className="msg-err">{error}</p>}
        <div className="form-actions"><button className="secondary" onClick={onClose}>Закрыть</button></div>
      </div>
    </div>
  );
}

function CheckinView({
  regs,
  events,
  log,
  profile,
  checkIn,
  message,
}: {
  regs: Record<string, Reg>;
  events: EventItem[];
  log: CheckLog[];
  profile: Profile | null;
  checkIn: (label: string) => void;
  message: string;
}) {
  const [code, setCode] = useState("");
  const [scannerOpen, setScannerOpen] = useState(false);
  const entered = (label: string) => log.some((l) => l.label === label && l.result === "ok");
  const myRows = events.filter((e) => regs[String(e.id)]);
  const enteredCount = log.filter((l) => l.result === "ok").length;
  const activeCodes = myRows.filter((e) => !regs[String(e.id)].used).length;
  const myName = profile?.name ?? "Гость";
  const myInitials = myName.split(/\s+/).map((w) => w[0]).join("").slice(0, 2).toUpperCase();
  const history = [...log].slice(-6).reverse();
  return <section className="content data-page"><span className="section-kicker">FUTURE OF WORK / ВХОД</span><div className="data-heading"><div><h1>Check-in</h1><p>Код, список и сканер пишут в один журнал. Активных билетов: {activeCodes}.</p></div><span className="live-badge"><i /> Онлайн</span></div>
    <div className="verify-row"><label><ScanLine /><input value={code} onChange={(e) => setCode(e.target.value)} placeholder="Введите код билета, например EVT-1-AB12" /></label><button className="primary" onClick={() => checkIn(code)}>Проверить</button></div>
    {message && <p className={message.startsWith("Проход") ? "msg-ok" : "msg-err"}>{message}</p>}
    <div className="checkin-grid"><article className="scanner-card"><div className="scanner-frame"><span /><QrCode /><b>Наведите камеру на QR</b></div><button className="primary" onClick={() => setScannerOpen(true)}><ScanLine /> Открыть сканер</button><p>Последняя синхронизация: только что</p></article>
    <article className="checkin-list"><div className="data-card-head"><span><Users /> На площадке</span><strong>{enteredCount}</strong></div>
      {myRows.map((e) => {
        const reg = regs[String(e.id)];
        const done = reg.used || entered(reg.code);
        return <button className="checkin-person" key={e.id} onClick={() => checkIn(reg.code)}><span className="guest-avatar">{myInitials}</span><span><strong>{myName} · {e.title}</strong><small>{reg.code}</small></span><span className={done ? "checked" : "pending"}>{done ? <><Check /> Вошёл</> : "Отметить"}</span></button>;
      })}
      {seededGuests.map((guest) => {
        const done = entered(guest.name);
        return <button className="checkin-person" key={guest.email} onClick={() => checkIn(guest.name)}><span className="guest-avatar">{guest.initials}</span><span><strong>{guest.name}</strong><small>{guest.email}</small></span><span className={done ? "checked" : "pending"}>{done ? <><Check /> Вошёл</> : "Отметить"}</span></button>;
      })}
    </article></div>
    {history.length > 0 && <div className="data-card log-card"><div className="data-card-head"><span><ScanLine /> Журнал проходов</span></div>{history.map((h, i) => <div className="log-row" key={`${h.at}-${i}`}><span>{h.label}</span><span className={h.result === "ok" ? "guest-status ok" : "guest-status"}>{h.result === "ok" ? "Прошёл" : "Дубль"}</span></div>)}</div>}
    {scannerOpen && <QrScanner onScan={(text) => { setScannerOpen(false); checkIn(text); }} onClose={() => setScannerOpen(false)} />}
  </section>;
}

function AnalyticsView({ events, regs }: { events: EventItem[]; regs: Record<string, Reg> }) {
  const total = Object.keys(regs).length;
  const active = Object.values(regs).filter((r) => !r.used).length;
  const visits = total - active;
  const funnel = [
    { label: "Регистрации", value: total, width: 100 },
    { label: "Активные билеты", value: active, width: total ? Math.round((active / total) * 100) : 0 },
    { label: "Визиты", value: visits, width: total ? Math.round((visits / total) * 100) : 0 },
  ];
  return <section className="content data-page"><span className="section-kicker">ORBIT LABS / INSIGHTS</span><div className="data-heading"><div><h1>Аналитика</h1><p>Только реальные данные этого устройства. Событий: {events.length}.</p></div></div>
    <div className="metric-row"><article><small>РЕГИСТРАЦИИ</small><strong>{total}</strong><span>выданные билеты</span></article><article><small>АКТИВНЫЕ</small><strong>{active}</strong><span>ждут входа</span></article><article><small>ВИЗИТЫ</small><strong>{visits}</strong><span>отмечено на входе</span></article></div>
    <div className="analytics-grid"><article className="funnel-card"><div className="data-card-head"><span><BarChart3 /> Воронка</span><small>регистрация → визит</small></div><div className="funnel-bars">{funnel.map((item) => <div key={item.label}><span><b>{item.label}</b><strong>{item.value}</strong></span><i><b style={{ width: `${item.width}%` }} /></i></div>)}</div></article><article className="funnel-card"><div className="data-card-head"><span><Ticket /> Мои события</span></div><div className="funnel-bars">{events.filter((e) => regs[String(e.id)]).map((e) => <div key={e.id}><span><b>{e.title}</b><strong>{regs[String(e.id)].used ? "Визит" : regs[String(e.id)].code}</strong></span></div>)}{total === 0 && <p className="pad-note">Пока нет данных — зарегистрируйтесь на событие в афише.</p>}</div></article></div>
  </section>;
}

function AdminView({ events, regs, online, log, overview, toggleStatus }: { events: EventItem[]; regs: Record<string, Reg>; online: boolean; log: CheckLog[]; overview: { events: number; users: number; registrations: number; visits: number } | null; toggleStatus: (id: number) => void }) {
  const ok = log.filter((l) => l.result === "ok").length;
  const dup = log.filter((l) => l.result === "duplicate").length;
  return (
    <section className="content data-page">
      <span className="section-kicker">ПЛАТФОРМА / МОДЕРАЦИЯ</span>
      <div className="data-heading"><div><h1>Админка</h1><p>Модерация событий, категории и общая статистика.</p></div></div>
      <div className="metric-row"><article><small>СОБЫТИЯ</small><strong>{overview?.events ?? events.length}</strong><span>на модерации: 0</span></article><article><small>РЕГИСТРАЦИИ</small><strong>{overview?.registrations ?? Object.keys(regs).length}</strong><span>выданные билеты</span></article><article><small>ПРОХОДЫ</small><strong>{overview?.visits ?? ok}</strong><span>повторных попыток: {dup}</span></article></div>
      <div className="data-card"><div className="data-card-head"><span><ShieldCheck /> Все события</span><small>нажмите на статус, чтобы скрыть/опубликовать</small></div>
        {events.map((event) => (
          <div className="table-row" key={event.id}>
            <span className={`tiny-art ${event.tone}`}>{event.day}</span>
            <span><strong>{event.title}</strong><small>{event.company} · {event.city}</small></span>
            <span><small>МЕСТА</small>{occupied(event, regs, online)} / {event.capacity}</span>
            <button className={`status-pill ${event.status !== "published" ? "muted" : ""}`} onClick={() => toggleStatus(event.id)}>{event.status === "published" ? "Опубликовано" : "Скрыто"}</button>
            <button aria-label="Меню"><MoreHorizontal /></button>
          </div>
        ))}
      </div>
      <div className="data-card admin-cats"><div className="data-card-head"><span><Grid2X2 /> Категории</span></div><div className="cat-row">{categories.map((c) => <span key={c}>{c}</span>)}</div></div>
    </section>
  );
}

type Persisted = {
  role: Role;
  profile: Profile | null;
  favorites: number[];
  regs: Record<string, Reg>;
  extra: EventItem[];
  statusOv: Record<string, string>;
  log: CheckLog[];
  guests: GuestRow[];
  waitlist: Record<string, WaitEntry>;
};

const defaults: Persisted = { role: "visitor", profile: null, favorites: [], regs: {}, extra: [], statusOv: {}, log: [], guests: [], waitlist: {} };

function loadPersisted(): Persisted {
  if (typeof window === "undefined") return defaults;
  try {
    const raw = window.localStorage.getItem("evently-v1");
    if (!raw) return defaults;
    const parsed = JSON.parse(raw) as Partial<Persisted> & { log?: Array<CheckLog & { code?: string }> };
    const log: CheckLog[] = Array.isArray(parsed.log)
      ? (parsed.log as Array<CheckLog & { code?: string }>).map((l) => ({
          label: l.label ?? l.code ?? "",
          result: l.result,
          at: l.at,
        }))
      : [];
    return { ...defaults, ...parsed, log };
  } catch {
    return defaults;
  }
}

export type AuthArgs = { mode: "register" | "login"; name: string; email: string; password: string; passwordConfirmation: string };

function AuthModal({ apiUp, eventTitle, full, onSubmit, onContinue, onClose }: {
  apiUp: boolean;
  eventTitle?: string;
  full?: boolean;
  onSubmit: (a: AuthArgs) => Promise<"ticket" | "complete">;
  onContinue: () => Promise<void>;
  onClose: () => void;
}) {
  const [mode, setMode] = useState<"register" | "login">("register");
  const [step, setStep] = useState<"account" | "ticket">("account");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [passwordConfirmation, setPasswordConfirmation] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    setError("");
    if (mode === "register" && (name.trim().length < 2 || name.trim().length > 80)) { setError("Укажите имя от 2 до 80 символов"); return; }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) || email.trim().length > 254) { setError("Укажите корректный email"); return; }
    if (apiUp && mode === "register" && password.length < 8) { setError("Пароль должен содержать не менее 8 символов"); return; }
    if (apiUp && mode === "register" && new TextEncoder().encode(password).length > 72) { setError("Пароль слишком длинный"); return; }
    if (apiUp && mode === "register" && password !== passwordConfirmation) { setError("Пароли не совпадают"); return; }
    if (apiUp && mode === "login" && !password) { setError("Введите пароль"); return; }
    setBusy(true);
    try {
      const result = await onSubmit({ mode, name: name.trim(), email: email.trim().toLowerCase(), password, passwordConfirmation });
      if (result === "ticket") setStep("ticket");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось войти. Попробуйте ещё раз.");
    } finally {
      setBusy(false);
    }
  };
  const continueToTicket = async () => {
    setError("");
    setBusy(true);
    try {
      await onContinue();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Не удалось оформить билет. Попробуйте ещё раз.");
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="modal-scrim" onClick={() => { if (!busy) onClose(); }}>
      <div className="modal-card auth-modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="auth-title">
        <button className="auth-close" type="button" onClick={onClose} disabled={busy} aria-label="Закрыть"><X /></button>
        <div className="auth-kicker"><span><Ticket /></span> EVENTLY PASS <i /> {step === "ticket" ? "02 / 02" : eventTitle ? "01 / 02" : "АККАУНТ"}</div>
        {eventTitle && <div className="auth-event"><small>ВАШЕ СОБЫТИЕ</small><strong>{eventTitle}</strong></div>}
        {step === "ticket" ? (
          <>
            <h2 id="auth-title">Вы в Evently.<br />Остался билет.</h2>
            <p>{full ? "Места закончились. Добавим вас в лист ожидания и сообщим, когда освободится место." : "Подключите Phantom в сети Solana Devnet. Кошелёк подпишет выпуск вашего именного билета."}</p>
            {!full && <div className="auth-wallet-note"><WalletCards /><span>Понадобится немного тестового SOL для комиссии сети. Реальные деньги не списываются.</span></div>}
            {error && <p className="msg-err" role="alert">{error}</p>}
            <div className="auth-actions"><button className="primary" type="button" disabled={busy} onClick={continueToTicket}>{busy ? "Подождите…" : full ? "Встать в лист ожидания" : "Продолжить с Phantom"}<ArrowRight /></button><button className="auth-later" type="button" onClick={onClose}>Сделаю это позже</button></div>
          </>
        ) : (
          <>
            <h2 id="auth-title">{!apiUp ? eventTitle ? "Демо-билет" : "Демо-профиль" : mode === "register" ? "Сначала знакомство." : "С возвращением."}</h2>
            <p>{!apiUp ? eventTitle ? "Сейчас сервер недоступен. Демо-билет сохранится только в этом браузере." : "Сейчас сервер недоступен. Профиль сохранится только в этом браузере." : mode === "register" ? "Создайте аккаунт, чтобы сохранить свои события и получить именной билет." : "Войдите, чтобы продолжить оформление билета."}</p>
            {apiUp && <div className="auth-tabs" role="group" aria-label="Режим"><button type="button" className={mode === "register" ? "active" : ""} onClick={() => { setMode("register"); setError(""); }}>Создать аккаунт</button><button type="button" className={mode === "login" ? "active" : ""} onClick={() => { setMode("login"); setError(""); }}>Уже есть аккаунт</button></div>}
            <form onSubmit={(e) => { e.preventDefault(); void submit(); }} noValidate>
              {mode === "register" && <label>Ваше имя<input value={name} onChange={(e) => { setName(e.target.value); setError(""); }} placeholder="Как к вам обращаться" autoComplete="name" maxLength={80} autoFocus /></label>}
              <label>Email<input type="email" value={email} onChange={(e) => { setEmail(e.target.value); setError(""); }} placeholder="you@example.com" inputMode="email" autoComplete="email" maxLength={254} /></label>
              {apiUp && <label>Пароль<span className="auth-password"><input type={showPassword ? "text" : "password"} value={password} onChange={(e) => { setPassword(e.target.value); setError(""); }} placeholder={mode === "register" ? "От 8 символов" : "Ваш пароль"} autoComplete={mode === "register" ? "new-password" : "current-password"} /><button type="button" onClick={() => setShowPassword((value) => !value)} aria-label={showPassword ? "Скрыть пароль" : "Показать пароль"}><Eye /> {showPassword ? "Скрыть" : "Показать"}</button></span></label>}
              {apiUp && mode === "register" && <label>Повторите пароль<input type={showPassword ? "text" : "password"} value={passwordConfirmation} onChange={(e) => { setPasswordConfirmation(e.target.value); setError(""); }} placeholder="Тот же пароль ещё раз" autoComplete="new-password" /></label>}
              {error && <p className="msg-err" role="alert">{error}</p>}
              <button className="primary auth-submit" type="submit" disabled={busy}>{busy ? "Подождите…" : !apiUp ? eventTitle ? "Сохранить демо-билет" : "Сохранить профиль" : mode === "register" ? "Создать аккаунт" : "Войти"}<ArrowRight /></button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}

export default function Home() {
  // Первый рендер — всегда defaults, как на сервере. localStorage подхватываем
  // эффектом после монтирования, иначе гидрация падает (React error #418).
  const [persisted, setPersisted] = useState<Persisted>(defaults);
  const [hydrated, setHydrated] = useState(false);
  const [view, setView] = useState<View>("discover");
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState(1);
  const [menuOpen, setMenuOpen] = useState(false);
  const [message, setMessage] = useState("");
  const [pendingId, setPendingId] = useState<number | null>(null);
  // Серверный слой: apiUp — доступен ли API; при недоступности — локальный fallback.
  const [apiUp, setApiUp] = useState(false);
  const [serverUser, setServerUser] = useState<ApiUser | null>(null);
  const [walletAddress, setWalletAddress] = useState<string | null>(null);
  const [serverEvents, setServerEvents] = useState<ServerEvent[]>([]);
  const [serverRegs, setServerRegs] = useState<Record<string, Reg>>({});
  const [serverWaitlist, setServerWaitlist] = useState<Record<string, WaitEntry>>({});
  const [serverFavs, setServerFavs] = useState<number[]>([]);
  const [overview, setOverview] = useState<{ events: number; users: number; registrations: number; visits: number } | null>(null);

  const { role: localRole, favorites: localFavs, regs: localRegs, extra, statusOv, waitlist: localWaitlist } = persisted;
  const online = apiUp;
  const role = (serverUser?.role ?? localRole) as Role;
  const regs = serverUser ? serverRegs : localRegs;
  const waitlist = serverUser ? serverWaitlist : localWaitlist;
  const favorites = serverUser ? serverFavs : localFavs;

  useEffect(() => {
    // Клиентские данные подхватываем после монтирования, иначе SSR-разметка
    // не совпадёт с клиентской (React error #418). Синхронизация разовая.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPersisted(loadPersisted());
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    try {
      window.localStorage.setItem("evently-v1", JSON.stringify(persisted));
    } catch { /* ignore */ }
  }, [persisted, hydrated]);

  useEffect(() => {
    if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => undefined);
  }, []);

  // Bootstrap API: health → каталог → сессия → билеты/избранное.
  useEffect(() => {
    let cancelled = false;
    health().then(async (ok) => {
      if (cancelled || !ok) return;
      setApiUp(true);
      try {
        setServerEvents(await Events.list());
      } catch {
        if (!cancelled) setApiUp(false);
        return;
      }
      if (!loadTokens()) return;
      try {
        const me = await Auth.me();
        if (cancelled) return;
        setServerUser(me);
        setWalletAddress(me.wallet_address ?? null);
        const [tickets, favs, queued] = await Promise.all([Events.myTickets(), Events.myFavorites(), Events.myWaitlist()]);
        if (cancelled) return;
        const sr: Record<string, Reg> = {};
        tickets.forEach((t) => {
          sr[String(t.event_id)] = serverTicketToReg(t);
        });
        setServerRegs(sr);
        setServerFavs(favs);
        setServerWaitlist(Object.fromEntries(queued.map((entry) => [String(entry.event_id), { regId: entry.registration_id, position: entry.position }])));
        if (me.role === "admin") {
          try {
            setOverview(await Events.overview());
          } catch { /* ignore */ }
        }
      } catch {
        clearTokens();
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const refreshServerEvents = async () => {
    try {
      setServerEvents(await Events.list());
    } catch {
      setApiUp(false);
    }
  };

  const events = useMemo(() => {
    if (online) {
      // Онлайн: каталог сервера + локальные черновики (id Date.now — не пересекаются).
      const mapped = serverEvents.map(mapServerEvent);
      return [...mapped, ...extra];
    }
    const seeded: EventItem[] = seedEvents.map((s) => ({ ...s, ...dateFor(s.dayOffset, s.time) }));
    const all = [...seeded, ...extra];
    return all.map((e) => ({ ...e, status: (statusOv[String(e.id)] as EventItem["status"]) ?? e.status }));
  }, [extra, statusOv, online, serverEvents]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return events.filter((e) => {
      if (role === "visitor" && e.status !== "published") return false;
      if (!q) return true;
      return `${e.title} ${e.company} ${e.city} ${e.category}`.toLowerCase().includes(q);
    });
  }, [events, query, role]);

  // Visitor никогда не видит скрытое событие в деталке: fallback только из visible (SPEC §10, правило 5).
  const selected =
    role === "visitor"
      ? visible.find((e) => e.id === selectedId) ?? visible[0]
      : events.find((e) => e.id === selectedId) ?? visible[0] ?? events[0];
  const pendingEvent = pendingId === null || pendingId === 0 ? undefined : events.find((item) => item.id === pendingId);

  const patch = (p: Partial<Persisted>) => setPersisted((s) => ({ ...s, ...p }));

  const doRegisterLocal = (id: number) => {
    const key = String(id);
    const event = events.find((e) => e.id === id);
    if (!event) return;
    if (localRegs[key] || occupied(event, localRegs, false) >= event.capacity || event.past) return;
    patch({ regs: { ...localRegs, [key]: { code: genCode(id), used: false } } });
    setView("tickets");
  };

  const joinWaitlistLocal = (id: number) => {
    const key = String(id);
    const event = events.find((e) => e.id === id);
    if (!event || localRegs[key] || localWaitlist[key] || event.past) return;
    if (occupied(event, localRegs, false) < event.capacity) return;
    patch({ waitlist: { ...localWaitlist, [key]: { position: 1, joinedAt: new Date().toISOString() } } });
  };

  const registerOnline = async (id: number) => {
    let address = walletAddress;
    if (!address) {
      address = await connectAndVerifyWallet();
      setWalletAddress(address);
    }
    const t = await Events.register(id);
    setServerRegs((s) => ({ ...s, [String(id)]: serverTicketToReg(t) }));
    const chain = await mintNonTransferableTicket(id, t.registration_id, address);
    const confirmed = await Events.confirmBlockchain(t.id, chain.signature, chain.tokenAddress);
    setServerRegs((s) => ({ ...s, [String(id)]: serverTicketToReg(confirmed) }));
    await refreshServerEvents();
    setView("tickets");
  };

  const connectWallet = async () => {
    if (!online || !serverUser) {
      setMessage("Сначала войдите в аккаунт Evently");
      return;
    }
    try {
      const address = await connectAndVerifyWallet();
      setWalletAddress(address);
      setServerUser((user) => user ? { ...user, wallet_address: address, wallet_verified_at: new Date().toISOString() } : user);
      setMessage("Phantom подключён и подтверждён");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Не удалось подключить Phantom");
    }
  };

  const joinWaitlistOnline = async (id: number) => {
    const queued = await Events.joinWaitlist(id);
    setServerWaitlist((items) => ({ ...items, [String(id)]: { regId: queued.registration_id, position: queued.position } }));
  };

  const register = async (id: number) => {
    if (regs[String(id)]) { setView("tickets"); return; }
    if (waitlist[String(id)]) return;
    const event = events.find((item) => item.id === id);
    if (!event || event.past) return;
    if (online && serverUser) {
      try {
        if (occupied(event, regs, true) >= event.capacity) await joinWaitlistOnline(id);
        else await registerOnline(id);
      } catch (error) {
        setMessage(error instanceof Error ? error.message : "Не удалось зарегистрироваться");
      }
      return;
    }
    // Офлайн без профиля или онлайн без входа — через форму входа.
    if (online || !persisted.profile) { setPendingId(id); return; }
    if (occupied(event, localRegs, false) >= event.capacity) joinWaitlistLocal(id);
    else doRegisterLocal(id);
  };

  const submitAuth = async ({ mode, name, email, password, passwordConfirmation }: AuthArgs): Promise<"ticket" | "complete"> => {
    if (!online) {
      // Офлайн: локальный именной профиль.
      const profile = { name, email };
      if (pendingId !== null) {
        const id = pendingId;
        const key = String(id);
        const event = events.find((e) => e.id === id);
        setPendingId(null);
        if (event && !localRegs[key] && !event.past) {
          if (occupied(event, localRegs, false) >= event.capacity) {
            patch({ profile, waitlist: { ...localWaitlist, [key]: { position: 1, joinedAt: new Date().toISOString() } } });
          } else {
            patch({ profile, regs: { ...localRegs, [key]: { code: genCode(id), used: false } } });
            setView("tickets");
          }
          return "complete";
        }
      }
      patch({ profile });
      return "complete";
    }
    const t = mode === "login" ? await Auth.login(email, password) : await Auth.register(name, email, password, passwordConfirmation);
    setServerUser(t.user);
    setWalletAddress(t.user.wallet_address ?? null);
    const [tickets, favs, queued] = await Promise.allSettled([Events.myTickets(), Events.myFavorites(), Events.myWaitlist()]);
    const sr: Record<string, Reg> = {};
    if (tickets.status === "fulfilled") tickets.value.forEach((x) => { sr[String(x.event_id)] = serverTicketToReg(x); });
    setServerRegs(sr);
    setServerFavs(favs.status === "fulfilled" ? favs.value : []);
    setServerWaitlist(queued.status === "fulfilled" ? Object.fromEntries(queued.value.map((entry) => [String(entry.event_id), { regId: entry.registration_id, position: entry.position }])) : {});
    await refreshServerEvents();
    if (t.user.role === "admin") {
      try {
        setOverview(await Events.overview());
      } catch { /* ignore */ }
    }
    if (pendingId !== null && pendingId !== 0) return "ticket";
    setPendingId(null);
    setView("cabinet");
    return "complete";
  };

  const continueRegistration = async () => {
    const id = pendingId;
    if (id === null || id === 0) return;
    const event = events.find((item) => item.id === id);
    if (!event) throw new Error("Событие больше не доступно. Обновите страницу.");
    if (serverRegs[String(id)]) {
      setPendingId(null);
      setView("tickets");
      return;
    }
    if (serverWaitlist[String(id)]) {
      setPendingId(null);
      return;
    }
    if (occupied(event, serverRegs, true) >= event.capacity) await joinWaitlistOnline(id);
    else await registerOnline(id);
    setPendingId(null);
  };

  const logout = () => {
    clearTokens();
    setServerUser(null);
    setWalletAddress(null);
    setServerRegs({});
    setServerWaitlist({});
    setServerFavs([]);
    setOverview(null);
    setView("discover");
  };

  const toggleFav = async (id: number) => {
    if (online && serverUser) {
      try {
        if (serverFavs.includes(id)) {
          await Events.removeFavorite(id);
          setServerFavs((f) => f.filter((x) => x !== id));
        } else {
          await Events.addFavorite(id);
          setServerFavs((f) => [...f, id]);
        }
      } catch { /* ignore */ }
      return;
    }
    patch({ favorites: localFavs.includes(id) ? localFavs.filter((f) => f !== id) : [...localFavs, id] });
  };

  const toggleStatus = async (id: number) => {
    if (online && serverUser) {
      const current = events.find((e) => e.id === id)?.status ?? "published";
      try {
        await Events.patch(id, { status: current === "published" ? "hidden" : "published" });
        await refreshServerEvents();
      } catch { /* ignore */ }
      return;
    }
    const key = String(id);
    const current = events.find((e) => e.id === id)?.status ?? "published";
    patch({ statusOv: { ...statusOv, [key]: current === "published" ? "hidden" : "published" } });
  };

  // Единый check-in: код, ручной список и сканер пишут в один журнал (SPEC.md §10).
  const checkIn = async (raw: string) => {
    const input = raw.trim();
    if (!input) { setMessage("Введите код билета или выберите гостя"); return; }
    if (online && serverUser) {
      try {
        let address = walletAddress;
        if (!address) {
          address = await connectAndVerifyWallet();
          setWalletAddress(address);
        }
        const prepared = await Events.prepareCheckIn(input);
        const proof = await createCheckInProof(prepared.memo, address);
        const checked = await Events.checkIn(input, proof);
        const code = input.toUpperCase();
        setServerRegs((s) => {
          const key = Object.keys(s).find((k) => s[k].code === code);
          return key ? { ...s, [key]: { ...s[key], used: true, blockchainStatus: "used" } } : s;
        });
        patch({ log: [...persisted.log, { label: code, result: "ok", at: new Date().toISOString() }] });
        setMessage(`Проход разрешён · check-in записан в Solana: ${shortWallet(checked.check_in_signature)}`);
      } catch (e) {
        const status = e instanceof ApiError ? e.status : 0;
        if (status === 409) {
          patch({ log: [...persisted.log, { label: input.toUpperCase(), result: "duplicate", at: new Date().toISOString() }] });
          setMessage("Уже отмечен — повторный проход запрещён");
        } else if (status === 404) {
          setMessage("Билет не найден");
        } else if (status === 403) {
          setMessage("Чужое событие");
        } else {
          setMessage("API недоступно — проверьте соединение");
        }
      }
      return;
    }
    const entry = Object.entries(localRegs).find(([, r]) => r.code === input.toUpperCase());
    if (!entry && /^EVT-/i.test(input)) { setMessage("Билет не найден"); return; }
    const label = entry ? entry[1].code : input;
    if (persisted.log.some((l) => l.label === label && l.result === "ok")) {
      patch({ log: [...persisted.log, { label, result: "duplicate", at: new Date().toISOString() }] });
      setMessage("Уже отмечен — повторный проход запрещён");
      return;
    }
    const nextRegs = { ...localRegs };
    if (entry) nextRegs[entry[0]] = { ...entry[1], used: true };
    patch({
      regs: nextRegs,
      log: [...persisted.log, { label, result: "ok", at: new Date().toISOString() }],
    });
    setMessage("Проход разрешён");
  };

  const importGuests = (list: GuestRow[]) => {
    const known = new Set([...persisted.guests, ...seededGuests].map((g) => g.email.toLowerCase()));
    const fresh = list.filter((g) => !known.has(g.email.toLowerCase()));
    if (fresh.length > 0) patch({ guests: [...persisted.guests, ...fresh] });
  };
  // Отмена регистрации: место освобождается, билет инвалидируется (SPEC.md §10, правило 2).
  const cancelReg = async (id: number) => {
    const key = String(id);
    if (online && serverUser) {
      const r = serverRegs[key];
      if (!r || r.used || r.regId === undefined) return;
      try {
        await Events.cancelRegistration(r.regId);
        setServerRegs((s) => {
          const next = { ...s };
          delete next[key];
          return next;
        });
        await refreshServerEvents();
      } catch { /* ignore */ }
      return;
    }
    if (!localRegs[key] || localRegs[key].used) return;
    const next = { ...localRegs };
    delete next[key];
    patch({ regs: next });
  };

  const leaveWaitlist = async (id: number) => {
    const key = String(id);
    if (online && serverUser) {
      const entry = serverWaitlist[key];
      if (!entry?.regId) return;
      try {
        await Events.cancelRegistration(entry.regId);
        setServerWaitlist((items) => {
          const next = { ...items };
          delete next[key];
          return next;
        });
      } catch { /* ignore */ }
      return;
    }
    if (!localWaitlist[key]) return;
    const next = { ...localWaitlist };
    delete next[key];
    patch({ waitlist: next });
  };

  const createEvent = async (e: EventItem) => {
    if (online && serverUser && (serverUser.role === "organizer" || serverUser.role === "admin")) {
      try {
        const cats = await Categories.list();
        const cat = cats.find((c) => c.title === e.category);
        await Events.create({
          title: e.title,
          city: e.city,
          place: e.place,
          starts_at: e.date,
          capacity: e.capacity,
          category_id: cat?.id ?? null,
          cover_url: e.image,
        });
        await refreshServerEvents();
        setView("events");
        return;
      } catch { /* ignore */ }
    }
    patch({ extra: [...extra, e] });
    setSelectedId(e.id);
    setView("events");
  };

  const displayProfile: Profile | null = serverUser
    ? { name: serverUser.name, email: serverUser.email }
    : persisted.profile;

  const registrationToolRef = useRef(register);
  useEffect(() => {
    registrationToolRef.current = register;
  });
  useEffect(() => {
    const context = document.modelContext;
    if (!context?.registerTool) return;
    const lifecycle = new AbortController();
    const add = (tool: WebMcpTool) => {
      void Promise.resolve(context.registerTool(tool, { signal: lifecycle.signal })).catch(() => undefined);
    };
    add({
      name: "list_evently_events",
      title: "List Evently events",
      description: "Read the events currently shown in the Evently catalog, including seat availability.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
      annotations: { readOnlyHint: true, untrustedContentHint: false },
      execute: () => events.map((event) => ({ id: event.id, title: event.title, city: event.city, date: event.date, category: event.category, occupied: occupied(event, regs, online), capacity: event.capacity })),
    });
    add({
      name: "start_evently_registration",
      title: "Start Evently registration",
      description: "Open or complete the visible registration flow for an Evently event. Full events use the waitlist automatically.",
      inputSchema: { type: "object", properties: { eventId: { type: "number" } }, required: ["eventId"], additionalProperties: false },
      annotations: { readOnlyHint: false, untrustedContentHint: false },
      execute: async (input) => {
        const id = typeof input === "object" && input !== null && "eventId" in input ? Number((input as { eventId: unknown }).eventId) : NaN;
        const event = events.find((item) => item.id === id);
        if (!event) throw new Error("Unknown eventId");
        setSelectedId(id);
        setView("discover");
        await registrationToolRef.current(id);
        return { status: "started", eventId: id, full: occupied(event, regs, online) >= event.capacity };
      },
    });
    return () => lifecycle.abort();
  }, [events, online, regs]);

  return (
    <main className="app-shell">
      <Sidebar view={view} setView={setView} open={menuOpen} close={() => setMenuOpen(false)} role={role} setRole={(r) => patch({ role: r })} ticketCount={Object.keys(regs).length} loggedIn={serverUser !== null} />
      {menuOpen && <button className="scrim" onClick={() => setMenuOpen(false)} aria-label="Закрыть меню" />}
      <div className="main-shell">
        <Topbar onMenu={() => setMenuOpen(true)} query={query} setQuery={setQuery} role={role} profile={displayProfile} apiUp={online} walletAddress={walletAddress} onConnectWallet={connectWallet} loggedIn={serverUser !== null} onAccount={() => serverUser ? setView("cabinet") : setPendingId(0)} />
        {pendingId !== null && <AuthModal apiUp={online} eventTitle={pendingEvent?.title} full={pendingEvent ? occupied(pendingEvent, regs, online) >= pendingEvent.capacity : false} onSubmit={submitAuth} onContinue={continueRegistration} onClose={() => setPendingId(null)} />}
        {message && view !== "checkin" && <div className="app-notice" role="status"><span>{message}</span><button onClick={() => setMessage("")} aria-label="Закрыть уведомление"><X /></button></div>}
        {view === "discover" && selected && (
          <Discover list={visible} selected={selected} setSelected={(e) => setSelectedId(e.id)} regs={regs} register={register} favorites={favorites} toggleFav={toggleFav} online={online} waitlist={waitlist} leaveWaitlist={leaveWaitlist} />
        )}
        {view === "tickets" && <TicketView regs={regs} events={events} profile={displayProfile} onCancel={cancelReg} />}
        {view === "cabinet" && <CabinetView regs={regs} events={events} favorites={favorites} toggleFav={toggleFav} go={setView} profile={displayProfile} onSaveProfile={(name, email) => patch({ profile: { name, email } })} server={serverUser !== null} onLogout={logout} />}
        {view === "create" && <CreateView onCreate={createEvent} />}
        {view === "studio" && <Studio />}
        {view === "events" && <EventsView events={events} regs={regs} online={online} go={setView} toggleStatus={toggleStatus} />}
        {view === "guests" && <GuestsView profile={displayProfile} guests={persisted.guests} onImport={importGuests} />}
        {view === "checkin" && <CheckinView regs={regs} events={events} log={persisted.log} profile={displayProfile} checkIn={checkIn} message={message} />}
        {view === "analytics" && <AnalyticsView events={events} regs={regs} />}
        {view === "admin" && <AdminView events={events} regs={regs} online={online} log={persisted.log} overview={overview} toggleStatus={toggleStatus} />}
      </div>
    </main>
  );
}
