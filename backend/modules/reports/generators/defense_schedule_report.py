from io import BytesIO
from datetime import datetime, timedelta
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


def generate_defense_schedule_pdf(semester, schedules, generated_by_user):
    """
    Generate a PDF summarizing scheduled defense presentations.
    
    Args:
        semester: Semester database object
        schedules: QuerySet of DefenseSchedule objects
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
    total_slots = len(schedules)
    metadata_rows = [
        ("Academic Period:", f"{semester.school_year.label} — {semester.label}"),
        ("Total Scheduled Presentations:", str(total_slots)),
    ]
    
    defensys_cover_page(
        story=story,
        title="Defense Schedule Summary",
        subtitle=f"Official Defense Schedules List — {semester.school_year.label} {semester.label}",
        generated_by_user=generated_by_user,
        metadata_rows=metadata_rows
    )
    
    # 2. Main Title
    story.append(Paragraph(f"Defense Schedule Register", styles['SectionHeader']))
    story.append(Spacer(1, 0.05*inch))
    
    # 3. Schedule Table
    headers = [
        Paragraph("<b>Date & Time</b>", styles['TableHeader']),
        Paragraph("<b>Room / Venue</b>", styles['TableHeader']),
        Paragraph("<b>Student Team</b>", styles['TableHeader']),
        Paragraph("<b>Defense Stage</b>", styles['TableHeader']),
        Paragraph("<b>Panel Assignments</b>", styles['TableHeader']),
        Paragraph("<b>Status</b>", styles['TableHeader'])
    ]
    
    table_rows = [headers]
    for sched in schedules:
        # Time formatting
        time_str = ""
        if sched.scheduled_date:
            date_part = sched.scheduled_date.strftime('%b %d, %Y')
            start_part = sched.start_time.strftime('%I:%M %p') if sched.start_time else ""
            end_part = ""
            if sched.start_time:
                dummy_dt = datetime.combine(sched.scheduled_date, sched.start_time)
                end_dt = dummy_dt + timedelta(minutes=sched.slot_duration)
                end_part = end_dt.time().strftime('%I:%M %p')
            time_str = f"{date_part}\n{start_part} - {end_part}"
        else:
            time_str = "Unscheduled"
            
        # Panelists formatting
        panelists = []
        for assign in sched.panel_assignments.all().select_related('panelist'):
            if assign.panelist:
                panelists.append(assign.panelist.get_full_name() or assign.panelist.username)
        panel_str = ", ".join(panelists) if panelists else "No panel assigned"
        
        status_label = str(sched.status).upper() if getattr(sched, 'status', None) else "SCHEDULED"
        
        table_rows.append([
            Paragraph(time_str.replace('\n', '<br/>'), styles['TableCellBold']),
            Paragraph(sched.room or "TBA", styles['TableCell']),
            Paragraph(sched.team.name if sched.team else "N/A", styles['TableCellBold']),
            Paragraph(sched.defense_stage.label if sched.defense_stage else (sched.stage_label or "N/A"), styles['TableCell']),
            Paragraph(panel_str, styles['TableCell']),
            Paragraph(status_label, styles['TableCellBold'])
        ])
        
    sched_table = Table(table_rows, colWidths=[1.5*inch, 0.9*inch, 1.3*inch, 1.2*inch, 1.8*inch, 0.8*inch])
    sched_table.setStyle(defensys_table_style())
    story.append(sched_table)
    
    # 4. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
