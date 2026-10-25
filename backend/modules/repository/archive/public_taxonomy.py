"""Controlled public-library facets, derived from eligible published evidence.

No model training, network access, or database writes. Keywords remain search
terms; only supported catalogue IDs become public filters. This rule vocabulary
is versioned and testable, not a claim of measured classification accuracy.
"""
import hashlib
import json
import re
from collections import OrderedDict, defaultdict
from copy import deepcopy
from threading import Lock

from repository.deliverables.project_classification import matches, section_chunks


VERSION = 'public-library-1'
UNSPECIFIED = 'unspecified'
SUBJECTS = {
    'sports-fitness': ('Sports & Fitness',
        ('sport', 'sports', 'athlete', 'athletes', 'basketball', 'football', 'fitness', 'volleyball'),
        ('training', 'tournament', 'exercise', 'coaching', 'league', 'workout', 'scheduling', 'booking')),
    'health-wellbeing': ('Health & Wellbeing',
        ('health', 'healthcare', 'hospital', 'patient', 'patients', 'wellness', 'mental health', 'clinic'),
        ('patient records', 'clinical', 'diagnosis', 'triage', 'treatment', 'pharmacy', 'bed availability',
         'admission', 'admissions', 'counseling', 'counselling', 'check-in', 'reflection', 'care', 'appointments')),
    'education': ('Education',
        ('school', 'university', 'campus', 'academic', 'students', 'student', 'learning', 'alumni'),
        ('enrollment', 'admissions', 'curriculum', 'course', 'courses', 'tutoring', 'learning materials',
         'academic records', 'student records', 'grades', 'library', 'seminar', 'attendance', 'orientation',
         'graduation', 'mentorship', 'handbook', 'inquiries', 'classroom', 'employment records')),
    'business-finance': ('Business & Finance',
        ('business', 'customer', 'customers', 'retail', 'vendor', 'vendors', 'sales', 'financial', 'finance'),
        ('payment', 'payments', 'billing', 'inventory', 'purchase orders', 'checkout', 'transactions',
         'accounting', 'budget', 'prices', 'payroll', 'orders', 'stock', 'banking')),
    'agriculture-environment': ('Agriculture & Environment',
        ('agriculture', 'agricultural', 'farm', 'farmers', 'crop', 'crops', 'environmental', 'pollution'),
        ('soil', 'irrigation', 'greenhouse', 'water quality', 'air quality', 'harvest', 'moisture',
         'waste management', 'recycling', 'biodiversity', 'emissions')),
    'public-services': ('Public Services',
        ('municipal', 'government', 'barangay', 'public service', 'public safety', 'disaster', 'emergency'),
        ('permit', 'permits', 'citizen', 'citizens', 'response', 'evacuation', 'hazard', 'relief',
         'service requests', 'civil records', 'rescue')),
    'entertainment': ('Entertainment',
        ('game', 'gaming', 'entertainment', 'music', 'film', 'multiplayer'),
        ('player', 'players', 'gameplay', 'game mechanics', 'playable', 'streaming', 'playlist', 'audience')),
    'computing-it': ('Computing & IT',
        ('cybersecurity', 'network', 'cloud infrastructure', 'database engine', 'developer', 'software engineering'),
        ('vulnerability', 'penetration testing', 'intrusion detection', 'routing', 'bandwidth',
         'resource provisioning', 'query optimization', 'code analysis', 'debugging', 'malware')),
    'transport-logistics': ('Transport & Logistics',
        ('transport', 'transportation', 'logistics', 'fleet', 'vehicle', 'vehicles', 'delivery'),
        ('route', 'routes', 'dispatch', 'traffic', 'shipment', 'shipments', 'trip', 'trips', 'tracking')),
    'tourism-hospitality': ('Tourism & Hospitality',
        ('tourism', 'tourist', 'hotel', 'hospitality', 'resort', 'guest', 'guests'),
        ('room availability', 'reservation', 'reservations', 'booking', 'check-in', 'occupancy', 'itinerary')),
}
TECHNOLOGIES = {
    'web': ('Web Applications', ('web application', 'web app', 'web-based', 'web portal', 'website', 'browser-based')),
    'mobile': ('Mobile Applications', ('mobile application', 'mobile app', 'android application', 'android app',
        'ios application', 'ios app', 'smartphone application', 'smartphone app')),
    'iot-embedded': ('IoT & Embedded Systems', ('internet of things', 'iot', 'embedded system',
        'embedded device', 'microcontroller', 'sensor network')),
    'ai-ml': ('AI & Machine Learning', ('machine learning', 'deep learning', 'neural network',
        'artificial intelligence', 'model training')),
    'data-analytics': ('Data Analytics', ('data analytics', 'data analysis', 'statistical analysis',
        'business intelligence', 'data visualization')),
    'games': ('Games', ('game development', 'game engine', 'game mechanics', 'gameplay', 'playable game')),
    'desktop': ('Desktop Applications', ('desktop application', 'desktop app', 'standalone desktop')),
    'cloud': ('Cloud Infrastructure', ('cloud infrastructure', 'cloud storage', 'cloud computing',
        'serverless', 'distributed storage', 'cloud hosting')),
    'cybersecurity': ('Cybersecurity', ('penetration testing', 'vulnerability scanner', 'intrusion detection',
        'malware detection', 'threat hunting')),
    'networks': ('Networking', ('network monitoring', 'network administration', 'network topology',
        'routing protocol', 'network infrastructure')),
}
LANGUAGES = {
    'python': ('Python', ('python',)),
    'javascript': ('JavaScript', ('javascript', 'java script', 'ecmascript')),
    'typescript': ('TypeScript', ('typescript', 'type script')),
    'dart': ('Dart', ('dart',)),
    'java': ('Java', ('java',)),
    'php': ('PHP', ('php',)),
    'csharp': ('C#', ('c#', 'c sharp', 'csharp')),
    'cpp': ('C++', ('c++', 'c plus plus')),
    'c': ('C', ('c programming language', 'c language', 'programmed in c', 'written in c')),
    'kotlin': ('Kotlin', ('kotlin',)),
    'swift': ('Swift', ('swift',)),
    'go': ('Go', ('golang', 'go programming language', 'written in go', 'programmed in go')),
    'rust': ('Rust', ('rust',)),
    'ruby': ('Ruby', ('ruby',)),
    'r': ('R', ('r programming language', 'r language', 'r statistical', 'written in r')),
    'sql': ('SQL', ('sql', 'structured query language')),
    'matlab': ('MATLAB', ('matlab',)),
}
CATALOGUES = {'subject': SUBJECTS, 'technology': TECHNOLOGIES, 'language': LANGUAGES}
PURPOSE_SECTIONS = {
    'abstract', 'introduction', 'introduction/background', 'background', 'background and rationale',
    'background of the study', 'background of study', 'project description', 'project purpose',
    'objectives', 'project objectives', 'specific objectives', 'general objectives',
    'proposed system features', 'proposed system and key functions', 'system features',
    'functional requirements', 'main features', 'system functionality',
    'target beneficiaries', 'target users and information requirements',
}
TECH_SECTIONS = PURPOSE_SECTIONS | {'methodology', 'technical architecture', 'technology stack',
    'implementation', 'results', 'proposed development and validation plan'}
