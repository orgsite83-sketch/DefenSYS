"""Build reviewable audit diagrams and native-Docs text from local audit sources.

No application data or network access. Requires Pillow; inputs and outputs are
regenerable files in .tmp/system-flow-audit/.
"""
import json
import math
from pathlib import Path
import re
import textwrap
from html import escape

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.tmp' / 'system-flow-audit'
FONT = Path('C:/Windows/Fonts/segoeui.ttf')
BOLD = Path('C:/Windows/Fonts/seguisb.ttf')
INK = '#182736'
LINE = '#687C8C'
BLUE = '#DFEDF9'
GREEN = '#E2F0E8'
AMBER = '#FFF0D8'
RED = '#F8E4E3'


def font(size=30, bold=False):
    return ImageFont.truetype(str(BOLD if bold else FONT), size)


def chart(name, title, subtitle, nodes, edges, height):
    im = Image.new('RGB', (1400, height), 'white')
    d = ImageDraw.Draw(im)
    d.text((50, 24), title, font=font(40, True), fill=INK)
    d.text((50, 84), subtitle, font=font(25), fill=LINE)
    for points, label in edges:
        d.line(points, fill=LINE, width=4, joint='curve')
        x, y = points[-1]
        px, py = points[-2]
        a = math.atan2(y-py, x-px)
        d.polygon([(x, y), (x-17*math.cos(a-.45), y-17*math.sin(a-.45)),
                   (x-17*math.cos(a+.45), y-17*math.sin(a+.45))], fill=LINE)
        if label:
            lx, ly, text = label
            bbox = d.textbbox((lx, ly), text, font=font(24))
            d.rectangle((bbox[0]-8, bbox[1]-4, bbox[2]+8, bbox[3]+4), fill='white')
            d.text((lx, ly), text, font=font(24), fill=INK)
    for box, text, fill in nodes:
        d.rounded_rectangle(box, radius=15, fill=fill, outline='#CFD9E1', width=2)
        lines = text.split('\n')
        line_height = 39
        x1, y1, x2, y2 = box
        ty = y1 + ((y2-y1) - len(lines)*line_height)/2 - 1
        for line in lines:
            w = d.textlength(line, font=font(30, True))
            if w > x2-x1-20:
                raise ValueError(f'Label too wide: {line}')
            d.text(((x1+x2-w)/2, ty), line, font=font(30, True), fill=INK)
            ty += line_height
    path = OUT / f'{name}.png'
    im.save(path)
    return {'name': name, 'path': str(path), 'width': 468, 'height': round(468*height/1400, 2)}


