# Evently Web3

Evently is an event platform with verifiable, non-transferable tickets on Solana Devnet. Organizers publish events and scan QR codes; guests sign in with email, prove ownership of a Phantom wallet, and receive a Token-2022 ticket linked to their registration.

Русская версия находится [ниже](#русская-версия).

## Why blockchain is used

Blockchain does not replace PostgreSQL. Event descriptions, users, capacity, waitlists, analytics and QR check-ins remain in the application database. Solana records the part that benefits from independent verification: issuance of a unique ticket, its mint address, owner wallet and transaction history.

Each ticket is a Token-2022 mint with a supply of one and the `NonTransferable` extension. The mint transaction contains an Evently memo with the event and registration IDs. Rails accepts the ticket only after it verifies the confirmed transaction, signer, memo, Token-2022 program owner, supply and owner token account through Solana JSON-RPC.

## Architecture

```text
React / Vinext PWA ─────── Ruby on Rails API ─────── PostgreSQL
       │                          │
       │ Phantom                  │ Solana JSON-RPC
       └──────────────────────────┴──────────────→ Solana Devnet
                                                     │
                                         Non-transferable Token-2022
```

- **React/Vinext** renders the catalog, wallet connection, tickets, QR scanner and organizer tools.
- **Phantom** owns the user key and signs challenges and mint transactions. Evently never receives a user private key.
- **Ruby on Rails** owns authentication, capacity, waitlists, registration, ticket verification and check-in rules.
- **PostgreSQL** stores normal product data and the Solana signature/mint references.
- **Solana Devnet** provides verifiable ticket issuance without real-money payments.

## Ticket flow

1. The user signs into Evently.
2. Phantom signs a short-lived server challenge. Rails verifies the Ed25519 signature and links the public wallet.
3. Rails atomically reserves capacity and creates a pending registration and QR ticket.
4. Phantom signs a transaction that creates a supply-one, non-transferable Token-2022 mint and embeds `evently:v1:<event_id>:<registration_id>` as a memo.
5. Rails verifies the confirmed Devnet transaction and marks the ticket `confirmed`.
6. The ticket page shows its QR code, wallet, mint and a Solana Explorer link.
7. At check-in, the organizer signs a ticket-specific memo transaction in Phantom. Rails verifies that receipt and the guest's on-chain ownership, then atomically changes the ticket from `active` to `used`. Duplicate entry is rejected and logged.

## Local setup

Requirements: Docker, Node.js `>=22.13`, Phantom Wallet configured for Devnet, and a small amount of Devnet SOL from a faucet for mint rent and fees.

```sh
cp .env.example .env
# replace JWT_SECRET in .env
docker compose up --build -d db api
npm install
npm run dev
```

- Web app: `http://localhost:5173`
- Rails API: `http://localhost:8000`
- API health: `http://localhost:8000/health`
- Solana RPC health: `http://localhost:8000/health/solana`
- PostgreSQL: `localhost:5544`
- Demo organizer: `orga@example.com` / `orga123`

The frontend uses `NEXT_PUBLIC_API_URL` and `NEXT_PUBLIC_SOLANA_RPC_URL`. Rails uses `DATABASE_URL`, `JWT_SECRET`, `CORS_ORIGINS` and `SOLANA_RPC_URL`. Production values belong in environment variables; no wallet private key is required.

## Verification

```sh
npm run lint
npm test
npm run build

cd backend
JWT_SECRET=test-secret RAILS_ENV=test bundle exec rails test
bundle exec rubocop
```

The Rails tests cover Phantom-compatible Ed25519 verification and the Solana ticket verifier. Frontend tests cover ticket capacity, cancellation and duplicate check-in rules.

## Main folders

- `app/` — Evently interface and PWA screens
- `lib/api.ts` — Rails API client
- `lib/web3.ts` — Phantom and Token-2022 transaction code
- `backend/` — Rails API, PostgreSQL migrations and Solana services
- `backend/app/services/solana/` — JSON-RPC client and ticket verification
- `db/`, `drizzle/` — the original local/D1 schema retained for offline compatibility
- `SPEC.md` — product and business rules

## MVP boundaries

The MVP uses free tickets and Solana Devnet. It does not include crypto payments, a marketplace, a fungible token, DAO mechanics or DeFi features.

## Русская версия

Evently — платформа мероприятий с проверяемыми непередаваемыми билетами в Solana Devnet. Организатор создаёт событие и проверяет QR на входе, а гость входит по email, подтверждает Phantom-кошелёк и получает Token-2022 билет.

### Зачем здесь блокчейн

PostgreSQL остаётся основной базой продукта. В ней хранятся пользователи, события, вместимость, очередь, аналитика и check-in. В Solana записывается только проверяемая часть билета: выпуск уникального токена, адрес mint, кошелёк владельца и история транзакции.

Каждый билет имеет supply `1` и расширение `NonTransferable`. В транзакции находится memo с ID события и регистрации. Rails подтверждает билет только после проверки транзакции, подписавшего кошелька, memo, программы Token-2022, supply и token account владельца через официальный Solana JSON-RPC.

### Запуск

Нужны Docker, Node.js `>=22.13`, Phantom в сети Devnet и немного тестовых Devnet SOL для комиссии и rent.

```sh
cp .env.example .env
# замените JWT_SECRET в .env
docker compose up --build -d db api
npm install
npm run dev
```

После входа нажмите **Connect Phantom**, подтвердите подпись сообщения и выберите событие. Phantom покажет транзакцию выпуска билета. После подтверждения на странице билета появятся `Solana Verified`, адрес токена и ссылка на Solana Explorer. При check-in кошелёк организатора подписывает отдельную memo-транзакцию, поэтому факт использования также получает проверяемую запись в Devnet.

Приватный ключ Phantom никогда не отправляется в Evently. Пользователь подписывает challenge и blockchain-транзакцию внутри кошелька.
