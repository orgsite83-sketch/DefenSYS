from decimal import Decimal
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, Spacer
from reports.pdf_builder import DefensysPdfReportBuilder
from reports.pdf_styles import defensys_styles


def generate_curriculum_proposal_pdf(analytics_data, proposal_data, generated_by_user, signatories=None, include_signatures=True):
    """
    Generate an official USTP DIT Curriculum Review & Decision Support Proposal PDF.
    Suitable for PACUCOA accreditation, CHED compliance, and Department Curriculum Committee review.
    """
    selected_year = analytics_data.get('selected_academic_year') or 'All Academic Years'
    builder = DefensysPdfReportBuilder(
        title="Curriculum Analytics & Decision Support Proposal",
        subtitle=f"Evidence-Based Academic Improvement Report · AY {selected_year}",
        generated_by=generated_by_user,
    )

    kpis = analytics_data.get('kpi_summary') or {}
    total_projects = analytics_data.get('entries_count', 0)
    competency_index = kpis.get('competency_index', 85)
    pass_rate = kpis.get('first_pass_rate', 80)
    top_domain = kpis.get('top_domain', 'Enterprise & Cloud SaaS')

    # 1. Header Banner & Title
    builder.add_header()

    # 2. Executive Metadata Grid
    metadata_rows = [
        ("Target Academic Year", selected_year),
        ("Total Analyzed Projects", f"{total_projects} Capstone & PIT Projects"),
        ("Competency Proficiency Index", f"{competency_index}% Meeting Benchmark"),
        ("First-Time Defense Pass Rate", f"{pass_rate}%"),
        ("Leading Domain Specialization", top_domain),
        ("Report Classification", "Official Institutional Decision Support Report"),
    ]
    builder.add_metadata_grid(metadata_rows)

    # 3. Executive Summary Callout / Section
    builder.add_section_header("1. Executive Summary & Problem Context")
    summary_text = proposal_data.get('summary') or (
        f"This decision support analysis synthesizes {total_projects} capstone and PIT project deliverables, "
        f"multi-criteria defense rubrics, and longitudinal trends across Academic Year {selected_year}. "
        "The objective is to guide evidence-based curriculum adjustments, identify prerequisite course skill gaps, "
        "and optimize defense workflow efficiency."
    )
    styles = defensys_styles()
    builder.story.append(Paragraph(summary_text, styles["BodyDark"]))
    builder.story.append(Spacer(1, 0.12 * inch))

    # 4. Competency & Rubric Skill Gaps Table
    builder.add_section_header("2. Core Competency & Rubric Skill Gap Matrix")
    competencies = analytics_data.get('competency_matrix') or []
    if competencies:
        headers = ["Competency Dimension", "Avg Score", "Benchmark (75%)", "Prerequisite Alignment", "Status"]
        rows = []
        for comp in competencies:
            avg_score = comp.get('score', 0)
            status = "Proficient" if avg_score >= 75 else "Action Needed"
            rows.append([
                comp.get('name', 'N/A'),
                f"{avg_score:.1f}%",
                "Met" if avg_score >= 75 else "Below Target",
                comp.get('aligned_course', 'Major Courses'),
                status,
            ])
        builder.add_table(
            headers=headers,
            rows=rows,
            col_widths=[2.1 * inch, 0.8 * inch, 1.1 * inch, 1.4 * inch, 0.9 * inch],
            alignments=['left', 'center', 'center', 'left', 'center'],
            bold_cols=[0, 1, 4],
        )
    else:
        builder.story.append(Paragraph("No competency rubric data recorded for the selected period.", styles["BodyDark"]))
        builder.story.append(Spacer(1, 0.10 * inch))

    # 5. Project Domain & Specialization Landscape
    builder.add_section_header("3. Project Domain & Technology Distribution")
    domains = analytics_data.get('domain_distribution') or []
    if domains:
        headers = ["Specialization Domain", "Project Share", "Count", "Dominant Stacks / Keywords", "Trend"]
        rows = []
        for dom in domains[:6]:
            rows.append([
                dom.get('domain', 'N/A'),
                f"{dom.get('percentage', 0)}%",
                str(dom.get('count', 0)),
                dom.get('top_stacks', 'General'),
                dom.get('trend_status', 'Stable'),
            ])
        builder.add_table(
            headers=headers,
            rows=rows,
            col_widths=[1.8 * inch, 0.9 * inch, 0.6 * inch, 2.0 * inch, 1.0 * inch],
            alignments=['left', 'center', 'center', 'left', 'center'],
            bold_cols=[0, 1],
        )
    builder.story.append(Spacer(1, 0.10 * inch))

    # 6. Prescriptive Recommendations & Action Plan
    builder.add_section_header("4. Evidence-Based Strategic Recommendations")
    recommendations = proposal_data.get('recommendations') or []
    if recommendations:
        for idx, rec in enumerate(recommendations, 1):
            title = rec.get('title', f"Recommendation #{idx}") if isinstance(rec, dict) else f"Action Item #{idx}"
            body = rec.get('body', str(rec)) if isinstance(rec, dict) else str(rec)
            category = rec.get('type_label', 'Curriculum Intervention') if isinstance(rec, dict) else "Curriculum"
            
            p_content = f"<b>{idx}. [{category.upper()}] {title}</b><br/>{body}"
            builder.story.append(Paragraph(p_content, styles["BodyDark"]))
            builder.story.append(Spacer(1, 0.06 * inch))
    else:
        builder.story.append(Paragraph("Continue monitoring repository and defense performance metrics.", styles["BodyDark"]))

    builder.story.append(Spacer(1, 0.15 * inch))

    # 7. Official Signatures Certification Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="Curriculum Analytics Lead / Evaluator",
        noted_by="Academic Department Secretary",
        noted_role="Department Curriculum Committee Secretary",
        approved_by="IT Program Chairperson / College Dean",
        approved_role="Chairperson, Department of Information Technology",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
