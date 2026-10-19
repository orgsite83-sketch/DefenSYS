"""Transactional ownership, review and selection rules for a shared section system."""
from copy import deepcopy
from pathlib import Path
from hashlib import sha256
import json

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from .models import (SectionConceptProject, SectionProjectTeam, SectionConceptRound,
                     SectionSystemConcept, SectionConceptPaper)

KEYS = ('c1', 'c2', 'c3')


def admin(user):
    return bool(user and (getattr(user, 'is_superuser', False) or getattr(user, 'role', '') == 'admin'))


def is_pm(user, project):
    return getattr(user, 'role', '') == 'student' and user.pk == project.project_manager_id


def is_reviewer(user, project):
    return admin(user) or (getattr(user, 'role', '') == 'faculty' and user.pk == project.reviewer_id)


def context_fields(context):
    return {'pit_event_config': context} if hasattr(context, 'event_name') else {'defense_stage': context}


def latest(project):
    return project.rounds.order_by('-number', '-pk').first()


def project_for(team, context):
    if context is None or not getattr(team, 'pk', None):
        return None
    key = (type(context).__name__, context.pk, team.project_version, team.semester_id, team.section, team.year_level)
    cache = getattr(team, '_section_concept_projects', {})
    if key in cache:
        return cache[key]
    project = SectionConceptProject.objects.filter(**context_fields(context),
        section__semester_id=team.semester_id, section__section=team.section,
        section__year_level=team.year_level, team_links__team=team,
        team_links__project_version=team.project_version).select_related(
            'section__semester', 'project_manager', 'reviewer', 'defense_stage', 'pit_event_config').first()
    cache[key] = project
    team._section_concept_projects = cache
    return project


def active_links(project):
    from django.db.models import F
    return project.team_links.filter(project_version=F('team__project_version'),
        team__semester_id=project.section.semester_id, team__section=project.section.section,
        team__year_level=project.section.year_level).select_related('team__semester', 'team__adviser')


def can_manage(user, project):
    if admin(user):
        return True
    if getattr(user, 'role', '') != 'faculty':
        return False
    if project.pit_event_config_id and getattr(user, 'is_pit_lead', False) and (
            getattr(user, 'pit_lead_year', '') == project.section.year_level):
        return True
    if not project.pit_event_config_id:
        return False
    from user_management.models import SectionInstructorAssignment
    return SectionInstructorAssignment.objects.filter(faculty=user,
        semester_id=project.section.semester_id, year_level=project.section.year_level,
        section=project.section.section, is_active=True).exists()


def can_read(user, project):
    if not user or not user.is_authenticated:
        return False
    if not getattr(user, 'is_guest_panelist', False):
        if admin(user) or can_manage(user, project) or is_reviewer(user, project) or user.pk == project.project_manager_id:
            return True
        if active_links(project).filter(Q(team__memberships__student=user) | Q(team__adviser=user)).exists():
            return True
    schedules = project.rounds.values_list('schedules__pk', flat=True)
    from defense.scheduler.models import DefenseSchedule
    candidates = DefenseSchedule.objects.filter(Q(pk__in=schedules) |
        Q(concept_round__section_round__project=project)).exclude(status='cancelled')
    if getattr(user, 'is_guest_panelist', False):
        from user_management.models import GuestPanelistCode
        from user_management.external_evaluators import invitation_is_available, invitation_schedule_ids
        invitation = GuestPanelistCode.objects.select_related('evaluator').filter(
            pk=user.guest_code_id, code=user.guest_code, is_active=True).first()
        return bool(invitation and invitation_is_available(invitation) and candidates.filter(
            pk__in=invitation_schedule_ids(invitation), status='scheduled').exists())
    return candidates.filter(Q(panel_assignments__panelist=user) | Q(documenter=user)).exists()


def visible_projects(user, *, team_id=None):
    # Apply exactly the same ownership rules to lists and direct/private file access.
    projects = SectionConceptProject.objects.select_related('section__semester', 'reviewer',
        'project_manager', 'defense_stage', 'pit_event_config').order_by('-pk')
    if team_id is not None:
        from django.db.models import F
        projects = projects.filter(team_links__team_id=team_id,
            team_links__project_version=F('team_links__team__project_version'),
            section__semester_id=F('team_links__team__semester_id'),
            section__section=F('team_links__team__section'),
            section__year_level=F('team_links__team__year_level')).distinct()
    return [p for p in projects if can_read(user, p)]


def require_active(project):
    from student_teams.term_scope import get_active_semester
    active = get_active_semester()
    if not project.section.semester.is_active or not active or active.pk != project.section.semester_id:
        raise PermissionError('Historical section concepts are read-only.')
    if project.pit_event_config_id and project.pit_event_config.is_officially_complete:
        raise PermissionError('This PIT event is complete; reopen it before changing its concepts.')
    if project.defense_stage_id and project.defense_stage.grading_configs.filter(
            semester_id=project.section.semester_id, is_officially_complete=True).exists():
        raise PermissionError('This Capstone stage is complete; reopen it before changing its concepts.')


def writable(project):
    try:
        require_active(project)
        return True
    except PermissionError:
        return False


def audit(actor, action, target, **values):
    log_high_impact_action(category=SystemAuditLog.CATEGORY_REPOSITORY,
        action=f'section_concepts.{action}', target=target, actor=actor,
        new_values=values, strict=True)


