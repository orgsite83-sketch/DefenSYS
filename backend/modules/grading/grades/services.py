from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from academic_period_management.models import Semester
from defense.scheduler.models import DefenseSchedule
from grading.rubrics.models import Rubric
from student_teams.models import StudentTeam
from .models import GradeBreakdown, PeerEvaluationSubmission, StudentPeerGrade, TeamGrade


ACTIVE_SCHEDULE_STATUSES = [
    DefenseSchedule.STATUS_SCHEDULED,
    DefenseSchedule.STATUS_DONE,
]


def display_name(user):
    if user is None:
        return None
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


def active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def default_weights(scope):
    if scope == TeamGrade.SCOPE_PIT:
        return {'panel_weight': 80, 'peer_weight': 20, 'adviser_weight': 0}
    return {'panel_weight': 50, 'adviser_weight': 30, 'peer_weight': 20}


PANELIST_REMARK_PREFIX = 'Panelist: '
GUEST_PANELIST_REMARK_PREFIX = 'Guest panelist: '


def _panelist_key_from_breakdown_remarks(remarks):
    """Stable grouping key from the first line of panel breakdown remarks."""
    first_line = (remarks or '').split('\n', 1)[0].strip()
    if first_line.startswith(PANELIST_REMARK_PREFIX):
        return first_line
    if first_line.startswith(GUEST_PANELIST_REMARK_PREFIX):
        return first_line
    return first_line or '__unknown_panelist__'


def panelist_percentage_from_breakdowns(breakdowns):
    """panel_pct = sum(score) / sum(max_score) * 100 for one panelist's criteria rows."""
    total_score = sum((row.score for row in breakdowns), Decimal('0'))
    total_max = sum((row.max_score for row in breakdowns), Decimal('0'))
    if total_max <= 0:
        return None
    return (total_score / total_max * Decimal('100')).quantize(Decimal('0.01'))


def panelist_remark_key_for_user(user):
    return f'{PANELIST_REMARK_PREFIX}{user.username}'


def guest_panelist_remark_key(guest_name, guest_code):
    return f'{GUEST_PANELIST_REMARK_PREFIX}{guest_name} ({guest_code})'


def breakdowns_for_panelist(team_grade, panelist_key):
    return [
        row
        for row in team_grade.breakdowns.filter(evaluation_type=GradeBreakdown.EVAL_PANEL).order_by(
            'display_order', 'id'
        )
        if _panelist_key_from_breakdown_remarks(row.remarks) == panelist_key
    ]


def panelist_result_payload(team_grade, panelist_key):
    """Shape one OverallResultsTab row for a panelist's submission on a team grade."""
    rows = breakdowns_for_panelist(team_grade, panelist_key)
    if not rows:
        return None

    team = team_grade.team
    total_score = sum((row.score for row in rows), Decimal('0'))
    total_max = sum((row.max_score for row in rows), Decimal('0'))
    percentage = panelist_percentage_from_breakdowns(rows) or Decimal('0')

    status_map = {
        TeamGrade.STATUS_PUBLISHED: 'Approved',
    }
    team_status = status_map.get(team_grade.status, 'Pending')
    if team_grade.final_grade is not None:
        team_status = 'Approved' if team_grade.final_grade >= Decimal('75.00') else 'Failed'

    panel_w = team_grade.panel_weight
    peer_w = team_grade.peer_weight

    member_grades = []
    panel_contrib = None
    if team_grade.panel_score is not None:
        panel_contrib = float(
            (team_grade.panel_score * Decimal(panel_w) / Decimal('100')).quantize(Decimal('0.01'))
        )

    peer_by_student = {
        pg.student_id: pg for pg in team_grade.peer_member_grades.select_related('student')
    }
    for membership in team.memberships.select_related('student').order_by('order', 'id'):
        student = membership.student
        peer_row = peer_by_student.get(student.id)
        peer_score = float(peer_row.average_score) if peer_row else None
        peer_max = float(peer_row.max_score) if peer_row else None
        final_grade = None
        if team_grade.final_grade is not None and peer_row:
            panel_norm = team_grade.panel_score or Decimal('0')
            peer_norm = peer_row.normalized_score
            final_grade = float(
                (
                    panel_norm * Decimal(panel_w) / Decimal('100')
                    + peer_norm * Decimal(peer_w) / Decimal('100')
                ).quantize(Decimal('0.01'))
            )
        elif team_grade.final_grade is not None:
            final_grade = float(team_grade.final_grade)

        member_grades.append({
            'name': display_name(student),
            'isLeader': membership.is_leader,
            'panelContrib': panel_contrib,
            'peerScore': peer_score,
            'peerMax': peer_max,
            'finalGrade': final_grade,
        })

    return {
        'teamName': team.name,
        'projectTitle': team.project_title or '',
        'percentage': float(percentage),
        'total': float(total_score),
        'max': float(total_max),
        'teamStatus': team_status,
        'level': team.year_level or '',
        'criteria': [
            {
                'criteriaName': row.criterion_name,
                'score': float(row.score),
                'max': float(row.max_score),
            }
            for row in rows
        ],
        'memberGrades': member_grades,
        'weights': {
            'panel': panel_w,
            'peer': peer_w,
            **({'adviser': team_grade.adviser_weight} if team_grade.is_capstone and team_grade.adviser_weight else {}),
        },
        '_sort_date': team_grade.schedule.scheduled_date if team_grade.schedule_id else None,
        '_sort_time': team_grade.schedule.start_time if team_grade.schedule_id else None,
    }


