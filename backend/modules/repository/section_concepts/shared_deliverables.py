"""Version-bound shared checklists, with read-only adapters for existing papers.

Reading a checklist never activates a concept round or creates submissions.
Only uploads capture a set, and every write re-resolves its section/context.
"""
from copy import copy, deepcopy
from hashlib import sha256
import json
from pathlib import Path
from uuid import uuid4

from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from defensys_backend.read_projection import read_memoize

from defense.shared_deliverables import shared_definitions
from .models import SectionConceptProject, SectionConceptPaper, SharedDeliverableSet, SharedDeliverableFile
from . import services

MAX_FILE_SIZE = 50 * 1024 * 1024


def digest(value):
    return sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


@read_memoize
def section_assignment(semester_id, section, year_level):
    from student_teams.models import SectionAssignment
    return SectionAssignment.objects.filter(semester_id=semester_id, section=section,
        year_level=year_level).select_related('semester', 'project_manager').first()


@read_memoize
def resolve(team, context):
    """Resolve only matching participants; a title alone never joins projects."""
    from student_teams.models import StudentTeam
    if not context:
        return None
    pit = hasattr(context, 'event_name')
    if pit != team.is_pit or (pit and (context.semester_id != team.semester_id or context.year_level != team.year_level)):
        return None
    section = section_assignment(team.semester_id, team.section, team.year_level)
    if not section:
        return None
    project = services.project_for(team, context)
    current_project = project
    if not project:
        candidates = SectionConceptProject.objects.filter(section=section, team_links__team=team,
            team_links__project_version=team.project_version)
        candidates = candidates.filter(pit_event_config__isnull=False) if pit else candidates.filter(
            defense_stage__display_order__lt=context.display_order)
        approved = []
        for candidate in candidates.select_related('project_manager').distinct().order_by('-pk'):
            hearing = services.latest(candidate)
            if hearing and hearing.selected_key and (hearing.verdict == 'approved' or (
                    hearing.verdict == 'approved_with_revisions' and hearing.revisions_cleared_at)):
                approved.append((candidate, hearing))
        titles = {hearing.systems.get(key=hearing.selected_key).title for _, hearing in approved}
        if len(titles) > 1:
            raise ValidationError('This team has different approved shared systems. Resolve its project assignment first.')
        project = approved[0][0] if approved else None
    hearing = services.latest(project) if project else None
    pending_import = None
    if not project and (not section.system_name.strip() or not section.project_manager_id):
        return None
    teams = StudentTeam.objects.filter(semester_id=team.semester_id, section=team.section,
        year_level=team.year_level)
    teams = teams.filter(level__icontains='PIT') if pit else teams.exclude(level__icontains='PIT')
    if pit:
        from student_teams.pit_rosters import effective_ids
        teams = teams.filter(pk__in=effective_ids(team.semester_id, team.year_level, context))
    if project:
        teams = teams.filter(pk__in=services.active_links(project).values('team_id'))
    teams = list(teams.select_related('semester', 'adviser').order_by('pk'))
    if not any(member.pk == team.pk for member in teams):
        return None
    manager = project.project_manager if current_project else (section.project_manager or (project.project_manager if project else None))
    if not manager:
        return None
    if not any(member.memberships.filter(student=manager).exists() or member.leader_id == manager.pk for member in teams):
        return None
    systems = list(hearing.systems.order_by('pk').values('key', 'title')) if hearing else [
        {'key': 'assigned', 'title': section.system_name}]
    if not project and context.concept_config.get('enabled'):
        from .imported import imported_state
        _, imported_teams, _, _, keys, blocker, token = imported_state(team, context)
        if {member.pk for member in imported_teams} != {member.pk for member in teams}:
            blocker = 'Review the section’s participating event roster before opening shared concepts.'
        pending_import = {'token': token, 'blocker': blocker}
        systems = [{'key': key, 'title': section.system_name if index == 0 else ''}
                   for index, key in enumerate(keys)]
    if hearing and not current_project:
        systems = [row for row in systems if row['key'] == hearing.selected_key]
    team_snapshot = [{'id': member.pk, 'version': member.project_version} for member in teams]
    identity = digest({'teams': team_snapshot, 'source_round': hearing.pk if hearing else None,
                       'assigned_system': section.system_name if not hearing else None,
                       'import': pending_import['token'] if pending_import else None})
    binding = {'section': section, **services.context_fields(context), 'identity': identity}
    captured = SharedDeliverableSet.objects.filter(**binding).prefetch_related('files').first()
    return {'team': team, 'section': section, 'context': context, 'teams': teams, 'manager': manager,
            'project': project, 'round': hearing, 'current_project': current_project,
            'pending_import': pending_import,
            'systems': systems, 'team_snapshot': team_snapshot, 'identity': identity,
            'binding': binding, 'captured': captured,
            'definitions': deepcopy(captured.requirements) if captured else (
                deepcopy(hearing.shared_requirements_snapshot) if current_project and
                hearing.shared_requirements_snapshot is not None else shared_definitions(context))}