def locked_round(project):
    SectionConceptProject.objects.select_for_update().get(pk=project.pk)
    return SectionConceptRound.objects.select_for_update().filter(project=project).order_by('-number').first()


def editable(round):
    if round.verdict or round.module_rounds.filter(schedule__isnull=False).exclude(schedule__status='cancelled').exists():
        raise ValidationError('These proposals are attached to a hearing. Use the next revision round for changes.')


def correcting(round, key):
    return bool(round.verdict == 'approved_with_revisions' and not round.revisions_cleared_at and
                round.selected_key == key)


def invalidate(round):
    round.endorsed_at, round.endorsed_by, round.endorsement_snapshot = None, None, {}
    round.save(update_fields=['endorsed_at', 'endorsed_by', 'endorsement_snapshot'])
    from repository.deliverables.concepts import invalidate_clearance
    for module_round in round.module_rounds.filter(schedule__isnull=True).select_related('team'):
        invalidate_clearance(module_round.team, round.project.context.label)


def snapshot(round):
    return {'teams': list(active_links(round.project).order_by('team_id').values('team_id', 'project_version')),
        'systems': list(round.systems.order_by('key').values('id', 'key', 'title', 'confirmed')),
        'papers': list(SectionConceptPaper.objects.filter(concept__round=round, is_current=True).order_by(
            'concept__key').values('id', 'concept_id', 'revision', 'status'))}


def shared_clearance(round, *, state=None):
    """Current title confirmation and paper acceptance clear the shared set.

    Panel-requested revisions retain their explicit clearance, including the
    version snapshot. Legacy endorsement records remain available for auditing.
    """
    if not round or round.verdict in ('for_redefense', 'failed', 'project_rejected'):
        return False
    state = state if state is not None else snapshot(round)
    if round.verdict == 'approved_with_revisions':
        return bool(round.revisions_cleared_at and round.endorsement_snapshot == state)
    systems = state['systems']
    papers = state['papers']
    return bool(len(systems) == 3 and {s['key'] for s in systems} == set(KEYS)
        and all(s['confirmed'] and s['title'].strip() for s in systems)
        and len(papers) == 3 and {p['concept_id'] for p in papers} == {s['id'] for s in systems}
        and all(p['status'] == 'accepted' for p in papers))


def review_summary(round):
    """Read-only section facts shared by team summaries and review surfaces."""
    state = snapshot(round)
    progress = {'required': 3,
        'names_confirmed': sum(bool(s['confirmed'] and s['title'].strip()) for s in state['systems']),
        'papers_uploaded': len(state['papers']),
        'papers_accepted': sum(p['status'] == 'accepted' for p in state['papers'])}
    cleared = shared_clearance(round, state=state)
    statuses = [p['status'] for p in state['papers']]
    code, label = (
        ('failed', 'Shared system not approved') if round.verdict in ('failed', 'project_rejected') else
        ('revisions_pending', 'Shared system revisions pending') if round.verdict == 'approved_with_revisions' and not round.revisions_cleared_at else
        ('replacement_concepts_needed', 'Replacement shared papers needed') if round.verdict == 'for_redefense' else
        ('selected', 'Shared system revisions cleared') if round.verdict == 'approved_with_revisions' and cleared else
        ('selected', 'Shared system selected') if round.verdict == 'approved' and cleared else
        ('cleared', 'Shared papers cleared for hearing') if cleared else
        ('changes_requested', 'Shared paper corrections requested') if 'rejected' in statuses else
        ('awaiting_files', 'Shared papers awaiting upload') if len(statuses) < 3 else
        ('needs_review', 'Shared papers awaiting review') if 'pending' in statuses else
        ('needs_review', 'Shared titles awaiting confirmation'))
    return {'project_id': round.project_id, 'round_id': round.pk, 'round': round.number,
        'section': round.project.section.section, 'stage_label': round.project.context.label,
        'cleared': cleared, 'status': code, 'status_label': label,
        'review_progress': progress, 'systems': state['systems']}


def review_token(round):
    return sha256(json.dumps(snapshot(round), sort_keys=True).encode()).hexdigest()


