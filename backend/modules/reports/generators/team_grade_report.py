from decimal import Decimal
from reportlab.lib.units import inch
from reportlab.platypus import Table, TableStyle, Paragraph, Spacer
from reportlab.lib import colors

from reports.pdf_builder import DefensysPdfReportBuilder
from reports.pdf_styles import defensys_table_style


def generate_team_grade_pdf(team_grade, generated_by_user, signatories=None, include_signatures=True):
    """
    Generate an official USTP DIT PDF report detailing a team's Master Student Grade Sheet
    matrix and detailed panelist rubric criteria evaluation breakdown.
    """
    team = team_grade.team
    semester = team_grade.semester

    adviser_name = f"{team.adviser.first_name} {team.adviser.last_name}".strip() if team.adviser else "Unassigned"
    leader_name = f"{team.leader.first_name} {team.leader.last_name}".strip() if team.leader else "Unassigned"

    members = []
    if team.leader:
        members.append((team.leader, True))
    for m in team.members.all():
        if m != team.leader:
            members.append((m, False))

    proponents_list = [f"{m[0].get_full_name() or m[0].username} (Leader)" if m[1] else (m[0].get_full_name() or m[0].username) for m in members]
    proponents_str = ", ".join(proponents_list) if proponents_list else "None listed"

    builder = DefensysPdfReportBuilder(
        title=f"Project Final Defense Evaluation Report — {team.name or 'Team'}",
        subtitle=f"Official Defense Deliberation & Academic Grading Record · {team_grade.stage_label or 'Capstone Defense'}",
        generated_by=generated_by_user,
        show_sidebar=True,
    )

    styles = builder.styles

    # 1. Official Institutional Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    stage_text = f"{team_grade.stage_label or 'Defense Stage'}"
    if getattr(team_grade, 'attempt_count', 1) > 1:
        stage_text += f" (Attempt #{team_grade.attempt_count})"

    metadata_rows = [
        ("Title of Approved Project", team.project_title or team.name or "N/A"),
        ("Student Team & Section", f"{team.name or 'Team'} · {team.section or team.year_level or 'BSIT'}"),
        ("Academic Term / Semester", f"{semester.school_year.label if semester else ''} — {semester.label if semester else ''}"),
        ("Capstone Defense Stage", stage_text),
        ("Proponents / Members", proponents_str),
        ("Project Adviser", adviser_name),
    ]

    verdict_val = getattr(team_grade, 'verdict', '')
    if verdict_val:
        verdict_display = dict(team_grade.VERDICT_CHOICES).get(verdict_val, verdict_val.replace('_', ' ').title())
        if team_grade.revision_deadline:
            verdict_display += f" (Deadline: {team_grade.revision_deadline.strftime('%b %d, %Y')})"
        metadata_rows.append(("Panel Verdict", verdict_display))

    builder.add_metadata_grid(metadata_rows)

    # Panel Verdict Remarks & Instructions Box (if present)
    if getattr(team_grade, 'verdict_remarks', ''):
        builder.add_section_header("Official Defense Verdict & Panel Instructions")
        rem_p = Paragraph(f"<b>Verdict:</b> {verdict_display}<br/><br/><b>Instructions for Team:</b><br/>{team_grade.verdict_remarks}", styles['TableCell'])
        v_table = Table([[rem_p]], colWidths=[builder.usable_width])
        v_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#F8FAFC')),
            ('BOX', (0, 0), (-1, -1), 1, colors.HexColor('#CBD5E1')),
            ('PADDING', (0, 0), (-1, -1), 8),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ]))
        builder.add_flowable(v_table)
        builder.add_spacer(0.07)

    # Attempt History & ISO Audit Traceability (if past attempts exist)
    histories = list(team_grade.attempt_history.all().order_by('attempt_number'))
    if histories:
        builder.add_section_header("Defense Attempt History & Traceability Log")
        hist_headers = [
            Paragraph("<b>Attempt</b>", styles['TableHeaderCenter']),
            Paragraph("<b>Schedule Date</b>", styles['TableHeaderCenter']),
            Paragraph("<b>Panel</b>", styles['TableHeaderCenter']),
            Paragraph("<b>Final Grade</b>", styles['TableHeaderCenter']),
            Paragraph("<b>Verdict / Outcome</b>", styles['TableHeader']),
            Paragraph("<b>Instructions / Remarks</b>", styles['TableHeader']),
        ]
        hist_rows = [hist_headers]
        for h in histories:
            h_date = h.scheduled_date.strftime('%b %d, %Y') if h.scheduled_date else "—"
            h_verdict = dict(team_grade.VERDICT_CHOICES).get(h.verdict, h.verdict.replace('_', ' ').title()) if h.verdict else ("PASSED" if (h.final_grade and h.final_grade >= 75) else "FAILED")
            hist_rows.append([
                Paragraph(f"#{h.attempt_number}", styles['TableCellCenter']),
                Paragraph(h_date, styles['TableCellCenter']),
                Paragraph(f"{h.panel_score:.2f}%" if h.panel_score is not None else "—", styles['TableCellCenter']),
                Paragraph(f"<b>{h.final_grade:.2f}%</b>" if h.final_grade is not None else "—", styles['TableCellBoldCenter']),
                Paragraph(h_verdict, styles['TableCellBold']),
                Paragraph(h.verdict_remarks or "—", styles['TableCell']),
            ])
        hist_table = Table(hist_rows, colWidths=[0.65 * inch, 1.05 * inch, 0.85 * inch, 0.95 * inch, 1.40 * inch, 2.80 * inch])
        hist_table.setStyle(defensys_table_style())
        builder.add_flowable(hist_table)
        builder.add_spacer(0.07)

    # 3. Extract distinct panelists
    submissions = list(team_grade.panelist_submissions.all().prefetch_related('criterion_scores', 'panelist'))
    distinct_panelists = []
    seen_panelists = set()

    for sub in submissions:
        pan_key = (sub.panelist_id, sub.guest_code_id)
        if pan_key not in seen_panelists and sub.student_id is None:
            seen_panelists.add(pan_key)
            name = sub.panelist.get_full_name() if sub.panelist else sub.guest_name
            if not name:
                name = f"Panelist {len(distinct_panelists) + 1}"

            scores = list(sub.criterion_scores.all())
            tot_score = sum((c.score for c in scores), Decimal('0'))
            tot_max = sum((c.max_score_snapshot for c in scores), Decimal('0'))
            pct = (tot_score / tot_max * Decimal('100')).quantize(Decimal('0.01')) if tot_max > 0 else None

            distinct_panelists.append({
                'index': len(distinct_panelists) + 1,
                'name': name,
                'pan_key': pan_key,
                'score': pct,
                'sub': sub,
            })

    if not distinct_panelists:
        for sub in submissions:
            pan_key = (sub.panelist_id, sub.guest_code_id)
            if pan_key not in seen_panelists:
                seen_panelists.add(pan_key)
                name = sub.panelist.get_full_name() if sub.panelist else sub.guest_name
                if not name:
                    name = f"Panelist {len(distinct_panelists) + 1}"
                distinct_panelists.append({
                    'index': len(distinct_panelists) + 1,
                    'name': name,
                    'pan_key': pan_key,
                    'score': None,
                    'sub': sub,
                })

    # 4. Master Student Grade Sheet Matrix
    builder.add_section_header("Master Student Grade Sheet")
    matrix_sub = f"Official Stage Grade Matrix · Panelist Scores ({team_grade.panel_weight}%)"
    if team_grade.is_capstone and team_grade.adviser_weight > 0:
        matrix_sub += f" + Adviser Rating ({team_grade.adviser_weight}%)"
    matrix_sub += f" + Peer Rating ({team_grade.peer_weight}%)"
    builder.add_paragraph(matrix_sub, style_name='BodyMuted', space_after=0.03 * inch)

    # Header row
    matrix_headers = [
        Paragraph("<b>No.</b>", styles['TableHeaderCenter']),
        Paragraph("<b>Names</b>", styles['TableHeader']),
    ]
    for pan in distinct_panelists:
        matrix_headers.append(Paragraph(f"<b>Panel {pan['index']}</b><br/><font size=5.5>{pan['name']}</font>", styles['TableHeaderCenter']))

    matrix_headers.append(Paragraph("<b>Average</b>", styles['TableHeaderCenter']))
    matrix_headers.append(Paragraph(f"<b>Grade<br/>{team_grade.panel_weight}%</b>", styles['TableHeaderCenter']))

    if team_grade.is_capstone and team_grade.adviser_weight > 0:
        matrix_headers.append(Paragraph("<b>Adviser<br/>Rating</b>", styles['TableHeaderCenter']))
        matrix_headers.append(Paragraph(f"<b>{team_grade.adviser_weight}%</b>", styles['TableHeaderCenter']))

    matrix_headers.append(Paragraph("<b>Peer<br/>Rating</b>", styles['TableHeaderCenter']))
    matrix_headers.append(Paragraph(f"<b>{team_grade.peer_weight}%</b>", styles['TableHeaderCenter']))
    matrix_headers.append(Paragraph("<b>Total</b>", styles['TableHeaderCenter']))
    matrix_headers.append(Paragraph("<b>Final Grade</b>", styles['TableHeaderCenter']))

    matrix_rows = [matrix_headers]

    for idx, (student, is_leader) in enumerate(members, start=1):
        st_name = student.get_full_name() or student.username
        name_p = Paragraph(f"<b>{st_name}</b><br/><font size=6>(Leader)</font>" if is_leader else st_name, styles['TableCell'])
        sg = team_grade.student_grades.filter(student=student).first()

        row_cells = [
            Paragraph(str(idx), styles['TableCellCenter']),
            name_p,
        ]

        panel_scores = []
        for pan in distinct_panelists:
            sub_st = next((s for s in submissions if s.student_id == student.id and (s.panelist_id, s.guest_code_id) == pan['pan_key']), None)
            if sub_st:
                scores = list(sub_st.criterion_scores.all())
                tot_score = sum((c.score for c in scores), Decimal('0'))
                tot_max = sum((c.max_score_snapshot for c in scores), Decimal('0'))
                p_score = (tot_score / tot_max * Decimal('100')).quantize(Decimal('0.01')) if tot_max > 0 else None
            else:
                p_score = pan['score']

            if p_score is not None:
                panel_scores.append(p_score)
                row_cells.append(Paragraph(f"{p_score:.1f}%", styles['TableCellCenter']))
            else:
                row_cells.append(Paragraph("—", styles['TableCellCenter']))

        p_avg = (sum(panel_scores, Decimal('0')) / Decimal(len(panel_scores))).quantize(Decimal('0.01')) if panel_scores else team_grade.panel_score
        row_cells.append(Paragraph(f"<b>{p_avg:.2f}%</b>" if p_avg is not None else "—", styles['TableCellBoldCenter']))

        p_w = (p_avg * Decimal(team_grade.panel_weight) / Decimal('100')).quantize(Decimal('0.01')) if p_avg is not None else Decimal('0.00')
        row_cells.append(Paragraph(f"{p_w:.2f}" if p_avg is not None else "—", styles['TableCellCenter']))

        adv_score = team_grade.adviser_score
        adv_w = (adv_score * Decimal(team_grade.adviser_weight) / Decimal('100')).quantize(Decimal('0.01')) if (adv_score is not None and team_grade.adviser_weight > 0) else Decimal('0.00')
        if team_grade.is_capstone and team_grade.adviser_weight > 0:
            row_cells.append(Paragraph(f"{adv_score:.2f}%" if adv_score is not None else "—", styles['TableCellCenter']))
            row_cells.append(Paragraph(f"{adv_w:.2f}" if adv_score is not None else "—", styles['TableCellCenter']))

        peer_score = sg.peer_score if (sg and sg.peer_score is not None) else team_grade.peer_score
        peer_w = (peer_score * Decimal(team_grade.peer_weight) / Decimal('100')).quantize(Decimal('0.01')) if peer_score is not None else Decimal('0.00')
        row_cells.append(Paragraph(f"{peer_score:.2f}%" if peer_score is not None else "—", styles['TableCellCenter']))
        row_cells.append(Paragraph(f"{peer_w:.2f}" if peer_score is not None else "—", styles['TableCellCenter']))

        total = p_w + adv_w + peer_w
        row_cells.append(Paragraph(f"<b>{total:.2f}</b>", styles['TableCellBoldCenter']))

        final_g = sg.final_grade if (sg and sg.final_grade is not None) else total
        is_passed = (final_g is not None and final_g >= Decimal('75.00'))
        status_tag = "<font size=6.5><b>PASSED</b></font>" if is_passed else "<font size=6.5><b>FAILED</b></font>"
        row_cells.append(Paragraph(f"<b>{final_g:.2f}%</b><br/>{status_tag}" if final_g is not None else "PENDING", styles['TableCellBoldCenter']))

        matrix_rows.append(row_cells)

    # Calculate column widths to fit builder.usable_width cleanly
    num_panels = max(len(distinct_panelists), 1)
    has_adv = (team_grade.is_capstone and team_grade.adviser_weight > 0)

    w_no = 0.24 * inch
    w_name = 1.05 * inch
    w_avg = 0.54 * inch
    w_pgrade = 0.46 * inch
    w_adv_r = 0.54 * inch if has_adv else 0
    w_adv_w = 0.38 * inch if has_adv else 0
    w_peer_r = 0.54 * inch
    w_peer_w = 0.38 * inch
    w_total = 0.50 * inch
    w_final = 0.72 * inch

    fixed_sum = w_no + w_name + w_avg + w_pgrade + w_adv_r + w_adv_w + w_peer_r + w_peer_w + w_total + w_final
    avail_panels = max(builder.usable_width - fixed_sum, 0.46 * inch * num_panels)
    w_panel = avail_panels / num_panels

    col_widths = [w_no, w_name] + [w_panel] * len(distinct_panelists) + [w_avg, w_pgrade]
    if has_adv:
        col_widths += [w_adv_r, w_adv_w]
    col_widths += [w_peer_r, w_peer_w, w_total, w_final]

    t_style = defensys_table_style()
    t_style.add('LEFTPADDING', (0, 0), (-1, -1), 2)
    t_style.add('RIGHTPADDING', (0, 0), (-1, -1), 2)

    matrix_table = Table(matrix_rows, colWidths=col_widths)
    matrix_table.setStyle(t_style)
    builder.add_flowable(matrix_table)
    builder.add_spacer(0.07)

    # 5. Individual Rubric Breakdown & Criteria Assessment Table
    criteria_map = {}
    for sub in submissions:
        pan_key = (sub.panelist_id, sub.guest_code_id)
        for score in sub.criterion_scores.all():
            c_name = score.criterion_name_snapshot
            if c_name not in criteria_map:
                criteria_map[c_name] = {
                    'max_pts': score.max_score_snapshot,
                    'scores': {},
                }
            if pan_key not in criteria_map[c_name]['scores'] or sub.student_id is None:
                criteria_map[c_name]['scores'][pan_key] = score

    if criteria_map:
        builder.add_section_header("Individual Rubric Breakdown & Panelist Criteria Assessment")

        crit_headers = [
            Paragraph("<b>Criterion / Assessment Skill</b>", styles['TableHeader']),
            Paragraph("<b>Max Pts</b>", styles['TableHeaderCenter']),
        ]
        for pan in distinct_panelists:
            crit_headers.append(Paragraph(f"<b>Panel {pan['index']}</b><br/><font size=6>{pan['name']}</font>", styles['TableHeaderCenter']))
        crit_headers.append(Paragraph("<b>Normalized Avg</b>", styles['TableHeaderCenter']))

        crit_rows = [crit_headers]

        for c_name, c_data in criteria_map.items():
            row = [
                Paragraph(c_name, styles['TableCell']),
                Paragraph(f"{c_data['max_pts']:.1f}", styles['TableCellCenter']),
            ]
            tot_normal = Decimal('0.00')
            count = 0

            for pan in distinct_panelists:
                score_obj = c_data['scores'].get(pan['pan_key'])
                if score_obj is not None:
                    row.append(Paragraph(f"{score_obj.score:.1f} / {score_obj.max_score_snapshot:.1f}", styles['TableCellCenter']))
                    tot_normal += score_obj.normalized_score
                    count += 1
                else:
                    row.append(Paragraph("—", styles['TableCellCenter']))

            if count > 0:
                avg_pct = (tot_normal / Decimal(count)).quantize(Decimal('0.01'))
                row.append(Paragraph(f"<b>{avg_pct:.2f}%</b>", styles['TableCellBoldCenter']))
            else:
                row.append(Paragraph("—", styles['TableCellBoldCenter']))

            crit_rows.append(row)

        c_fixed = 2.10 * inch + 0.55 * inch + 0.85 * inch
        c_panel_w = max(builder.usable_width - c_fixed, 0.65 * inch * max(len(distinct_panelists), 1)) / max(len(distinct_panelists), 1)
        c_widths = [2.10 * inch, 0.55 * inch] + [c_panel_w] * len(distinct_panelists) + [0.85 * inch]

        crit_table = Table(crit_rows, colWidths=c_widths)
        crit_table.setStyle(defensys_table_style())
        builder.add_flowable(crit_table)

    # 6. Official Signatures Block
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