def staff_access(actor, profile):
    if getattr(actor, 'is_guest_panelist', False):
        return False
    if services.admin(actor):
        return True
    if getattr(actor, 'role', '') != 'faculty':
        return False
    context, section = profile['context'], profile['section']
    if hasattr(context, 'event_name'):
        if getattr(actor, 'is_pit_lead', False) and actor.pit_lead_year == section.year_level:
            return True
        from user_management.models import SectionInstructorAssignment
        return SectionInstructorAssignment.objects.filter(faculty=actor, is_active=True,
            semester_id=section.semester_id, section=section.section, year_level=section.year_level).exists()
    return any(member.adviser_id == actor.pk for member in profile['teams'])


def member_access(actor, profile):
    if getattr(actor, 'is_guest_panelist', False):
        return False
    return actor.pk == profile['manager'].pk or any(
        member.memberships.filter(student=actor).exists() or member.leader_id == actor.pk for member in profile['teams'])


def reviewer_access(actor, profile):
    if getattr(actor, 'is_guest_panelist', False):
        return False
    if services.admin(actor):
        return True
    if getattr(actor, 'role', '') != 'faculty':
        return False
    if profile['current_project']:
        return services.is_reviewer(actor, profile['current_project'])
    if hasattr(profile['context'], 'event_name'):
        from user_management.models import SectionInstructorAssignment
        instructors = list(SectionInstructorAssignment.objects.filter(is_active=True, faculty__is_active=True,
            semester_id=profile['section'].semester_id, section=profile['section'].section,
            year_level=profile['section'].year_level).values_list('faculty_id', flat=True).distinct())
        return instructors == [actor.pk]
    return any(member.adviser_id == actor.pk for member in profile['teams'])


def panel_access(actor, profile):
    rows = schedules(profile)
    ids = [row.pk for row in rows]
    if not ids:
        return False
    from defense.scheduler.models import DefenseSchedule
    if getattr(actor, 'is_guest_panelist', False):
        from user_management.models import GuestPanelistCode
        from user_management.external_evaluators import invitation_is_available, invitation_schedule_ids
        invitation = GuestPanelistCode.objects.select_related('evaluator').filter(
            pk=actor.guest_code_id, code=actor.guest_code, is_active=True).first()
        return bool(invitation and invitation_is_available(invitation) and
                    set(ids).intersection(invitation_schedule_ids(invitation)))
    return DefenseSchedule.objects.filter(pk__in=ids).filter(
        Q(panel_assignments__panelist=actor) | Q(documenter=actor)).exists()


def can_read_file(actor, row):
    """One policy for authenticated media, file details and archive downloads."""
    captured = row.submission_set
    if services.admin(actor):
        return True
    context = captured.pit_event_config or captured.defense_stage
    if captured.pit_event_config_id and getattr(actor, 'is_pit_lead', False) and (
            getattr(actor, 'role', '') == 'faculty' and actor.pit_lead_year == context.year_level):
        return True
    from student_teams.models import StudentTeam
    teams = list(StudentTeam.objects.filter(pk__in=[t['id'] for t in captured.team_snapshot],
        semester_id=captured.section.semester_id).select_related('semester', 'adviser'))
    if not getattr(actor, 'is_guest_panelist', False):
        for team in teams:
            if team.adviser_id == actor.pk or team.memberships.filter(student=actor).exists() or team.leader_id == actor.pk:
                return True
    section = captured.section
    if captured.pit_event_config_id:
        from types import SimpleNamespace
        section = SimpleNamespace(semester_id=section.semester_id, section=section.section, year_level=context.year_level)
    profile = {'teams': teams, 'context': context, 'section': section}
    if staff_access(actor, profile):
        return True
    definition = next((d for d in captured.requirements if d['deliverable_id'] == row.deliverable_id), {})
    return bool(definition.get('is_defense_material') and definition['deliverable_type'] == 'pre' and panel_access(actor, profile))


def can_read_legacy_file(actor, paper):
    project = paper.concept.round.project
    if not services.can_read(actor, project):
        return False
    guest = getattr(actor, 'is_guest_panelist', False)
    if not guest and (services.admin(actor) or services.can_manage(actor, project) or services.is_reviewer(actor, project) or actor.pk == project.project_manager_id):
        return True
    profile = for_round(paper.concept.round)
    if profile and member_access(actor, profile):
        return True
    return bool(profile and paper.purpose == 'proposal' and any(
        definition.get('legacy_purpose') == 'proposal' and definition.get('is_defense_material')
        for definition in profile['definitions']))