@transaction.atomic
def configure(actor, teams, context, data):
    """Explicit activation only; display system names never enable this workflow."""
    from student_teams.models import SectionAssignment, StudentTeam
    from student_teams.formation_access import require_formation_scope, is_manager
    from user_management.models import SectionInstructorAssignment
    from user_management.academic_records.models import StudentAcademicRecord
    from repository.deliverables.models import ConceptRound
    if not teams or not context or not context.concept_config.get('enabled'):
        raise ValidationError('Enable concept selection on the selected stage/event first.')
    anchor = teams[0]
    require_formation_scope(actor, anchor.semester, anchor.level, anchor.section)
    if not anchor.section or any((t.section, t.semester_id, t.year_level, t.is_pit) != (
            anchor.section, anchor.semester_id, anchor.year_level, anchor.is_pit) for t in teams):
        raise ValidationError('Shared-system teams must belong to one section, year, program and semester.')
    from repository.deliverables.concepts import require_context
    require_context(anchor, context)
    if anchor.is_pit and context.is_officially_complete:
        raise ValidationError('A completed event cannot receive a shared-system project.')
    mode = data.get('title_mode', 'student_proposed')
    if mode not in ('student_proposed', 'faculty_provided'):
        raise ValidationError('Choose student-proposed or faculty-provided proposal names.')
    manager_id, reviewer_id = data.get('project_manager_id'), data.get('reviewer_id')
    manager = get_user_model().objects.filter(pk=manager_id, role='student', is_active=True).first()
    enrolled = manager and (StudentAcademicRecord.objects.filter(student=manager,
        semester=anchor.semester, year_level=anchor.year_level, section=anchor.section).exists() or
        StudentTeam.objects.filter(semester=anchor.semester, year_level=anchor.year_level,
            section=anchor.section, memberships__student=manager).exists())
    if not enrolled:
        raise ValidationError('Choose an active student project manager enrolled in this section.')
    reviewer = get_user_model().objects.filter(pk=reviewer_id, role='faculty', is_active=True).first()
    if not reviewer:
        raise ValidationError('Choose an active faculty reviewer for the shared system.')
    if not is_manager(actor) and not SectionInstructorAssignment.objects.filter(faculty=reviewer,
            semester=anchor.semester, year_level=anchor.year_level, section=anchor.section, is_active=True).exists():
        raise PermissionError('The reviewer must be an assigned instructor for this section.')
    section, _ = SectionAssignment.objects.get_or_create(semester=anchor.semester, section=anchor.section,
        defaults={'year_level': anchor.year_level, 'project_manager': manager})
    section = SectionAssignment.objects.select_for_update().get(pk=section.pk)
    if section.year_level != anchor.year_level:
        raise ValidationError('The section contains a different year level.')
    project = SectionConceptProject.objects.select_for_update().filter(section=section, **context_fields(context)).first()
    created = project is None
    added = False
    if project:
        require_active(project)
        if (project.project_manager_id, project.reviewer_id, project.title_mode) != (manager.pk, reviewer.pk, mode):
            raise ValidationError('This shared project already exists. Reassign its responsibilities in its workspace.')
        round = latest(project)
    else:
        project = SectionConceptProject.objects.create(section=section, **context_fields(context),
            project_manager=manager, reviewer=reviewer, title_mode=mode)
        require_active(project)
        round = SectionConceptRound.objects.create(project=project)
        SectionSystemConcept.objects.bulk_create([SectionSystemConcept(round=round, key=k) for k in KEYS])
    for team in teams:
        if project.team_links.filter(team=team, project_version=team.project_version).exists():
            continue
        editable(round)
        existing = ConceptRound.objects.filter(team=team, project_version=team.project_version,
            **context_fields(context)).order_by('-number').first()
        if existing or team.deliverable_submissions.filter(stage_label=context.label).exists():
            raise ValidationError(f'{team.name} already has concept work. Use a new project or an unstarted concept event.')
        SectionProjectTeam.objects.create(project=project, team=team, project_version=team.project_version)
        team._section_concept_projects = {}
        added = True
        team.project_pending = True
        team.save(update_fields=['project_pending', 'updated_at'])
    if created or added:
        invalidate(round)
    audit(actor, 'configured', project, team_ids=[t.pk for t in teams], context=context.pk,
          project_manager_id=manager.pk, reviewer_id=reviewer.pk, title_mode=mode)
    return project


def policy_for(team, context):
    project = project_for(team, context)
    if not project:
        return None
    round = latest(project)
    return {**context.concept_config, 'mode': 'proposals', 'required_count': 3, 'assigned_title': '',
        'source': 'section_system', 'section_project_id': project.pk, 'section_round_id': round.pk,
        'title_mode': project.title_mode, 'system_concepts': list(round.systems.values('id', 'key', 'title'))}


def team_display(team, label=None):
    projects = SectionConceptProject.objects.filter(team_links__team=team,
        team_links__project_version=team.project_version, section__semester_id=team.semester_id,
        section__section=team.section).select_related('project_manager')
    context_label = label or team.current_defense_stage
    if context_label:
        projects = projects.filter(Q(defense_stage__label=context_label) | Q(pit_event_config__event_name=context_label))
    for project in projects:
        round = latest(project)
        selected = round.systems.filter(key=round.selected_key).first() if round.selected_key else None
        return {'system_name': selected.title if selected else '',
                'project_manager_name': project.project_manager.get_full_name() or project.project_manager.username,
                'section_project_id': project.pk}
    return {}


def scheduling_blocker(team, context, current):
    project = project_for(team, context)
    if not project:
        return ''
    round = latest(project)
    if not current or current.section_round_id != round.pk:
        return 'Submit this team’s modules for the current section system proposals.'
    if round.verdict == 'for_redefense':
        return 'The section needs replacement system concepts.'
    if not shared_clearance(round):
        return 'Confirm the shared system titles and accept their current papers before scheduling.'
    if not all(c.get('faculty_confirmed') for c in current.concepts):
        return 'The instructor/adviser must confirm all three module names and system connections.'
    return ''


def can_edit_module_titles(user, team, context, current):
    project = project_for(team, context)
    if not project:
        return True
    if user is None:
        return False
    faculty = can_manage(user, project) or (getattr(user, 'role', '') == 'faculty' and team.adviser_id == user.pk)
    if project.title_mode == 'faculty_provided' and not faculty:
        return False
    if any(c.get('faculty_confirmed') for c in current.concepts) and not faculty:
        return False
    return faculty or (getattr(user, 'role', '') == 'student' and team.leader_id == user.pk)


def module_title_metadata(user, team, context):
    project = project_for(team, context)
    confirmed = bool(project and user and (can_manage(user, project) or (
        getattr(user, 'role', '') == 'faculty' and team.adviser_id == user.pk)))
    return {'faculty_confirmed': confirmed} if project else {}


