"""Compact report sheets for individual/team assessments and supporting records."""
from reports.grade_summary import assessment_scope_label, grade_outcome_label, student_assessment_scores, assessment_panel_submissions


def _name(user):
    return (user.get_full_name() or user.username) if user else 'Unassigned'


def _percent(value):
    return f'{value:.2f}%' if value is not None else 'Pending'


def _points(value):
    return str(value).removesuffix('%') if value is not None else 'Pending'


def _column(key, label, width=14, kind=None):
    text_keys = {'name', 'component', 'source', 'status', 'evaluator', 'candidate', 'criterion', 'remarks', 'outcome'}
    result = {'key': key, 'label': label, 'width': width, 'align': 'left' if key in text_keys else 'center'}
    if kind:
        result['type'] = kind
        if kind == 'number':
            result['number_format'] = '0.00'
    return result


def _supporting_name(label, kind):
    suffix = ' - ' + kind
    return label[:31 - len(suffix)] + suffix


def assessment_document_sheets(records, *, student, team_rows, coverage):
    sheets = []
    for grade in records:
        team = grade.team
        members = [team.leader] if team.leader else []
        members.extend(member for member in team.members.all() if member.pk != team.leader_id)
        student_grade = next((item for item in grade.student_grades.all() if student and item.student_id == student.pk), None)
        scope = assessment_scope_label(grade)
        subtitle = f'Official Assessment Record - {grade.stage_label}'
        metadata = [
            {'label': 'Project Title', 'value': grade.project_title_snapshot or team.project_title or team.name},
            {'label': 'Academic Scope', 'value': scope}, {'label': 'Report Coverage', 'value': coverage},
            {'label': 'Student Team & Section', 'value': f'{team.name} | {team.section or team.year_level}'},
            {'label': 'Academic Term / Semester', 'value': grade.semester.display_name},
            {'label': 'Defense Stage' if grade.is_capstone else 'PIT Event', 'value': grade.stage_label + (f' (Attempt #{grade.attempt_count})' if grade.attempt_count > 1 else '')},
            {'label': 'Project Adviser', 'value': _name(team.adviser)},
            {'label': 'Defense Outcome', 'value': grade_outcome_label(grade)},
        ]
        if grade.revision_deadline:
            metadata.append({'label': 'Revision Deadline', 'value': grade.revision_deadline.isoformat()})
        if student:
            metadata.insert(0, {'label': 'Student Candidate', 'value': f'{_name(student)} ({student.username})'})
            values = student_assessment_scores(grade, student_grade)
            columns = [_column('component', 'Assessment Component', 32), _column('weight', 'Weight', 10, 'percentage'),
                       _column('score', 'Earned Score', 14, 'percentage'), _column('weighted', 'Weighted Contribution', 18, 'number'),
                       _column('source', 'Evaluation Remarks / Source', 36)]
            components = [('Panel Defense Evaluation', 'panel', 'Composite panel rubric score')]
            if grade.is_capstone and grade.adviser_weight:
                components.append(('Project Adviser Grade', 'adviser', f'Assessed by {_name(team.adviser)}'))
            components.append(('Individual Peer Evaluation', 'peer', 'Internal peer rubric average'))
            rows = [{'component': label, 'weight': getattr(grade, key + '_weight'), 'score': _percent(values[key]),
                     'weighted': values[key + '_weighted'] if values[key + '_weighted'] is not None else 'Pending', 'source': source}
                    for label, key, source in components]
            rows.append({'component': 'TOTAL OFFICIAL GRADE', 'weight': 100, 'score': '',
                         'weighted': values['final'] if values['final'] is not None else 'Pending', 'source': values['status']})
            section = 'Individual Academic Grade Breakdown'
            title = f'{scope} Individual Grade Audit Report - {_name(student)}'
        else:
            metadata.insert(6, {'label': 'Proponents / Members', 'value': ', '.join(_name(member) + (' (Leader)' if member.pk == team.leader_id else '') for member in members)})
            rows = team_rows(grade)
            panel_keys = sorted({key for row in rows for key in row if key.startswith('panel_') and key[6:].isdigit()}, key=lambda key: int(key[6:]))
            columns = [_column('no', 'No.', 5, 'integer'), _column('name', 'Names', 27)]
            columns.extend(_column(key, f'Panel {key[6:]}\n{rows[0].get(key + "_label", "Evaluator")}', 17, 'percentage') for key in panel_keys)
            columns += [_column('panel_avg', 'Panel Average', 14, 'percentage'),
                        _column('panel_weighted', f'Panel Contribution\n({grade.panel_weight}%)', 15, 'number')]
            if grade.is_capstone and grade.adviser_weight:
                columns += [_column('adviser_rating', 'Adviser Rating', 14, 'percentage'),
                            _column('adviser_weighted', f'Adviser Contribution\n({grade.adviser_weight}%)', 15, 'number')]
            columns += [_column('peer_rating', 'Peer Rating', 14, 'percentage'),
                        _column('peer_weighted', f'Peer Contribution\n({grade.peer_weight}%)', 15, 'number'),
                        _column('total', 'Total Score', 14, 'number'), _column('status', 'Grade Status', 20)]
            for row, member in zip(rows, members):
                row['name'] += '\n(Leader)' if member.pk == team.leader_id else ''
                row['status'] = row['grade_status']
                for key in ('panel_weighted', 'adviser_weighted', 'peer_weighted', 'total'):
                    row[key] = _points(row[key])
            title = f'{scope} Team Grade Report - {team.name}'
            section = 'Master Student Grade Sheet'
        name = grade.stage_label or 'Assessment'
        sheets.append({'name': name, 'title': title, 'subtitle': subtitle, 'metadata': metadata,
                       'section_title': section, 'columns': columns, 'rows': rows})

        submissions = list(assessment_panel_submissions(grade, official=False))
        if student:
            submissions = [item for item in submissions if item.student_id in (None, student.pk)]
        criteria, feedback = [], []
        for submission in submissions:
            evaluator = _name(submission.panelist) if submission.panelist else submission.guest_name or 'Guest panelist'
            candidate = _name(submission.student) if submission.student else 'Team assessment'
            if submission.concept_key:
                candidate = f'{submission.concept_key.upper()} | {candidate}'
            for score in submission.criterion_scores.all():
                criteria.append({'evaluator': evaluator, 'candidate': candidate, 'criterion': score.criterion_name_snapshot,
                                 'score': score.score, 'max': score.max_score_snapshot, 'normalized': score.normalized_score})
            if submission.remarks and submission.remarks.strip():
                for part, offset in enumerate(range(0, len(submission.remarks), 1000), 1):
                    feedback.append({'evaluator': evaluator, 'candidate': candidate, 'part': part, 'remarks': submission.remarks[offset:offset + 1000]})
        if criteria:
            sheets.append({'name': _supporting_name(name, 'Criteria'), 'title': title, 'subtitle': 'Panelist Criteria Assessment', 'metadata': metadata,
                           'section_title': 'Individual Rubric Breakdown & Panelist Criteria Assessment', 'signatures': False,
                           'columns': [_column('evaluator', 'Panelist', 28), _column('candidate', 'Student / Target', 28),
                                       _column('criterion', 'Criterion / Assessment Skill', 34), _column('score', 'Score', 12),
                                       _column('max', 'Maximum Points', 12), _column('normalized', 'Normalized Score', 16, 'percentage')], 'rows': criteria})
        if grade.verdict_remarks:
            feedback.insert(0, {'evaluator': 'Defense Panel', 'candidate': 'Team assessment', 'part': 1, 'remarks': grade.verdict_remarks[:1000]})
            for part, offset in enumerate(range(1000, len(grade.verdict_remarks), 1000), 2):
                feedback.append({'evaluator': 'Defense Panel', 'candidate': 'Team assessment', 'part': part, 'remarks': grade.verdict_remarks[offset:offset + 1000]})
        if feedback:
            sheets.append({'name': _supporting_name(name, 'Feedback'), 'title': title, 'subtitle': 'Defense Feedback & Instructions', 'metadata': metadata,
                           'section_title': 'Panelist Defense Feedback & Direct Observations', 'signatures': False,
                           'columns': [_column('evaluator', 'Evaluator / Source', 26), _column('candidate', 'Student / Target', 26),
                                       _column('part', 'Text Part', 10), _column('remarks', 'Remarks & Recommendations', 70)], 'rows': feedback})
        histories = list(grade.attempt_history.select_related('schedule').order_by('attempt_number'))
        if histories:
            history_rows = []
            for attempt in histories:
                remarks = attempt.verdict_remarks or ''
                for part, offset in enumerate(range(0, max(1, len(remarks)), 1000), 1):
                    history_rows.append({'attempt': attempt.attempt_number, 'date': attempt.schedule.scheduled_date if attempt.schedule else '', 'panel': _percent(attempt.panel_score),
                                         'final': _percent(attempt.final_grade), 'outcome': dict(grade.VERDICT_CHOICES).get(attempt.verdict, attempt.verdict.replace('_', ' ').title()) if attempt.verdict else 'Not recorded',
                                         'part': part, 'remarks': remarks[offset:offset + 1000]})
            sheets.append({'name': _supporting_name(name, 'History'), 'title': title, 'subtitle': 'Defense Attempt History', 'metadata': metadata,
                           'section_title': 'Defense Attempt History & Traceability Log', 'signatures': False,
                           'columns': [_column('attempt', 'Attempt', 9), _column('date', 'Schedule Date', 16, 'date'),
                                       _column('panel', 'Panel Score', 14, 'percentage'), _column('final', 'Final Grade', 14, 'percentage'),
                                       _column('outcome', 'Verdict / Outcome', 24), _column('part', 'Text Part', 10),
                                       _column('remarks', 'Instructions / Remarks', 55)], 'rows': history_rows})
    return sheets
