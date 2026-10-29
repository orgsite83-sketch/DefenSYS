"""Read-only, cohort-first grade tables shared by the workspace and reports.

Enrollment is the left side of the student join: an ungraded/unassigned student
must not disappear. List assembly never synchronizes or creates grade records.
"""
from collections import defaultdict
from decimal import Decimal

from django.db.models import Count, Prefetch, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from academic_period_management.models import Semester
from authentication_access_control.scopes import is_admin_user, is_pit_lead_only
from authentication_access_control.workspaces import workspace_grades_for, workspace_teams_for
from defense.scheduler.event_scope import pit_events_for_user
from defense.scheduler.models import PitEventGradingConfig
from defense.stages.models import DefenseStage, StageGradingConfig
from grading.grades.models import StudentStageGrade
from grading.grades.evaluator_identity import public_guest_name
from student_teams.models import StudentTeam
from user_management.academic_records.models import StudentAcademicRecord

PAGE_SIZES = (10, 25, 50, 100)
STATUSES = ('pending', 'published', 'awaiting_peers', 'awaiting_evaluations', 'not_assessed', 'no_team')
COMPONENTS = ('panel', 'adviser', 'peer')


def display_name(user):
    return user.get_full_name().strip() or user.username


def can_view_peer_evidence(user, scope, year_level):
    """Raw peer-rater evidence is an oversight capability, not panel membership."""
    return is_admin_user(user) or bool(is_pit_lead_only(user) and scope == 'pit'
        and user.pit_lead_year and user.pit_lead_year == year_level)


def component_values(grade, student_grade=None, *, individual=False):
    """Present stored results; never infer an individual final from a team total."""
    enabled = {
        'panel': grade.panel_weight > 0,
        'adviser': grade.scope == 'capstone' and grade.adviser_weight > 0
        and (grade.semester.capstone_adviser_grading_enabled or grade.adviser_score is not None
             or bool(student_grade and student_grade.adviser_score is not None)),
        'peer': grade.peer_weight > 0 and (
            grade.scope == 'pit' or grade.semester.capstone_peer_evaluation_enabled
            or grade.peer_score is not None or bool(student_grade and student_grade.peer_score is not None)
        ),
    }
    values = {}
    for name in COMPONENTS:
        value = getattr(student_grade, f'{name}_score', None) if individual else getattr(grade, f'{name}_score')
        # Adviser and team-target panel scores may legitimately be shared.
        rubric = grade.schedule.rubric if grade.schedule_id and grade.schedule.rubric_id else (
            grade.pit_event_config.panel_rubric if grade.pit_event_config_id else None)
        shared = name == 'adviser' or (name == 'panel' and (not rubric or rubric.target_type == 'team'))
        if individual and value is None and shared:
            value = getattr(grade, f'{name}_score')
        weight = getattr(grade, f'{name}_weight')
        values[name] = {
            'score': value, 'weight': weight, 'enabled': enabled[name],
            'weighted': (value * Decimal(weight) / 100).quantize(Decimal('.01'))
            if value is not None and enabled[name] else None,
        }
    final = student_grade.final_grade if individual and student_grade else (None if individual else grade.final_grade)
    if any(values[name]['score'] is None for name in COMPONENTS if enabled[name]):
        final = None
    return values, final


def _choice(params, key, default, allowed):
    value = params.get(key) or default
    if value not in allowed:
        raise ValidationError({key: 'Choose a supported value.'})
    return value


def _integer(params, key, default=None):
    value = params.get(key)
    if value in (None, ''):
        return default
    if not str(value).isdigit() or int(value) < 1:
        raise ValidationError({key: 'Choose a positive record or page number.'})
    return int(value)


