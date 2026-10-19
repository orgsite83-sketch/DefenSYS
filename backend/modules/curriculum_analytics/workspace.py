"""Progressive curriculum views. No criteria are equated across assessments."""
from collections import Counter
from statistics import mean

from rest_framework.exceptions import ValidationError
from grading.grades.models import TeamGrade
from grading.grades.defense_workflow import passed_and_cleared
from .comparisons import comparison_key
from .performance import members


def archive_completion_allowed(explorer, entry, semester):
    if not semester or entry.status != 'Approved':
        return False
    if explorer.scope == 'capstone' and entry.stage_label:
        configs = [c for (_, sid), c in explorer._historical_configs.items()
                   if explorer.semesters[str(sid)].school_year.label == semester.school_year.label]
        matched = [c for c in configs if c.defense_stage.label.casefold() == entry.stage_label.casefold()]
        if matched:
            return any(c.is_officially_complete and c.defense_stage.display_order == max(
                x.defense_stage.display_order for x in configs) for c in matched)
    if explorer.scope == 'pit' and entry.pit_event_config_id:
        return entry.pit_event_config.is_officially_complete
    # Imported, approved project archives can predate structured assessments.
    return True


def configure_range(explorer, params):
    years = sorted({explorer.semesters[p].school_year.label for project in explorer.projects.values()
                    for p in project['periods'] if p in explorer.semesters})
    explorer.recorded_years = years
    start = params.get('year_from') or (years[-5] if len(years) >= 5 else years[0] if years else '')
    end = params.get('year_to') or (years[-1] if years else '')
    if explorer.view and ((start and start not in years) or (end and end not in years) or start > end):
        raise ValidationError({'year_range': 'Choose an ordered range of recorded academic years.'})
    explorer.year_from, explorer.year_to = start, end
    explorer.range_years = [y for y in years if start <= y <= end]
    explorer.project_status = params.get('project_status') or 'completed'
    if explorer.project_status not in ('completed', 'all'):
        raise ValidationError({'project_status': 'Select completed projects or all project records.'})
    if explorer.view in ('year', 'assessment') and explorer.year not in explorer.range_years:
        raise ValidationError({'academic_year': 'Select an academic year inside the chosen range.'})


def _latest(grades):
    return max(grades, key=lambda g: (g.published_at or g.updated_at, g.pk), default=None)


def _rubric_signature(explorer, grade):
    parts, names = [], set()
    for role in explorer.roles:
        rubric = explorer._rubric_objects.get(explorer._assigned_rubric(grade, role))
        if rubric:
            names.add(rubric.name)
            parts.append((role, rubric.target_type, tuple(sorted(
                (c.name.casefold().strip(), float(c.max_score), c.target_type) for c in rubric.criteria.all()))))
    rows = explorer._valid_rows(grade)
    names.update(r.rubric.name for r in rows if r.rubric_id)
    if not parts:
        parts = sorted({(r.evaluation_type, r.criterion_name.casefold().strip(), float(r.max_score),
                         bool(r.student_id)) for r in rows})
    weights = (grade.panel_weight, grade.peer_weight, grade.adviser_weight)
    return repr((parts, weights)), names


