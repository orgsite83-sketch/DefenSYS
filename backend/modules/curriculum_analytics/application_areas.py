"""Document-backed project purposes, separate from computing focus and domain.

These deterministic labels describe the intended service, not an implemented
platform or a model prediction. Two different groups of supporting terms must
occur in substantive passages; cover pages and general campus boilerplate do
not establish an area. Unknown or tied purposes remain explicit.
"""
import re

from repository.deliverables.project_classification import _term_pattern, matches
from repository.deliverables.concept_focus import UNSUPPORTED
from repository.deliverables.manuscript_sections import manuscript_sections


UNRESOLVED_AREA = 'Unresolved application area'
AREA_VERSION = 'application-area-2.1'
AREA_SIGNALS = {
    'Library & Resource Services': (
        ('library', 'librarian', 'librarians'),
        ('book', 'books', 'catalog', 'circulation', 'study pod', 'study-pod'),
    ),
    'Learning & Academic Support': (
        ('tutoring', 'tutors', 'peer mentor', 'peer mentors', 'mentorship', 'study group', 'study groups', 'faculty mentoring', 'mentors', 'mentees'),
        ('subjects', 'subject', 'sessions', 'session', 'availability', 'topics', 'professional development', 'coaching'),
    ),
    'Events & Community Engagement': (
        ('event management', 'event scoring', 'event registration', 'events', 'club', 'clubs', 'student organization', 'student organizations'),
        ('attendance', 'registration', 'recruitment', 'award', 'awards', 'activities', 'scoring', 'tabulation', 'booking'),
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
         'bulletin', 'announcement', 'announcements', 'digital signage', 'document management', 'document tracking', 'document routing', 'record management', 'record classification', 'record classifier'),
        ('version', 'versions', 'publishing', 'publishers', 'notices', 'screen', 'screens', 'slides', 'effective date', 'forms', 'tracking', 'routing', 'classification', 'documents', 'records'),
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
        ('cafeteria', 'dining', 'meal', 'meals', 'menu', 'menus', 'eatery', 'eateries', 'restaurant', 'restaurants'),
        ('vendor', 'vendors', 'stall', 'stalls', 'dish', 'dishes', 'prices', 'price', 'orders', 'ordering', 'pos', 'transactions'),
    ),
    'Printing Services': (
        ('printing', 'print', 'print-job', 'print job', 'print-shop'),
        ('credits', 'credit', 'queue', 'pickup', 'job'),
    ),
    'Agriculture & Farming': (
        ('agriculture', 'agricultural', 'farm', 'farmers', 'farming', 'crop', 'crops', 'livestock', 'aquaculture'),
        ('irrigation', 'soil moisture', 'harvest', 'pest', 'plant disease', 'feeding', 'yield', 'soil nutrients'),
    ),
    'Environment & Waste Management': (
        ('waste', 'garbage', 'recyclable', 'recycling', 'pollution', 'flood', 'water quality', 'air quality'),
        ('sorting', 'segregation', 'collection', 'disposal', 'material identification', 'monitoring', 'alerts', 'classification'),
    ),
    'Healthcare Services': (
        ('patient', 'patients', 'hospital', 'clinic', 'medical', 'healthcare'),
        ('triage', 'appointments', 'diagnosis', 'bed availability', 'patient transfers', 'health records', 'patient intake', 'admission', 'laboratory', 'x-ray', 'radiology'),
    ),
    'Transport & Logistics': (
        ('transport', 'transportation', 'fleet', 'freight', 'logistics', 'commuter', 'commuters', 'vehicle', 'vehicles', 'delivery service', 'parcel', 'parcels'),
        ('route', 'routes', 'dispatch', 'tracking', 'trip', 'trips', 'shipment', 'shipments', 'booking'),
    ),
    'Commerce & Inventory': (
        ('retail', 'store', 'shop', 'sales', 'inventory', 'e-commerce', 'ecommerce', 'marketplace'),
        ('stock', 'orders', 'checkout', 'products', 'purchase', 'purchases', 'transactions', 'point of sale', 'supply', 'supplies', 'distribution', 'tracking', 'selling'),
    ),
    'Finance & Payments': (
        ('finance', 'financial', 'accounting', 'loan', 'loans', 'budget', 'payroll', 'billing', 'invoice', 'invoices'),
        ('payments', 'expenses', 'ledger', 'salary', 'salaries', 'repayment', 'disbursement', 'transactions', 'charges', 'financial records'),
    ),
    'Public Safety & Emergency Response': (
        ('emergency', 'disaster', 'fire', 'crime', 'rescue', 'evacuation'),
        ('alerts', 'reporting', 'response', 'dispatch', 'incident', 'incidents', 'shelter', 'shelters'),
    ),
    'Government & Public Services': (
        ('barangay', 'municipal', 'municipality', 'government', 'citizen', 'citizens'),
        ('permits', 'permit', 'certificates', 'civil registry', 'service requests', 'complaints', 'resident records'),
    ),
    'Academic Administration': (
        ('enrollment', 'admissions', 'registrar', 'curriculum', 'capstone', 'thesis', 'academic records', 'faculty', 'academic leadership'),
        ('grades', 'grading', 'scheduling', 'evaluation', 'defense', 'student records', 'course registration', 'self-assessment', 'rank upgrade', 'reclassification', 'reporting'),
    ),
    'Careers & Employment': (
        ('alumni', 'employment', 'internship', 'internships', 'job seekers', 'interview coach', 'career readiness'),
        ('career', 'careers', 'vacancies', 'applications', 'placement', 'employment records', 'career history', 'interview skills', 'interview simulations', 'attendance'),
    ),
    'Tourism & Hospitality': (
        ('tourism', 'tourist', 'tourists', 'hotel', 'hotels', 'resort', 'resorts', 'homestay'),
        ('booking', 'bookings', 'reservation', 'reservations', 'itinerary', 'accommodation', 'destinations', 'registration', 'trip organization', 'tourism information', 'destination planning'),
    ),
    'Security & Access Management': (
        ('cybersecurity', 'intrusion', 'malware', 'vulnerability', 'vulnerabilities', 'threat hunting', 'penetration testing'),
        ('detection', 'prevention', 'verification', 'threat', 'threats', 'penetration testing', 'incident response'),
    ),
    'Workforce & Personnel Services': (
        ('human resource', 'hrms', 'employee', 'employees', 'personnel', 'workforce', 'daily time record'),
        ('attendance', 'time record', 'recruitment', 'selection', 'placement', 'leave', 'training', 'payroll'),
    ),
    'Pharmacy & Medication Services': (
        ('pharmacy', 'pharmacies', 'pharmacist', 'pharmacists'),
        ('dispensing', 'medicine', 'medication', 'prescription', 'drug', 'drugs'),
    ),
    'Legal & Case Management': (
        ('legal', 'law office', 'law firm', 'attorney', 'litigation'),
        ('case', 'cases', 'hearing', 'court', 'client data', 'case documents'),
    ),
    'Elections & Voting': (
        ('election', 'elections', 'electoral', 'voting'),
        ('ballot', 'ballots', 'votes', 'voters', 'candidates', 'vote tally', 'voter'),
    ),
    'Social Welfare & Assistance': (
        ('social work', 'social welfare', 'social assistance'),
        ('assistance', 'eligibility', 'beneficiaries', 'case records', 'patient', 'patients', 'documents'),
    ),
    'Construction & Project Operations': (
        ('construction', 'contractor', 'contractors', 'civil engineering'),
        ('monitoring', 'progress', 'site', 'projects', 'costs', 'materials', 'operations'),
    ),
    'Community & Institutional Administration': (
        ('parish', 'church', 'student government', 'e-governance', 'gender and development'),
        ('operations', 'services', 'workflows', 'administration', 'appointments', 'records', 'management'),
    ),
}
# Explicit taxonomy inheritance resolves a specialised service alongside its
# generic workflow only at the same evidence priority. Titles never override.
AREA_REFINEMENTS = {
    'Pharmacy & Medication Services': {'Healthcare Services', 'Commerce & Inventory'},
    'Social Welfare & Assistance': {'Healthcare Services', 'Information & Document Services'},
    'Legal & Case Management': {'Information & Document Services'},
    'Food & Dining Services': {'Commerce & Inventory', 'Finance & Payments'},
    'Workforce & Personnel Services': {'Careers & Employment'},
    'Construction & Project Operations': {'Commerce & Inventory', 'Finance & Payments', 'Transport & Logistics'},
    'Healthcare Services': {'Information & Document Services', 'Printing Services', 'Commerce & Inventory'},
    'Learning & Academic Support': {'Academic Administration'},
    'Community & Institutional Administration': {'Information & Document Services', 'Events & Community Engagement'},
}
PURPOSE_SECTIONS = {
    'abstract', 'project description', 'project purpose', 'objectives',
    'project objectives', 'specific objectives', 'general objectives',
    'proposed system features', 'proposed system and key functions',
    'system features', 'functional requirements', 'main features',
    'system functionality', 'target beneficiaries',
    'target users and information requirements', 'implementation',
}
CONTEXT_SECTIONS = {
    'abstract', 'project description', 'background', 'background of the study',
    'background of study', 'background and rationale', 'introduction',
    'introduction / background', 'problem statement', 'statement of the problem',
}
def purpose_passages(text):
    """Prioritise the declared general objective over secondary modules.

    The shared parser excludes front matter and Chapter II and preserves
    page/section provenance. Area evidence has no learned probability.
    """
    passages = []
    for passage in manuscript_sections(text):
        if passage['section'].lower() not in PURPOSE_SECTIONS | CONTEXT_SECTIONS:
            continue
        # Some papers put the general aim and the list of specific goals under
        # one heading. Keep all text, but do not give the feature list the same
        # precedence as the declared main purpose.
        marker = re.search(r'\b(?:specifically|specific\s*objectives|the following (?:goals|objectives)|'
                           r'to achieve (?:the |this )?general objective)\b|[\uf0b7\uf06c]', passage['text'], re.I)
        if passage['tier'] >= 3 and marker:
            before, after = passage['text'][:marker.start()].strip(), passage['text'][marker.start():].strip()
            if before:
                passages.append({**passage, 'text': before})
            if after:
                passages.append({**passage, 'text': after, 'tier': 2})
        else:
            passages.append(passage)
    for passage in passages:
        passage['text'] = ' '.join(sentence for sentence in re.split(
            r'(?<=[.!?])\s+|[\u2022\ufffd]', passage['text']) if not UNSUPPORTED.search(sentence))
    return [p for p in passages if p['text']]


