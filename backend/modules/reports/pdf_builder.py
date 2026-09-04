import os
from io import BytesIO
from datetime import datetime
from decimal import Decimal

from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate,
    Table,
    TableStyle,
    Paragraph,
    Spacer,
    PageBreak,
    KeepTogether,
    Image,
    Flowable,
)
from reportlab.lib.styles import ParagraphStyle

from reports.pdf_styles import (
    defensys_styles,
    defensys_official_header,
    defensys_metadata_grid,
    defensys_signatures_block,
    defensys_confidential_callout,
    defensys_table_style,
    NumberedCanvas,
    get_official_header_image,
    MAROON,
    MAROON_DARK,
    MAROON_LIGHT,
    GOLD,
    GOLD_DARK,
    TEXT_DARK,
    TEXT_MUTED,
    BG_LIGHT,
    BORDER_GREY,
    RED_WARNING_BG,
    RED_WARNING_BORDER,
    RED_WARNING_TEXT,
)


class DefensysPdfReportBuilder:
    """
    Centralized, high-level fluent builder for institutional USTP DefenSYS PDF exports.
    Standardizes margins, headers, dynamic numbered footers, metadata grids, table styling,
    and institutional signature certification blocks.
    """

    def __init__(
        self,
        title: str = "",
        subtitle: str = "",
        generated_by: str = "System Administrator",
        orientation: str = "portrait",
        page_size=letter,
        show_sidebar: bool = True,
        top_margin: float = None,
        bottom_margin: float = 0.50 * inch,
        left_margin: float = None,
        right_margin: float = 0.35 * inch,
    ):
        self.title = title
        self.subtitle = subtitle
        self.generated_by = generated_by or "System Administrator"
        self.generated_at = datetime.now().strftime("%Y-%m-%d %I:%M %p")
        self.orientation = orientation.lower()

        if self.orientation == "landscape":
            self.pagesize = landscape(page_size)
            self.show_sidebar = False
        else:
            self.pagesize = page_size
            self.show_sidebar = show_sidebar

        page_w = self.pagesize[0]
        banner_h = page_w * (400.0 / 2448.0)

        # Default top_margin accommodates the edge-to-edge header banner + spacing
        if top_margin is None:
            self.top_margin = banner_h + 0.16 * inch
        else:
            self.top_margin = top_margin

        # When sidebar is enabled, left margin indents so content flows right of sidebar
        if left_margin is None:
            self.left_margin = 1.76 * inch if self.show_sidebar else 0.38 * inch
        else:
            self.left_margin = left_margin

        self.bottom_margin = bottom_margin
        self.right_margin = right_margin or 0.32 * inch

        # Usable page width
        self.usable_width = self.pagesize[0] - (self.left_margin + self.right_margin)

        self.buffer = BytesIO()
        self.doc = SimpleDocTemplate(
            self.buffer,
            pagesize=self.pagesize,
            topMargin=self.top_margin,
            bottomMargin=self.bottom_margin,
            leftMargin=self.left_margin,
            rightMargin=self.right_margin,
        )
        self.doc.generated_by = self.generated_by
        self.doc.generated_at = self.generated_at
        self.doc.show_sidebar = self.show_sidebar
        self.doc.draw_canvas_header = True

        self.story: list[Flowable] = []
        self.styles = defensys_styles()

    def add_header(self, title: str = None, subtitle: str = None, custom_banner_width=None):
        """
        Appends the document title and subtitle in solid black Times New Roman typography.
        The full-bleed official university banner is drawn automatically by the page canvas.
        """
        doc_title = title if title is not None else self.title
        doc_subtitle = subtitle if subtitle is not None else self.subtitle

        if doc_title:
            self.story.append(Paragraph(doc_title.upper(), self.styles['ReportTitle']))
        if doc_subtitle:
            self.story.append(Paragraph(doc_subtitle, self.styles['ReportSubtitle']))
        else:
            self.story.append(Spacer(1, 0.04 * inch))
        return self

    def add_metadata_grid(self, pairs: list[tuple[str, str]], width=None, col_ratio=(0.28, 0.72)):
        """
        Appends a 2-column key-value metadata block matching the university template layout.
        """
        grid_width = width or self.usable_width
        col1_w = grid_width * col_ratio[0]
        col2_w = grid_width * col_ratio[1]

        table_data = []
        for label, val in pairs:
            table_data.append([
                Paragraph(f"<b>{label}</b>", self.styles['MetaLabel']),
                Paragraph(f": {val or 'N/A'}", self.styles['MetaVal']),
            ])

        t = Table(table_data, colWidths=[col1_w, col2_w])
        t.setStyle(TableStyle([
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ('TOPPADDING', (0, 0), (-1, -1), 2),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 2),
            ('LEFTPADDING', (0, 0), (-1, -1), 4),
            ('RIGHTPADDING', (0, 0), (-1, -1), 4),
            ('BACKGROUND', (0, 0), (-1, -1), BG_LIGHT),
            ('BOX', (0, 0), (-1, -1), 0.5, BORDER_GREY),
            ('INNERGRID', (0, 0), (-1, -1), 0.3, BORDER_GREY),
        ]))
        self.story.append(t)
        self.story.append(Spacer(1, 0.08 * inch))
        return self

    def add_section_header(self, title: str, subtitle: str = None, space_before: float = 8, space_after: float = 3):
        """
        Adds a maroon section header with keep-with-next enabled.
        """
        self.story.append(Paragraph(title, self.styles['SectionHeader']))
        if subtitle:
            self.story.append(Paragraph(subtitle, self.styles['BodyMuted']))
        self.story.append(Spacer(1, space_after * (1 / 72.0) * inch))
        return self

    def add_subsection_header(self, title: str):
        """
        Adds a dark bold subsection header.
        """
        self.story.append(Paragraph(title, self.styles['SubSectionHeader']))
        self.story.append(Spacer(1, 0.02 * inch))
        return self

    def add_paragraph(self, text: str, style_name: str = 'BodyDark', space_after: float = 0.04 * inch):
        """
        Appends a formatted paragraph.
        """
        p_style = self.styles.get(style_name, self.styles['BodyDark'])
        self.story.append(Paragraph(text, p_style))
        if space_after:
            self.story.append(Spacer(1, space_after))
        return self

    def add_confidential_callout(self):
        """
        Appends the institutional confidential warning callout.
        """
        self.story.append(defensys_confidential_callout())
        self.story.append(Spacer(1, 0.08 * inch))
        return self

    def add_alert_box(self, title: str, message: str, level: str = 'info', width=None):
        """
        Appends a styled notification / alert banner.
        """
        box_width = width or self.usable_width
        bg_col = colors.HexColor('#EFF6FF') if level == 'info' else colors.HexColor('#FEF3C7') if level == 'warning' else colors.HexColor('#ECFDF5')
        border_col = colors.HexColor('#93C5FD') if level == 'info' else colors.HexColor('#FCD34D') if level == 'warning' else colors.HexColor('#6EE7B7')
        title_col = colors.HexColor('#1E40AF') if level == 'info' else colors.HexColor('#92400E') if level == 'warning' else colors.HexColor('#065F46')

        content = [
            Paragraph(f"<b>{title}</b>", ParagraphStyle('AlertTitle', parent=self.styles['Normal'], fontName='Helvetica-Bold', fontSize=8, textColor=title_col)),
            Paragraph(message, ParagraphStyle('AlertMsg', parent=self.styles['Normal'], fontName='Helvetica', fontSize=7.5, textColor=TEXT_DARK, spaceBefore=2)),
        ]
        table = Table([[content]], colWidths=[box_width])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, -1), bg_col),
            ('BOX', (0, 0), (-1, -1), 0.7, border_col),
            ('TOPPADDING', (0, 0), (-1, -1), 4),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
            ('LEFTPADDING', (0, 0), (-1, -1), 6),
            ('RIGHTPADDING', (0, 0), (-1, -1), 6),
        ]))
        self.story.append(table)
        self.story.append(Spacer(1, 0.08 * inch))
        return self

    def add_table(
        self,
        headers: list,
        rows: list[list],
        col_widths: list = None,
        alignments: list[str] = None,
        bold_cols: list[int] = None,
        custom_style: TableStyle = None,
        space_after: float = 0.10 * inch,
    ):
        """
        Adds a fully formatted institutional table.
        Automatically converts strings / numbers into Paragraphs with appropriate cell styles.
        """
        bold_cols_set = set(bold_cols or [])
        num_cols = len(headers) if headers else (len(rows[0]) if rows else 0)

        if alignments is None:
            alignments = ['left'] * num_cols

        # Format header row
        formatted_table_data = []
        if headers:
            hdr_cells = []
            for idx, h in enumerate(headers):
                if isinstance(h, Flowable):
                    hdr_cells.append(h)
                else:
                    align = alignments[idx] if idx < len(alignments) else 'left'
                    hdr_style = self.styles['TableHeaderCenter'] if align == 'center' else self.styles['TableHeader']
                    hdr_cells.append(Paragraph(f"<b>{h}</b>", hdr_style))
            formatted_table_data.append(hdr_cells)

        # Format body rows
        for row in rows:
            row_cells = []
            for col_idx, cell in enumerate(row):
                if isinstance(cell, Flowable):
                    row_cells.append(cell)
                else:
                    cell_text = str(cell) if cell is not None else ""
                    cell_text = cell_text.replace('\n', '<br/>')
                    align = alignments[col_idx] if col_idx < len(alignments) else 'left'
                    is_bold = col_idx in bold_cols_set

                    if is_bold:
                        cell_style = self.styles['TableCellBoldCenter'] if align == 'center' else self.styles['TableCellBold']
                    else:
                        cell_style = self.styles['TableCellCenter'] if align == 'center' else self.styles['TableCell']

                    row_cells.append(Paragraph(cell_text, cell_style))
            formatted_table_data.append(row_cells)

        if not formatted_table_data:
            return self

        t = Table(formatted_table_data, colWidths=col_widths)
        t.setStyle(custom_style or defensys_table_style())
        self.story.append(t)
        if space_after:
            self.story.append(Spacer(1, space_after))
        return self

    def add_signatures(
        self,
        prepared_by: str = None,
        prepared_role: str = "Academic Documenter / Evaluator",
        noted_by: str = None,
        noted_role: str = "Project Adviser / Panel Chair",
        approved_by: str = "IT Program Chairperson",
        approved_role: str = "IT Program Chairperson",
        certification_text: str = None,
        signatories: list[dict] = None,
        include_signatures: bool = True,
        width=None,
        line_width=2.5 * inch,
    ):
        """
        Adds the official institutional vertical stacked signature block matching the university template.
        Protected with KeepTogether to avoid page-break separation.
        """
        if not include_signatures:
            return self

        sig_width = width or self.usable_width
        actual_line_w = min(line_width, sig_width)
        gap_w = max(0.0, sig_width - actual_line_w)

        # If custom signatories list is provided, sanitize and use it
        if signatories and isinstance(signatories, list):
            valid_signers = [s for s in signatories if isinstance(s, dict) and (s.get('name') or s.get('label') or s.get('role'))]
        else:
            prep_name = prepared_by or self.generated_by
            note_name = noted_by or ""
            appr_name = approved_by or ""
            valid_signers = [
                {'label': 'Prepared by:', 'name': prep_name, 'role': prepared_role},
                {'label': 'Noted by:', 'name': note_name, 'role': noted_role},
                {'label': 'Approved by:', 'name': appr_name, 'role': approved_role},
            ]

        if not valid_signers:
            return self

        sig_elements = []
        sig_elements.append(Spacer(1, 0.12 * inch))

        # Optional certification clause (only if explicitly provided)
        if certification_text:
            cert_p = Paragraph(certification_text, self.styles['BodyDark'])
            cert_table = Table([[cert_p]], colWidths=[sig_width])
            cert_table.setStyle(TableStyle([
                ('BOX', (0, 0), (-1, -1), 0.7, TEXT_DARK),
                ('TOPPADDING', (0, 0), (-1, -1), 4),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
                ('LEFTPADDING', (0, 0), (-1, -1), 7),
                ('RIGHTPADDING', (0, 0), (-1, -1), 7),
                ('BACKGROUND', (0, 0), (-1, -1), BG_LIGHT),
            ]))
            sig_elements.append(cert_table)
            sig_elements.append(Spacer(1, 0.12 * inch))

        for s_idx, s in enumerate(valid_signers):
            lbl = s.get('label') or 'Signed by:'
            nm = (s.get('name') or '').strip()
            role = (s.get('role') or '').strip()

            lbl_p = Paragraph(f"<i>{lbl}</i>", self.styles['BodyDark'])

            if nm and role and nm.lower() != role.lower():
                name_role_text = f"<b>{nm}</b><br/>{role}"
            elif nm:
                name_role_text = f"<b>{nm}</b>"
            elif role:
                name_role_text = f"{role}"
            else:
                name_role_text = "—"

            nr_p = Paragraph(name_role_text, self.styles['BodyDark'])

            block_data = [
                [lbl_p, ""],
                [Spacer(1, 0.22 * inch), ""],
                [nr_p, ""],
            ]
            t = Table(block_data, colWidths=[actual_line_w, gap_w])
            t.setStyle(TableStyle([
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                ('LINEBELOW', (0, 1), (0, 1), 0.75, TEXT_DARK),
                ('TOPPADDING', (0, 0), (-1, -1), 1),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
                ('LEFTPADDING', (0, 0), (-1, -1), 0),
                ('RIGHTPADDING', (0, 0), (-1, -1), 0),
            ]))
            sig_elements.append(t)
            if s_idx < len(valid_signers) - 1:
                sig_elements.append(Spacer(1, 0.12 * inch))

        self.story.append(KeepTogether(sig_elements))
        return self

    def add_spacer(self, height_inch: float = 0.1):
        """
        Adds vertical spacing.
        """
        self.story.append(Spacer(1, height_inch * inch))
        return self

    def add_page_break(self):
        """
        Inserts a page break.
        """
        self.story.append(PageBreak())
        return self

    def add_flowable(self, flowable: Flowable):
        """
        Appends any raw ReportLab Flowable.
        """
        self.story.append(flowable)
        return self

    def build(self) -> bytes:
        """
        Builds the PDF document using the 2-pass NumberedCanvas and returns the raw byte stream.
        """
        doc_ref = self.doc
        show_side = self.show_sidebar

        class BoundNumberedCanvas(NumberedCanvas):
            _doctemplate = doc_ref
            _show_sidebar = show_side

        self.doc.build(self.story, canvasmaker=BoundNumberedCanvas)
        pdf_content = self.buffer.getvalue()
        self.buffer.close()
        return pdf_content