def _assessment(explorer, projects, grades, year):
    by_project = {}
    for grade in grades:
        by_project.setdefault((grade.team_id, grade.project_version), []).append(grade)
    scores, people, assessed_people, signatures, rubrics = [], set(), set(), set(), set()
    for project in projects:
        group = by_project.get((project['team'].pk, project['version']), [])
        latest = _latest([g for g in group if g.status == TeamGrade.STATUS_PUBLISHED and g.final_grade is not None])
        roster_grade = latest or _latest(group)
        period_project = {**project, 'grades': [g for g in project['grades'] if g.semester.school_year.label == year],
                          'periods': {p for p in project['periods'] if explorer.semesters[p].school_year.label == year}}
        roster = members(explorer, period_project, roster_grade)
        people.update(roster)
        if latest:
            scores.append(float(latest.final_grade))
            assessed_people.update(roster)
            signature, names = _rubric_signature(explorer, latest)
            signatures.add(signature)
            rubrics.update(names)
    return {'score': round(mean(scores), 2) if scores else None,
            'assessed': len(scores), 'eligible': len(projects), 'pending': len(projects) - len(scores),
            'students': len(people), 'assessed_students': len(assessed_people),
            'rubrics': sorted(rubrics), '_signatures': signatures, '_people': assessed_people,
            'distribution': [{'label': label, 'count': sum(low <= s < high for s in scores)}
                             for label, low, high in [('Below 75%', 0, 75), ('75–84%', 75, 85),
                                                      ('85–94%', 85, 95), ('95–100%', 95, 101)]]}


def _period_projects(explorer, year, semester_label=None, context=None):
    projects = explorer._selected_projects(year=year, semester_id='')
    if semester_label:
        projects = [p for p in projects if any(explorer.semesters[s].school_year.label == year and
                    explorer.semesters[s].label == semester_label for s in p['periods'] if s in explorer.semesters)]
    if context and context.startswith('stage:'):
        periods = {str(sid) for (key, sid) in explorer._historical_configs if key == context and
                   explorer.semesters[str(sid)].school_year.label == year}
        periods.update(str(r.semester_id) for r in explorer._rubric_objects.values() if
                       f'stage:{r.defense_stage_id}' == context and str(r.semester_id) in explorer.semesters and
                       explorer.semesters[str(r.semester_id)].school_year.label == year)
        periods.update(str(g.semester_id) for g in explorer.grades if explorer.context_key(g) == context and
                       g.semester.school_year.label == year)
        projects = [p for p in projects if p['periods'] & periods]
    return projects


def _completion_periods(explorer, project):
    periods = set(project['completed_periods'])
    # Use configured assessment closure, never a high score alone, as completion.
    orders = {}
    if explorer.scope == 'capstone':
        for (_, semester_id), config in explorer._historical_configs.items():
            year = explorer.semesters[str(semester_id)].school_year.label
            orders[year] = max(orders.get(year, 0), config.defense_stage.display_order)
    for grade in project['grades']:
        if grade.status != TeamGrade.STATUS_PUBLISHED:
            continue
        if explorer.scope == 'pit':
            complete = (grade.pit_event_config_id and grade.pit_event_config.is_officially_complete and
                        grade.final_grade is not None and passed_and_cleared(grade))
        else:
            config = explorer._historical_configs.get((explorer.context_key(grade), grade.semester_id))
            complete = (config and config.is_officially_complete and grade.defense_stage_id and
                        grade.defense_stage.display_order == orders.get(grade.semester.school_year.label) and
                        passed_and_cleared(grade))
        if complete:
            periods.add(str(grade.semester_id))
    return periods


def _project_collection(explorer):
    collection, years = [], Counter()
    for project in explorer.projects.values():
        periods = _completion_periods(explorer, project) if explorer.project_status == 'completed' else project['periods']
        periods = [explorer.semesters[p] for p in periods if p in explorer.semesters]
        if explorer.project_status == 'all':
            periods = [s for s in periods if s.school_year.label <= explorer.year_to]
        if not periods:
            continue
        # A completed project belongs to its first documented completion year.
        period = min(periods, key=lambda s: (s.school_year.label, s.pk)) if explorer.project_status == 'completed' else max(
            periods, key=lambda s: (s.school_year.label, s.pk))
        year = period.school_year.label
        if year not in explorer.range_years or (explorer.year and explorer.year != year):
            continue
        years[year] += 1
        if explorer.view == 'projects':
            historic = _latest([g for g in project['grades'] if g.semester.school_year.label == year])
            project = {**project, 'title': historic.project_title_snapshot if historic and historic.project_title_snapshot else project['title']}
            classification = explorer._category(project, year, '')
            collection.append({'id': project['key'], 'team_id': project['team'].pk,
                'team_name': project['team'].name, 'project_title': project['title'],
                'project_version': project['version'], 'academic_year': year,
                'category': classification['label'], 'domain': classification['domain'],
                'technologies': [t['name'] for t in classification['technologies']],
                'classification_status': classification['status'], 'classification_reason': classification['reason'],
                'classification_reason_code': classification['reason_code']})
    return sorted(collection, key=lambda p: (p['academic_year'], p['team_name'])), years