def _context(request):
    user, params = request.user, request.query_params
    if not is_admin_user(user) and getattr(user, 'role', '') != 'faculty':
        raise PermissionDenied('Grade masterlists are available to authorized faculty and administrators.')
    scope = _choice(params, 'scope', 'pit' if is_pit_lead_only(user) else 'capstone', ('pit', 'capstone'))
    year = params.get('year_level', '').strip()
    if year and year not in ('1st Year', '2nd Year', '3rd Year', '4th Year'):
        raise ValidationError({'year_level': 'Choose an academic year level.'})
    if is_pit_lead_only(user):
        assigned = (user.pit_lead_year or '').strip()
        if scope != 'pit' or (assigned and year and year != assigned):
            raise PermissionDenied('This cohort is outside your assigned PIT year.')
        year = assigned or '__unassigned__'
    semester_id = _integer(params, 'semester_id')
    semesters = Semester.objects.select_related('school_year')
    semester = get_object_or_404(semesters, pk=semester_id) if semester_id else semesters.filter(is_active=True).first()
    if not semester:
        raise ValidationError({'semester_id': 'Choose an academic period.'})
    coverage = _choice(params, 'coverage', 'assessment', ('assessment', 'semester'))
    entity = _choice(params, 'entity', 'students', ('students', 'teams'))
    detail = _choice(params, 'detail_level', 'summary', ('summary', 'full'))
    workspace = params.get('workspace', 'operations' if is_admin_user(user) or is_pit_lead_only(user) else '')
    if workspace not in ('', 'operations', 'adviser', 'instructor', 'panelist'):
        raise ValidationError({'workspace': 'Choose a supported grading workspace.'})
    return {
        'scope': scope, 'semester': semester, 'year_level': year, 'entity': entity,
        'coverage': coverage, 'detail_level': detail, 'workspace': workspace,
        'section': params.get('section', '').strip(), 'search': params.get('search', '').strip(),
        'status': _choice(params, 'status', 'all', ('all', *STATUSES)),
        'student_id': _integer(params, 'student_id'),
        'team_id': _integer(params, 'team_id'),
    }


def _assessments(request, context):
    params, semester = request.query_params, context['semester']
    if context['scope'] == 'pit':
        queryset = pit_events_for_user(request.user, semester=semester, workspace=context['workspace'])
        visible_event_ids = workspace_grades_for(request.user, context['workspace'], include_previous_projects=True).prefetch_related(None).filter(
            semester=semester, scope='pit', pit_event_config__isnull=False).values('pit_event_config_id')
        queryset = PitEventGradingConfig.objects.filter(Q(pk__in=queryset.values('pk')) | Q(pk__in=visible_event_ids))
        if context['year_level']:
            queryset = queryset.filter(year_level=context['year_level'])
        records = list(queryset.select_related('panel_rubric', 'peer_rubric').order_by('event_name', 'year_level', 'pk'))
        choices = [{'key': f'pit:{r.pk}', 'id': r.pk, 'label': r.event_name,
                    'year_level': r.year_level, 'kind': 'pit', 'config': r} for r in records]
        selected = _integer(params, 'pit_event_config_id')
        if params.get('defense_stage_id') or params.get('stage_id'):
            raise ValidationError({'defense_stage_id': 'Choose a PIT event for PIT grades.'})
    else:
        configurations = {r.defense_stage_id: r for r in StageGradingConfig.objects.filter(semester=semester)
                          .select_related('panel_rubric', 'adviser_rubric', 'peer_rubric')}
        recorded_stages = workspace_grades_for(request.user, context['workspace'], include_previous_projects=True).prefetch_related(None).filter(
            semester=semester, scope='capstone').values('defense_stage_id')
        stage_filter = Q(pk__in=configurations) | Q(pk__in=recorded_stages)
        if semester.is_active:
            stage_filter |= Q(is_active=True)
        records = list(DefenseStage.objects.filter(stage_filter).order_by('display_order', 'pk'))
        choices = [{'key': f'capstone:{r.pk}', 'id': r.pk, 'label': r.label,
                    'year_level': '', 'kind': 'capstone', 'config': configurations.get(r.pk)} for r in records]
        selected = _integer(params, 'defense_stage_id') or _integer(params, 'stage_id')
        if params.get('pit_event_config_id'):
            raise ValidationError({'pit_event_config_id': 'Choose a Capstone stage for Capstone grades.'})
    # Preserve recorded unscheduled/legacy assessments without inventing a config.
    legacy = workspace_grades_for(request.user, context['workspace'], include_previous_projects=True).prefetch_related(None).filter(
        semester=semester, scope=context['scope'], **{
            'pit_event_config__isnull' if context['scope'] == 'pit' else 'defense_stage__isnull': True})
    if context['year_level']:
        legacy = legacy.filter(team__year_level=context['year_level'])
    for record in legacy.values('stage_label', 'team__year_level').order_by('stage_label', 'team__year_level').distinct():
        label, year = record['stage_label'], record['team__year_level']
        if not any(a['label'].casefold() == label.casefold() and (context['scope'] == 'capstone' or a['year_level'] == year) for a in choices):
            choices.append({'key': f'legacy:{context["scope"]}:{year}:{label}', 'id': None,
                            'label': label, 'year_level': year, 'kind': context['scope'], 'config': None})
    if selected and not any(r['id'] == selected for r in choices):
        raise PermissionDenied('The selected assessment is not visible in this academic context.')
    label = params.get('stage_label') or params.get('stage') or params.get('pit_event')
    selected_choice = next((a for a in choices if selected and a['id'] == selected), None)
    if not selected and label:
        matches = [r for r in choices if r['label'].casefold() == label.casefold()]
        if len(matches) > 1:
            raise ValidationError({'year_level': 'Choose a PIT year or a specific event.'})
        if not matches:
            raise ValidationError({'assessment': 'This assessment is unavailable for the selected academic period.'})
        selected_choice = matches[0]
    if selected_choice is None and choices:
        selected_choice = choices[0]
    active = choices if context['coverage'] == 'semester' else [selected_choice] if selected_choice else []
    context['assessment_id'] = selected_choice['id'] if selected_choice else None
    context['assessment_key'] = selected_choice['key'] if selected_choice else ''
    context['assessment_label'] = selected_choice['label'] if selected_choice else ''
    return choices, active