def recompute_panel_score(team_grade):
    """
    Set team_grade.panel_score to the arithmetic mean of each panelist's percentage.

    panel_score = mean(panelist_i percentage), where each panelist_i percentage is
    sum(criterion scores) / sum(criterion max scores) * 100 from their GradeBreakdown rows.
    """
    breakdowns = list(
        team_grade.breakdowns.filter(evaluation_type=GradeBreakdown.EVAL_PANEL).order_by(
            'display_order', 'id'
        )
    )
    if not breakdowns:
        team_grade.panel_score = None
        team_grade.save()
        return team_grade.panel_score

    by_panelist = {}
    for row in breakdowns:
        key = _panelist_key_from_breakdown_remarks(row.remarks)
        by_panelist.setdefault(key, []).append(row)

    percentages = []
    for rows in by_panelist.values():
        pct = panelist_percentage_from_breakdowns(rows)
        if pct is not None:
            percentages.append(pct)

    if not percentages:
        team_grade.panel_score = None
    else:
        team_grade.panel_score = (
            sum(percentages, Decimal('0')) / Decimal(len(percentages))
        ).quantize(Decimal('0.01'))
    team_grade.save()
    return team_grade.panel_score


def weights_for_schedule(schedule):
    if schedule and schedule.scope == TeamGrade.SCOPE_CAPSTONE and schedule.defense_stage_id:
        from defense.stages.grading_config import weights_for_capstone_stage

        return weights_for_capstone_stage(schedule.defense_stage, schedule.semester)

    if schedule and schedule.scope == TeamGrade.SCOPE_PIT:
        from defense.scheduler.pit_config import weights_for_pit_event

        label = schedule.event_name or schedule.stage_label
        return weights_for_pit_event(schedule.semester, label)

    if schedule and schedule.rubric_id:
        rubric = schedule.rubric
        return {
            'panel_weight': rubric.panel_weight,
            'adviser_weight': rubric.adviser_weight,
            'peer_weight': rubric.peer_weight,
        }
    return default_weights(schedule.scope if schedule else TeamGrade.SCOPE_CAPSTONE)


def grade_queryset():
    return (
        TeamGrade.objects.select_related(
            'schedule',
            'schedule__rubric',
            'schedule__defense_stage',
            'team',
            'team__leader',
            'team__adviser',
            'semester',
            'semester__school_year',
            'published_by',
        )
        .prefetch_related(
            'breakdowns',
            'breakdowns__rubric',
            'peer_member_grades',
            'peer_member_grades__student',
            'team__memberships',
            'team__memberships__student',
            'schedule__panel_assignments',
            'schedule__panel_assignments__panelist',
        )
    )


def _is_pit_lead_only(user):
    return bool(
        user
        and getattr(user, 'is_authenticated', False)
        and getattr(user, 'is_pit_lead', False)
        and getattr(user, 'role', None) != 'admin'
        and not getattr(user, 'is_superuser', False)
    )


def grade_queryset_for_user(user):
    queryset = grade_queryset()
    if _is_pit_lead_only(user):
        queryset = queryset.filter(
            scope=TeamGrade.SCOPE_PIT,
            team__level__icontains='PIT',
            team__year_level=getattr(user, 'pit_lead_year', None),
        ).exclude(team__year_level='3rd Year', semester__label=Semester.SECOND)
    return queryset


def schedule_queryset_for_user(user):
    queryset = (
        DefenseSchedule.objects.select_related(
            'semester',
            'semester__school_year',
            'team',
            'team__leader',
            'team__adviser',
            'defense_stage',
            'rubric',
        )
        .filter(status__in=ACTIVE_SCHEDULE_STATUSES)
        .order_by('scheduled_date', 'start_time', 'team__name')
    )
    if _is_pit_lead_only(user):
        queryset = queryset.filter(
            scope=DefenseSchedule.SCOPE_PIT,
            team__level__icontains='PIT',
            team__year_level=getattr(user, 'pit_lead_year', None),
        ).exclude(team__year_level='3rd Year', semester__label=Semester.SECOND)
    return queryset


def _scope_for_team(team):
    return TeamGrade.SCOPE_CAPSTONE if team.is_capstone else TeamGrade.SCOPE_PIT


def _context_for_team(team):
    return team.current_defense_stage or team.ready_for_stage or 'Unscheduled'