UNSUPPORTED = re.compile(
    r'\b(?:may|might|could|consider(?:ing|ed)?|perhaps|possibly|future work|out of scope|'
    r'not (?:implemented|included|supported|planned|used)|does not|do not|will not|'
    r'without (?:implementing|using)|prior stud(?:y|ies)|previous research|according to|'
    r'for example|such as|e\.g\.)\b', re.I)
NEGATED = re.compile(r'\b(?:no|not|neither|nor|rather than|instead of|excluding|replaced)\b', re.I)
PROPOSED = re.compile(r'\b(?:proposed|will|shall|aims? to|plans? to)\b', re.I)
LANGUAGE_ASSERTION = re.compile(
    r'\b(?:(?:written|programmed|coded|developed|implemented|built)\s+(?:in|using|with)|'
    r'uses?|using|(?:backend|frontend|language|languages|stack|code)\s*[:=])\s*(.+)', re.I)
ADMIN_DOCUMENT = re.compile(r'minutes|rubric|evaluation|certificate|attendance sheet|consent|approval form', re.I)
_CACHE, _LOCK = OrderedDict(), Lock()


def _passages(text):
    # Normalize additional manuscript headings before the shared section parser.
    # A chapter break or literature heading must not inherit an earlier purpose.
    text = re.sub(r'(?im)^\s*(?:\d+(?:\.\d+)*[.)]?\s+)?'
                  r'(?:review of related (?:literature|studies|work)|related studies|'
                  r'chapter\s+(?:\d+|[ivx]+))\s*[:.]?\s*$', '\nReferences\n', text)
    joined = []
    for chunk in section_chunks(text):
        if joined and joined[-1]['section'] == chunk['section']:
            joined[-1]['text'] += ' ' + chunk['text']
        else:
            joined.append(dict(chunk))
    for chunk in joined:
        # Rejoin PDF wraps before checking tentative or negated assertions.
        for sentence in re.split(r'(?<=[.!?])\s+(?=[A-Z])|[•\ufffd]', chunk['text']):
            if (UNSUPPORTED.search(sentence) or NEGATED.search(sentence)
                    or re.search(r'\[\d[\d,\s–-]*\]|\bet al\.|\(\d{4}\)', sentence)):
                continue
            # Explicit stack lists can be a single short language name (R, Go, C).
            # Keep the substantive-passage threshold for narrative sections.
            if len(sentence.strip()) >= 25 or (
                    chunk['section'].lower() == 'technology stack' and sentence.strip()):
                yield {**chunk, 'text': sentence.strip()}


