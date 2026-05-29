from io import BytesIO
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.lib import colors

from reports.pdf_styles import (
    defensys_styles,
    defensys_cover_page,
    defensys_table_style,
    NumberedCanvas,
    MAROON,
    GOLD,
    BORDER_GREY,
    BG_LIGHT,
    TEXT_DARK
)


def generate_team_roster_pdf(semester, teams, generated_by_user):
    """
    Generate a PDF roster listing all active teams and their memberships.
    
    Args:
        semester: Semester database object
        teams: QuerySet of StudentTeam objects
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
        leftMargin=0.5*inch,
        rightMargin=0.5*inch
    )
    
    doc.generated_by = generated_by_user
    doc.generated_at = datetime.now().strftime('%Y-%m-%d %I:%M %p')
    
    story = []
    styles = defensys_styles()
    
    # 1. Cover Page
    total_teams = len(teams)
    metadata_rows = [
        ("Academic Period:", f"{semester.school_year.label} — {semester.label}" if semester else "All Semesters"),
        ("Total Student Teams:", str(total_teams)),
    ]
    
    defensys_cover_page(
        story=story,
        title="Team Roster Report",
        subtitle=f"Official Student Team Roster",
        generated_by_user=generated_by_user,
        metadata_rows=metadata_rows
    )
    
    # 2. Main Title
    story.append(Paragraph(f"Academic Student Team Roster", styles['SectionHeader']))
    story.append(Spacer(1, 0.05*inch))
    
    # 3. Roster Table
    headers = [
        Paragraph("<b>Team Name & Project</b>", styles['TableHeader']),
        Paragraph("<b>Level / Year</b>", styles['TableHeader']),
        Paragraph("<b>Leader</b>", styles['TableHeader']),
        Paragraph("<b>Adviser</b>", styles['TableHeader']),
        Paragraph("<b>Team Members</b>", styles['TableHeader']),
    ]
    
    table_rows = [headers]
    for team in teams:
        # Project + Name
        team_info = f"<b>{team.name or 'N/A'}</b><br/><i>{team.project_title or 'Untitled Project'}</i>"
        level_info = f"{team.level or 'N/A'}<br/>{team.year_level or 'N/A'}"
        
        # Leader
        leader_name = team.leader.get_full_name() if team.leader else "None"
        
        # Adviser
        adviser_name = team.adviser.get_full_name() if team.adviser else "Unassigned"
        
        # Members list
        members = []
        for mship in team.memberships.all().select_related('student'):
            if mship.student:
                members.append(mship.student.get_full_name() or mship.student.username)
        members_str = "<br/>".join(members) if members else "No members registered"
        
        table_rows.append([
            Paragraph(team_info, styles['TableCell']),
            Paragraph(level_info, styles['TableCell']),
            Paragraph(leader_name, styles['TableCell']),
            Paragraph(adviser_name, styles['TableCell']),
            Paragraph(members_str, styles['TableCell'])
        ])
        
    roster_table = Table(table_rows, colWidths=[2.2*inch, 1.0*inch, 1.3*inch, 1.3*inch, 1.7*inch])
    roster_table.setStyle(defensys_table_style())
    story.append(roster_table)
    
    # 4. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
