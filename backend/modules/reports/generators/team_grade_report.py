from decimal import Decimal
from io import BytesIO
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak, KeepTogether
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


def generate_team_grade_pdf(team_grade, generated_by_user):
    """
    Generate a PDF report card detailing a team's grades and assessment breakdown.
    
    Args:
        team_grade: TeamGrade database object
        generated_by_user: Username of the requestor
        
    Returns:
        bytes: PDF binary content
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.85*inch, # generous margins to clear NumberedCanvas headers/footers
        bottomMargin=0.85*inch,
        leftMargin=0.75*inch,
        rightMargin=0.75*inch
    )
    
    # Track metadata on doc template for the canvas footer
    doc.generated_by = generated_by_user
    doc.generated_at = datetime.now().strftime('%Y-%m-%d %I:%M %p')
    
    story = []
    styles = defensys_styles()
    
    # 1. Cover Page
    team = team_grade.team
    semester = team_grade.semester
    
    metadata_rows = [
        ("Academic Period:", f"{semester.school_year.label} — {semester.label}"),
        ("Team Name:", team.name or "N/A"),
        ("Project Title:", team.project_title or "N/A"),
        ("Course / Year Level:", f"{team.level or 'N/A'} — {team.year_level or 'N/A'}"),
        ("Capstone Stage:", team_grade.stage_label or "N/A"),
        ("Project Adviser:", f"{team.adviser.first_name} {team.adviser.last_name}".strip() if team.adviser else "N/A"),
    ]
    
    defensys_cover_page(
        story=story,
        title="Team Grade Report Card",
        subtitle=f"Official Defense & Evaluation Breakdown — {team_grade.stage_label}",
        generated_by_user=generated_by_user,
        metadata_rows=metadata_rows
    )
    
    # 2. Main Page Header & Warning callout
    story.append(defensys_confidential_callout())
    story.append(Spacer(1, 0.25*inch))
    
    # 3. Overall Grade Summary
    story.append(Paragraph("Overall Grade Summary", styles['SectionHeader']))
    story.append(Spacer(1, 0.05*inch))
    
    def format_score(val):
        return f"{val:.2f}%" if val is not None else "Pending"
        
    summary_data = [
        [
            Paragraph("<b>Component</b>", styles['TableHeader']),
            Paragraph("<b>Weight</b>", styles['TableHeader']),
            Paragraph("<b>Score</b>", styles['TableHeader']),
            Paragraph("<b>Weighted Value</b>", styles['TableHeader'])
        ]
    ]
    
    # Component 1: Panel
    panel_val = (team_grade.panel_score * Decimal(team_grade.panel_weight) / Decimal('100')).quantize(Decimal('0.01')) if team_grade.panel_score is not None else None
    summary_data.append([
        Paragraph("Panel Defense Grade", styles['TableCell']),
        Paragraph(f"{team_grade.panel_weight}%", styles['TableCell']),
        Paragraph(format_score(team_grade.panel_score), styles['TableCell']),
        Paragraph(format_score(panel_val), styles['TableCell'])
    ])
    
    # Component 2: Adviser (only capstone scope has advisers usually)
    if team_grade.is_capstone and team_grade.adviser_weight > 0:
        adviser_val = (team_grade.adviser_score * Decimal(team_grade.adviser_weight) / Decimal('100')).quantize(Decimal('0.01')) if team_grade.adviser_score is not None else None
        summary_data.append([
            Paragraph("Project Adviser Grade", styles['TableCell']),
            Paragraph(f"{team_grade.adviser_weight}%", styles['TableCell']),
            Paragraph(format_score(team_grade.adviser_score), styles['TableCell']),
            Paragraph(format_score(adviser_val), styles['TableCell'])
        ])
        
    # Component 3: Peer Evaluation
    peer_val = (team_grade.peer_score * Decimal(team_grade.peer_weight) / Decimal('100')).quantize(Decimal('0.01')) if team_grade.peer_score is not None else None
    summary_data.append([
        Paragraph("Student Peer Evaluation", styles['TableCell']),
        Paragraph(f"{team_grade.peer_weight}%", styles['TableCell']),
        Paragraph(format_score(team_grade.peer_score), styles['TableCell']),
        Paragraph(format_score(peer_val), styles['TableCell'])
    ])
    
    # Final row
    result_text = team_grade.result.upper() if team_grade.final_grade is not None else "PENDING"
    summary_data.append([
        Paragraph("<b>FINAL COURSE GRADE</b>", styles['TableCellBold']),
        Paragraph("<b>100%</b>", styles['TableCellBold']),
        Paragraph(f"<b>{format_score(team_grade.final_grade)}</b>", styles['TableCellBold']),
        Paragraph(f"<b>Status: {result_text}</b>", styles['TableCellBold'])
    ])
    
    summary_table = Table(summary_data, colWidths=[2.5*inch, 1.2*inch, 1.5*inch, 1.8*inch])
    summary_table.setStyle(defensys_table_style())
    story.append(summary_table)
    story.append(Spacer(1, 0.3*inch))
    
    # 4. Detailed Panelist Scores Breakdown
    submissions = list(team_grade.panelist_submissions.all().prefetch_related('criterion_scores'))
    if submissions:
        story.append(Paragraph("Detailed Panelist Defense Assessments", styles['SectionHeader']))
        story.append(Spacer(1, 0.05*inch))
        
        # Build headers
        headers = [Paragraph("<b>Criterion / Skill</b>", styles['TableHeader'])]
        for idx, sub in enumerate(submissions):
            name = sub.panelist.get_full_name() if sub.panelist else sub.guest_name
            if not name:
                name = f"Panelist {idx + 1}"
            headers.append(Paragraph(f"<b>{name}</b>", styles['TableHeader']))
        headers.append(Paragraph("<b>Normalized Avg</b>", styles['TableHeader']))
        
        # Gather criterion matrix
        criteria_map = {}
        for sub in submissions:
            for score in sub.criterion_scores.all():
                crit_name = score.criterion_name_snapshot
                if crit_name not in criteria_map:
                    criteria_map[crit_name] = []
                criteria_map[crit_name].append(score)
                
        grid_data = [headers]
        
        for crit_name, scores in criteria_map.items():
            row = [Paragraph(crit_name, styles['TableCell'])]
            tot_normal = Decimal('0.00')
            count = 0
            
            for sub in submissions:
                # Find score for this panelist for this criterion
                sub_score = next((s for s in scores if s.submission_id == sub.id), None)
                if sub_score is not None:
                    row.append(Paragraph(f"{sub_score.score:.1f} / {sub_score.max_score_snapshot:.1f}", styles['TableCell']))
                    tot_normal += sub_score.normalized_score
                    count += 1
                else:
                    row.append(Paragraph("-", styles['TableCell']))
                    
            if count > 0:
                avg_pct = (tot_normal / Decimal(count)).quantize(Decimal('0.01'))
                row.append(Paragraph(f"<b>{avg_pct:.2f}%</b>", styles['TableCellBold']))
            else:
                row.append(Paragraph("-", styles['TableCellBold']))
                
            grid_data.append(row)
            
        # Dynamically distribute column widths
        col_width = 4.5 * inch / max(len(submissions), 1)
        widths = [2.5*inch] + [col_width]*len(submissions) + [1.2*inch]
        
        grid_table = Table(grid_data, colWidths=widths)
        grid_table.setStyle(defensys_table_style())
        story.append(grid_table)
        story.append(Spacer(1, 0.3*inch))
        
    # 5. Peer Evaluation Breakdown
    peer_grades = list(team_grade.student_grades.all().select_related('student'))
    if peer_grades:
        story.append(Paragraph("Individual Peer Evaluation Summaries", styles['SectionHeader']))
        story.append(Spacer(1, 0.05*inch))
        
        peer_headers = [
            Paragraph("<b>Student Name</b>", styles['TableHeader']),
            Paragraph("<b>Normalized Peer Grade</b>", styles['TableHeader'])
        ]
        
        peer_rows = [peer_headers]
        for pg in peer_grades:
            peer_rows.append([
                Paragraph(pg.student.get_full_name() or pg.student.username, styles['TableCell']),
                Paragraph(f"<b>{pg.peer_score:.2f}%</b>" if pg.peer_score is not None else "Pending", styles['TableCellBold'])
            ])
            
        peer_table = Table(peer_rows, colWidths=[4.0*inch, 3.0*inch])
        peer_table.setStyle(defensys_table_style())
        story.append(peer_table)
        story.append(Spacer(1, 0.3*inch))
        
    # Build document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
