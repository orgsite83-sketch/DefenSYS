"""Read-only rubric inventory, actual grading assignments and review documents."""
from collections import defaultdict
from xml.sax.saxutils import escape

from django.db.models import Q


def rubric_assignments(rubrics):
    """A stage association or publication alone is not a grading selection.

    Read all configuration references in two queries, including reuse across
    academic periods. Never use the serializer's get-or-create weights helper.
    """
    from defense.stages.models import StageGradingConfig
    from defense.scheduler.models import PitEventGradingConfig
    by_id = {rubric.pk: rubric for rubric in rubrics}
    assignments = defaultdict(list)
    if not by_id:
        return assignments
    for scope, model, slots in (
        ('capstone', StageGradingConfig, ('panel', 'adviser', 'peer')),
        ('pit', PitEventGradingConfig, ('panel', 'peer')),
    ):
        ids = [key for key, rubric in by_id.items() if rubric.scope == scope]
        if not ids:
            continue
        query = Q()
        for slot in slots:
            query |= Q(**{f'{slot}_rubric_id__in': ids})
        related = ['semester__school_year'] + (['defense_stage'] if scope == 'capstone' else [])
        configs = model.objects.filter(query).select_related(*related).order_by('semester_id', 'pk')
        for config in configs:
            distribution = ', '.join(f'{slot.title()}: {getattr(config, slot + "_weight")}%' for slot in slots)
            for slot in slots:
                rubric_id = getattr(config, f'{slot}_rubric_id')
                if rubric_id not in ids:
                    continue
                assignments[rubric_id].append({
                    'stage': config.defense_stage.label if scope == 'capstone' else config.event_name,
                    'semester': config.semester.display_name,
                    'evaluation_type': slot.title(),
                    'weight': getattr(config, slot + '_weight'),
                    'weights': distribution,
                    'status': 'Officially complete' if config.is_officially_complete else 'Configured',
                })
    return assignments


def build_rubric_spec(rubrics, *, individual=False):
    from reports.catalog_reports import column, dataset
    assignments = rubric_assignments(rubrics)
    rows, criteria_rows, assignment_rows, details = [], [], [], []
    for number, rubric in enumerate(rubrics, 1):
        selected = assignments[rubric.pk]
        criteria = list(rubric.criteria.all())
        contexts = list(dict.fromkeys(item['stage'] for item in selected))
        stage = rubric.defense_stage.label if rubric.defense_stage_id else (
            ', '.join(contexts) if contexts else 'No event assigned' if rubric.scope == 'pit' else 'No fixed stage'
        )
        assigned_to = '\n'.join(f'{item["stage"]} - {item["evaluation_type"]} - {item["semester"]}' for item in selected)
        distributions = list(dict.fromkeys(item['weights'] for item in selected))
        row = {
            'rubric_no': number, 'name': rubric.name, 'scope': rubric.get_scope_display(),
            'semester': rubric.semester.display_name, 'stage': stage,
            'evaluation_type': rubric.get_evaluation_type_display(), 'target': rubric.get_target_type_display(),
            'status': rubric.get_status_display(), 'assignment_status': 'Assigned' if selected else 'Not assigned',
            'assigned_to': assigned_to or 'Not selected in a grading configuration',
            'criteria': len(criteria), 'weights': '\n'.join(distributions) or 'No grading assignment',
        }
        rows.append(row)
        details.append({'rubric': row, 'criteria': criteria, 'assignments': selected})
        for assignment in selected:
            assignment_rows.append({'rubric_no': number, 'rubric': rubric.name, 'scope': row['scope'], **assignment})
        for index, criterion in enumerate(criteria, 1):
            description = criterion.description or ''
            from reports.document_workbooks import text_parts
            for part_number, part in enumerate(list(text_parts(description)) or [''], 1):
                criteria_rows.append({
                    'rubric_no': number, 'rubric': rubric.name, 'criterion_no': index,
                    'criterion': criterion.name, 'description': part, 'part': part_number,
                    'order': criterion.display_order, 'scale': criterion.get_scale_display(),
                    'max_score': criterion.max_score, 'weight': str(criterion.weight),
                    'target': criterion.get_target_type_display(),
                })
    assignment_columns = [
        column('rubric_no', 'Rubric No.', 12, type='integer'), column('rubric', 'Rubric', 34),
        column('scope', 'Scope', 16), column('stage', 'Assigned Stage / Event', 30),
        column('semester', 'Assignment Academic Period', 36), column('evaluation_type', 'Selected Grading Slot', 24),
        column('weight', 'Slot Contribution', 20, type='percentage'), column('weights', 'Grade Distribution', 38),
        column('status', 'Stage / Event Setup Status', 28),
    ]
    criteria_columns = [
        column('rubric_no', 'Rubric No.', 12, type='integer'), column('rubric', 'Rubric', 32),
        column('criterion_no', 'Criterion No.', 14, type='integer'), column('criterion', 'Criterion', 32),
        column('description', 'Description', 66), column('part', 'Text Part', 12, type='integer'),
        column('order', 'Order', 12, type='integer'), column('scale', 'Scoring Scale', 22),
        column('max_score', 'Maximum Score', 18, type='integer'),
        column('weight', 'Configured Criterion Weight', 26, type='number', number_format='0.00'),
        column('target', 'Target', 20),
    ]
    published = sum(row['status'] == 'Published' for row in rows)
    assigned = sum(row['assignment_status'] == 'Assigned' for row in rows)
    return dataset('Rubric Details' if individual else 'Rubric Catalog', [
        column('rubric_no', 'Rubric No.', 12, type='integer'), column('name', 'Rubric', 34, link_to='Criteria'),
        column('status', 'Publication Status', 22),
        column('assignment_status', 'Grading Assignment', 22, link_to='Assignments'),
        column('evaluation_type', 'Evaluator Type', 20), column('stage', 'Rubric Stage / Event', 30),
        column('scope', 'Scope', 16), column('semester', 'Rubric Academic Period', 36),
        column('target', 'Evaluation Target', 24),
        column('assigned_to', 'Actual Grading Selections', 48), column('criteria', 'Criteria', 12, type='integer'),
        column('weights', 'Assigned Grade Distribution', 38),
    ], rows, details=details, report_layout='rubrics', individual=individual,
        summary_kpis=[{'label': label, 'value': str(value)} for label, value in (
            ('Rubrics', len(rows)), ('Published', published), ('Draft', len(rows) - published),
            ('Assigned', assigned), ('Not assigned', len(rows) - assigned))],
        extra_sheets=[
            {'name': 'Assignments', 'title': 'Actual Rubric Grading Assignments', 'metadata': [],
             'columns': assignment_columns, 'rows': assignment_rows, 'link_key': 'rubric_no'},
            {'name': 'Criteria', 'title': 'Complete Rubric Criteria', 'metadata': [],
             'columns': criteria_columns, 'rows': criteria_rows, 'link_key': 'rubric_no'},
        ], sections=[
            {'title': 'Actual Grading Assignments', 'columns': assignment_columns, 'rows': assignment_rows},
            {'title': 'Complete Rubric Criteria', 'columns': criteria_columns, 'rows': criteria_rows},
        ])