def diagrams():
    master = chart('master', 'DefenSYS: feature connections', 'Implemented paths • read alongside findings and owner verification points', [
        ((380,150,1020,260),'Active semester + accounts\nAcademic records + faculty assignments',BLUE),
        ((70,335,640,445),'PIT teams + sections\nYear-owned event configuration',BLUE),
        ((760,335,1330,445),'Capstone teams + adviser\nOrdered stage configuration',BLUE),
        ((70,520,640,630),'PIT requirements / endorsement\nPanel + peer rubrics',BLUE),
        ((760,520,1330,630),'Stage requirements / endorsement\nPanel + adviser + peer rubrics',BLUE),
        ((380,710,1020,820),'Schedule + room + evaluator assignments\nPresentation materials + deadlines',BLUE),
        ((70,915,640,1025),'PIT evaluation + event completion\nCohort rollover is a separate action',GREEN),
        ((760,915,1330,1025),'Capstone scores + official verdict\nRevisions / re-defense / recovery',AMBER),
        ((380,1115,1020,1230),'Approved post files / private evidence\nRepository • reports • analytics • history',GREEN),
    ], [
        ([(700,260),(700,295),(355,295),(355,335)],None),
        ([(700,295),(1045,295),(1045,335)],None),
        ([(355,445),(355,520)],None), ([(1045,445),(1045,520)],None),
        ([(355,630),(355,675),(550,675),(550,710)],None),
        ([(1045,630),(1045,675),(850,675),(850,710)],None),
        ([(550,820),(550,865),(355,865),(355,915)],None),
        ([(850,820),(850,865),(1045,865),(1045,915)],None),
        ([(355,1025),(355,1070),(550,1070),(550,1115)],None),
        ([(1045,1025),(1045,1070),(850,1070),(850,1115)],None),
    ], 1290)
    capstone = chart('capstone', 'Capstone: defense outcomes and progression', 'Numeric grade, official verdict, schedule state and archive visibility are separate', [
        ((350,150,1050,260),'Configure stage + create team\nSubmit / review scheduling requirements',BLUE),
        ((350,325,1050,435),'Assigned adviser / admin endorses\nAdmin schedules eligible team',BLUE),
        ((350,500,1050,610),'Materials + panel evaluations\nAdviser / peer components when enabled',BLUE),
        ((350,675,1050,775),'All required panelists complete\nChair / admin records official verdict',AMBER),
        ((100,855,1300,1160),'Approved → complete remaining evidence\nApproved with Revisions → evidence + clearance\nFor Re-defense → verify if required + new attempt\nFailed → admin authorizes recovery or keeps blocked\nProject Rejected → authorize new project version',AMBER),
        ((150,1310,1250,1430),'Required scores + accepted post files + passing / cleared outcome\nPublish / finalize → passed stage → next stage when eligible',GREEN),
    ], [
        ([(700,260),(700,325)],None), ([(700,435),(700,500)],None),
        ([(700,610),(700,675)],None),
        ([(700,775),(700,855)],None),
        ([(700,1160),(700,1310)],(730,1200,'Passing / cleared outcomes only')),
    ], 1490)
    pit = chart('pit', 'PIT: event assessment and academic continuity', 'PIT scores do not decide academic promotion • PIT has no Capstone verdict workflow', [
        ((350,150,1050,260),'Lead imports year / section cohort\nAssign instructors + form PIT teams',BLUE),
        ((350,325,1050,435),'Create year-owned event\nRequirements + panel / peer rubrics',BLUE),
        ((350,500,1050,610),'Review / endorse where required\nSchedule + presentation materials',BLUE),
        ((350,675,1050,785),'Panel evaluations + open peer evaluation\nComplete required scores',BLUE),
        ((350,850,1050,960),'Event readiness → official completion\nComplete results can finalize below 75',GREEN),
        ((40,1050,660,1170),'Approved unrestricted post files\nShared repository + private archive',GREEN),
        ((740,1050,1360,1170),'Separate cohort rollover action\nPreview → academic records → history',AMBER),
    ], [
        ([(700,260),(700,325)],None), ([(700,435),(700,500)],None),
        ([(700,610),(700,675)],None), ([(700,785),(700,850)],None),
        ([(700,960),(700,1000),(350,1000),(350,1050)],None),
        ([(1050,205),(1380,205),(1380,1015),(1050,1015),(1050,1050)],None),
    ], 1230)
    return [master, capstone, pit]


