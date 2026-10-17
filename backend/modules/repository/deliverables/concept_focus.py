"""Conservative functional evidence for proposals without a chosen platform.

This is a broad Information Systems estimate, not a trained-model probability.
Only proposed objectives/features count; a problem description, implementation
boilerplate or an isolated noun cannot establish the proposed functionality.
"""
import re


FUNCTION_SECTIONS = {
    'objectives', 'project objectives', 'specific objectives', 'general objectives',
    'proposed system features', 'system features', 'proposed system and key functions',
    'functional requirements', 'main features', 'system functionality',
}
ENTITIES = (
    r'records?|entries|requests?|tickets?|notices?|announcements?|documents?|forms?|'
    r'files?|catalogs?|catalogues?|directories|directory|listings?|books?|'
    r'reservations?|bookings?|appointments?|availability|time slots?|schedules?|'
    r'events?|sessions?|trips?|routes?|stops?|vehicles?|menus?|items?|meals?|prices?|'
    r'ratings?|feedback|comments?|groups?|profiles?|contacts?|badges?|awards?|'
    r'milestones?|achievements?|submissions?|claims?|questions?|answers?|faqs?|'
    r'check[ -]ins?|history|histories|tasks?|progress|deadlines?|links?|content|'
    r'text|slides?|jobs?|transactions?|credits?|costs?|pages?|rooms?|buildings?|'
    r'locations?|reports?|attendance|attendees|resources?|status|states?'
)
FUNCTION_VERBS = {
    'Maintain information': (
        r'capture|collect|curate|create|edit|update|maintain|record|register|log|'
        r'store|save|upload|publish|prepare|keep|correct|revoke|delete'
    ),
    'Retrieve information': (
        r'search|look up|lookup|browse|filter|find|retrieve|list|display|show|view|'
        r'present|review|inspect|export'
    ),
    'Coordinate requests or transactions': (
        r'assign|approve|reject|confirm|cancel|reserve|book|schedule|dispatch|'
        r'verify|route|reschedule|handle|queue|mark|track|check|calculate'
    ),
}
FUNCTION_PATTERNS = {
    # An imperative or an explicit verb construction prevents nouns such as
    # "book records" and "search accuracy" from becoming operational actions.
    family: re.compile(r'(?:^|\b(?:to|and|can|shall|will|must)\s+)'
                       r'(?P<operation>(?:' + verbs + r')\b[^.!?;\n]{0,100}?\b(?:' + ENTITIES + r')\b)', re.I)
    for family, verbs in FUNCTION_VERBS.items()
}
UNSUPPORTED = re.compile(
    r'\b(?:may|might|could|consider|perhaps|possibly|future work|out of scope|'
    r'not (?:implemented|included|supported|planned)|does not|do not|will not|'
    r'without implementing|prior stud(?:y|ies)|manually|handwritten|paper[ -]based)\b', re.I,
)
DEVELOPMENT_TASK = re.compile(r'\b(?:prototype|wireframes?|testing|accuracy|requirements|validation|research)\b', re.I)


def concept_function_evidence(text, chunks):
    """Require two different operations in separate proposed-function passages.

    For example, retrieving a catalog and updating its entries establish an
    information workflow without claiming that it uses a browser or mobile app.
    Repeating the same retrieval operation cannot supply the second function.
    """
    if not (re.search(r'\b(?:concept paper|project proposal)\b', text[:2000], re.I) or
            any(c['section'].lower().startswith('proposed system') for c in chunks)):
        return []
    passages = []
    for chunk in chunks:
        if chunk['section'].lower() not in FUNCTION_SECTIONS:
            continue
        if passages and passages[-1]['section'] == chunk['section']:
            passages[-1]['text'] += ' ' + chunk['text']
        else:
            passages.append(dict(chunk))
    hits = []
    for passage in passages:
        # Rejoin PDF line wraps before splitting sentences and bullet points.
        for sentence in re.split(r'(?<=[.!?])\s+|[\u2022\ufffd]', passage['text']):
            sentence = sentence.strip()
            if not sentence or UNSUPPORTED.search(sentence):
                continue
            for family, pattern in FUNCTION_PATTERNS.items():
                match = pattern.search(sentence)
                if not match or DEVELOPMENT_TASK.search(match['operation']):
                    continue
                start = max(0, match.start() - 80)
                hits.append({'label': 'Information Systems', 'term': match['operation'],
                             'function': family, 'section': passage['section'],
                             'excerpt': sentence[start:start + 360]})
    independent = []
    for hit in hits:
        if any(hit['function'] == prior['function'] or hit['excerpt'] == prior['excerpt']
               for prior in independent):
            continue
        independent.append(hit)
    return independent if len(independent) >= 2 else []
