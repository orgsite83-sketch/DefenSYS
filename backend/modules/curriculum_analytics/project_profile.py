"""Extract a bounded project overview from eligible, related source passages.

This is an extractive view, not a new ML prediction or an implementation claim.
The caller applies the same period, version and topic checks as classification.
"""
import re

from repository.deliverables.project_classification import HEADER, METADATA, TENTATIVE, section_chunks


CONTEXT_HEADER = re.compile(
    r'^\s*(?:\d+(?:\.\d+)*[.)]?\s+)?'
    r'(?:chapter\s+[\divx]+\s+)?'
    r'(background of (?:the )?study|background and rationale|background|'
    r'introduction\s*/\s*background|introduction|abstract|'
    r'statement of the problem|problem statement|project purpose)\s*[:.]?\s*(.*)$', re.I)
SECTION_BOUNDARY = re.compile(
    r'^\s*(?:\d+(?:\.\d+)*[.)]?\s+)?'
    r'(?:chapter\s+[\divx]+\b|specific objectives|general objectives|'
    r'objectives of (?:the )?(?:study|project)|scope and limitations|'
    r'significance of (?:the )?study|definition of terms|'
    r'conceptual framework|theoretical framework|functional requirements|'
    r'main features|system functionality)\b', re.I)
CONTEXT_PRIORITY = {'background of the study': 0, 'background of study': 0,
                    'background and rationale': 0, 'background': 0,
                    'introduction / background': 1, 'introduction': 1,
                    'abstract': 2, 'statement of the problem': 3,
                    'problem statement': 3, 'project purpose': 4}
PROPOSED = re.compile(r'\b(?:proposed|will|shall|aims? to|plans? to)\b', re.I)
PROPOSAL_LABEL = re.compile(r'concept|proposal|chapters?\s*1\s*[-–]\s*3', re.I)
PLATFORMS = {
    'Web': r'\b(?:web[-\s]+(?:based|application|app|portal)|browser[-\s]+based|website)\b',
    'Mobile': r'\b(?:mobile (?:app|application)|android|ios)\b',
    'Desktop': r'\bdesktop (?:app|application)\b',
    'Embedded': r'\b(?:embedded (?:system|device|prototype)|microcontroller|arduino|esp32)\b',
}


def _reference(document, section, text):
    return {'text': text, 'excerpt': text, 'section': section,
            'document_id': document['id'], 'source_label': document['display_name']}


def _status(document, section, text):
    return 'proposed' if (PROPOSAL_LABEL.search(document['label']) or
                          'proposed' in section.lower() or PROPOSED.search(text)) else 'documented'


def _context_excerpt(text):
    """Copy a named introductory section; never reinterpret objectives."""
    section, pending, results = '', [], []

    def flush():
        value = ' '.join(pending).strip()
        pending.clear()
        if section and len(value) >= 40:
            results.append((section, value))

    for raw in (text or '')[:80000].splitlines():
        line = re.sub(r'\s+', ' ', re.sub(r'\(cid:\d+\)', ' ', raw)).strip()
        heading = CONTEXT_HEADER.match(line)
        if heading:
            flush()
            section = re.sub(r'\s*/\s*', ' / ', heading[1].lower())
            line = heading[2].strip()
        elif HEADER.match(line) or SECTION_BOUNDARY.match(line):
            flush()
            section = ''
            continue
        if not section or not line or METADATA.match(line):
            continue
        pending.append(line)
    flush()
    if not results:
        return None
    section, body = min(results, key=lambda result: CONTEXT_PRIORITY[result[0]])
    truncated = len(body) > 1000
    if truncated:
        shortened = body[:1000].rsplit(' ', 1)[0]
        sentence_end = max(shortened.rfind('. '), shortened.rfind('! '), shortened.rfind('? '))
        body = shortened[:sentence_end + 1] if sentence_end >= 500 else shortened + '…'
    title = section.title().replace(' Of The ', ' of the ').replace(' Of Study', ' of Study').replace(' And ', ' and ')
    return {'section': title, 'text': body, 'truncated': truncated}


def build_project_profile(documents, classification):
    """Return source-linked facts; absent fields stay absent."""
    primary = classification.get('document_id')
    documents = sorted(documents, key=lambda d: (d['id'] == primary, d['uploaded_at']), reverse=True)
    platforms, description = {}, None
    for document in documents:
        raw = document.get('_raw_text', '')
        if description is None:
            context = _context_excerpt(raw)
            if context:
                description = {**_reference(document, context['section'], context['text']),
                               'truncated': context['truncated']}
        chunks = section_chunks(raw)
        passages = []
        for chunk in chunks:
            if passages and passages[-1]['section'] == chunk['section']:
                passages[-1]['text'] += ' ' + chunk['text']
            else:
                passages.append(dict(chunk))
        for passage in passages:
            # Tentative, excluded and literature sections are removed by section_chunks.
            # Check again after joining wraps to catch "may be\nused".
            if TENTATIVE.search(passage['text']):
                continue
            for name, pattern in PLATFORMS.items():
                match = re.search(pattern, passage['text'], re.I)
                if match and name not in platforms:
                    start = max(0, match.start() - 80)
                    excerpt = passage['text'][start:start + 320]
                    platforms[name] = {**_reference(document, passage['section'], excerpt),
                                       'name': name, 'status': _status(document, passage['section'], passage['text'])}
    return {'description': description, 'platforms': list(platforms.values()),
            'primary_document_id': primary,
            'source_count': len(documents), 'method': 'Extracted source passages'}
