from decimal import Decimal
from io import BytesIO
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.lib import colors

from reports.pdf_styles import (
    defensys_styles,
    defensys_cover_page,
    defensys_confidential_callout,
    defensys_table_style,
    NumberedCanvas,
    MAROON,
    GOLD,
    BORDER_GREY,
    BG_LIGHT,
    TEXT_DARK
)


def generate_semester_grades_pdf(semester, grade_records, generated_by_user):
    """
    Generate a PDF summary of all grades for all teams within a given academic semester.
    
    Args:
        semester: Semester database object
        grade_records: QuerySet of TeamGrade objects
        generated_by_user: Username of requestor
        
    Returns:
        bytes: PDF binary content
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.85*inch,
        bottomMargin=0.85*inch,
        leftMargin=0.5*inch, # wider margins for landscape/dense table
        rightMargin=0.5*inch
    )
    
    doc.generated_by = generated_by_user
    doc.generated_at = datetime.now().strftime('%Y-%m-%d %I:%M %p')
    
    story = []
    styles = defensys_styles()
    
    # 1. Compute summary stats
    total_records = len(grade_records)
    passed_count = sum(1 for g in grade_records if g.result == 'passed')
    failed_count = sum(1 for g in grade_records if g.result == 'failed')
    pending_count = sum(1 for g in grade_records if g.result == 'pending')
    
    # Compute average final grade of complete records
    completed_grades = [g.final_grade for g in grade_records if g.final_grade is not None]
    avg_grade = sum(completed_grades) / len(completed_grades) if completed_grades else Decimal('0.00')
    
    # 2. Cover Page
    metadata_rows = [
        ("Academic Year:", semester.school_year.label),
        ("Semester:", semester.label),
        ("Active Status:", "Active" if semester.is_active else "Archived / Inactive"),
        ("Total Graded Entries:", str(total_records)),
        ("Result Summary:", f"Passed: {passed_count}  |  Failed: {failed_count}  |  Pending: {pending_count}"),
        ("Cohort Grade Average:", f"{avg_grade:.2f}%" if completed_grades else "N/A"),
    ]
    
    defensys_cover_page(
        story=story,
        title="Semester Grade Summary",
        subtitle=f"Official Compiled Grade Record — {semester.school_year.label} {semester.label}",
        generated_by_user=generated_by_user,
        metadata_rows=metadata_rows
    )
    
    # 3. Warning callout
    story.append(defensys_confidential_callout())
    story.append(Spacer(1, 0.25*inch))
    
    # 4. Main Grade Sheet Table
    story.append(Paragraph("Student Teams Grade Register", styles['SectionHeader']))
    story.append(Spacer(1, 0.05*inch))
    
    headers = [
        Paragraph("<b>Team Name</b>", styles['TableHeader']),
        Paragraph("<b>Project Title</b>", styles['TableHeader']),
        Paragraph("<b>Stage</b>", styles['TableHeader']),
        Paragraph("<b>Panel</b>", styles['TableHeader']),
        Paragraph("<b>Adviser</b>", styles['TableHeader']),
        Paragraph("<b>Peer</b>", styles['TableHeader']),
        Paragraph("<b>Final</b>", styles['TableHeader']),
        Paragraph("<b>Result</b>", styles['TableHeader'])
    ]
    
    table_rows = [headers]
    for gr in grade_records:
        # Format scores safely
        p_score = f"{gr.panel_score:.1f}" if gr.panel_score is not None else "-"
        a_score = f"{gr.adviser_score:.1f}" if (gr.adviser_score is not None and gr.adviser_weight > 0) else "-"
        peer_score = f"{gr.peer_score:.1f}" if gr.peer_score is not None else "-"
        f_grade = f"{gr.final_grade:.2f}%" if gr.final_grade is not None else "Pending"
        
        result_label = gr.result.upper() if gr.final_grade is not None else "PENDING"
        
        # Styles for the result text
        if result_label == "PASSED":
            res_style = styles['TableCellBold']
        elif result_label == "FAILED":
            res_style = ParagraphStyle('FailLabel', parent=styles['TableCellBold'], textColor=colors.HexColor('#DC2626'))
        else:
            res_style = styles['TableCell']
            
        table_rows.append([
            Paragraph(gr.team.name or "N/A", styles['TableCellBold']),
            Paragraph(gr.team.project_title or "N/A", styles['TableCell']),
            Paragraph(gr.stage_label or "N/A", styles['TableCell']),
            Paragraph(p_score, styles['TableCell']),
            Paragraph(a_score, styles['TableCell']),
            Paragraph(peer_score, styles['TableCell']),
            Paragraph(f_grade, styles['TableCellBold']),
            Paragraph(result_label, res_style)
        ])
        
    # Full printable width is 7.5 inches
    grade_table = Table(table_rows, colWidths=[1.3*inch, 2.1*inch, 1.2*inch, 0.5*inch, 0.6*inch, 0.5*inch, 0.7*inch, 0.6*inch])
    grade_table.setStyle(defensys_table_style())
    story.append(grade_table)
    
    # 5. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
