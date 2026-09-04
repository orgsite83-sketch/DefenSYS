from decimal import Decimal
from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_individual_grade_pdf(student, student_grade, team_grade, generated_by_user, signatories=None, include_signatures=True):
    """
    Generate an official USTP DIT confidential PDF report detailing an individual student's grades,
    peer evaluation score contribution, panel assessment, and official audit summary.
    """
    team = team_grade.team
    semester = team_grade.semester
    student_name = student.get_full_name() or student.username
    adviser_name = f"{team.adviser.first_name} {team.adviser.last_name}".strip() if team.adviser else "Unassigned"

    builder = DefensysPdfReportBuilder(
        title=f"Individual Student Grade Audit Report — {student_name}",
        subtitle=f"Certified Academic Performance & Defense Breakdown · {team_grade.stage_label or 'Defense Stage'}",
        generated_by=generated_by_user,
    )

    # 1. Official Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    stage_text = f"{team_grade.stage_label or 'Defense Stage'}"
    if getattr(team_grade, 'attempt_count', 1) > 1:
        stage_text += f" (Attempt #{team_grade.attempt_count})"

    metadata_rows = [
        ("Student Candidate", f"{student_name} (ID: {student.username})"),
        ("Student Team & Section", f"{team.name or 'Team'} · {team.section or team.year_level or 'BSIT'}"),
        ("Title of Approved Project", team.project_title or team.name or "N/A"),
        ("Academic Term / Semester", f"{semester.school_year.label if semester else ''} — {semester.label if semester else ''}"),
        ("Capstone Defense Stage", stage_text),
        ("Project Adviser", adviser_name),
    ]

    verdict_val = getattr(team_grade, 'verdict', '')
    if verdict_val:
        verdict_display = dict(team_grade.VERDICT_CHOICES).get(verdict_val, verdict_val.replace('_', ' ').title())
        if team_grade.revision_deadline:
            verdict_display += f" (Deadline: {team_grade.revision_deadline.strftime('%b %d, %Y')})"
        metadata_rows.append(("Panel Verdict", verdict_display))

    builder.add_metadata_grid(metadata_rows)

    # 3. Overall Grade Breakdown
    builder.add_section_header("Individual Academic Grade Breakdown")

    def format_score(val):
        return f"{val:.2f}%" if val is not None else "Pending"

    # Effective student scores
    student_panel = student_grade.panel_score if student_grade and student_grade.panel_score is not None else team_grade.panel_score
    student_adviser = student_grade.adviser_score if student_grade and student_grade.adviser_score is not None else team_grade.adviser_score
    student_peer = student_grade.peer_score if student_grade and student_grade.peer_score is not None else team_grade.peer_score

    if student_grade and student_grade.final_grade is not None:
        student_final = student_grade.final_grade
    else:
        if student_panel is not None and student_peer is not None:
            tot = student_panel * Decimal(team_grade.panel_weight) + student_peer * Decimal(team_grade.peer_weight)
            if team_grade.is_capstone and team_grade.adviser_weight > 0 and student_adviser is not None:
                tot += student_adviser * Decimal(team_grade.adviser_weight)
            student_final = (tot / Decimal('100')).quantize(Decimal('0.01'))
        else:
            student_final = team_grade.final_grade

    headers = [
        "Assessment Component",
        "Weight",
        "Earned Score",
        "Weighted Value",
        "Evaluation Remarks / Source",
    ]

    rows = []

    # Panel Component
    panel_val = (
        (student_panel * Decimal(team_grade.panel_weight) / Decimal('100')).quantize(Decimal('0.01'))
        if student_panel is not None
        else None
    )
    rows.append([
        "Panel Defense Evaluation",
        f"{team_grade.panel_weight}%",
        format_score(student_panel),
        format_score(panel_val),
        "Composite panel rubric score",
    ])

    # Adviser Component (if Capstone)
    if team_grade.is_capstone and team_grade.adviser_weight > 0:
        adviser_val = (
            (student_adviser * Decimal(team_grade.adviser_weight) / Decimal('100')).quantize(Decimal('0.01'))
            if student_adviser is not None
            else None
        )
        rows.append([
            "Project Adviser Grade",
            f"{team_grade.adviser_weight}%",
            format_score(student_adviser),
            format_score(adviser_val),
            f"Assessed by {adviser_name}",
        ])

    # Peer Evaluation Component
    peer_val = (
        (student_peer * Decimal(team_grade.peer_weight) / Decimal('100')).quantize(Decimal('0.01'))
        if student_peer is not None
        else None
    )
    rows.append([
        "Individual Peer Evaluation Contribution",
        f"{team_grade.peer_weight}%",
        format_score(student_peer),
        format_score(peer_val),
        "Internal peer rubric average",
    ])

    # Final Result
    status_str = "PASSED" if (student_final is not None and student_final >= Decimal('75.00')) else "FAILED / RE-DEFENSE"
    if student_final is None:
        status_str = "PENDING"

    rows.append([
        "TOTAL OFFICIAL GRADE",
        "100%",
        format_score(student_final),
        format_score(student_final),
        f"Official Status: {status_str}",
    ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[2.0 * inch, 0.8 * inch, 1.0 * inch, 1.0 * inch, 2.2 * inch],
        alignments=['left', 'center', 'center', 'center', 'left'],
        bold_cols=[0, 4],
    )

    # 4. Panelist Defense Feedback & Remarks
    submissions = list(team_grade.panelist_submissions.all().select_related('panelist'))
    remarks_list = [s for s in submissions if s.remarks and s.remarks.strip()]
    if remarks_list:
        builder.add_section_header("Panelist Defense Feedback & Direct Observations")

        rem_headers = ["Panelist", "Remarks & Recommendations"]
        rem_rows = []
        for s in remarks_list:
            pname = s.panelist.get_full_name() if s.panelist else s.guest_name
            if not pname:
                pname = "Defense Panelist"
            rem_rows.append([pname, s.remarks])

        builder.add_table(
            headers=rem_headers,
            rows=rem_rows,
            col_widths=[2.2 * inch, 4.8 * inch],
            bold_cols=[0],
        )

    # 5. Official Signatures Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="Academic Documenter / Evaluator",
        noted_by=adviser_name,
        noted_role="Project Adviser / Panel Chair",
        approved_by="IT Program Chairperson",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
