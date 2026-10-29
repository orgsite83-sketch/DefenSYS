"""Section defaults for confirmed, normal Capstone 2 continuation only.

Enrollment never grants eligibility. Previews are read-only, and reconciliation
only fills existing blank enrollment rows; it never creates enrollment/placement.
"""
import re

from django.db import transaction
from django.db.models import Q

from academic_period_management.models import Semester
from user_management.academic_records.models import StudentAcademicRecord
from .models import StudentTeam, TeamTermParticipation, StudentCapstonePlacement


POLICY_KEY = 'continuation_sections'
SECTION_PATTERN = re.compile(r'^BSIT\s*[- ]?\s*([34])\s*([A-Z]+)$', re.IGNORECASE)


def clean(value):
    return ' '.join((value or '').strip().split())


def progressed_section(section, source_year, target_year='4th Year'):
    """Preserve the class suffix, including fourth-year repeat intakes."""
    match = SECTION_PATTERN.fullmatch(clean(section))
    source_years = {'3': '3rd Year', '4': '4th Year'}
    if (not match or target_year != '4th Year'
            or source_year != source_years[match[1]]):
        return ''
    return f'BSIT-4{match[2].upper()}'


def transition_section_plan(team, source, target):
    """Called only for an academically eligible row of the transition preview."""
    from .participation import roster_ids
    ids = roster_ids(team)
    records = list(StudentAcademicRecord.objects.filter(
        student_id__in=ids, semester_id__in=[source.pk, target.pk]))
    previous = {r.student_id: r for r in records if r.semester_id == source.pk}
    destination = {r.student_id: r for r in records if r.semester_id == target.pk}
    students, sections, issues = [], set(), []
    for student_id in sorted(ids):
        old, current = previous.get(student_id), destination.get(student_id)
        assigned = clean(current.section) if current else ''
        from .section_years import capstone_section_issue
        issue = capstone_section_issue(assigned, '4th Year')
        if issue:
            issues.append(f'Student #{student_id}: {issue}')
        proposed = (assigned if not issue else '') or (progressed_section(old.section, old.year_level) if old else '')
        if proposed:
            sections.add(proposed)
        else:
            issues.append(f'Student #{student_id}: previous enrollment section needs review.')
        students.append({'student_id': student_id,
            'source_section': old.section if old else '', 'section': proposed,
            'source': 'existing' if assigned else ('inferred' if proposed else 'review')})
    if len(sections) > 1:
        issues.append('Destination section assignments conflict. Review the official roster.')
    return {'source_section': team.section,
        'section': next(iter(sections)) if len(sections) == 1 and not issues else '',
        'students': students, 'issues': issues}


def continued_contexts(term, student_ids):
    """Require recorded approval plus a live placement, never a team label alone."""
    if not term or term.label != Semester.FIRST or not term.is_active or not student_ids:
        return {}
    from .capstone_lifecycle import transition_kind
    from .participation import closed_failure
    rows = TeamTermParticipation.objects.filter(semester=term, closed_at__isnull=True,
        outcome='open', team__semester=term, team__level__icontains='Capstone',
        team__participation_review_reason='', transition__isnull=False).filter(
        Q(team__leader_id__in=student_ids) | Q(team__memberships__student_id__in=student_ids)
    ).select_related('team__intake_semester__school_year', 'team__semester__school_year',
        'transition__from_semester__school_year', 'transition__to_semester__school_year').distinct()
    contexts = {}
    for row in rows:
        team, log = row.team, row.transition
        source = log.from_semester
        if (not source or log.to_semester_id != term.pk or team.intake_semester_id != source.pk
                or row.project_version != team.project_version
                or transition_kind(source, term) != 'continue'
                or team.pk not in log.impact_snapshot.get('applied_team_ids', [])
                or closed_failure(team)):
            continue
        approved = any(r.get('team_id') == team.pk and r.get('can_include') is True
            for r in log.impact_snapshot.get('capstone_review', {}).get('teams', []))
        source_row = team.term_participations.filter(semester=source,
            project_version=team.project_version, outcome='open', closed_at__isnull=False).first()
        if not approved or not source_row:
            continue
        placements = StudentCapstonePlacement.objects.filter(team=team, ended_at__isnull=True,
            participation__state='active', participation__intake_semester=source,
            participation__student_id__in=student_ids).values_list('participation__student_id', flat=True)
        members = set(team.memberships.values_list('student_id', flat=True)) | {team.leader_id}
        for student_id in set(placements) & members:
            contexts.setdefault(student_id, []).append((row, source_row))
    return contexts