def writable(profile):
    from student_teams.term_scope import get_active_semester
    section, context = profile['section'], profile['context']
    active = get_active_semester()
    if not active or not section.semester.is_active or active.pk != section.semester_id:
        raise PermissionError('Historical shared deliverables are read-only.')
    if getattr(context, 'is_officially_complete', False) or (not hasattr(context, 'event_name') and
            context.grading_configs.filter(semester_id=section.semester_id, is_officially_complete=True).exists()):
        raise PermissionError('This stage or event is officially complete.')


def schedules(profile):
    from defense.scheduler.models import DefenseSchedule
    query = DefenseSchedule.objects.filter(team_id__in=[t.pk for t in profile['teams']],
        semester_id=profile['section'].semester_id).exclude(status='cancelled')
    context = profile['context']
    query = query.filter(scope='pit', event_name__iexact=context.event_name) if hasattr(context, 'event_name') else query.filter(
        scope='capstone', defense_stage=context)
    versions = {t.pk: t.project_version for t in profile['teams']}
    return [row for row in query if row.project_version == versions.get(row.team_id)]


def ensure_editable(profile, definition):
    if profile.get('historical'):
        raise PermissionError('Earlier shared rounds and project versions are read-only.')
    writable(profile)
    if profile['pending_import'] and profile['pending_import']['blocker']:
        raise PermissionError(profile['pending_import']['blocker'])
    from repository.deliverables.services import post_defense_ready
    from repository.deliverables.stage_access import manually_locked
    dtype, context = definition['deliverable_type'], profile['context']
    for team in profile['teams']:
        if manually_locked(team, context.label, dtype):
            raise PermissionError('Shared uploads for this stage are locked by management.')
    if dtype == 'post':
        from repository.deliverables.services import latest_stage_grade
        from grading.grades.models import TeamGrade
        if any(getattr(latest_stage_grade(team, context.label), 'status', '') in TeamGrade.LOCKED_STATUSES for team in profile['teams']):
            raise PermissionError('Shared files for published grades are locked. Reopen the assessment before changes.')
        if not all(post_defense_ready(team, context.label) for team in profile['teams']):
            raise PermissionError('Complete the section’s current defense assessments and outcomes before post-defense submissions.')
    elif profile['current_project']:
        services.editable(profile['round'])
    elif schedules(profile):
        raise PermissionError('Pre-defense shared files are locked after scheduling. Use the existing revision workflow.')


def slots(profile, definition):
    from repository.deliverables.documents import slots_for
    systems = profile['systems']
    if definition['deliverable_type'] == 'post' and profile['round'] and profile['round'].selected_key:
        systems = [s for s in systems if s['key'] == profile['round'].selected_key]
    config = {'required_count': len(systems), 'concept_keys': [s['key'] for s in systems]}
    values = deepcopy(slots_for({**definition, 'concept_policy': config}, stage=profile['context']))
    for slot in values:
        slot['system_key'] = slot['key'].split(':', 1)[0] if definition.get('file_policy', {}).get('mode') == 'concepts' else ''
    return values


def legacy_file(profile, definition, slot_key):
    hearing = profile['round']
    if not hearing or not profile['current_project'] or not definition.get('legacy_purpose'):
        return None
    purpose = definition['legacy_purpose']
    if purpose == 'proposal':
        if not slot_key.endswith(':paper'):
            return None
        key = slot_key.split(':')[0]
    else:
        key = hearing.selected_key
    return SectionConceptPaper.objects.filter(concept__round=hearing, concept__key=key,
        purpose=purpose, is_current=True).first()


def file_payload(row, *, legacy=False, project_id=None):
    return {'id': row.pk, 'legacy': legacy, 'revision': row.revision, 'file_name': row.file_name,
        'slot_key': getattr(row, 'slot_key', ''), 'title_review_context': row.title_review_context,
        'file_size': getattr(row, 'file_size', None), 'status': row.status, 'feedback': row.feedback,
        'reviewed_by_id': row.reviewed_by_id, 'is_current': row.is_current,
        'uploaded_at': row.uploaded_at.isoformat(), 'reviewed_at': row.reviewed_at.isoformat() if row.reviewed_at else None,
        'file_url': (f'/api/repository/section-concepts/{project_id}/papers/{row.pk}/' if legacy else
                     f'/api/repository/section-concepts/shared-deliverables/files/{row.pk}/')}


def requirement_files(profile, definition):
    captured = profile['captured']
    rows = list(captured.files.all()) if captured else []
    result = {row.slot_key: file_payload(row) for row in rows if row.is_current and row.deliverable_id == definition['deliverable_id']}
    for slot in slots(profile, definition):
        prior = legacy_file(profile, definition, slot['key'])
        if prior and slot['key'] not in result:
            result[slot['key']] = file_payload(prior, legacy=True, project_id=profile['project'].pk)
    return result


