"""Deterministic presentation metadata for already-public repository files.

Document stages come from their labels, never a research-topic classifier.
Overviews quote an existing section; they do not generate paper summaries.
"""

import html
import re
from pathlib import PurePosixPath


DOCUMENT_LABELS = {
    'concept': 'Concept Paper',
    'chapters': 'Chapters 1–3',
    'final': 'Final Manuscript',
    'document': 'Document',
    'poster': 'Poster',
    'video': 'Video',
    'other': 'Other Output',
}
VIDEO_EXTENSIONS = {'.mp4', '.webm', '.mov', '.m4v', '.avi', '.mkv'}
IMAGE_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg'}
DOCUMENT_EXTENSIONS = {'.pdf', '.doc', '.docx', '.txt', '.odt', '.rtf'}
HEADING = re.compile(
    r'^\s*(?:(?:\d+(?:\.\d+)*|[IVX]+)[.)]?\s+)?'
    r'(?P<title>abstract|background(?: of (?:the )?study| and rationale)?|'
    r'study background|introduction|statement of (?:the )?problem|problem statement|'
    r'objectives(?: of (?:the )?study)?|scope(?: and (?:limitations|boundaries))?|'
    r'significance(?: of (?:the )?study)?|methodology|research methodology|'
    r'related (?:literature|studies|work)|review of related literature|'
    r'definition of terms|theoretical framework|conceptual framework|'
    r'references|bibliography|results(?: and discussion)?|conclusions?|recommendations?)'
    r'\s*(?::\s*(?P<inline>.*)|[.]?\s*)$', re.I,
)
CHAPTER = re.compile(r'^\s*chapter\s+(?:\d+|[IVX]+)\b', re.I)
TOC_LINE = re.compile(r'(?:\.{2,}|\s{3,})\s*\d+\s*$')


def clean_document_text(text):
    value = html.unescape(str(text or ''))
    value = re.sub(r'<br\s*/?>|</(?:p|div)>', '\n', value, flags=re.I)
    value = re.sub(r'<[^>]+>', '', value)
    value = re.sub(r'\(cid:\d+\)', '', value)
    return value.replace('\r\n', '\n').replace('\r', '\n')


def document_overview(text, fallback=''):
    """Prefer an actual abstract/background, skipping TOC and cover metadata."""
    source = clean_document_text(text)[:180000]
    sections = []
    current = None
    offset = 0
    for line in source.splitlines(keepends=True):
        stripped = line.strip()
        match = None if TOC_LINE.search(stripped) else HEADING.fullmatch(stripped)
        if match or CHAPTER.match(stripped):
            if current:
                sections.append(current)
            current = None
            if match:
                title = match['title'].lower()
                label = 'Abstract' if title == 'abstract' else (
                    'Background of the Study' if 'background' in title else None)
                if label:
                    current = {'label': label, 'lines': [match['inline'] or ''],
                               'page': source[:offset].count('\f') + 1 if '\f' in source else None}
        elif current:
            if stripped and not stripped.isdigit():
                current['lines'].append(stripped)
        offset += len(line)
    if current:
        sections.append(current)
    for preferred in ('Abstract', 'Background of the Study'):
        for section in sections:
            content = re.sub(r'\s+', ' ', ' '.join(section['lines'])).strip()
            if section['label'] == preferred and len(content) >= 40:
                return {'overview_label': preferred, 'overview_text': content[:3500],
                        'overview_page': section['page']}
    excerpt = re.sub(r'\s+', ' ', source or clean_document_text(fallback)).strip()
    return {'overview_label': 'Document excerpt', 'overview_text': excerpt[:650],
            'overview_page': None}


def document_kind(entry):
    filename = str(entry.get('file_name') or '')
    extension = PurePosixPath(filename.lower()).suffix
    label = str(entry.get('deliverable_label') or '')
    words = re.sub(r'[_–—.-]', ' ', f'{label} {filename}').lower()
    if extension in VIDEO_EXTENSIONS:
        return 'video'
    if re.search(r'\bposter\b', words):
        return 'poster'
    if extension in IMAGE_EXTENSIONS:
        return 'other'
    if extension and extension not in DOCUMENT_EXTENSIONS:
        return 'other'
    if re.search(r'\bconcept(?:\s+(?:paper|proposal))?\b', words):
        return 'concept'
    if re.search(r'\bchapters?\s*1\s*(?:to\s*|\s+)?[23]\b', words):
        return 'chapters'
    if re.search(r'\b(?:final|approved|full)\s+(?:manuscript|paper|research)\b|\bmanuscript\b', words):
        return 'final'
    return 'document'


def enrich_library_entry(entry):
    kind = document_kind(entry)
    document_label = DOCUMENT_LABELS[kind]
    if kind == 'chapters':
        chapter_range = re.search(r'chapters?\s*1\s*(?:[-_–—]|to|\s)\s*([23])\b',
                                  f"{entry.get('deliverable_label', '')} {entry.get('file_name', '')}".replace('_', ' '), re.I)
        if chapter_range:
            document_label = f'Chapters 1–{chapter_range[1]}'
    title = str(entry.get('project_title') or '').strip()
    if not title:
        filename = str(entry.get('file_name') or '')
        candidate = re.sub(r'[_]+', ' ', PurePosixPath(filename).stem).strip()
        generic = re.search(r'\b(?:approved concept|concept paper|final manuscript|chapter[s]? 1)\b', candidate, re.I)
        title = candidate if candidate and not generic else str(entry.get('team_name') or 'Research project')
    team_id = entry.get('team_id')
    # Unlinked uploads remain independent; matching team names is insufficient.
    project_key = ':'.join(str(part or '') for part in (
        entry.get('type'), team_id, entry.get('project_version', 1),
        entry.get('academic_year'), entry.get('semester'),
    )) if team_id else f"entry:{entry['id']}"
    is_document = kind in ('concept', 'chapters', 'final', 'document')
    overview = document_overview(entry.get('extracted_text'), entry.get('summary')) if is_document else {
        'overview_label': 'Description', 'overview_text': str(entry.get('description') or ''),
        'overview_page': None,
    }
    entry.update(project_key=project_key, display_title=title, document_kind=kind,
                 document_label=document_label, overview_source=entry.get('deliverable_label') or document_label,
                 **overview)
    return entry
