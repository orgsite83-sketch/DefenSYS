"""Resolve setup ownership from saved semester evidence, without creating rows."""
from django.db.models import Q

from defensys_backend.read_projection import read_memoize


@read_memoize(copy=True)
def setup_stage_ids(semester):
    from authentication_access_control.models import SystemAuditLog
    from grading.grades.models import TeamGrade
    from student_teams.models import StudentTeam, TeamStageProgress, TeamTermParticipation
    from .models import (DefenseStage, StageGradingConfig, DEFAULT_PANEL_WEIGHT,
                         DEFAULT_ADVISER_WEIGHT, DEFAULT_PEER_WEIGHT)

    definitions = dict(DefenseStage.objects.values_list('pk', 'setup_semester_id'))
    all_ids = set(definitions)
    if semester is None:
        return all_ids
    owned = {pk for pk, term_id in definitions.items() if term_id == semester.pk}
    known = {pk for pk, term_id in definitions.items() if term_id is not None}

    def include(rows):
        for stage_id, term_id in rows:
            known.add(stage_id)
            if term_id == semester.pk and definitions.get(stage_id) in (None, semester.pk):
                owned.add(stage_id)

    # Empty rows are often created by weight lookups during rollover. They do
    # not establish that an administrator set up this stage in the new term.
    configured = StageGradingConfig.objects.filter(
        Q(is_officially_complete=True) | Q(panel_rubric__isnull=False)
        | Q(adviser_rubric__isnull=False) | Q(peer_rubric__isnull=False)
        | ~Q(panel_weight=DEFAULT_PANEL_WEIGHT)
        | ~Q(adviser_weight=DEFAULT_ADVISER_WEIGHT)
        | ~Q(peer_weight=DEFAULT_PEER_WEIGHT) | Q(peer_grading_enabled=True)
        | Q(default_slot_duration_minutes__isnull=False))
    include(configured.values_list('defense_stage_id', 'semester_id'))
    include(TeamGrade.all_objects.filter(scope='capstone').filter(
        Q(status='published') | ~Q(verdict='') | Q(schedule__isnull=False)
        | Q(panel_score__isnull=False) | Q(adviser_score__isnull=False)
        | Q(peer_score__isnull=False)).values_list('defense_stage_id', 'semester_id'))
    include(TeamStageProgress.all_objects.exclude(status=TeamStageProgress.STATUS_LOCKED)
            .values_list('defense_stage_id', 'semester_id'))
    events = SystemAuditLog.objects.filter(action__in=(
        'capstone.stage_created', 'capstone.grading_configuration_changed'))
    include((values.get('defense_stage_id'), values.get('semester_id'))
            for values in events.values_list('new_values', flat=True)
            if values.get('defense_stage_id') and values.get('semester_id'))

    # Captured source requirements prevent unused historical definitions from
    # being silently claimed by a new intake. Open snapshots alone are not
    # setup evidence: older roster imports copied the global stage catalogue.
    for term_id, requirements in TeamTermParticipation.objects.filter(
            closed_at__isnull=False).values_list('semester_id', 'requirements'):
        known.update(row['id'] for row in requirements)
        if term_id == semester.pk:
            owned.update(row['id'] for row in requirements
                if definitions.get(row['id']) in (None, semester.pk))
    # A continuing intake keeps its unfinished source requirements. This is
    # distinct from a new batch, which has no source participation to carry.
    from student_teams.participation import intake_for
    from student_teams.capstone_context import inherited_stage_ids
    # Only closed source terms can contribute source_ids below. Avoid looking up
    # intake/history for every unrelated current team during a one-team action.
    for team in StudentTeam.objects.filter(semester=semester, level__icontains='Capstone',
            term_participations__closed_at__isnull=False).select_related(
            'semester__school_year', 'intake_semester__school_year').distinct():
        intake = intake_for(team)
        if not intake or intake.pk == semester.pk:
            continue
        inherited = set(inherited_stage_ids(team))
        source_ids = {row['id'] for requirements in team.term_participations.filter(
            project_version=team.project_version, closed_at__isnull=False).exclude(semester=semester)
            .values_list('requirements', flat=True) for row in requirements}
        owned.update(DefenseStage.objects.filter(pk__in=source_ids - inherited, is_active=True)
            .values_list('pk', flat=True))
    # Keep initial setup and newly introduced drafts available before their
    # first grading configuration or team evidence exists.
    return owned | (all_ids - known)


def stages_for_semester(semester=None):
    from .grading_config import resolve_semester
    from .models import DefenseStage
    term = semester if hasattr(semester, 'pk') else resolve_semester(semester)
    return DefenseStage.objects.filter(pk__in=setup_stage_ids(term)).order_by('display_order', 'pk')


def stage_for_label(label, *, semester=None, team=None):
    """Resolve labels within their record's term; evidence uses stable stage IDs."""
    from .models import DefenseStage
    if team is not None:
        from student_teams.capstone_lifecycle import requirement_for_label
        requirement = getattr(team, '_capstone_requirement', None) or requirement_for_label(team, label)
        if requirement and requirement['label'] == label:
            return DefenseStage.objects.filter(pk=requirement['id']).first()
        semester = team.semester
    return stages_for_semester(semester).filter(label=label).first()