def complete(profile, definition, *, accepted=True):
    files = requirement_files(profile, definition)
    from repository import title_workflow
    if accepted and title_workflow.enabled(profile.get('round')):
        for slot in slots(profile, definition):
            row = files.get(slot['key'])
            if row and row['status'] == 'accepted':
                try:
                    context = title_workflow.shared_context(profile, definition, slot['key'], accepting=True)
                    if context and row.get('title_review_context') != context:
                        return False
                except ValidationError:
                    return False
    valid = {key: row for key, row in files.items() if accepted is None or row['status'] == 'accepted' or (accepted is False and row['status'] != 'rejected')}
    policy = definition.get('file_policy') or {}
    if policy.get('mode') == 'multiple':
        return policy.get('min_files', 1) <= len(valid) <= policy.get('max_files', 10) and len(valid) == len(files)
    required = [slot for slot in slots(profile, definition) if slot.get('required', True)]
    return bool(required) and all(slot['key'] in valid for slot in required)


def applicable(profile, definition):
    if definition['deliverable_type'] != 'post' or definition.get('verdict_condition') != 'revisions_only':
        return True
    from repository.deliverables.services import latest_stage_grade
    return any(getattr(latest_stage_grade(team, profile['context'].label), 'verdict', '') == 'approved_with_revisions'
               for team in profile['teams'])


def required_complete(profile, dtype='pre', *, accepted=True):
    return all(complete(profile, d, accepted=accepted) for d in profile['definitions'] if
        d['deliverable_type'] == dtype and d.get('required') and applicable(profile, d))


def document_progress(profile, dtype='pre'):
    result = {'documents_required': 0, 'documents_uploaded': 0, 'documents_accepted': 0}
    for definition in profile['definitions']:
        if definition['deliverable_type'] != dtype or not definition.get('required') or not applicable(profile, definition):
            continue
        files = requirement_files(profile, definition)
        policy = definition.get('file_policy') or {}
        if policy.get('mode') == 'multiple':
            # Every submitted attachment needs review, including those above the minimum.
            count = max(policy.get('min_files', 1), len(files))
            uploaded = min(count, len(files))
            accepted = min(count, sum(f['status'] == 'accepted' for f in files.values()))
        else:
            keys = [slot['key'] for slot in slots(profile, definition) if slot.get('required', True)]
            count = len(keys)
            uploaded = sum(key in files for key in keys)
            accepted = sum(key in files and files[key]['status'] == 'accepted' for key in keys)
        result['documents_required'] += count
        result['documents_uploaded'] += uploaded
        result['documents_accepted'] += accepted
    return result


def completion_summary(profile, dtype='post'):
    """Describe section work once, without attributing it to each team's adviser."""
    hearing = profile['round']
    selected_key = hearing.selected_key if hearing else ''
    selected = next((s for s in profile['systems'] if s['key'] == selected_key), None)
    requirements = []
    for definition in profile['definitions']:
        if (definition['deliverable_type'] != dtype or not definition.get('required')
                or not applicable(profile, definition)):
            continue
        files = requirement_files(profile, definition)
        accepted = complete(profile, definition)
        uploaded = complete(profile, definition, accepted=None)
        status = ('accepted' if accepted else 'changes_requested' if any(
            f['status'] == 'rejected' for f in files.values()) else
            'awaiting_review' if uploaded else 'awaiting_pm_upload')
        requirements.append({'id': definition['deliverable_id'], 'label': definition['label'],
            'status': status, 'complete': accepted})
    status = ('accepted' if all(row['complete'] for row in requirements) else
        'awaiting_pm_upload' if any(row['status'] == 'awaiting_pm_upload' for row in requirements) else
        'changes_requested' if any(row['status'] == 'changes_requested' for row in requirements) else 'awaiting_review')
    return {'identity': profile['identity'], 'section_id': profile['section'].pk,
        'section': profile['section'].section, 'project_id': profile['project'].pk if profile['project'] else None,
        'round_id': hearing.pk if hearing else None, 'stage_label': profile['context'].label,
        'project_manager_name': profile['manager'].get_full_name() or profile['manager'].username,
        'selected_key': selected_key, 'selected_system_title': selected['title'] if selected else '',
        'status': status, 'complete': all(row['complete'] for row in requirements),
        'requirements': requirements, **document_progress(profile, dtype)}


