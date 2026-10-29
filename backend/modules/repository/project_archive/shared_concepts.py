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
            'has_file': bool(paper.file),
            'deliverable_id': shared_definition.get('deliverable_id') or definition.get('id', 'APPROVED_CONCEPT'),
            'deliverable_label': (shared_definition.get('label') if shared_definition.get('label') not in (
                None, 'Approved concept paper') else 'Approved shared concept paper'), 'team_id': None,
            'team_name': f'Shared system · {project.section.section}', 'section': project.section.section,
            'section_project_id': project.pk, 'section_round_id': paper.concept.round_id,
            'project_title': paper.concept.title,
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


def shared_deliverable_entries(scope, request=None, *, include_pre=False):
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
        if not definition or (definition['deliverable_type'] != 'post' and not include_pre):
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
            'section_round_id': captured.source_round_id,
            'project_title': system_title,
            'year_level': captured.pit_event_config.year_level if pit else captured.section.year_level,
            'level': f'{captured.section.year_level} {"PIT" if pit else "Capstone"}',
            'academic_year': semester.school_year.label, 'semester': semester.label,
            'pit_event_config_id': captured.pit_event_config_id, 'stage': context.label,
            'course_code': '', 'status': 'Approved', 'submission_kind': definition['deliverable_type'],
            'deliverable_type': definition['deliverable_type'],
            'deliverable_type_label': 'Post-Defense' if definition['deliverable_type'] == 'post' else 'Pre-Defense',
            'is_restricted_archive': definition.get('is_restricted', False),
            'archive_locked': False, 'is_missing': False, 'uploaded_by': display_name(row.uploaded_by),
            'uploaded_at': row.uploaded_at, 'can_override': False, 'feedback': row.feedback,
            'file_replacement_unlocked': False, 'file_replacement_reason': '', 'audit_trail': [],
            'archive_note': definition.get('archive_note', ''), **empty_ml_fields(),
        })
    return output


def _shared_context(project, hearing):
    selected = next((s for s in hearing.systems.all() if s.key == hearing.selected_key), None)
    return {'section_project_id': project.pk, 'section_round_id': hearing.pk,
        'section': project.section.section, 'shared_section_id': project.section_id,
        'shared_system_title': selected.title if selected else '',
        'selected_system_key': hearing.selected_key, 'shared_round': hearing.number,
        'shared_system_keys': [s.key for s in hearing.systems.all()]}