def render_rubric_sections(builder, spec):
    """A scan-friendly inventory, then a distinctly headed page per rubric."""
    details = spec['details']
    if not spec['individual']:
        builder.add_section_header('Rubric Inventory')
        builder.add_paragraph(' | '.join(f'{item["label"]}: {item["value"]}' for item in spec['summary_kpis']), 'BodyMuted')
        builder.add_paragraph('Publication status and grading assignment are separate. Assigned means the rubric is selected in a stage or event grading configuration.', 'BodyMuted')
        headers = ['No.', 'Rubric', 'Stage / Event', 'Evaluator', 'Publication', 'Grading Assignment']
        ratios = (.05, .24, .23, .13, .12, .23)
        rows = [[str(row['rubric_no']), escape(row['name']), escape(row['stage']),
                 row['evaluation_type'], row['status'], row['assignment_status']] for row in spec['rows']]
        builder.add_table(headers, rows, col_widths=[builder.usable_width * ratio for ratio in ratios],
            bold_cols=[1, 4, 5], repeat_headers=True)
        if not rows:
            builder.add_paragraph('No rubrics match the selected filters.')
    for detail in details:
        row = detail['rubric']
        if not spec['individual']:
            builder.add_page_break()
        builder.add_page_context(f'Rubric {row["rubric_no"]:02d} - {row["name"]}')
        builder.add_section_header(f'Rubric {row["rubric_no"]:02d} - {escape(row["name"])}')
        builder.add_metadata_grid([(label, escape(str(row[key]))) for label, key in (
            ('Publication Status', 'status'), ('Grading Assignment', 'assignment_status'),
            ('Academic Scope', 'scope'), ('Academic Period', 'semester'), ('Rubric Stage / Event', 'stage'),
            ('Evaluator Type', 'evaluation_type'), ('Evaluation Target', 'target'), ('Criteria Count', 'criteria'))])
        builder.add_section_header('Actual Grading Assignments')
        if detail['assignments']:
            if row['status'] == 'Draft':
                builder.add_paragraph('This draft rubric is selected in a grading configuration. It must be published before evaluation.', 'BodyMuted')
            builder.add_table(['Stage / Event', 'Academic Period', 'Grading Slot', 'Contribution', 'Grade Distribution'],
                [[escape(item['stage']), escape(item['semester']), item['evaluation_type'], f'{item["weight"]}%', escape(item['weights'])]
                 for item in detail['assignments']],
                col_widths=[builder.usable_width * ratio for ratio in (.21, .23, .13, .15, .28)], repeat_headers=True)
        else:
            builder.add_paragraph('Not assigned: this rubric is not selected in any stage or event grading configuration. A stage association does not establish a grading assignment.', 'BodyMuted')
        builder.add_section_header('Evaluation Criteria')
        builder.add_paragraph('Criterion weights below are the configured numeric values; grade distribution is shown separately above.', 'BodyMuted')
        criteria = detail['criteria']
        builder.add_table(['No.', 'Criterion', 'Scoring Scale', 'Maximum Score', 'Configured Weight', 'Target'],
            [[str(index), escape(criterion.name), criterion.get_scale_display(), str(criterion.max_score),
              f'{criterion.weight:.2f}', criterion.get_target_type_display()] for index, criterion in enumerate(criteria, 1)],
            col_widths=[builder.usable_width * ratio for ratio in (.05, .33, .20, .12, .14, .16)], repeat_headers=True)
        if not criteria:
            builder.add_paragraph('No evaluation criteria have been configured.')
        for index, criterion in enumerate(criteria, 1):
            if criterion.description:
                builder.add_subsection_header(f'{index}. {escape(criterion.name)} - Description')
                builder.add_paragraph(escape(criterion.description).replace('\n', '<br/>'))
