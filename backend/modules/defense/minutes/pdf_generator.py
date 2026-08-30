import os
from io import BytesIO
from datetime import datetime
from django.conf import settings
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak, Image, HRFlowable
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT

from reports.pdf_styles import (
    get_official_header_image,
    NumberedCanvas,
    defensys_styles,
    defensys_official_header,
    defensys_metadata_grid,
    defensys_signatures_block,
    defensys_table_style,
)

MAROON = colors.HexColor('#7A110A')
GOLD = colors.HexColor('#D4A843')
TEXT_DARK = colors.HexColor('#1E293B')
TEXT_MUTED = colors.HexColor('#64748B')
BORDER_LIGHT = colors.HexColor('#E2E8F0')
BG_LIGHT = colors.HexColor('#F8FAFC')


def generate_minutes_pdf(minutes):
    """
    Generates an official USTP DIT PDF for the completed defense minutes matching Minutes-Defense-TEMPLATE.pdf.

    Args:
        minutes: DefenseMinutes object

    Returns:
        bytes: PDF content
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
    
    doc.generated_by = minutes.documenter_name or 'Defense Documenter'
    doc.generated_at = datetime.now().strftime('%Y-%m-%d %I:%M %p')
    
    story = []
    styles = defensys_styles()

    # 1. Official Header Banner & Document Title
    defensys_official_header(
        story=story,
        title=f"Project Final Oral Defense Minutes of Team",
        subtitle=f"[{minutes.team_name or 'Student Team'}]"
    )

    # 2. Defense Information Metadata Grid
    def format_time(t):
        if not t:
            return 'N/A'
        if isinstance(t, str):
            return t
        return t.strftime('%I:%M %p')

    def format_date(d):
        if not d:
            return 'N/A'
        if isinstance(d, str):
            return d
        return d.strftime('%B %d, %Y')

    comments = list(minutes.panelist_comments.all().order_by('display_order'))
    panelists_str = ', '.join(
        [f"{c.panelist_name_snapshot} ({c.panelist_role_snapshot})" for c in comments]
    ) or 'N/A'

    metadata_rows = [
        ("Title of Approved Concept", minutes.project_title or 'N/A'),
        ("Date of Defense", format_date(minutes.defense_date)),
        ("Time of Defense", format_time(minutes.defense_time)),
        ("Defense Room / Venue", minutes.room or 'N/A'),
        ("Proponents of Study", minutes.team_name or 'N/A'),
        ("Capstone Adviser", minutes.adviser_name or 'N/A'),
        ("Panel Members", panelists_str),
    ]
    story.append(defensys_metadata_grid(metadata_rows, width=7.1*inch))
    story.append(Spacer(1, 0.12 * inch))

    # 3. Panelist Comments / Suggestions Table
    story.append(Paragraph("PANELIST COMMENTS & SUGGESTIONS", styles['SectionHeader']))
    story.append(Spacer(1, 0.04 * inch))

    comment_headers = [
        Paragraph("<b>PANELIST</b>", styles['TableHeader']),
        Paragraph("<b>COMMENTS / SUGGESTIONS</b>", styles['TableHeader']),
    ]
    
    comment_rows = [comment_headers]
    for c in comments:
        role_tag = f" ({c.panelist_role_snapshot})" if c.panelist_role_snapshot else ""
        panelist_label = f"<b>{c.panelist_name_snapshot or 'Panelist'}</b>{role_tag}"
        comments_html = c.comments.replace('\n', '<br/>') if c.comments else "<i>No specific comments recorded.</i>"
        
        comment_rows.append([
            Paragraph(panelist_label, styles['TableCellBold']),
            Paragraph(comments_html, styles['TableCell']),
        ])

    if len(comment_rows) == 1:
        comment_rows.append([
            Paragraph("Panelists", styles['TableCell']),
            Paragraph("<i>All panelists endorsed the project presentation without major revisions.</i>", styles['TableCell'])
        ])

    comments_table = Table(comment_rows, colWidths=[2.2 * inch, 4.9 * inch])
    comments_table.setStyle(defensys_table_style())
    story.append(comments_table)

    # 4. Certification & Signatures Section
    defensys_signatures_block(
        story=story,
        prepared_by=minutes.documenter_name or "Documenter",
        noted_by=minutes.adviser_name or "Capstone Adviser",
        approved_by="IT Program Chairperson"
    )

    # Build document
    doc.build(story, canvasmaker=NumberedCanvas)
    pdf_content = buffer.getvalue()
    buffer.close()

    return pdf_content
