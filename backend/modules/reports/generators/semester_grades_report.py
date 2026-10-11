from collections import defaultdict
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, Spacer, Table

from grading.constants import PASS_GRADE_THRESHOLD
from reports.grade_summary import (
    GRADE_OUTCOME_NOTE,
    grade_outcome_label,
    outcome_breakdown,
    summarize_grade_records,
)
from reports.pdf_builder import DefensysPdfReportBuilder
from reports.pdf_styles import BORDER_GREY, defensys_table_style


def _stage_groups(grade_records):
    """Group by scope and stage/event, following the configured capstone order."""
    groups = defaultdict(list)
    for grade in grade_records:
        groups[(grade.scope, grade.stage_label or 'Unspecified stage / event')].append(grade)

    def group_order(item):
        (scope, label), grades = item
        stage_orders = [
            grade.defense_stage.display_order
            for grade in grades if grade.defense_stage is not None
        ]
        return (0 if scope == 'capstone' else 1, min(stage_orders, default=999), label.casefold())

    return sorted(groups.items(), key=group_order)


def _add_stage_table(builder, scope, stage_label, grade_records):
    """Repeat the stage band and column headings when a table continues on a page."""
    headers = ['Team Name', 'Project Title', 'Panel', 'Adviser', 'Peer', 'Final Grade', 'Outcome']
    outcome_style = ParagraphStyle(
        'SemesterGradeOutcome', parent=builder.styles['TableCellBoldCenter'],
        splitLongWords=False,
    )
    scope_label = 'Capstone' if scope == 'capstone' else 'PIT'
    count_label = 'record' if len(grade_records) == 1 else 'records'
    stage_heading = (
        f"<b>{escape(stage_label)}</b>"
        f" - {scope_label} - {len(grade_records)} {count_label}"
    )
    rows = [[Paragraph(stage_heading, builder.styles['TableHeader']), *[''] * 6]]
    rows.append([
        Paragraph(f'<b>{header}</b>', builder.styles['TableHeader' if index < 2 else 'TableHeaderCenter'])
        for index, header in enumerate(headers)
    ])

    for grade in sorted(grade_records, key=lambda grade: (grade.team.name or '').casefold()):
        panel_score = f'{grade.panel_score:.1f}%' if grade.panel_score is not None else '-'
        adviser_score = (
            f'{grade.adviser_score:.1f}%'
            if grade.adviser_score is not None and grade.adviser_weight > 0 else '-'
        )
        peer_score = f'{grade.peer_score:.1f}%' if grade.peer_score is not None else '-'
        final_grade = f'{grade.final_grade:.2f}%' if grade.final_grade is not None else 'Pending'
        if grade.final_grade is not None and grade.final_grade < PASS_GRADE_THRESHOLD:
            final_grade += f"<br/><font size=7 color='#991B1B'>Below {PASS_GRADE_THRESHOLD:.0f}%</font>"

        values = [
            escape(grade.team.name or 'N/A'),
            escape(grade.project_title_snapshot or grade.team.project_title or 'N/A'),
            panel_score, adviser_score, peer_score, final_grade,
            escape(grade_outcome_label(grade)),
        ]
        cell_styles = [
            builder.styles['TableCellBold'], builder.styles['TableCell'],
            *[builder.styles['TableCellCenter']] * 3,
            builder.styles['TableCellBoldCenter'], outcome_style,
        ]
        rows.append([Paragraph(value, style) for value, style in zip(values, cell_styles)])

    # Reassign the former Stage column's space to the final grade and outcome.
    widths = [builder.usable_width * ratio for ratio in (.185, .285, .07, .09, .07, .10, .20)]
    table = Table(rows, colWidths=widths, repeatRows=2)
    table.setStyle(defensys_table_style())
    table.setStyle([
        ('SPAN', (0, 0), (-1, 0)),
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#EDEFF2')),
        ('BACKGROUND', (0, 1), (-1, 1), colors.HexColor('#F3F4F6')),
        ('LINEBELOW', (0, 1), (-1, 1), 0.5, BORDER_GREY),
        ('TOPPADDING', (0, 0), (-1, 0), 6),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 6),
        ('VALIGN', (0, 2), (-1, -1), 'MIDDLE'),
    ])
    builder.add_flowable(table)
    builder.add_flowable(Spacer(1, .10 * inch))


def generate_semester_grades_pdf(semester, grade_records, generated_by_user, signatories=None, include_signatures=False):
    """
    Generate an official USTP DIT PDF summary of all team grades for a semester.
    """
    sem_label = f"{semester.school_year.label if semester else ''} {semester.label if semester else ''}".strip()
    builder = DefensysPdfReportBuilder(
        title="Semester Grade Summary Report",
        subtitle=f"Official Defense Evaluation Registry · {sem_label}",
        generated_by=generated_by_user,
    )

    summary = summarize_grade_records(grade_records)

    # 1. Official Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    metadata_rows = [
        ("Academic School Year", semester.school_year.label if semester else "N/A"),
        ("Semester / Term", semester.label if semester else "N/A"),
        ("Academic Scope", ' / '.join(sorted({'Capstone' if grade.is_capstone else 'PIT' for grade in grade_records})) or 'No matching assessments'),
        ("Teams in Report", str(summary['team_count'])),
        ("Stage / Event Records", str(summary['record_count'])),
        ("Outcome Breakdown", outcome_breakdown(summary)),
        ("Mean Recorded Grade", f"{summary['average']:.2f}%" if summary['average'] is not None else "N/A"),
    ]
    builder.add_metadata_grid(metadata_rows)
    builder.add_paragraph(escape(GRADE_OUTCOME_NOTE), style_name='BodyMuted')

    # 3. Main Grade Sheet Table
    builder.add_section_header("Student Teams Grade Register")

    for (scope, stage_label), records in _stage_groups(grade_records):
        _add_stage_table(builder, scope, stage_label, records)
    if not grade_records:
        builder.add_paragraph('No grade records match the selected filters.')

    # 4. Signatures Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="Academic Documenter / Evaluator",
        noted_by="Academic Department Secretary",
        noted_role="Department Administrative Secretary",
        approved_by="IT Program Chairperson",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
