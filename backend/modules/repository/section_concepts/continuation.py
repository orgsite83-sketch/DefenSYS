"""Carry an approved system across a verified normal Capstone continuation.

The original project, hearing and papers stay in their recorded term. Destination
checklists reference that approval and capture their own requirements and files.
Reads also support continuations recorded before this adapter was introduced.
"""
from django.core.exceptions import ValidationError
from django.db import transaction

from defensys_backend.read_projection import read_memoize


@read_memoize
def has_recorded_source(team):
    return bool(team.is_capstone and not getattr(team, '_recorded_term', None) and
        team.section_project_links.exclude(project__section__semester_id=team.semester_id).exists())


def recorded_access(actor, project):
    from student_teams.models import TeamTermParticipation
    versions = set(project.team_links.values_list('team_id', 'project_version'))
    rows = TeamTermParticipation.objects.filter(team_id__in={team_id for team_id, _ in versions},
        semester_id=project.section.semester_id, closed_at__isnull=False)
    for row in rows:
        if (row.team_id, row.project_version) not in versions:
            continue
        snapshot = row.snapshot
        if actor.pk in set(snapshot.get('member_ids', [])) | {
                snapshot.get('leader_id'), snapshot.get('adviser_id')}:
            return True
    return False


@read_memoize
def source_participation(team):
    from student_teams.continuation_sections import continued_contexts
    from student_teams.participation import roster_ids
    if (not team.is_capstone or not team.section or getattr(team, '_recorded_term', None)
            or getattr(team, '_assessment_semester_id', None)):
        return None
    ids = roster_ids(team)
    contexts = continued_contexts(team.semester, ids)
    sources = []
    for student_id in ids:
        matches = [(row, old) for row, old in contexts.get(student_id, []) if row.team_id == team.pk]
        if len(matches) != 1:
            return None
        sources.append(matches[0][1])
    return sources[0] if sources and len({row.pk for row in sources}) == 1 else None


@read_memoize
def approved_source(team, context=None):
    from student_teams.capstone_context import inherited_stage_ids
    from .models import SectionConceptProject
    from . import services
    old = source_participation(team)
    if not old or (context and hasattr(context, 'event_name')):
        return None
    projects = SectionConceptProject.objects.filter(section__semester=old.semester,
        section__section=old.snapshot.get('section', ''),
        section__year_level=old.snapshot.get('year_level', ''),
        team_links__team=team, team_links__project_version=old.project_version,
        defense_stage_id__in=inherited_stage_ids(team)).select_related(
            'section__semester', 'project_manager', 'reviewer', 'defense_stage').distinct()
    if context:
        projects = projects.filter(defense_stage__display_order__lt=context.display_order)
    approved = []
    for project in projects.order_by('-defense_stage__display_order', '-pk'):
        hearing = services.latest(project)
        if hearing and hearing.selected_key and (hearing.verdict == 'approved' or (
                hearing.verdict == 'approved_with_revisions' and hearing.revisions_cleared_at)):
            selected = hearing.systems.filter(key=hearing.selected_key).first()
            if selected and selected.title.strip():
                approved.append((project, hearing, selected))
    if len({selected.pk for _, _, selected in approved}) > 1:
        raise ValidationError('This continuation has different approved shared systems. Review its project assignment.')
    return approved[0] if approved else None


@read_memoize
def participants(project, *, team=None):
    """Live participants only; historical links never grant new project access."""
    from student_teams.models import StudentTeam
    candidates = StudentTeam.objects.filter(semester__is_active=True,
        section_project_links__project=project,
        level__icontains='Capstone').select_related('semester__school_year', 'adviser').distinct()
    if team:
        candidates = candidates.filter(semester_id=team.semester_id, section=team.section,
            year_level=team.year_level)
    return [member for member in candidates.order_by('pk')
        if (source := approved_source(member)) and source[0].pk == project.pk]


def section_for(team, source):
    """An unsaved adapter makes old continuations readable without GET writes."""
    from student_teams.models import SectionAssignment
    project, _, selected = source
    return SectionAssignment.objects.filter(semester_id=team.semester_id,
        section=team.section, year_level=team.year_level).select_related(
            'semester', 'project_manager').first() or SectionAssignment(
                semester=team.semester, section=team.section, year_level=team.year_level,
                system_name=selected.title, project_manager=project.project_manager)


@transaction.atomic
def materialize_section(team):
    """Called during activation or a normal upload, never during a read."""
    from student_teams.models import SectionAssignment, StudentTeam
    team = StudentTeam.objects.select_for_update().select_related('semester__school_year').get(pk=team.pk)
    source = approved_source(team)
    if not source:
        return None
    project, _, selected = source
    # One section still represents one shared project. Do not silently merge
    # different approved systems after an administrator's section reassignment.
    peers = StudentTeam.objects.filter(semester=team.semester, section=team.section,
        year_level=team.year_level, level__icontains='Capstone')
    for peer in peers:
        other = approved_source(peer)
        if not other or other[0].pk != project.pk:
            raise ValidationError('This section contains different project assignments. Review its shared system first.')
    section, created = SectionAssignment.objects.get_or_create(semester=team.semester,
        section=team.section, defaults={'year_level': team.year_level,
            'system_name': selected.title, 'project_manager': project.project_manager})
    if section.year_level != team.year_level:
        raise ValidationError('The destination section belongs to another year level.')
    if created:
        from student_teams.history_events import record_team_event
        record_team_event(team, 'capstone.shared_system_continued', values={
            'section_id': section.pk, 'source_project_id': project.pk,
            'source_round_id': source[1].pk, 'selected_system_id': selected.pk})
    return section
