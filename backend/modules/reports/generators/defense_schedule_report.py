from datetime import datetime, timedelta
from reportlab.lib.units import inch
from reports.pdf_builder import DefensysPdfReportBuilder


def generate_defense_schedule_pdf(semester, schedules, generated_by_user, signatories=None, include_signatures=True):
    """
    Generate an official USTP DIT PDF report summarizing scheduled defense presentations.
    """
    sem_label = f"{semester.school_year.label if semester else ''} {semester.label if semester else ''}".strip()
    builder = DefensysPdfReportBuilder(
        title="Defense Timetable & Presentation Schedule",
        subtitle=f"Official Defense Sessions & Panel Assignment Registry · {sem_label}",
        generated_by=generated_by_user,
    )

    total_slots = len(schedules)

    # 1. Official Header Banner & Document Title
    builder.add_header()

    # 2. Metadata Grid
    metadata_rows = [
        ("Academic Term / Semester", f"{semester.school_year.label if semester else ''} — {semester.label if semester else ''}"),
        ("Total Scheduled Presentations", f"{total_slots} Defense Sessions"),
        ("Defense Venue / Modality", "Department of Information Technology Defense Rooms / Hybrid"),
    ]
    builder.add_metadata_grid(metadata_rows)

    # 3. Main Schedule Table
    builder.add_section_header("Defense Presentation Schedule Register")

    headers = [
        "Date & Time",
        "Room / Venue",
        "Student Team",
        "Defense Stage",
        "Panel Assignments",
        "Status",
    ]

    rows = []
    for sched in schedules:
        time_str = ""
        if sched.scheduled_date:
            date_part = sched.scheduled_date.strftime('%b %d, %Y')
            start_part = sched.start_time.strftime('%I:%M %p') if sched.start_time else ""
            end_part = ""
            if sched.start_time:
                dummy_dt = datetime.combine(sched.scheduled_date, sched.start_time)
                end_dt = dummy_dt + timedelta(minutes=sched.slot_duration)
                end_part = end_dt.time().strftime('%I:%M %p')
            time_str = f"{date_part}<br/>{start_part} - {end_part}"
        else:
            time_str = "Unscheduled"

        panelists = []
        for assign in sched.panel_assignments.all().select_related('panelist'):
            if assign.panelist:
                panelists.append(assign.panelist.get_full_name() or assign.panelist.username)
        panel_str = ", ".join(panelists) if panelists else "No panel assigned"

        status_label = str(sched.status).upper() if getattr(sched, 'status', None) else "SCHEDULED"

        rows.append([
            time_str,
            sched.room or "TBA",
            sched.team.name if sched.team else "N/A",
            sched.defense_stage.label if sched.defense_stage else (sched.stage_label or "N/A"),
            panel_str,
            status_label,
        ])

    builder.add_table(
        headers=headers,
        rows=rows,
        col_widths=[1.25 * inch, 0.8 * inch, 1.2 * inch, 0.95 * inch, 1.5 * inch, 0.7 * inch],
        alignments=['left', 'center', 'left', 'center', 'left', 'center'],
        bold_cols=[2, 5],
    )

    # 4. Signatures Block
    builder.add_signatures(
        prepared_by=generated_by_user,
        prepared_role="Defense Scheduler / Admin",
        noted_by="Capstone Defense Coordinator",
        noted_role="Faculty Defense Coordinator",
        approved_by="IT Program Chairperson",
        approved_role="IT Program Chairperson",
        signatories=signatories,
        include_signatures=include_signatures,
    )

    return builder.build()
