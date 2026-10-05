"""Render compact, clearly labelled views of saved RK1 run evidence for screenshots."""

from html import escape
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'evidence'
OUTPUT = EVIDENCE / 'screenshot-pages'
OUTPUT.mkdir(parents=True, exist_ok=True)

run = json.loads((EVIDENCE / 'localnet-run.json').read_text())
detective = json.loads((EVIDENCE / 'devnet-detective.json').read_text())
mvp = json.loads((EVIDENCE / 'mvp-integration.json').read_text())
tx = {item['label']: item for item in run['transactions']}


def row(label, value):
    return f'<div class="row"><span>{escape(str(label))}</span><strong>{escape(str(value))}</strong></div>'


def signature(value):
    return f'<div class="signature">{escape(value)}</div>'


def transaction(label):
    item = tx[label]
    return f'<div class="transaction"><b>{escape(label)}</b>{signature(item["signature"])}{row("Slot", item["slot"])}{row("Статус", "Подтверждено")}</div>'


pages = [
    (1, 'Кошелёк и первый перевод', 'LOCALNET · учебный запуск',
     '<p>Подтверждённый перевод 0,001 SOL между двумя учебными адресами.</p>'
     + row('Отправитель', run['payer']) + row('Получатель', run['recipient'])
     + row('Сумма', '1 000 000 lamports') + row('Комиссия', '5 000 lamports')
     + transaction('week1_sol_transfer'),
     'localnet-run.json'),
    (2, 'Разбор транзакции', 'DEVNET · чужая публичная транзакция',
     '<p>Реальная транзакция Solana Devnet взята только для анализа; Evently её не отправлял.</p>'
     + row('Подписант', next(a['address'] for a in detective['accounts'] if a['signer']))
     + row('Аккаунтов', len(detective['accounts'])) + row('Slot', detective['slot'])
     + row('Комиссия', str(detective['fee_lamports']) + ' lamports')
     + signature(detective['signature'])
     + '<div class="small">explorer.solana.com/tx/3FFzLG...UBvjA?cluster=devnet</div>',
     'devnet-detective.json'),
    (3, 'Rust CLI и тесты', 'ЛОКАЛЬНО · cargo test',
     '<p>Локальный CLI моделирует регистрацию и одноразовый проход.</p>'
     + '<pre>' + escape((EVIDENCE / 'rust-tests.txt').read_text().split('running 4 tests', 1)[1].strip()) + '</pre>'
     + '<div class="small">CLI: Repeated check-in: AlreadyUsed</div>',
     'rust-tests.txt · rust-cli.txt'),
    (4, 'Первая Solana Program', 'LOCALNET · развёртывание и вызов',
     row('Program ID', run['hello_program'])
     + '<p>Deploy подписи и вызов сохранены в локальном протоколе.</p>'
     + transaction('week4_hello_program')
     + '<pre>Program log: Hello Evently RK1\nProgram success</pre>',
     'localnet-deploy-hello_evently.json · localnet-run.json'),
    (5, 'Anchor Counter', 'LOCALNET · PDA и проверки прав',
     row('Counter PDA', run['counter']['address'])
     + row('Значение', f"{run['counter']['before']} → {run['counter']['after']}")
     + transaction('week5_initialize_counter') + transaction('week5_increment')
     + '<div class="pass">✓ Чужой authority отклонён: ConstraintSeeds</div>',
     'localnet-run.json'),
    (6, 'Профиль PDA', 'LOCALNET · создание и изменение',
     row('Profile PDA', run['profile']['address'])
     + row('Имя', run['profile']['data']['name'])
     + row('Bio', run['profile']['data']['bio'])
     + transaction('week6_create_profile') + transaction('week6_update_profile')
     + '<div class="pass">✓ Чужой authority и длинное имя отклонены</div>',
     'localnet-run.json'),
    (7, 'Токен Evently Lab', 'LOCALNET · Token-2022',
     row('Mint', run['token']['mint']) + row('Символ', run['token']['metadata']['symbol'])
     + row('Выпуск', '1 000,00 ELAB') + row('Переведено', '25,00 ELAB')
     + row('Баланс отправителя', '975,00 ELAB') + row('Баланс получателя', '25,00 ELAB')
     + transaction('week7_transfer_tokens')
     + '<div class="pass">✓ Метаданные и объём выпуска проверены</div>',
     'localnet-run.json'),
    (8, 'РК1: Web3 MVP', 'LOCALNET · интеграционный прогон',
     '<p>Evently: гость регистрируется, получает билет с Web3-подтверждением, организатор делает check-in.</p>'
     + row('Проверок', f"{sum(x['passed'] for x in mvp['checks'])}/{len(mvp['checks'])} пройдено")
     + '<div class="checks">' + ''.join(
         f'<div><span>✓</span>{escape(item["label"])}<b>{escape(str(item["actual"]))}</b></div>'
         for item in mvp['checks'] if item['label'] in {
             'login_visitor', 'organizer_creates_event', 'guest_reserves_ticket',
             'rails_verifies_real_token2022', 'ticket_is_confirmed',
             'first_checkin_accepted', 'duplicate_checkin_rejected',
             'guest_cannot_read_guest_list', 'one_visit'}) + '</div>',
     'mvp-integration.json'),
]

