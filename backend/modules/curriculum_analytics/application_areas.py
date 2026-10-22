"""Document-backed project purposes, separate from computing focus and domain.

These deterministic labels describe the intended service, not an implemented
platform or a model prediction. Two different groups of supporting terms must
occur in substantive passages; cover pages and general campus boilerplate do
not establish an area. Unknown or tied purposes remain explicit.
"""
import re

from repository.deliverables.project_classification import _term_pattern, matches, section_chunks
from repository.deliverables.concept_focus import UNSUPPORTED


UNRESOLVED_AREA = 'Unresolved application area'
AREA_SIGNALS = {
    'Library & Resource Services': (
        ('library', 'librarian', 'librarians'),
        ('book', 'books', 'catalog', 'circulation', 'study pod', 'study-pod'),
    ),
    'Learning & Academic Support': (
        ('tutoring', 'tutors', 'peer mentor', 'peer mentors', 'mentorship', 'study group', 'study groups'),
        ('subjects', 'subject', 'sessions', 'session', 'availability', 'topics'),
    ),
    'Events & Community Engagement': (
        ('event', 'events', 'club', 'clubs', 'organization', 'organizations', 'badge', 'badges'),
        ('attendance', 'registration', 'recruitment', 'milestone', 'milestones', 'award', 'awards', 'interests', 'activities'),
    ),
    'Health & Wellbeing': (
        ('wellness', 'mental health', 'counseling', 'counselling'),
        ('check-in', 'check in', 'feelings', 'reflection', 'support resources', 'support-resource'),
    ),
    'Helpdesk & Inquiries': (
        ('faq', 'faqs', 'helpdesk', 'inquiry', 'inquiries'),
        ('ticket', 'tickets', 'questions', 'answers', 'resolved'),
    ),
    'Information & Document Services': (
        ('handbook', 'handbooks', 'document library', 'document repository', 'forms repository',
         'bulletin', 'announcement', 'announcements', 'digital signage'),
        ('version', 'versions', 'publishing', 'publishers', 'notices', 'screen', 'screens', 'slides', 'effective date', 'forms'),
    ),
    'Onboarding & Orientation': (
        ('onboarding', 'orientation timeline', 'orientation navigator', 'orientation checklist'),
        ('checklist', 'before-arrival', 'first-day', 'first-week', 'deadlines', 'tasks'),
    ),
    'Lost & Found Services': (
        ('lost', 'found', 'lost/found', 'lost-and-found'),
        ('claim', 'claims', 'custody', 'ownership', 'handover'),
    ),
    'Food & Dining Services': (
        ('cafeteria', 'dining', 'meal', 'meals', 'menu', 'menus'),
        ('vendor', 'vendors', 'stall', 'stalls', 'dish', 'dishes', 'prices', 'price'),
    ),
    'Printing Services': (
        ('printing', 'print', 'print-job', 'print job', 'print-shop'),
        ('credits', 'credit', 'queue', 'pickup', 'job'),
    ),
}
PURPOSE_SECTIONS = {
    'abstract', 'project description', 'project purpose', 'objectives',
    'project objectives', 'specific objectives', 'general objectives',
    'proposed system features', 'proposed system and key functions',
    'system features', 'functional requirements', 'main features',
    'system functionality', 'target beneficiaries',
    'target users and information requirements', 'implementation',
}


def application_area(documents, primary_id=None):
    """Use one source document, preferring the current computing-focus source.

    Copies never add votes. Supporting text must identify both the service and
    its specific activity. Broad words such as student, school or campus are
    deliberately absent from the taxonomy.
    """
    documents = sorted(documents, key=lambda d: (d['id'] == primary_id, d.get('uploaded_at', '')), reverse=True)
    for document in documents:
        chunks = [c for c in section_chunks(document.get('_raw_text', ''))
                  if c['section'].lower() in PURPOSE_SECTIONS]
        # Rejoin PDF line wraps without crossing section boundaries.
        passages = []
        for chunk in chunks:
            if passages and passages[-1]['section'] == chunk['section']:
                passages[-1]['text'] += ' ' + chunk['text']
            else:
                passages.append(dict(chunk))
        passages = [{**p, 'text': ' '.join(sentence for sentence in re.split(r'(?<=[.!?])\s+|[\u2022\ufffd]', p['text'])
                                          if not UNSUPPORTED.search(sentence))} for p in passages]
        candidates = []
        for label, families in AREA_SIGNALS.items():
            evidence = []
            for terms in families:
                hit = next(((term, passage) for passage in passages for term in terms
                            if matches(passage['text'], term)), None)
                if hit:
                    term, passage = hit
                    # Keep the actual matching passage for the evidence viewer.
                    position = _term_pattern(term).search(passage['text']).start()
                    start = max(0, position - 100)
                    evidence.append({'label': label, 'term': term, 'section': passage['section'],
                                     'excerpt': passage['text'][start:start + 360],
                                     'document_id': document['id'], 'source_label': document['display_name']})
            if len(evidence) == len(families):
                candidates.append((label, evidence))
        if len(candidates) == 1:
            label, evidence = candidates[0]
            return {'application_area': label, 'application_area_evidence': evidence}
        if candidates:
            # A conflicting primary source cannot be resolved by an older copy.
            break
    return {'application_area': UNRESOLVED_AREA, 'application_area_evidence': []}