@transaction.atomic
def save_system_titles(project, actor, titles):
    require_active(project)
    round = locked_round(project)
    editable(round)
    faculty = can_manage(actor, project) or is_reviewer(actor, project)
    if not faculty and (not is_pm(actor, project) or project.title_mode == 'faculty_provided'):
        raise PermissionError('Only the designated project manager can propose names; faculty confirms official names.')
    if not isinstance(titles, list) or len(titles) != 3 or {c.get('key') for c in titles if isinstance(c, dict)} != set(KEYS):
        raise ValidationError('Enter one unique title for each of System A, B and C.')
    keyed = {c['key']: c for c in titles}
    changed = False
    for concept in round.systems.all():
        title = keyed[concept.key].get('title', '')
        if not isinstance(title, str) or not title.strip() or len(title.strip()) > 255:
            raise ValidationError('Every system proposal needs a title of up to 255 characters.')
        if concept.confirmed and not faculty and title.strip() != concept.title:
            raise PermissionError('A faculty-confirmed system name can only be changed by assigned faculty.')
        if (concept.title, concept.confirmed) != (title.strip(), faculty or concept.confirmed):
            if concept.title != title.strip():
                # Acceptance belongs to the reviewed title and file version.
                for paper in concept.papers.filter(is_current=True, status='accepted'):
                    audit(actor, 'paper_review_invalidated', paper, reason='System title changed',
                        previous_title=concept.title, title=title.strip(),
                        reviewed_by=paper.reviewed_by_id,
                        reviewed_at=paper.reviewed_at.isoformat() if paper.reviewed_at else None)
                    paper.status, paper.reviewed_by, paper.reviewed_at = 'pending', None, None
                    paper.save(update_fields=['status', 'reviewed_by', 'reviewed_at'])
            concept.title, concept.confirmed = title.strip(), faculty or concept.confirmed
            concept.save(update_fields=['title', 'confirmed'])
            changed = True
    if changed:
        invalidate(round)
    audit(actor, 'system_names_saved', round, systems=list(round.systems.values('key', 'title', 'confirmed')))


@transaction.atomic
def upload(project, actor, key, file):
    require_active(project)
    round = locked_round(project)
    if not correcting(round, key):
        editable(round)
    if not is_pm(actor, project):
        raise PermissionError('The assigned project manager submits the shared section papers.')
    if file is None or Path(file.name).suffix.lower() != '.pdf' or file.size > 25 * 1024 * 1024:
        raise ValidationError('Upload a PDF concept paper of up to 25 MB.')
    header = file.read(5)
    file.seek(0)
    if header != b'%PDF-':
        raise ValidationError('The uploaded file must contain a PDF document.')
    concept = round.systems.filter(key=key).first()
    if not concept:
        raise ValidationError('Choose a system proposal in this section round.')
    prior = concept.papers.filter(is_current=True).first()
    if prior and prior.status == 'accepted' and not correcting(round, key):
        raise ValidationError('Ask the reviewer to request corrections before replacing an accepted paper.')
    revision = (concept.papers.order_by('-revision').values_list('revision', flat=True).first() or 0) + 1
    concept.papers.filter(is_current=True).update(is_current=False)
    row = SectionConceptPaper.objects.create(concept=concept, file=file, file_name=Path(file.name).name,
        revision=revision, uploaded_by=actor)
    invalidate(round)
    audit(actor, 'paper_uploaded', row, round_id=round.pk, key=key, revision=revision)
    return row


@transaction.atomic
def review(project, actor, paper_id, status, feedback=''):
    require_active(project)
    round = locked_round(project)
    paper_key = SectionConceptPaper.objects.filter(pk=paper_id, concept__round=round).values_list('concept__key', flat=True).first()
    if not correcting(round, paper_key):
        editable(round)
    if not is_reviewer(actor, project):
        raise PermissionError('Only the designated system reviewer can accept these papers.')
    if status not in ('accepted', 'rejected') or not isinstance(feedback, str) or len(feedback) > 5000:
        raise ValidationError('Choose acceptance or corrections and enter valid feedback.')
    if status == 'rejected' and not feedback.strip():
        raise ValidationError('Explain the requested corrections.')
    row = SectionConceptPaper.objects.filter(pk=paper_id, concept__round=round, is_current=True).first()
    if not row:
        raise ValidationError('Review the current paper version from this section round.')
    row.status, row.feedback = status, feedback.strip()
    row.reviewed_by, row.reviewed_at = actor, timezone.now()
    row.save(update_fields=['status', 'feedback', 'reviewed_by', 'reviewed_at'])
    invalidate(round)
    audit(actor, 'paper_reviewed', row, status=status, feedback=feedback)


