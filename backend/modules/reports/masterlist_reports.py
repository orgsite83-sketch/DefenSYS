"""Exports of the same authorized entity rows used by Evaluation & Grades."""
from types import SimpleNamespace

from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from authentication_access_control.audit import log_high_impact_action
from grading.grades.masterlist import build_masterlist, display_name
from grading.grades.models import TeamGrade
from grading.grades.evaluator_identity import public_guest_name, public_evaluation_text
from grading.grades.outcome_rules import policy_for, selected_key
from reports.catalog_reports import column, dataset, render_pdf
from reports.export_formatters import handle_export_or_preview
from reports.views import _parse_signature_params


def _percentage(value, enabled=True):
    return value if value is not None and enabled else 'Pending' if enabled else 'N/A'


def report_dataset(payload):
    context = payload['context']
    students = context['entity'] == 'students'
    matrix = context['coverage'] == 'semester'
    title = 'Student Grade Masterlist' if students else 'Team Grade Masterlist'
    if matrix:
        title = 'Semester ' + title
    columns = [column('name', 'Student' if students else 'Team', 28, freeze=True)]
    if students:
        columns += [column('student_number', 'Student ID', 18, freeze=True), column('team', 'Team', 25)]
    columns += [column('section', 'Section', 15)]
    if matrix:
        columns += [column(a['key'], a['label'], 25, type='percentage') for a in payload['assessments']]
    else:
        if not students:
            columns += [column('project', 'Project Title', 48), column('adviser', 'Adviser', 25)]
        for component in ('panel', 'adviser', 'peer'):
            if component == 'adviser' and context['scope'] == 'pit':
                continue
            columns.append(column(component, component.title() + ' Score', 17, type='percentage'))
            if context['detail_level'] == 'full':
                columns += [column(component + '_weight', component.title() + ' Weight', 16, type='percentage'),
                            column(component + '_weighted', component.title() + ' Weighted', 18, type='number')]
        if context['detail_level'] == 'full':
            count = max((len(c['evaluators']) for r in payload['rows'] for c in r['assessments']), default=0)
            for index in range(count):
                columns += [column(f'evaluator_{index}', f'Panel {index + 1} Evaluator', 26),
                            column(f'panel_{index}', f'Panel {index + 1} Score', 18, type='percentage')]
        columns += [column('final', 'Individual Final' if students else 'Team Final', 18, type='percentage'),
                    column('status', 'Grading Status', 24), column('publication', 'Publication', 18), column('outcome', 'Defense Outcome', 25)]
    rows = []
    for source in payload['rows']:
        result = {'name': source['name'], 'student_number': source['student_number'],
                  'team': source['team_name'], 'section': source['section']}
        for cell in source['assessments']:
            if matrix:
                result[cell['assessment_key']] = _percentage(cell['final_grade'])
                continue
            team = cell['team'] or {}
            result.update(project=team.get('project_title', ''), adviser=team.get('adviser_name') or 'Unassigned',
                          final=_percentage(cell['final_grade']), status=cell['status_label'],
                          publication=cell['publication_status'].replace('_', ' ').title(), outcome=cell['outcome'])
            for component, values in cell['components'].items():
                result[component] = _percentage(values['score'], values['enabled'])
                result[component + '_weight'] = values['weight']
                result[component + '_weighted'] = _percentage(values['weighted'], values['enabled'])
            for index, evaluator in enumerate(cell['evaluators']):
                result[f'evaluator_{index}'] = evaluator['name']
                result[f'panel_{index}'] = _percentage(evaluator['score'])
        rows.append(result)
    return dataset(title, columns, rows)