def _grade_has_score_data(grade):
    return (
        grade.panel_score is not None
        or grade.adviser_score is not None
        or grade.peer_score is not None
        or grade.breakdowns.exists()
        or grade.peer_member_grades.exists()
        or grade.peer_evaluation_submissions.exists()
    )


def _merge_stale_grade(stale, canonical):
    score_fields = ('panel_score', 'adviser_score', 'peer_score')
    for field in score_fields:
        if getattr(stale, field) is not None and getattr(canonical, field) is None:
            setattr(canonical, field, getattr(stale, field))

    if stale.status in TeamGrade.LOCKED_STATUSES and canonical.status not in TeamGrade.LOCKED_STATUSES:
        canonical.status = stale.status
        canonical.published_by = stale.published_by
        canonical.published_at = stale.published_at

    stale.breakdowns.update(team_grade=canonical)
    stale.peer_member_grades.update(team_grade=canonical)
    stale.peer_evaluation_submissions.update(team_grade=canonical)
    stale.delete()
    canonical.save()


def canonical_capstone_grade_for_team(team, semester=None, stage_label=None):
    """Prefer the scheduled capstone grade row; fall back to team stage context."""
    semester_obj = semester
    if semester_obj is None:
        semester_obj = team.semester
    elif isinstance(semester_obj, int):
        semester_obj = Semester.objects.filter(pk=semester_obj).first()
    if semester_obj is None:
        return None

    schedule = (
        DefenseSchedule.objects.filter(
            team=team,
            semester=semester_obj,
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            status__in=ACTIVE_SCHEDULE_STATUSES,
        )
        .select_related('defense_stage')
        .order_by('-scheduled_date', '-start_time', '-id')
        .first()
    )

    resolved_label = (stage_label or '').strip()
    if not resolved_label and schedule:
        resolved_label = schedule.stage_label or ''
    if not resolved_label:
        resolved_label = _context_for_team(team)

    if schedule:
        grade = TeamGrade.objects.filter(
            team=team,
            semester=semester_obj,
            scope=TeamGrade.SCOPE_CAPSTONE,
            schedule=schedule,
        ).first()
        if grade is not None:
            return grade

    grade = (
        TeamGrade.objects.filter(
            team=team,
            semester=semester_obj,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label=resolved_label,
        )
        .order_by('-updated_at', '-id')
        .first()
    )
    if grade is not None:
        return grade

    return (
        TeamGrade.objects.filter(
            team=team,
            semester=semester_obj,
            scope=TeamGrade.SCOPE_CAPSTONE,
        )
        .order_by('-updated_at', '-id')
        .first()
    )


def _cleanup_stale_capstone_grades_for_team(canonical, team, semester):
    if canonical.scope != TeamGrade.SCOPE_CAPSTONE:
        return
    semester_id = semester.pk if hasattr(semester, 'pk') else semester
    stale_grades = TeamGrade.objects.filter(
        team_id=team.pk,
        semester_id=semester_id,
        scope=TeamGrade.SCOPE_CAPSTONE,
    ).exclude(pk=canonical.pk)

    for stale in stale_grades:
        if _grade_has_score_data(stale):
            _merge_stale_grade(stale, canonical)
        else:
            stale.delete()

    canonical.refresh_from_db()
    from .models import PeerEvaluationSubmission

    if PeerEvaluationSubmission.objects.filter(team_grade=canonical).exists():
        from .peer_eval import sync_peer_summaries

        sync_peer_summaries(canonical)


def resolve_canonical_capstone_grade(grade):
    if grade.scope != TeamGrade.SCOPE_CAPSTONE:
        return grade
    canonical = canonical_capstone_grade_for_team(grade.team, grade.semester, grade.stage_label)
    if canonical is None:
        return grade
    if canonical.pk != grade.pk:
        if _grade_has_score_data(grade):
            _merge_stale_grade(grade, canonical)
        else:
            grade.delete()
        canonical.refresh_from_db()
    return canonical


def adviser_capstone_grades_for_user(user):
    """One canonical capstone grade row per advised team."""
    sync_missing_grade_rows(user=user)
    grades = (
        grade_queryset()
        .filter(team__adviser=user, scope=TeamGrade.SCOPE_CAPSTONE)
        .select_related('team', 'team__semester')
        .order_by('team__name', 'stage_label')
    )
    seen_teams = set()
    canonical_rows = []
    for grade in grades:
        team_id = grade.team_id
        if team_id in seen_teams:
            continue
        seen_teams.add(team_id)
        canonical = resolve_canonical_capstone_grade(grade)
        if canonical is not None:
            canonical_rows.append(canonical)
    return canonical_rows


def _is_stale_placeholder(stale, canonical, schedule):
    if stale.pk == canonical.pk:
        return False
    if stale.schedule_id and stale.schedule_id != schedule.id:
        return False
    if stale.schedule_id is not None:
        return False
    if stale.stage_label == canonical.stage_label:
        return False
    return True


