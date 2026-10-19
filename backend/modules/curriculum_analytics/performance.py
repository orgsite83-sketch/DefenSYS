"""Read-only student component comparisons for the curriculum explorer.

Component percentages are recorded grade values, never sums of criterion means.
Each event uses the latest published assessment for each selected team. Historical
students come from assessment records; today's membership cannot supply a past roster.
"""
from statistics import mean

from rest_framework.exceptions import ValidationError


def members(explorer, project, grade=None):
    people = {}
    grades = [grade] if grade else [g for g in project['grades'] if explorer._in_period(g)]
    team = project['team']
    current_period = (grade.semester_id == team.semester_id if grade else
                      str(team.semester_id) in project['periods'] and
                      (not explorer.year or team.semester.school_year.label == explorer.year) and
                      (not explorer.semester_id or str(team.semester_id) == explorer.semester_id))
    if current_period:
        people.update((m.student_id, m.student) for m in team.memberships.all())
    for assessment in grades:
        people.update((s.student_id, s.student) for s in assessment.student_grades.all())
        people.update((r.student_id, r.student) for r in explorer._valid_rows(assessment) if r.student_id)
    return people


def configure_selection(explorer, value):
    options, seen = [], set()
    for project in explorer.selected:
        team = project['team']
        options.append({'id': f'team:{team.pk}', 'label': team.name, 'kind': 'team'})
        for student_id, student in sorted(members(explorer, project).items(), key=lambda item: item[1].username):
            if student_id in seen:
                continue
            seen.add(student_id)
            name = student.get_full_name().strip() or student.username
            options.append({'id': f'student:{student_id}', 'label': name, 'kind': 'student'})
    explorer.subject = str(value or '')
    if explorer.subject and explorer.subject not in {o['id'] for o in options}:
        raise ValidationError({'subject': 'Select a team or student in this workflow and period.'})
    explorer.performance_options = options
    explorer.performance_selected = [p for p in explorer.selected if not explorer.subject or
        (explorer.subject.startswith('team:') and explorer.subject == f"team:{p['team'].pk}") or
        (explorer.subject.startswith('student:') and int(explorer.subject.split(':')[1]) in members(explorer, p))]


def selected_rows(explorer, grade):
    rows = explorer._valid_rows(grade)
    if explorer.subject.startswith('student:'):
        student_id = int(explorer.subject.split(':')[1])
        rows = [r for r in rows if r.student_id is None or r.student_id == student_id]
    return rows


def _component(explorer, grade, role, student_id):
    rubric_id = explorer._assigned_rubric(grade, role)
    rubric = explorer._rubric_objects.get(rubric_id)
    individual = role == 'peer' or (rubric is not None and rubric.target_type in ('individual', 'both'))
    individual |= any(r.evaluation_type == role and r.student_id is not None
                      for r in explorer._valid_rows(grade))
    summary = next((s for s in grade.student_grades.all() if s.student_id == student_id), None)
    field = f'{role}_score'
    if summary is not None and getattr(summary, field) is not None:
        return float(getattr(summary, field)), not individual
    if individual:
        return None, False
    value = getattr(grade, field)
    return (float(value) if value is not None else None), True


def build_performance(explorer, context_id=None):
    contexts = []
    for context in explorer.contexts:
        if context_id and context['id'] != context_id:
            continue
        buckets = {role: {'scores': {}, 'eligible': set(), 'shared': set(), 'available': False}
                   for role in explorer.roles}
        for (key, _), config in explorer.context_configs.items():
            if key != context['id']:
                continue
            for role, bucket in buckets.items():
                bucket['available'] |= bool(getattr(config, f'{role}_rubric_id', None) or
                                             getattr(config, f'{role}_weight', 0))
        for grade in explorer.grades:
            if not explorer._in_period(grade) or explorer.context_key(grade) != context['id']:
                continue
            recorded_roles = {r.evaluation_type for r in explorer._valid_rows(grade)}
            for role, bucket in buckets.items():
                bucket['available'] |= role in recorded_roles or getattr(grade, f'{role}_score') is not None or any(
                    getattr(s, f'{role}_score') is not None for s in grade.student_grades.all())
        if not any(bucket['available'] for bucket in buckets.values()):
            buckets['panel']['available'] = True
        for project in explorer.performance_selected:
            if context.get('semester_id') and context['semester_id'] not in project['periods']:
                continue
            grades = [g for g in project['grades'] if explorer._in_period(g) and
                      explorer.context_key(g) == context['id']]
            published = [g for g in grades if g.status == 'published']
            latest = max(published, key=lambda g: (g.published_at or g.updated_at, g.pk), default=None)
            people = members(explorer, project, latest) if latest else members(explorer, project)
            if explorer.subject.startswith('student:'):
                selected = int(explorer.subject.split(':')[1])
                people = {k: v for k, v in people.items() if k == selected}
            for role, bucket in buckets.items():
                if not bucket['available']:
                    continue
                bucket['eligible'].update(people)
                if latest is None:
                    continue
                for student_id in people:
                    value, shared = _component(explorer, latest, role, student_id)
                    if value is not None:
                        bucket['scores'].setdefault(student_id, []).append(value)
                        if shared:
                            bucket['shared'].add(student_id)
        components = []
        for role, bucket in buckets.items():
            scores = [mean(values) for values in bucket['scores'].values()]
            components.append({'id': role, 'label': explorer.roles[role],
                'score': round(mean(scores), 2) if scores else None,
                'assessed': len(scores), 'eligible': len(bucket['eligible']),
                'pending': len(bucket['eligible']) - len(scores),
                'shared': len(bucket['shared']), 'available': bucket['available']})
        contexts.append({**context, 'components': components})
    return {'contexts': contexts, 'selections': explorer.performance_options, 'subject': explorer.subject,
            'methodology': 'Recorded component percentages before weighting; latest published assessment per team and event. Students count once per event. Shared team results are labelled. Missing results are excluded.'}
