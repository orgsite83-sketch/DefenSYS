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


def generate_audit_trail_pdf(logs, filters_desc, generated_by_user):
    """
    Generate a PDF audit trail compilation for official ISO compliance monitoring.
    
    Args:
        logs: QuerySet of SystemAuditLog objects
        filters_desc: Dictionary of active filter labels and values for context
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
    total_logs = len(logs)
    metadata_rows = [
        ("Total Audit Log Records:", str(total_logs)),
    ]
    if filters_desc:
        for k, v in filters_desc.items():
            metadata_rows.append((f"Filter - {k}:", str(v)))
            
    defensys_cover_page(
        story=story,
        title="ISO 9001:2015 Audit Register",
        subtitle="Portal Security Compliance & System Action Logs",
        generated_by_user=generated_by_user,
        metadata_rows=metadata_rows
    )
    
    # 2. Main Title
    story.append(Paragraph("System Compliance Action Logs", styles['SectionHeader']))
    story.append(Spacer(1, 0.05*inch))
    
    # 3. Log Table
    headers = [
        Paragraph("<b>Date / Time</b>", styles['TableHeader']),
        Paragraph("<b>Process Area</b>", styles['TableHeader']),
        Paragraph("<b>Control Activity</b>", styles['TableHeader']),
        Paragraph("<b>Responsible User</b>", styles['TableHeader']),
        Paragraph("<b>Action Details / Reason</b>", styles['TableHeader']),
    ]
    
    table_rows = [headers]
    for log in logs:
        # Date & Time
        time_str = ""
        if log.created_at:
            # We localize or convert to standard string
            time_str = log.created_at.strftime('%Y-%m-%d %H:%M')
            
        actor_name = log.actor_name if hasattr(log, 'actor_name') else ""
        if not actor_name and log.actor:
            actor_name = log.actor.get_full_name() or log.actor.username
        if not actor_name:
            actor_name = "System"
            
        category_lbl = log.category_label if hasattr(log, 'category_label') else (dict(log.CATEGORY_CHOICES).get(log.category, log.category))
        
        detail_reason = f"<b>Reason:</b> {log.reason or 'None provided'}"
        
        table_rows.append([
            Paragraph(time_str, styles['TableCellBold']),
            Paragraph(category_lbl or "", styles['TableCell']),
            Paragraph(log.action or "", styles['TableCell']),
            Paragraph(actor_name, styles['TableCellBold']),
            Paragraph(detail_reason, styles['TableCell']),
        ])
        
    log_table = Table(table_rows, colWidths=[1.1*inch, 1.2*inch, 1.4*inch, 1.3*inch, 2.5*inch])
    log_table.setStyle(defensys_table_style())
    story.append(log_table)
    
    # 4. Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