def _document_tags(entry):
    found = {group: {} for group in CATALOGUES}
    for passage in _passages(entry.get('extracted_text') or ''):
        section = passage['section'].lower()
        text = passage['text']
        if section in PURPOSE_SECTIONS:
            for key, (label, contexts, activities) in SUBJECTS.items():
                context = next((term for term in contexts if matches(text, term)), None)
                activity = next((term for term in activities if matches(text, term)), None)
                if context and activity and context != activity:
                    found['subject'][key] = {'id': key, 'label': label, 'status': 'documented'}
        if section not in TECH_SECTIONS:
            continue
        status = 'proposed' if (entry.get('document_kind') in ('concept', 'chapters')
            or 'proposed' in section or PROPOSED.search(text)) else 'documented'
        for key, (label, terms) in TECHNOLOGIES.items():
            if any(matches(text, term) for term in terms):
                _merge_tag(found['technology'], {'id': key, 'label': label, 'status': status})
        assertion = LANGUAGE_ASSERTION.search(text)
        language_text = text if section == 'technology stack' else (assertion[1] if assertion else '')
        if language_text:
            for key, (label, terms) in LANGUAGES.items():
                supported = (bool(re.search(r'\bc(?![+#\w])', language_text, re.I)) if key == 'c'
                             else any(matches(language_text, term) for term in terms))
                if key in ('go', 'r'):
                    supported = supported or bool(re.search(
                        r'(?:^|[,;&]|\band\s+)\s*' + re.escape(label) + r'(?!\w)', language_text))
                    supported = supported or (section == 'technology stack' and matches(language_text, label))
                if supported:
                    # Single-letter C must not also match C++ or C#.
                    if key == 'c' and not (section == 'technology stack' or re.match(r'c(?![+#\w])', language_text, re.I)
                            or re.search(r'\bc (?:programming language|language)\b|\b(?:programmed|written) in c(?![+#\w])', text, re.I)):
                        continue
                    if key in ('rust', 'swift', 'dart') and re.search(
                            r'\b(?:rust (?:on|samples|detection)|swift (?:payment|bank|network)|dart (?:board|game|throw))\b',
                            language_text, re.I):
                        continue
                    _merge_tag(found['language'], {'id': key, 'label': label, 'status': status})
    return found


