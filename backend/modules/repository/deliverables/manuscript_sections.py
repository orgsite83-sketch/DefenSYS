"""Conservative manuscript sections shared by evidence readers, without I/O.

Headings must occupy a line or use an explicit colon. Ordinary sentences such
as "implementation improves ..." must not silently change section identity.
"""
import re


SECTION_VERSION = 'manuscript-sections-1'
ALIASES = {
    'general objective': 'general objectives', 'specific objective': 'specific objectives',
    'statement of objectives': 'objectives', 'statement of the objectives': 'objectives',
    'objectives of the study': 'objectives', 'objectives of study': 'objectives',
    'objectives of the project': 'project objectives', 'objectives of project': 'project objectives',
    'system objectives': 'project objectives',
    'overview of the proposed system': 'proposed system features',
    'proposed key features': 'proposed system features', 'proposed system': 'proposed system features',
    'proposed innovation': 'project purpose', 'beneficiaries': 'target beneficiaries',
    'target users': 'target beneficiaries',
    'hardware and software requirements': 'technology stack',
    'software requirements': 'technology stack', 'development tools and technologies': 'technology stack',
    'system architecture': 'technical architecture', 'system architecture and development': 'technical architecture',
    'scope and limitation': 'scope and limitations',
}
KNOWN = {
    'abstract', 'introduction', 'introduction / background', 'background',
    'background and rationale', 'background of study', 'background of the study',
    'problem statement', 'statement of the problem', 'project purpose', 'project description',
    'objectives', 'project objectives', 'general objectives', 'specific objectives',
    'proposed system features', 'proposed system and key functions', 'system features',
    'functional requirements', 'main features', 'system functionality',
    'target beneficiaries', 'target users and information requirements',
    'implementation', 'technical architecture', 'technology stack', 'methodology',
    'scope', 'scope and limitations', 'scope and boundaries', 'success indicators',
    'expected output', 'expected outputs', 'expected outputs and outcomes',
    'expected outputs and initial success indicators', 'proposed development and validation plan',
    'results', 'conclusion',
}
EXCLUDED = re.compile(
    r'^(?:review of (?:the )?related (?:literature|literatures|studies|systems)|'
    r'review of literature|related (?:work|literature|studies|systems)|literature review|'
    r'references|bibliography|significance of (?:the )?study|definition of terms|'
    r'conceptual framework|theoretical framework|risk considerations and safeguards|'
    r'preliminary technology considerations|research design|research methodology|'
    r'data gathering|scope and limitation(?:s)? of (?:the )?study)\b', re.I)
NUMBER = re.compile(r'^\s*\d+(?:\.\d+)*[.)]?\s*(?=[A-Za-z])')
EXCLUDED_TITLES = {
    'significance of the study', 'significance of study', 'definition of terms',
    'conceptual framework', 'theoretical framework', 'research design', 'research methodology',
    'review of related literature', 'review of related literatures', 'review of related literature and studies',
    'review of related literature and related systems', 'review of related systems', 'references', 'bibliography',
    'risk considerations and safeguards', 'preliminary technology considerations',
    'scope and limitation of the study', 'scope and limitations of the study',
}
COMPACT_HEADINGS = [(re.compile(r'^' + r'\s*'.join(re.escape(word) for word in title.split()), re.I),
                     ALIASES.get(title, title))
                    for title in sorted(KNOWN | set(ALIASES) | EXCLUDED_TITLES, key=len, reverse=True)]
COMPACT_LOOKUP = {re.sub(r'\s+', '', title): ALIASES.get(title, title)
                  for title in KNOWN | set(ALIASES) | EXCLUDED_TITLES}
CHAPTER = re.compile(r'^chapter\s*(\d+|[ivx]+)\b\s*[:.\-–—\ufffd]?\s*(.*)$', re.I)
LEADER = re.compile(r'\.{3,}|(?:\.\s){4,}|\ufffd{4,}|\u2026{3,}')
METADATA = re.compile(r'^(?:team members?|adviser|advisor|submitted by|submitted to|'
                      r'concept paper page|page \d)\b', re.I)
