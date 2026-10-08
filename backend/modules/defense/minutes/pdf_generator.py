from xml.sax.saxutils import escape
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_minutes_pdf(minutes, signatories=None, include_signatures=True, draft=False):
    """
    Generates an official USTP DIT PDF for the completed defense minutes matching Minutes-Defense-TEMPLATE.pdf.

    Args:
        minutes: DefenseMinutes object
        signatories: list of custom signers
        include_signatures: bool

    Returns:
        bytes: PDF content
    """
    builder = DefensysPdfReportBuilder(
        title=f"{minutes.defense_stage_label or 'Defense'} Minutes of Team",
        subtitle=f"[{minutes.team_name or 'Student Team'}]",
        generated_by=minutes.documenter_name or 'Defense Documenter',
        show_sidebar=True,
    )

    # 1. Official Header Banner & Document Title
    builder.add_header()
    if draft:
        builder.add_alert_box('DRAFT PREVIEW', 'For review only. This document is awaiting the required signatures.', level='warning')

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

    team = minutes.schedule.team
    students = {m.student_id: m.student for m in team.memberships.select_related('student').all()}
    if team.leader_id:
        students.setdefault(team.leader_id, team.leader)
    proponents = [u.get_full_name() or u.username for u in students.values()]
    metadata_rows = [
        ("Project Title", escape(minutes.project_title or 'N/A')),
        ("Date of Defense", format_date(minutes.defense_date)),
        ("Time of Defense", format_time(minutes.defense_time)),
        ("Defense Room / Venue", minutes.room or 'N/A'),
        ("Proponents of Study", '<br/>'.join(escape(name) for name in proponents) or 'Not recorded'),
        ("Capstone Adviser", minutes.adviser_name or 'N/A'),
        ("Panel Members", panelists_str),
    ]
    builder.add_metadata_grid(metadata_rows)

    # 3. Panelist Comments / Suggestions Table
    builder.add_section_header("PANELIST COMMENTS & SUGGESTIONS")

    headers = [
        "PANELIST",
        "COMMENTS / SUGGESTIONS",
    ]

    rows = []
    for c in comments:
        role_tag = f" ({c.panelist_role_snapshot})" if c.panelist_role_snapshot else ""
        panelist_label = f"<b>{escape(c.panelist_name_snapshot or 'Panelist')}</b>{role_tag}"
        comments_html = escape(c.comments).replace('\n', '<br/>') if c.comments else "<i>Not recorded yet.</i>"
        # Keep rows small enough to fit a page. Splitting oversized table rows
        # in ReportLab can duplicate headers and leave empty continuation pages.
        remaining = Paragraph(comments_html, builder.styles['TableCell'])
        comment_width = builder.usable_width - 1.8 * inch - 12
        continued = False
        while remaining is not None:
            _, height = remaining.wrap(comment_width, 100000)
            if height <= 1.2 * inch:
                chunk, remaining = remaining, None
            else:
                pieces = remaining.split(comment_width, 1.2 * inch)
                chunk = pieces[0]
                remaining = pieces[1] if len(pieces) > 1 else None
            label = panelist_label + ('<br/><i>(continued)</i>' if continued else '')
            rows.append([label, chunk])
            continued = True

    if not rows:
        rows.append([
            "Panelists",
            "<i>Panelist comments have not been recorded.</i>",
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[1.8 * inch, builder.usable_width - 1.8 * inch],
        bold_cols=[0],
        repeat_headers=True,
    )

    # 4. Certification & Signatures Section
    if signatories is None:
        signatories = []
        for label, role, name, user, signed_at in [
            ('Prepared by:', 'Documenter', minutes.documenter_name, minutes.documenter_signed_by, minutes.documenter_signed_at),
            ('Noted by:', 'Capstone Adviser', minutes.adviser_name, minutes.adviser_signed_by, minutes.adviser_signed_at),
            ('Approved by:', 'IT Program Chairperson', 'IT Program Chairperson', minutes.chairman_signed_by, minutes.chairman_signed_at),
        ]:
            signer = {'label': label, 'role': role, 'name': user.get_full_name() or user.username if user else name}
            if signed_at and user and user.e_signature:
                with user.e_signature.open('rb') as signature:
                    signer['signature_image'] = signature.read()
                signer['signed_at'] = signed_at.strftime('%B %d, %Y')
            signatories.append(signer)
    builder.add_signatures(
        prepared_by=minutes.documenter_name or "Documenter",
        prepared_role="Documenter / Evaluator",
        noted_by=minutes.adviser_name or "Capstone Adviser",
        noted_role="Capstone Adviser / Panel Chair",
        approved_by="IT Program Chairperson",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
