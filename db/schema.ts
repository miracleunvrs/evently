import { sql } from "drizzle-orm";
import {
  index,
  integer,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";

// Роли: visitor | organizer | admin. Email — уникальный идентификатор входа,
// password_hash — задел под JWT backend (FastAPI), в PWA MVP auth демо-режима.
export const users = sqliteTable(
  "users",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    email: text("email").notNull(),
    name: text("name").notNull().default(""),
    role: text("role").notNull().default("visitor"),
    passwordHash: text("password_hash").notNull().default(""),
    createdAt: text("created_at")
      .notNull()
      .default(sql`CURRENT_TIMESTAMP`),
  },
  (t) => [uniqueIndex("users_email_unique").on(t.email), index("users_role_idx").on(t.role)]
);

export const categories = sqliteTable(
  "categories",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    slug: text("slug").notNull(),
    title: text("title").notNull(),
  },
  (t) => [
    uniqueIndex("categories_slug_unique").on(t.slug),
    uniqueIndex("categories_title_unique").on(t.title),
  ]
);

// Статус: draft | published | hidden. capacity — лимит мест, проверяется при регистрации.
export const events = sqliteTable(
  "events",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    organizerId: integer("organizer_id").notNull(),
    categoryId: integer("category_id"),
    title: text("title").notNull(),
    description: text("description").notNull().default(""),
    city: text("city").notNull().default(""),
    place: text("place").notNull().default(""),
    startsAt: text("starts_at").notNull().default(""),
    capacity: integer("capacity").notNull().default(100),
    // Цена в минимальных единицах валюты. 0 = бесплатно. Задел под комиссию 3–5%.
    price: integer("price").notNull().default(0),
    status: text("status").notNull().default("published"),
    coverUrl: text("cover_url").notNull().default(""),
    createdAt: text("created_at")
      .notNull()
      .default(sql`CURRENT_TIMESTAMP`),
  },
  (t) => [
    index("events_organizer_idx").on(t.organizerId),
    index("events_status_idx").on(t.status),
    index("events_starts_idx").on(t.startsAt),
    index("events_category_idx").on(t.categoryId),
  ]
);

export const eventImages = sqliteTable(
  "event_images",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    eventId: integer("event_id").notNull(),
    url: text("url").notNull(),
    sort: integer("sort").notNull().default(0),
  },
  (t) => [index("event_images_event_idx").on(t.eventId)]
);

// Одна пара (event, user) — одна регистрация. Повторная регистрация запрещена.
export const registrations = sqliteTable(
  "registrations",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    eventId: integer("event_id").notNull(),
    userId: integer("user_id").notNull(),
    status: text("status").notNull().default("confirmed"),
    createdAt: text("created_at")
      .notNull()
      .default(sql`CURRENT_TIMESTAMP`),
  },
  (t) => [
    uniqueIndex("registrations_event_user_unique").on(t.eventId, t.userId),
    index("registrations_event_idx").on(t.eventId),
    index("registrations_user_idx").on(t.userId),
    index("registrations_event_status_created_idx").on(t.eventId, t.status, t.createdAt),
  ]
);

// 1 регистрация = 1 билет. code — уникальный payload QR. status: active | used.
export const tickets = sqliteTable(
  "tickets",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    registrationId: integer("registration_id").notNull(),
    code: text("code").notNull(),
    status: text("status").notNull().default("active"),
    createdAt: text("created_at")
      .notNull()
      .default(sql`CURRENT_TIMESTAMP`),
  },
  (t) => [
    uniqueIndex("tickets_registration_unique").on(t.registrationId),
    uniqueIndex("tickets_code_unique").on(t.code),
    index("tickets_status_idx").on(t.status),
  ]
);

export const favorites = sqliteTable(
  "favorites",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    userId: integer("user_id").notNull(),
    eventId: integer("event_id").notNull(),
    createdAt: text("created_at")
      .notNull()
      .default(sql`CURRENT_TIMESTAMP`),
  },
  (t) => [
    uniqueIndex("favorites_user_event_unique").on(t.userId, t.eventId),
    index("favorites_user_idx").on(t.userId),
  ]
);

// История проходов: result ok | duplicate. Повторный скан пишется как duplicate,
// билет при этом остаётся used — защита от повторного прохода.
export const checkIns = sqliteTable(
  "check_ins",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    ticketId: integer("ticket_id").notNull(),
    eventId: integer("event_id").notNull(),
    checkedBy: integer("checked_by"),
    result: text("result").notNull().default("ok"),
    createdAt: text("created_at")
      .notNull()
      .default(sql`CURRENT_TIMESTAMP`),
  },
  (t) => [
    index("check_ins_ticket_idx").on(t.ticketId),
    index("check_ins_event_idx").on(t.eventId),
  ]
);
