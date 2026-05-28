from decimal import Decimal

from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from academic_period_management.models import Semester
from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule
from grading.rubrics.models import Rubric
from student_teams.models import StudentTeam
from student_teams.services import mark_stage_result
from .models import (
    GradeBreakdown,
    PanelistCriterionScore,
    PanelistGradeSubmission,
    PeerEvaluationSubmission,
    StudentPeerGrade,
    TeamGrade,
)


ACTIVE_SCHEDULE_STATUSES = [
    DefenseSchedule.STATUS_SCHEDULED,
    DefenseSchedule.STATUS_DONE,
]


def grade_audit_values(grade, **extra):
    values = {
        **audit_scope_metadata(scope=grade.scope, team=grade.team),
        'grade_id': grade.pk,
        'stage_label': grade.stage_label,
        'semester_id': grade.semester_id,
    }
    values.update(extra)
    return values


def group_audit_values(scope, stage_label, *, year_level='', **extra):
    values = {
        **audit_scope_metadata(scope=scope, year_level=year_level),
        'stage_label': stage_label,
    }
    values.update(extra)
    return values


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


def panelist_percentage_from_criterion_scores(scores):
    total_score = sum((row.score for row in scores), Decimal('0'))
    total_max = sum((row.max_score_snapshot for row in scores), Decimal('0'))
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
    submissions = list(
        team_grade.panelist_submissions.prefetch_related('criterion_scores').all()
    )
    if submissions:
        percentages = []
        for submission in submissions:
            pct = panelist_percentage_from_criterion_scores(
                submission.criterion_scores.all()
            )
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


def _submitted_criterion_id(item):
    value = item.get('criterion_id')
    if value in (None, ''):
        value = item.get('id')
    try:
        return int(value)
    except (TypeError, ValueError):
        raise ValidationError({'criteria_scores': 'Each criterion score must include a valid criterion_id.'})


def _validated_panel_criterion_rows(schedule, criteria_scores):
    if schedule is None or schedule.rubric_id is None:
        raise ValidationError({'rubric': 'A panel rubric is required before grading.'})

    criteria = list(schedule.rubric.criteria.order_by('display_order', 'id'))
    if not criteria:
        raise ValidationError({'rubric': 'The assigned panel rubric has no criteria.'})
    if not isinstance(criteria_scores, list) or not criteria_scores:
        raise ValidationError({'criteria_scores': 'criteria_scores must be a non-empty list.'})

    payload_by_id = {}
    duplicate_ids = set()
    missing_id_items = []
    for item in criteria_scores:
        if not isinstance(item, dict):
            raise ValidationError({'criteria_scores': 'Each criterion score must be an object.'})
        
        # Legacy fallback extraction
        value = item.get('criterion_id')
        if value in (None, ''):
            value = item.get('id')
            
        try:
            criterion_id = int(value) if value is not None else None
        except (TypeError, ValueError):
            criterion_id = None
            
        if criterion_id is None:
            missing_id_items.append(item)
        else:
            if criterion_id in payload_by_id:
                duplicate_ids.add(criterion_id)
            payload_by_id[criterion_id] = item

    # Legacy APK fallback for old versions that send null IDs
    if missing_id_items:
        # If EVERY item is missing an ID, and the count EXACTLY matches the rubric length,
        # we can safely assume they are submitted in the same order as the rubric.
        if not payload_by_id and len(missing_id_items) == len(criteria):
            for criterion, item in zip(criteria, missing_id_items):
                payload_by_id[criterion.id] = item
            missing_id_items = [] # clear them since we mapped them

        if missing_id_items:
            raise ValidationError({'criteria_scores': 'Each criterion score must include a valid criterion_id.'})

    if duplicate_ids:
        raise ValidationError({'criteria_scores': 'Duplicate rubric criteria are not allowed.'})

    expected_ids = {criterion.id for criterion in criteria}
    submitted_ids = set(payload_by_id)
    missing_ids = expected_ids - submitted_ids
    extra_ids = submitted_ids - expected_ids
    if missing_ids or extra_ids:
        raise ValidationError({
            'criteria_scores': 'Submitted criteria must exactly match the assigned panel rubric.'
        })

    rows = []
    for criterion in criteria:
        item = payload_by_id[criterion.id]
        try:
            score = Decimal(str(item.get('score')))
        except Exception as exc:
            raise ValidationError({'score': 'Score must be numeric.'}) from exc
        max_score = Decimal(str(criterion.max_score))
        if score < 0 or score > max_score:
            raise ValidationError({'score': 'Score must be between 0 and max score.'})
        rows.append({
            'criterion': criterion,
            'score': score,
            'max_score': max_score,
        })
    return rows