def section_decisions(term, years, explicit=None, *, _expanded=False):
    """Resolve a batch for preview/commit. Inferred preview values are never input."""
    explicit = explicit or {}
    contexts = continued_contexts(term, set(years))
    if contexts and not _expanded:
        from .participation import roster_ids
        all_ids = set(years)
        teams = {row.team_id: row.team for matches in contexts.values() for row, _ in matches}
        for team in teams.values():
            all_ids.update(roster_ids(team))
        if all_ids != set(years):
            actual_years = dict(StudentAcademicRecord.objects.filter(
                semester=term, student_id__in=all_ids).values_list('student_id', 'year_level'))
            expanded = {sid: actual_years.get(sid, '4th Year') for sid in all_ids}
            expanded.update(years)
            decisions = section_decisions(term, expanded, explicit, _expanded=True)
            return {sid: decisions[sid] for sid in years}
    source_terms = {old.semester_id for rows in contexts.values() for _, old in rows}
    records = {(r.student_id, r.semester_id): r for r in StudentAcademicRecord.objects.filter(
        student_id__in=years, semester_id__in=source_terms | {term.pk})}
    result = {}
    for student_id, year in years.items():
        supplied = clean(explicit.get(student_id))
        current = records.get((student_id, term.pk))
        existing = clean(current.section) if current else ''
        decision = {'section': supplied or existing, 'source': 'explicit' if supplied else (
            'existing' if existing else 'unassigned'), 'message': ''}
        from .section_years import enrollment_section_issue
        issue = enrollment_section_issue(supplied or existing, year, term)
        if issue:
            decision.update(source='review', message=issue)
            result[student_id] = decision
            continue
        matches = contexts.get(student_id, [])
        if not matches:
            result[student_id] = decision
            continue
        if len(matches) != 1:
            decision.update(source='review', message='Conflicting confirmed Capstone placements require review.')
            result[student_id] = decision
            continue
        row, old_row = matches[0]
        team = row.team
        decision['team_id'] = team.pk
        previous = records.get((student_id, old_row.semester_id))
        proposed = progressed_section(previous.section, previous.year_level, year) if previous else ''
        policy = row.snapshot.get(POLICY_KEY, {})
        baseline = policy.get('team_section', old_row.snapshot.get('section', ''))
        # Comparing against the stable baseline also protects edits made outside
        # the roster serializer. Never treat a later snapshot refresh as consent.
        override = policy.get('admin_override', False) or team.section != baseline
        if override and clean(team.section):
            decision.update(section=existing or clean(team.section), source='admin',
                message='Preserves the section assigned in Student Teams.')
        elif not supplied and not existing:
            if year != '4th Year':
                decision.update(source='review', message='Confirmed continuation requires fourth-year enrollment.')
            elif proposed:
                decision.update(section=proposed, source='inferred',
                    message=f'Capstone 2 continuation: {previous.section} → {proposed}.')
            else:
                decision.update(source='review', message='Previous enrollment section is missing or unrecognized; enter the official section.')
        result[student_id] = decision
    # A class split must be reviewed; never fill blanks from contradictory defaults.
    by_team = {}
    for decision in result.values():
        if decision.get('team_id') and decision['section']:
            by_team.setdefault(decision['team_id'], set()).add(decision['section'])
    for decision in result.values():
        if len(by_team.get(decision.get('team_id'), set())) > 1:
            if decision['source'] == 'inferred':
                decision['section'] = ''
            decision.update(source='review', message='Destination sections conflict; review the official roster.')
    return result


