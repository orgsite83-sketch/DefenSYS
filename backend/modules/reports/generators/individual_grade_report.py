from decimal import Decimal
from io import BytesIO
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib import colors

from reports.pdf_styles import (
    defensys_styles,
    defensys_cover_page,
    defensys_confidential_callout,
    defensys_table_style,
    NumberedCanvas,
)


def generate_individual_grade_pdf(student, student_grade, team_grade, generated_by_user):
    """
    Generate a confidential PDF report detailing an individual student's grades,
    peer evaluation score contribution, panel assessment, and official audit summary.

    Args:
        student: User model instance (Student)
        student_grade: StudentStageGrade model instance or None
        team_grade: TeamGrade database object
        generated_by_user: Username/Name of the requestor

    Returns:
        bytes: PDF binary content
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.85 * inch,
        bottomMargin=0.85 * inch,
        leftMargin=0.75 * inch,
        rightMargin=0.75 * inch,
    )

    doc.generated_by = generated_by_user
    doc.generated_at = datetime.now().strftime('%Y-%m-%d %I:%M %p')

    story = []
    styles = defensys_styles()

    # 1. Cover Page
    team = team_grade.team
    semester = team_grade.semester
    student_name = student.get_full_name() or student.username

    metadata_rows = [
        ("Student Name:", student_name),
        ("Student ID / Username:", student.username),
        ("Academic Period:", f"{semester.school_year.label} — {semester.label}"),
        ("Team Name:", team.name or "N/A"),
        ("Project Title:", team.project_title or "N/A"),
        ("Course / Year Level:", f"{team.level or 'N/A'} — {team.year_level or 'N/A'}"),
        ("Defense Stage:", team_grade.stage_label or "N/A"),
        ("Project Adviser:", f"{team.adviser.first_name} {team.adviser.last_name}".strip() if team.adviser else "N/A"),
    ]

    defensys_cover_page(
        story=story,
        title="Individual Student Grade Audit Report",
        subtitle=f"Confidential Performance & Evaluation Breakdown — {team_grade.stage_label}",
        generated_by_user=generated_by_user,
        metadata_rows=metadata_rows,
    )

    # 2. Main Page Header & Confidential Callout
    story.append(defensys_confidential_callout())
    story.append(Spacer(1, 0.25 * inch))

    # 3. Overall Grade Breakdown
    story.append(Paragraph("Individual Academic Grade Breakdown", styles['SectionHeader']))
    story.append(Spacer(1, 0.05 * inch))

    def format_score(val):
        return f"{val:.2f}%" if val is not None else "Pending"

    # Effective student scores
    student_panel = student_grade.panel_score if student_grade and student_grade.panel_score is not None else team_grade.panel_score
    student_adviser = student_grade.adviser_score if student_grade and student_grade.adviser_score is not None else team_grade.adviser_score
    student_peer = student_grade.peer_score if student_grade and student_grade.peer_score is not None else team_grade.peer_score
    
    if student_grade and student_grade.final_grade is not None:
        student_final = student_grade.final_grade
    else:
        # Calculate from components if available
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
            Paragraph("<b>Weight</b>", styles['TableHeader']),
            Paragraph("<b>Earned Score</b>", styles['TableHeader']),
            Paragraph("<b>Weighted Value</b>", styles['TableHeader']),
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
        Paragraph(f"{team_grade.panel_weight}%", styles['TableCell']),
        Paragraph(format_score(student_panel), styles['TableCell']),
        Paragraph(format_score(panel_val), styles['TableCell']),
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
            Paragraph(f"{team_grade.adviser_weight}%", styles['TableCell']),
            Paragraph(format_score(student_adviser), styles['TableCell']),
            Paragraph(format_score(adviser_val), styles['TableCell']),
        ])

    # Peer Evaluation Component
    peer_val = (
        (student_peer * Decimal(team_grade.peer_weight) / Decimal('100')).quantize(Decimal('0.01'))
        if student_peer is not None
        else None
    )
    summary_data.append([
        Paragraph("Individual Peer Evaluation Contribution", styles['TableCell']),
        Paragraph(f"{team_grade.peer_weight}%", styles['TableCell']),
        Paragraph(format_score(student_peer), styles['TableCell']),
        Paragraph(format_score(peer_val), styles['TableCell']),
    ])

    # Final Result
    status_str = "PASSED" if (student_final is not None and student_final >= Decimal('75.00')) else "FAILED / RE-DEFENSE"
    if student_final is None:
        status_str = "PENDING"

    summary_data.append([
        Paragraph("<b>TOTAL OFFICIAL GRADE</b>", styles['TableCellBold']),
        Paragraph("<b>100%</b>", styles['TableCellBold']),
        Paragraph(f"<b>{format_score(student_final)}</b>", styles['TableCellBold']),
        Paragraph(f"<b>Status: {status_str}</b>", styles['TableCellBold']),
    ])

    summary_table = Table(summary_data, colWidths=[2.6 * inch, 1.1 * inch, 1.5 * inch, 1.8 * inch])
    summary_table.setStyle(defensys_table_style())
    story.append(summary_table)
    story.append(Spacer(1, 0.3 * inch))

    # 4. Panelist Defense Feedback & Remarks
    submissions = list(team_grade.panelist_submissions.all().select_related('panelist'))
    remarks_list = [s for s in submissions if s.remarks and s.remarks.strip()]
    if remarks_list:
        story.append(Paragraph("Panelist Defense Feedback & Remarks", styles['SectionHeader']))
        story.append(Spacer(1, 0.05 * inch))

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
        story.append(Spacer(1, 0.3 * inch))

    # 5. Formal Certification Notice & Signature Signoff
    story.append(Paragraph("Official Audit & Verification Certification", styles['SectionHeader']))
    story.append(Spacer(1, 0.05 * inch))

    cert_text = (
        "This Individual Student Grade Audit Report has been extracted directly from the DefenSYS "
        "Academic Governance Registry upon verified audit request. All criterion assessments, "
        "panelist deliberations, and peer evaluation weights reflect institutional records."
    )
    story.append(Paragraph(cert_text, styles['Normal']))
    story.append(Spacer(1, 0.4 * inch))

    sig_data = [
        [
            Paragraph("________________________________________<br/><b>PIT Coordinator / Adviser</b>", styles['Normal']),
            Paragraph("________________________________________<br/><b>Department Chair / Dean</b>", styles['Normal']),
        ]
    ]
    sig_table = Table(sig_data, colWidths=[3.5 * inch, 3.5 * inch])
    sig_table.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
    ]))
    story.append(sig_table)

    # Build document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()

    return pdf_content
