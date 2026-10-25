"""Read-only projections for both authorized team-import workflows."""
from collections import defaultdict

from django.db.models import Q
from rest_framework.exceptions import PermissionDenied, ValidationError

from user_management.academic_records.models import StudentAcademicRecord
from .bulk_import import (collect_bulk_section_metadata, format_bulk_import_errors,
    import_user_lookup, imported_concept_requirement, resolve_user_by_full_name)
from .models import SectionAssignment, TeamMembership
from .serializers import display_name


def section_import_summaries(rows, preview_rows, term, *, import_section='', year='',
                             system_name='', project_manager='', metadata=None, user=None):
    """Use row-scoped headers, never the first system found in another section."""
    metadata = metadata if metadata is not None else collect_bulk_section_metadata(rows,
        import_section=import_section, system_name=system_name, project_manager=project_manager)
    grouped = defaultdict(list)
    for index, row in enumerate(rows):
        if isinstance(row, dict):
            grouped[(row.get('section') or import_section or '').strip()].append((index, row))
    existing = {a.section: a for a in SectionAssignment.objects.filter(
        semester=term, section__in=grouped).select_related('project_manager')}
    previews = {r.get('row'): r for r in preview_rows}
    summaries = []
    with import_user_lookup():
        for section, items in grouped.items():
            assignment = existing.get(section)
            if assignment and user is not None:
                from .section_access import require_section_write
                try:
                    require_section_write(user, term, assignment.year_level, section)
                except (PermissionDenied, ValidationError):
                    # Invalid uploaded scope must not reveal another cohort's saved details.
                    assignment = None
            meta = metadata.get(section, {})
            if not meta and not assignment and not any(r.get('project_kind') == 'module' for _, r in items):
                continue
            if not meta and assignment and not (assignment.system_name or assignment.project_manager_id):
                continue
            uploaded_system = meta.get('system_name', '')
            uploaded_manager = meta.get('project_manager', '')
            manager = assignment.project_manager if assignment else None
            if uploaded_manager:
                manager, _ = resolve_user_by_full_name(uploaded_manager, role='student', field_label='Project Manager')
            effective_system = uploaded_system or (assignment.system_name if assignment else '')
            issues = list(meta.get('issues', []))
            warnings = []
            for index, _ in items:
                result = previews.get(index + 1, {})
                if result.get('section_metadata_invalid'):
                    issues.extend(result.get('metadata_issues', result.get('issues', [])))
            issues = list(dict.fromkeys(issues))
            checked = not preview_rows or all(index + 1 in previews for index, _ in items)
            summaries.append({
                'section': section, 'year_level': year or items[0][1].get('year_level', ''),
                'system_name': effective_system, 'uploaded_system_name': uploaded_system,
                'project_manager_reference': uploaded_manager,
                'project_manager_name': display_name(manager) or uploaded_manager,
                'project_manager_username': manager.username if manager else '',
                'previous_system_name': assignment.system_name if assignment else '',
                'previous_project_manager_name': display_name(assignment.project_manager) if assignment else '',
                'previous_project_manager_username': assignment.project_manager.username if assignment and assignment.project_manager else '',
                'retains_system_name': not bool(uploaded_system) and bool(assignment and assignment.system_name),
                'retains_project_manager': not bool(uploaded_manager) and bool(manager),
                'team_count': len(items), 'group_keys': [r.get('group_key', '') for _, r in items],
                'rows': [index + 1 for index, _ in items], 'ready': checked and not issues,
                'issues': issues, 'warnings': warnings,
            })
    return summaries