CONTEXT = {'abstract', 'introduction', 'introduction / background', 'background',
           'background and rationale', 'background of study', 'background of the study',
           'problem statement', 'statement of the problem', 'project description'}
PRIMARY = {'general objectives', 'objectives', 'project objectives', 'project purpose'}
FUNCTIONS = {'specific objectives', 'proposed system features', 'proposed system and key functions',
             'system features', 'functional requirements', 'main features', 'system functionality'}


def heading(line):
    """Return (canonical heading, explicit inline content), or None."""
    value = NUMBER.sub('', line).strip().strip('#').strip()
    title, separator, body = value.partition(':')
    title = re.sub(r'\s*/\s*', ' / ', title).strip(' .').casefold()
    title = ALIASES.get(title, title)
    if title in KNOWN or EXCLUDED.match(title):
        return title, body.strip() if separator else ''
    # PDF fonts sometimes lose spaces inside headings. A numbered heading may
    # also share a line with its paragraph; ordinary unnumbered prose cannot.
    numbered = bool(NUMBER.match(line))
    if not numbered:
        canonical = COMPACT_LOOKUP.get(re.sub(r'\s+', '', value.strip(' .:')).casefold())
        return (canonical, '') if canonical else None
    for pattern, canonical in COMPACT_HEADINGS:
        match = pattern.match(value)
        if match and (numbered or not value[match.end():].strip(' .:')):
            return canonical, value[match.end():].strip(' .:')
    return None


def manuscript_sections(text):
    """Read full documents, retaining page/section boundaries and excluding RRL.

    TOC pages cannot establish a section. Chapter II stays excluded even when
    a cited paper has headings like Objectives or Implementation. Unknown
    numbered subsections close an active section rather than inheriting it.
    """
    pages = (text or '').split('\f')
    structured = any(heading(line) or CHAPTER.match(line.strip()) for line in (text or '').splitlines()
                     if not LEADER.search(line))
    section = '' if structured else 'project description'
    literature = False
    bibliography = False
    passages, seen = [], set()
    for page_number, page in enumerate(pages, 1):
        lines = page.splitlines()
        if (re.search(r'(?im)^\s*(?:table\s*of\s*contents|list\s*of\s*(?:figures|tables))\s*$', page) or
                sum(bool(LEADER.search(line)) for line in lines) >= 3):
            section = ''
            continue
        for raw in lines:
            line = re.sub(r'\s+', ' ', re.sub(r'\(cid:\d+\)', ' ', raw)).strip(' •\t')
            if (not line or LEADER.search(line) or METADATA.match(line) or
                    re.fullmatch(r'\d+|[ivx]+', line, re.I)):
                continue
            chapter = CHAPTER.match(line)
            if chapter:
                literature = chapter[1].casefold() in ('ii', '2')
                bibliography = False
                section = ''
                line = chapter[2]
                if not line:
                    continue
            if literature or bibliography:
                continue
            match = heading(line)
            if match:
                section, line = match
                bibliography = bool(re.match(r'^(?:references|bibliography)\b', section))
                if EXCLUDED.match(section):
                    section = ''
            elif re.match(r'^\d+(?:\.\d+)+[.)]?\s+(?!to\b)', line, re.I):
                section = ''
                continue
            if not section or not line:
                continue
            fingerprint = (section, line.casefold())
            if fingerprint in seen:
                continue
            seen.add(fingerprint)
            tier = 4 if section == 'general objectives' else 3 if section in PRIMARY else 2 if section in FUNCTIONS else 1
            weight = 1 if section in CONTEXT or section.startswith('scope') or section == 'methodology' else 3
            if passages and (passages[-1]['section'], passages[-1]['page']) == (section.title(), page_number):
                passages[-1]['text'] += ' ' + line
            else:
                passages.append({'section': section.title(), 'page': page_number, 'tier': tier,
                                 'weight': weight, 'text': line})
    return passages
