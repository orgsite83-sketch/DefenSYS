"""Project archive projection for the one approved shared-system final paper."""
from defense.document_policy import is_approved_concept
from repository.archive.models import ArchiveEntry
from repository.section_concepts.models import SectionConceptPaper
from repository.deliverables.services import display_name, get_deliverable_definitions_for_scope
from repository.entry_payloads import empty_ml_fields


def shared_final_entries(scope, request=None):
    if scope['scope'] not in ('admin', 'pit_lead'):
        return []
    papers = SectionConceptPaper.objects.filter(purpose='final', is_current=True, status='accepted').select_related(
        'concept__round__project__section__semester__school_year', 'concept__round__project__pit_event_config',
        'concept__round__project__defense_stage', 'uploaded_by')
    if scope['scope'] == 'pit_lead':
        papers = papers.filter(concept__round__project__pit_event_config__isnull=False,
            concept__round__project__section__year_level=scope.get('pit_year_level') or '')
    result = []
    for paper in papers:
        project = paper.concept.round.project
        semester = project.section.semester
        context = project.context
        pit = bool(project.pit_event_config_id)
        definitions = get_deliverable_definitions_for_scope('pit' if pit else 'capstone', semester.pk,
            context.label, year_level=project.section.year_level)
        definition = next((d for d in definitions if is_approved_concept(d)), {})
        result.append({
            'id': f'section-final-{paper.pk}', 'source_id': paper.pk, 'file_id': paper.pk,
            'type': ArchiveEntry.TYPE_PIT if pit else ArchiveEntry.TYPE_CAPSTONE,
            'file_name': paper.file_name, 'file_size': '',
            'file_url': (request.build_absolute_uri(f'/api/repository/section-concepts/{project.pk}/papers/{paper.pk}/')
                if request else f'/api/repository/section-concepts/{project.pk}/papers/{paper.pk}/'),
            'has_file': bool(paper.file), 'deliverable_id': definition.get('id', 'APPROVED_CONCEPT'),
            'deliverable_label': 'Approved shared concept paper', 'team_id': None,
            'team_name': f'Shared system · {project.section.section}', 'section': project.section.section,
            'section_project_id': project.pk, 'project_title': paper.concept.title,
            'year_level': project.section.year_level, 'level': f'{project.section.year_level} {"PIT" if pit else "Capstone"}',
            'academic_year': semester.school_year.label, 'semester': semester.label,
            'pit_event_config_id': project.pit_event_config_id, 'stage': context.label,
            'course_code': '', 'status': 'Approved', 'submission_kind': 'post', 'deliverable_type': 'post',
            'deliverable_type_label': 'Post-Defense', 'is_restricted_archive': definition.get('is_restricted', False),
            'archive_locked': False, 'is_missing': False, 'uploaded_by': display_name(paper.uploaded_by),
            'uploaded_at': paper.uploaded_at, 'can_override': False, 'feedback': paper.feedback,
            'file_replacement_unlocked': False, 'file_replacement_reason': '', 'audit_trail': [],
            'archive_note': definition.get('archive_note', ''), **empty_ml_fields(),
        })
    return result