def _cleanup_stale_grades_for_schedule(canonical, schedule):
    if schedule.scope == TeamGrade.SCOPE_CAPSTONE:
        _cleanup_stale_capstone_grades_for_team(canonical, schedule.team, schedule.semester)
        return

    stale_grades = TeamGrade.objects.filter(
        team_id=schedule.team_id,
        semester_id=schedule.semester_id,
        scope=schedule.scope,
    ).exclude(pk=canonical.pk)

    for stale in stale_grades:
        if not _is_stale_placeholder(stale, canonical, schedule):
            continue
        if _grade_has_score_data(stale):
            _merge_stale_grade(stale, canonical)
        else:
            stale.delete()


def _is_stale_unscheduled_placeholder(stale, canonical):
    if stale.pk == canonical.pk:
        return False
    if stale.schedule_id is not None:
        return False
    if stale.stage_label == canonical.stage_label:
        return False
    return True


def _cleanup_stale_grades_for_unscheduled_team(canonical, team):
    scope = _scope_for_team(team)
    if scope == TeamGrade.SCOPE_CAPSTONE:
        _cleanup_stale_capstone_grades_for_team(canonical, team, team.semester)
        return

    stale_grades = TeamGrade.objects.filter(
        team_id=team.pk,
        semester_id=team.semester_id,
        scope=scope,
    ).exclude(pk=canonical.pk)

    for stale in stale_grades:
        if not _is_stale_unscheduled_placeholder(stale, canonical):
            continue
        if _grade_has_score_data(stale):
            _merge_stale_grade(stale, canonical)
        else:
            stale.delete()


def _sync_grade_for_schedule(schedule):
    stage_label = schedule.stage_label or 'Defense'
    weights = weights_for_schedule(schedule)
    grade, created = TeamGrade.objects.get_or_create(
        team=schedule.team,
        semester=schedule.semester,
        scope=schedule.scope,
        stage_label=stage_label,
        defaults={
            'schedule': schedule,
            **weights,
        },
    )

    changed = False
    if grade.schedule_id != schedule.id:
        grade.schedule = schedule
        changed = True
    if grade.status not in TeamGrade.LOCKED_STATUSES:
        for field, value in weights.items():
            if getattr(grade, field) != value:
                setattr(grade, field, value)
                changed = True
    if changed:
        grade.save()
    _cleanup_stale_grades_for_schedule(grade, schedule)
    return grade, created, changed


def _sync_unscheduled_team(team):
    scope = _scope_for_team(team)
    stage_label = _context_for_team(team)
    weights = default_weights(scope)
    grade, created = TeamGrade.objects.get_or_create(
        team=team,
        semester=team.semester,
        scope=scope,
        stage_label=stage_label,
        defaults=weights,
    )
    _cleanup_stale_grades_for_unscheduled_team(grade, team)
    return grade, created


@transaction.atomic
def sync_missing_grade_rows(user=None):
    created = 0
    updated = 0

    for schedule in schedule_queryset_for_user(user):
        _, made, changed = _sync_grade_for_schedule(schedule)
        if made:
            created += 1
        elif changed:
            updated += 1

    semester = active_semester()
    if semester is not None:
        scheduled_team_ids = set(
            DefenseSchedule.objects.filter(
                semester=semester,
                status__in=ACTIVE_SCHEDULE_STATUSES,
            ).values_list('team_id', flat=True)
        )
        teams = StudentTeam.objects.select_related('semester', 'leader', 'adviser').filter(
            semester=semester,
        ).exclude(pk__in=scheduled_team_ids)
        if _is_pit_lead_only(user):
            teams = teams.filter(
                level__icontains='PIT',
                year_level=getattr(user, 'pit_lead_year', None),
            ).exclude(year_level='3rd Year', semester__label=Semester.SECOND)

        for team in teams:
            _, made = _sync_unscheduled_team(team)
            if made:
                created += 1

    return {'created': created, 'updated': updated}


def _stage_grading_config_for_grade(grade):
    from defense.stages.grading_config import get_or_create_stage_grading_config
    from defense.stages.models import DefenseStage

    stage = None
    if grade.schedule and grade.schedule.defense_stage_id:
        stage = grade.schedule.defense_stage
    else:
        stage = DefenseStage.objects.filter(label=grade.stage_label).first()
    if stage is None:
        return None
    return get_or_create_stage_grading_config(stage, grade.semester)


