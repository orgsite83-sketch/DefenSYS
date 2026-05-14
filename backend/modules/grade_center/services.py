from decimal import Decimal

from django.core.exceptions import ValidationError
from django.db import transaction

from academic_period_management.models import Semester
from defense_scheduler.models import DefenseSchedule
from rubric_engine.models import Rubric
from student_teams.models import StudentTeam
from .models import GradeBreakdown, StudentPeerGrade, TeamGrade


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
        return {'panel_weight': 80, 'adviser_weight': 0, 'peer_weight': 20}
    return {'panel_weight': 50, 'adviser_weight': 30, 'peer_weight': 20}


def weights_for_schedule(schedule):
    if schedule and schedule.rubric_id:
        return {
            'panel_weight': schedule.rubric.panel_weight,
            'adviser_weight': schedule.rubric.adviser_weight,
            'peer_weight': schedule.rubric.peer_weight,
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
    if grade.status != TeamGrade.STATUS_PUBLISHED:
        for field, value in weights.items():
            if getattr(grade, field) != value:
                setattr(grade, field, value)
                changed = True
    if changed:
        grade.save()
    return grade, created, changed


def _sync_unscheduled_team(team):
    scope = _scope_for_team(team)
    weights = default_weights(scope)
    grade, created = TeamGrade.objects.get_or_create(
        team=team,
        semester=team.semester,
        scope=scope,
        stage_label=_context_for_team(team),
        defaults=weights,
    )
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


def find_matching_rubric(grade, evaluation_type):
    if evaluation_type == Rubric.EVAL_PANEL and grade.schedule and grade.schedule.rubric_id:
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

    exact = queryset.filter(event_name__iexact=grade.stage_label).order_by('-updated_at', 'name').first()
    return exact or queryset.order_by('-updated_at', 'name').first()


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


@transaction.atomic
def demo_fill_capstone_grades(user=None):
    sync_missing_grade_rows(user=user)
    grades = grade_queryset_for_user(user).filter(scope=TeamGrade.SCOPE_CAPSTONE)
    count = 0

    for grade in grades:
        grade.panel_score = rebuild_component_breakdown(grade, Rubric.EVAL_PANEL, Decimal('0.88'))
        grade.adviser_score = rebuild_component_breakdown(grade, Rubric.EVAL_ADVISER, Decimal('0.90'))
        rebuild_component_breakdown(grade, Rubric.EVAL_PEER, Decimal('0.86'))
        grade.peer_score = rebuild_peer_member_grades(grade)
        grade.save()
        publish_grade_record(grade, user=user)
        count += 1

    return count


def require_complete_for_publish(grade):
    grade.recalculate()
    if not grade.is_complete:
        raise ValidationError({'status': 'Only complete grades can be published.'})