def _result(label=UNRESOLVED_AREA, evidence=None, *, code, reason, candidates=None, candidate_evidence=None):
    return {
        'application_area': label, 'application_area_evidence': evidence or [],
        'application_area_status': 'estimated' if label != UNRESOLVED_AREA else 'unresolved',
        'application_area_reason_code': code, 'application_area_reason': reason,
        'application_area_candidates': candidates or [],
        'application_area_candidate_evidence': candidate_evidence or [],
        'application_area_method': 'document_rules', 'application_area_version': AREA_VERSION,
    }


def application_area(documents, primary_id=None, *, source_reason=None):
    """Use one source document, preferring the current computing-focus source.

    Copies never add votes. Supporting text must identify both the service and
    its specific activity. Broad words such as student, school or campus are
    deliberately absent from the taxonomy.
    """
    if not documents:
        code = source_reason if source_reason in ('no_documents', 'unreadable', 'unrelated_documents') else 'no_documents'
        reasons = {
            'no_documents': 'No eligible project manuscript is linked to this period and project version.',
            'unreadable': 'The current files have no readable extracted text. Check PDF text extraction.',
            'unrelated_documents': 'The extracted text does not match the recorded project topic.',
        }
        return _result(code=code, reason=reasons[code])
    documents = sorted(documents, key=lambda d: (d['id'] == primary_id, d.get('uploaded_at', '')), reverse=True)
    has_text = has_passages = False
    for document in documents:
        text = document.get('_raw_text', '')
        if len(re.sub(r'\s+', '', text)) < 40:
            continue
        has_text = True
        passages = purpose_passages(text)
        has_passages |= bool(passages)
        candidates = []
        for label, families in AREA_SIGNALS.items():
            # Two cue families must occur within the same section/page; a
            # mention in beneficiaries cannot combine with unrelated context.
            for passage in sorted(passages, key=lambda p: -p['tier']):
                hits = [next((term for term in terms if matches(passage['text'], term)), None)
                        for terms in families]
                if not all(hits) or len(set(hits)) != len(families):
                    continue
                if (label == 'Information & Document Services' and
                        hits[0] in ('bulletin', 'announcement', 'announcements') and
                        not any(matches(passage['text'], term) for term in
                                ('publishing', 'publish', 'published', 'publishers', 'version', 'versions', 'effective date'))):
                    # Sending alerts or tracking applications does not make
                    # document publishing the purpose of an unrelated service.
                    continue
                evidence = []
                for term in hits:
                    # Keep the actual matching passage for the evidence viewer.
                    position = _term_pattern(term).search(passage['text']).start()
                    start = max(0, position - 100)
                    evidence.append({'label': label, 'term': term, 'section': passage['section'], 'page': passage['page'],
                                     'excerpt': passage['text'][start:start + 360],
                                     'document_id': document['id'], 'source_label': document['display_name']})
                candidates.append((label, evidence, passage['tier']))
                break
        if candidates:
            tier = max(c[2] for c in candidates)
            candidates = [c for c in candidates if c[2] == tier]
            refinements = set().union(*(AREA_REFINEMENTS.get(c[0], set()) for c in candidates))
            candidates = [c for c in candidates if c[0] not in refinements]
        if len(candidates) == 1:
            label, evidence, _ = candidates[0]
            return _result(label, evidence, code='supported',
                           reason=f'Estimated {label} from purpose evidence in {evidence[0]["section"]}.')
        if candidates:
            # A conflicting primary source cannot be resolved by an older copy.
            labels = [c[0] for c in candidates]
            return _result(code='ambiguous', reason='The source supports multiple application areas: ' +
                           ', '.join(labels) + '. Review the primary project purpose.', candidates=labels,
                           candidate_evidence=[{'label': label, 'priority': tier, 'evidence': hits}
                                               for label, hits, tier in candidates])
    if not has_text:
        return _result(code='unreadable', reason='The current files have no readable extracted text. Check PDF text extraction.')
    if not has_passages:
        return _result(code='missing_purpose_sections', reason='No readable purpose, objectives, functions or context passages were found outside excluded sections.')
    return _result(code='unsupported_area', reason='Readable project passages do not provide both service and activity evidence for a supported application area.')
