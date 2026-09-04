from datetime import datetime
from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_minutes_pdf(minutes, signatories=None, include_signatures=True):
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
        title="Project Final Oral Defense Minutes of Team",
        subtitle=f"[{minutes.team_name or 'Student Team'}]",
        generated_by=minutes.documenter_name or 'Defense Documenter',
        show_sidebar=True,
    )

    # 1. Official Header Banner & Document Title
    builder.add_header()

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
        panelist_label = f"<b>{c.panelist_name_snapshot or 'Panelist'}</b>{role_tag}"
        comments_html = c.comments.replace('\n', '<br/>') if c.comments else "<i>No specific comments recorded.</i>"
        rows.append([
            panelist_label,
            comments_html,
        ])

    if not rows:
        rows.append([
            "Panelists",
            "<i>All panelists endorsed the project presentation without major revisions.</i>",
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[1.8 * inch, builder.usable_width - 1.8 * inch],
        bold_cols=[0],
    )

    # 4. Certification & Signatures Section
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
