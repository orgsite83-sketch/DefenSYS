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
        captured = paper.concept.round.shared_requirements_snapshot or []
        shared_definition = next((d for d in captured if d.get('legacy_purpose') == 'final'), {})
        definition = {**definition, **shared_definition}
        result.append({
            'id': f'section-final-{paper.pk}', 'source_id': paper.pk, 'file_id': paper.pk,
            'type': ArchiveEntry.TYPE_PIT if pit else ArchiveEntry.TYPE_CAPSTONE,
            'file_name': paper.file_name, 'file_size': '',
            'file_url': (request.build_absolute_uri(f'/api/repository/section-concepts/{project.pk}/papers/{paper.pk}/')
                if request else f'/api/repository/section-concepts/{project.pk}/papers/{paper.pk}/'),
            'has_file': bool(paper.file), 'deliverable_id': definition.get('id', 'APPROVED_CONCEPT'),
            'deliverable_label': (shared_definition.get('label') if shared_definition.get('label') not in (
                None, 'Approved concept paper') else 'Approved shared concept paper'), 'team_id': None,
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
    result.extend(shared_deliverable_entries(scope, request))
    return result


def shared_deliverable_entries(scope, request=None):
    """Accepted shared post files occur once, with their captured privacy rules."""
    from repository.section_concepts.models import SharedDeliverableFile
    files = SharedDeliverableFile.objects.filter(is_current=True, status='accepted').select_related(
        'submission_set__section__semester__school_year', 'submission_set__pit_event_config',
        'submission_set__defense_stage', 'submission_set__source_round', 'uploaded_by')
    if scope['scope'] == 'pit_lead':
        files = files.filter(submission_set__pit_event_config__isnull=False,
            submission_set__pit_event_config__year_level=scope.get('pit_year_level') or '')
    output = []
    for row in files:
        captured = row.submission_set
        definition = next((d for d in captured.requirements if d['deliverable_id'] == row.deliverable_id), None)
        if not definition or definition['deliverable_type'] != 'post':
            continue
        semester = captured.section.semester
        pit = bool(captured.pit_event_config_id)
        context = captured.pit_event_config or captured.defense_stage
        system_title = ', '.join(s['title'] for s in captured.system_snapshot if s['title'])
        if captured.source_round_id and captured.source_round.selected_key:
            system_title = captured.source_round.systems.filter(key=captured.source_round.selected_key).values_list('title', flat=True).first() or system_title
        url = f'/api/repository/section-concepts/shared-deliverables/files/{row.pk}/'
        output.append({
            'id': f'shared-file-{row.pk}', 'source_id': row.pk, 'file_id': row.pk,
            'type': ArchiveEntry.TYPE_PIT if pit else ArchiveEntry.TYPE_CAPSTONE,
            'file_name': row.file_name, 'file_size': f'{row.file_size / 1024:.1f} KB',
            'file_url': request.build_absolute_uri(url) if request else url, 'has_file': bool(row.file),
            'deliverable_id': row.deliverable_id, 'deliverable_label': definition['label'], 'team_id': None,
            'team_name': f'Shared system · {captured.section.section}', 'section': captured.section.section,
            'section_project_id': captured.source_project_id,
            'project_title': system_title,
            'year_level': captured.pit_event_config.year_level if pit else captured.section.year_level,
            'level': f'{captured.section.year_level} {"PIT" if pit else "Capstone"}',
            'academic_year': semester.school_year.label, 'semester': semester.label,
            'pit_event_config_id': captured.pit_event_config_id, 'stage': context.label,
            'course_code': '', 'status': 'Approved', 'submission_kind': 'post', 'deliverable_type': 'post',
            'deliverable_type_label': 'Post-Defense', 'is_restricted_archive': definition.get('is_restricted', False),
            'archive_locked': False, 'is_missing': False, 'uploaded_by': display_name(row.uploaded_by),
            'uploaded_at': row.uploaded_at, 'can_override': False, 'feedback': row.feedback,
            'file_replacement_unlocked': False, 'file_replacement_reason': '', 'audit_trail': [],
            'archive_note': definition.get('archive_note', ''), **empty_ml_fields(),
        })
    return output
