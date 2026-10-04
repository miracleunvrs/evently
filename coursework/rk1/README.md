# Evently — практические работы до РК1

Курс «ИТ-стартап Итоговый проект 1 (DS/ML стартап)», AlmaU, 2026.
Объём: недели 1–7 и прототип недели 8. Основа — существующий Evently.

## Состав

| Неделя | Реализация |
|---|---|
| 1 | Учебный кошелёк и SOL transfer — `scripts/wallet.mjs`, `client/run.mjs` |
| 2 | Transaction Detective — `client/analyze.mjs`, JSON с accounts/instructions/programs |
| 3 | Rust CLI — `cli/src/main.rs`, тесты capacity и single-use |
| 4 | Native Solana Program — `programs/hello_evently` |
| 5 | Anchor Counter — `programs/evently_lab`, TypeScript-compatible JS client |
| 6 | On-chain Profile PDA — тот же Anchor-модуль и проверки authority |
| 7 | Token-2022, metadata, mint и transfer — `client/run.mjs` |
| 8 | Web3 MVP — основной Evently и `client/mvp.mjs` |

`localnet` — настоящий локальный валидатор, но не публичная Devnet.
Файл `evidence/devnet-run.json` считается доказательством Devnet только после успешного запуска.
JSON содержит реальные signatures и slot, а не заранее заданные результаты.

## Инструменты

Rust stable, Agave/Solana CLI 2.3.0, Anchor CLI 0.32.1, platform-tools v1.51, Node.js >=22.13.
Официальные инструкции: https://solana.com/docs/intro/installation
и https://www.anchor-lang.com/docs/updates/release-notes/0-32-1.
Используется совместимая зафиксированная версия Anchor; `Cargo.lock` и `package-lock.json` сохраняют зависимости.

## Воспроизведение

Из корня репозитория:

```sh
npm ci
npm ci --prefix coursework/rk1
node coursework/rk1/scripts/wallet.mjs
node coursework/rk1/scripts/sync-program-id.mjs
cargo test --manifest-path coursework/rk1/Cargo.toml -p evently-cli
cargo run --manifest-path coursework/rk1/Cargo.toml -p evently-cli -- demo 2
cd coursework/rk1
anchor build -p evently_lab --no-idl -- --tools-version v1.51
mkdir -p target/idl
anchor idl build -p evently_lab -o target/idl/evently_lab.json
cargo build-sbf --manifest-path programs/hello_evently/Cargo.toml --sbf-out-dir target/deploy --tools-version v1.51
```

В отдельном терминале:

```sh
solana-test-validator --ledger .local-ledger --bind-address 127.0.0.1 --rpc-port 8899
```

Затем:

```sh
solana --url http://127.0.0.1:8899 --keypair .secrets/payer.json airdrop 100
solana --url http://127.0.0.1:8899 --keypair .secrets/recipient.json airdrop 2
bash scripts/deploy.sh localnet
node client/run.mjs localnet
node client/analyze.mjs localnet
node client/detective.mjs
```

Для Devnet получите тестовый SOL на адрес из `evidence/wallet.json`, выполните
`bash scripts/deploy.sh devnet`, `node client/run.mjs devnet` и `node client/analyze.mjs devnet`.
Использование Mainnet запрещено настройками клиентов. Покупать SOL не требуется.

`client/detective.mjs` читает успешную стороннюю транзакцию Devnet. Это отдельный
пример для разбора, а не доказательство отправки транзакции учебным кошельком.
Можно передать signature первым аргументом для повторного разбора конкретного примера.

## Проверка полного MVP без изменения основной базы

После запуска локального валидатора и пополнения обоих учебных кошельков из корня репозитория:

```sh
docker compose up -d db
docker compose run --detach --name evently-rk1-api --no-deps \
  -p 127.0.0.1:8001:8000 \
  -e DATABASE_URL=postgresql://evently:evently@db:5432/evently_rk1 \
  -e SOLANA_RPC_URL=http://host.docker.internal:8899 \
  -e CORS_ORIGINS=http://127.0.0.1:8787 api
# Дождитесь ответа 200 от http://127.0.0.1:8001/health
node coursework/rk1/client/mvp.mjs
```

Используется отдельная PostgreSQL-база `evently_rk1` и API на порту 8001.
Сценарий сам создаёт учебные аккаунты, проверяет подпись кошелька, выпуск настоящего
Token-2022 и check-in. Пароли сохраняются только в `.secrets/mvp-accounts.json`.
Для Linux Docker может потребоваться `--add-host=host.docker.internal:host-gateway`
и доступный контейнеру bind-address валидатора. Проверенная среда — Docker Desktop на macOS.
Повторный запуск: `docker start evently-rk1-api`, затем клиент. Остановка: `docker stop evently-rk1-api`.

## Ключи и переносимость

`.secrets/` содержит только отдельно созданные учебные ключи и исключён из Git и архива сдачи.
Приватные ключи Phantom и ключи пользовательских аккаунтов не используются.
При создании новых ключей у проверяющего изменится Program ID. Команда
`node scripts/sync-program-id.mjs` обновляет `declare_id!` и `Anchor.toml` на адрес
`evently_lab.json`; затем пересоберите программу и IDL. Исходный ID в отчёте относится к приложенным доказательствам.
Не публикуйте seed phrase или keypair JSON. В сдачу включены только публичные адреса и результаты.

## Ограничения учебного токена

ELAB — отдельный передаваемый учебный Token-2022. Это не билет и не платёжное средство.
Билеты основного Evently сохраняют `NonTransferable`, supply 1 и отозванное право дополнительной эмиссии.
Профиль PDA хранит только публичные имя и описание; email и пароль остаются в Rails/PostgreSQL.