def review_roster_import(user, term, year, section, raw, event, *, workspace=None):
    """Collect correctable errors without issuing a token or changing enrollment."""
    from .roster_workspace import imported_rows, imported_sheet_details, validate_rows
    from .pit_rosters import membership_queryset
    if not isinstance(raw, list) or not 0 < len(raw) <= 500:
        raise ValidationError('Upload between 1 and 500 teams.')
    results, resolved = [], {}
    with import_user_lookup():
        for index, item in enumerate(raw):
            result = {'row': index + 1, 'group_key': item.get('group_key', '') if isinstance(item, dict) else '',
                'section': section, 'program_label': f'{year} PIT', 'ready': False,
                'issues': [], 'warnings': [], 'notes': []}
            results.append(result)
            try:
                row = imported_rows(term, year, section, [item])[0]
                row['group_key'] = result['group_key'] or f'import/{index}'
                resolved[index] = row
            except (ValidationError, PermissionDenied) as exc:
                result['issues'].extend(format_bulk_import_errors(exc.detail))
        members = {member for row in resolved.values() for member in row['member_ids']}
        enrollment = dict(StudentAcademicRecord.objects.filter(
            Q(section=section) | Q(section='') | Q(section__iexact='BSIT'), semester=term,
            year_level=year, student__is_active=True, student__role='student',
            student_id__in=members).values_list('student_id', 'section'))
        other = TeamMembership.objects.filter(student_id__in=members, team__semester=term,
            team__year_level=year, team__level__icontains='PIT').exclude(team__section=section)
        conflicts = set(membership_queryset(other, event.event_name if event else None).values_list('student_id', flat=True))
        names, memberships = defaultdict(list), defaultdict(list)
        for index, row in resolved.items():
            result = results[index]
            if row['name']:
                names[row['name'].casefold()].append(index)
            for member in set(row['member_ids']):
                memberships[member].append(index)
            try:
                validate_rows(term, year, section, [row], event, allow_unassigned=True,
                    enrollment=set(enrollment), conflicts=conflicts)
                imported_sheet_details(user, term, year, section,
                    [{'instructor_name': raw[index].get('instructor_name', '')}], workspace=workspace)
                assignment, policy = imported_concept_requirement({
                    'team_name': row['name'], 'project_title': row['project_title'],
                    'level': f'{year} PIT', 'year_level': year, 'section': section,
                    'system_name': raw[index].get('system_name', ''),
                    'current_defense_stage': event.event_name if event else None})
                if policy['mode'] != assignment['mode'] or policy['mode'] == 'assigned' and not policy.get('assigned_title'):
                    raise ValidationError('The section concept policy conflicts with an imported title. Review the section policy before importing.')
                result['concept_requirement'] = policy
                unassigned = sum(enrollment[member].casefold() in ('', 'bsit') for member in row['member_ids'])
                if unassigned:
                    result['notes'].append(f'{unassigned} student' + ('s' if unassigned != 1 else '')
                        + f' will be assigned to {section} when this roster is applied.')
                if raw[index].get('adviser_name') or raw[index].get('adviser_id'):
                    result['warnings'].append('PIT uses assigned section instructors; Adviser input is ignored.')
            except (ValidationError, PermissionDenied) as exc:
                result['issues'].extend(format_bulk_import_errors(exc.detail))
        for indices in names.values():
            if len(indices) > 1:
                for index in indices:
                    results[index]['issues'].append('The team name is repeated in this file.')
        for indices in memberships.values():
            if len(indices) > 1:
                for index in indices:
                    if event and event.team_membership_policy == 'multiple':
                        results[index]['warnings'].append('A student appears in multiple teams, as allowed for this event.')
                    else:
                        results[index]['issues'].append('A student appears in more than one team in this replacement.')
        valid_members = {m for index, row in resolved.items() if not results[index]['issues'] for m in row['member_ids']}
        try:
            imported_sheet_details(user, term, year, section,
                [{**item, 'instructor_name': ''} for item in raw if isinstance(item, dict)],
                member_ids=valid_members, workspace=workspace)
        except (ValidationError, PermissionDenied) as exc:
            issues = format_bulk_import_errors(exc.detail)
            for result in results:
                result['issues'].extend(issues)
                result['metadata_issues'] = issues
                result['section_metadata_invalid'] = True
        for result in results:
            result['issues'] = list(dict.fromkeys(result['issues']))
            result['warnings'] = list(dict.fromkeys(result['warnings']))
            result['ready'] = not result['issues']
        summaries = section_import_summaries(raw, results, term, import_section=section, year=year, user=user)
    return {'rows': results, 'ready': all(r['ready'] for r in results),
        'section_summaries': summaries, 'summary': {
            'ready': sum(r['ready'] and not r['warnings'] for r in results),
            'warnings': sum(r['ready'] and bool(r['warnings']) for r in results),
            'issues': sum(not r['ready'] for r in results)}}