def find_matching_rubric(grade, evaluation_type):
    if grade.scope == TeamGrade.SCOPE_CAPSTONE:
        if evaluation_type == Rubric.EVAL_PANEL and grade.schedule and grade.schedule.rubric_id:
            return grade.schedule.rubric
        config = _stage_grading_config_for_grade(grade)
        if config is not None:
            if evaluation_type == Rubric.EVAL_PANEL and config.panel_rubric_id:
                return (
                    Rubric.objects.select_related('defense_stage')
                    .prefetch_related('criteria')
                    .filter(pk=config.panel_rubric_id)
                    .first()
                )
            if evaluation_type == Rubric.EVAL_ADVISER and config.adviser_rubric_id:
                return (
                    Rubric.objects.select_related('defense_stage')
                    .prefetch_related('criteria')
                    .filter(pk=config.adviser_rubric_id)
                    .first()
                )
            if evaluation_type == Rubric.EVAL_PEER and config.peer_rubric_id:
                return (
                    Rubric.objects.select_related('defense_stage')
                    .prefetch_related('criteria')
                    .filter(pk=config.peer_rubric_id)
                    .first()
                )

    elif evaluation_type == Rubric.EVAL_PANEL and grade.schedule and grade.schedule.rubric_id:
        return grade.schedule.rubric

    queryset = (
        Rubric.objects.select_related('defense_stage')
        .prefetch_related('criteria')
        .filter(
            semester=grade.semester,
            scope=grade.scope,
            evaluation_type=evaluation_type,
            status=Rubric.STATUS_PUBLISHED,
        )
    )
    if grade.scope == TeamGrade.SCOPE_CAPSTONE:
        if grade.schedule and grade.schedule.defense_stage_id:
            queryset = queryset.filter(defense_stage=grade.schedule.defense_stage)
        else:
            queryset = queryset.filter(defense_stage__label=grade.stage_label)
        return queryset.order_by('-updated_at', 'name').first()

    if evaluation_type == Rubric.EVAL_PEER:
        from defense.scheduler.pit_config import peer_rubric_for_pit_event

        rubric = peer_rubric_for_pit_event(grade.semester, grade.stage_label)
        if rubric is not None:
            return (
                Rubric.objects.select_related('defense_stage')
                .prefetch_related('criteria')
                .filter(pk=rubric.pk)
                .first()
            )

    return queryset.order_by('-updated_at', 'name').first()


def assigned_adviser_rubric_payload(grade):
    rubric = find_matching_rubric(grade, Rubric.EVAL_ADVISER)
    if rubric is None:
        return {
            'assigned_adviser_rubric_id': None,
            'assigned_adviser_rubric_name': None,
            'assigned_adviser_rubric_scale': None,
            'assigned_adviser_criteria': [],
        }
    criteria = [
        {
            'name': criterion.name,
            'description': criterion.description,
            'max_score': criterion.max_score,
            'display_order': criterion.display_order,
        }
        for criterion in rubric.criteria.all().order_by('display_order', 'id')
    ]
    return {
        'assigned_adviser_rubric_id': rubric.id,
        'assigned_adviser_rubric_name': rubric.name,
        'assigned_adviser_rubric_scale': rubric.scale,
        'assigned_adviser_criteria': criteria,
    }


def _fallback_criteria(evaluation_type):
    if evaluation_type == Rubric.EVAL_ADVISER:
        return [
            {'name': 'Research Quality', 'max_score': Decimal('10')},
            {'name': 'Technical Depth', 'max_score': Decimal('10')},
            {'name': 'Documentation', 'max_score': Decimal('10')},
        ]
    if evaluation_type == Rubric.EVAL_PEER:
        return [
            {'name': 'Teamwork', 'max_score': Decimal('5')},
            {'name': 'Contribution', 'max_score': Decimal('5')},
        ]
    return [
        {'name': 'Technical Feasibility', 'max_score': Decimal('10')},
        {'name': 'Presentation and Defense', 'max_score': Decimal('10')},
        {'name': 'Project Quality', 'max_score': Decimal('10')},
    ]


def rebuild_component_breakdown(grade, evaluation_type, ratio):
    rubric = find_matching_rubric(grade, evaluation_type)
    criteria = list(rubric.criteria.all()) if rubric else []
    if criteria:
        rows = [
            {
                'name': criterion.name,
                'max_score': Decimal(str(criterion.max_score)),
                'display_order': criterion.display_order,
            }
            for criterion in criteria
        ]
    else:
        rows = [
            {**item, 'display_order': index}
            for index, item in enumerate(_fallback_criteria(evaluation_type))
        ]

    GradeBreakdown.objects.filter(team_grade=grade, evaluation_type=evaluation_type).delete()
    breakdowns = []
    total = Decimal('0.00')
    max_total = Decimal('0.00')
    for row in rows:
        max_score = Decimal(row['max_score'])
        score = (max_score * ratio).quantize(Decimal('0.01'))
        total += score
        max_total += max_score
        breakdowns.append(
            GradeBreakdown(
                team_grade=grade,
                rubric=rubric,
                evaluation_type=evaluation_type,
                criterion_name=row['name'],
                score=score,
                max_score=max_score,
                display_order=row['display_order'],
            )
        )
    GradeBreakdown.objects.bulk_create(breakdowns)
    if max_total <= 0:
        return None
    return (total / max_total * Decimal('100')).quantize(Decimal('0.01'))


