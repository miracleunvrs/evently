"""Extract one editable Word handout per syllabus week from the full report."""

from pathlib import Path
import sys

from docx import Document
from docx.shared import Pt, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn


SOURCE = Path(sys.argv[1])
DEST = Path(sys.argv[2])
DEST.mkdir(parents=True, exist_ok=True)
SCREENSHOTS = Path(__file__).resolve().parents[1] / 'evidence' / 'screenshots'

SECTIONS = [
    ('01', 'Кошелек_и_первая_транзакция', 'Неделя 1 Кошелёк и первая транзакция', 'Неделя 2 Разбор реальных транзакций'),
    ('02', 'Разбор_транзакций', 'Неделя 2 Разбор реальных транзакций', 'Неделя 3 Программа на Rust'),
    ('03', 'Программа_на_Rust', 'Неделя 3 Программа на Rust', 'Неделя 4 Первая Solana Program'),
    ('04', 'Первая_Solana_Program', 'Неделя 4 Первая Solana Program', 'Неделя 5 Счётчик на Anchor'),
    ('05', 'Счетчик_Anchor', 'Неделя 5 Счётчик на Anchor', 'Неделя 6 Профиль с использованием PDA'),
    ('06', 'Профиль_PDA', 'Неделя 6 Профиль с использованием PDA', 'Неделя 7 Выпуск и перевод токена'),
    ('07', 'Токен_и_перевод', 'Неделя 7 Выпуск и перевод токена', 'РК1 Концепция и архитектура MVP'),
    ('08', 'РК1_Web3_MVP', 'РК1 Концепция и архитектура MVP', None),
]


def element_text(element):
    return ''.join((t.text or '') for t in element.xpath('.//w:t'))


original = Document(SOURCE)
body_items = list(original.element.body)
positions = {element_text(item): index for index, item in enumerate(body_items) if item.tag == qn('w:p')}
for number, name, start_title, end_title in SECTIONS:
    assert start_title in positions, start_title
    start = positions[start_title]
    end = positions[end_title] - 1 if end_title else len(body_items) - 1
    assert start < end
    # Start at the heading; keep internal page breaks only for the longer RK1 report.
    report = Document(SOURCE)
    for index, item in enumerate(list(report.element.body)):
        if item.tag != qn('w:sectPr') and not start <= index < end:
            report.element.body.remove(item)
    section = report.sections[0]
    section.different_first_page_header_footer = False
    header = section.header.paragraphs[0]
    header.text = 'ALMATY MANAGEMENT UNIVERSITY   ·   EVENTLY   ·   РК1'
    header.runs[0].font.size = Pt(9)
    header.runs[0].font.color.rgb = RGBColor(0, 0, 0)
    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    footer.text = 'Студент ____________________   Группа __________   |   '
    field = OxmlElement('w:fldSimple')
    field.set(qn('w:instr'), 'PAGE')
    footer._p.append(field)
    for run in footer.runs:
        run.font.size = Pt(8)
    title_style = report.styles['Title']
    title_style.font.size = Pt(19)
    title_style.font.bold = True
    title_style.font.color.rgb = RGBColor(0, 0, 0)
    first = report.paragraphs[0]
    assert first.text == start_title
    first.style = title_style
    report.core_properties.title = f'Evently {start_title}'
    report.core_properties.subject = 'Практическая работа по силлабусу AlmaU 2026'
    report.core_properties.author = ''
    report.add_page_break()
    report.add_heading('Скриншот проверки', level=1)
    if number == '02':
        report.add_paragraph('Solana Explorer: публичная транзакция стороннего кошелька в Devnet. Это материал для разбора, не отправленная Evently транзакция.')
        report.add_picture(str(SCREENSHOTS / 'week-02-explorer.jpg'), width=Inches(5.9))
        report.add_paragraph('Ниже — сводка разобранной транзакции из сохранённого RPC-ответа.')
        report.add_picture(str(SCREENSHOTS / 'week-02.jpg'), width=Inches(5.9))
    else:
        cluster = 'Localnet' if number != '03' else 'локальный Rust CLI'
        report.add_paragraph(f'Снимок экрана с результатами запуска ({cluster}); данные взяты из файлов evidence, указанных в работе. Это не подтверждение развёртывания в Devnet.')
        report.add_picture(str(SCREENSHOTS / f'week-{number}.jpg'), width=Inches(6.2))
    output = DEST / f'Неделя_{number}_{name}.docx'
    report.save(output)
    print(output)
