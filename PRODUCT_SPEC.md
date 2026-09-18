# Evently product specification

## Product

Evently is an event aggregator and operating system for independent organizations. Each organization owns its employees, events, guests, brand settings, invitation templates, and analytics. Platform administrators approve organizations and moderate events published to the public catalog.

## Roles

- **Guest** — discovers events, registers, receives tickets, and manages personal data.
- **Organization Owner** — manages the company, branding, staff, and access.
- **Organizer** — creates events, invitations, forms, guest lists, and reports.
- **Check-in Staff** — scans tickets and searches guests without access to organization settings.
- **Platform Admin** — moderates organizations and public events.

## MVP journey

1. An organizer creates an event and configures its access, capacity, schedule, speakers, venue, and registration form.
2. Public events go through moderation; private events can be published by the organization.
3. Guests register or join a waitlist and receive a personalized invitation and signed QR ticket.
4. The ticket is available as a mobile page, PDF, and PNG.
5. Check-in staff scan the QR or find a guest manually. Duplicate entry is rejected.
6. The organizer reviews invitations, registrations, attendance, no-show rate, answers, and CSV exports.

## Invitation studio

The editor supports system templates, private organization templates, and copies of earlier invitations. MVP controls include text, images, logos, shapes, layers, colors, fonts, alignment, undo/redo, preset sizes, dynamic fields such as `{{guest_name}}`, and a personalized QR code.

## Event access and lifecycle

- Public catalog event
- Corporate-domain event
- Invite-only event

Lifecycle: `Draft → Moderation → Published → Completed`, with `Cancelled` and `Archived` states. Private events may move directly from draft to published.

## Platform direction

The first client is a responsive Next.js PWA. A later Expo React Native app should reuse TypeScript domain types, API client, access rules, and design tokens. Payment is represented by a provider interface so acquiring for CIS and Russia can be added without changing event, order, or ticket entities.

## Later releases

- Real payment provider integration
- Google, Microsoft, and corporate SSO
- Offline-first check-in synchronization
- Messenger delivery
- Apple Wallet and Google Wallet
- Real-time collaborative invitation editing
- Recurring event series
