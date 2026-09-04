from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_team_roster_pdf(semester, teams, generated_by_user, signatories=None, include_signatures=True):
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
        ("Program / Department", "Department of Information Technology — Bachelor of Science in Information Technology"),
    ]
    builder.add_metadata_grid(metadata_rows)

    # 3. Main Roster Table
    builder.add_section_header("Academic Student Team Roster")

    headers = [
        "Team Name & Project Title",
        "Section / Year",
        "Project Leader",
        "Project Adviser",
        "Registered Members",
    ]

    rows = []
    for team in teams:
        team_info = f"<b>{team.name or 'N/A'}</b><br/><i>{team.project_title or 'Untitled Project'}</i>"
        level_info = f"{team.section or team.year_level or 'BSIT'}"
        leader_name = team.leader.get_full_name() if team.leader else "Unassigned"
        adviser_name = team.adviser.get_full_name() if team.adviser else "Unassigned"

        members = []
        for mship in team.memberships.all().select_related('student'):
            if mship.student:
                members.append(mship.student.get_full_name() or mship.student.username)
        members_str = ", ".join(members) if members else "No members"

        rows.append([
            team_info,
            level_info,
            leader_name,
            adviser_name,
            members_str,
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[1.9 * inch, 0.8 * inch, 1.1 * inch, 1.1 * inch, 1.5 * inch],
        alignments=['left', 'center', 'left', 'left', 'left'],
        bold_cols=[],
    )

    # 4. Signatures Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="Academic Documenter / Evaluator",
        noted_by="Capstone Project Coordinator",
        noted_role="Faculty Capstone Coordinator",
        approved_by="IT Program Chairperson",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
