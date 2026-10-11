"""Scope-aware team and individual assessment selection and export assembly."""

from django.contrib.auth import get_user_model
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.scopes import grade_records_for, is_admin_user
from reports.export_formatters import handle_export_or_preview
from reports.grade_summary import assessment_scope_label, grade_outcome_label, student_assessment_scores
from reports.generators.team_grade_report import generate_team_grades_pdf
from reports.generators.individual_grade_report import generate_individual_grades_pdf


def assessment_candidates(request):
    """Return selection contexts from assessments, including previous academic periods."""
    queryset = grade_records_for(request.user).prefetch_related(None).prefetch_related('team__memberships__student')
    scope = request.query_params.get('scope', '')
    if scope in ('capstone', 'pit'):
        queryset = queryset.filter(scope=scope)
    elif scope not in ('', 'all'):
        raise ValidationError({'scope': 'Select Capstone, PIT, or all scopes.'})
    if request.query_params.get('semester_id'):
        queryset = queryset.filter(semester_id=request.query_params['semester_id'])
    teams, students, contexts = {}, {}, {}
    seen_contexts = set()
    for grade in queryset:
        team = grade.team
        team_data = teams.setdefault(team.pk, {
            'id': team.pk, 'name': team.name, 'project_title': grade.project_title_snapshot or team.project_title,
            'section': team.section, 'year_level': team.year_level, 'level': team.level,
            'semester_id': grade.semester_id, 'scope': grade.scope, 'scopes': [],
            'leader_name': team.leader.get_full_name() if team.leader else 'Unassigned',
            'adviser_name': team.adviser.get_full_name() if team.adviser else 'Unassigned',
        })
        if grade.scope not in team_data['scopes']:
            team_data['scopes'].append(grade.scope)
        context_key = (team.pk, grade.scope, grade.semester_id)
        if context_key in seen_contexts:
            continue
        seen_contexts.add(context_key)
        members = [membership.student for membership in team.memberships.all()]
        if team.leader and all(member.pk != team.leader_id for member in members):
            members.insert(0, team.leader)
        for student in members:
            students[student.pk] = {
                'id': student.pk, 'username': student.username,
                'name': student.get_full_name() or student.username,
                'first_name': student.first_name, 'last_name': student.last_name,
            }
            context_team = {**team_data, 'scope': grade.scope, 'semester_id': grade.semester_id}
            meta = contexts.setdefault(str(student.pk), {'student': students[student.pk], 'contexts': []})
            meta['contexts'].append({
                'team': context_team, 'section': team.section or team.year_level,
                'isLeader': student.pk == team.leader_id,
            })
    for team in teams.values():
        if len(team['scopes']) > 1:
            team['scope'] = 'mixed'
    return Response({'teams': list(teams.values()), 'students': list(students.values()), 'student_contexts': contexts})


def _select_assessments(queryset, params):
    scope = params.get('scope', '').strip()
    if scope not in ('', 'all', 'capstone', 'pit'):
        raise ValidationError({'scope': 'Select Capstone, PIT, or all scopes.'})
    if scope in ('capstone', 'pit'):
        queryset = queryset.filter(scope=scope)
    if params.get('semester_id'):
        queryset = queryset.filter(semester_id=params['semester_id'])
    if params.get('team_id'):
        queryset = queryset.filter(team_id=params['team_id'])
    available = list(queryset)
    if not available:
        raise NotFound('No assessments match the selected semester and scope.')

    coverage = params.get('coverage', 'latest')
    if coverage not in ('latest', 'all', 'specific'):
        raise ValidationError({'coverage': 'Select the latest, a specific assessment, or all assessments.'})
    selected = queryset
    grade_id = params.get('grade_id')
    stage = params.get('stage_id') or params.get('stage')
    event = params.get('pit_event_config_id') or params.get('pit_event_id') or params.get('pit_event')
    if grade_id:
        records = [get_object_or_404(selected, pk=grade_id)]
    elif stage and stage != 'all':
        selected = selected.filter(defense_stage_id=stage) if str(stage).isdigit() else selected.filter(stage_label=stage, scope='capstone')
        records = list(selected)
    elif event and event != 'all':
        selected = selected.filter(pit_event_config_id=event) if str(event).isdigit() else selected.filter(stage_label=event, scope='pit')
        records = list(selected)
    elif coverage == 'all':
        records = available
    elif coverage == 'specific':
        raise ValidationError({'grade_id': 'Select a recorded stage or event.'})
    else:
        records = [max(available, key=lambda grade: (grade.created_at, grade.pk))]
    if not records:
        raise NotFound('No assessment exists for the selected stage or event.')

    def order(grade):
        return (
            grade.semester_id, 0 if grade.is_capstone else 1,
            grade.defense_stage.display_order if grade.defense_stage else 999,
            grade.stage_label.casefold(), grade.pk,
        )
    return sorted(records, key=order), sorted(available, key=order)


