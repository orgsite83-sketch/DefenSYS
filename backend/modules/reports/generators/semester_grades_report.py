from decimal import Decimal
from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_semester_grades_pdf(semester, grade_records, generated_by_user, signatories=None, include_signatures=True):
    """
    Generate an official USTP DIT PDF summary of all team grades for a semester.
    """
    sem_label = f"{semester.school_year.label if semester else ''} {semester.label if semester else ''}".strip()
    builder = DefensysPdfReportBuilder(
        title="Semester Grade Summary Report",
        subtitle=f"Official Defense Evaluation Registry · {sem_label}",
        generated_by=generated_by_user,
    )

    total_records = len(grade_records)
    passed_count = sum(1 for g in grade_records if g.result == 'passed')
    failed_count = sum(1 for g in grade_records if g.result == 'failed')
    pending_count = sum(1 for g in grade_records if g.result == 'pending')

    completed_grades = [g.final_grade for g in grade_records if g.final_grade is not None]
    avg_grade = sum(completed_grades) / len(completed_grades) if completed_grades else Decimal('0.00')

    # 1. Official Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    metadata_rows = [
        ("Academic School Year", semester.school_year.label if semester else "N/A"),
        ("Semester / Term", semester.label if semester else "N/A"),
        ("Total Graded Teams", f"{total_records} Teams Recorded"),
        ("Outcome Breakdown", f"Passed: {passed_count}  ·  Failed: {failed_count}  ·  Pending: {pending_count}"),
        ("Cohort Grade Average", f"{avg_grade:.2f}%" if completed_grades else "N/A"),
    ]
    builder.add_metadata_grid(metadata_rows)

    # 3. Main Grade Sheet Table
    builder.add_section_header("Student Teams Grade Register")

    headers = [
        "Team Name",
        "Project Title",
        "Stage",
        "Panel",
        "Adv",
        "Peer",
        "Final",
        "Result",
    ]

    rows = []
    for gr in grade_records:
        p_score = f"{gr.panel_score:.1f}%" if gr.panel_score is not None else "-"
        a_score = f"{gr.adviser_score:.1f}%" if (gr.adviser_score is not None and gr.adviser_weight > 0) else "-"
        peer_score = f"{gr.peer_score:.1f}%" if gr.peer_score is not None else "-"
        f_grade = f"{gr.final_grade:.2f}%" if gr.final_grade is not None else "Pending"

        result_label = gr.result.upper() if gr.final_grade is not None else "PENDING"

        rows.append([
            gr.team.name or "N/A",
            gr.team.project_title or "N/A",
            gr.stage_label or "N/A",
            p_score,
            a_score,
            peer_score,
            f_grade,
            result_label,
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[1.3 * inch, 1.8 * inch, 0.9 * inch, 0.55 * inch, 0.45 * inch, 0.45 * inch, 0.50 * inch, 0.55 * inch],
        alignments=['left', 'left', 'center', 'center', 'center', 'center', 'center', 'center'],
        bold_cols=[0, 6, 7],
    )

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
