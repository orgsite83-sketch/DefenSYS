"""Export the selected progressive view, using its already-scoped payload."""
from collections import Counter
from xml.sax.saxutils import escape
from reports.export_formatters import handle_export_or_preview
from reports.pdf_builder import DefensysPdfReportBuilder


def export_workspace(request, data, fmt):
    view = data['view']
    scope = 'Capstone' if data['scope'] == 'capstone' else f"PIT / Year {data['year_level']}"
    period = data['academic_year'] or f"{data['year_from']} to {data['year_to']}"
    metadata = [{'label': 'Program', 'value': scope}, {'label': 'Period', 'value': period},
                {'label': 'View', 'value': view.replace('_', ' ').title()}]
    note = 'Published team averages describe recorded assessments. Different criteria, grading weights and cohorts limit direct comparison. Missing results are excluded.'
    percent = lambda x: 'Awaiting' if x is None else f'{x:.1f}%'
    if view in ('overview', 'year'):
        metadata.append({'label': 'Assessment', 'value': data.get('assessment_label', 'Separate stage/event results')})
        columns = [('label', 'Academic year' if view == 'overview' else 'Stage / event'), ('score', 'Published team average'),
                   ('assessed', 'Assessed teams'), ('eligible', 'Eligible teams'), ('pending', 'Pending teams')]
        rows = [{'label': r['academic_year'] if view == 'overview' else r['label'], 'score': percent(r['score']),
                 'assessed': r['assessed'], 'eligible': r['eligible'], 'pending': r['pending']}
                for r in data.get('annual_performance' if view == 'overview' else 'stage_results', [])]
        if data.get('rubric_changed'):
            note += ' Rubric or grading weights changed within the selected range.'
    elif view == 'assessment':
        columns = [('name', 'Criterion'), ('rubric', 'Rubric'), ('score', 'Average'), ('assessed', 'Assessed'), ('eligible', 'Eligible')]
        rows = [{'name': c['name'], 'rubric': c['rubric_name'], 'score': percent(c['score']),
                 'assessed': c['assessed'], 'eligible': c['eligible']} for c in data['criteria']]
        metadata += [{'label': 'Evaluator', 'value': data['evaluation_type']},
                     {'label': 'Assessment', 'value': next((c['label'] for c in data['contexts'] if c['id'] == data['context']), '')}]
    elif view == 'project_output':
        columns = [('academic_year', 'Academic year'), ('count', 'Projects')]
        rows = data['project_output']
        note = data['completion_policy']
    else:
        columns = [('dimension', 'Dimension'), ('label', 'Group'), ('count', 'Projects'), ('share', 'Share of projects')]
        total = len(data['projects'])
        rows = []
        for field, label in [('category', 'Primary focus'), ('domain', 'Application domain'), ('technologies', 'Documented technology')]:
            counts = Counter(t for p in data['projects'] for t in set(p[field])) if field == 'technologies' else Counter(p[field] for p in data['projects'])
            rows += [{'dimension': label, 'label': name, 'count': count, 'share': percent(count / total * 100)}
                     for name, count in counts.most_common()]
        note = data['completion_policy'] + ' Technology percentages overlap; focus and domain estimates require review.'
    if view.startswith('project'):
        metadata.append({'label': 'Project status', 'value': data['project_status']})
    column_spec = [{'key': k, 'label': label} for k, label in columns]
    safe = lambda value: "'" + str(value) if str(value).lstrip().startswith(('=', '+', '-', '@')) else str(value)
    rows = [{k: safe(v) for k, v in r.items()} for r in rows]

    def pdf():
        builder = DefensysPdfReportBuilder(title='Curriculum analytics', subtitle=f'{scope} / {period}',
            generated_by=request.user.get_full_name() or request.user.username, orientation='landscape')
        builder.add_header()
        builder.add_metadata_grid([(m['label'], escape(str(m['value']))) for m in metadata])
        if rows:
            builder.add_table([c['label'] for c in column_spec], [[escape(str(r[c['key']])) for c in column_spec] for r in rows],
                              col_widths=[builder.doc.width / len(columns)] * len(columns))
        else:
            builder.add_paragraph('No recorded results for this selection.')
        builder.add_paragraph(note)
        return builder.build()

    return handle_export_or_preview(fmt, 'Curriculum analytics', f'{scope} / {period}', [], metadata,
        column_spec, rows, f'Curriculum_{view}', pdf, sections=[{'type': 'summary', 'title': 'Interpretation', 'text': note}],
        generated_by=request.user.username)
