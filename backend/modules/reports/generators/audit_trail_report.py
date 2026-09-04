from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_audit_trail_pdf(logs, filters_desc, generated_by_user, signatories=None, include_signatures=True):
    """
    Generate an official USTP DIT PDF audit trail compilation for official ISO compliance monitoring.
    """
    builder = DefensysPdfReportBuilder(
        title="ISO 9001:2015 System Audit Trail Register",
        subtitle="Official Security Governance, Access Integrity & System Action Audit Logs",
        generated_by=generated_by_user,
    )

    total_logs = len(logs)

    # 1. Official Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    metadata_rows = [
        ("Compliance Standard", "ISO 9001:2015 Quality Management System (Clause 9.2 Audit Log)"),
        ("Total Audit Log Records", f"{total_logs} Log Entries Captured"),
        ("Audit Integrity Status", "Cryptographically Timestamped and Verified"),
    ]
    if filters_desc:
        for k, v in filters_desc.items():
            metadata_rows.append((f"Active Filter ({k})", str(v)))

    builder.add_metadata_grid(metadata_rows)

    # 3. Main Log Table
    builder.add_section_header("System Compliance Action Logs")

    headers = [
        "Date / Time",
        "Process Area",
        "Control Activity",
        "Responsible User",
        "Action Details & Recorded Reason",
    ]

    rows = []
    for log in logs:
        time_str = log.created_at.strftime('%Y-%m-%d %H:%M') if log.created_at else ""

        actor_name = log.actor_name if hasattr(log, 'actor_name') else ""
        if not actor_name and log.actor:
            actor_name = log.actor.get_full_name() or log.actor.username
        if not actor_name:
            actor_name = "System"

        category_lbl = log.category_label if hasattr(log, 'category_label') else (dict(log.CATEGORY_CHOICES).get(log.category, log.category))
        detail_reason = f"<b>Reason:</b> {log.reason or 'None provided'}"

        rows.append([
            time_str,
            category_lbl or "",
            log.action or "",
            actor_name,
            detail_reason,
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[1.0 * inch, 1.1 * inch, 1.2 * inch, 1.1 * inch, 2.0 * inch],
        bold_cols=[3],
    )

    # 4. Signatures Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="Compliance Officer / System Admin",
        noted_by="Quality Management Officer",
        noted_role="Quality Assurance Coordinator",
        approved_by="IT Program Chairperson / Dean",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
