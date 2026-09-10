import os
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, Spacer, Table, TableStyle, Image, PageBreak, HRFlowable, KeepTogether
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.pdfgen import canvas

# Institutional Branding Colors
MAROON = colors.HexColor('#7A110A')
MAROON_DARK = colors.HexColor('#540B06')
MAROON_LIGHT = colors.HexColor('#991B1B')
GOLD = colors.HexColor('#D4A843')
GOLD_DARK = colors.HexColor('#B8860B')
TEXT_DARK = colors.HexColor('#1E293B')
TEXT_MUTED = colors.HexColor('#64748B')
BG_LIGHT = colors.HexColor('#F8FAFC')
BORDER_GREY = colors.HexColor('#E2E8F0')
RED_WARNING_BG = colors.HexColor('#FEF2F2')
RED_WARNING_BORDER = colors.HexColor('#FCA5A5')
RED_WARNING_TEXT = colors.HexColor('#991B1B')


def _find_asset_path(filename):
    """
    Search multiple candidate locations for an asset file.
    """
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    candidates = [
        os.path.join(base_dir, 'modules', 'reports', 'assets', filename),
        os.path.join(base_dir, 'static', 'template', filename),
        os.path.join(base_dir, '..', 'frontend', 'assets', 'template', 'Minutes-Defense-TEMPLATE_files', filename),
        os.path.join(base_dir, '..', 'frontend', 'assets', filename),
    ]
    for p in candidates:
        abs_p = os.path.abspath(p)
        if os.path.exists(abs_p):
            return abs_p
    return None


def get_official_header_image(width=7.1*inch, height=None):
    """
    Returns the official USTP Department of Information Technology Header Banner (ustp_header_banner.png / image003.png).
    """
    header_path = _find_asset_path('ustp_header_banner.png') or _find_asset_path('image003.png')
    if header_path:
        try:
            if height is None:
                # True aspect ratio of the official trimmed header banner (2448 x 392)
                height = width * (392.0 / 2448.0)
            img = Image(header_path, width=width, height=height)
            img.hAlign = 'CENTER'
            return img
        except Exception:
            pass

    # Fallback institutional header block
    fallback_data = [
        [
            Paragraph(
                "<font size=8 color='#64748B'>REPUBLIC OF THE PHILIPPINES</font><br/>"
                "<font size=11 color='#7A110A'><b>UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES</b></font><br/>"
                "<font size=12 color='#1E293B'><b>Department of Information Technology</b></font><br/>"
                "<font size=7.5 color='#64748B'>P-6, Mobod, Oroquieta City, Misamis Occidental 7207 • ustporoquieta.bsit@ustp.edu.ph</font>",
                ParagraphStyle('FallbackHdr', alignment=TA_CENTER, leading=13)
            )
        ]
    ]
    fb_table = Table(fallback_data, colWidths=[width])
    fb_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('TOPPADDING', (0, 0), (-1, -1), 6),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ('LINEBELOW', (0, 0), (-1, -1), 1.8, GOLD),
    ]))
    return fb_table


def get_official_footer_image(width=1.2*inch, height=0.56*inch):
    """
    Returns the official OROQUIETA Campus footer badge (image005.png).
    """
    footer_path = _find_asset_path('image005.png')
    if footer_path:
        try:
            return Image(footer_path, width=width, height=height)
        except Exception:
            pass
    return None