def _team_context(team, semester, event=None):
    participation = next((r for r in team.term_participations.all()
                          if r.semester_id == semester.pk and r.closed_at is not None), None)
    snapshot = participation.snapshot if participation else {}
    details = next((r for r in team.roster_details.all() if event and r.event_id == event.pk), None)
    return {
        'id': team.pk, 'name': details.name if details else snapshot.get('name', team.name),
        'project_title': details.project_title if details else snapshot.get('project_title', team.project_title),
        'section': snapshot.get('section', team.section), 'year_level': snapshot.get('year_level', team.year_level),
        'adviser_name': display_name(team.adviser) if team.adviser_id and not participation else snapshot.get('adviser_name', ''),
        'historical': bool(participation),
    }


def _member_ids(team, semester):
    historical = next((r for r in team.term_participations.all()
                       if r.semester_id == semester.pk and r.closed_at is not None), None)
    if historical:
        members = historical.snapshot.get('members', [])
        return {int(m.get('student_id', m.get('id'))) if isinstance(m, dict) else int(m)
                for m in members if (not isinstance(m, dict) or m.get('student_id', m.get('id')))}
    return {m.student_id for m in team.memberships.all()} | ({team.leader_id} if team.leader_id else set())


def _sources(request, context, assessments):
    semester, scope, workspace = context['semester'], context['scope'], context['workspace']
    grades = list(workspace_grades_for(request.user, workspace, include_previous_projects=True)
                  .prefetch_related(None).select_related(None)
                  .filter(semester=semester, scope=scope)
                  .select_related('team', 'semester', 'schedule', 'schedule__rubric', 'pit_event_config__panel_rubric')
                  .order_by('team_id', '-project_version', '-pk'))
    # Superseded placeholder rows never replace a scheduled official record.
    by_assessment = defaultdict(list)
    for grade in grades:
        matches = [a for a in assessments if (scope == 'pit' and (
            (a['id'] is not None and grade.pit_event_config_id == a['id']) or not grade.pit_event_config_id
            and grade.stage_label.casefold() == a['label'].casefold()
            and grade.team.year_level == a['year_level'])) or (scope == 'capstone' and (
            (a['id'] is not None and grade.defense_stage_id == a['id']) or not grade.defense_stage_id
            and grade.stage_label.casefold() == a['label'].casefold()))]
        for assessment in matches:
            by_assessment[assessment['key']].append(grade)
    visible_grade_team_ids = {g.team_id for g in grades}
    teams = StudentTeam.objects.filter(
        Q(pk__in=workspace_teams_for(request.user, workspace).values('pk')) | Q(pk__in=visible_grade_team_ids))
    teams = teams.filter(Q(semester=semester) | Q(term_participations__semester=semester))
    teams = teams.filter(level__icontains='PIT' if scope == 'pit' else 'Capstone')
    teams = list(teams.select_related('adviser', 'leader').prefetch_related(
        'memberships__student', 'term_participations', 'roster_details').distinct().order_by('name', 'pk'))
    team_map = {t.pk: t for t in teams}
    team_ids = {}
    for assessment in assessments:
        ids = set(team_map)
        if scope == 'pit':
            from student_teams.pit_rosters import effective_ids
            ids &= set(effective_ids(semester.pk, assessment['year_level'], assessment['config']))
            ids |= {g.team_id for g in by_assessment[assessment['key']] if g.team_id in team_map}
        team_ids[assessment['key']] = ids
    records = StudentAcademicRecord.objects.filter(semester=semester, student__role='student')
    if scope == 'pit':
        records = records.filter(year_level__in=('1st Year', '2nd Year', '3rd Year'))
        if semester.label == '2nd Semester':
            records = records.exclude(year_level='3rd Year')
    else:
        records = records.filter(Q(year_level='4th Year') | (
            Q(year_level='3rd Year') if semester.label == '2nd Semester' else Q(pk__in=[])))
    if context['year_level']:
        records = records.filter(year_level=context['year_level'])
    elif scope == 'pit' and context['coverage'] == 'assessment' and assessments:
        records = records.filter(year_level=assessments[0]['year_level'])
    if not is_admin_user(request.user) and not is_pit_lead_only(request.user):
        allowed_ids = set().union(*[_member_ids(t, semester) for t in teams]) if teams else set()
        allowed = Q(student_id__in=allowed_ids)
        if workspace in ('', 'instructor'):
            from user_management.models import SectionInstructorAssignment
            for assignment in SectionInstructorAssignment.objects.filter(faculty=request.user, semester=semester, is_active=True):
                if scope == 'pit':
                    allowed |= Q(year_level=assignment.year_level, section=assignment.section)
        records = records.filter(allowed)
    sections = sorted(set(records.exclude(section='').values_list('section', flat=True)))
    if context['section']:
        records = records.filter(section=context['section'])
    if context['student_id']:
        records = records.filter(student_id=context['student_id'])
    return list(records.select_related('student').order_by('student__last_name', 'student__first_name', 'student_id')), team_map, team_ids, by_assessment, sections


