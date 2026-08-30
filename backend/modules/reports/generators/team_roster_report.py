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


def generate_team_roster_pdf(semester, teams, generated_by_user):
    """
    Generate an official USTP DIT PDF roster listing all active teams and their memberships.
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
    
    total_teams = len(teams)
    
    # 1. Official Header Banner & Document Title
    defensys_official_header(
        story=story,
        title="Student Team Directory & Roster Report",
        subtitle=f"Official Student Project Teams and Membership Registry · {semester.school_year.label if semester else ''} {semester.label if semester else ''}"
    )
    
    # 2. Metadata Grid
    metadata_rows = [
        ("Academic Term / Semester", f"{semester.school_year.label if semester else ''} — {semester.label if semester else ''}"),
        ("Total Active Student Teams", f"{total_teams} Project Teams Registered"),
        ("Program / Department", "Department of Information Technology — Bachelor of Science in Information Technology"),
    ]
    story.append(defensys_metadata_grid(metadata_rows, width=7.1*inch))
    story.append(Spacer(1, 0.12*inch))
    
    # 3. Main Roster Table
    story.append(Paragraph("Academic Student Team Roster", styles['SectionHeader']))
    story.append(Spacer(1, 0.04*inch))
    
    headers = [
        Paragraph("<b>Team Name & Project Title</b>", styles['TableHeader']),
        Paragraph("<b>Section / Year</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Project Leader</b>", styles['TableHeader']),
        Paragraph("<b>Project Adviser</b>", styles['TableHeader']),
        Paragraph("<b>Registered Members</b>", styles['TableHeader']),
    ]
    
    table_rows = [headers]
    for team in teams:
        team_info = f"<b>{team.name or 'N/A'}</b><br/><i>{team.project_title or 'Untitled Project'}</i>"
        level_info = f"{team.section or team.year_level or 'BSIT'}"
        leader_name = team.leader.get_full_name() if team.leader else "Unassigned"
        adviser_name = team.adviser.get_full_name() if team.adviser else "Unassigned"
        
        members = []
        for mship in team.memberships.all().select_related('student'):
            if mship.student:
                members.append(mship.student.get_full_name() or mship.student.username)
        members_str = ", ".join(members) if members else "No members"
        
        table_rows.append([
            Paragraph(team_info, styles['TableCell']),
            Paragraph(level_info, styles['TableCellCenter']),
            Paragraph(leader_name, styles['TableCell']),
            Paragraph(adviser_name, styles['TableCell']),
            Paragraph(members_str, styles['TableCell'])
        ])
        
    roster_table = Table(table_rows, colWidths=[2.2*inch, 0.9*inch, 1.2*inch, 1.2*inch, 1.6*inch])
    roster_table.setStyle(defensys_table_style())
    story.append(roster_table)
    
    # 4. Signatures Block
    defensys_signatures_block(
        story=story,
        prepared_by=generated_by_user,
        noted_by="Capstone Project Coordinator",
        approved_by="IT Program Chairperson"
    )
    
    # 5. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