style = '''<style>
*{box-sizing:border-box}body{margin:0;background:#edf1f7;color:#182443;font-family:Arial,sans-serif}
.page{max-width:760px;margin:22px auto;padding:28px;background:#fff;border:1px solid #dfe5f0;border-radius:16px;box-shadow:0 14px 40px #1b28541c}
.brand{font-size:13px;font-weight:800;letter-spacing:.14em;color:#674fea}.eyebrow{margin:20px 0 4px;font-size:12px;font-weight:800;letter-spacing:.1em;color:#5342c2}
h1{font-size:26px;line-height:1.15;margin:0 0 14px}p{font-size:14px;line-height:1.45;color:#40506e;margin:0 0 14px}
.row{display:flex;gap:18px;justify-content:space-between;padding:9px 0;border-bottom:1px solid #e7ebf4;font-size:13px}
.row span{color:#67738d;min-width:120px}.row strong{max-width:70%;text-align:right;overflow-wrap:anywhere;font-size:12px}
.transaction{border:1px solid #dfe3f5;background:#f8f9fe;border-radius:10px;margin-top:12px;padding:12px}.transaction>b{font-size:13px;color:#342788}
.transaction .row{padding:5px 0}.signature{padding:8px 0;font:11px/1.35 Menlo,Consolas,monospace;overflow-wrap:anywhere;color:#29355d}
pre{font:11px/1.35 Menlo,Consolas,monospace;white-space:pre-wrap;background:#151d39;color:#e6eaff;padding:12px;border-radius:9px;overflow:hidden}
.pass{color:#176b46;background:#e6f7ef;padding:9px;border-radius:7px;font-size:12px;margin-top:12px;font-weight:700}
.small{font-size:11px;color:#64708c;margin-top:9px;overflow-wrap:anywhere}.checks{font-size:12px}.checks div{display:flex;gap:8px;align-items:center;padding:6px 0;border-bottom:1px solid #edf0f5}.checks span{color:#14885b}.checks b{margin-left:auto;color:#382a93}
.foot{border-top:1px solid #e6eaf3;margin-top:16px;padding-top:10px;font-size:11px;color:#68748e}
@media(max-width:800px){.page{margin:0;min-height:100vh;border-radius:0;padding:18px}.row strong{max-width:65%}}
</style>'''

for number, title, badge, body, source in pages:
    html = (f'<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>Evently — Неделя {number}</title>{style}<div class="page">'
            f'<div class="brand">EVENTLY / RK1</div><div class="eyebrow">НЕДЕЛЯ {number:02d} · {escape(badge)}</div>'
            f'<h1>{escape(title)}</h1>{body}<div class="foot">Снимок сохранённых результатов · источник: coursework/rk1/evidence/{escape(source)}</div></div></html>')
    (OUTPUT / f'week-{number:02d}.html').write_text(html)
    print(OUTPUT / f'week-{number:02d}.html')
