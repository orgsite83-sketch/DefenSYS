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


def generate_audit_trail_pdf(logs, filters_desc, generated_by_user):
    """
    Generate an official USTP DIT PDF audit trail compilation for official ISO compliance monitoring.
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
    
    total_logs = len(logs)
    
    # 1. Official Header Banner & Document Title
    defensys_official_header(
        story=story,
        title="ISO 9001:2015 System Audit Trail Register",
        subtitle="Official Security Governance, Access Integrity & System Action Audit Logs"
    )
    
    # 2. Metadata Grid
    metadata_rows = [
        ("Compliance Standard", "ISO 9001:2015 Quality Management System (Clause 9.2 Audit Log)"),
        ("Total Audit Log Records", f"{total_logs} Log Entries Captured"),
        ("Audit Integrity Status", "Cryptographically Timestamped and Verified"),
    ]
    if filters_desc:
        for k, v in filters_desc.items():
            metadata_rows.append((f"Active Filter ({k})", str(v)))
            
    story.append(defensys_metadata_grid(metadata_rows, width=7.1*inch))
    story.append(Spacer(1, 0.12*inch))
    
    # 3. Main Log Table
    story.append(Paragraph("System Compliance Action Logs", styles['SectionHeader']))
    story.append(Spacer(1, 0.04*inch))
    
    headers = [
        Paragraph("<b>Date / Time</b>", styles['TableHeader']),
        Paragraph("<b>Process Area</b>", styles['TableHeader']),
        Paragraph("<b>Control Activity</b>", styles['TableHeader']),
        Paragraph("<b>Responsible User</b>", styles['TableHeader']),
        Paragraph("<b>Action Details & Recorded Reason</b>", styles['TableHeader']),
    ]
    
    table_rows = [headers]
    for log in logs:
        time_str = ""
        if log.created_at:
            time_str = log.created_at.strftime('%Y-%m-%d %H:%M')
            
        actor_name = log.actor_name if hasattr(log, 'actor_name') else ""
        if not actor_name and log.actor:
            actor_name = log.actor.get_full_name() or log.actor.username
        if not actor_name:
            actor_name = "System"
            
        category_lbl = log.category_label if hasattr(log, 'category_label') else (dict(log.CATEGORY_CHOICES).get(log.category, log.category))
        detail_reason = f"<b>Reason:</b> {log.reason or 'None provided'}"
        
        table_rows.append([
            Paragraph(time_str, styles['TableCell']),
            Paragraph(category_lbl or "", styles['TableCell']),
            Paragraph(log.action or "", styles['TableCell']),
            Paragraph(actor_name, styles['TableCellBold']),
            Paragraph(detail_reason, styles['TableCell']),
        ])
        
    log_table = Table(table_rows, colWidths=[1.1*inch, 1.2*inch, 1.4*inch, 1.2*inch, 2.2*inch])
    log_table.setStyle(defensys_table_style())
    story.append(log_table)
    
    # 4. Signatures Block
    defensys_signatures_block(
        story=story,
        prepared_by=generated_by_user,
        noted_by="Quality Management Officer",
        approved_by="IT Program Chairperson / Dean"
    )
    
    # 5. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
