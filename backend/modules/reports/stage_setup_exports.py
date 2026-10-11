"""Keep each stage/event's settings, selected rubrics and requirements together."""
from xml.sax.saxutils import escape


def stage_document_sheets(groups):
    return [{
        'name': group['configuration']['stage'],
        'title': group['configuration']['stage'],
        'subtitle': 'Official Stage / Event Configuration',
        'metadata': [{'label': label, 'value': group['configuration'][key]} for label, key in (
            ('Academic Scope', 'scope'), ('Academic Period', 'semester'), ('Setup Status', 'status'),
            ('Grade Distribution', 'weights'), ('Peer Grading Setting', 'peer_enabled'))] + [
                {'label': f'{row["role"]} Rubric', 'value': f'{row["rubric"]} ({row["publication"]})' if row['publication'] != '-' else row['rubric']}
                for row in group['rubrics']],
        'section_title': 'Deliverable Requirements',
        'columns': [
            {'key': 'code', 'label': 'Deliverable Code', 'width': 16},
            {'key': 'label', 'label': 'Requirement', 'width': 48},
            {'key': 'type', 'label': 'Submission Phase', 'width': 22},
            {'key': 'required', 'label': 'Required', 'width': 14},
        ],
        'rows': [{**row, 'required': 'Yes' if row['required'] else 'No'} for row in group['requirements']],
    } for group in groups]


def render_stage_setup_sections(builder, spec):
    groups = spec['stage_groups']
    if not groups:
        builder.add_paragraph('No stages or events match the selected filters.')
    for index, group in enumerate(groups):
        row = group['configuration']
        if index:
            builder.add_page_break()
        builder.add_page_context(f'{row["stage"]} - {row["semester"]}')
        builder.add_section_header(escape(row['stage']))
        builder.add_metadata_grid([(label, escape(str(row[key]))) for label, key in (
            ('Academic Scope', 'scope'), ('Academic Period', 'semester'), ('Setup Status', 'status'),
            ('Grade Distribution', 'weights'), ('Peer Grading Setting', 'peer_enabled'))])
        builder.add_section_header('Selected Evaluation Rubrics')
        builder.add_table(['Grading Slot', 'Selected Rubric', 'Publication Status', 'Contribution'],
            [[item['role'], escape(item['rubric']), item['publication'], item['contribution']]
             for item in group['rubrics']],
            col_widths=[builder.usable_width * ratio for ratio in (.18, .44, .21, .17)], repeat_headers=True)
        builder.add_section_header('Deliverable Requirements')
        builder.add_table(['Code', 'Requirement', 'Submission Phase', 'Required'],
            [[escape(item['code']), escape(item['label']), item['type'], 'Yes' if item['required'] else 'No']
             for item in group['requirements']],
            col_widths=[builder.usable_width * ratio for ratio in (.14, .48, .24, .14)], repeat_headers=True)
        if not group['requirements']:
            builder.add_paragraph('No deliverable requirements have been configured for this stage or event.')