@transaction.atomic
def clear_revisions(project, actor, remarks):
    require_active(project)
    round = locked_round(project)
    if not is_reviewer(actor, project):
        raise PermissionError('Only the designated system reviewer can clear shared system revisions.')
    if not correcting(round, round.selected_key):
        raise ValidationError('This system has no outstanding shared revision clearance.')
    if not isinstance(remarks, str) or not remarks.strip() or len(remarks) > 5000:
        raise ValidationError('Record how the panel’s shared system revisions were satisfied.')
    paper = SectionConceptPaper.objects.filter(concept__round=round, concept__key=round.selected_key,
        is_current=True, status='accepted').first()
    presented_ids = {p['id'] for p in round.decision_snapshot.get('papers', [])}
    if not paper or paper.pk in presented_ids:
        raise ValidationError('Review and accept a revised paper for the selected system first.')
    from student_teams.models import StudentTeam
    # A concurrent module verdict locks its team before reading shared clearance.
    # Lock participants before reading their grades to avoid applying stale outcomes.
    list(StudentTeam.objects.select_for_update().filter(pk__in=active_links(project).values('team_id')).order_by('pk'))
    round.revisions_cleared_by, round.revisions_cleared_at = actor, timezone.now()
    round.revision_notes, round.endorsement_snapshot = remarks.strip(), snapshot(round)
    round.endorsed_at, round.endorsed_by = round.revisions_cleared_at, actor
    round.save(update_fields=['revisions_cleared_by', 'revisions_cleared_at', 'revision_notes',
        'endorsement_snapshot', 'endorsed_at', 'endorsed_by'])
    from grading.grades.services import _apply_team_result_from_grade, maybe_auto_finalize_passed_grade
    for schedule in round.schedules.all():
        grade = schedule.grade_records.first()
        if grade:
            _apply_team_result_from_grade(grade)
            maybe_auto_finalize_passed_grade(grade, user=actor)
    audit(actor, 'shared_revisions_cleared', round, remarks=remarks, paper_id=paper.pk)


def module_pass_allowed(grade):
    if not grade.schedule_id:
        return True
    from repository.deliverables.models import ConceptRound
    current = ConceptRound.objects.filter(schedule_id=grade.schedule_id,
        section_round__isnull=False).select_related('section_round').first()
    if not current:
        return True
    shared = current.section_round
    return bool(shared.selected_key and (shared.verdict == 'approved' or (
        shared.verdict == 'approved_with_revisions' and shared.revisions_cleared_at)))


def completion_blocker(context, semester):
    from repository.deliverables.concepts import latest_round
    for project in SectionConceptProject.objects.filter(**context_fields(context), section__semester=semester):
        links = list(active_links(project))
        if not links:
            continue
        round = latest(project)
        if not round.selected_key or (round.verdict == 'approved_with_revisions' and not round.revisions_cleared_at):
            return f'{project.section.section} still needs its shared system decision or shared revision clearance.'
        for link in links:
            current = latest_round(link.team, context)
            if not current or current.verdict not in ('approved', 'approved_with_revisions', 'failed', 'project_rejected'):
                return f'{link.team.name} still needs its corresponding module hearing outcome.'
    return ''


@transaction.atomic
def endorse(project, actor):
    # Compatibility for older clients; new clients use automatic clearance.
    require_active(project)
    round = locked_round(project)
    editable(round)
    if not is_reviewer(actor, project):
        raise PermissionError('Only the designated system reviewer can endorse the section papers.')
    if round.systems.exclude(confirmed=True).exists() or round.systems.filter(title='').exists():
        raise ValidationError('Faculty must confirm all three system names before endorsement.')
    if SectionConceptPaper.objects.filter(concept__round=round, is_current=True, status='accepted').count() != 3:
        raise ValidationError('Accept all three current system concept papers before endorsement.')
    round.endorsed_by, round.endorsed_at = actor, timezone.now()
    round.endorsement_snapshot = snapshot(round)
    round.save(update_fields=['endorsed_by', 'endorsed_at', 'endorsement_snapshot'])
    audit(actor, 'endorsed', round, snapshot=round.endorsement_snapshot)


@transaction.atomic
def confirm_modules(project, actor, team_id, titles):
    from repository.deliverables.concepts import save_titles
    link = active_links(project).filter(team_id=team_id).first()
    if not link or not (can_manage(actor, project) or (
            getattr(actor, 'role', '') == 'faculty' and link.team.adviser_id == actor.pk)):
        raise PermissionError('Only the assigned section faculty or this team’s adviser can confirm its modules.')
    require_active(project)
    save_titles(link.team, project.context, titles, actor=actor)
    audit(actor, 'module_names_confirmed', project, team_id=team_id)


def available_schedules(round):
    from defense.scheduler.models import DefenseSchedule
    # A schedule owns one module round; old attempts never substitute for a new attempt.
    return DefenseSchedule.objects.filter(concept_round__section_round=round).exclude(status='cancelled').select_related('team')


@transaction.atomic
def schedule_hearing(project, actor, schedule_ids):
    require_active(project)
    if not can_manage(actor, project):
        raise PermissionError('Only assigned faculty or the scoped lead can assemble this section hearing.')
    round = locked_round(project)
    if round.verdict:
        raise ValidationError('This section hearing already has a system decision.')
    if not shared_clearance(round):
        raise ValidationError('Endorse the current shared system papers before assembling the hearing.')
    if not isinstance(schedule_ids, list) or not schedule_ids or len(set(schedule_ids)) != len(schedule_ids):
        raise ValidationError('Choose exactly one current defense schedule per participating team.')
    schedules = list(available_schedules(round).select_for_update().filter(pk__in=schedule_ids).order_by('pk'))
    expected = set(active_links(project).values_list('team_id', flat=True))
    if len(schedules) != len(schedule_ids) or len(schedules) != len(expected) or {s.team_id for s in schedules} != expected:
        raise ValidationError('Include exactly one schedule for every participating team in this section round.')
    if len({s.scheduled_date for s in schedules}) != 1 or len({s.room for s in schedules}) != 1:
        raise ValidationError('Schedule the section teams on the same day and in the same room.')
    chairs = [s.panel_assignments.filter(is_chair=True).values_list('panelist_id', flat=True).first() for s in schedules]
    if not chairs[0] or len(set(chairs)) != 1:
        raise ValidationError('Assign the same faculty panel chair to all section team schedules.')
    from repository.deliverables.concepts import latest_round
    for schedule in schedules:
        current = latest_round(schedule.team, project.context)
        if not current or current.schedule_id != schedule.pk or scheduling_blocker(schedule.team, project.context, current):
            raise ValidationError('Each scheduled module set must match the current cleared section proposals.')
    round.schedules.set(schedules)
    round.chair_id = chairs[0]
    round.save(update_fields=['chair'])
    audit(actor, 'hearing_assembled', round, schedule_ids=schedule_ids, chair_id=round.chair_id)