def mark_admin_section_change(team, previous_section):
    if not team.is_capstone or previous_section == team.section:
        return
    row = team.term_participations.select_for_update().filter(
        semester=team.semester, closed_at__isnull=True).first()
    if row and row.snapshot.get(POLICY_KEY):
        row.snapshot[POLICY_KEY]['admin_override'] = True
        row.save(update_fields=['snapshot', 'updated_at'])


@transaction.atomic
def apply_transition_sections(team, source, target, row, plan, actor=None):
    """The confirmed eligible transition is the sole creator of this policy."""
    old_section = team.section
    if plan['section']:
        team.section = plan['section']
        team.save(update_fields=['section', 'updated_at'])
    else:
        from .section_years import capstone_section_issue
        if capstone_section_issue(team.section, team.year_level):
            team.section = ''
            team.save(update_fields=['section', 'updated_at'])
    row.snapshot[POLICY_KEY] = {'source_semester_id': source.pk,
        'team_section': team.section, 'admin_override': False}
    row.snapshot['section'] = team.section
    row.save(update_fields=['snapshot', 'updated_at'])
    changes = []
    if not plan['issues']:
        for student in plan['students']:
            if student['source'] == 'inferred':
                record = StudentAcademicRecord.objects.filter(student_id=student['student_id'],
                    semester=target, year_level='4th Year', section='').first()
                if record:
                    record.section = student['section']
                    record.save(update_fields=['section'])
                    changes.append({'record_id': record.pk, 'section': record.section})
    _audit(team, old_section, changes, actor)


def _audit(team, old_section, changes, actor):
    if changes or team.section != old_section:
        from .history_events import record_team_event
        record_team_event(team, 'capstone.sections_reconciled', actor=actor,
            old_values={'section': old_section},
            values={'section': team.section, 'enrollment_sections': changes})


@transaction.atomic
def reconcile_sections(term, student_ids, actor=None, applied_defaults=None):
    """Only touch confirmed live continuations and already-created enrollment."""
    contexts = continued_contexts(term, student_ids)
    teams = {row.team_id: row.team for matches in contexts.values() for row, _ in matches}
    source_sections = {row.team_id: old.snapshot.get('section', '')
        for matches in contexts.values() for row, old in matches}
    from .participation import roster_ids
    for team_id in sorted(teams):
        team = StudentTeam.objects.select_for_update().get(pk=team_id)
        ids = roster_ids(team)
        records = list(StudentAcademicRecord.objects.select_for_update().filter(
            semester=term, student_id__in=ids).order_by('pk'))
        years = {r.student_id: r.year_level for r in records}
        decisions = section_decisions(term, years)
        changes = [{'record_id': r.pk, 'section': r.section} for r in records
            if (applied_defaults or {}).get(r.student_id) == r.section and r.section]
        for record in records:
            decision = decisions[record.student_id]
            if not clean(record.section) and decision['section'] and decision['source'] in ('inferred', 'admin'):
                record.section = decision['section']
                record.save(update_fields=['section'])
                changes.append({'record_id': record.pk, 'section': record.section})
        old_section = team.section
        row = team.term_participations.get(semester=term)
        policy = row.snapshot.get(POLICY_KEY, {})
        baseline = policy.get('team_section', source_sections.get(team_id, old_section))
        admin_override = bool(policy.get('admin_override') or old_section != baseline)
        sections = {clean(r.section) for r in records}
        if (len(records) == len(ids) and all(r.year_level == '4th Year' for r in records)
                and len(sections) == 1 and '' not in sections
                and not admin_override):
            team.section = sections.pop()
            if team.section != old_section:
                team.save(update_fields=['section', 'updated_at'])
        if changes or team.section != old_section or (admin_override and not policy.get('admin_override')):
            from .capstone_lifecycle import capture_participation
            row = capture_participation(team)
            policy = row.snapshot.setdefault(POLICY_KEY, {'source_semester_id': team.intake_semester_id})
            policy.update(team_section=team.section, admin_override=admin_override)
            row.save(update_fields=['snapshot', 'updated_at'])
            _audit(team, old_section, changes, actor)