def _merge_tag(target, tag):
    if tag['id'] not in target or tag['status'] == 'documented':
        target[tag['id']] = tag


def _project_tags(entries):
    documents = [e for e in entries if e.get('document_kind') in ('concept', 'chapters', 'final', 'document')
        and not ADMIN_DOCUMENT.search(str(e.get('deliverable_label') or e.get('file_name') or ''))]
    priorities = {'final': 3, 'chapters': 2, 'concept': 1, 'document': 0}
    stage = max((priorities[e['document_kind']] for e in documents), default=-1)
    documents = [e for e in documents if priorities[e['document_kind']] == stage]
    fingerprint = hashlib.sha256(json.dumps([
        (e.get('document_kind'), e.get('deliverable_label'), e.get('extracted_text') or '')
        for e in documents], ensure_ascii=False, sort_keys=True).encode()).hexdigest()
    cache_key = (VERSION, fingerprint)
    with _LOCK:
        cached = _CACHE.get(cache_key)
        if cached is not None:
            _CACHE.move_to_end(cache_key)
            return deepcopy(cached)
    merged, seen = {group: {} for group in CATALOGUES}, set()
    for entry in documents:
        digest = hashlib.sha256((entry.get('extracted_text') or '').encode()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        for group, tags in _document_tags(entry).items():
            for tag in tags.values():
                _merge_tag(merged[group], tag)
    result = {group: sorted(tags.values(), key=lambda t: t['label']) for group, tags in merged.items()}
    with _LOCK:
        _CACHE[cache_key] = deepcopy(result)
        while len(_CACHE) > 256:
            _CACHE.popitem(last=False)
    return result


def enrich_public_tags(entries):
    """Call only after access checks and project identities have been resolved."""
    projects = defaultdict(list)
    for entry in entries:
        projects[entry.get('project_key') or f"entry:{entry['id']}"].append(entry)
    for files in projects.values():
        tags = _project_tags(files)
        for entry in files:
            entry['library_tags'] = deepcopy(tags)
            entry['library_taxonomy_version'] = VERSION
    return entries


def selected_values(params, group):
    raw = params.get(group, '') if hasattr(params, 'get') else ''
    return {part.strip() for part in str(raw or '').split(',') if part.strip()}


def matches_public_tags(entry, params):
    for group in CATALOGUES:
        selected = selected_values(params, group)
        available = {tag['id'] for tag in entry.get('library_tags', {}).get(group, [])} or {UNSPECIFIED}
        if selected and not selected.intersection(available):
            return False
    return True


def public_facets(entries, params):
    """Disjunctive counts: apply other groups, count each visible project once."""
    from .ml_search import _apply_standard_filters, matches_search
    result = {}
    for group, catalogue in CATALOGUES.items():
        query = {key: params.get(key) for key in params if key != group}
        counts = defaultdict(set)
        for entry in entries:
            if not _apply_standard_filters(entry, query) or not matches_search(entry, str(query.get('search') or '')):
                continue
            ids = {t['id'] for t in entry.get('library_tags', {}).get(group, [])} or {UNSPECIFIED}
            for tag_id in ids:
                counts[tag_id].add(entry.get('project_key') or f"entry:{entry['id']}")
        for value in selected_values(params, group):
            if value in catalogue or value == UNSPECIFIED:
                counts.setdefault(value, set())
        result[group] = sorted([
            {'id': key, 'label': catalogue[key][0] if key in catalogue else 'Not specified', 'count': len(projects)}
            for key, projects in counts.items()
        ], key=lambda t: (-t['count'], t['label']))
    return result
