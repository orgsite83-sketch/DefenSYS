from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_user_directory_pdf(users, generated_by_user, signatories=None, include_signatures=True):
    """
    Generate an official USTP DIT PDF user account directory.
    """
    builder = DefensysPdfReportBuilder(
        title="Department User Directory & Account Registry",
        subtitle="Official Department of Information Technology System Users and Stakeholders Registry",
        generated_by=generated_by_user,
    )

    total_users = len(users)

    # 1. Official Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    metadata_rows = [
        ("Institutional Department", "Department of Information Technology — USTP Oroquieta"),
        ("Total Registered Users", f"{total_users} Active System Accounts"),
        ("Registry Purpose", "Academic Governance, Defense Evaluations, and Role Administration"),
    ]
    builder.add_metadata_grid(metadata_rows)

    # 3. Main Directory Table
    builder.add_section_header("System User Accounts Register")

    headers = [
        "Username / ID",
        "Full Legal Name",
        "Official Email Address",
        "System Role / Designation",
        "Account Status",
    ]

    rows = []
    for user in users:
        fullname = user.get_full_name() or f"{user.first_name} {user.last_name}".strip()
        if not fullname:
            fullname = "N/A"

        role_label = str(user.role).capitalize() if getattr(user, 'role', None) else "User"

        sub_roles = []
        if getattr(user, 'is_pit_lead', False):
            sub_roles.append("PIT Lead")
        if getattr(user, 'is_uploader', False):
            sub_roles.append("Doc Uploader")
        if getattr(user, 'is_panelist', False):
            sub_roles.append("Panelist")

        if sub_roles:
            role_label = f"{role_label} ({', '.join(sub_roles)})"

        status_label = "ACTIVE" if user.is_active else "INACTIVE"

        rows.append([
            user.username,
            fullname,
            user.email or "No Email",
            role_label,
            status_label,
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[1.1 * inch, 1.5 * inch, 1.8 * inch, 1.2 * inch, 0.7 * inch],
        alignments=['left', 'left', 'left', 'left', 'center'],
        bold_cols=[0, 4],
    )

    # 4. Signatures Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="System Administrator / Documenter",
        noted_by="System Administrator / Lead Developer",
        noted_role="System Administrator",
        approved_by="IT Program Chairperson",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