def _submission_identity_kwargs(panelist=None, guest=None):
    if panelist is not None:
        return {
            'lookup': {'panelist': panelist},
            'defaults': {
                'panelist': panelist,
                'guest_code_id': None,
                'guest_code': '',
                'guest_name': '',
            },
            'remark_key': panelist_remark_key_for_user(panelist),
        }

    guest_code_id = str(getattr(guest, 'guest_code_id', '') or getattr(guest, 'guest_code', '') or '').strip()
    guest_code = str(getattr(guest, 'guest_code', '') or '').strip()
    guest_name = str(getattr(guest, 'guest_name', '') or '').strip()
    if not guest_code_id:
        raise ValidationError({'guest': 'Guest panelist identity is required.'})
    return {
        'lookup': {'guest_code_id': guest_code_id},
        'defaults': {
            'panelist': None,
            'guest_code_id': guest_code_id,
            'guest_code': guest_code,
            'guest_name': guest_name,
        },
        'remark_key': guest_panelist_remark_key(guest_name, guest_code),
    }


@transaction.atomic
def submit_panelist_grade(schedule, team_grade, criteria_scores, *, panelist=None, guest=None, remarks=''):
    if bool(panelist) == bool(guest):
        raise ValidationError({'panelist': 'Use either a panelist or a guest identity.'})

    rows = _validated_panel_criterion_rows(schedule, criteria_scores)
    identity = _submission_identity_kwargs(panelist=panelist, guest=guest)
    submission, _created = PanelistGradeSubmission.objects.update_or_create(
        team_grade=team_grade,
        schedule=schedule,
        **identity['lookup'],
        defaults={
            **identity['defaults'],
            'remarks': remarks or '',
        },
    )

    PanelistCriterionScore.objects.filter(submission=submission).delete()
    PanelistCriterionScore.objects.bulk_create([
        PanelistCriterionScore(
            submission=submission,
            criterion=row['criterion'],
            criterion_name_snapshot=row['criterion'].name,
            score=row['score'],
            max_score_snapshot=row['max_score'],
            display_order=row['criterion'].display_order,
        )
        for row in rows
    ])

    remark = f"{identity['remark_key']}\n{remarks or ''}"
    GradeBreakdown.objects.filter(
        team_grade=team_grade,
        evaluation_type=GradeBreakdown.EVAL_PANEL,
        remarks__startswith=identity['remark_key'],
    ).delete()
    GradeBreakdown.objects.bulk_create([
        GradeBreakdown(
            team_grade=team_grade,
            rubric=schedule.rubric,
            evaluation_type=GradeBreakdown.EVAL_PANEL,
            criterion_name=row['criterion'].name,
            score=row['score'],
            max_score=row['max_score'],
            remarks=remark,
            display_order=row['criterion'].display_order,
        )
        for row in rows
    ])

    recompute_panel_score(team_grade)
    submission.refresh_from_db()
    return submission


def weights_for_schedule(schedule):
    if schedule and schedule.scope == TeamGrade.SCOPE_CAPSTONE and schedule.defense_stage_id:
        from defense.stages.grading_config import weights_for_capstone_stage

        return weights_for_capstone_stage(schedule.defense_stage, schedule.semester)

    if schedule and schedule.scope == TeamGrade.SCOPE_PIT:
        from defense.scheduler.pit_config import get_pit_event_config, weights_for_pit_event

        label = schedule.event_name or schedule.stage_label
        config = get_pit_event_config(schedule.semester, label)
        if config is not None:
            return {
                'panel_weight': config.panel_weight,
                'peer_weight': config.peer_weight,
                'adviser_weight': 0,
            }
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
            'defense_stage',
            'pit_event_config',
            'pit_event_config__panel_rubric',
            'pit_event_config__peer_rubric',
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
    from authentication_access_control.scopes import is_pit_lead_only

    return is_pit_lead_only(user)


def grade_queryset_for_user(user):
    from authentication_access_control.scopes import grade_records_for

    return grade_records_for(user)


def schedule_queryset_for_user(user):
    from authentication_access_control.scopes import visible_schedules_for

    return visible_schedules_for(user).filter(status__in=ACTIVE_SCHEDULE_STATUSES)


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