def _canonical(grades):
    """Prefer a scheduled record within the latest visible project version."""
    if not grades:
        return None
    version = max(g.project_version for g in grades)
    candidates = [g for g in grades if g.project_version == version]
    return max(candidates, key=lambda g: (bool(g.schedule_id), g.pk))


def _empty_cell(assessment, team=None):
    return {'assessment_key': assessment['key'], 'assessment_id': assessment['id'], 'grade_id': None,
            'assessment_label': assessment['label'],
            'team': team, 'components': {}, 'final_grade': None, 'evaluators': [],
            'status': 'not_assessed' if team else 'no_team',
            'status_label': 'Not assessed' if team else 'No team', 'publication_status': 'pending',
            'outcome': '', 'missing_components': [], 'is_locked': False}


def _cell(grade, assessment, team, student_grade=None, *, individual=False):
    if not grade:
        return _empty_cell(assessment, team)
    components, final = component_values(grade, student_grade, individual=individual)
    missing = [name for name in COMPONENTS if components[name]['enabled'] and components[name]['score'] is None]
    status = grade.status if final is not None else ('pending' if not missing else 'awaiting_peers' if missing == ['peer'] else 'awaiting_evaluations')
    labels = {'published': 'Published', 'pending': 'Pending publication' if final is not None else 'Pending grading', 'awaiting_peers': 'Awaiting peers',
              'awaiting_evaluations': 'Awaiting evaluations'}
    return {'assessment_key': assessment['key'], 'assessment_id': assessment['id'], 'grade_id': grade.pk,
            'assessment_label': assessment['label'],
            'team': {**team, 'project_title': grade.project_title_snapshot or team['project_title']},
            'components': components, 'final_grade': final, 'status': status, 'status_label': labels.get(status, 'Pending'),
            'publication_status': grade.status, 'outcome': 'Failed (stage closure)' if grade.closed_as_failed else grade.get_verdict_display() if grade.verdict else '',
            'missing_components': missing, 'evaluators': [], 'is_locked': grade.status == 'published',
            'project_version': grade.project_version, 'attempt': grade.attempt_count}


