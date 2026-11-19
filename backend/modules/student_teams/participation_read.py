"""Batched facts for the canonical participation validator. Reads never repair data."""
from collections import defaultdict

from django.contrib.auth import get_user_model
from django.db.models import F, Prefetch, Q

from academic_period_management.models import Semester
from .models import StudentCapstoneParticipation, StudentCapstonePlacement, StudentTeam, TeamMembership, TeamTermParticipation


def roster_facts(student_ids, *, team=None):
    students = {s.pk: s for s in get_user_model().objects.filter(
        pk__in=student_ids, role='student', is_active=True)}
    participations, placements = {}, defaultdict(list)
    rows = StudentCapstoneParticipation.objects.filter(student_id__in=students).select_related(
        'intake_semester__school_year').order_by('student_id', '-number')
    for row in rows:
        participations.setdefault(row.student_id, row)
    if participations:
        for row in StudentCapstonePlacement.objects.filter(
                participation_id__in=[p.pk for p in participations.values()]).select_related('team__semester__school_year'):
            placements[row.participation_id].append(row)
    legacy_students = set(students) - set(participations)
    history, old_intakes, failures = defaultdict(list), {}, set()
    if legacy_students:
        old_teams = list(StudentTeam.objects.filter(level__icontains='Capstone').filter(
            Q(leader_id__in=legacy_students) | Q(memberships__student_id__in=legacy_students)
        ).exclude(pk=team.pk if team else None).select_related(
            'semester__school_year', 'intake_semester__school_year').prefetch_related(
            Prefetch('memberships', queryset=TeamMembership.objects.only('team_id', 'student_id'))).distinct())
        for old in old_teams:
            old_intakes[old.pk] = old.intake_semester if old.intake_semester_id else (
                old.semester if not old.participation_review_reason and old.semester.label == Semester.SECOND else None)
            ids = {m.student_id for m in old.memberships.all()} | {old.leader_id}
            for student_id in ids & legacy_students:
                history[student_id].append(old)
        unresolved = [old.pk for old in old_teams if not old_intakes[old.pk] and not old.participation_review_reason]
        for row in TeamTermParticipation.objects.filter(team_id__in=unresolved,
                semester__label=Semester.SECOND, is_extended=False).select_related(
                    'semester__school_year').order_by('semester__school_year__label', 'semester_id'):
            if not old_intakes[row.team_id]:
                old_intakes[row.team_id] = row.semester
        ids = [old.pk for old in old_teams]
        failures.update(TeamTermParticipation.objects.filter(team_id__in=ids,
            project_version=F('team__project_version'), outcome='failed', closed_at__isnull=False).values_list('team_id', flat=True))
        if ids:
            from grading.grades.models import TeamGrade
            from .capstone_lifecycle import latest_assessment_from
            attempts = defaultdict(list)
            for grade in TeamGrade.all_objects.filter(team_id__in=ids, scope='capstone',
                    project_version=F('team__project_version')).select_related('semester__school_year', 'schedule'):
                attempts[(grade.team_id, grade.defense_stage_id)].append(grade)
            for (team_id, _), grades in attempts.items():
                grade = latest_assessment_from(grades)
                if grade and grade.status == 'published' and grade.result == 'failed':
                    failures.add(team_id)
    return students, participations, placements, history, old_intakes, failures
