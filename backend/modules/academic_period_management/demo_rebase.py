"""Explicit demo-baseline correction, separate from normal semester rollover.

Preview is read-only. Apply requires an exact revision, an empty destination,
the development DB opt-in, an administrator and an exclusive recovery file.
"""
from hashlib import sha256
import json
from pathlib import Path
import re

from django.apps import apps
from django.core.serializers import serialize
from django.core.serializers.json import DjangoJSONEncoder
from django.db import transaction

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defensys_backend.db_guard import assert_safe_for_orm_writes
from .models import Semester, SemesterTransitionLog


@transaction.atomic
def rebase_demo_term(*, source_id, target_id, expected_year, expected_teams,
                     expected_enrollments, expected_capstone_teams, reason,
                     actor=None, apply=False, backup_path=None, preview_revision=''):
    from user_management.models import FacultyRoleAssignment, SectionInstructorAssignment
    from user_management.academic_records.models import StudentAcademicRecord
    from student_teams.models import (CapstoneJourney, SectionAssignment, StudentTeam,
                                     TeamMembership, TeamTermParticipation)
    from student_teams.capstone_lifecycle import EXTENSION_POLICY, year_after
    from grading.grades.models import TeamGrade
    from repository.archive.models import ArchiveEntry
    from repository.deliverables.models import DeliverableSubmission

    if not reason.strip() or source_id == target_id:
        raise ValueError('Provide distinct terms and a correction reason.')
    if apply:
        assert_safe_for_orm_writes()
        if not backup_path or not actor or not (actor.is_superuser or actor.role == 'admin'):
            raise ValueError('Apply requires a backup path and an administrator.')
        from .services import _lock_period_state
        _lock_period_state()
    source = Semester.objects.select_related('school_year').get(pk=source_id)
    target = Semester.objects.select_related('school_year').get(pk=target_id)
    if (not source.is_active or target.is_active or source.label != Semester.FIRST
            or target.label != Semester.SECOND or source.school_year_id != target.school_year_id
            or target.school_year.label != expected_year):
        raise ValueError('Expected active first semester and empty second semester of the specified year.')
    if target.starts_on or target.ends_on:
        raise ValueError('The destination already has calendar dates; review it separately.')

    # Enumerate every real Semester FK, including archive attribution and faculty
    # assignments. Earlier transition/audit evidence remains immutable history.
    references, records = [], {(source._meta.label, source.pk): source,
                               (target._meta.label, target.pk): target}
    counts = {}
    for model in apps.get_models():
        if model is SemesterTransitionLog or model._meta.proxy:
            continue
        for field in model._meta.local_fields:
            if not field.is_relation or field.related_model is not Semester:
                continue
            if model._base_manager.filter(**{field.attname: target_id}).exists():
                raise ValueError(f'Destination has {model._meta.label} records. No records were merged.')
            query = model._base_manager.filter(**{field.attname: source_id}).order_by('pk')
            if apply:
                query = query.select_for_update()
            rows = list(query)
            if rows:
                references.append((model, field, [row.pk for row in rows]))
                counts[f'{model._meta.label}.{field.name}'] = len(rows)
                for row in rows:
                    records[(row._meta.label, row.pk)] = row

    teams = list(StudentTeam.objects.filter(semester=source).order_by('pk'))
    capstone = [team for team in teams if team.level == StudentTeam.LEVEL_4_CAPSTONE]
    enrollments = StudentAcademicRecord.objects.filter(semester=source)
    if (len(teams) != expected_teams or enrollments.count() != expected_enrollments
            or len(capstone) != expected_capstone_teams):
        raise ValueError('Team/enrollment counts changed. Preview the exact dataset again.')
    if any(team.level == StudentTeam.LEVEL_3_PIT for team in teams):
        raise ValueError('Third-year PIT cannot be relabeled as second-semester Capstone. Review those teams separately.')
    capstone_ids = [team.pk for team in capstone]
    if any(team.capstone_phase == StudentTeam.PHASE_EXTENDED or team.project_version != 1 for team in capstone):
        raise ValueError('Extended or replacement projects require the normal historical correction process.')
    if (CapstoneJourney.objects.filter(team_id__in=capstone_ids).exists()
            or TeamGrade.all_objects.filter(team_id__in=capstone_ids).exists()):
        raise ValueError('Existing Capstone cohort/assessment evidence cannot be rebased as a fresh intake.')
    participations = list(TeamTermParticipation.objects.filter(semester=source).order_by('pk'))
    if any(row.closed_at or row.team_id not in capstone_ids for row in participations):
        raise ValueError('Only open current Capstone participation can be rebased.')
    if ArchiveEntry.objects.filter(team__semester=source).exists():
        raise ValueError('Published library entries require a separate metadata correction.')
    members = list(TeamMembership.objects.filter(team_id__in=capstone_ids).order_by('pk'))
    student_ids = {row.student_id for row in members} | {team.leader_id for team in capstone}
    fourth_ids = set(enrollments.filter(year_level='4th Year').values_list('student_id', flat=True))
    if student_ids != fourth_ids:
        raise ValueError('Fourth-year enrollment does not exactly match the Capstone roster.')
    if enrollments.exclude(rolled_from=None).exists():
        raise ValueError('Enrollment already has rollover history; use the normal correction process.')
    section_map = {team.section: re.sub(r'(?<=-)4(?=[A-Za-z])', '3', team.section) for team in capstone}
    if SectionAssignment.objects.filter(semester=source, section__in=section_map.values()).exclude(year_level='4th Year').exists():
        raise ValueError('The destination third-year sections already have assignments.')
    for member in members:
        records[(member._meta.label, member.pk)] = member
    before = json.loads(serialize('json', [records[key] for key in sorted(records)]))
    revision = sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()
    report = {'source_id': source_id, 'target_id': target_id, 'target': target.display_name,
              'team_count': len(teams), 'capstone_team_count': len(capstone),
              'capstone_student_count': len(student_ids), 'enrollment_count': enrollments.count(),
              'moved_records': counts, 'section_map': section_map,
              'calendar_preserved': {'starts_on': source.starts_on, 'ends_on': source.ends_on},
              'preview_revision': revision, 'applied': False}
    if not apply:
        return report
    if not preview_revision or preview_revision != revision:
        raise ValueError('The preview is stale or missing. No changes were applied.')
    backup = Path(backup_path)
    backup.parent.mkdir(parents=True, exist_ok=True)
    with backup.open('x', encoding='utf-8') as stream:
        json.dump({'correction': report, 'reason': reason, 'records_before': before,
                   'created_journey_team_ids': capstone_ids}, stream, cls=DjangoJSONEncoder, indent=2)

    for model, field, ids in references:
        model._base_manager.filter(pk__in=ids).update(**{field.attname: target_id})
    for old_section, new_section in section_map.items():
        StudentTeam.objects.filter(pk__in=capstone_ids, section=old_section).update(
            level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year', section=new_section)
        StudentAcademicRecord.objects.filter(semester=target, student_id__in=student_ids,
            section=old_section).update(year_level='3rd Year', section=new_section)
        for model in (SectionAssignment, SectionInstructorAssignment):
            model.objects.filter(semester=target, year_level='4th Year', section=old_section).update(
                year_level='3rd Year', section=new_section)
    FacultyRoleAssignment.objects.filter(semester=target, year_level='4th Year').update(year_level='3rd Year')
    FacultyRoleAssignment.objects.filter(semester=target, role_detail='4th Year').update(role_detail='3rd Year')
    DeliverableSubmission.all_objects.filter(team_id__in=capstone_ids, archive_year_level='4th Year').update(
        archive_year_level='3rd Year', archive_team_level=StudentTeam.LEVEL_3_CAPSTONE)
    for row in participations:
        team = StudentTeam.objects.get(pk=row.team_id)
        row.snapshot = {**row.snapshot, 'semester_id': target.pk, 'semester': target.label,
                        'school_year': expected_year, 'display_semester': target.display_name,
                        'year_level': team.year_level, 'level': team.level, 'section': team.section}
        row.save(update_fields=['snapshot'])
    for team in capstone:
        CapstoneJourney.objects.create(team_id=team.pk, intake_semester=target,
            normal_completion_year=year_after(expected_year),
            extension_end_year=year_after(year_after(expected_year)), extension_policy=EXTENSION_POLICY)

    source.is_active = False
    source.save(update_fields=['is_active'])
    target.is_active = True
    target.starts_on, target.ends_on = source.starts_on, source.ends_on
    target.capstone_peer_evaluation_enabled = source.capstone_peer_evaluation_enabled
    target.capstone_adviser_grading_enabled = source.capstone_adviser_grading_enabled
    target.capstone_team_creation_enabled = source.capstone_team_creation_enabled
    target.capstone_program_phase = Semester.PHASE_CAPSTONE_1
    target.save(update_fields=['is_active', 'starts_on', 'ends_on', 'capstone_peer_evaluation_enabled',
        'capstone_adviser_grading_enabled', 'capstone_team_creation_enabled', 'capstone_program_phase'])
    log_high_impact_action(category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD,
        action='semester.demo_baseline_corrected', target=target, actor=actor, reason=reason,
        old_values={'source_semester_id': source_id, 'source_semester': source.display_name},
        new_values=json.loads(json.dumps({**report, 'applied': True, 'backup': str(backup.resolve()),
            'created_journey_team_ids': capstone_ids}, cls=DjangoJSONEncoder)), strict=True)
    return {**report, 'applied': True, 'backup': str(backup.resolve())}