def rebuild_peer_member_grades(grade):
    StudentPeerGrade.objects.filter(team_grade=grade).delete()
    memberships = list(grade.team.memberships.select_related('student').all())
    if not memberships:
        return Decimal('88.00')

    peer_rows = []
    normalized_total = Decimal('0.00')
    for index, membership in enumerate(memberships):
        average = Decimal('4.20') + (Decimal(index % 4) * Decimal('0.20'))
        if average > Decimal('4.90'):
            average = Decimal('4.90')
        peer_rows.append(
            StudentPeerGrade(
                team_grade=grade,
                student=membership.student,
                average_score=average,
                max_score=Decimal('5.00'),
            )
        )
        normalized_total += average / Decimal('5.00') * Decimal('100')

    StudentPeerGrade.objects.bulk_create(peer_rows)
    return (normalized_total / Decimal(len(peer_rows))).quantize(Decimal('0.01'))


def group_settings_key(scope, stage_label):
    return f'{scope}|{(stage_label or "").strip()}'


def _default_group_settings(scope, stage_label):
    return {
        'scope': scope,
        'stage_label': stage_label or '',
        'is_officially_complete': False,
        'peer_grading_enabled': False,
    }


def _pit_group_settings(semester, stage_label):
    from defense.scheduler.pit_config import get_pit_event_config, pit_event_config_payload

    config = get_pit_event_config(semester, stage_label)
    if config is None:
        return _default_group_settings(TeamGrade.SCOPE_PIT, stage_label)
    payload = pit_event_config_payload(config)
    return {
        'scope': TeamGrade.SCOPE_PIT,
        'stage_label': config.event_name,
        'is_officially_complete': payload['is_officially_complete'],
        'peer_grading_enabled': payload['peer_grading_enabled'],
        'panel_weight': payload['panel_weight'],
        'peer_weight': payload['peer_weight'],
        'peer_complete_team_count': 0,
        'peer_total_team_count': 0,
    }


def _capstone_group_settings(semester, stage_label):
    from defense.stages.grading_config import get_or_create_stage_grading_config, grading_config_payload
    from defense.stages.models import DefenseStage

    stage = DefenseStage.objects.filter(label=stage_label).first()
    if stage is None:
        return _default_group_settings(TeamGrade.SCOPE_CAPSTONE, stage_label)
    config = get_or_create_stage_grading_config(stage, semester)
    payload = grading_config_payload(config)
    return {
        'scope': TeamGrade.SCOPE_CAPSTONE,
        'stage_label': stage.label,
        'is_officially_complete': payload['is_officially_complete'],
        'peer_grading_enabled': payload['peer_grading_enabled'],
        'panel_weight': payload['panel_weight'],
        'adviser_weight': payload['adviser_weight'],
        'peer_weight': payload['peer_weight'],
        'peer_complete_team_count': 0,
        'peer_total_team_count': 0,
    }


def group_settings_for_grade(grade):
    if grade.scope == TeamGrade.SCOPE_PIT:
        return _pit_group_settings(grade.semester, grade.stage_label)
    return _capstone_group_settings(grade.semester, grade.stage_label)


def build_group_settings_map(grades_queryset, semester):
    if semester is None:
        return {}
    from defense.scheduler.models import PitEventGradingConfig
    from defense.stages.models import DefenseStage

    result = {}

    def _put(scope, label):
        key = group_settings_key(scope, label)
        if key in result:
            return
        if scope == TeamGrade.SCOPE_PIT:
            result[key] = _pit_group_settings(semester, label)
        else:
            result[key] = _capstone_group_settings(semester, label)

    for scope, stage_label in grades_queryset.values_list('scope', 'stage_label').distinct():
        _put(scope, (stage_label or '').strip())

    for stage in DefenseStage.objects.filter(is_active=True).order_by('display_order', 'label'):
        _put(TeamGrade.SCOPE_CAPSTONE, stage.label)

    for config in PitEventGradingConfig.objects.filter(semester=semester):
        _put(TeamGrade.SCOPE_PIT, config.event_name)

    return result


PASS_GRADE_THRESHOLD = Decimal('75.00')


def _apply_team_result_from_grade(grade):
    next_status = (
        StudentTeam.STATUS_APPROVED
        if grade.final_grade is not None and grade.final_grade >= PASS_GRADE_THRESHOLD
        else StudentTeam.STATUS_FAILED
    )
    if grade.team.status != next_status:
        grade.team.status = next_status
        grade.team.save(update_fields=['status', 'updated_at'])


def finalize_passed_grade_for_archive(grade, user=None):
    grade.recalculate()
    if not grade.is_complete:
        raise ValidationError({'status': 'Only complete grades can be finalized for archive.'})
    if grade.final_grade is None or grade.final_grade < PASS_GRADE_THRESHOLD:
        raise ValidationError({'status': 'Only passed grades can be finalized for archive.'})
    if grade.status == TeamGrade.STATUS_PUBLISHED:
        return grade

    grade.status = TeamGrade.STATUS_READY_FOR_ARCHIVE
    grade.published_by = user
    grade.published_at = timezone.now()
    grade.save()

    if grade.schedule_id and grade.schedule.status != DefenseSchedule.STATUS_DONE:
        grade.schedule.status = DefenseSchedule.STATUS_DONE
        grade.schedule.save(update_fields=['status', 'updated_at'])

    _apply_team_result_from_grade(grade)
    return grade