class NumberedCanvas(canvas.Canvas):
    """
    Two-pass canvas to dynamically compute and draw 'Page X of Y' 
    along with official campus footer branding and user attribution.
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_decorations(num_pages)
            super().showPage()
        super().save()

    def draw_page_decorations(self, page_count):
        self.saveState()
        page_w = getattr(self, '_pagesize', (612, 792))[0]
        page_h = getattr(self, '_pagesize', (612, 792))[1]
        doc = getattr(self, '_doctemplate', None)
        show_sidebar = getattr(self, '_show_sidebar', getattr(doc, 'show_sidebar', False))
        draw_canvas_header = getattr(self, '_draw_canvas_header', getattr(doc, 'draw_canvas_header', True))

        # 1. Official Header Banner & Left Sidebar on Every Page (Edge-to-Edge Full Bleed)
        if draw_canvas_header:
            banner_path = _find_asset_path('ustp_header_banner.png') or _find_asset_path('image003.png')
            banner_h = page_w * (400.0 / 2448.0)
            if banner_path:
                self.drawImage(banner_path, 0, page_h - banner_h, width=page_w, height=banner_h, mask='auto')
            else:
                top_y = page_h - 30
                self.setFont("Times-Bold", 8)
                self.setFillColor(colors.black)
                self.drawString(28, top_y, "UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES")
                self.setFont("Times-Roman", 8)
                self.setFillColor(colors.HexColor('#374151'))
                self.drawRightString(page_w - 28, top_y, "Department of Information Technology — Oroquieta Campus")
                self.setStrokeColor(BORDER_GREY)
                self.setLineWidth(0.5)
                self.line(28, top_y - 7, page_w - 28, top_y - 7)

            # Vision / Mission / Quality Policy Left Sidebar (image004.png) on every page
            if show_sidebar:
                side_path = _find_asset_path('ustp_sidebar.png') or _find_asset_path('image004.png')
                if side_path:
                    sb_w = 1.30 * inch
                    sb_h = sb_w * (1726.0 / 421.0)
                    sb_x = 24
                    sb_y = page_h - banner_h - sb_h - 10
                    self.drawImage(side_path, sb_x, sb_y, width=sb_w, height=sb_h, mask='auto')
        elif self._pageNumber > 1:
            # Fallback running header on Page 2+ if canvas header banner is explicitly disabled
            top_y = page_h - 30
            self.setFont("Times-Bold", 8)
            self.setFillColor(colors.black)
            self.drawString(28, top_y, "UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES")
            self.setFont("Times-Roman", 8)
            self.setFillColor(colors.HexColor('#374151'))
            self.drawRightString(page_w - 28, top_y, "Department of Information Technology — Oroquieta Campus")
            
            self.setStrokeColor(BORDER_GREY)
            self.setLineWidth(0.5)
            self.line(28, top_y - 7, page_w - 28, top_y - 7)

        # 2. Bottom Footer on all pages
        generated_by = getattr(doc, 'generated_by', 'System Administrator')
        generated_at = getattr(doc, 'generated_at', datetime.now().strftime('%Y-%m-%d %I:%M %p'))
        
        # Gold rule line across entire page width
        self.setStrokeColor(GOLD)
        self.setLineWidth(0.9)
        self.line(0, 34, page_w, 34)
        
        # Campus badge on bottom left (image005.png)
        footer_img_path = _find_asset_path('ustp_footer_badge.png') or _find_asset_path('image005.png')
        if footer_img_path:
            try:
                self.drawImage(footer_img_path, 22, 10, width=64, height=27, preserveAspectRatio=True, mask='auto')
            except Exception:
                self.setFont("Times-Bold", 8)
                self.setFillColor(colors.black)
                self.drawString(22, 20, "USTP OROQUIETA CAMPUS")
        else:
            self.setFont("Times-Bold", 8)
            self.setFillColor(colors.black)
            self.drawString(22, 20, "USTP OROQUIETA CAMPUS")
            
        # Accountability text in center
        self.setFont("Times-Roman", 7.5)
        self.setFillColor(colors.HexColor('#4B5563'))
        self.drawCentredString(page_w / 2.0, 18, f"Official Record · Generated by: {generated_by} · {generated_at}")
        
        # Page count on bottom right
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.setFont("Times-Bold", 8)
        self.setFillColor(colors.black)
        self.drawRightString(page_w - 24, 18, page_str)
        
        self.restoreState()


def defensys_styles():
    """
    Return custom stylesheet extensions for official DefenSYS institutional report layout using Times New Roman.
    """
    styles = getSampleStyleSheet()
    
    report_styles = {
        'ReportTitle': ParagraphStyle(
            'ReportTitle',
            parent=styles['Heading1'],
            fontName='Times-Bold',
            fontSize=13.5,
            textColor=colors.black,
            alignment=TA_CENTER,
            spaceBefore=4,
            spaceAfter=2,
            leading=17,
        ),
        'ReportSubtitle': ParagraphStyle(
            'ReportSubtitle',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=10,
            textColor=colors.HexColor('#1F2937'),
            alignment=TA_CENTER,
            spaceAfter=8,
            leading=13,
        ),
        'SectionHeader': ParagraphStyle(
            'SectionHeader',
            parent=styles['Heading2'],
            fontName='Times-Bold',
            fontSize=10.5,
            textColor=colors.black,
            spaceBefore=8,
            spaceAfter=3,
            leading=13,
            keepWithNext=True,
        ),
        'SubSectionHeader': ParagraphStyle(
            'SubSectionHeader',
            parent=styles['Heading3'],
            fontName='Times-Bold',
            fontSize=9.5,
            textColor=colors.black,
            spaceBefore=6,
            spaceAfter=2,
            leading=12,
            keepWithNext=True,
        ),
        'BodyDark': ParagraphStyle(
            'BodyDark',
            parent=styles['Normal'],
            fontName='Times-Roman',
            fontSize=9,
            textColor=colors.black,
            leading=12,
        ),
        'BodyDarkBold': ParagraphStyle(
            'BodyDarkBold',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=9,
            textColor=colors.black,
            leading=12,
        ),
        'BodyMuted': ParagraphStyle(
            'BodyMuted',
            parent=styles['Normal'],
            fontName='Times-Italic',
            fontSize=8.5,
            textColor=colors.HexColor('#4B5563'),
            leading=11,
        ),
        'TableHeader': ParagraphStyle(
            'TableHeader',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=8.5,
            textColor=colors.black,
            alignment=TA_LEFT,
            leading=11,
        ),
        'TableHeaderCenter': ParagraphStyle(
            'TableHeaderCenter',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=8.5,
            textColor=colors.black,
            alignment=TA_CENTER,
            leading=11,
        ),
        'TableCell': ParagraphStyle(
            'TableCell',
            parent=styles['Normal'],
            fontName='Times-Roman',
            fontSize=8.5,
            textColor=colors.black,
            leading=11,
        ),
        'TableCellCenter': ParagraphStyle(
            'TableCellCenter',
            parent=styles['Normal'],
            fontName='Times-Roman',
            fontSize=8.5,
            textColor=colors.black,
            alignment=TA_CENTER,
            leading=11,
        ),
        'TableCellBold': ParagraphStyle(
            'TableCellBold',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=8.5,
            textColor=colors.black,
            leading=11,
        ),
        'TableCellBoldCenter': ParagraphStyle(
            'TableCellBoldCenter',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=8.5,
            textColor=colors.black,
            alignment=TA_CENTER,
            leading=11,
        ),
        'MetaLabel': ParagraphStyle(
            'MetaLabel',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=9,
            textColor=colors.black,
            leading=12,
        ),
        'MetaVal': ParagraphStyle(
            'MetaVal',
            parent=styles['Normal'],
            fontName='Times-Roman',
            fontSize=9,
            textColor=colors.black,
            leading=12,
        ),
        'SigName': ParagraphStyle(
            'SigName',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=9.5,
            textColor=colors.black,
            alignment=TA_CENTER,
            leading=12,
        ),
        'SigRole': ParagraphStyle(
            'SigRole',
            parent=styles['Normal'],
            fontName='Times-Roman',
            fontSize=8.5,
            textColor=colors.HexColor('#374151'),
            alignment=TA_CENTER,
            leading=11,
        ),
        'WarningText': ParagraphStyle(
            'WarningText',
            parent=styles['Normal'],
            fontName='Times-Bold',
            fontSize=8.5,
            textColor=RED_WARNING_TEXT,
            alignment=TA_CENTER,
            leading=11,
        ),
        'WarningSubtext': ParagraphStyle(
            'WarningSubtext',
            parent=styles['Normal'],
            fontName='Times-Roman',
            fontSize=7.5,
            textColor=RED_WARNING_TEXT,
            alignment=TA_CENTER,
            spaceBefore=1.5,
            leading=10,
        ),
    }
    
    for key, value in report_styles.items():
        if key not in styles:
            styles.add(value)
            
    return styles


def defensys_official_header(story, title, subtitle=None):
    """
    Renders the official school header banner (image003.png) followed by the centered document title.
    """
    styles = defensys_styles()
    
    # 1. Official Header Banner Image
    header_img = get_official_header_image(width=6.9*inch, height=1.28*inch)
    story.append(header_img)
    story.append(Spacer(1, 0.05*inch))
    
    # 2. Document Title
    story.append(Paragraph(title.upper(), styles['ReportTitle']))
    if subtitle:
        story.append(Paragraph(subtitle, styles['ReportSubtitle']))
    else:
        story.append(Spacer(1, 0.04*inch))


def defensys_metadata_grid(metadata_pairs, width=6.9*inch):
    """
    Renders a clean 2-column key-value metadata block matching the official university template.
    """
    styles = defensys_styles()
    table_data = []
    
    for item in metadata_pairs:
        label = item[0]
        val = item[1]
        table_data.append([
            Paragraph(f"<b>{label}</b>", styles['MetaLabel']),
            Paragraph(f": {val}", styles['MetaVal'])
        ])
        
    t = Table(table_data, colWidths=[2.0*inch, width - 2.0*inch])
    t.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('TOPPADDING', (0, 0), (-1, -1), 2),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 2),
        ('LEFTPADDING', (0, 0), (-1, -1), 3.5),
        ('RIGHTPADDING', (0, 0), (-1, -1), 3.5),
        ('BACKGROUND', (0, 0), (-1, -1), BG_LIGHT),
        ('BOX', (0, 0), (-1, -1), 0.5, BORDER_GREY),
        ('INNERGRID', (0, 0), (-1, -1), 0.3, BORDER_GREY),
    ]))
    return t


def defensys_signatures_block(story, prepared_by="System Administrator", noted_by="Capstone Adviser / Panel Chair", approved_by="IT Program Chairperson"):
    """
    Renders the official university 3-column signature block at the bottom of the report.
    """
    styles = defensys_styles()
    
    sig_elements = []
    sig_elements.append(Spacer(1, 0.10*inch))
    
    # Institutional Certification Box
    cert_text = Paragraph(
        "<i>I hereby certify that the above statements and computational evaluation scores are true and correct to the best of my ability, and I further certify the official accuracy of the foregoing academic defense records.</i>",
        styles['BodyDark']
    )
    cert_table = Table([[cert_text]], colWidths=[6.9*inch])
    cert_table.setStyle(TableStyle([
        ('BOX', (0, 0), (-1, -1), 0.7, TEXT_DARK),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 7),
        ('RIGHTPADDING', (0, 0), (-1, -1), 7),
        ('BACKGROUND', (0, 0), (-1, -1), BG_LIGHT),
    ]))
    sig_elements.append(cert_table)
    sig_elements.append(Spacer(1, 0.12*inch))
    
    # 3 Signatures: Prepared by, Noted by, Approved by
    sig_data = [
        [
            Paragraph("Prepared by:", styles['BodyDark']),
            Paragraph("Noted by:", styles['BodyDark']),
            Paragraph("Approved by:", styles['BodyDark']),
        ],
        [
            Spacer(1, 0.30*inch),
            Spacer(1, 0.30*inch),
            Spacer(1, 0.30*inch),
        ],
        [
            Paragraph(f"<b>{prepared_by}</b>", styles['SigName']),
            Paragraph(f"<b>{noted_by}</b>", styles['SigName']),
            Paragraph(f"<b>{approved_by}</b>", styles['SigName']),
        ],
        [
            Paragraph("Documenter / Evaluator", styles['SigRole']),
            Paragraph("Capstone Adviser / Panel Chair", styles['SigRole']),
            Paragraph("IT Program Chairperson", styles['SigRole']),
        ]
    ]
    
    sig_table = Table(sig_data, colWidths=[2.3*inch, 2.3*inch, 2.3*inch])
    sig_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LINEBELOW', (0, 1), (0, 1), 0.7, TEXT_DARK),
        ('LINEBELOW', (1, 1), (1, 1), 0.7, TEXT_DARK),
        ('LINEBELOW', (2, 1), (2, 1), 0.7, TEXT_DARK),
        ('TOPPADDING', (0, 0), (-1, -1), 1.5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 1.5),
        ('LEFTPADDING', (0, 0), (-1, -1), 3),
        ('RIGHTPADDING', (0, 0), (-1, -1), 3),
    ]))
    sig_elements.append(sig_table)
    
    story.append(KeepTogether(sig_elements))


def defensys_confidential_callout():
    """
    Renders a compact confidential notice banner.
    """
    styles = defensys_styles()
    
    content = [
        Paragraph("CONFIDENTIAL: OFFICIAL ACADEMIC EVALUATION RECORD", styles['WarningText']),
        Paragraph("This document contains certified academic evaluation data. Unauthorized reproduction is strictly prohibited.", styles['WarningSubtext'])
    ]
    
    callout_table = Table([[content]], colWidths=[6.9*inch])
    callout_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), RED_WARNING_BG),
        ('BOX', (0, 0), (-1, -1), 0.7, RED_WARNING_BORDER),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 7),
        ('RIGHTPADDING', (0, 0), (-1, -1), 7),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ]))
    return callout_table


def defensys_table_style():
    """
    Standard professional academic tabular layout theme with subtle grey headers and clean borders.
    """
    return TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#F3F4F6')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.black),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
        ('LEFTPADDING', (0, 0), (-1, -1), 4.5),
        ('RIGHTPADDING', (0, 0), (-1, -1), 4.5),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F9FAFB')]),
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#CBD5E1')),
    ])