def _student_grade(grade, student):
    return next((item for item in grade.student_grades.all() if item.student_id == student.pk), None)


def _percent(value):
    return f'{value:.2f}%' if value is not None else 'Pending'


def _period(grade):
    return f'{grade.semester.school_year.label} {grade.semester.label}'


def _context(grade):
    return {
        'scope': assessment_scope_label(grade), 'assessment': grade.stage_label,
        'academic_period': _period(grade), 'team_name': grade.team.name,
    }


def _team_rows(grade):
    submissions = list(grade.panelist_submissions.all().select_related('panelist').prefetch_related('criterion_scores'))
    panelists = {}
    for submission in submissions:
        key = (submission.panelist_id, submission.guest_code_id)
        panelists.setdefault(key, submission.panelist.get_full_name() if submission.panelist else submission.guest_name)
    members = []
    if grade.team.leader:
        members.append(grade.team.leader)
    members.extend(member for member in grade.team.members.all() if member.pk != grade.team.leader_id)
    rows = []
    for index, student in enumerate(members, start=1):
        values = student_assessment_scores(grade, _student_grade(grade, student))
        row = {
            **_context(grade), 'no': str(index),
            'name': student.get_full_name() or student.username,
            'panel_avg': _percent(values['panel']), 'panel_weight': f'{grade.panel_weight}%',
            'adviser_rating': _percent(values['adviser']) if grade.is_capstone and grade.adviser_weight else 'N/A',
            'adviser_weight': f'{grade.adviser_weight}%',
            'peer_rating': _percent(values['peer']), 'peer_weight': f'{grade.peer_weight}%',
            'final_grade': _percent(values['final']), 'grade_status': values['status'],
            'outcome': grade_outcome_label(grade),
            'panel_weighted': _percent(values['panel_weighted']),
            'adviser_weighted': _percent(values['adviser_weighted']) if grade.is_capstone and grade.adviser_weight else 'N/A',
            'peer_weighted': _percent(values['peer_weighted']),
            'total': _percent(values['final']),
            'panel_evaluators': '; '.join(f'Panel {number}: {name or "Guest panelist"}' for number, name in enumerate(panelists.values(), start=1)),
        }
        for number, (key, name) in enumerate(panelists.items(), start=1):
            matching = [item for item in submissions if (item.panelist_id, item.guest_code_id) == key and item.student_id in (None, student.pk)]
            criteria = [score for item in matching for score in item.criterion_scores.all()]
            from grading.grades.services import panelist_percentage_from_criterion_scores
            row[f'panel_{number}'] = _percent(panelist_percentage_from_criterion_scores(criteria))
            row[f'panel_{number}_label'] = name or 'Guest panelist'
        rows.append(row)
    return rows