def _evaluator_data(grades, rows, context, *, include_scores=True):
    """Batch completion metadata; hydrate actual criterion scores only on demand."""
    from grading.grades.models import TeamGrade, PanelistGradeSubmission
    from grading.grades.scoring import panelist_overall_percentage
    from grading.grades.outcome_rules import policy_for, selected_key
    submission_query = PanelistGradeSubmission.objects.select_related('panelist').annotate(criterion_count=Count('criterion_scores'))
    if include_scores:
        submission_query = submission_query.prefetch_related('criterion_scores')
    hydrated = TeamGrade.all_objects.filter(pk__in=grades).select_related('schedule__rubric').prefetch_related(
        'schedule__panel_assignments__panelist', 'schedule__guest_invitations__evaluator', 'schedule__guest_panelist_codes__evaluator',
        'student_grades', Prefetch('panelist_submissions', queryset=submission_query))
    data = {}
    for grade in hydrated:
        expected = {}
        if grade.schedule_id:
            for assignment in grade.schedule.panel_assignments.all():
                expected[(assignment.panelist_id, '')] = display_name(assignment.panelist)
            for relation in ('guest_invitations', 'guest_panelist_codes'):
                for guest in getattr(grade.schedule, relation).all():
                    if guest.is_active:
                        expected[(None, str(guest.pk))] = public_guest_name(guest.evaluator.name if guest.evaluator_id else guest.guest_name)
        submissions = [s for s in grade.panelist_submissions.all()
                       if not s.is_void and (not grade.schedule_id or s.schedule_id == grade.schedule_id)]
        if grade.schedule_id and policy_for(grade.schedule).get('per_concept'):
            key = selected_key(grade.schedule)
            submissions = [s for s in submissions if key is not None and s.concept_key == key]
        for submission in submissions:
            expected.setdefault((submission.panelist_id, str(submission.guest_code_id or '')),
                                display_name(submission.panelist) if submission.panelist_id else public_guest_name(submission.guest_name))
        data[grade.pk] = (grade, list(sorted(expected.items(), key=lambda e: (e[1].casefold(), str(e[0])))), submissions)
    for row in rows:
        for cell in row['assessments']:
            if cell['grade_id'] not in data:
                continue
            grade, expected, submissions = data[cell['grade_id']]
            individual = context['entity'] == 'students'
            target = policy_for(grade.schedule).get('target_type') or (
                grade.schedule.rubric.target_type if grade.schedule_id and grade.schedule.rubric_id else 'team')
            subjects = {row['student_id']} if individual else {s.student_id for s in grade.student_grades.all()}
            required_subjects = {None} if target == 'team' else subjects | ({None} if target == 'both' else set())
            complete_evaluators = 0
            for (pid, gid), name in expected:
                selected = [s for s in submissions if (s.panelist_id, str(s.guest_code_id or '')) == (pid, gid)
                            and (not individual or s.student_id in (None, row['student_id']))]
                submitted_subjects = {s.student_id for s in selected if s.criterion_count > 0}
                complete = bool(required_subjects) and required_subjects.issubset(submitted_subjects)
                complete_evaluators += int(complete)
                if include_scores:
                    criteria = [c for s in selected for c in s.criterion_scores.all()]
                    total = panelist_overall_percentage(criteria, maximum_attr='max_score_snapshot') if criteria else None
                    cell['evaluators'].append({'key': f'{pid or "guest"}:{gid}', 'name': name, 'score': total})
            required = len(expected)
            submitted = complete_evaluators
            cell['panel_required'], cell['panel_submitted'] = required, submitted
            if required and submitted < required and cell['components'].get('panel', {}).get('enabled'):
                cell['final_grade'] = None
                cell['status'], cell['status_label'] = 'awaiting_evaluations', 'Awaiting evaluations'
                if 'panel' not in cell['missing_components']:
                    cell['missing_components'].append('panel')


