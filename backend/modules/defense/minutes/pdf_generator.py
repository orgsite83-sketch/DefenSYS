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

# DefenSYS brand palette
MAROON = colors.HexColor('#6B1D1D')
MAROON_DARK = colors.HexColor('#4A1212')
GOLD = colors.HexColor('#D4A843')
GOLD_LIGHT = colors.HexColor('#F5E6C8')
TEXT_DARK = colors.HexColor('#1F2937')
TEXT_MUTED = colors.HexColor('#6B7280')
BORDER_LIGHT = colors.HexColor('#E5E7EB')
BG_LIGHT = colors.HexColor('#F9FAFB')


def generate_minutes_pdf(minutes):
    """
    Generates a branded DefenSYS PDF for the completed defense minutes.

    Args:
        minutes: DefenseMinutes object

    Returns:
        bytes: PDF content
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=0.6 * inch,
        bottomMargin=0.6 * inch,
        leftMargin=0.75 * inch,
        rightMargin=0.75 * inch,
    )
    story = []
    styles = getSampleStyleSheet()

    # ── Custom styles ──────────────────────────────────────────────────
    title_style = ParagraphStyle(
        'MinutesTitle',
        parent=styles['Heading1'],
        fontSize=17,
        textColor=MAROON,
        spaceAfter=4,
        spaceBefore=10,
        alignment=TA_CENTER,
        fontName='Helvetica-Bold',
        leading=22,
    )

    subtitle_style = ParagraphStyle(
        'MinutesSubtitle',
        parent=styles['Normal'],
        fontSize=10,
        textColor=TEXT_MUTED,
        spaceAfter=12,
        alignment=TA_CENTER,
        fontName='Helvetica',
    )

    section_heading = ParagraphStyle(
        'SectionHeading',
        parent=styles['Heading2'],
        fontSize=12,
        textColor=MAROON,
        spaceBefore=16,
        spaceAfter=6,
        fontName='Helvetica-Bold',
    )

    body_style = ParagraphStyle(
        'BodyTextCustom',
        parent=styles['Normal'],
        fontSize=10,
        leading=14,
        textColor=TEXT_DARK,
    )

    label_style = ParagraphStyle(
        'LabelStyle',
        parent=styles['Normal'],
        fontSize=9.5,
        textColor=TEXT_MUTED,
        fontName='Helvetica',
    )

    value_style = ParagraphStyle(
        'ValueStyle',
        parent=styles['Normal'],
        fontSize=10,
        textColor=TEXT_DARK,
        fontName='Helvetica-Bold',
    )

    centered_style = ParagraphStyle(
        'CenteredText',
        parent=styles['Normal'],
        alignment=TA_CENTER,
        fontSize=9,
        leading=12,
        textColor=TEXT_DARK,
    )

    role_style = ParagraphStyle(
        'RoleStyle',
        parent=styles['Normal'],
        alignment=TA_CENTER,
        fontSize=8.5,
        textColor=TEXT_MUTED,
        fontName='Helvetica',
    )

    comment_author_style = ParagraphStyle(
        'CommentAuthor',
        parent=styles['Normal'],
        fontSize=10,
        textColor=MAROON,
        fontName='Helvetica-Bold',
        spaceBefore=8,
    )

    comment_body_style = ParagraphStyle(
        'CommentBody',
        parent=styles['Normal'],
        fontSize=10,
        leading=15,
        textColor=TEXT_DARK,
        leftIndent=12,
        spaceBefore=3,
        spaceAfter=8,
    )

    # ── Header with optional logo ──────────────────────────────────────
    logo_path = os.path.join(settings.BASE_DIR, 'static', 'logo-48.png')
    header_parts = []
    if os.path.exists(logo_path):
        try:
            logo = Image(logo_path, width=0.45 * inch, height=0.45 * inch)
            logo.hAlign = 'CENTER'
            header_parts.append(logo)
        except Exception:
            pass

    # Maroon accent bar
    story.append(HRFlowable(
        width='100%', thickness=3, color=MAROON,
        spaceAfter=6, spaceBefore=0,
    ))

    # Title block
    if header_parts:
        story.extend(header_parts)
        story.append(Spacer(1, 0.05 * inch))

    story.append(Paragraph('MINUTES OF DEFENSE', title_style))
    story.append(Paragraph('Capstone Project Defense · Official Record', subtitle_style))

    # Gold accent line
    story.append(HRFlowable(
        width='40%', thickness=1.5, color=GOLD,
        spaceAfter=14, spaceBefore=2,
    ))

    # ── Defense Information ─────────────────────────────────────────────
    comments = list(minutes.panelist_comments.all().order_by('display_order'))
    panelists_str = ', '.join(
        [f"{c.panelist_name_snapshot} ({c.panelist_role_snapshot})" for c in comments]
    ) or 'N/A'

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

    story.append(Paragraph('DEFENSE INFORMATION', section_heading))

    header_data = [
        [Paragraph('Team Name', label_style), Paragraph(minutes.team_name or 'N/A', value_style)],
        [Paragraph('Capstone Project', label_style), Paragraph(minutes.project_title or 'N/A', value_style)],
        [Paragraph('Defense Stage', label_style), Paragraph(minutes.defense_stage_label or 'N/A', value_style)],
        [Paragraph('Date & Time', label_style),
         Paragraph(f"{format_date(minutes.defense_date)} at {format_time(minutes.defense_time)}", value_style)],
        [Paragraph('Room / Venue', label_style), Paragraph(minutes.room or 'N/A', value_style)],
        [Paragraph('Project Adviser', label_style), Paragraph(minutes.adviser_name or 'N/A', value_style)],
        [Paragraph('Panel Members', label_style), Paragraph(panelists_str, body_style)],
        [Paragraph('Documenter', label_style), Paragraph(minutes.documenter_name or 'N/A', value_style)],
    ]

    header_table = Table(header_data, colWidths=[1.6 * inch, 5.4 * inch])
    header_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('LINEBELOW', (0, 0), (-1, -2), 0.5, BORDER_LIGHT),
        ('LINEBELOW', (0, -1), (-1, -1), 1, MAROON),
        ('BACKGROUND', (0, 0), (0, -1), BG_LIGHT),
        ('LEFTPADDING', (0, 0), (0, -1), 8),
    ]))

    story.append(header_table)
    story.append(Spacer(1, 0.25 * inch))

    # ── Panelist Comments ──────────────────────────────────────────────
    story.append(Paragraph('PANELIST COMMENTS & FEEDBACK', section_heading))
    story.append(HRFlowable(
        width='100%', thickness=0.5, color=BORDER_LIGHT,
        spaceAfter=8, spaceBefore=2,
    ))

    for i, comment in enumerate(comments):
        role_tag = comment.panelist_role_snapshot or ''
        name_tag = comment.panelist_name_snapshot or ''

        # Role badge
        role_color = GOLD if role_tag == 'Chair' else TEXT_MUTED
        story.append(Paragraph(
            f'<font color="{role_color.hexval()}">{role_tag}</font>: '
            f'<b>{name_tag}</b>',
            comment_author_style,
        ))

        comments_html = comment.comments.replace('\n', '<br/>') if comment.comments else '<i>No comments recorded.</i>'
        story.append(Paragraph(comments_html, comment_body_style))

        if i < len(comments) - 1:
            story.append(HRFlowable(
                width='90%', thickness=0.4, color=BORDER_LIGHT,
                spaceAfter=4, spaceBefore=4,
            ))

    story.append(Spacer(1, 0.35 * inch))

    # ── Signature Section ──────────────────────────────────────────────
    story.append(Paragraph('SIGNATURES', section_heading))
    story.append(HRFlowable(
        width='100%', thickness=0.5, color=BORDER_LIGHT,
        spaceAfter=12, spaceBefore=2,
    ))

    def get_signature_flowables(user, date_signed, role_label):
        content = []
        has_sig = False
        if user and user.e_signature:
            try:
                sig_path = user.e_signature.path
                if os.path.exists(sig_path):
                    img = Image(sig_path, width=1.4 * inch, height=0.55 * inch)
                    img.hAlign = 'CENTER'
                    content.append(img)
                    has_sig = True
            except Exception:
                pass

        if not has_sig:
            content.append(Spacer(1, 0.55 * inch))

        # Underline
        content.append(HRFlowable(
            width='80%', thickness=0.8, color=MAROON,
            spaceAfter=3, spaceBefore=2,
        ))

        name = user.get_full_name() if user else 'Pending'
        content.append(Paragraph(f'<b>{name}</b>', centered_style))
        content.append(Paragraph(role_label, role_style))

        date_str = date_signed.strftime('%B %d, %Y') if date_signed else ''
        if date_str:
            content.append(Paragraph(
                f'<font color="{TEXT_MUTED.hexval()}">Signed: {date_str}</font>',
                role_style,
            ))
        else:
            content.append(Paragraph(
                '<font color="#DC2626"><i>Pending Signature</i></font>',
                role_style,
            ))

        return content

    doc_flowables = get_signature_flowables(
        minutes.documenter_signed_by, minutes.documenter_signed_at, 'Documenter',
    )
    adv_flowables = get_signature_flowables(
        minutes.adviser_signed_by, minutes.adviser_signed_at, 'Project Adviser',
    )
    chr_flowables = get_signature_flowables(
        minutes.chairman_signed_by, minutes.chairman_signed_at, 'Chairman',
    )

    sig_data = [[doc_flowables, adv_flowables, chr_flowables]]

    sig_table = Table(sig_data, colWidths=[2.3 * inch, 2.3 * inch, 2.3 * inch])
    sig_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 10),
        ('TOPPADDING', (0, 0), (-1, -1), 10),
    ]))

    story.append(sig_table)

    # ── Footer accent bar ──────────────────────────────────────────────
    story.append(Spacer(1, 0.3 * inch))
    story.append(HRFlowable(
        width='100%', thickness=2, color=MAROON,
        spaceAfter=4, spaceBefore=0,
    ))
    story.append(Paragraph(
        '<font color="#9CA3AF" size="7">Generated by DefenSYS — Capstone Defense Management System</font>',
        ParagraphStyle('Footer', parent=styles['Normal'], alignment=TA_CENTER, spaceAfter=0),
    ))

    # Build document
    doc.build(story)
    pdf_content = buffer.getvalue()
    buffer.close()

    return pdf_content