def for_round(hearing):
    link = services.active_links(hearing.project).first()
    latest = services.latest(hearing.project)
    if link and latest and latest.pk == hearing.pk:
        return resolve(link.team, hearing.project.context)
    # Completed rounds keep their original evidence after a new project/round.
    # This projection never reconnects old teams to new work.
    project = hearing.project
    captured = SharedDeliverableSet.objects.filter(source_round=hearing,
        **services.context_fields(project.context)).prefetch_related('files').order_by('-pk').first()
    recorded = hearing.decision_snapshot.get('teams') or hearing.endorsement_snapshot.get('teams') or list(
        project.team_links.values('team_id', 'project_version'))
    team_snapshot = captured.team_snapshot if captured else [
        {'id': item['team_id'], 'version': item['project_version']} for item in recorded]
    from student_teams.models import StudentTeam
    versions = {item['id']: item['version'] for item in team_snapshot}
    teams = list(StudentTeam.objects.filter(pk__in=versions).select_related('semester', 'adviser'))
    for team in teams:
        team.project_version = versions[team.pk]
    if not teams:
        return None
    requirements = captured.requirements if captured else hearing.shared_requirements_snapshot
    return {'team': teams[0], 'teams': teams, 'team_snapshot': team_snapshot,
        'section': project.section, 'context': project.context, 'project': project, 'current_project': project,
        'round': hearing, 'manager': project.project_manager, 'pending_import': None, 'historical': True,
        'captured': captured, 'identity': captured.identity if captured else digest(team_snapshot),
        'systems': list(hearing.systems.order_by('pk').values('key', 'title')),
        'definitions': deepcopy(requirements if requirements is not None else shared_definitions(project.context))}


def round_complete(hearing, dtype='pre', *, accepted=True):
    profile = for_round(hearing)
    return required_complete(profile, dtype, accepted=accepted) if profile else False


def invalidate_title_reviews(hearing, keys, actor):
    """Configured per-system evidence follows the same title binding as legacy papers."""
    profile = for_round(hearing)
    if not profile or not profile['captured']:
        return
    numbers = [d['deliverable_id'] for d in profile['definitions']
               if d['deliverable_type'] == 'pre' and (d.get('file_policy') or {}).get('mode') == 'concepts']
    for row in profile['captured'].files.filter(is_current=True, status='accepted', deliverable_id__in=numbers):
        if row.slot_key.split(':')[0] not in keys:
            continue
        services.audit(actor, 'paper_review_invalidated', row, reason='System title changed',
                       reviewed_by=row.reviewed_by_id,
                       reviewed_at=row.reviewed_at.isoformat() if row.reviewed_at else None)
        row.status, row.reviewed_by, row.reviewed_at = 'pending', None, None
        row.save(update_fields=['status', 'reviewed_by', 'reviewed_at'])


def content_snapshot(hearing, *, include_status=True):
    profile = for_round(hearing)
    if not profile:
        return []
    output = []
    for definition in profile['definitions']:
        if definition['deliverable_type'] != 'pre':
            continue
        for key, row in sorted(requirement_files(profile, definition).items()):
            item = {'deliverable_id': definition['deliverable_id'], 'slot_key': key,
                    'id': row['id'], 'legacy': row['legacy'], 'revision': row['revision']}
            if include_status:
                item.update(status=row['status'], reviewed_by_id=row['reviewed_by_id'])
            output.append(item)
    return output


def review_token(profile):
    return digest({'identity': profile['identity'], 'requirements': profile['definitions'],
        'files': {d['deliverable_id']: requirement_files(profile, d) for d in profile['definitions']},
        'titles': services.review_token(profile['round']) if profile.get('round') else ''})


@read_memoize(copy=True)
def stage_navigation_states(team):
    """Read the same progression evidence as the team workspace, never file counts alone."""
    from repository.deliverables.services import current_stage_for_team, post_deliverables_complete
    current = current_stage_for_team(team)
    if team.is_pit:
        from defense.scheduler.event_scope import pit_events_for_team
        return {event.label: 'complete' if event.is_officially_complete and
            post_deliverables_complete(team, event.label) else
            'current' if event.label == current else 'upcoming'
            for event in pit_events_for_team(team)}
    from student_teams.capstone_lifecycle import requirements_for, stage_cleared
    requirements = requirements_for(team)
    current_order = next((r['order'] for r in requirements if r['label'] == current), None)
    return {requirement['label']: 'complete' if stage_cleared(team, requirement) else
        'current' if requirement['label'] == current or (
            current_order is not None and requirement['order'] < current_order) else 'upcoming'
        for requirement in requirements}


