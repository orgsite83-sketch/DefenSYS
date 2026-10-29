"""Explicit, backed-up correction of labels carried by earlier transitions."""
from hashlib import sha256
import json
from pathlib import Path

from django.core.serializers import serialize
from django.core.serializers.json import DjangoJSONEncoder
from django.db import transaction

from academic_period_management.models import Semester
from user_management.academic_records.models import StudentAcademicRecord
from .continuation_sections import (POLICY_KEY, apply_transition_sections,
    continued_contexts, transition_section_plan)
from .models import StudentTeam, TeamTermParticipation, SectionAssignment
from .section_years import capstone_section_issue


def correction_plan(term):
    teams = list(StudentTeam.objects.filter(semester=term, level__icontains='Capstone')
        .select_related('semester__school_year').prefetch_related('memberships').order_by('pk'))
    ids = {sid for team in teams for sid in (
        {team.leader_id} | {m.student_id for m in team.memberships.all()})}
    contexts = continued_contexts(term, ids)
    evidence = {row.team_id: (row, old) for matches in contexts.values() for row, old in matches}
    changes, skipped, fingerprints, enrollment_warnings = [], [], [], []
    for team in teams:
        if not capstone_section_issue(team.section, team.year_level):
            continue
        reason, plan = '', None
        rows = evidence.get(team.pk)
        if not rows:
            reason = 'No approved normal continuation with an active student placement.'
        else:
            row, old = rows
            policy = row.snapshot.get(POLICY_KEY, {})
            if (policy.get('admin_override') or team.section != old.snapshot.get('section')
                    or team.section != policy.get('team_section', team.section)):
                reason = 'Section was changed after migration; administrator review is required.'
            else:
                plan = transition_section_plan(team, old.semester, term)
                if plan['issues'] or not plan['section']:
                    reason = ' '.join(plan['issues']) or 'No reliable destination section.'
        if reason:
            skipped.append({'team_id': team.pk, 'section': team.section, 'reason': reason})
            continue
        enrollment_ids = list(StudentAcademicRecord.objects.filter(semester=term, section='',
            year_level='4th Year', student_id__in=[s['student_id'] for s in plan['students']]
        ).order_by('pk').values_list('pk', flat=True))
        enrollment_warnings.extend({'team_id': team.pk, 'record_id': r.pk,
            'student_id': r.student_id, 'year_level': r.year_level,
            'reason': 'Existing enrollment year differs from the approved continuing team; retained for administrator review.'}
            for r in StudentAcademicRecord.objects.filter(semester=term,
                student_id__in=[s['student_id'] for s in plan['students']]).exclude(year_level='4th Year'))
        changes.append({'team_id': team.pk, 'source_section': team.section,
            'section': plan['section'], 'enrollment_ids': enrollment_ids, 'plan': plan})
        fingerprints.append({'team': list(StudentTeam.objects.filter(pk=team.pk).values()),
            'source': list(TeamTermParticipation.objects.filter(pk=old.pk).values()),
            'destination': list(TeamTermParticipation.objects.filter(pk=row.pk).values()),
            'approval': row.transition.impact_snapshot,
            'enrollment': list(StudentAcademicRecord.objects.filter(semester_id__in=[old.semester_id, term.pk],
                student_id__in=[s['student_id'] for s in plan['students']]).order_by('pk').values())})
    # Move only Capstone metadata for exactly the old/new class names. Never
    # relabel PIT sections or merge two pre-existing class assignments.
    mappings = {(r['source_section'], r['section']) for r in changes}
    assignments, blockers = [], []
    for old, new in sorted(mappings):
        rows = SectionAssignment.objects.filter(semester=term, year_level='4th Year', section=old)
        if rows.exists() and SectionAssignment.objects.filter(semester=term, section=new).exists():
            blockers.append(f'Section {new} already has class metadata; review it before correction.')
        assignments.extend({'id': r.pk, 'section': new} for r in rows)
    all_enrollment_ids = sorted({pk for r in changes for pk in r['enrollment_ids']})
    payload = {'semester_id': term.pk, 'changes': changes, 'skipped': skipped,
        'assignments': assignments, 'blockers': blockers, 'fingerprints': fingerprints,
        'assignment_state': list(SectionAssignment.objects.filter(semester=term).order_by('pk').values())}
    revision = sha256(json.dumps(payload, cls=DjangoJSONEncoder, sort_keys=True).encode()).hexdigest()
    return {'semester_id': term.pk, 'period': term.display_name, 'revision': revision,
        'team_count': len(changes), 'enrollment_count': len(all_enrollment_ids),
        'enrollment_ids': all_enrollment_ids, 'teams': changes, 'skipped': skipped,
        'enrollment_warnings': enrollment_warnings,
        'assignments': assignments, 'blockers': blockers, 'applied': False}


