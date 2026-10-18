"""Read-only review candidates after PIT/Capstone scope repairs.

Run with backend/venv/Scripts/python.exe execution/audit_pit_capstone_integrity.py.
PostgreSQL enforces a read-only transaction. This script never repairs records.
"""
import json
import os
from collections import Counter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
sys.path.insert(0, str(ROOT / 'backend' / 'modules'))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')


def collect_findings():
    from student_teams.models import StudentTeam, TeamMembership, SectionAssignment
    from student_teams.team_levels import is_capstone_scope
    from student_teams.weekly_progress.models import WeeklyProgressReport
    from user_management.academic_records.models import StudentAcademicRecord
    findings = []

    def add(kind, **ids):
        findings.append({'kind': kind, **ids})

    teams = {t.pk: t for t in StudentTeam.objects.select_related('semester')}
    records = {(r.student_id, r.semester_id): r for r in StudentAcademicRecord.objects.all()}
    memberships = set()
    for membership in TeamMembership.objects.all():
        team = teams[membership.team_id]
        memberships.add((membership.student_id, team.pk))
        record = records.get((membership.student_id, team.semester_id))
        if record and (record.year_level != team.year_level or (record.section and team.section and record.section != team.section)):
            add('enrollment_membership_mismatch', student_id=membership.student_id, team_id=team.pk, academic_record_id=record.pk)
    for team in teams.values():
        if team.is_capstone != is_capstone_scope(team.year_level, team.semester) or not team.level.startswith(team.year_level):
            add('team_calendar_or_year_mismatch', team_id=team.pk, semester_id=team.semester_id)
        if (team.leader_id, team.pk) not in memberships:
            add('leader_missing_membership', team_id=team.pk, student_id=team.leader_id)
    for section in SectionAssignment.objects.select_related('semester', 'project_manager'):
        section_teams = [t for t in teams.values() if t.semester_id == section.semester_id and t.section == section.section]
        if any(t.year_level != section.year_level or t.is_capstone != is_capstone_scope(section.year_level, section.semester) for t in section_teams):
            add('section_scope_mismatch', section_assignment_id=section.pk, team_ids=[t.pk for t in section_teams])
        if section.project_manager_id:
            record = records.get((section.project_manager_id, section.semester_id))
            enrolled = record and record.year_level == section.year_level and record.section == section.section
            member = any((section.project_manager_id, t.pk) in memberships and t.year_level == section.year_level for t in section_teams)
            if not section.project_manager.is_active or not (enrolled or member):
                add('project_manager_outside_section', section_assignment_id=section.pk, student_id=section.project_manager_id)
    for report in WeeklyProgressReport.objects.all():
        team = teams[report.team_id]
        if not team.is_capstone or (report.student_id, team.pk) not in memberships:
            add('weekly_report_invalid_team', report_id=report.pk, team_id=team.pk, student_id=report.student_id)
        elif report.submitted_at < team.created_at:
            add('weekly_report_predates_team', report_id=report.pk, team_id=team.pk)
    # Roster import review is evidence only: membership overlap can be legitimate
    # for separate events or a deliberately configured multiple-team event.
    from defense.scheduler.models import PitEventGradingConfig
    active_pit = {pk: t for pk, t in teams.items() if t.is_pit and t.semester.is_active}
    by_student = {}
    for student_id, team_id in sorted(memberships):
        if team_id in active_pit:
            by_student.setdefault(student_id, []).append(team_id)
    repeated = [{'student_id': sid, 'team_ids': ids} for sid, ids in by_student.items() if len(ids) > 1]
    affected = {tid for row in repeated for tid in row['team_ids']}
    from repository.deliverables.models import ConceptRound
    from repository.section_concepts.models import SectionConceptProject
    import_review = {
        'events': list(PitEventGradingConfig.objects.filter(semester__is_active=True).values(
            'id', 'semester_id', 'year_level', 'event_name', 'team_membership_policy', 'concept_config')),
        'repeated_students': repeated,
        'teams': [{'id': t.pk, 'name': t.name, 'section': t.section, 'year_level': t.year_level,
            'event_name': t.current_defense_stage or '', 'project_pending': t.project_pending,
            'concept_assignment': t.concept_assignment, 'created_at': t.created_at.isoformat(),
            'member_ids': sorted(sid for sid, tid in memberships if tid == t.pk),
            'concept_rounds': list(ConceptRound.objects.filter(team=t).values('id', 'pit_event_config_id',
                'number', 'schedule_id', 'verdict', 'endorsed_at')),
            'submission_count': t.deliverable_submissions.count(),
            'shared_project_ids': list(SectionConceptProject.objects.filter(team_links__team=t).values_list('pk', flat=True))}
            for pk, t in active_pit.items() if pk in affected],
    }
    return {
        'mode': 'read_only', 'automatic_repairs': False,
        'limitations': ['Candidates require Admin review; retained historical mismatches may be intentional.',
            'Past unauthorized reads cannot be reconstructed from present records. No exposure count is inferred.',
            'This audit cannot establish which actor or import caused an existing mismatch.'],
        'counts': dict(Counter(f['kind'] for f in findings)), 'candidate_count': len(findings), 'candidates': findings,
        'inspected': {'teams': len(teams), 'academic_records': len(records), 'memberships': len(memberships),
            'sections': SectionAssignment.objects.count(), 'weekly_reports': WeeklyProgressReport.objects.count()},
        'pit_import_review': import_review,
    }


def main():
    import django
    django.setup()
    from django.db import connection, transaction
    if connection.vendor != 'postgresql':
        raise RuntimeError('This audit requires PostgreSQL read-only transaction enforcement.')
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute('SET TRANSACTION READ ONLY')
        result = collect_findings()
    output = ROOT / '.tmp' / 'pit-capstone-integrity-review.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(result, indent=2, default=str), encoding='utf-8')
    print(json.dumps({'candidate_count': result['candidate_count'], 'counts': result['counts'], 'output': str(output)}))


if __name__ == '__main__':
    main()
