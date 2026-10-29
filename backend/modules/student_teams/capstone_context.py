"""Read-only phase/stage projections over existing participation evidence.

An intake continues across academic years. An absent destination configuration
never means that the team's completed source concept should start again.
"""
from django.db.models import Q

from defensys_backend.read_projection import read_memoize


def phase_for(team, semester=None):
    from .participation import intake_for
    from .capstone_lifecycle import transition_kind
    term = semester or team.semester
    intake = intake_for(team)
    if intake and intake.pk == term.pk:
        return 'capstone_1'
    if intake and transition_kind(intake, term) == 'continue':
        return 'capstone_2'
    return 'needs_review'


def phase_label(phase):
    return {'capstone_1': 'Capstone 1', 'capstone_2': 'Capstone 2'}.get(phase, 'Phase needs review')


@read_memoize(copy=True)
def inherited_stage_ids(team):
    from .models import TeamStageProgress
    from grading.grades.models import TeamGrade
    from .capstone_lifecycle import term_key
    row = team.term_participations.filter(semester=team.semester).first()
    if row and 'inherited_stage_ids' in row.snapshot:
        return row.snapshot['inherited_stage_ids']
    # Compatibility for already-migrated teams. Use recorded source evidence,
    # never the new semester's empty grading-config placeholders.
    ids = set()
    for source in team.term_participations.filter(project_version=team.project_version,
            closed_at__isnull=False).select_related('semester__school_year'):
        if term_key(source.semester) >= term_key(team.semester):
            continue
        evidenced = set(TeamStageProgress.all_objects.filter(team=team,
            semester=source.semester, project_version=source.project_version,
            status=TeamStageProgress.STATUS_PASSED).values_list('defense_stage_id', flat=True))
        if source.transition_id and source.outcome == 'open':
            # A successful continuation validated every source prerequisite.
            evidenced.update(TeamGrade.all_objects.filter(team=team,
                semester=source.semester, project_version=source.project_version,
                status='published', verdict__in=('approved', 'approved_with_revisions'))
                .values_list('defense_stage_id', flat=True))
        ids.update(r['id'] for r in source.requirements if r['id'] in evidenced)
    return sorted(ids)


@read_memoize(copy=True)
def phase_requirements(team):
    from .capstone_lifecycle import requirements_for
    inherited = set(inherited_stage_ids(team))
    result = [r for r in requirements_for(team) if r['id'] not in inherited]
    recorded = getattr(team, '_recorded_term', None)
    if recorded:
        from grading.grades.models import TeamGrade
        evidence = set(TeamGrade.all_objects.filter(team=team, semester=team.semester,
            project_version=team.project_version).exclude(status='pending', verdict='', schedule__isnull=True)
            .values_list('defense_stage_id', flat=True))
        evidence.update(team.stage_progress.filter(semester=team.semester,
            project_version=team.project_version).exclude(status='locked').values_list('defense_stage_id', flat=True))
        positions = [i for i, r in enumerate(result) if r['id'] in evidence]
        if positions:
            result = result[:max(positions) + 1]
    return result


def submission_count(team, label):
    if not label:
        return 0
    scope = Q(archive_semester=team.semester)
    if not team.term_participations.exclude(semester=team.semester).exists():
        scope |= Q(archive_semester__isnull=True)
    return team.deliverable_submissions.filter(stage_label=label,
        project_version=team.project_version).filter(scope).count()


@read_memoize(copy=True)
def stage_context(team):
    from defense.stages.models import DefenseStage
    from defense.stages.readiness import stage_setup_readiness
    from .models import TeamStageProgress
    applicable = phase_requirements(team)
    phase = phase_for(team)
    common = {'is_pit': False, 'phase': phase, 'phase_label': phase_label(phase),
        'semester_id': team.semester_id, 'display_semester': team.semester.display_name,
        'has_configured_stages': bool(applicable), 'concept_workflow': None}
    if not applicable:
        return {**common, 'current_stage': None, 'ready_for_stage': None,
            'stage_status': 'awaiting_stage_setup', 'deliverable_count': 0}
    progress = {p.defense_stage_id: p for p in team.stage_progress.filter(
        semester=team.semester, project_version=team.project_version)}
    from grading.grades.models import TeamGrade
    from .capstone_lifecycle import stage_cleared
    grades = {g.defense_stage_id: g for g in TeamGrade.all_objects.filter(team=team,
        semester=team.semester, project_version=team.project_version, status='published')}
    completed = {i for i, p in progress.items() if p.status == TeamStageProgress.STATUS_PASSED}
    for requirement in applicable:
        grade = grades.get(requirement['id'])
        if grade and stage_cleared(team, requirement, grade):
            completed.add(requirement['id'])
    by_label = {r['label']: r for r in applicable}
    current = by_label.get(team.current_defense_stage) or by_label.get(team.ready_for_stage)
    # A stale stored pointer cannot put the UI back in a completed source stage.
    if not getattr(team, '_selected_history_stage', False) and (not current or current['id'] in completed):
        current = next((r for r in applicable if r['id'] not in completed), applicable[-1])
    stage = DefenseStage.objects.filter(pk=current['id']).first()
    item = progress.get(current['id'])
    status = TeamStageProgress.STATUS_PASSED if current['id'] in completed else item.status if item else None
    if not status or status == TeamStageProgress.STATUS_LOCKED:
        config = stage.grading_configs.filter(semester=team.semester).select_related(
            'panel_rubric', 'adviser_rubric', 'peer_rubric').first() if stage else None
        status = 'preparing' if stage and stage_setup_readiness(stage, config, team.semester)['ready'] else 'setup_pending'
    return {**common, 'current_stage': stage.label if stage else current['label'],
        'current_stage_id': current['id'], 'ready_for_stage': team.ready_for_stage
            if team.ready_for_stage in by_label else None,
        'stage_status': status, 'deliverable_count': submission_count(team, current['label'])}