def payload(profile, actor):
    full_access = staff_access(actor, profile) or member_access(actor, profile)
    if not full_access and not panel_access(actor, profile):
        raise PermissionError('Only the linked section members and authorized faculty can read its shared checklist.')
    context = profile['context']
    if hasattr(context, 'event_name'):
        from django.contrib.auth import get_user_model
        from user_management.models import SectionInstructorAssignment
        reviewers = get_user_model().objects.filter(pk__in=SectionInstructorAssignment.objects.filter(
            is_active=True, faculty__is_active=True, semester_id=profile['section'].semester_id,
            section=profile['section'].section, year_level=profile['section'].year_level).values('faculty_id'))
        reviewer_names = [user.get_full_name() or user.username for user in reviewers.order_by('pk')]
    else:
        reviewer_names = list(dict.fromkeys(team.adviser.get_full_name() or team.adviser.username
            for team in profile['teams'] if team.adviser_id))
    requirements = []
    for definition in profile['definitions']:
        if not full_access and (not definition.get('is_defense_material') or definition['deliverable_type'] != 'pre'):
            continue
        if not applicable(profile, definition):
            continue
        reason = ''
        try:
            ensure_editable(profile, definition)
        except (PermissionError, ValidationError) as exc:
            reason = str(exc)
        if definition['deliverable_type'] == 'post':
            from repository.deliverables.services import post_defense_ready
            if not all(post_defense_ready(team, context.label) for team in profile['teams']) and not (
                    profile.get('historical') and requirement_files(profile, definition)):
                continue
        files = requirement_files(profile, definition)
        current = list(files.values())
        status = ('accepted' if complete(profile, definition) else 'rejected' if any(f['status'] == 'rejected' for f in current)
                  else 'pending' if current else 'missing')
        documents = []
        configured_slots = slots(profile, definition)
        if (definition.get('file_policy') or {}).get('mode') == 'multiple':
            configured_slots = [{'key': key, 'label': row['file_name'], 'required': True,
                                 'file_format': definition.get('file_format', 'any'), 'system_key': ''} for key, row in files.items()]
        for slot in configured_slots:
            row = files.get(slot['key'])
            suggested = archive_file_name(profile, {**definition,
                'file_format': slot.get('file_format') or definition.get('file_format', 'any')},
                row['file_name'] if row else '') if definition['deliverable_type'] == 'post' else ''
            from repository import title_workflow
            title_blocker, upload_blocker = '', ''
            try:
                title_workflow.shared_context(profile, definition, slot['key'], accepting=True)
            except ValidationError as exc:
                title_blocker = ' '.join(exc.messages)
            try:
                title_workflow.shared_context(profile, definition, slot['key'])
            except ValidationError as exc:
                upload_blocker = ' '.join(exc.messages)
            documents.append({**slot, 'file': row, 'title_blocker': title_blocker,
                'suggested_file_name': suggested,
                'title_revision_available': bool((system := title_workflow.shared_system(profile, definition, slot['key'])) and system.title_review.get('state') in ('submitted', 'accepted')),
                'upload_blocker': upload_blocker,
                'max_file_size': 25 * 1024 * 1024 if profile['current_project'] and (
                    definition.get('legacy_purpose') == 'final' or (
                    definition.get('legacy_purpose') == 'proposal' and slot['key'].endswith(':paper'))) else MAX_FILE_SIZE,
                'can_upload': not reason and not upload_blocker and actor.pk == profile['manager'].pk and (not row or row['status'] != 'accepted'),
                'can_review': not reason and reviewer_access(actor, profile) and bool(row)
                    and not (definition['deliverable_type'] == 'post' and row['status'] == 'accepted')})
        history = []
        if profile['captured']:
            history = [file_payload(row) for row in profile['captured'].files.all() if
                       row.deliverable_id == definition['deliverable_id'] and not row.is_current]
        if profile['current_project'] and definition.get('legacy_purpose'):
            for slot in slots(profile, definition):
                current_paper = legacy_file(profile, definition, slot['key'])
                if current_paper:
                    history.extend({**file_payload(old, legacy=True, project_id=profile['project'].pk),
                                    'slot_key': slot['key']} for old in current_paper.concept.papers.filter(
                                        purpose=definition['legacy_purpose'], is_current=False))
        requirements.append({**definition, 'id': definition['deliverable_id'], 'status': status, 'documents': documents,
            'suggested_file_name': archive_file_name(profile, definition, '') if definition['deliverable_type'] == 'post' else '',
            'files': current, 'history': history, 'unavailable_reason': reason,
            'can_add_attachment': not reason and actor.pk == profile['manager'].pk and
                not (definition['deliverable_type'] == 'post' and status == 'accepted') and
                len(files) < (definition.get('file_policy') or {}).get('max_files', 10),
            'max_file_size': MAX_FILE_SIZE})
    states = {stage_navigation_states(team).get(context.label, 'upcoming') for team in profile['teams']}
    stage_status = 'complete' if states == {'complete'} else 'current' if 'current' in states else 'upcoming'
    return {'team_id': profile['team'].pk, 'section': profile['section'].section,
        'imported': bool(profile['pending_import']), 'concept_selection_enabled': bool(context.concept_config.get('enabled')),
        'stage_label': context.label, 'stage_status': stage_status,
        'scope': 'pit' if hasattr(context, 'event_name') else 'capstone',
        'context_id': context.pk, 'source_project_id': profile['project'].pk if profile['project'] else None,
        'project_manager_id': profile['manager'].pk,
        'project_manager_name': profile['manager'].get_full_name() or profile['manager'].username,
        'reviewer_name': ', '.join(reviewer_names) if reviewer_names else 'Not assigned',
        'systems': profile['systems'],
        'selected_key': profile['round'].selected_key if profile['round'] else '',
        'post_completion': completion_summary(profile),
        'identity': profile['identity'], 'review_token': review_token(profile),
        'requirements': requirements, 'pre_complete': required_complete(profile),
        'post_complete': required_complete(profile, 'post')}