finalize_passed_pit_grade_for_archive = finalize_passed_grade_for_archive


def _empty_auto_finalize_result():
    return {
        'ready_for_archive_count': 0,
        'published_count': 0,
        'skipped_incomplete': 0,
        'skipped_below_threshold': 0,
    }


def _peer_gate_applies_for_group(semester, scope, stage_label, config):
    """Whether peer completion must be satisfied before closing this group."""
    label = (stage_label or '').strip()
    grade_ids = TeamGrade.objects.filter(
        semester=semester,
        scope=scope,
        stage_label__iexact=label,
    ).values_list('id', flat=True)
    if not grade_ids:
        return False
    has_submissions = PeerEvaluationSubmission.objects.filter(
        team_grade_id__in=grade_ids,
    ).exists()
    if scope == TeamGrade.SCOPE_PIT:
        if getattr(config, 'peer_grading_enabled', False):
            return True
        return has_submissions
    return has_submissions


def incomplete_peer_teams_for_group(semester, scope, stage_label, *, config=None):
    from .peer_eval import is_team_peer_eval_complete, peer_completion_summary

    label = (stage_label or '').strip()
    grades = TeamGrade.objects.filter(
        semester=semester,
        scope=scope,
        stage_label__iexact=label,
    ).select_related('team')
    incomplete = []
    for grade in grades:
        if is_team_peer_eval_complete(grade):
            continue
        summary = peer_completion_summary(grade)
        incomplete.append(
            {
                'team_id': grade.team_id,
                'team_name': grade.team.name,
                'grade_id': grade.id,
                'submitted': summary['submitted'],
                'required': summary['required'],
                'evaluators_done': summary['evaluators_done'],
                'evaluators_total': summary['evaluators_total'],
            }
        )
    return incomplete


def peer_completion_counts_for_group(semester, scope, stage_label):
    from .peer_eval import is_team_peer_eval_complete

    label = (stage_label or '').strip()
    grades = TeamGrade.objects.filter(
        semester=semester,
        scope=scope,
        stage_label__iexact=label,
    )
    total = grades.count()
    complete = sum(1 for grade in grades if is_team_peer_eval_complete(grade))
    return {'peer_complete_team_count': complete, 'peer_total_team_count': total}


def _auto_finalize_passed_grades_in_queryset(grades, user=None):
    from .peer_eval import is_team_peer_eval_complete, peer_submission_count

    ready_count = 0
    skipped_incomplete = 0
    skipped_below_threshold = 0

    for grade in grades:
        grade.recalculate()
        if peer_submission_count(grade) > 0 and not is_team_peer_eval_complete(grade):
            skipped_incomplete += 1
            continue
        if not grade.is_complete:
            skipped_incomplete += 1
            continue
        if grade.final_grade is None or grade.final_grade < PASS_GRADE_THRESHOLD:
            skipped_below_threshold += 1
            continue
        if grade.status in TeamGrade.LOCKED_STATUSES:
            continue
        finalize_passed_grade_for_archive(grade, user=user)
        ready_count += 1

    return {
        'ready_for_archive_count': ready_count,
        'published_count': ready_count,
        'skipped_incomplete': skipped_incomplete,
        'skipped_below_threshold': skipped_below_threshold,
    }


def auto_publish_passed_grades_for_event(semester, event_name, user=None):
    label = (event_name or '').strip()
    if not label:
        return _empty_auto_finalize_result()

    grades = TeamGrade.objects.filter(
        semester=semester,
        scope=TeamGrade.SCOPE_PIT,
        stage_label__iexact=label,
    ).select_related('team', 'schedule')
    return _auto_finalize_passed_grades_in_queryset(grades, user=user)


def auto_finalize_passed_capstone_grades_for_stage(semester, stage_label, user=None):
    label = (stage_label or '').strip()
    if not label:
        return _empty_auto_finalize_result()

    grades = TeamGrade.objects.filter(
        semester=semester,
        scope=TeamGrade.SCOPE_CAPSTONE,
        stage_label__iexact=label,
    ).select_related('team', 'schedule')
    return _auto_finalize_passed_grades_in_queryset(grades, user=user)


def maybe_auto_finalize_passed_grade(grade, user=None):
    settings = group_settings_for_grade(grade)
    if not settings.get('is_officially_complete'):
        return grade
    grade.recalculate()
    if grade.status in TeamGrade.LOCKED_STATUSES:
        return grade
    if (
        grade.is_complete
        and grade.final_grade is not None
        and grade.final_grade >= PASS_GRADE_THRESHOLD
    ):
        return finalize_passed_grade_for_archive(grade, user=user)
    return grade


maybe_auto_publish_passed_grade = maybe_auto_finalize_passed_grade


def repair_pending_passed_grades_in_queryset(queryset, user=None):
    """Finalize passed grades still pending when their stage/event is officially complete."""
    pending = queryset.filter(status=TeamGrade.STATUS_PENDING).select_related(
        'team', 'schedule', 'semester'
    )
    for grade in pending:
        maybe_auto_finalize_passed_grade(grade, user=user)