def decision_allowed(round, actor):
    if getattr(actor, 'is_guest_panelist', False):
        return False
    if admin(actor):
        return True
    schedules = list(round.schedules.all())
    return bool(schedules and round.chair_id == actor.pk and all(
        s.status != 'cancelled' and s.panel_assignments.filter(panelist=actor, is_chair=True).exists() for s in schedules))


@transaction.atomic
def decide(project, actor, decisions, verdict, remarks):
    require_active(project)
    round = locked_round(project)
    if not decision_allowed(round, actor):
        raise PermissionError('Only the common section panel chair or an administrator can select the system.')
    if round.verdict:
        raise ValidationError('The section system decision has already been recorded.')
    expected = set(active_links(project).values_list('team_id', flat=True))
    schedules = list(round.schedules.select_for_update().exclude(status='cancelled'))
    if not schedules or len(schedules) != len(expected) or {s.team_id for s in schedules} != expected:
        raise ValidationError('Assemble a current hearing containing all participating section teams first.')
    if not shared_clearance(round):
        raise ValidationError('The shared papers are not cleared. Review the current titles and papers first.')
    from defense.scheduler.panelist_evaluation import verdict_unavailable_reason
    from grading.grades.services import GradeContextService
    for schedule in schedules:
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        reason = verdict_unavailable_reason(schedule, grade)
        if reason:
            raise ValidationError(f'{schedule.team.name}: {reason}')
    if verdict not in ('approved', 'approved_with_revisions', 'for_redefense'):
        raise ValidationError('Approve one system or request a new section concept hearing.')
    if not isinstance(remarks, str) or len(remarks) > 5000 or (verdict != 'approved' and not remarks.strip()):
        raise ValidationError('Record the required changes or reason for another hearing.')
    from repository.deliverables.concepts import validate_decisions
    candidate = type('SystemSet', (), {'concepts': [{'key': s.key, 'title': s.title} for s in round.systems.all()]})()
    systems, replacement, selected = validate_decisions(candidate, decisions, verdict, False)
    if verdict == 'for_redefense' and not all(s['decision'] == 'rejected' for s in systems):
        raise ValidationError('Reject all three system proposals to request a replacement section set.')
    for item in systems:
        round.systems.filter(key=item['key']).update(decision=item['decision'], remarks=item['remarks'])
    round.verdict, round.remarks = verdict, remarks.strip()
    round.selected_key = selected[0]['key'] if selected else ''
    round.decided_by, round.decided_at = actor, timezone.now()
    round.decision_snapshot = {**snapshot(round), 'systems': systems,
        'teams': list(active_links(project).values('team_id', 'project_version')),
        'schedule_ids': [s.pk for s in schedules]}
    round.save()
    if verdict == 'for_redefense':
        # Apply the ordinary per-team re-defense machinery so assessments and evidence
        # retain their established lifecycle; the system decision never creates passes.
        from grading.grades.defense_workflow import record_verdict
        for schedule in schedules:
            grade = schedule.grade_records.first()
            record_verdict(grade, actor=actor, verdict='for_redefense', remarks=remarks,
                concept_decisions=[{'key': key, 'decision': 'rejected', 'remarks': remarks} for key in KEYS],
                replacement_concepts_required=True)
        next_round = SectionConceptRound.objects.create(project=project, number=round.number + 1)
        SectionSystemConcept.objects.bulk_create([SectionSystemConcept(round=next_round, key=key) for key in KEYS])
        for module_round in round.module_rounds.filter(schedule__isnull=True):
            module_round.section_round = next_round
            module_round.policy_snapshot = {**module_round.policy_snapshot, 'section_round_id': next_round.pk,
                'system_concepts': list(next_round.systems.values('id', 'key', 'title'))}
            module_round.save(update_fields=['section_round', 'policy_snapshot'])
    audit(actor, 'system_decided', round, verdict=verdict, selected_key=round.selected_key, remarks=remarks)


def validate_module_decision(grade, current, concepts):
    if not current.section_round_id:
        return
    round = current.section_round
    if grade.verdict == 'for_redefense' and round.verdict == 'for_redefense':
        return
    if not round.selected_key:
        raise ValidationError('The section panel chair must select the shared system before module decisions.')
    for c in concepts:
        if c.get('decision') in ('approved', 'approved_with_revisions') and c['key'] != round.selected_key:
            raise ValidationError('Approve only the module linked to the section’s selected system.')