def _individual_rows(grade, student):
    values = student_assessment_scores(grade, _student_grade(grade, student))
    components = [('Panel Evaluation', 'panel', grade.panel_weight)]
    if grade.is_capstone and grade.adviser_weight > 0:
        components.append(('Adviser Evaluation', 'adviser', grade.adviser_weight))
    components.append(('Peer Evaluation', 'peer', grade.peer_weight))
    rows = [{
        **_context(grade), 'component': label, 'weight': f'{weight}%',
        'score': _percent(values[key]), 'remarks': 'Recorded assessment rating',
    } for label, key, weight in components]
    rows.append({
        **_context(grade), 'component': 'Final Individual Grade', 'weight': '100%',
        'score': _percent(values['final']), 'remarks': values['status'],
    })
    rows.append({
        **_context(grade), 'component': 'Defense Outcome', 'weight': '-',
        'score': grade_outcome_label(grade), 'remarks': 'Recorded defense verdict or grade threshold',
    })
    return rows


def export_assessment_report(request, *, team_id=None, student_id=None, include_signatures=False, signatories=None):
    student = get_object_or_404(get_user_model(), pk=student_id, role='student') if student_id is not None else None
    visible = grade_records_for(request.user)
    if student is not None:
        visible = visible.filter(Q(team__leader=student) | Q(team__memberships__student=student)).distinct()
    else:
        visible = visible.filter(team_id=team_id)
    if not visible.exists():
        if student is not None and (is_admin_user(request.user) or request.user.pk == student.pk):
            raise NotFound('No evaluation records found for this student.')
        raise PermissionDenied('You do not have permission to view these assessment records.')
    records, available = _select_assessments(visible, request.query_params)
    name = (student.get_full_name() or student.username) if student else records[0].team.name
    kind = 'Individual Grade Audit' if student else 'Team Grade Report'
    scopes = {assessment_scope_label(grade) for grade in records}
    scope_label = next(iter(scopes)) if len(scopes) == 1 else 'Capstone & PIT'
    specific = any(request.query_params.get(key) for key in ('grade_id', 'stage_id', 'stage', 'pit_event', 'pit_event_id', 'pit_event_config_id'))
    coverage_label = 'All recorded stages / events' if request.query_params.get('coverage') == 'all' and not specific else records[0].stage_label
    title = f'{scope_label} {kind} - {name}'
    generated_by = request.user.get_full_name() or request.user.username
    metadata = [
        {'label': 'Student' if student else 'Team', 'value': name},
        {'label': 'Academic Scope', 'value': scope_label},
        {'label': 'Academic Period', 'value': '; '.join(dict.fromkeys(_period(grade) for grade in records))},
        {'label': 'Coverage', 'value': coverage_label},
        {'label': 'Assessment Records', 'value': str(len(records))},
    ]
    context_columns = [
        {'key': 'scope', 'label': 'Scope'}, {'key': 'assessment', 'label': 'Stage / Event'},
        {'key': 'academic_period', 'label': 'Academic Period'}, {'key': 'team_name', 'label': 'Team'},
    ]
    if student:
        columns = context_columns + [
            {'key': 'component', 'label': 'Grade Component'}, {'key': 'weight', 'label': 'Weight'},
            {'key': 'score', 'label': 'Score / Outcome'}, {'key': 'remarks', 'label': 'Status / Source'},
        ]
        row_builder = lambda grade: _individual_rows(grade, student)
        pdf_generator = lambda: generate_individual_grades_pdf(
            student, records, generated_by, signatories=signatories, include_signatures=include_signatures, coverage_label=coverage_label,
        )
    else:
        columns = context_columns + [
            {'key': 'no', 'label': 'No.'}, {'key': 'name', 'label': 'Student'},
            {'key': 'panel_avg', 'label': 'Panel Score'}, {'key': 'panel_weight', 'label': 'Panel Weight'},
            {'key': 'adviser_rating', 'label': 'Adviser Score'}, {'key': 'adviser_weight', 'label': 'Adviser Weight'},
            {'key': 'peer_rating', 'label': 'Peer Score'}, {'key': 'peer_weight', 'label': 'Peer Weight'},
            {'key': 'final_grade', 'label': 'Final Grade'}, {'key': 'grade_status', 'label': 'Grade Status'},
            {'key': 'outcome', 'label': 'Defense Outcome'},
            {'key': 'panel_weighted', 'label': 'Weighted Panel'},
            {'key': 'adviser_weighted', 'label': 'Weighted Adviser'},
            {'key': 'peer_weighted', 'label': 'Weighted Peer'},
            {'key': 'total', 'label': 'Total'},
            {'key': 'panel_evaluators', 'label': 'Panel Evaluators'},
        ]
        row_builder = _team_rows
        pdf_generator = lambda: generate_team_grades_pdf(
            records, generated_by, signatories=signatories, include_signatures=include_signatures, coverage_label=coverage_label,
        )
    percentage_keys = {
        'weight', 'score', 'panel_avg', 'panel_weight', 'adviser_rating', 'adviser_weight',
        'peer_rating', 'peer_weight', 'final_grade', 'panel_weighted', 'adviser_weighted',
        'peer_weighted', 'total',
    }
    for column in columns:
        if column['key'] in percentage_keys:
            column['type'] = 'percentage'
        elif column['key'] == 'no':
            column['type'] = 'integer'
    sections = [{
        'title': f'{assessment_scope_label(grade)} - {grade.stage_label} - {grade.team.name}',
        'columns': columns, 'rows': row_builder(grade),
    } for grade in records]
    rows = [row for section in sections for row in section['rows']]
    if student is None:
        panel_keys = sorted({key for row in rows for key in row if key.startswith('panel_') and key[6:].isdigit()}, key=lambda key: int(key[6:]))
        columns[6:6] = [{
            'key': key,
            'label': f'Panel {key[6:]} ({rows[0].get(key + "_label", "Evaluator")})' if len(records) == 1 else f'Panel {key[6:]} Score',
        } for key in panel_keys]
    export_format = request.query_params.get('export_format') or request.query_params.get('format')
    if export_format not in ('json', 'preview', 'data'):
        log_high_impact_action(
            category='compliance',
            action='report.generate_individual_grade' if student else 'report.generate_team_grade',
            target=student or records[0].team, target_id=student.pk if student else records[0].team_id,
            reason=f'Exported {title} ({coverage_label})', request=request,
            new_values={'grade_ids': [grade.pk for grade in records], 'scope': scope_label, 'coverage': coverage_label},
        )
    filename = 'DefenSYS_' + '_'.join(''.join(c for c in value if c.isalnum() or c in ' -_').strip().replace(' ', '_') for value in (scope_label, kind, name, coverage_label))
    from reports.assessment_workbooks import assessment_document_sheets
    document_sheets = assessment_document_sheets(records, student=student, team_rows=_team_rows, coverage=coverage_label) if (export_format or '').lower() in ('json', 'preview', 'data', 'xlsx', 'excel', 'sheet') else None
    response = handle_export_or_preview(
        export_format=export_format, title=title,
        subtitle=f'{scope_label} - {coverage_label} - {metadata[2]["value"]}',
        summary_kpis=[{'label': 'Assessment Records', 'value': str(len(records))}],
        metadata=metadata, columns=columns, rows=rows, sections=sections,
        filename=filename, generated_by=generated_by, pdf_generator_func=pdf_generator,
        include_signatures=include_signatures, signatories=signatories, document_sheets=document_sheets,
    )
    if hasattr(response, 'data'):
        response.data['assessments'] = [{
            'id': grade.pk, 'scope': grade.scope, 'stage_label': grade.stage_label,
            'team_id': grade.team_id, 'team_name': grade.team.name,
            'semester_id': grade.semester_id, 'academic_period': _period(grade),
        } for grade in available]
    return response
