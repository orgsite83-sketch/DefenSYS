"""Export the same recorded data and scope used by the curriculum explorer."""
from xml.sax.saxutils import escape
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from rest_framework.exceptions import ValidationError
from reports.export_formatters import handle_export_or_preview
from reports.pdf_builder import DefensysPdfReportBuilder
from .explorer import explorer_payload


def _percent(value):
    return 'Awaiting' if value is None else f'{value:.1f}%'


def _cell(value):
    text = str(value)
    return "'" + text if text.lstrip().startswith(('=', '+', '-', '@')) else text


class CurriculumExplorerReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        data = explorer_payload(request.user, request.query_params)
        fmt = request.query_params.get('export_format', 'pdf')
        if fmt not in ('pdf', 'csv', 'xlsx', 'json'):
            raise ValidationError({'export_format': 'Use PDF, XLSX or CSV.'})
        project_tab = request.query_params.get('tab') == 'projects'
        scope = 'Capstone' if data['scope'] == 'capstone' else f"PIT / Year {data['year_level']}"
        period = data['academic_year'] or 'All academic years'
        semester = next((s['label'] for s in data['semesters'] if s['id'] == data['semester']), 'All semesters')
        context = next((c['label'] for c in data['contexts'] if c['id'] == data['context']), '')
        metadata = [{'label': 'Workflow', 'value': scope}, {'label': 'Academic year', 'value': period},
                    {'label': 'Semester', 'value': semester}, {'label': 'Unique projects', 'value': data['projects_count']}]
        if project_tab:
            metadata += [{'label': 'Computing focus estimated', 'value': data['project_analytics']['coverage']['classified']},
                         {'label': 'Unresolved focus', 'value': data['project_analytics']['coverage']['unresolved']},
                         {'label': 'Classification status', 'value': data['project_analytics']['status']}]
            columns = [{'key': 'dimension', 'label': 'Analysis dimension'},
                       {'key': 'category', 'label': 'Category / documented technology'},
                       {'key': 'count', 'label': 'Projects'}, {'key': 'share', 'label': 'Share'}]
            rows = [{'dimension': dimension, 'category': d['category'],
                     'count': d['count'], 'share': _percent(d['percentage'])}
                    for dimension, distribution in [
                        ('Primary computing focus', data['project_distribution']),
                        ('Application domain', data['project_analytics']['domains']),
                        ('Documented technology (overlapping)', data['project_analytics']['technologies']),
                        ('Unresolved reason', data['project_analytics']['unresolved_reasons'])]
                    for d in distribution]
        elif data['academic_year']:
            metadata += [{'label': 'Stage' if data['scope'] == 'capstone' else 'Event', 'value': context},
                         {'label': 'Evaluation source', 'value': data['evaluation_type'].title()},
                         {'label': 'Analysis reference', 'value': f"{data['reference']}% (does not change grades)"}]
            columns = [{'key': 'criterion', 'label': 'Criterion'}, {'key': 'rubric', 'label': 'Rubric'},
                       {'key': 'semester', 'label': 'Semester'},
                       {'key': 'target', 'label': 'Assessed unit'}, {'key': 'score', 'label': 'Average'},
                       {'key': 'coverage', 'label': 'Assessed / eligible'}, {'key': 'below', 'label': 'Below reference'}]
            rows = [{'criterion': c['name'], 'rubric': c['rubric_name'], 'target': c['target_type'],
                     'semester': c['semester_label'],
                     'score': _percent(c['score']), 'coverage': f"{c['assessed']} / {c['eligible']}",
                     'below': c['below']} for c in data['criteria']]
        else:
            columns = [{'key': 'year', 'label': 'Academic year'}, {'key': 'score', 'label': 'Average published grade'},
                       {'key': 'coverage', 'label': 'Assessed / eligible teams'}, {'key': 'status', 'label': 'Period status'}]
            rows = [{'year': y['academic_year'], 'score': _percent(y['score']),
                     'coverage': f"{y['assessed']} / {y['eligible']}",
                     'status': 'In progress' if y['in_progress'] else 'Recorded'} for y in data['annual_performance']]
        methodology = [data['methodology']['projects'], data['methodology']['classification'],
                       data['methodology']['performance'], data['methodology']['annual']]
        sections = [{'type': 'summary', 'title': 'How to interpret these results', 'text': ' '.join(methodology)}]

        def pdf():
            builder = DefensysPdfReportBuilder(title='Curriculum meeting report',
                                               subtitle=f'{scope} / {period}',
                                               generated_by=request.user.get_full_name() or request.user.username,
                                               orientation='landscape')
            builder.add_header()
            builder.add_metadata_grid([(m['label'], escape(str(m['value']))) for m in metadata])
            builder.add_section_header('Project insights' if project_tab else 'Recorded student performance')
            if rows:
                builder.add_table([c['label'] for c in columns],
                                  [[escape(str(row[c['key']])) for c in columns] for row in rows],
                                  col_widths=[builder.doc.width / len(columns)] * len(columns))
            else:
                builder.add_paragraph('No recorded results for this selection.')
            if project_tab and data['projects']:
                builder.add_section_header('Observed patterns')
                for observation in data['project_analytics']['observations']:
                    builder.add_paragraph(observation)
                builder.add_section_header('Classification evidence and unresolved reasons')
                builder.add_table(['Project', 'Computing estimate', 'Domain', 'Why'],
                                  [[escape(p['project_title']), escape(p['category']), escape(p['domain']),
                                    escape(p['classification_reason'])] for p in data['projects']],
                                  col_widths=[builder.doc.width * f for f in (.25, .2, .2, .35)])
            builder.add_section_header('How to interpret these results')
            for sentence in methodology:
                builder.add_paragraph(sentence)
            return builder.build()

        return handle_export_or_preview(fmt, 'Curriculum meeting report', f'{scope} / {period}', [],
                                       metadata, columns, [{k: _cell(v) for k, v in row.items()} for row in rows],
                                       f"Curriculum_{data['scope']}_{period.replace(' ', '-')}", pdf,
                                       sections=sections, generated_by=request.user.username)