def workspace_payload(explorer):
    data = {'view': explorer.view, 'scope': explorer.scope, 'year_level': explorer.year_level,
            'academic_year': explorer.year, 'year_from': explorer.year_from, 'year_to': explorer.year_to,
            'academic_years': explorer.recorded_years, 'range_years': explorer.range_years,
            'comparison': explorer.comparison, 'comparison_options': explorer.comparison_options,
            'context': explorer.context_id, 'evaluation_type': explorer.role,
            'contexts': explorer.contexts, 'roles': [{'id': k, 'label': v} for k, v in explorer.roles.items()],
            'semesters': [{'id': str(s.pk), 'label': s.label} for s in explorer.semesters.values()
                          if s.school_year.label == explorer.year and explorer._period_allowed(s)],
            'score_unit': 'teams', 'reference': explorer.reference}
    if explorer.view == 'overview':
        option = next((o for o in explorer.comparison_options if o['id'] == explorer.comparison), {})
        rows, signatures = [], set()
        for year in explorer.range_years:
            projects = _period_projects(explorer, year, option.get('semester_label'), explorer.comparison)
            grades = [g for p in projects for g in p['grades'] if g.semester.school_year.label == year and
                      explorer.comparison and comparison_key(explorer, g) == explorer.comparison]
            summary = _assessment(explorer, projects, grades, year)
            signatures.update(summary.pop('_signatures'))
            summary.pop('_people')
            rows.append({'academic_year': year, **summary, 'in_progress': any(
                s.is_active and s.school_year.label == year for s in explorer.semesters.values())})
        data.update(annual_performance=rows, rubric_changed=len(signatures) > 1,
                    assessment_label=option.get('label', 'Select an assessment'))
    elif explorer.view == 'year':
        rows, cohorts = [], []
        for context in explorer.contexts:
            projects = _period_projects(explorer, explorer.year, context.get('semester_label'), context['id'])
            grades = [g for p in projects for g in p['grades'] if explorer._in_period(g) and
                      explorer.context_key(g) == context['id']]
            summary = _assessment(explorer, projects, grades, explorer.year)
            summary.pop('_signatures')
            people = summary.pop('_people')
            if summary['assessed']:
                cohorts.append(people)
            rows.append({**context, **summary})
        data.update(stage_results=rows, matched_students=len(set.intersection(*cohorts)) if cohorts else 0)
    elif explorer.view == 'assessment':
        data.update(performance=explorer.performance, criteria=explorer.criteria,
                    assessment_summary=explorer._assessment_summary(), subject=explorer.subject)
    else:
        collection, counts = _project_collection(explorer)
        data.update(projects=collection, projects_count=sum(counts.values()), project_status=explorer.project_status,
            project_output=[{'academic_year': y, 'count': counts[y]} for y in explorer.range_years],
            completion_policy=(
                'Approved project archive, or a published passing result in an officially closed PIT event / last configured Capstone stage with defense revisions cleared. Known earlier-stage archives do not establish final completion. Each project version counts once, in its first documented completion year.'
                if explorer.project_status == 'completed' else
                'Includes work in progress. Each project version counts once, in its latest recorded academic year up to the selected end year. Stages, assessment attempts and document copies do not add projects.'))
        if explorer.view == 'projects':
            data['project_analytics'] = explorer._project_analytics(collection)
    return data