def shared_project_entries(scope, request=None):
    """Admin archive navigation includes PM work once, alongside proposal history."""
    if scope['scope'] not in ('admin', 'pit_lead'):
        return []
    from repository.section_concepts.models import SectionConceptProject
    from repository.section_concepts import shared_deliverables as shared
    projects = SectionConceptProject.objects.select_related('section__semester__school_year',
        'defense_stage', 'pit_event_config', 'project_manager').prefetch_related('rounds__systems__papers__uploaded_by')
    if scope['scope'] == 'pit_lead':
        projects = projects.filter(pit_event_config__year_level=scope.get('pit_year_level') or '')
    output = shared_final_entries(scope, request)
    output.extend(entry for entry in shared_deliverable_entries(scope, request, include_pre=True)
        if entry['submission_kind'] == 'pre')
    contexts = {}
    for project in projects:
        semester = project.section.semester
        pit = bool(project.pit_event_config_id)
        rounds = list(project.rounds.all())
        for hearing in rounds:
            metadata = _shared_context(project, hearing)
            contexts[(project.pk, hearing.pk)] = metadata
            base = {'type': ArchiveEntry.TYPE_PIT if pit else ArchiveEntry.TYPE_CAPSTONE,
                'team_id': None, 'team_name': f'Shared system · {project.section.section}',
                'academic_year': semester.school_year.label, 'semester': semester.label,
                'year_level': project.section.year_level, 'level': f'{project.section.year_level} {"PIT" if pit else "Capstone"}',
                'stage': project.context.label, 'pit_event_config_id': project.pit_event_config_id,
                'course_code': '', 'shared_owner': 'section', 'can_override': False,
                'archive_locked': False, 'is_restricted_archive': False,
                'file_replacement_unlocked': False, 'file_replacement_reason': '',
                'feedback': '', 'audit_trail': [], 'archive_note': '', **metadata, **empty_ml_fields()}
            for system in hearing.systems.all():
                for paper in system.papers.all():
                    if paper.purpose != 'proposal' or not paper.is_current or paper.status != 'accepted':
                        continue
                    url = f'/api/repository/section-concepts/{project.pk}/papers/{paper.pk}/'
                    output.append({**base, 'id': f'section-proposal-{paper.pk}', 'source_id': paper.pk,
                        'file_id': paper.pk, 'file_name': paper.file_name, 'file_size': '',
                        'file_url': request.build_absolute_uri(url) if request else url,
                        'has_file': bool(paper.file), 'is_missing': False,
                        'deliverable_id': 'SHARED_CONCEPTS', 'deliverable_label': 'Shared concept proposal',
                        'project_title': system.title, 'system_key': system.key,
                        'is_proposal_history': bool(hearing.selected_key),
                        'status': 'Approved', 'submission_kind': 'pre', 'deliverable_type': 'pre',
                        'deliverable_type_label': 'Pre-Defense', 'uploaded_by': display_name(paper.uploaded_by),
                        'uploaded_at': paper.uploaded_at})
            # Outstanding PM work is a section requirement, never a missing team copy.
            if not semester.is_active or hearing != max(rounds, key=lambda r: (r.number, r.pk)) or not hearing.selected_key:
                continue
            profile = shared.for_round(hearing)
            if not profile or profile.get('historical'):
                continue
            for requirement in shared.completion_summary(profile)['requirements']:
                if requirement['complete']:
                    continue
                definition = next(d for d in profile['definitions'] if d['deliverable_id'] == requirement['id'])
                output.append({**base, 'id': f'shared-required-{hearing.pk}-{requirement["id"]}',
                    'source_id': None, 'file_id': None, 'file_name': requirement['label'],
                    'file_size': '', 'file_url': '', 'has_file': False, 'is_missing': True,
                    'is_shared_requirement': True, 'project_title': metadata['shared_system_title'],
                    'deliverable_id': requirement['id'], 'deliverable_label': requirement['label'],
                    'status': 'Missing required', 'workflow_status': requirement['status'],
                    'submission_kind': 'post', 'deliverable_type': 'post', 'deliverable_type_label': 'Post-Defense',
                    'is_restricted_archive': definition.get('is_restricted', False),
                    'uploaded_by': '', 'uploaded_at': hearing.created_at,
                    'project_manager_name': profile['manager'].get_full_name() or profile['manager'].username,
                    'archive_note': 'Awaiting PM upload' if requirement['status'] == 'awaiting_pm_upload' else
                        'Shared file corrections requested' if requirement['status'] == 'changes_requested' else 'Awaiting shared-file review'})
    for entry in output:
        if entry.get('shared_owner'):
            continue
        entry.update(contexts.get((entry['section_project_id'], entry.get('section_round_id')), {}))
        entry['shared_owner'] = 'section'
        entry['is_proposal_history'] = bool(entry.get('selected_system_key') and entry['submission_kind'] == 'pre')
    return output


def attach_shared_team_context(entries):
    """Join saved project identities, not team names or filename conventions."""
    from repository.section_concepts.models import SectionProjectTeam
    links = SectionProjectTeam.objects.filter(team_id__in={e['team_id'] for e in entries if e.get('team_id')}).select_related(
        'project__section__semester__school_year', 'project__defense_stage', 'project__pit_event_config').prefetch_related(
        'project__rounds__systems')
    indexed = {}
    for link in links:
        project = link.project
        semester = project.section.semester
        key = (link.team_id, 'pit' if project.pit_event_config_id else 'capstone', project.context.label,
            semester.school_year.label, semester.label)
        hearing = max(project.rounds.all(), key=lambda r: (r.number, r.pk), default=None)
        if hearing:
            indexed.setdefault(key, {})[link.project_version] = _shared_context(project, hearing)
    for entry in entries:
        key = (entry.get('team_id'), entry.get('type'), entry.get('stage'), entry.get('academic_year'), entry.get('semester'))
        versions = indexed.get(key, {})
        context = versions.get(entry.get('project_version'))
        if context is None and entry.get('project_version') is None and len(versions) == 1:
            context = next(iter(versions.values()))
        if context:
            entry.update(context, shared_owner='team')
            slot = entry.get('slot_key', '').partition(':')[0]
            entry['is_proposal_history'] = bool(slot in context['shared_system_keys'] and context['selected_system_key']
                and slot != context['selected_system_key'])