def summary(team, context):
    profile = resolve(team, context)
    if not profile or not profile['definitions']:
        return None
    return {'team_id': team.pk, 'section_id': profile['section'].pk, 'section': team.section,
        'context_id': context.pk, 'stage_label': context.label,
        'project_manager_name': profile['manager'].get_full_name() or profile['manager'].username,
        'pre_complete': required_complete(profile), 'post_complete': required_complete(profile, 'post')}


def groups_for_team(team, actor):
    if team.is_pit:
        from defense.scheduler.event_scope import pit_events_for_team
        contexts = pit_events_for_team(team).order_by('pk')
    else:
        from defense.stages.models import DefenseStage
        contexts = DefenseStage.objects.filter(is_active=True).order_by('display_order', 'pk')
    result = []
    for context in contexts:
        profile = resolve(team, context)
        if profile and profile['definitions'] and (staff_access(actor, profile) or member_access(actor, profile) or panel_access(actor, profile)):
            result.append(payload(profile, actor))
    return result


def lock_profile(team, context, expected_token):
    from student_teams.models import SectionAssignment, StudentTeam
    # Section lock serializes the first upload as well as later revisions.
    SectionAssignment.objects.select_for_update().get(semester_id=team.semester_id,
        section=team.section, year_level=team.year_level)
    context = type(context).objects.select_for_update().get(pk=context.pk)
    StudentTeam.objects.select_for_update().get(pk=team.pk)
    profile = resolve(team, context)
    if not profile or review_token(profile) != expected_token:
        raise ValidationError('The shared project or documents changed. Refresh and review the current checklist.')
    return profile


@transaction.atomic
def upload(team, context, actor, number, slot_key, file, expected_token):
    profile = lock_profile(team, context, expected_token)
    if actor.pk != profile['manager'].pk or getattr(actor, 'role', '') != 'student':
        raise PermissionError('Only this section’s project manager submits shared deliverables.')
    if profile['pending_import']:
        from . import imported
        imported.save(team, context, actor, None, profile['pending_import']['token'])
        team._section_concept_projects = {}
        profile = resolve(team, context)
    definition = next((d for d in profile['definitions'] if d['deliverable_id'] == number), None)
    if not definition or not applicable(profile, definition):
        raise ValidationError('Choose a shared requirement in this stage or event.')
    ensure_editable(profile, definition)
    configured = {slot['key']: slot for slot in slots(profile, definition)}
    mode = definition.get('file_policy', {}).get('mode', 'single')
    prior = requirement_files(profile, definition)
    if definition['deliverable_type'] == 'post' and complete(profile, definition):
        raise ValidationError('This shared post-defense requirement is already accepted and archived.')
    if mode == 'multiple':
        if not slot_key:
            slot_key = 'file_' + uuid4().hex
        elif slot_key not in prior:
            raise ValidationError('Choose a current attachment to replace.')
        if slot_key not in prior and len(prior) >= definition['file_policy'].get('max_files', 10):
            raise ValidationError('This shared requirement has reached its attachment limit.')
        slot = {'file_format': definition.get('file_format', 'any')}
    elif slot_key not in configured:
        raise ValidationError('Choose a configured shared document slot.')
    else:
        slot = configured[slot_key]
    from repository.title_workflow import shared_context
    title_context = shared_context(profile, definition, slot_key)
    if slot_key in prior and prior[slot_key]['status'] == 'accepted':
        raise ValidationError('Ask the reviewer to request corrections before replacing an accepted file.')
    if not file or not file.size or file.size > MAX_FILE_SIZE:
        raise ValidationError('Choose a readable file of up to 50 MB.')
    from repository.deliverables.timing import validate_material_file
    try:
        validate_material_file({'file_format': slot.get('file_format', definition.get('file_format', 'any'))}, file.name, file)
    except ValueError as exc:
        raise ValidationError(str(exc)) from exc
    if Path(file.name).suffix.lower() == '.pdf':
        header = file.read(5)
        file.seek(0)
        if header != b'%PDF-':
            raise ValidationError('The selected file must contain a PDF document.')
    legacy = definition.get('legacy_purpose') and profile['current_project'] and (
        (definition['legacy_purpose'] == 'proposal' and slot_key.endswith(':paper')) or definition['legacy_purpose'] == 'final')
    if legacy:
        key = slot_key.split(':')[0] if definition['legacy_purpose'] == 'proposal' else profile['round'].selected_key
        services.upload(profile['current_project'], actor, key, file, purpose=definition['legacy_purpose'])
    else:
        captured = profile['captured']
        if not captured:
            captured = SharedDeliverableSet.objects.create(**profile['binding'],
                source_project=profile['project'], source_round=profile['round'], project_manager=profile['manager'],
                requirements=profile['definitions'], team_snapshot=profile['team_snapshot'], system_snapshot=profile['systems'])
        query = captured.files.filter(deliverable_id=number, slot_key=slot_key)
        revision = (query.order_by('-revision').values_list('revision', flat=True).first() or 0) + 1
        query.filter(is_current=True).update(is_current=False)
        repository_name = archive_file_name(profile, definition, file.name)
        file.name = repository_name
        row = SharedDeliverableFile.objects.create(submission_set=captured, deliverable_id=number, slot_key=slot_key,
            file=file, file_name=repository_name, file_size=file.size, revision=revision, uploaded_by=actor, title_review_context=title_context)
        if profile['current_project'] and definition['deliverable_type'] == 'pre':
            services.invalidate(profile['round'])
        if hasattr(context, 'event_name'):
            from student_teams.pit_rosters import pin
            for member in profile['teams']:
                pin(member, context)
        services.audit(actor, 'shared_deliverable_uploaded', row, deliverable_id=number,
                       slot_key=slot_key, revision=revision)
    return payload(resolve(team, context), actor)