def build_masterlist(request, *, paginate=True):
    context = _context(request)
    choices, assessments = _assessments(request, context)
    records, teams, team_ids, by_assessment, sections = _sources(request, context, assessments)
    all_grades = {g.pk: g for values in by_assessment.values() for g in values}
    individual_grades = {(r.team_grade_id, r.student_id): r for r in StudentStageGrade.objects.filter(team_grade_id__in=all_grades)}
    membership = {tid: _member_ids(team, context['semester']) for tid, team in teams.items()}
    subjects = records if context['entity'] == 'students' else list(teams.values())
    rows = []
    for subject in subjects:
        individual = context['entity'] == 'students'
        student_id = subject.student_id if individual else None
        if not individual and context['team_id'] and subject.pk != context['team_id']:
            continue
        row = {'id': student_id if individual else subject.pk, 'student_id': student_id,
               'name': display_name(subject.student) if individual else subject.name,
               'student_number': subject.student.username if individual else '',
               'section': subject.section, 'year_level': subject.year_level, 'assessments': []}
        for assessment in assessments:
            if individual and context['scope'] == 'pit' and assessment['year_level'] != subject.year_level:
                continue
            candidates = [tid for tid in team_ids[assessment['key']] if tid in teams and (
                student_id in membership[tid] if individual else tid == subject.pk)]
            # Historical individual summaries are evidence even if a mutable current membership differs.
            if individual:
                candidates += [g.team_id for g in by_assessment[assessment['key']]
                               if (g.pk, student_id) in individual_grades and g.team_id in teams and g.team_id not in candidates]
            grades = [g for g in by_assessment[assessment['key']] if g.team_id in candidates
                      and (not individual or (g.pk, student_id) in individual_grades or student_id in membership[g.team_id])]
            grade = _canonical(grades)
            team = teams.get(grade.team_id) if grade else teams.get(candidates[0]) if len(candidates) == 1 else None
            if team:
                team_context = _team_context(team, context['semester'], assessment['config'] if context['scope'] == 'pit' else None)
                if context['year_level'] and team_context['year_level'] != context['year_level']:
                    continue
                if context['section'] and team_context['section'] != context['section'] and not individual:
                    continue
            else:
                team_context = None
            if not individual and not team_context:
                continue
            cell = _cell(grade, assessment, team_context, individual_grades.get((grade.pk, student_id)) if grade and individual else None, individual=individual)
            row['assessments'].append(cell)
        if not individual:
            if not row['assessments']:
                continue
            first_team = row['assessments'][0]['team']
            row.update(name=first_team['name'], section=first_team['section'], year_level=first_team['year_level'])
        team_names = {c['team']['name'] for c in row['assessments'] if c['team']}
        row['team_name'] = next(iter(team_names)) if len(team_names) == 1 else 'Varies by assessment' if team_names else 'Unassigned'
        haystack = ' '.join([row['name'], row['student_number'], row['section'], row['team_name'],
                             *[c['team']['project_title'] for c in row['assessments'] if c['team']]])
        if context['search'] and context['search'].casefold() not in haystack.casefold():
            continue
        rows.append(row)
    _evaluator_data({c['grade_id'] for r in rows for c in r['assessments'] if c['grade_id']}, rows, context, include_scores=False)
    if context['status'] != 'all':
        rows = [r for r in rows if any(c['status'] == context['status'] for c in r['assessments'])]
    ordering = request.query_params.get('ordering') or 'name'
    key = ordering.lstrip('-')
    if key not in ('name', 'student_number', 'section', 'team_name', 'final_grade', 'panel', 'adviser', 'peer', 'status'):
        raise ValidationError({'ordering': 'Choose a supported column.'})
    def sort_value(row):
        cell = row['assessments'][0] if row['assessments'] else {}
        value = cell.get('final_grade') if key == 'final_grade' else cell.get('components', {}).get(key, {}).get('score') if key in COMPONENTS else cell.get('status') if key == 'status' else row.get(key)
        return value.casefold() if isinstance(value, str) else value
    present = [r for r in rows if sort_value(r) is not None]
    missing = [r for r in rows if sort_value(r) is None]
    rows = sorted(present, key=lambda r: (sort_value(r), r['id']), reverse=ordering.startswith('-')) + sorted(missing, key=lambda r: r['id'])
    total = len(rows)
    context['evaluator_slots'] = max((cell.get('panel_required', 0) for row in rows for cell in row['assessments']), default=0)
    page = _integer(request.query_params, 'page', 1)
    page_size = _integer(request.query_params, 'page_size', 25)
    if page_size not in PAGE_SIZES:
        raise ValidationError({'page_size': 'Choose 10, 25, 50 or 100 rows.'})
    if paginate:
        page = min(page, max(1, (total + page_size - 1) // page_size))
        rows = rows[(page - 1) * page_size:page * page_size]
    if context['detail_level'] == 'full':
        _evaluator_data({c['grade_id'] for r in rows for c in r['assessments'] if c['grade_id']}, rows, context)
    serialized_context = {k: v for k, v in context.items() if k != 'semester'}
    serialized_context.update(semester_id=context['semester'].pk, academic_period=context['semester'].display_name)
    serialized_context['can_view_peer_evidence'] = can_view_peer_evidence(
        request.user, context['scope'], context['year_level'])
    clean_assessment = lambda a: {k: v for k, v in a.items() if k != 'config'}
    return {'context': serialized_context, 'rows': rows, 'total': total, 'page': page, 'page_size': page_size,
            'assessments': [clean_assessment(a) for a in assessments],
            'options': {'assessments': [clean_assessment(a) for a in choices],
                        'sections': sections,
                        'semesters': [{'id': s.pk, 'label': s.display_name} for s in Semester.objects.select_related('school_year').order_by('-school_year__label', 'label')],
                        'statuses': [{'value': s, 'label': s.replace('_', ' ').capitalize()} for s in STATUSES]},
            'generated_at': timezone.now().isoformat()}
