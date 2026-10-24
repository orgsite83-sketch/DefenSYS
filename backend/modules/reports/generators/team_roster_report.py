from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder
from xml.sax.saxutils import escape


def generate_team_roster_pdf(semester, teams, generated_by_user, signatories=None, include_signatures=False):
    """
    Generate an official USTP DIT PDF roster listing all active teams and their memberships.
    """
    sem_label = f"{semester.school_year.label if semester else ''} {semester.label if semester else ''}".strip()
    builder = DefensysPdfReportBuilder(
        title="Student Team Directory & Roster Report",
        subtitle=f"Official Student Project Teams and Membership Registry · {sem_label}",
        generated_by=generated_by_user,
    )

    total_teams = len(teams)

    # 1. Official Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    metadata_rows = [
        ("Academic Term / Semester", f"{semester.school_year.label if semester else ''} — {semester.label if semester else ''}"),
        ("Total Active Student Teams", f"{total_teams} Project Teams Registered"),
        ("Academic Scope", ' / '.join(sorted({'PIT' if team.is_pit else 'Capstone' for team in teams})) or 'No matching teams'),
        ("Program / Department", "Department of Information Technology — Bachelor of Science in Information Technology"),
    ]
    builder.add_metadata_grid(metadata_rows)

    # 3. Main Roster Table
    builder.add_section_header("Academic Student Team Roster")

    headers = [
        "Team Name & Project Title",
        "Scope",
        "Section / Year",
        "Project Leader",
        "Project Adviser",
        "Registered Members",
        "Academic Period",
    ]

    rows = []
    for team in teams:
        team_info = f"<b>{escape(team.name or 'N/A')}</b><br/><i>{escape(team.project_title or 'Untitled Project')}</i>"
        level_info = f"{team.section or team.year_level or 'BSIT'}"
        leader_name = team.leader.get_full_name() if team.leader else "Unassigned"
        adviser_name = team.adviser.get_full_name() if team.adviser else "Unassigned"

        members = []
        for mship in team.memberships.all().select_related('student'):
            if mship.student:
                members.append(mship.student.get_full_name() or mship.student.username)
        members_str = ", ".join(members) if members else "No members"
        if hasattr(team, '_recorded_term'):
            frozen = team._recorded_term.snapshot
            leader_name = frozen.get('leader_name') or 'Unassigned'
            adviser_name = frozen.get('adviser_name') or 'Unassigned'
            members_str = ', '.join(member.get('name') or member.get('username') or '' for member in frozen.get('members', [])) or 'No members'

        rows.append([
            team_info,
            'PIT' if team.is_pit else 'Capstone',
            level_info,
            leader_name,
            adviser_name,
            members_str,
            team.semester.display_name,
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[builder.usable_width * ratio for ratio in (.20, .08, .10, .12, .12, .24, .14)],
        alignments=['left', 'center', 'center', 'left', 'left', 'left', 'left'],
        repeat_headers=True,
        bold_cols=[],
    )

    # 4. Signatures Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="Academic Documenter / Evaluator",
        noted_by="Academic Project Coordinator",
        noted_role="Faculty Project Coordinator",
        approved_by="IT Program Chairperson",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