def _is_unscheduled_placeholder_label(stage_label):
    return (stage_label or '').strip() in {'', 'Unscheduled'}


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
    """Resolve the capstone grade for a team without crossing real stage records."""
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
    label_is_placeholder = _is_unscheduled_placeholder_label(resolved_label)

    if not resolved_label and schedule:
        resolved_label = schedule.stage_label or ''
    if not resolved_label:
        resolved_label = _context_for_team(team)

    if schedule and (label_is_placeholder or schedule.stage_label == resolved_label):
        grade = TeamGrade.objects.filter(
            team=team,
            semester=semester_obj,
            scope=TeamGrade.SCOPE_CAPSTONE,
            schedule=schedule,
        ).first()
        if grade is not None:
            return grade

    if stage_label and not label_is_placeholder:
        return (
            TeamGrade.objects.filter(
                team=team,
                semester=semester_obj,
                scope=TeamGrade.SCOPE_CAPSTONE,
                stage_label=resolved_label,
            )
            .order_by('-updated_at', '-id')
            .first()
        )

    return (
        TeamGrade.objects.filter(
            team=team,
            semester=semester_obj,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label=resolved_label,
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
        if stale.schedule_id:
            continue
        if not _is_unscheduled_placeholder_label(stale.stage_label):
            continue
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


def _pit_event_config_for_schedule(schedule):
    if not schedule or schedule.scope != TeamGrade.SCOPE_PIT:
        return None
    from defense.scheduler.pit_config import get_pit_event_config

    return get_pit_event_config(schedule.semester, schedule.event_name or schedule.stage_label)


def _identity_for_schedule(schedule):
    if schedule.scope == TeamGrade.SCOPE_CAPSTONE:
        return {
            'defense_stage': schedule.defense_stage if schedule.defense_stage_id else None,
            'pit_event_config': None,
        }
    return {
        'defense_stage': None,
        'pit_event_config': _pit_event_config_for_schedule(schedule),
    }


def _lookup_grade_for_schedule(schedule, stage_label):
    identity = _identity_for_schedule(schedule)
    base = TeamGrade.objects.filter(
        team=schedule.team,
        semester=schedule.semester,
        scope=schedule.scope,
    )
    if identity['defense_stage'] is not None:
        grade = base.filter(defense_stage=identity['defense_stage']).order_by('-updated_at', '-id').first()
        if grade is not None:
            return grade, identity
    if identity['pit_event_config'] is not None:
        grade = base.filter(pit_event_config=identity['pit_event_config']).order_by('-updated_at', '-id').first()
        if grade is not None:
            return grade, identity

    legacy = base.filter(stage_label__iexact=stage_label)
    if identity['defense_stage'] is not None:
        legacy = legacy.filter(defense_stage__isnull=True)
    if identity['pit_event_config'] is not None:
        legacy = legacy.filter(pit_event_config__isnull=True)
    return legacy.order_by('-updated_at', '-id').first(), identity


class GradeContextService:
    """Central resolver for TeamGrade lifecycle operations."""

    @staticmethod
    def get_or_create_for_schedule(schedule, *, repair_placeholders=True):
        stage_label = schedule.stage_label or 'Defense'
        weights = weights_for_schedule(schedule)
        grade, identity = _lookup_grade_for_schedule(schedule, stage_label)
        created = grade is None
        if created:
            grade = TeamGrade.objects.create(
                team=schedule.team,
                semester=schedule.semester,
                scope=schedule.scope,
                stage_label=stage_label,
                schedule=schedule,
                defense_stage=identity['defense_stage'],
                pit_event_config=identity['pit_event_config'],
                **weights,
            )
            if repair_placeholders:
                _cleanup_stale_grades_for_schedule(grade, schedule)
            return grade, created, True

        changed = False
        if grade.schedule_id != schedule.id:
            grade.schedule = schedule
            changed = True
        if grade.defense_stage_id != (identity['defense_stage'].id if identity['defense_stage'] else None):
            grade.defense_stage = identity['defense_stage']
            changed = True
        if grade.pit_event_config_id != (identity['pit_event_config'].id if identity['pit_event_config'] else None):
            grade.pit_event_config = identity['pit_event_config']
            changed = True
        if stage_label and grade.stage_label != stage_label:
            grade.stage_label = stage_label
            changed = True
        if grade.status not in TeamGrade.LOCKED_STATUSES:
            for field, value in weights.items():
                if getattr(grade, field) != value:
                    setattr(grade, field, value)
                    changed = True
        if changed:
            grade.save()
        if repair_placeholders:
            _cleanup_stale_grades_for_schedule(grade, schedule)
        return grade, created, changed

    @staticmethod
    def get_or_create_unscheduled_team(team, *, repair_placeholders=True):
        scope = _scope_for_team(team)
        stage_label = _context_for_team(team)
        weights = default_weights(scope)
        defense_stage = None
        if scope == TeamGrade.SCOPE_CAPSTONE and not _is_unscheduled_placeholder_label(stage_label):
            from defense.stages.models import DefenseStage

            defense_stage = DefenseStage.objects.filter(label=stage_label).first()
        lookup = {
            'team': team,
            'semester': team.semester,
            'scope': scope,
        }
        if defense_stage is not None:
            lookup['defense_stage'] = defense_stage
            legacy = TeamGrade.objects.filter(
                team=team,
                semester=team.semester,
                scope=scope,
                defense_stage__isnull=True,
                stage_label__iexact=stage_label,
            ).order_by('-updated_at', '-id').first()
            if legacy is not None:
                legacy.defense_stage = defense_stage
                legacy.save()
                if repair_placeholders:
                    _cleanup_stale_grades_for_unscheduled_team(legacy, team)
                return legacy, False
        else:
            lookup['stage_label'] = stage_label
        grade, created = TeamGrade.objects.get_or_create(
            **lookup,
            defaults={
                'stage_label': stage_label,
                **weights,
            },
        )
        if repair_placeholders:
            _cleanup_stale_grades_for_unscheduled_team(grade, team)
        return grade, created

    @staticmethod
    def get_for_panel_submission(schedule, panelist=None):
        return GradeContextService.get_or_create_for_schedule(schedule)[0]

    @staticmethod
    def get_for_guest_panel_submission(schedule, guest=None):
        return GradeContextService.get_or_create_for_schedule(schedule)[0]

    @staticmethod
    def get_for_current_student_peer_context(team):
        scope = _scope_for_team(team)
        if scope == TeamGrade.SCOPE_CAPSTONE:
            grade = canonical_capstone_grade_for_team(team, team.semester)
            if grade is None:
                grade, _created = GradeContextService.get_or_create_unscheduled_team(team)
                return resolve_canonical_capstone_grade(grade)
            return resolve_canonical_capstone_grade(grade)

        grade = (
            TeamGrade.objects.filter(team=team, scope=scope)
            .order_by('-updated_at', '-id')
            .first()
        )
        if grade:
            return grade
        grade, _created = GradeContextService.get_or_create_unscheduled_team(team)
        return grade

    @staticmethod
    def get_for_adviser_context(adviser, grade):
        if grade.team.adviser_id != getattr(adviser, 'id', None):
            raise ValidationError({'grade': 'This grade does not belong to one of your advised teams.'})
        return resolve_canonical_capstone_grade(grade)

    @staticmethod
    def finalize_for_archive(grade, user=None):
        old_values = {
            **grade_audit_values(
                grade,
                status=grade.status,
                final_grade=str(grade.final_grade) if grade.final_grade is not None else None,
            ),
        }
        grade.recalculate()
        if not grade.is_complete:
            raise ValidationError({'status': 'Only complete grades can be finalized for archive.'})
        if grade.final_grade is None or grade.final_grade < PASS_GRADE_THRESHOLD:
            raise ValidationError({'status': 'Only passed grades can be finalized for archive.'})
        if grade.status == TeamGrade.STATUS_PUBLISHED:
            return grade

        grade.status = TeamGrade.STATUS_PUBLISHED
        grade.published_by = user
        grade.published_at = timezone.now()
        grade.save()
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='grade.finalize_for_archive',
            target=grade,
            actor=user,
            old_values=old_values,
            new_values=grade_audit_values(
                grade,
                status=grade.status,
                final_grade=str(grade.final_grade) if grade.final_grade is not None else None,
            ),
        )

        if grade.schedule_id and grade.schedule.status != DefenseSchedule.STATUS_DONE:
            grade.schedule.status = DefenseSchedule.STATUS_DONE
            grade.schedule.save(update_fields=['status', 'updated_at'])

        _apply_team_result_from_grade(grade)
        return grade

    @staticmethod
    def publish(grade, user=None):
        grade.publish(user=user)
        if grade.schedule_id and grade.schedule.status != DefenseSchedule.STATUS_DONE:
            grade.schedule.status = DefenseSchedule.STATUS_DONE
            grade.schedule.save(update_fields=['status', 'updated_at'])

        _apply_team_result_from_grade(grade)
        return grade

    @staticmethod
    def grade_ready_for_archive(team, *, scope, semester=None, defense_stage_id=None, pit_event_config_id=None, stage_label=None):
        if not team:
            return None
        if semester is None:
            semester = team.semester if getattr(team, 'semester_id', None) else active_semester()
        grades = TeamGrade.objects.filter(
            team=team,
            scope=scope,
            status=TeamGrade.STATUS_PUBLISHED,
            final_grade__gte=Decimal('75.00'),
        )
        if semester:
            grades = grades.filter(semester=semester)
        if defense_stage_id:
            grades = grades.filter(defense_stage_id=defense_stage_id)
        elif pit_event_config_id:
            grades = grades.filter(pit_event_config_id=pit_event_config_id)
        elif stage_label:
            grades = grades.filter(stage_label=stage_label)
        return grades.order_by('-updated_at').first()

def _sync_grade_for_schedule(schedule, *, repair_placeholders=True):
    return GradeContextService.get_or_create_for_schedule(
        schedule,
        repair_placeholders=repair_placeholders,
    )


def _sync_unscheduled_team(team, *, repair_placeholders=True):
    return GradeContextService.get_or_create_unscheduled_team(
        team,
        repair_placeholders=repair_placeholders,
    )


@transaction.atomic
def sync_missing_grade_rows(user=None, *, repair_placeholders=True):
    created = 0
    updated = 0

    for schedule in schedule_queryset_for_user(user):
        _, made, changed = _sync_grade_for_schedule(
            schedule,
            repair_placeholders=repair_placeholders,
        )
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
            _, made = _sync_unscheduled_team(
                team,
                repair_placeholders=repair_placeholders,
            )
            if made:
                created += 1

    return {'created': created, 'updated': updated}


def _stage_grading_config_for_grade(grade):
    from defense.stages.grading_config import get_or_create_stage_grading_config
    from defense.stages.models import DefenseStage

    stage = None
    if grade.defense_stage_id:
        stage = grade.defense_stage
    elif grade.schedule and grade.schedule.defense_stage_id:
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
        if grade.defense_stage_id:
            queryset = queryset.filter(defense_stage=grade.defense_stage)
        elif grade.schedule and grade.schedule.defense_stage_id:
            queryset = queryset.filter(defense_stage=grade.schedule.defense_stage)
        else:
            queryset = queryset.filter(defense_stage__label=grade.stage_label)
        return queryset.order_by('-updated_at', 'name').first()

    if evaluation_type == Rubric.EVAL_PEER:
        from defense.scheduler.pit_config import peer_rubric_for_pit_event

        rubric = grade.pit_event_config.peer_rubric if grade.pit_event_config_id else None
        if rubric is None:
            rubric = peer_rubric_for_pit_event(grade.semester, grade.stage_label)
        if rubric is not None:
            return (
                Rubric.objects.select_related('defense_stage')
                .prefetch_related('criteria')
                .filter(pk=rubric.pk)
                .first()
            )

    return queryset.order_by('-updated_at', 'name').first()


def _evaluation_type_label(evaluation_type):
    return {
        Rubric.EVAL_PANEL: 'panel',
        Rubric.EVAL_ADVISER: 'adviser',
        Rubric.EVAL_PEER: 'peer',
    }.get(evaluation_type, 'grading')


def _configured_rubric_for_grade(grade, evaluation_type):
    if grade.scope == TeamGrade.SCOPE_CAPSTONE:
        if evaluation_type == Rubric.EVAL_PANEL and grade.schedule and grade.schedule.rubric_id:
            return grade.schedule.rubric
        config = _stage_grading_config_for_grade(grade)
        if config is None:
            return None
        if evaluation_type == Rubric.EVAL_PANEL:
            return config.panel_rubric
        if evaluation_type == Rubric.EVAL_ADVISER:
            return config.adviser_rubric
        if evaluation_type == Rubric.EVAL_PEER:
            return config.peer_rubric
        return None

    if evaluation_type == Rubric.EVAL_PANEL and grade.schedule and grade.schedule.rubric_id:
        return grade.schedule.rubric
    config = grade.pit_event_config if grade.pit_event_config_id else None
    if config is None:
        from defense.scheduler.pit_config import get_pit_event_config

        config = get_pit_event_config(grade.semester, grade.stage_label)
    if config is None:
        return None
    if evaluation_type == Rubric.EVAL_PANEL:
        return config.panel_rubric
    if evaluation_type == Rubric.EVAL_PEER:
        return config.peer_rubric
    return None


def require_matching_rubric(grade, evaluation_type):
    rubric = _configured_rubric_for_grade(grade, evaluation_type)
    label = _evaluation_type_label(evaluation_type)
    if rubric is None:
        raise ValidationError({
            'rubric': f'Configure a published {label} rubric before grading this team.'
        })
    if rubric.status != Rubric.STATUS_PUBLISHED:
        raise ValidationError({
            'rubric': f'Configure a published {label} rubric before grading this team.'
        })
    if not rubric.criteria.exists():
        raise ValidationError({
            'rubric': f'The configured {label} rubric must have at least one criterion.'
        })
    return rubric


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

def rebuild_component_breakdown(grade, evaluation_type, ratio):
    rubric = require_matching_rubric(grade, evaluation_type)
    rows = [
        {
            'name': criterion.name,
            'max_score': Decimal(str(criterion.max_score)),
            'display_order': criterion.display_order,
        }
        for criterion in rubric.criteria.all()
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



def group_settings_key(scope, stage_label):
    return f'{scope}|{(stage_label or "").strip()}'


def _default_group_settings(scope, stage_label):
    return {
        'scope': scope,
        'defense_stage_id': None,
        'pit_event_config_id': None,
        'stage_label': stage_label or '',
        'is_officially_complete': False,
        'peer_grading_enabled': False,
    }


def _pit_group_settings(semester, stage_label=None, *, pit_event_config=None):
    from defense.scheduler.pit_config import get_pit_event_config, pit_event_config_payload

    config = pit_event_config or get_pit_event_config(semester, stage_label)
    if config is None:
        return _default_group_settings(TeamGrade.SCOPE_PIT, stage_label)
    payload = pit_event_config_payload(config)
    return {
        'scope': TeamGrade.SCOPE_PIT,
        'pit_event_config_id': config.id,
        'defense_stage_id': None,
        'stage_label': config.event_name,
        'is_officially_complete': payload['is_officially_complete'],
        'peer_grading_enabled': payload['peer_grading_enabled'],
        'panel_weight': payload['panel_weight'],
        'peer_weight': payload['peer_weight'],
        'peer_complete_team_count': 0,
        'peer_total_team_count': 0,
    }


def _capstone_group_settings(semester, stage_label=None, *, defense_stage=None):
    from defense.stages.grading_config import get_or_create_stage_grading_config, grading_config_payload
    from defense.stages.models import DefenseStage

    stage = defense_stage or DefenseStage.objects.filter(label=stage_label).first()
    if stage is None:
        return _default_group_settings(TeamGrade.SCOPE_CAPSTONE, stage_label)
    config = get_or_create_stage_grading_config(stage, semester)
    payload = grading_config_payload(config)
    return {
        'scope': TeamGrade.SCOPE_CAPSTONE,
        'defense_stage_id': stage.id,
        'pit_event_config_id': None,
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
        return _pit_group_settings(
            grade.semester,
            grade.stage_label,
            pit_event_config=grade.pit_event_config if grade.pit_event_config_id else None,
        )
    return _capstone_group_settings(
        grade.semester,
        grade.stage_label,
        defense_stage=grade.defense_stage if grade.defense_stage_id else None,
    )


def build_group_settings_map(grades_queryset, semester):
    if semester is None:
        return {}
    from defense.scheduler.models import PitEventGradingConfig
    from defense.stages.models import DefenseStage

    result = {}

    def _put(scope, label, *, defense_stage=None, pit_event_config=None):
        key = group_settings_key(scope, label)
        if key in result:
            return
        if scope == TeamGrade.SCOPE_PIT:
            result[key] = _pit_group_settings(semester, label, pit_event_config=pit_event_config)
        else:
            result[key] = _capstone_group_settings(semester, label, defense_stage=defense_stage)

    for scope, stage_label, defense_stage_id, pit_event_config_id in grades_queryset.values_list(
        'scope',
        'stage_label',
        'defense_stage_id',
        'pit_event_config_id',
    ).distinct():
        defense_stage = None
        pit_event_config = None
        if defense_stage_id:
            defense_stage = DefenseStage.objects.filter(pk=defense_stage_id).first()
        if pit_event_config_id:
            pit_event_config = PitEventGradingConfig.objects.filter(pk=pit_event_config_id).first()
        _put(
            scope,
            (stage_label or '').strip(),
            defense_stage=defense_stage,
            pit_event_config=pit_event_config,
        )

    for stage in DefenseStage.objects.filter(is_active=True).order_by('display_order', 'label'):
        _put(TeamGrade.SCOPE_CAPSTONE, stage.label, defense_stage=stage)

    for config in PitEventGradingConfig.objects.filter(semester=semester):
        _put(TeamGrade.SCOPE_PIT, config.event_name, pit_event_config=config)

    return result


PASS_GRADE_THRESHOLD = Decimal('75.00')


class IncompleteGradingTeamsError(Exception):
    """Raised when officially complete is blocked by incomplete team grading."""

    def __init__(self, teams):
        self.teams = teams
        super().__init__('One or more teams have incomplete grading.')


def _apply_team_result_from_grade(grade):
    if grade.scope == TeamGrade.SCOPE_CAPSTONE and grade.defense_stage_id:
        mark_stage_result(grade, user=grade.published_by)
        return

    next_status = (
        StudentTeam.STATUS_APPROVED
        if grade.final_grade is not None and grade.final_grade >= PASS_GRADE_THRESHOLD
        else StudentTeam.STATUS_FAILED
    )
    if grade.team.status != next_status:
        grade.team.status = next_status
        grade.team.save(update_fields=['status', 'updated_at'])


def _mark_schedule_done_from_grade(grade):
    if grade.schedule_id and grade.schedule.status != DefenseSchedule.STATUS_DONE:
        grade.schedule.status = DefenseSchedule.STATUS_DONE
        grade.schedule.save(update_fields=['status', 'updated_at'])


def finalize_passed_grade_for_archive(grade, user=None):
    return GradeContextService.finalize_for_archive(grade, user=user)


finalize_passed_pit_grade_for_archive = finalize_passed_grade_for_archive


def _empty_auto_finalize_result():
    return {
        'ready_for_archive_count': 0,
        'published_count': 0,
        'skipped_incomplete': 0,
        'skipped_below_threshold': 0,
    }


def peer_required_for_grade(grade, semester, scope, config):
    from .peer_eval import peer_submission_count

    if scope == TeamGrade.SCOPE_PIT:
        if getattr(config, 'peer_grading_enabled', False):
            return True
        return peer_submission_count(grade) > 0
    if getattr(semester, 'capstone_peer_evaluation_enabled', True):
        return True
    return peer_submission_count(grade) > 0


def adviser_required_for_grade(grade, semester):
    if grade.scope != TeamGrade.SCOPE_CAPSTONE:
        return False
    if grade.adviser_weight <= 0:
        return False
    return bool(getattr(semester, 'capstone_adviser_grading_enabled', True))


def _grading_config_for_grade(grade, semester, scope, config=None):
    if config is not None:
        return config
    if scope == TeamGrade.SCOPE_PIT:
        from defense.scheduler.pit_config import get_pit_event_config

        if grade.pit_event_config_id:
            return grade.pit_event_config
        return get_pit_event_config(semester, grade.stage_label)

    class _CapstonePlaceholder:
        peer_grading_enabled = False

    return _CapstonePlaceholder()


def _grades_for_group(semester, scope, stage_label, *, config=None, year_level=None):
    label = (stage_label or '').strip()
    grades = TeamGrade.objects.filter(
        semester=semester,
        scope=scope,
    )
    if year_level:
        grades = grades.filter(team__year_level=year_level)
    if scope == TeamGrade.SCOPE_PIT:
        if config is not None:
            return grades.filter(
                Q(pit_event_config=config)
                | Q(pit_event_config__isnull=True, stage_label__iexact=getattr(config, 'event_name', label))
            )
        return grades.filter(stage_label__iexact=label)
    if config is not None and getattr(config, 'defense_stage_id', None):
        return grades.filter(
            Q(defense_stage_id=config.defense_stage_id)
            | Q(defense_stage__isnull=True, stage_label__iexact=getattr(config.defense_stage, 'label', label))
        )
    return grades.filter(stage_label__iexact=label)


def team_grading_readiness(grade, semester, scope, config=None):
    from .peer_eval import is_team_peer_eval_complete, peer_completion_summary

    config = _grading_config_for_grade(grade, semester, scope, config)
    panel_complete = grade.panel_score is not None
    peer_required = peer_required_for_grade(grade, semester, scope, config=config)
    peer_complete = is_team_peer_eval_complete(grade) if peer_required else True
    adviser_required = adviser_required_for_grade(grade, semester)
    adviser_complete = grade.adviser_score is not None if adviser_required else True

    missing = []
    if not panel_complete:
        missing.append('panel')
    if peer_required and not peer_complete:
        missing.append('peer')
    if adviser_required and not adviser_complete:
        missing.append('adviser')

    summary = peer_completion_summary(grade) if peer_required else {}
    return {
        'panel_complete': panel_complete,
        'peer_complete': peer_complete,
        'adviser_complete': adviser_complete,
        'peer_required': peer_required,
        'adviser_required': adviser_required,
        'ready': not missing,
        'missing_components': missing,
        'submitted': summary.get('submitted', 0),
        'required': summary.get('required', 0),
        'evaluators_done': summary.get('evaluators_done', 0),
        'evaluators_total': summary.get('evaluators_total', 0),
    }


def incomplete_grading_teams_for_group(
    semester,
    scope,
    stage_label,
    *,
    config=None,
    year_level=None,
    grades_queryset=None,
):
    grades = grades_queryset
    if grades is None:
        grades = _grades_for_group(
            semester,
            scope,
            stage_label,
            config=config,
            year_level=year_level,
        )
    grades = grades.select_related('team', 'semester')
    incomplete = []
    for grade in grades:
        readiness = team_grading_readiness(grade, semester, scope, config)
        if readiness['ready']:
            continue
        incomplete.append(
            {
                'team_id': grade.team_id,
                'team_name': grade.team.name,
                'grade_id': grade.id,
                'missing_components': readiness['missing_components'],
                'panel_complete': readiness['panel_complete'],
                'peer_complete': readiness['peer_complete'],
                'adviser_complete': readiness['adviser_complete'],
                'submitted': readiness['submitted'],
                'required': readiness['required'],
                'evaluators_done': readiness['evaluators_done'],
                'evaluators_total': readiness['evaluators_total'],
            }
        )
    return incomplete


# Backward-compatible alias
incomplete_peer_teams_for_group = incomplete_grading_teams_for_group


def grading_readiness_counts_for_group(semester, scope, stage_label, *, config=None, year_level=None):
    grades = list(
        _grades_for_group(
            semester,
            scope,
            stage_label,
            config=config,
            year_level=year_level,
        ).select_related('team', 'semester')
    )
    total = len(grades)
    ready = sum(
        1
        for grade in grades
        if team_grading_readiness(grade, semester, scope, config)['ready']
    )
    from .peer_eval import is_team_peer_eval_complete

    peer_complete = sum(1 for grade in grades if is_team_peer_eval_complete(grade))
    return {
        'grading_ready_team_count': ready,
        'grading_total_team_count': total,
        'peer_complete_team_count': peer_complete,
        'peer_total_team_count': total,
    }


def peer_completion_counts_for_group(semester, scope, stage_label, *, config=None):
    return grading_readiness_counts_for_group(semester, scope, stage_label, config=config)


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
            _mark_schedule_done_from_grade(grade)
            _apply_team_result_from_grade(grade)
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


def auto_publish_passed_grades_for_event(semester, event_name, user=None, *, config=None, year_level=None):
    label = (event_name or '').strip()
    if not label and config is None:
        return _empty_auto_finalize_result()

    grades = _grades_for_group(
        semester,
        TeamGrade.SCOPE_PIT,
        label or getattr(config, 'event_name', ''),
        config=config,
        year_level=year_level,
    ).select_related('team', 'schedule')
    return _auto_finalize_passed_grades_in_queryset(grades, user=user)


def auto_finalize_passed_capstone_grades_for_stage(semester, stage_label, user=None, *, config=None):
    label = (stage_label or '').strip()
    if not label and config is None:
        return _empty_auto_finalize_result()

    grades = _grades_for_group(
        semester,
        TeamGrade.SCOPE_CAPSTONE,
        label or getattr(getattr(config, 'defense_stage', None), 'label', ''),
        config=config,
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


def _single_year_level_for_grades(grades):
    year_levels = list(set(grade.team.year_level for grade in grades if getattr(grade, 'team', None)))
    return year_levels[0] if len(year_levels) == 1 else ''


class StageCompletionService:
    @staticmethod
    def _lock_config(scope, config):
        if scope == TeamGrade.SCOPE_PIT:
            from defense.scheduler.models import PitEventGradingConfig

            return PitEventGradingConfig.objects.select_for_update().get(pk=config.pk)

        from defense.stages.models import StageGradingConfig

        return StageGradingConfig.objects.select_for_update().get(pk=config.pk)

    @staticmethod
    def _pit_year_scope(user):
        if _is_pit_lead_only(user):
            return (getattr(user, 'pit_lead_year', '') or '').strip()
        return None

    @classmethod
    def complete_group(cls, *, semester, scope, stage_label, config, user=None, peer_grading_enabled=None):
        if _is_pit_lead_only(user) and scope != TeamGrade.SCOPE_PIT:
            raise PermissionDenied('PIT leads can only complete PIT events.')
        if peer_grading_enabled is True:
            raise ValidationError({'peer_grading_enabled': 'Peer grading cannot be enabled while the event is officially complete.'})

        label = (stage_label or '').strip()
        year_level = cls._pit_year_scope(user) if scope == TeamGrade.SCOPE_PIT else None

        with transaction.atomic():
            config = cls._lock_config(scope, config)
            grades = (
                _grades_for_group(
                    semester,
                    scope,
                    label,
                    config=config,
                    year_level=year_level,
                )
                .select_for_update(of=('self',))
                .select_related('team', 'schedule', 'semester')
            )
            if year_level and not grades.exists():
                raise ValidationError({'stage_label': 'No PIT grades found for your assigned year.'})
            audit_year_level = year_level or _single_year_level_for_grades(grades)
            old_values = group_audit_values(
                scope,
                label,
                year_level=audit_year_level,
                is_officially_complete=config.is_officially_complete,
                peer_grading_enabled=config.peer_grading_enabled,
            )

            incomplete = incomplete_grading_teams_for_group(
                semester,
                scope,
                label,
                config=config,
                year_level=year_level,
                grades_queryset=grades,
            )
            if incomplete:
                raise IncompleteGradingTeamsError(incomplete)

            if scope == TeamGrade.SCOPE_PIT:
                auto_result = _auto_finalize_passed_grades_in_queryset(grades, user=user)
            else:
                auto_result = _auto_finalize_passed_grades_in_queryset(grades, user=user)

            config.is_officially_complete = True
            config.peer_grading_enabled = False
            config.save(update_fields=['is_officially_complete', 'peer_grading_enabled', 'updated_at'])
            log_high_impact_action(
                category=SystemAuditLog.CATEGORY_GRADE_CENTER,
                action='grading.official_completion',
                target=config,
                target_type=config.__class__.__name__,
                target_id=config.pk,
                actor=user,
                old_values=old_values,
                new_values=group_audit_values(
                    scope,
                    label,
                    year_level=audit_year_level,
                    is_officially_complete=config.is_officially_complete,
                    peer_grading_enabled=config.peer_grading_enabled,
                ),
            )

            if scope == TeamGrade.SCOPE_PIT:
                from realtime.broadcast import notify_pit_peer_grading

                notify_pit_peer_grading(
                    semester,
                    label,
                    peer_eval_enabled=False,
                )
                settings_payload = _pit_group_settings(semester, label, pit_event_config=config)
                settings_payload['auto_publish'] = auto_result
            else:
                settings_payload = _capstone_group_settings(semester, label, defense_stage=config.defense_stage)
                settings_payload['auto_finalize'] = auto_result
                settings_payload['auto_publish'] = auto_result

            readiness_counts = grading_readiness_counts_for_group(
                semester,
                scope,
                label,
                config=config,
                year_level=year_level,
            )
            settings_payload.update(readiness_counts)
            return settings_payload


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
    if _is_pit_lead_only(user) and scope != TeamGrade.SCOPE_PIT:
        raise PermissionDenied('PIT leads can only manage PIT event settings.')

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
        return StageCompletionService.complete_group(
            semester=semester,
            scope=scope,
            stage_label=label,
            config=config,
            user=user,
            peer_grading_enabled=peer_grading_enabled,
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
        year_level = getattr(user, 'pit_lead_year', '') if scope == TeamGrade.SCOPE_PIT else ''
        if scope == TeamGrade.SCOPE_PIT and not year_level:
            year_level = _single_year_level_for_grades(
                _grades_for_group(semester, scope, label, config=config)
            )
        previous_config = config.__class__.objects.get(pk=config.pk)
        old_values = group_audit_values(
            scope,
            label,
            year_level=year_level,
            is_officially_complete=previous_config.is_officially_complete,
            peer_grading_enabled=previous_config.peer_grading_enabled,
        )
        config.save(update_fields=list(dict.fromkeys(update_fields)) + ['updated_at'])
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='grading.settings_update',
            target=config,
            target_type=config.__class__.__name__,
            target_id=config.pk,
            actor=user,
            old_values=old_values,
            new_values=group_audit_values(
                scope,
                label,
                year_level=year_level,
                is_officially_complete=config.is_officially_complete,
                peer_grading_enabled=config.peer_grading_enabled,
            ),
        )
        if 'peer_grading_enabled' in update_fields and scope == TeamGrade.SCOPE_PIT:
            from realtime.broadcast import notify_pit_peer_grading

            notify_pit_peer_grading(
                semester,
                label,
                peer_eval_enabled=bool(config.peer_grading_enabled),
            )

    settings_payload = None
    if scope == TeamGrade.SCOPE_PIT:
        settings_payload = _pit_group_settings(semester, label, pit_event_config=config)
    else:
        settings_payload = _capstone_group_settings(semester, label, defense_stage=config.defense_stage)

    readiness_counts = grading_readiness_counts_for_group(
        semester,
        scope,
        label,
        config=config,
    )
    settings_payload.update(readiness_counts)

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
    return GradeContextService.publish(grade, user=user)


def require_complete_for_publish(grade):
    grade.recalculate()
    if not grade.is_complete:
        raise ValidationError({'status': 'Only complete grades can be published.'})