@transaction.atomic
def reassign(project, actor, manager_id, reviewer_id):
    require_active(project)
    if not can_manage(actor, project):
        raise PermissionError('Only assigned section faculty or the scoped lead can reassign responsibilities.')
    from student_teams.formation_access import is_manager
    from user_management.academic_records.models import StudentAcademicRecord
    from user_management.models import SectionInstructorAssignment
    SectionConceptProject.objects.select_for_update().get(pk=project.pk)
    manager = get_user_model().objects.filter(pk=manager_id, role='student', is_active=True).first()
    reviewer = get_user_model().objects.filter(pk=reviewer_id, role='faculty', is_active=True).first()
    if not manager or not StudentAcademicRecord.objects.filter(student=manager,
        semester_id=project.section.semester_id, section=project.section.section,
        year_level=project.section.year_level).exists():
        raise ValidationError('Choose an enrolled student project manager from this section.')
    if not reviewer or (not is_manager(actor) and not SectionInstructorAssignment.objects.filter(faculty=reviewer,
            semester_id=project.section.semester_id, year_level=project.section.year_level,
            section=project.section.section, is_active=True).exists()):
        raise ValidationError('Choose an assigned faculty reviewer for the section.')
    previous = {'project_manager_id': project.project_manager_id, 'reviewer_id': project.reviewer_id}
    project.project_manager, project.reviewer = manager, reviewer
    project.save(update_fields=['project_manager', 'reviewer'])
    audit(actor, 'responsibilities_reassigned', project, before=previous,
          project_manager_id=manager.pk, reviewer_id=reviewer.pk)


def task_payload(user):
    if getattr(user, 'is_guest_panelist', False):
        return []
    tasks = []
    projects = SectionConceptProject.objects.filter(Q(project_manager=user) | Q(reviewer=user),
        section__semester__is_active=True).select_related('section__semester', 'pit_event_config', 'defense_stage')
    for project in projects:
        if not writable(project) or not active_links(project).exists():
            continue
        round = latest(project)
        if not round.verdict and shared_clearance(round):
            continue
        if round.verdict in ('approved', 'approved_with_revisions'):
            if round.verdict == 'approved' or round.revisions_cleared_at:
                continue
        manager = project.project_manager_id == user.pk
        reviewer = project.reviewer_id == user.pk
        if manager or reviewer:
            state = snapshot(round)
            statuses = [paper['status'] for paper in state['papers']]
            status = ('shared_revisions_pending' if round.verdict == 'approved_with_revisions' else
                'papers_missing' if len(statuses) < 3 else 'corrections_requested' if 'rejected' in statuses else
                'awaiting_faculty_review' if 'pending' in statuses else
                'awaiting_name_confirmation' if not all(c['confirmed'] for c in state['systems']) else
                'cleared')
            tasks.append({'project_id': project.pk, 'section': project.section.section,
                'stage_label': project.context.label, 'round': round.number,
                'role': 'project_manager' if manager else 'reviewer',
                'title': (('Submit revised shared system paper' if manager else 'Review and clear shared system revisions')
                    if round.verdict == 'approved_with_revisions' else
                    'Submit three shared system concept papers' if manager else
                    'Confirm system names and review shared concept papers'),
                'status': status, 'status_label': status.replace('_', ' ')})
    return tasks


