"""
PDF Generator for Weekly Progress Reports Compilation using DefensysPdfReportBuilder
"""
from datetime import datetime
from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_weekly_reports_pdf(team, reports):
    """
    Generate PDF compilation of weekly progress reports matching official USTP DefenSYS template.
    
    Args:
        team: StudentTeam object
        reports: QuerySet of WeeklyProgressReport objects
        
    Returns:
        bytes: PDF content
    """
    adviser_name = team.adviser.get_full_name() if team.adviser else 'Unassigned'
    leader_name = team.leader.get_full_name() if team.leader else (team.name or 'Student Team')

    builder = DefensysPdfReportBuilder(
        title="Weekly Progress Reports Compilation",
        subtitle=f"Official Student Deliverables & Milestone Progress Registry · {team.name or 'Team'}",
        generated_by=leader_name,
    )

    # 1. Official Header
    builder.add_header()

    # 2. Cover / Metadata Grid
    metadata_rows = [
        ("Student Team Name", team.name or 'N/A'),
        ("Approved Project Title", team.project_title or 'N/A'),
        ("Academic Year Level & Section", f"{team.year_level or 'BSIT'} · {team.section or 'N/A'}"),
        ("Project Adviser", adviser_name),
        ("Total Progress Reports", f"{len(reports)} Weekly Submissions"),
        ("Compilation Date", datetime.now().strftime('%B %d, %Y')),
    ]
    builder.add_metadata_grid(metadata_rows)

    if not reports:
        builder.add_section_header("Weekly Progress Reports")
        builder.add_paragraph("<i>No weekly progress reports submitted for this team.</i>", style_name='BodyMuted')
    else:
        # Process each week
        for idx, report in enumerate(reports):
            week_date = report.report_date.strftime('%B %d, %Y') if hasattr(report.report_date, 'strftime') else str(report.report_date)
            builder.add_section_header(f"WEEK {report.week_number} — {week_date}")

            student_name = report.student.get_full_name() if report.student else "Unknown"
            submitted_str = report.submitted_at.strftime("%B %d, %Y %I:%M %p") if report.submitted_at else "N/A"
            builder.add_paragraph(f"<i>Submitted by: <b>{student_name}</b> on {submitted_str}</i>", style_name='BodyMuted', space_after=0.06 * inch)

            # Check if this is a file-based report or legacy JSON report
            if report.report_file:
                builder.add_subsection_header("Report Deliverable Attachment")
                file_rows = [
                    ["File Attachment Name", str(report.report_file)],
                    ["Attachment File Size", str(report.file_size or 'N/A')],
                ]
                builder.add_table(
                    headers=["Property", "Details"],
                    rows=file_rows,
                    col_widths=[2.0 * inch, 4.8 * inch],
                    bold_cols=[0],
                )
                builder.add_paragraph("<i>Note: This is a file-based submission. The attached deliverable is archived in the DefenSYS repository.</i>", style_name='BodyMuted')
            else:
                # Accomplishments
                builder.add_subsection_header("Accomplishments for the Week")
                if report.accomplishments and len(report.accomplishments) > 0:
                    acc_rows = []
                    for acc in report.accomplishments:
                        acc_rows.append([
                            acc.get('task', 'N/A'),
                            acc.get('description', 'N/A'),
                            acc.get('evidence', 'Attached / Verified'),
                        ])
                    builder.add_table(
                        headers=["Task / Activity", "Description", "Output / Evidence"],
                        rows=acc_rows,
                        col_widths=[1.8 * inch, 3.4 * inch, 1.6 * inch],
                        bold_cols=[0],
                    )
                else:
                    builder.add_paragraph("<i>No specific accomplishments recorded.</i>", style_name='BodyMuted')

                # Individual Contributions
                if report.contributions and len(report.contributions) > 0:
                    builder.add_subsection_header("Individual Member Contributions")
                    cont_rows = []
                    for cont in report.contributions:
                        cont_rows.append([
                            cont.get('member', 'N/A'),
                            cont.get('contribution', 'N/A'),
                        ])
                    builder.add_table(
                        headers=["Team Member", "Individual Contribution"],
                        rows=cont_rows,
                        col_widths=[2.2 * inch, 4.6 * inch],
                        bold_cols=[0],
                    )

                # Issues Encountered
                if report.issues and len(report.issues) > 0:
                    builder.add_subsection_header("Issues Encountered & Actions Taken")
                    issue_rows = []
                    for issue in report.issues:
                        issue_rows.append([
                            issue.get('issue', 'N/A'),
                            issue.get('action', 'N/A'),
                        ])
                    builder.add_table(
                        headers=["Issue / Concern", "Action Taken / Resolution"],
                        rows=issue_rows,
                        col_widths=[3.4 * inch, 3.4 * inch],
                    )

                # Plans for Next Week
                if report.plans and len(report.plans) > 0:
                    builder.add_subsection_header("Plan for Next Week")
                    plan_rows = []
                    for plan in report.plans:
                        plan_rows.append([
                            plan.get('task', 'N/A'),
                            plan.get('output', 'N/A'),
                        ])
                    builder.add_table(
                        headers=["Planned Task", "Expected Milestone Output"],
                        rows=plan_rows,
                        col_widths=[3.4 * inch, 3.4 * inch],
                    )

            if idx < len(reports) - 1:
                builder.add_page_break()

    # Signatures Block
    builder.add_signatures(
        prepared_by=leader_name,
        prepared_role="Project Leader / Student Proponent",
        noted_by=adviser_name,
        noted_role="Capstone Project Adviser",
        approved_by="IT Program Chairperson",
        approved_role="IT Program Chairperson",
    )

    return builder.build()