@transaction.atomic
def correct_current_sections(*, semester_id, actor=None, apply=False, backup_path=None,
                             revision='', expected_teams=None, expected_enrollments=None,
                             reason='Correction of section labels carried by an approved Capstone 2 transition.'):
    if apply:
        from defensys_backend.db_guard import assert_safe_for_orm_writes
        assert_safe_for_orm_writes()
        if not actor or not actor.is_active or not (actor.role == 'admin' or actor.is_superuser):
            raise ValueError('An active administrator must be identified for the correction audit.')
        if not backup_path or not revision or not reason.strip():
            raise ValueError('Apply requires a backup path, reviewed revision, and reason.')
        list(Semester.objects.select_for_update().order_by('pk'))
    term = Semester.objects.select_related('school_year').get(pk=semester_id, is_active=True)
    if apply:
        from django.contrib.auth import get_user_model
        from .participation import roster_ids
        teams = list(StudentTeam.objects.filter(semester=term, level__icontains='Capstone'))
        ids = {sid for team in teams for sid in roster_ids(team)}
        list(get_user_model().objects.select_for_update().filter(pk__in=ids).order_by('pk'))
        list(StudentTeam.objects.select_for_update().filter(pk__in=[t.pk for t in teams]).order_by('pk'))
        list(StudentAcademicRecord.objects.select_for_update().filter(semester=term,
            student_id__in=ids).order_by('pk'))
        list(TeamTermParticipation.objects.select_for_update().filter(team__in=teams).order_by('pk'))
        list(SectionAssignment.objects.select_for_update().filter(semester=term).order_by('pk'))
    review = correction_plan(term)
    if not apply:
        return review
    if revision != review['revision']:
        raise ValueError('Section data changed. Regenerate and review the correction preview.')
    if expected_teams != review['team_count'] or expected_enrollments != review['enrollment_count']:
        raise ValueError('Correction counts differ from the exact reviewed scope.')
    if review['blockers']:
        raise ValueError(' '.join(review['blockers']))
    if not review['team_count']:
        return review
    team_ids = [r['team_id'] for r in review['teams']]
    originals = [*StudentTeam.objects.filter(pk__in=team_ids),
        *TeamTermParticipation.objects.filter(team_id__in=team_ids, semester=term),
        *StudentAcademicRecord.objects.filter(pk__in=review['enrollment_ids']),
        *SectionAssignment.objects.filter(pk__in=[r['id'] for r in review['assignments']])]
    backup = Path(backup_path).resolve()
    backup.parent.mkdir(parents=True, exist_ok=True)
    with backup.open('x', encoding='utf-8') as handle:
        json.dump({'review': review, 'reason': reason,
            'records_before': json.loads(serialize('json', originals))}, handle, indent=2)
    for item in review['teams']:
        team = StudentTeam.objects.select_related('semester__school_year').get(pk=item['team_id'])
        row = team.term_participations.select_related('transition__from_semester').get(semester=term)
        apply_transition_sections(team, row.transition.from_semester, term, row, item['plan'], actor=actor)
    for item in review['assignments']:
        SectionAssignment.objects.filter(pk=item['id']).update(section=item['section'])
    from authentication_access_control.audit import log_high_impact_action
    from authentication_access_control.models import SystemAuditLog
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
        action='capstone.section_labels_corrected', target=term, actor=actor, strict=True,
        old_values={'semester_id': term.pk, 'teams': [
            {'team_id': r['team_id'], 'section': r['source_section']} for r in review['teams']]},
        new_values={'semester_id': term.pk, 'teams': [
            {'team_id': r['team_id'], 'section': r['section']} for r in review['teams']],
            'enrollment_ids': review['enrollment_ids'], 'backup': str(backup)}, reason=reason)
    return {**review, 'applied': True, 'backup': str(backup)}
