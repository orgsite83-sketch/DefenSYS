from decimal import Decimal
from io import BytesIO
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib import colors

from reports.pdf_styles import (
    defensys_styles,
    defensys_official_header,
    defensys_metadata_grid,
    defensys_signatures_block,
    defensys_table_style,
    NumberedCanvas,
)


def generate_individual_grade_pdf(student, student_grade, team_grade, generated_by_user):
    """
    Generate an official USTP DIT confidential PDF report detailing an individual student's grades,
    peer evaluation score contribution, panel assessment, and official audit summary.
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.42 * inch,
        bottomMargin=0.50 * inch,
        leftMargin=0.50 * inch,
        rightMargin=0.50 * inch,
    )

    doc.generated_by = generated_by_user
    doc.generated_at = datetime.now().strftime('%Y-%m-%d %I:%M %p')

    story = []
    styles = defensys_styles()

    team = team_grade.team
    semester = team_grade.semester
    student_name = student.get_full_name() or student.username
    adviser_name = f"{team.adviser.first_name} {team.adviser.last_name}".strip() if team.adviser else "Unassigned"

    # 1. Official Header Banner & Document Title
    defensys_official_header(
        story=story,
        title=f"Individual Student Grade Audit Report — {student_name}",
        subtitle=f"Certified Academic Performance & Defense Breakdown · {team_grade.stage_label or 'Defense Stage'}"
    )

    # 2. Metadata Grid
    stage_text = f"{team_grade.stage_label or 'Defense Stage'}"
    if getattr(team_grade, 'attempt_count', 1) > 1:
        stage_text += f" (Attempt #{team_grade.attempt_count})"

    metadata_rows = [
        ("Student Candidate", f"{student_name} (ID: {student.username})"),
        ("Student Team & Section", f"{team.name or 'Team'} · {team.section or team.year_level or 'BSIT'}"),
        ("Title of Approved Project", team.project_title or team.name or "N/A"),
        ("Academic Term / Semester", f"{semester.school_year.label if semester else ''} — {semester.label if semester else ''}"),
        ("Capstone Defense Stage", stage_text),
        ("Project Adviser", adviser_name),
    ]

    verdict_val = getattr(team_grade, 'verdict', '')
    if verdict_val:
        verdict_display = dict(team_grade.VERDICT_CHOICES).get(verdict_val, verdict_val.replace('_', ' ').title())
        if team_grade.revision_deadline:
            verdict_display += f" (Deadline: {team_grade.revision_deadline.strftime('%b %d, %Y')})"
        metadata_rows.append(("Panel Verdict", verdict_display))

    story.append(defensys_metadata_grid(metadata_rows, width=7.0*inch))
    story.append(Spacer(1, 0.08*inch))

    # 3. Overall Grade Breakdown
    story.append(Paragraph("Individual Academic Grade Breakdown", styles['SectionHeader']))
    story.append(Spacer(1, 0.03*inch))

    def format_score(val):
        return f"{val:.2f}%" if val is not None else "Pending"

    # Effective student scores
    student_panel = student_grade.panel_score if student_grade and student_grade.panel_score is not None else team_grade.panel_score
    student_adviser = student_grade.adviser_score if student_grade and student_grade.adviser_score is not None else team_grade.adviser_score
    student_peer = student_grade.peer_score if student_grade and student_grade.peer_score is not None else team_grade.peer_score
    
    if student_grade and student_grade.final_grade is not None:
        student_final = student_grade.final_grade
    else:
        if student_panel is not None and student_peer is not None:
            tot = student_panel * Decimal(team_grade.panel_weight) + student_peer * Decimal(team_grade.peer_weight)
            if team_grade.is_capstone and team_grade.adviser_weight > 0 and student_adviser is not None:
                tot += student_adviser * Decimal(team_grade.adviser_weight)
            student_final = (tot / Decimal('100')).quantize(Decimal('0.01'))
        else:
            student_final = team_grade.final_grade

    summary_data = [
        [
            Paragraph("<b>Assessment Component</b>", styles['TableHeader']),
            Paragraph("<b>Weight</b>", styles['TableHeaderCenter']),
            Paragraph("<b>Earned Score</b>", styles['TableHeaderCenter']),
            Paragraph("<b>Weighted Value</b>", styles['TableHeaderCenter']),
            Paragraph("<b>Evaluation Remarks / Source</b>", styles['TableHeader'])
        ]
    ]

    # Panel Component
    panel_val = (
        (student_panel * Decimal(team_grade.panel_weight) / Decimal('100')).quantize(Decimal('0.01'))
        if student_panel is not None
        else None
    )
    summary_data.append([
        Paragraph("Panel Defense Evaluation", styles['TableCell']),
        Paragraph(f"{team_grade.panel_weight}%", styles['TableCellCenter']),
        Paragraph(format_score(student_panel), styles['TableCellCenter']),
        Paragraph(format_score(panel_val), styles['TableCellCenter']),
        Paragraph("Composite panel rubric score", styles['TableCell']),
    ])

    # Adviser Component (if Capstone)
    if team_grade.is_capstone and team_grade.adviser_weight > 0:
        adviser_val = (
            (student_adviser * Decimal(team_grade.adviser_weight) / Decimal('100')).quantize(Decimal('0.01'))
            if student_adviser is not None
            else None
        )
        summary_data.append([
            Paragraph("Project Adviser Grade", styles['TableCell']),
            Paragraph(f"{team_grade.adviser_weight}%", styles['TableCellCenter']),
            Paragraph(format_score(student_adviser), styles['TableCellCenter']),
            Paragraph(format_score(adviser_val), styles['TableCellCenter']),
            Paragraph(f"Assessed by {adviser_name}", styles['TableCell']),
        ])

    # Peer Evaluation Component
    peer_val = (
        (student_peer * Decimal(team_grade.peer_weight) / Decimal('100')).quantize(Decimal('0.01'))
        if student_peer is not None
        else None
    )
    summary_data.append([
        Paragraph("Individual Peer Evaluation Contribution", styles['TableCell']),
        Paragraph(f"{team_grade.peer_weight}%", styles['TableCellCenter']),
        Paragraph(format_score(student_peer), styles['TableCellCenter']),
        Paragraph(format_score(peer_val), styles['TableCellCenter']),
        Paragraph("Internal peer rubric average", styles['TableCell']),
    ])

    # Final Result
    status_str = "PASSED" if (student_final is not None and student_final >= Decimal('75.00')) else "FAILED / RE-DEFENSE"
    if student_final is None:
        status_str = "PENDING"

    summary_data.append([
        Paragraph("<b>TOTAL OFFICIAL GRADE</b>", styles['TableCellBold']),
        Paragraph("<b>100%</b>", styles['TableCellBoldCenter']),
        Paragraph(f"<b>{format_score(student_final)}</b>", styles['TableCellBoldCenter']),
        Paragraph(f"<b>{format_score(student_final)}</b>", styles['TableCellBoldCenter']),
        Paragraph(f"<b>Official Status: {status_str}</b>", styles['TableCellBold']),
    ])

    summary_table = Table(summary_data, colWidths=[2.0 * inch, 0.8 * inch, 1.0 * inch, 1.0 * inch, 2.2 * inch])
    summary_table.setStyle(defensys_table_style())
    story.append(summary_table)
    story.append(Spacer(1, 0.08 * inch))

    # 4. Panelist Defense Feedback & Remarks
    submissions = list(team_grade.panelist_submissions.all().select_related('panelist'))
    remarks_list = [s for s in submissions if s.remarks and s.remarks.strip()]
    if remarks_list:
        story.append(Paragraph("Panelist Defense Feedback & Direct Observations", styles['SectionHeader']))
        story.append(Spacer(1, 0.03 * inch))

        rem_data = [[
            Paragraph("<b>Panelist</b>", styles['TableHeader']),
            Paragraph("<b>Remarks & Recommendations</b>", styles['TableHeader']),
        ]]
        for s in remarks_list:
            pname = s.panelist.get_full_name() if s.panelist else s.guest_name
            if not pname:
                pname = "Defense Panelist"
            rem_data.append([
                Paragraph(pname, styles['TableCellBold']),
                Paragraph(s.remarks, styles['TableCell']),
            ])
        rem_table = Table(rem_data, colWidths=[2.2 * inch, 4.8 * inch])
        rem_table.setStyle(defensys_table_style())
        story.append(rem_table)

    # 5. Official Signatures Block
    defensys_signatures_block(
        story=story,
        prepared_by=generated_by_user,
        noted_by=adviser_name,
        approved_by="IT Program Chairperson"
    )

    # Build document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()

    return pdf_content