def technical(inv):
    lines = ['### Appendix A. Resolved API catalog',
             'Methods are resolved from class inheritance; aliases and dynamically expanded catalog reports are included. Service checks may disable or further restrict an operation.']
    for r in inv['resolved_routes']:
        lines.append(f"{','.join(r['methods'])} {r['route']} → {r['view']}")
    lines += ['', '### Appendix B. All model classes and their relationship fields',
              'Only explicit Django model classes and relationship declarations are listed; inherited auth tables, generated join tables and scalar fields are not counted as separate feature models.']
    for m in inv['models']:
        rels = [f'{k} → {v}' for k, v in m['attributes'].items() if any(t in v for t in ('models.ForeignKey(', 'models.OneToOneField(', 'models.ManyToManyField('))]
        lines.append(f"{m['name']} — {m['file']}:{m['line']}")
        for rel in rels:
            # Preserve relation targets and ownership without all field kwargs.
            match = re.match(r'(\w+) → models\.(\w+)\(([^,]+)', rel)
            if match:
                lines.append(f'  {match[1]}: {match[2]} → {match[3]}')
    lines += ['', '### Appendix C. Frontend API and navigation wiring',
              'Root provider files often re-export the feature-directory implementation; an export shim is not a separate feature.']
    for f in inv['frontend']:
        if not f['api_lines']:
            continue
        relevant = [p for p in f['api_lines'] if 'ApiConfig.' in p['text'] or ('baseUrl' in p['text'] and 'static' in p['text'])]
        if relevant and '/services/' in f['file']:
            lines.append(f['file'])
            for line in relevant:
                lines.append(f"  L{line['line']}: {line['text']}")
    return '\n'.join(lines)


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    inv = json.loads((OUT/'inventory.json').read_text(encoding='utf-8'))
    images = diagrams()
    source = (OUT/'report.md').read_text(encoding='utf-8')
    source = source.replace('[[TECHNICAL_APPENDIX]]', technical(inv))
    result_path = OUT/'frontend-result.txt'
    source = source.replace('[[FRONTEND_RESULTS]]', result_path.read_text(encoding='utf-8') if result_path.exists() else 'Frontend focused checks are in progress; result will be updated before delivery.')
    headings, image_markers, lines, offset = [], [], [], 1
    for line in source.splitlines():
        match = re.match(r'^(#{1,3}) (.*)$', line)
        if match:
            level, line = len(match[1]), match[2]
            headings.append({'startIndex':offset, 'endIndex':offset+len(line), 'style':'TITLE' if level == 1 else f'HEADING_{level-1}'})
        if line.startswith('[[IMAGE:'):
            name = line[8:-2]
            image_markers.append({'startIndex':offset,'endIndex':offset+len(line),'name':name})
        lines.append(line)
        offset += len(line.encode('utf-16-le'))//2 + 1
    # Heading/marker content is ASCII or BMP only, so Python lengths coincide
    # with UTF-16 units for those specific ranges.
    text = '\n'.join(lines)+'\n'
    payload = {'text':text, 'headings':headings,'image_markers':image_markers,'images':images,
               'summary':{'words':len(text.split()), 'api_routes':len(inv['resolved_routes']), 'models':len(inv['models'])}}
    (OUT/'doc_payload.json').write_text(json.dumps(payload, ensure_ascii=False), encoding='utf-8')
    local_source = source
    for item in images:
        local_source = local_source.replace(f"[[IMAGE:{item['name']}]]", f"![{item['name'].title()} flow]({item['name']}.png)")
    (OUT/'complete-report.md').write_text(local_source, encoding='utf-8')
    print(json.dumps(payload['summary']))


def build_pdf():
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Image as PdfImage, PageBreak

    pdfmetrics.registerFont(TTFont('SegoeAudit', str(FONT)))
    pdfmetrics.registerFont(TTFont('SegoeAuditBold', str(BOLD)))
    p = json.loads((OUT/'doc_payload.json').read_text(encoding='utf-8'))
    styles = {
        'body': ParagraphStyle('body', fontName='SegoeAudit', fontSize=9.5, leading=14, spaceAfter=7, splitLongWords=True),
        'title': ParagraphStyle('title', fontName='SegoeAuditBold', fontSize=23, leading=29, spaceAfter=16, keepWithNext=True),
        'h1': ParagraphStyle('h1', fontName='SegoeAuditBold', fontSize=16, leading=21, spaceBefore=17, spaceAfter=9, keepWithNext=True),
        'h2': ParagraphStyle('h2', fontName='SegoeAuditBold', fontSize=12, leading=16, spaceBefore=13, spaceAfter=7, keepWithNext=True),
        'tech': ParagraphStyle('tech', fontName='SegoeAudit', fontSize=8, leading=11, spaceAfter=5, splitLongWords=True),
    }
    heading_map = {p['text'][h['startIndex']-1:h['endIndex']-1]: h['style'] for h in p['headings']}
    images = {i['name']: i for i in p['images']}
    story, technical_mode = [], False
    for raw in p['text'].splitlines():
        raw = raw.replace('—','-').replace('–','-').replace('\u2011','-')
        if not raw.strip():
            continue
        if raw.startswith('[[IMAGE:'):
            item = images[raw[8:-2]]
            story.append(PdfImage(item['path'], width=item['width'], height=item['height']))
            story.append(Spacer(1, 10))
            continue
        # Normalize Unicode dashes before lookup while preserving original text.
        style_name = next((v for k,v in heading_map.items() if k.replace('—','-').replace('–','-').replace('\u2011','-') == raw), None)
        if raw.startswith('Appendix A.'):
            technical_mode = True
            story.append(PageBreak())
        style = styles['title'] if style_name == 'TITLE' else styles['h1'] if style_name == 'HEADING_1' else styles['h2'] if style_name else styles['tech'] if technical_mode else styles['body']
        story.append(Paragraph(escape(raw), style))

    final = ROOT/'outputs'/'system-flow-audit'
    final.mkdir(parents=True, exist_ok=True)
    pdf_path = final/'DefenSYS-System-Audit-and-Feature-Flows.pdf'
    def decorate(canvas, doc):
        canvas.saveState()
        canvas.setFont('SegoeAudit', 8)
        canvas.setFillColor(colors.HexColor('#536575'))
        canvas.drawString(48, 24, 'DefenSYS | Owner review | 16 Oct 2026 | Local working-tree audit')
        canvas.drawRightString(A4[0]-48, 24, str(doc.page))
        canvas.restoreState()
    doc = SimpleDocTemplate(str(pdf_path), pagesize=A4, leftMargin=48, rightMargin=48,
                            topMargin=43, bottomMargin=43, title='DefenSYS - System Audit and Feature Flows',
                            author='DefenSYS codebase audit')
    doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
    print(json.dumps({'pdf':str(pdf_path)}))