def detail_sheets(payload):
    if payload['context']['detail_level'] != 'full':
        return []
    subjects = {}
    for row in payload['rows']:
        for cell in row['assessments']:
            if cell['grade_id']:
                subjects.setdefault(cell['grade_id'], []).append((row, cell))
    grades = TeamGrade.all_objects.filter(pk__in=subjects).select_related(
        'schedule', 'team', 'semester', 'pit_event_config').prefetch_related(
        'panelist_submissions__panelist', 'panelist_submissions__student',
        'panelist_submissions__criterion_scores', 'peer_evaluation_submissions__evaluator',
        'peer_evaluation_submissions__evaluatee', 'student_grades__student', 'breakdowns')
    sheets = {name: [] for name in ('Grade calculation', 'Panel criteria', 'Peer ratings', 'Feedback', 'Member grades')}
    for grade in grades:
        if grade.schedule_id and policy_for(grade.schedule).get('per_concept'):
            official_concept = selected_key(grade.schedule)
        else:
            official_concept = ''
        for row, cell in subjects[grade.pk]:
            identity = {'grade_id': grade.pk, 'assessment': grade.stage_label, 'scope': grade.scope,
                        'period': payload['context']['academic_period'], 'subject': row['name'],
                        'student_id': row['student_number'], 'team': (cell['team'] or {}).get('name', '')}
            for component, values in cell['components'].items():
                sheets['Grade calculation'].append({**identity, 'component': component.title(),
                    'score': _percentage(values['score'], values['enabled']), 'weight': values['weight'],
                    'weighted': _percentage(values['weighted'], values['enabled']), 'final': _percentage(cell['final_grade']),
                    'status': cell['status_label']})
            for submission in grade.panelist_submissions.all():
                if submission.is_void or (grade.schedule_id and submission.schedule_id != grade.schedule_id):
                    continue
                if official_concept is None or submission.concept_key != official_concept:
                    continue
                if row['student_id'] and submission.student_id not in (None, row['student_id']):
                    continue
                evaluator = display_name(submission.panelist) if submission.panelist_id else public_guest_name(submission.guest_name)
                for criterion in submission.criterion_scores.all():
                    sheets['Panel criteria'].append({**identity, 'evaluator': evaluator, 'component': 'Panel',
                        'recipient': display_name(submission.student) if submission.student_id else 'Team',
                        'criterion': criterion.criterion_name_snapshot, 'score': criterion.score,
                        'max': criterion.max_score_snapshot, 'criterion_weight': criterion.weight_snapshot})
                sheets['Feedback'].append({**identity, 'evaluator': evaluator, 'component': 'Panel', 'feedback': public_evaluation_text(submission.remarks)})
            for breakdown in grade.breakdowns.all():
                if breakdown.is_void:
                    continue
                if breakdown.evaluation_type != 'adviser' or (row['student_id'] and breakdown.student_id not in (None, row['student_id'])):
                    continue
                sheets['Panel criteria'].append({**identity, 'evaluator': 'Recorded adviser evaluation', 'component': 'Adviser',
                    'recipient': row['name'], 'criterion': breakdown.criterion_name, 'score': breakdown.score,
                    'max': breakdown.max_score, 'criterion_weight': breakdown.weight_snapshot})
                if breakdown.remarks:
                    sheets['Feedback'].append({**identity, 'evaluator': 'Adviser', 'component': 'Adviser', 'feedback': breakdown.remarks})
            peers = grade.peer_evaluation_submissions.all() if payload['context']['can_view_peer_evidence'] else []
            for peer in peers:
                if peer.attempt_number != grade.attempt_count or peer.is_void:
                    continue
                if row['student_id'] and peer.evaluatee_id != row['student_id']:
                    continue
                for criterion in peer.breakdown or [{}]:
                    sheets['Peer ratings'].append({**identity, 'evaluator': display_name(peer.evaluator),
                        'recipient': display_name(peer.evaluatee), 'rating_type': 'Self' if peer.evaluator_id == peer.evaluatee_id else 'Teammate',
                        'criterion': criterion.get('criteriaName', criterion.get('criterion_name', 'Recorded rating')),
                        'score': criterion.get('score', peer.total_score), 'max': criterion.get('max', peer.max_score),
                        'criterion_weight': criterion.get('weight_snapshot'), 'total': peer.weighted_score})
            if not payload['context']['can_view_peer_evidence']:
                aggregates = [student for student in grade.student_grades.all() if not row['student_id'] or student.student_id == row['student_id']]
                for student in aggregates:
                    sheets['Peer ratings'].append({**identity, 'evaluator': 'Aggregate only',
                        'recipient': display_name(student.student), 'rating_type': 'Recorded average',
                        'criterion': 'Recorded peer average', 'score': _percentage(student.peer_score),
                        'max': 100, 'criterion_weight': None, 'total': _percentage(student.peer_score)})
            if payload['context']['entity'] == 'teams':
                for student in grade.student_grades.all():
                    sheets['Member grades'].append({**identity, 'student_id': student.student.username,
                        'recipient': display_name(student.student), 'panel': student.panel_score,
                        'adviser': student.adviser_score, 'peer': student.peer_score, 'final': _percentage(student.final_grade)})
    common = [column('grade_id', 'Assessment Record ID', 18, type='integer'), column('period', 'Academic Period', 28),
              column('scope', 'Scope', 14), column('assessment', 'Assessment', 28), column('subject', 'Subject', 28),
              column('student_id', 'Student ID', 18), column('team', 'Team', 25)]
    fields = {
        'Grade calculation': [('component', 'Component'), ('score', 'Score', 'percentage'), ('weight', 'Weight', 'percentage'), ('weighted', 'Weighted', 'number'), ('final', 'Final', 'percentage'), ('status', 'Status')],
        'Panel criteria': [('component', 'Component'), ('evaluator', 'Evaluator'), ('recipient', 'Recipient'), ('criterion', 'Criterion'), ('score', 'Score', 'number'), ('max', 'Maximum', 'number'), ('criterion_weight', 'Criterion Weight', 'number')],
        'Peer ratings': [('recipient', 'Recipient'), ('evaluator', 'Evaluator'), ('rating_type', 'Rating Type'), ('criterion', 'Criterion'), ('score', 'Score', 'number'), ('max', 'Maximum', 'number'), ('criterion_weight', 'Criterion Weight', 'number'), ('total', 'Received Rating', 'percentage')],
        'Feedback': [('component', 'Component'), ('evaluator', 'Evaluator'), ('feedback', 'Feedback')],
        'Member grades': [('recipient', 'Student'), ('panel', 'Panel', 'percentage'), ('adviser', 'Adviser', 'percentage'), ('peer', 'Peer', 'percentage'), ('final', 'Individual Final', 'percentage')],
    }
    return [{'name': name, 'title': name, 'columns': common + [column(key, label, 32,
                **({'type': kind[0]} if kind else {})) for key, label, *kind in fields[name]], 'rows': rows}
            for name, rows in sheets.items() if name != 'Member grades' or payload['context']['entity'] == 'teams']


class GradeMasterlistReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, entity='students'):
        params = request.query_params.copy()
        params['entity'] = entity
        payload = build_masterlist(SimpleNamespace(user=request.user, query_params=params), paginate=False)
        spec = report_dataset(payload)
        extra = detail_sheets(payload)
        generated_by = display_name(request.user)
        metadata = [{'label': 'Academic Period', 'value': payload['context']['academic_period']},
                    {'label': 'Scope', 'value': payload['context']['scope'].upper()},
                    {'label': 'Coverage', 'value': payload['context']['coverage']},
                    {'label': 'Records', 'value': payload['total']},
                    {'label': 'Generated at', 'value': timezone.localtime().strftime('%b %d, %Y %I:%M %p')},
                    {'label': 'Filters', 'value': '; '.join(f'{key}: {value}' for key, value in params.items()
                        if value and key in ('year_level', 'section', 'search', 'status', 'detail_level'))}]
        export_format = request.query_params.get('export_format') or request.query_params.get('format') or 'pdf'
        preview = export_format in ('json', 'preview', 'data')
        if preview:
            if len(spec['rows']) > 100 or any(len(sheet['rows']) > 200 for sheet in extra):
                metadata.append({'label': 'Preview Coverage', 'value': 'Preview shows at most 100 summary and 200 supporting rows per sheet. Downloads include all matching records.'})
            spec = {**spec, 'rows': spec['rows'][:100]}
            extra = [{**sheet, 'rows': sheet['rows'][:200]} for sheet in extra]
        include_signatures, signatories = _parse_signature_params(request)
        pdf_spec = {**spec, 'sections': [{'title': sheet['title'], 'columns': sheet['columns'], 'rows': sheet['rows']} for sheet in extra]}
        if not preview:
            log_high_impact_action(category='compliance', action='report.generate_grade_masterlist',
                target=request.user, target_id=request.user.pk, request=request,
                reason=f'Exported {spec["title"]}', new_values={'scope': payload['context']['scope'],
                    'year_level': payload['context']['year_level'], 'semester_id': payload['context']['semester_id'],
                    'entity': entity, 'records': payload['total']})
        response = handle_export_or_preview(export_format, spec['title'], 'Recorded assessment results',
            [{'label': entity.title(), 'value': str(payload['total'])}], metadata, spec['columns'], spec['rows'],
            'DefenSYS_' + spec['title'].replace(' ', '_'),
            lambda: render_pdf(pdf_spec, metadata, generated_by, include_signatures, signatories),
            generated_by=generated_by, include_signatures=include_signatures, signatories=signatories, extra_sheets=extra)
        if hasattr(response, 'data'):
            response.data.update(total_rows=payload['total'], preview_limited=payload['total'] > len(spec['rows']))
        return response