def payload(project, actor):
    from repository.deliverables.concepts import latest_round
    round = latest(project)
    context = project.context
    can_write = writable(project)
    editable_now = not round.verdict and not round.module_rounds.filter(schedule__isnull=False).exclude(
        schedule__status='cancelled').exists() and can_write
    systems = []
    for concept in round.systems.prefetch_related('papers'):
        papers = list(concept.papers.all())
        current_paper = next((p for p in papers if p.is_current), None)
        systems.append({'id': concept.pk, 'key': concept.key, 'title': concept.title,
            'confirmed': concept.confirmed, 'decision': concept.decision, 'remarks': concept.remarks,
            'can_upload': bool(can_write and is_pm(actor, project) and (correcting(round, concept.key) or
                (editable_now and (not current_paper or current_paper.status != 'accepted')))),
            'can_review': can_write and is_reviewer(actor, project) and correcting(round, concept.key),
            'papers': [{'id': p.pk, 'file_name': p.file_name, 'revision': p.revision,
                'is_current': p.is_current, 'status': p.status, 'feedback': p.feedback,
                'file_url': f'/api/repository/section-concepts/{project.pk}/papers/{p.pk}/'}
                for p in sorted(papers, key=lambda p: p.revision, reverse=True)]})
    teams = []
    for link in active_links(project):
        current = latest_round(link.team, context)
        concepts = deepcopy(current.concepts) if current else [{'key': k, 'title': ''} for k in KEYS]
        from repository.deliverables.services import get_deliverable_definitions_for_team
        from repository.deliverables.models import DeliverableSubmission
        from repository.deliverables.documents import slots_for
        definitions = [d for d in get_deliverable_definitions_for_team(link.team, context.label)
            if d['required'] and d['type'] == 'pre' and d.get('requirement_timing') != 'defense' and
            (d.get('file_policy') or {}).get('mode') == 'concepts']
        submissions = DeliverableSubmission.objects.filter(team=link.team, stage_label=context.label,
            project_version=link.project_version,
            deliverable_id__in=[d['id'] for d in definitions]).prefetch_related('files')
        files = {(s.deliverable_id, f.slot_key): f for s in submissions for f in s.files.all() if f.is_current and f.file}
        for c in concepts:
            c['system_title'] = next((s['title'] for s in systems if s['key'] == c['key']), '')
            required = [(d['id'], slot['key']) for d in definitions for slot in slots_for(d, stage=context)
                if slot.get('required', True) and slot['key'].startswith(f'{c["key"]}:')]
            statuses = [files[key].status if key in files else 'missing' for key in required]
            c['documents_status'] = ('missing' if not statuses or 'missing' in statuses else
                'corrections_requested' if 'rejected' in statuses else
                'accepted' if all(s == 'accepted' for s in statuses) else 'pending_review')
        leader_name = (link.team.leader.get_full_name() or link.team.leader.username) if link.team.leader else ''
        members = [{'id': m.student_id, 'name': m.student.get_full_name() or m.student.username, 'is_leader': m.student_id == link.team.leader_id}
            for m in link.team.memberships.select_related('student').all()]
        teams.append({'id': link.team_id, 'name': link.team.name, 'leader_id': link.team.leader_id,
            'leader_name': leader_name, 'members': members,
            'endorsed': bool(current and current.endorsed_at),
            'concepts': concepts, 'schedule_id': current.schedule_id if current else None,
            'verdict': current.verdict if current else '',
            'can_issue_verdict': bool(can_write and round.selected_key and current and current.schedule_id and not current.verdict and (
                admin(actor) or (getattr(actor, 'role', '') == 'faculty' and current.schedule.panel_assignments.filter(panelist=actor, is_chair=True).exists()))),
            'can_confirm_names': can_write and (can_manage(actor, project) or (
                getattr(actor, 'role', '') == 'faculty' and link.team.adviser_id == actor.pk))})
    current_papers = [p for system in systems for p in system['papers'] if p['is_current']]
    progress = {'required': 3,
        'names_confirmed': sum(bool(s['confirmed'] and s['title'].strip()) for s in systems),
        'papers_uploaded': len(current_papers),
        'papers_accepted': sum(p['status'] == 'accepted' for p in current_papers)}
    manager_options, reviewer_options = [], []
    if can_manage(actor, project):
        from user_management.academic_records.models import StudentAcademicRecord
        from user_management.models import SectionInstructorAssignment
        from student_teams.formation_access import is_manager
        managers = get_user_model().objects.filter(role='student', is_active=True).filter(
            Q(pk__in=StudentAcademicRecord.objects.filter(semester_id=project.section.semester_id,
                section=project.section.section, year_level=project.section.year_level).values('student_id')) |
            Q(pk=project.project_manager_id))
        reviewers = get_user_model().objects.filter(role='faculty', is_active=True)
        if not is_manager(actor):
            reviewers = reviewers.filter(Q(pk=project.reviewer_id) | Q(pk__in=SectionInstructorAssignment.objects.filter(
                semester_id=project.section.semester_id, section=project.section.section,
                year_level=project.section.year_level, is_active=True).values('faculty_id')))
        manager_options = [{'id': u.pk, 'name': u.get_full_name() or u.username} for u in managers.order_by('username')]
        reviewer_options = [{'id': u.pk, 'name': u.get_full_name() or u.username} for u in reviewers.order_by('username')]
    shared_review = review_summary(round)
    return {'id': project.pk, 'section': project.section.section, 'year_level': project.section.year_level,
        'review_token': review_token(round), 'manager_options': manager_options, 'reviewer_options': reviewer_options,
        'can_reassign': can_write,
        'semester_id': project.section.semester_id, 'stage_label': context.label,
        'scope': 'pit' if project.pit_event_config_id else 'capstone', 'round': round.number,
        'round_id': round.pk, 'title_mode': project.title_mode,
        'project_manager_id': project.project_manager_id, 'project_manager_name': project.project_manager.get_full_name() or project.project_manager.username,
        'reviewer_id': project.reviewer_id, 'reviewer_name': project.reviewer.get_full_name() or project.reviewer.username,
        'systems': systems, 'teams': teams, 'selected_key': round.selected_key, 'verdict': round.verdict,
        'remarks': round.remarks, 'endorsed': shared_review['cleared'], 'cleared': shared_review['cleared'],
        'shared_review': shared_review, 'editable': editable_now,
        'review_progress': progress,
        'can_endorse': False,
        'shared_revisions_pending': round.verdict == 'approved_with_revisions' and not round.revisions_cleared_at,
        'can_clear_shared_revisions': round.verdict == 'approved_with_revisions' and not round.revisions_cleared_at and (
            is_reviewer(actor, project)) and can_write,
        'can_manage': can_manage(actor, project),
        'can_edit_names': editable_now and (can_manage(actor, project) or is_reviewer(actor, project) or (
            is_pm(actor, project) and project.title_mode == 'student_proposed')),
        'can_upload': editable_now and is_pm(actor, project),
        'can_review': editable_now and is_reviewer(actor, project),
        'can_decide': not round.verdict and decision_allowed(round, actor) and can_write,
        'hearing_schedule_ids': list(round.schedules.values_list('pk', flat=True)),
        'available_schedules': [{'id': s.pk, 'team_id': s.team_id, 'team_name': s.team.name,
            'date': str(s.scheduled_date), 'time': str(s.start_time), 'room': s.room} for s in available_schedules(round)],
        'history': [{'id': r.pk, 'round': r.number, 'verdict': r.verdict, 'selected_key': r.selected_key,
            'remarks': r.remarks, 'snapshot': r.decision_snapshot} for r in project.rounds.exclude(pk=round.pk)]}