def update_group_settings(
    *,
    semester,
    scope,
    stage_label,
    is_officially_complete=None,
    peer_grading_enabled=None,
    user=None,
):
    label = (stage_label or '').strip()
    if not label:
        raise ValidationError({'stage_label': 'Stage or event label is required.'})

    update_fields = []
    if scope == TeamGrade.SCOPE_PIT:
        from defense.scheduler.models import PitEventGradingConfig

        config = PitEventGradingConfig.objects.filter(
            semester=semester,
            event_name__iexact=label,
        ).first()
        if config is None:
            raise ValidationError({'stage_label': f'No PIT event configuration found for "{label}".'})
    else:
        from defense.stages.models import DefenseStage, StageGradingConfig

        stage = DefenseStage.objects.filter(label=label).first()
        if stage is None:
            raise ValidationError({'stage_label': f'No defense stage found for "{label}".'})
        config = StageGradingConfig.objects.filter(semester=semester, defense_stage=stage).first()
        if config is None:
            from defense.stages.grading_config import get_or_create_stage_grading_config

            config = get_or_create_stage_grading_config(stage, semester)

    if is_officially_complete is True:
        if _peer_gate_applies_for_group(semester, scope, label, config):
            incomplete = incomplete_peer_teams_for_group(
                semester,
                scope,
                label,
                config=config,
            )
            if incomplete:
                raise ValidationError(
                    {
                        'detail': (
                            'Cannot mark officially complete until every team '
                            'finishes peer evaluation.'
                        ),
                        'incomplete_teams': incomplete,
                    }
                )

    if is_officially_complete is not None:
        config.is_officially_complete = is_officially_complete
        update_fields.append('is_officially_complete')
        if is_officially_complete:
            config.peer_grading_enabled = False
            if 'peer_grading_enabled' not in update_fields:
                update_fields.append('peer_grading_enabled')
    if peer_grading_enabled is not None:
        if config.is_officially_complete and peer_grading_enabled:
            raise ValidationError({'peer_grading_enabled': 'Peer grading cannot be enabled while the event is officially complete.'})
        config.peer_grading_enabled = peer_grading_enabled
        if 'peer_grading_enabled' not in update_fields:
            update_fields.append('peer_grading_enabled')

    if update_fields:
        config.save(update_fields=list(dict.fromkeys(update_fields)) + ['updated_at'])
        if 'peer_grading_enabled' in update_fields and scope == TeamGrade.SCOPE_PIT:
            from realtime.broadcast import notify_pit_peer_grading

            notify_pit_peer_grading(
                semester,
                label,
                peer_eval_enabled=bool(config.peer_grading_enabled),
            )

    settings_payload = None
    if scope == TeamGrade.SCOPE_PIT:
        settings_payload = _pit_group_settings(semester, label)
    else:
        settings_payload = _capstone_group_settings(semester, label)

    peer_counts = peer_completion_counts_for_group(semester, scope, label)
    settings_payload.update(peer_counts)

    if scope == TeamGrade.SCOPE_PIT and is_officially_complete is True:
        settings_payload['auto_publish'] = auto_publish_passed_grades_for_event(
            semester,
            label,
            user=user,
        )
    elif scope == TeamGrade.SCOPE_CAPSTONE and is_officially_complete is True:
        auto_finalize = auto_finalize_passed_capstone_grades_for_stage(
            semester,
            label,
            user=user,
        )
        settings_payload['auto_finalize'] = auto_finalize
        settings_payload['auto_publish'] = auto_finalize

    return settings_payload


def require_grade_editable(grade):
    settings = group_settings_for_grade(grade)
    if settings.get('is_officially_complete'):
        raise ValidationError(
            'This event or stage is marked officially complete. Grades cannot be edited.'
        )


def peer_grading_allowed_for_grade(grade):
    if grade.scope == TeamGrade.SCOPE_PIT:
        settings = group_settings_for_grade(grade)
        return bool(settings.get('peer_grading_enabled'))
    return bool(getattr(grade.semester, 'capstone_peer_evaluation_enabled', True))


def publish_grade_record(grade, user=None):
    grade.publish(user=user)
    if grade.schedule_id and grade.schedule.status != DefenseSchedule.STATUS_DONE:
        grade.schedule.status = DefenseSchedule.STATUS_DONE
        grade.schedule.save(update_fields=['status', 'updated_at'])

    next_status = (
        StudentTeam.STATUS_APPROVED
        if grade.final_grade is not None and grade.final_grade >= Decimal('75.00')
        else StudentTeam.STATUS_FAILED
    )
    if grade.team.status != next_status:
        grade.team.status = next_status
        grade.team.save(update_fields=['status', 'updated_at'])
    return grade


def require_complete_for_publish(grade):
    grade.recalculate()
    if not grade.is_complete:
        raise ValidationError({'status': 'Only complete grades can be published.'})
