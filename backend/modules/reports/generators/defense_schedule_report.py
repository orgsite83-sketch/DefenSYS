from io import BytesIO
from datetime import datetime, timedelta
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


def generate_defense_schedule_pdf(semester, schedules, generated_by_user):
    """
    Generate an official USTP DIT PDF report summarizing scheduled defense presentations.
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
    
    total_slots = len(schedules)
    
    # 1. Official Header Banner & Document Title
    defensys_official_header(
        story=story,
        title="Defense Timetable & Presentation Schedule",
        subtitle=f"Official Defense Sessions & Panel Assignment Registry · {semester.school_year.label if semester else ''} {semester.label if semester else ''}"
    )
    
    # 2. Metadata Grid
    metadata_rows = [
        ("Academic Term / Semester", f"{semester.school_year.label if semester else ''} — {semester.label if semester else ''}"),
        ("Total Scheduled Presentations", f"{total_slots} Defense Sessions"),
        ("Defense Venue / Modality", "Department of Information Technology Defense Rooms / Hybrid"),
    ]
    story.append(defensys_metadata_grid(metadata_rows, width=7.1*inch))
    story.append(Spacer(1, 0.12*inch))
    
    # 3. Main Schedule Table
    story.append(Paragraph("Defense Presentation Schedule Register", styles['SectionHeader']))
    story.append(Spacer(1, 0.04*inch))
    
    headers = [
        Paragraph("<b>Date & Time</b>", styles['TableHeader']),
        Paragraph("<b>Room / Venue</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Student Team</b>", styles['TableHeader']),
        Paragraph("<b>Defense Stage</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Panel Assignments</b>", styles['TableHeader']),
        Paragraph("<b>Status</b>", styles['TableHeaderCenter'])
    ]
    
    table_rows = [headers]
    for sched in schedules:
        time_str = ""
        if sched.scheduled_date:
            date_part = sched.scheduled_date.strftime('%b %d, %Y')
            start_part = sched.start_time.strftime('%I:%M %p') if sched.start_time else ""
            end_part = ""
            if sched.start_time:
                dummy_dt = datetime.combine(sched.scheduled_date, sched.start_time)
                end_dt = dummy_dt + timedelta(minutes=sched.slot_duration)
                end_part = end_dt.time().strftime('%I:%M %p')
            time_str = f"{date_part}<br/>{start_part} - {end_part}"
        else:
            time_str = "Unscheduled"
            
        panelists = []
        for assign in sched.panel_assignments.all().select_related('panelist'):
            if assign.panelist:
                panelists.append(assign.panelist.get_full_name() or assign.panelist.username)
        panel_str = ", ".join(panelists) if panelists else "No panel assigned"
        
        status_label = str(sched.status).upper() if getattr(sched, 'status', None) else "SCHEDULED"
        
        table_rows.append([
            Paragraph(time_str, styles['TableCell']),
            Paragraph(sched.room or "TBA", styles['TableCellCenter']),
            Paragraph(sched.team.name if sched.team else "N/A", styles['TableCellBold']),
            Paragraph(sched.defense_stage.label if sched.defense_stage else (sched.stage_label or "N/A"), styles['TableCellCenter']),
            Paragraph(panel_str, styles['TableCell']),
            Paragraph(status_label, styles['TableCellBoldCenter'])
        ])
        
    sched_table = Table(table_rows, colWidths=[1.4*inch, 0.9*inch, 1.3*inch, 1.1*inch, 1.7*inch, 0.7*inch])
    sched_table.setStyle(defensys_table_style())
    story.append(sched_table)
    
    # 4. Signatures Block
    defensys_signatures_block(
        story=story,
        prepared_by=generated_by_user,
        noted_by="Capstone Defense Coordinator",
        approved_by="IT Program Chairperson"
    )
    
    # 5. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