def archive_file_name(profile, definition, original):
    if definition['deliverable_type'] != 'post':
        return Path(original).name
    from repository.project_archive.services import resolve_archive_file_template
    team = copy(profile['team'])
    systems = profile['systems']
    if profile['round'] and profile['round'].selected_key:
        systems = [s for s in systems if s['key'] == profile['round'].selected_key]
    team.project_title = next((s['title'] for s in systems if s['title']), profile['section'].system_name)
    name = resolve_archive_file_template(definition.get('archive_file_template', ''), team,
        profile['context'].label, semester_label=profile['section'].semester.label,
        deliverable_label=definition['label'], file_extension=Path(original).suffix.lstrip('.'),
        file_format=definition.get('file_format', 'any'))
    suffix = Path(name).suffix
    return name if len(name) <= 255 else name[:255 - len(suffix)] + suffix


@transaction.atomic
def review(team, context, actor, number, slot_key, file_id, legacy, status, feedback, expected_token, revision_scope='paper'):
    profile = lock_profile(team, context, expected_token)
    if not reviewer_access(actor, profile):
        raise PermissionError('Only authorized section reviewers can review shared deliverables.')
    definition = next((d for d in profile['definitions'] if d['deliverable_id'] == number), None)
    if not definition or not applicable(profile, definition):
        raise ValidationError('Choose a current shared requirement.')
    ensure_editable(profile, definition)
    if status not in ('accepted', 'rejected') or not isinstance(feedback, str) or len(feedback) > 5000 or (status == 'rejected' and not feedback.strip()):
        raise ValidationError('Choose acceptance or corrections and explain requested corrections.')
    current = requirement_files(profile, definition).get(slot_key)
    if not current or current['id'] != file_id or current['legacy'] != legacy:
        raise ValidationError('Review the current shared file version.')
    from repository import title_workflow
    system = title_workflow.shared_system(profile, definition, slot_key)
    if revision_scope == 'title_and_paper' and system is None:
        raise ValidationError('This file does not have a reviewable concept title.')
    if legacy:
        services.review(profile['current_project'], actor, file_id, status, feedback, revision_scope=revision_scope)
    else:
        row = SharedDeliverableFile.objects.select_for_update().get(pk=file_id, is_current=True,
            submission_set=profile['captured'], deliverable_id=number, slot_key=slot_key)
        if definition['deliverable_type'] == 'post' and row.status == 'accepted':
            raise ValidationError('This shared post-defense file is already accepted and archived.')
        if status == 'accepted':
            title_workflow.file_acceptance(row, title_workflow.shared_context(profile, definition, slot_key, accepting=True))
        elif system:
            title_workflow.revise_file(profile['round'], system.key, actor, feedback, row, revision_scope, 'shared')
        row.status, row.feedback = status, feedback.strip()
        row.reviewed_by, row.reviewed_at = actor, timezone.now()
        row.save(update_fields=['status', 'feedback', 'reviewed_by', 'reviewed_at'])
        if profile['current_project'] and definition['deliverable_type'] == 'pre':
            services.invalidate(profile['round'])
        services.audit(actor, 'shared_deliverable_reviewed', row, status=status, feedback=feedback)
    # Review shared post files before attempting any archive-dependent closure.
    if definition['deliverable_type'] == 'post':
        refreshed = resolve(team, context)
        if required_complete(refreshed, 'post') and profile['current_project'] and services.correcting(profile['round'], profile['round'].selected_key):
            services.clear_revisions(profile['current_project'], actor, 'Accepted the required shared post-defense documents and verified corrections.')
        from grading.grades.services import maybe_auto_finalize_passed_grade
        from repository.deliverables.services import latest_stage_grade
        for member in profile['teams']:
            grade = latest_stage_grade(member, context.label)
            if grade:
                maybe_auto_finalize_passed_grade(grade, user=actor)
    return payload(resolve(team, context), actor)
