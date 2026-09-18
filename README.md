# Evently

Evently is a multi-organization event platform for publishing events, managing guests, creating personalized invitations, issuing QR tickets, handling check-in, and reviewing attendance analytics.

## Current demo

- Public event catalog with filters and capacity indicators
- Organization dashboard and event management
- Invitation editor with templates, editable typography, dynamic fields, and color controls
- Mobile, PDF, and PNG ticket flows
- Guest directory with search and CSV-oriented actions
- Interactive check-in list and QR scanner concept
- Registration funnel and attendance analytics
- Responsive PWA shell for desktop and mobile

## Run locally

```bash
npm run install:ci
npm run dev
```

Open `http://localhost:5173`.

## Stack

Next.js-compatible Vinext runtime, React, TypeScript, Tailwind CSS, Lucide icons, and Cloudflare Sites. The product architecture is prepared for a shared TypeScript monorepo with an Expo app and a replaceable payment provider.

---

# Evently — Русский

Evently — мультиорганизационная платформа для публикации мероприятий, управления гостями, создания персональных приглашений, выпуска QR-билетов, check-in и аналитики посещаемости.

## Что работает в демо

- Каталог мероприятий с фильтрами и отображением свободных мест
- Панель организации и управление событиями
- Редактор приглашений с шаблонами, типографикой, динамическими полями и цветами
- Билеты для мобильного экрана, PDF и PNG
- Поиск по гостям и действия для CSV
- Интерактивный check-in и концепт QR-сканера
- Воронка регистрации и аналитика посещений
- Адаптивная PWA для компьютера и телефона

## Локальный запуск

```bash
npm run install:ci
npm run dev
```

Откройте `http://localhost:5173`.

Подробные границы продукта и дорожная карта находятся в [PRODUCT_SPEC.md](./PRODUCT_SPEC.md).
