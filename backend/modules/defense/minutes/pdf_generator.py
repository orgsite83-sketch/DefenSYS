import os
from io import BytesIO
from datetime import datetime
from django.conf import settings
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak, Image
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT

def generate_minutes_pdf(minutes):
    """
    Generates a PDF for the completed defense minutes.
    
    Args:
        minutes: DefenseMinutes object
        
    Returns:
        bytes: PDF content
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.75*inch,
        bottomMargin=0.75*inch,
        leftMargin=0.75*inch,
        rightMargin=0.75*inch
    )
    story = []
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'MinutesTitle',
        parent=styles['Heading1'],
        fontSize=18,
        textColor=colors.HexColor('#1E3A8A'), # Sleek dark blue
        spaceAfter=15,
        alignment=TA_CENTER,
        fontName='Helvetica-Bold',
    )
    
    section_heading = ParagraphStyle(
        'SectionHeading',
        parent=styles['Heading2'],
        fontSize=12,
        textColor=colors.HexColor('#1E3A8A'),
        spaceBefore=12,
        spaceAfter=6,
        fontName='Helvetica-Bold',
    )
    
    body_style = ParagraphStyle(
        'BodyTextCustom',
        parent=styles['Normal'],
        fontSize=10,
        leading=14,
    )
    
    centered_style = ParagraphStyle(
        'CenteredText',
        parent=styles['Normal'],
        alignment=TA_CENTER,
        fontSize=9,
        leading=12,
    )
    
    # Title
    story.append(Paragraph('CAPSTONE DEFENSE MINUTES', title_style))
    story.append(Spacer(1, 0.1*inch))
    
    # Header metadata table
    comments = list(minutes.panelist_comments.all().order_by('display_order'))
    panelists_str = ", ".join([f"{c.panelist_name_snapshot} ({c.panelist_role_snapshot})" for c in comments]) or 'N/A'
    
    # Dates formatting
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

    header_data = [
        [Paragraph('<b>Team Name:</b>', body_style), Paragraph(minutes.team_name or 'N/A', body_style)],
        [Paragraph('<b>Project Title:</b>', body_style), Paragraph(minutes.project_title or 'N/A', body_style)],
        [Paragraph('<b>Defense Stage:</b>', body_style), Paragraph(minutes.defense_stage_label or 'N/A', body_style)],
        [Paragraph('<b>Date & Time:</b>', body_style), Paragraph(f"{format_date(minutes.defense_date)} at {format_time(minutes.defense_time)}", body_style)],
        [Paragraph('<b>Room / Venue:</b>', body_style), Paragraph(minutes.room or 'N/A', body_style)],
        [Paragraph('<b>Adviser:</b>', body_style), Paragraph(minutes.adviser_name or 'N/A', body_style)],
        [Paragraph('<b>Panel Members:</b>', body_style), Paragraph(panelists_str, body_style)],
        [Paragraph('<b>Documenter:</b>', body_style), Paragraph(minutes.documenter_name or 'N/A', body_style)],
    ]
    
    header_table = Table(header_data, colWidths=[1.8*inch, 5.2*inch])
    header_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('LINEBELOW', (0, -1), (-1, -1), 1, colors.HexColor('#CBD5E1')),
    ]))
    
    story.append(header_table)
    story.append(Spacer(1, 0.2*inch))
    
    # Panelist Comments Section
    story.append(Paragraph('PANELIST COMMENTS AND FEEDBACK', section_heading))
    
    for comment in comments:
        story.append(Paragraph(f"<b>{comment.panelist_role_snapshot}: {comment.panelist_name_snapshot}</b>", body_style))
        story.append(Spacer(1, 0.03*inch))
        comments_html = comment.comments.replace('\n', '<br/>') if comment.comments else 'No comments recorded.'
        story.append(Paragraph(comments_html, body_style))
        story.append(Spacer(1, 0.15*inch))
        
    story.append(Spacer(1, 0.3*inch))
    
    # Signature flowables helper
    def get_signature_flowables(user, date_signed, role_label):
        content = []
        has_sig = False
        if user and user.e_signature:
            try:
                sig_path = user.e_signature.path
                if os.path.exists(sig_path):
                    img = Image(sig_path, width=1.5*inch, height=0.6*inch)
                    img.hAlign = 'CENTER'
                    content.append(img)
                    has_sig = True
            except Exception:
                pass
                
        if not has_sig:
            content.append(Spacer(1, 0.6*inch))
            
        name = user.get_full_name() if user else 'Unknown'
        content.append(Paragraph(f"<b>{name}</b>", centered_style))
        content.append(Paragraph(role_label, centered_style))
        
        date_str = date_signed.strftime("%B %d, %Y") if date_signed else ""
        if date_str:
            content.append(Paragraph(f"Signed: {date_str}", centered_style))
        else:
            content.append(Paragraph("Pending Signature", centered_style))
            
        return content

    # Signatures Table
    doc_flowables = get_signature_flowables(minutes.documenter_signed_by, minutes.documenter_signed_at, "Documenter")
    adv_flowables = get_signature_flowables(minutes.adviser_signed_by, minutes.adviser_signed_at, "Adviser")
    chr_flowables = get_signature_flowables(minutes.chairman_signed_by, minutes.chairman_signed_at, "Chairman")
    
    sig_data = [
        [doc_flowables, adv_flowables, chr_flowables]
    ]
    
    sig_table = Table(sig_data, colWidths=[2.3*inch, 2.3*inch, 2.3*inch])
    sig_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 10),
        ('TOPPADDING', (0, 0), (-1, -1), 10),
    ]))
    
    story.append(sig_table)
    
    # Build document
    doc.build(story)
    pdf_content = buffer.getvalue()
    buffer.close()
    
    return pdf_content