def inspect_pdf():
    import pdfplumber
    pdf_path = ROOT/'outputs'/'system-flow-audit'/'DefenSYS-System-Audit-and-Feature-Flows.pdf'
    thumbs, pages, texts, selected = [], [], [], []
    with pdfplumber.open(pdf_path) as pdf:
        for index, page in enumerate(pdf.pages):
            text = page.extract_text() or ''
            texts.append(text)
            preview = page.to_image(resolution=75).original.convert('RGB')
            thumb = preview.copy()
            thumb.thumbnail((178, 252))
            tile = Image.new('RGB', (194, 280), '#E7EDF0')
            tile.paste(thumb, ((194-thumb.width)//2, 4))
            ImageDraw.Draw(tile).text((9,258),str(index+1),font=font(16),fill=INK)
            thumbs.append(tile)
            if index == 0 or page.images or 'A01 - High' in text or 'V01.' in text or index == len(pdf.pages)-1:
                dest = OUT/f'pdf-page-{index+1:02}.png'
                page.to_image(resolution=120).save(str(dest))
                selected.append({'page':index+1,'image':str(dest)})
            pages.append({'page':index+1,'characters':len(text),'images':len(page.images)})
    sheet = Image.new('RGB',(194*5,280*math.ceil(len(thumbs)/5)),'#E7EDF0')
    for i,tile in enumerate(thumbs):
        sheet.paste(tile,((i%5)*194,(i//5)*280))
    sheet.save(OUT/'pdf-contact-sheet.png')
    joined='\n'.join(texts)
    checks={
        'feature_ids_complete':all(f'F{i:02}.' in joined for i in range(1,35)),
        'verification_ids_complete':all(f'V{i:02}.' in joined for i in range(1,31)),
        'finding_ids_complete':all(f'A{i:02}' in joined for i in range(1,12)),
        'placeholder_free':'[[IMAGE:' not in joined and '[[FRONTEND' not in joined and 'in progress; result' not in joined,
        'api_catalog_present':'/api/password-reset/confirm/' in joined and '/api/health/' in joined,
        'test_results_present':'168 tests passed' in joined and '61 tests passed' in joined,
    }
    result={'page_count':len(pages),'image_count':sum(p['images'] for p in pages),'checks':checks,'selected':selected,'pages':pages}
    (OUT/'pdf-qa.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='pages'}))
    if not all(checks.values()):
        raise ValueError('PDF completeness check failed')


if __name__ == '__main__':
    build()
    if '--pdf' in __import__('sys').argv:
        build_pdf()
    if '--inspect-pdf' in __import__('sys').argv:
        inspect_pdf()
