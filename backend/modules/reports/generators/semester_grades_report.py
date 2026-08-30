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
    defensys_confidential_callout,
    defensys_table_style,
    NumberedCanvas,
)


def generate_semester_grades_pdf(semester, grade_records, generated_by_user):
    """
    Generate an official USTP DIT PDF summary of all team grades for a semester.
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.4 * inch,
        bottomMargin=0.55 * inch,
        leftMargin=0.5 * inch,
        rightMargin=0.5 * inch,
    )
    
    doc.generated_by = generated_by_user
    doc.generated_at = datetime.now().strftime('%Y-%m-%d %I:%M %p')
    
    story = []
    styles = defensys_styles()
    
    total_records = len(grade_records)
    passed_count = sum(1 for g in grade_records if g.result == 'passed')
    failed_count = sum(1 for g in grade_records if g.result == 'failed')
    pending_count = sum(1 for g in grade_records if g.result == 'pending')
    
    completed_grades = [g.final_grade for g in grade_records if g.final_grade is not None]
    avg_grade = sum(completed_grades) / len(completed_grades) if completed_grades else Decimal('0.00')
    
    # 1. Official Header Banner & Document Title
    defensys_official_header(
        story=story,
        title="Semester Grade Summary Report",
        subtitle=f"Official Defense Evaluation Registry · {semester.school_year.label if semester else ''} {semester.label if semester else ''}"
    )
    
    # 2. Metadata Grid
    metadata_rows = [
        ("Academic School Year", semester.school_year.label if semester else "N/A"),
        ("Semester / Term", semester.label if semester else "N/A"),
        ("Total Graded Teams", f"{total_records} Teams Recorded"),
        ("Outcome Breakdown", f"Passed: {passed_count}  ·  Failed: {failed_count}  ·  Pending: {pending_count}"),
        ("Cohort Grade Average", f"{avg_grade:.2f}%" if completed_grades else "N/A"),
    ]
    story.append(defensys_metadata_grid(metadata_rows, width=7.1*inch))
    story.append(Spacer(1, 0.12*inch))
    
    # 3. Main Grade Sheet Table
    story.append(Paragraph("Student Teams Grade Register", styles['SectionHeader']))
    story.append(Spacer(1, 0.04*inch))
    
    headers = [
        Paragraph("<b>Team Name</b>", styles['TableHeader']),
        Paragraph("<b>Project Title</b>", styles['TableHeader']),
        Paragraph("<b>Stage</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Panel</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Adv</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Peer</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Final</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Result</b>", styles['TableHeaderCenter'])
    ]
    
    table_rows = [headers]
    for gr in grade_records:
        p_score = f"{gr.panel_score:.1f}%" if gr.panel_score is not None else "-"
        a_score = f"{gr.adviser_score:.1f}%" if (gr.adviser_score is not None and gr.adviser_weight > 0) else "-"
        peer_score = f"{gr.peer_score:.1f}%" if gr.peer_score is not None else "-"
        f_grade = f"{gr.final_grade:.2f}%" if gr.final_grade is not None else "Pending"
        
        result_label = gr.result.upper() if gr.final_grade is not None else "PENDING"
        
        table_rows.append([
            Paragraph(gr.team.name or "N/A", styles['TableCellBold']),
            Paragraph(gr.team.project_title or "N/A", styles['TableCell']),
            Paragraph(gr.stage_label or "N/A", styles['TableCellCenter']),
            Paragraph(p_score, styles['TableCellCenter']),
            Paragraph(a_score, styles['TableCellCenter']),
            Paragraph(peer_score, styles['TableCellCenter']),
            Paragraph(f_grade, styles['TableCellBoldCenter']),
            Paragraph(result_label, styles['TableCellBoldCenter'])
        ])
        
    grade_table = Table(table_rows, colWidths=[1.4*inch, 2.1*inch, 1.0*inch, 0.6*inch, 0.5*inch, 0.5*inch, 0.5*inch, 0.5*inch])
    grade_table.setStyle(defensys_table_style())
    story.append(grade_table)
    
    # 4. Signatures Block
    defensys_signatures_block(
        story=story,
        prepared_by=generated_by_user,
        noted_by="Academic Department Secretary",
        approved_by="IT Program Chairperson"
    )
    
    # 5. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
