from decimal import Decimal
from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder
from reports.grade_summary import assessment_scope_label, student_assessment_scores
from xml.sax.saxutils import escape


def generate_individual_grade_pdf(student, student_grade, team_grade, generated_by_user, signatories=None, include_signatures=False, builder=None, coverage_label=None):
    """
    Generate an official USTP DIT confidential PDF report detailing an individual student's grades,
    peer evaluation score contribution, panel assessment, and official audit summary.
    """
    team = team_grade.team
    semester = team_grade.semester
    student_name = student.get_full_name() or student.username
    adviser_name = f"{team.adviser.first_name} {team.adviser.last_name}".strip() if team.adviser else "Unassigned"

    owns_builder = builder is None
    scope_label = assessment_scope_label(team_grade)
    title = f"{scope_label} Individual Grade Audit Report - {escape(student_name)}"
    subtitle = f"Academic Performance Breakdown - {escape(team_grade.stage_label)}"
    if owns_builder:
        builder = DefensysPdfReportBuilder(title=title, subtitle=subtitle, generated_by=generated_by_user)

    # 1. Official Header Banner & Document Title
    builder.add_header(title=title, subtitle=subtitle)

    # 2. Metadata Grid
    stage_text = f"{team_grade.stage_label or 'Defense Stage'}"
    if getattr(team_grade, 'attempt_count', 1) > 1:
        stage_text += f" (Attempt #{team_grade.attempt_count})"

    metadata_rows = [
        ("Student Candidate", f"{student_name} (ID: {student.username})"),
        ("Student Team & Section", f"{team.name or 'Team'} · {team.section or team.year_level or 'BSIT'}"),
        ("Project Title", escape(team_grade.project_title_snapshot or team.project_title or team.name or "N/A")),
        ("Academic Scope", scope_label),
        ("Report Coverage", escape(coverage_label or team_grade.stage_label)),
        ("Academic Term / Semester", f"{semester.school_year.label if semester else ''} — {semester.label if semester else ''}"),
        ("Defense Stage" if team_grade.is_capstone else "PIT Event", escape(stage_text)),
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
    values = student_assessment_scores(team_grade, student_grade)
    student_panel, student_adviser, student_peer = values['panel'], values['adviser'], values['peer']
    student_final = values['final']

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
    status_str = values['status']

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
        col_widths=[builder.usable_width * ratio for ratio in (.28, .09, .15, .15, .33)],
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
            col_widths=[builder.usable_width * .30, builder.usable_width * .70],
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

    return builder.build() if owns_builder else None


def generate_individual_grades_pdf(student, grade_records, generated_by_user, signatories=None, include_signatures=False, coverage_label=None):
    builder = DefensysPdfReportBuilder(generated_by=generated_by_user)
    for index, grade in enumerate(grade_records):
        if index:
            builder.add_page_break()
        student_grade = next((item for item in grade.student_grades.all() if item.student_id == student.pk), None)
        generate_individual_grade_pdf(
            student, student_grade, grade, generated_by_user,
            signatories=signatories, include_signatures=include_signatures, builder=builder,
            coverage_label=coverage_label or ('All recorded stages / events' if len(grade_records) > 1 else grade.stage_label),
        )
    return builder.build()
