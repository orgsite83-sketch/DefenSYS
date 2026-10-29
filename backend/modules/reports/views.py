import json
from decimal import Decimal
from datetime import datetime, date, timedelta
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.db.models import Q
from django.utils.dateparse import parse_date
from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from django.contrib.auth import get_user_model

from authentication_access_control.scopes import (
    is_admin_user,
    is_pit_lead_only,
    can_review_audit_logs,
    visible_teams_for,
    visible_schedules_for,
    grade_records_for,
    audit_logs_for,
)

from defense.scheduler.models import DefenseSchedule
from academic_period_management.models import Semester
from academic_period_management.services import active_semester
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.audit import log_high_impact_action, filter_audit_logs, audit_evidence

# PDF Generators
from reports.generators.semester_grades_report import generate_semester_grades_pdf
from reports.generators.defense_schedule_report import generate_defense_schedule_pdf
from reports.generators.team_roster_report import generate_team_roster_pdf
from reports.generators.user_directory_report import generate_user_directory_pdf
from reports.generators.audit_trail_report import generate_audit_trail_pdf, generate_audit_trail_xlsx
from reports.grade_summary import (
    GRADE_OUTCOME_NOTE,
    grade_outcome_label,
    outcome_breakdown,
    summarize_grade_records,
)

# Multi-Format & Preview Dispatcher
from reports.export_formatters import handle_export_or_preview

User = get_user_model()


class ReportAPIView(APIView):
    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        from reports.catalog_reports import validate_filters
        validate_filters(request.query_params)


def _parse_signature_params(request):
    """
    Extracts include_signatures (bool) and signatories (list of dicts) from request query params.
    """
    raw_inc = request.query_params.get('include_signatures')
    include_signatures = False
    if raw_inc is not None:
        include_signatures = str(raw_inc).strip().lower() in ('true', '1', 'yes')

    raw_sig = request.query_params.get('signatories')
    signatories = None
    if raw_sig:
        try:
            parsed = json.loads(raw_sig)
            if isinstance(parsed, list):
                signatories = parsed
        except (ValueError, TypeError):
            signatories = None

    return include_signatures, signatories


class TeamGradeReportView(ReportAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, team_id):
        from reports.assessment_reports import export_assessment_report
        include_signatures, signatories = _parse_signature_params(request)
        return export_assessment_report(
            request, team_id=team_id, include_signatures=include_signatures,
            signatories=signatories,
        )


class AssessmentCandidatesView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from reports.assessment_reports import assessment_candidates
        return assessment_candidates(request)


class IndividualGradeReportView(ReportAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, student_id):
        from reports.assessment_reports import export_assessment_report
        include_signatures, signatories = _parse_signature_params(request)
        return export_assessment_report(
            request, student_id=student_id, include_signatures=include_signatures,
            signatories=signatories,
        )


class SemesterGradesReportView(ReportAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        semester_id = request.query_params.get('semester_id')
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = active_semester()
            if not semester:
                return Response(
                    {"detail": "No active semester is configured."},
                    status=status.HTTP_400_BAD_REQUEST
                )
                
        current_period = active_semester()
        historical_period = current_period is None or current_period.pk != semester.pk
        base_queryset = grade_records_for(request.user, include_previous_projects=historical_period).filter(semester=semester)
        
        search = request.query_params.get('search', '').strip()
        year_level = request.query_params.get('year_level', '').strip()
        status_filter = request.query_params.get('status', '').strip()
        scope = request.query_params.get('scope', '').strip()
        stage_filter = request.query_params.get('stage_id') or request.query_params.get('stage') or request.query_params.get('stage_label')
        pit_event_filter = request.query_params.get('pit_event_config_id') or request.query_params.get('pit_event_id') or request.query_params.get('pit_event')
        
        queryset = base_queryset
        if search:
            queryset = queryset.filter(
                Q(team__name__icontains=search)
                | Q(team__project_title__icontains=search)
                | Q(stage_label__icontains=search)
                | Q(team__adviser__first_name__icontains=search)
                | Q(team__adviser__last_name__icontains=search)
                | Q(team__adviser__username__icontains=search)
            ).distinct()
        if year_level:
            from student_teams.capstone_lifecycle import filter_recorded_team_field
            source_teams = filter_recorded_team_field(visible_teams_for(request.user), semester, 'year_level', year_level)
            queryset = queryset.filter(team__in=source_teams)
        if request.query_params.get('section'):
            from student_teams.capstone_lifecycle import filter_recorded_team_field
            source_teams = filter_recorded_team_field(visible_teams_for(request.user), semester, 'section', request.query_params['section'])
            queryset = queryset.filter(team__in=source_teams)
        if status_filter:
            queryset = queryset.filter(status=status_filter)
        if scope and scope != 'all':
            queryset = queryset.filter(scope=scope)
            
        if stage_filter and stage_filter != 'all' and stage_filter != '':
            if str(stage_filter).isdigit():
                queryset = queryset.filter(defense_stage_id=int(stage_filter))
            else:
                queryset = queryset.filter(stage_label__icontains=stage_filter)
                
        if pit_event_filter and pit_event_filter != 'all' and pit_event_filter != '':
            if str(pit_event_filter).isdigit():
                queryset = queryset.filter(pit_event_config_id=int(pit_event_filter))
            else:
                queryset = queryset.filter(stage_label__icontains=pit_event_filter)
            
        grade_records = list(queryset.select_related('team', 'team__adviser', 'team__leader'))
        from student_teams.capstone_lifecycle import recorded_team
        for record in grade_records:
            record.team = recorded_team(record.team, semester)
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        
        summary = summarize_grade_records(grade_records)
        average_label = f"{summary['average']:.2f}%" if summary['average'] is not None else "N/A"

        # Determine dynamic title & subtitle
        if scope == 'capstone' and stage_filter:
            report_title = f"Capstone Stage Grade Report — {stage_filter}"
            scope_label = f"Capstone ({stage_filter})"
        elif scope == 'pit' and pit_event_filter:
            report_title = f"PIT Event Grade Report — {pit_event_filter}"
            scope_label = f"PIT ({pit_event_filter})"
        elif scope == 'capstone':
            report_title = "Capstone Grades Summary"
            scope_label = "Capstone (All Stages)"
        elif scope == 'pit':
            report_title = "PIT Events Grade Summary"
            scope_label = "PIT (All Events)"
        else:
            report_title = "Semester Grade Summary"
            scope_label = "All Academic Scopes (Capstone & PIT)"

        summary_kpis = [
            {'label': 'Teams in Report', 'value': str(summary['team_count'])},
            {'label': 'Stage / Event Records', 'value': str(summary['record_count'])},
            {'label': 'Passed / Approved', 'value': str(summary['outcomes']['passed'])},
            {'label': 'Mean Recorded Grade', 'value': average_label},
        ]

        metadata = [
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} — {semester.label}"},
            {'label': 'Academic Scope', 'value': scope_label},
            {'label': 'Teams in Report', 'value': str(summary['team_count'])},
            {'label': 'Stage / Event Records', 'value': str(summary['record_count'])},
            {'label': 'Outcome Breakdown', 'value': outcome_breakdown(summary)},
            {'label': 'Mean Recorded Grade', 'value': average_label},
            {'label': 'Outcome Basis', 'value': GRADE_OUTCOME_NOTE},
        ]

        columns = [
            {'key': 'scope', 'label': 'Scope', 'align': 'center'},
            {'key': 'team_name', 'label': 'Team Name', 'align': 'left'},
            {'key': 'project_title', 'label': 'Project Title', 'align': 'left'},
            {'key': 'section', 'label': 'Section', 'align': 'center'},
            {'key': 'stage', 'label': 'Stage / Event', 'align': 'left'},
            {'key': 'adviser', 'label': 'Adviser', 'align': 'left'},
            {'key': 'panel_score', 'type': 'percentage', 'label': 'Panel Score', 'align': 'center'},
            {'key': 'adviser_score', 'type': 'percentage', 'label': 'Adviser Score', 'align': 'center'},
            {'key': 'peer_score', 'type': 'percentage', 'label': 'Peer Score', 'align': 'center'},
            {'key': 'final_grade', 'type': 'percentage', 'label': 'Final Grade', 'align': 'center'},
            {'key': 'result', 'label': 'Outcome', 'align': 'center'},
        ]

        rows = []
        for gr in grade_records:
            sec = gr.team.section or gr.team.year_level or 'N/A'
            adv = f"{gr.team.adviser.first_name} {gr.team.adviser.last_name}".strip() if gr.team.adviser else "Unassigned"
            rows.append({
                'scope': 'Capstone' if gr.is_capstone else 'PIT',
                'team_name': gr.team.name,
                'project_title': gr.project_title_snapshot or gr.team.project_title or 'N/A',
                'section': sec,
                'stage': gr.stage_label,
                'adviser': adv,
                'panel_score': f"{gr.panel_score:.2f}%" if gr.panel_score is not None else "Pending",
                'adviser_score': f"{gr.adviser_score:.2f}%" if gr.adviser_score is not None else "N/A",
                'peer_score': f"{gr.peer_score:.2f}%" if gr.peer_score is not None else "Pending",
                'final_grade': f"{gr.final_grade:.2f}%" if gr.final_grade is not None else "Pending",
                'result': grade_outcome_label(gr),
            })

        sem_label_safe = "".join(c for c in semester.school_year.label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        clean_title = "".join(c for c in report_title if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_{clean_title}_{sem_label_safe}"

        include_signatures, signatories = _parse_signature_params(request)

        return handle_export_or_preview(
            export_format=export_format,
            title=report_title,
            subtitle=f"Official Compiled Grade Record — {semester.school_year.label} {semester.label}",
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename, generated_by=generated_by,
            include_signatures=include_signatures, signatories=signatories,
            pdf_generator_func=lambda: generate_semester_grades_pdf(
                semester, grade_records, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class DefenseScheduleReportView(ReportAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        semester_id = request.query_params.get('semester_id')
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = active_semester()
            if not semester:
                return Response(
                    {"detail": "No active semester is configured."},
                    status=status.HTTP_400_BAD_REQUEST
                )
                
        base_queryset = visible_schedules_for(request.user).filter(semester=semester)
        
        search = request.query_params.get('search', '').strip()
        scope = request.query_params.get('scope', '').strip()
        status_filter = request.query_params.get('status', '').strip()
        date_filter = request.query_params.get('date', '').strip()
        
        queryset = base_queryset
        if search:
            queryset = queryset.filter(
                Q(team__name__icontains=search)
                | Q(team__project_title__icontains=search)
                | Q(room__icontains=search)
                | Q(event_name__icontains=search)
            ).distinct()
        if scope and scope != 'all':
            queryset = queryset.filter(scope=scope)
        stage_filter = request.query_params.get('stage_id') or request.query_params.get('stage') or request.query_params.get('stage_label')
        if stage_filter and stage_filter != 'all' and stage_filter != '':
            if str(stage_filter).isdigit():
                queryset = queryset.filter(defense_stage_id=int(stage_filter))
            else:
                queryset = queryset.filter(Q(defense_stage__label__icontains=stage_filter) | Q(event_name__icontains=stage_filter))
        if status_filter:
            queryset = queryset.filter(status=status_filter)
        if date_filter:
            queryset = queryset.filter(scheduled_date=date_filter)
        if request.query_params.get('source_context') == 'defense-board':
            from defense.board.views import filter_board_queryset
            queryset = filter_board_queryset(request, base_queryset)
        else:
            if request.query_params.get('section'):
                queryset = queryset.filter(team__section__iexact=request.query_params['section'])
            adviser = request.query_params.get('adviser', '')
            if adviser.isdigit():
                queryset = queryset.filter(team__adviser_id=adviser)
        if request.query_params.get('start_date'):
            queryset = queryset.filter(scheduled_date__gte=request.query_params['start_date'])
        if request.query_params.get('end_date'):
            queryset = queryset.filter(scheduled_date__lte=request.query_params['end_date'])
            
        schedules = list(
            queryset.select_related('team', 'defense_stage', 'team__adviser')
            .prefetch_related('panel_assignments', 'panel_assignments__panelist')
            .order_by('scheduled_date', 'start_time')
        )
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        
        from defense.scheduler.progress import schedule_progress
        workflow = {s.pk: schedule_progress(s, reconcile_status=False) for s in schedules}
        confirmed_count = sum(1 for s in schedules if s.status == 'scheduled' and not workflow[s.pk]['is_completed'])
        completed_count = sum(1 for s in schedules if workflow[s.pk]['is_completed'])
        pending_count = len(schedules) - confirmed_count - completed_count

        summary_kpis = [
            {'label': 'Total Schedules', 'value': str(len(schedules))},
            {'label': 'Completed stages / events', 'value': str(completed_count)},
            {'label': 'Scheduled hearings', 'value': str(confirmed_count)},
            {'label': 'Other schedules', 'value': str(pending_count)},
        ]

        metadata = [
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} — {semester.label}"},
            {'label': 'Total Events', 'value': str(len(schedules))},
            {'label': 'Scheduled / Completed', 'value': f"{confirmed_count + completed_count} of {len(schedules)}"},
        ]

        columns = [
            {'key': 'scope', 'label': 'Scope', 'align': 'center'},
            {'key': 'scheduled_date', 'type': 'date', 'label': 'Date', 'align': 'center'},
            {'key': 'time_slot', 'label': 'Time Slot', 'align': 'center'},
            {'key': 'team_name', 'label': 'Team Name', 'align': 'left'},
            {'key': 'stage', 'label': 'Stage / Event', 'align': 'left'},
            {'key': 'room', 'label': 'Venue Room', 'align': 'center'},
            {'key': 'panelists', 'label': 'Panel Members', 'align': 'left'},
            {'key': 'adviser', 'label': 'Adviser', 'align': 'left'},
            {'key': 'status', 'label': 'Status', 'align': 'center'},
        ]

        rows = []
        for s in schedules:
            panelists_list = [
                f"{pa.panelist.first_name} {pa.panelist.last_name}".strip() or pa.panelist.username
                for pa in s.panel_assignments.all()
                if pa.panelist
            ]
            adv = f"{s.team.adviser.first_name} {s.team.adviser.last_name}".strip() if s.team and s.team.adviser else "Unassigned"
            t_name = s.team.name if s.team else "No Team Assigned"
            stage_lbl = s.defense_stage.label if s.defense_stage else (s.event_name or "Defense Event")
            if s.start_time:
                start_dt = datetime.combine(date.today(), s.start_time)
                end_dt = start_dt + timedelta(minutes=s.slot_duration or 60)
                start_str = start_dt.strftime('%I:%M %p')
                end_str = end_dt.strftime('%I:%M %p')
                time_slot_str = f"{start_str} - {end_str}"
            else:
                time_slot_str = "TBD"

            rows.append({
                'scope': 'Capstone' if s.scope == 'capstone' else 'PIT',
                'scheduled_date': s.scheduled_date.strftime('%Y-%m-%d') if s.scheduled_date else "Unscheduled",
                'time_slot': time_slot_str,
                'team_name': t_name,
                'stage': stage_lbl,
                'room': s.room or "TBA",
                'panelists': ", ".join(panelists_list) if panelists_list else "None assigned",
                'adviser': adv,
                'status': workflow[s.pk]['display_status'].replace('_', ' ').title(),
            })

        sem_label_safe = "".join(c for c in semester.school_year.label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_Defense_Schedules_{sem_label_safe}_{semester.label.replace(' ', '_')}"

        include_signatures, signatories = _parse_signature_params(request)

        return handle_export_or_preview(
            export_format=export_format,
            title="Defense Timetable & Schedule Summary",
            subtitle=f"Compiled Schedule Timetable — {semester.school_year.label} {semester.label}",
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename, generated_by=generated_by,
            include_signatures=include_signatures, signatories=signatories,
            pdf_generator_func=lambda: generate_defense_schedule_pdf(
                semester, schedules, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class TeamRosterReportView(ReportAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from student_teams.capstone_lifecycle import teams_in_recorded_term, filter_recorded_team_field, recorded_team
        from student_teams.models import TeamTermParticipation
        semester_id = request.query_params.get('semester_id')
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = active_semester()
            
        queryset = visible_teams_for(request.user)
        term_context = request.query_params.get('term_context')
        if term_context in ('history', 'active', 'all'):
            from student_teams.term_scope import apply_team_scope
            queryset = apply_team_scope(queryset, scope=term_context, user=request.user)
            if term_context in ('history', 'all') and not semester_id:
                semester = None
        history_base = queryset
        if semester:
            queryset = teams_in_recorded_term(queryset, semester)
            
        level = (request.query_params.get('scope') or request.query_params.get('level', '')).strip()
        if level == 'all':
            level = ''
        year_level = request.query_params.get('year_level', '').strip()
        
        if level:
            queryset = filter_recorded_team_field(queryset, semester, 'level', level, lookup='icontains') if semester else queryset.filter(level__icontains=level)
        if year_level:
            queryset = filter_recorded_team_field(queryset, semester, 'year_level', year_level) if semester else queryset.filter(year_level=year_level)
        for key in ('section', 'status'):
            if request.query_params.get(key):
                queryset = filter_recorded_team_field(queryset, semester, key, request.query_params[key]) if semester else queryset.filter(**{key: request.query_params[key]})
        search = request.query_params.get('search', '').strip()
        if search:
            live_search = Q(name__icontains=search) | Q(project_title__icontains=search)
            live_search |= (Q(leader__first_name__icontains=search) | Q(leader__last_name__icontains=search) | Q(leader__username__icontains=search)
                | Q(adviser__first_name__icontains=search) | Q(adviser__last_name__icontains=search) | Q(adviser__username__icontains=search))
            if semester:
                recorded = TeamTermParticipation.objects.filter(semester=semester, closed_at__isnull=False)
                matching = recorded.filter(Q(snapshot__name__icontains=search) | Q(snapshot__project_title__icontains=search)
                    | Q(snapshot__leader_name__icontains=search) | Q(snapshot__adviser_name__icontains=search))
                queryset = queryset.filter(Q(pk__in=matching.values('team_id')) | (live_search & ~Q(pk__in=recorded.values('team_id'))))
            else:
                queryset = queryset.filter(Q(name__icontains=search) | Q(project_title__icontains=search)
                | Q(leader__first_name__icontains=search) | Q(leader__last_name__icontains=search) | Q(leader__username__icontains=search)
                | Q(adviser__first_name__icontains=search) | Q(adviser__last_name__icontains=search) | Q(adviser__username__icontains=search))
        event = request.query_params.get('event_name') or request.query_params.get('pit_event')
        if event:
            from student_teams.pit_rosters import filter_teams
            queryset = filter_teams(queryset, event)
        elif request.query_params.get('roster_view') == 'current':
            from student_teams.pit_rosters import filter_teams
            queryset = filter_teams(queryset, current=True)
            
        teams = list(
            queryset.select_related('leader', 'adviser')
            .prefetch_related('memberships', 'memberships__student')
            .order_by('name')
        )
        if semester:
            teams = [recorded_team(team, semester) for team in teams]
        elif term_context in ('history', 'all'):
            records = TeamTermParticipation.objects.filter(team__in=history_base, closed_at__isnull=False).select_related('team__semester__school_year', 'semester__school_year')
            if term_context == 'history':
                records = records.exclude(semester=active_semester())
            covered = set(records.values_list('team_id', flat=True))
            teams = [team for team in teams if team.pk not in covered or (term_context == 'all' and team.semester_id == getattr(active_semester(), 'pk', None))]
            for record in records:
                data = record.snapshot
                if event or (level and level.casefold() not in data.get('level', '').casefold()):
                    continue
                if year_level and year_level != data.get('year_level'):
                    continue
                if any(request.query_params.get(key) and request.query_params[key] != data.get(key) for key in ('section', 'status')):
                    continue
                if search and search.casefold() not in ' '.join(str(data.get(key, '')) for key in ('name', 'project_title', 'leader_name', 'adviser_name')).casefold():
                    continue
                teams.append(recorded_team(record.team, record.semester))
        if term_context == 'history' and request.query_params.get('intake_id'):
            from student_teams.capstone_history import history_payload, history_teams_for
            from copy import copy
            candidates = history_teams_for(request.user)
            scoped = history_payload(candidates, request.query_params, user=request.user)
            by_id = {t.pk: t for t in candidates}
            terms = {t.pk: t for t in Semester.objects.select_related('school_year')}
            teams = [copy(recorded_team(by_id[r['id']], terms[r['semester_id']])) for r in scoped['teams']]
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username

        total_members_count = len({student_id for t in teams for student_id in (
            t._recorded_term.snapshot.get('member_ids', []) if hasattr(t, '_recorded_term') else
            t.memberships.values_list('student_id', flat=True))})

        summary_kpis = [
            {'label': 'Total Teams', 'value': str(len({t.pk for t in teams}))},
            {'label': 'Total Enrolled Students', 'value': str(total_members_count)},
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} {semester.label}" if semester else "All Semesters"},
        ]

        metadata = [
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} — {semester.label}" if semester else "All Records"},
            {'label': 'Total Active Teams', 'value': str(len(teams))},
            {'label': 'Total Members Enrolled', 'value': str(total_members_count)},
        ]

        columns = [
            {'key': 'period', 'label': 'Academic Period', 'align': 'left'},
            {'key': 'scope', 'label': 'Scope', 'align': 'center'},
            {'key': 'team_name', 'label': 'Team Name', 'align': 'left'},
            {'key': 'project_title', 'label': 'Project Title', 'align': 'left'},
            {'key': 'section', 'label': 'Section / Year', 'align': 'center'},
            {'key': 'leader', 'label': 'Team Leader', 'align': 'left'},
            {'key': 'adviser', 'label': 'Faculty Adviser', 'align': 'left'},
            {'key': 'members_count', 'type': 'integer', 'label': 'Size', 'align': 'center'},
            {'key': 'members_list', 'label': 'Team Members', 'align': 'left'},
        ]

        rows = []
        for t in teams:
            leader_name = f"{t.leader.first_name} {t.leader.last_name}".strip() if t.leader else "Unassigned"
            adviser_name = f"{t.adviser.first_name} {t.adviser.last_name}".strip() if t.adviser else "Unassigned"
            members = [
                f"{m.student.first_name} {m.student.last_name}".strip() or m.student.username
                for m in t.memberships.all()
                if m.student
            ]
            if hasattr(t, '_recorded_term'):
                frozen = t._recorded_term.snapshot
                leader_name = frozen.get('leader_name') or 'Unassigned'
                adviser_name = frozen.get('adviser_name') or 'Unassigned'
                members = [member.get('name') or member.get('username') or '' for member in frozen.get('members', [])]
            rows.append({
                'period': t.semester.display_name,
                'scope': 'PIT' if t.is_pit else 'Capstone',
                'team_name': t.name,
                'project_title': t.project_title or 'N/A',
                'section': f"{t.section or ''} {t.year_level or ''}".strip() or 'N/A',
                'leader': leader_name,
                'adviser': adviser_name,
                'members_count': str(len(members)),
                'members_list': ", ".join(members) if members else "None",
            })

        sem_label = f"_{semester.school_year.label}_{semester.label}" if semester else ""
        sem_label_safe = "".join(c for c in sem_label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_Team_Roster{sem_label_safe}"

        include_signatures, signatories = _parse_signature_params(request)

        return handle_export_or_preview(
            export_format=export_format,
            title="Student Team Directory Roster",
            subtitle=f"Official Directory — {semester.school_year.label} {semester.label}" if semester else "All Teams",
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename, generated_by=generated_by,
            include_signatures=include_signatures, signatories=signatories,
            pdf_generator_func=lambda: generate_team_roster_pdf(
                semester, teams, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class UserDirectoryReportView(ReportAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if not is_admin_user(request.user):
            raise PermissionDenied("Only administrators can export the complete user directory.")
            
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        role = request.query_params.get('role', '').strip()
        status_filter = request.query_params.get('status', '').strip()
        
        queryset = User.objects.all()
        search = request.query_params.get('search', '').strip()
        if search:
            queryset = queryset.filter(Q(first_name__icontains=search) | Q(last_name__icontains=search) | Q(username__icontains=search) | Q(email__icontains=search))
        if role:
            queryset = queryset.filter(role=role)
        if status_filter:
            is_active = status_filter.lower() == 'active'
            queryset = queryset.filter(is_active=is_active)
            
        users = list(queryset.order_by('role', 'username'))
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        
        active_count = sum(1 for u in users if u.is_active)
        students_count = sum(1 for u in users if u.role == 'student')
        faculty_count = sum(1 for u in users if u.role in ('faculty', 'panelist'))

        summary_kpis = [
            {'label': 'Total Accounts', 'value': str(len(users))},
            {'label': 'Active Users', 'value': str(active_count)},
            {'label': 'Students', 'value': str(students_count)},
            {'label': 'Faculty & Panelists', 'value': str(faculty_count)},
        ]

        metadata = [
            {'label': 'Total Accounts Exported', 'value': str(len(users))},
            {'label': 'Active / Inactive', 'value': f"{active_count} Active / {len(users) - active_count} Inactive"},
            {'label': 'Role Filter', 'value': role.upper() if role else 'ALL ROLES'},
        ]

        columns = [
            {'key': 'username', 'label': 'User ID / Username', 'align': 'left'},
            {'key': 'full_name', 'label': 'Full Name', 'align': 'left'},
            {'key': 'role', 'label': 'System Role', 'align': 'center'},
            {'key': 'email', 'label': 'Email Address', 'align': 'left'},
            {'key': 'status', 'label': 'Status', 'align': 'center'},
            {'key': 'date_joined', 'type': 'date', 'label': 'Date Registered', 'align': 'center'},
        ]

        rows = []
        for u in users:
            name = f"{u.first_name} {u.last_name}".strip() or "N/A"
            rows.append({
                'username': u.username,
                'full_name': name,
                'role': u.role.upper() if u.role else "USER",
                'email': u.email or "N/A",
                'status': "ACTIVE" if u.is_active else "INACTIVE",
                'date_joined': u.date_joined.strftime('%Y-%m-%d') if u.date_joined else "N/A",
            })

        filename = f"DefenSYS_User_Directory_{datetime.now().strftime('%Y-%m-%d')}"

        include_signatures, signatories = _parse_signature_params(request)

        return handle_export_or_preview(
            export_format=export_format,
            title="System User Account Directory",
            subtitle=f"Export generated on {datetime.now().strftime('%Y-%m-%d %I:%M %p')}",
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename, generated_by=generated_by,
            include_signatures=include_signatures, signatories=signatories,
            pdf_generator_func=lambda: generate_user_directory_pdf(
                users, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class AuditTrailReportView(ReportAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if not can_review_audit_logs(request.user):
            raise PermissionDenied("You do not have permission to view or export the Audit Trail logs.")
            
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        base_queryset = audit_logs_for(request.user)
        queryset = base_queryset
        
        category = request.query_params.get('category', '').strip()
        action = request.query_params.get('action', '').strip()
        review_status = request.query_params.get('review_status', '').strip()
        actor_id = request.query_params.get('actor', '').strip()
        search = request.query_params.get('search', '').strip()
        start_date = parse_date(request.query_params.get('start_date', '').strip())
        end_date = parse_date(request.query_params.get('end_date', '').strip())
        track = request.query_params.get('track', '').strip().lower()
        year_level = request.query_params.get('year_level', '').strip()
        log_id = request.query_params.get('log_id', '').strip()

        filters_desc = {}
        if log_id:
            queryset = queryset.filter(id=log_id)
            filters_desc['Audit Entry ID'] = f"#{log_id}"
        if category:
            filters_desc['Category'] = category
        if action:
            filters_desc['Action'] = action
        if review_status:
            filters_desc['Review Status'] = review_status
        if actor_id:
            actor = User.objects.filter(id=actor_id).first()
            if actor:
                filters_desc['Responsible User'] = f"{actor.first_name} {actor.last_name}".strip() or actor.username
        if start_date:
            filters_desc['Start Date'] = start_date.strftime('%Y-%m-%d')
        if end_date:
            filters_desc['End Date'] = end_date.strftime('%Y-%m-%d')
        if track:
            filters_desc['Academic Track'] = track.upper()
        if year_level:
            filters_desc['Year Level'] = year_level
        if search:
            filters_desc['Search query'] = search
            
        queryset = filter_audit_logs(base_queryset, request.query_params)
        if log_id:
            queryset = queryset.filter(id=log_id)
        queryset = queryset.order_by('-created_at', '-id')
        try:
            limit = min(max(int(request.query_params.get('limit', 1000)), 1), 2000)
        except (TypeError, ValueError):
            return Response({'detail': 'Limit must be an integer.'}, status=status.HTTP_400_BAD_REQUEST)
        logs = list(queryset.select_related('actor').prefetch_related('reviews')[:limit])
        from authentication_access_control.audit_references import AuditReferenceResolver
        reference_resolver = AuditReferenceResolver(logs)
        matching_count = queryset.count() if len(logs) == limit else len(logs)
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username

        summary_kpis = [
            {'label': 'Total Audit Events', 'value': str(len(logs))},
            {'label': 'Category Filter', 'value': category.upper() if category else 'ALL CATEGORIES'},
            {'label': 'Date Range', 'value': f"{filters_desc.get('Start Date', 'Start')} to {filters_desc.get('End Date', 'Now')}" if (start_date or end_date) else 'All Recorded Time'},
        ]

        metadata = [
            {'label': 'Total Events', 'value': str(len(logs))},
            {'label': 'Category Filter', 'value': category.upper() if category else 'ALL'},
            {'label': 'Date Scope', 'value': f"{filters_desc.get('Start Date', 'All')} → {filters_desc.get('End Date', 'Present')}"},
            {'label': 'Time Zone', 'value': timezone.get_current_timezone_name()},
            {'label': 'Review Tracking', 'value': 'Evidence captured means saved event data; pending review means no current completed review.'},
        ]
        if matching_count > len(logs):
            metadata.append({'label': 'Export Scope', 'value': f'Latest {len(logs)} of {matching_count} matching events (export limit {limit}).'})
            filters_desc['Export Scope'] = f'Latest {len(logs)} of {matching_count} matching events'
        for label, value in filters_desc.items():
            if label not in ('Category', 'Start Date', 'End Date', 'Export Scope'):
                metadata.append({'label': label, 'value': value})

        columns = [
            {'key': 'created_at', 'label': 'Timestamp', 'align': 'center', 'type': 'datetime', 'width': 23, 'number_format': 'm/d/yyyy hh:mm'},
            {'key': 'actor', 'label': 'Responsible User', 'align': 'left'},
            {'key': 'category', 'label': 'Category', 'align': 'center'},
            {'key': 'action', 'label': 'Action', 'align': 'left'},
            {'key': 'target', 'label': 'Target Entity', 'align': 'left'},
            {'key': 'reason', 'label': 'Reason for Change', 'align': 'left', 'width': 44},
            {'key': 'evidence_status', 'label': 'Evidence Status', 'align': 'left', 'width': 26, 'link_to': 'Event Evidence'},
            {'key': 'review_status', 'label': 'Review Status', 'align': 'left'},
            {'key': 'reviewed_by', 'label': 'Reviewed By', 'align': 'left'},
            {'key': 'reviewer_role', 'label': 'Reviewer Role', 'align': 'left'},
            {'key': 'reviewed_at', 'label': 'Last Review Timestamp', 'align': 'left', 'type': 'datetime', 'width': 23, 'number_format': 'm/d/yyyy hh:mm'},
            {'key': 'review_history', 'label': 'Review History', 'align': 'left', 'width': 36, 'link_to': 'Review History'},
        ]

        rows = []
        for log in logs:
            actor_name = (log.actor.get_full_name().strip() or log.actor.username) if log.actor else 'System'
            evidence = audit_evidence(log)
            has_review = bool(log.reviewed_by_name or log.reviewed_at or log.review_status == 'reviewed')
            rows.append({
                'event_id': log.pk,
                'created_at': timezone.localtime(log.created_at).isoformat() if log.created_at else 'Not recorded',
                'actor': actor_name,
                'category': log.category.upper() if log.category else "SYSTEM",
                'action': log.action,
                'target': reference_resolver.target_label(log),
                'evidence_status': evidence['label'],
                'evidence_summary': evidence['summary'],
                'reason_required': evidence['reason_required'],
                'reason': log.reason or ('Reason required - not recorded' if evidence['reason_required'] else 'Not required for this event'),
                'review_status': 'Reviewed' if log.review_status == 'reviewed' else 'Pending review',
                'reviewed_by': log.reviewed_by_name or ('Reviewer not recorded' if has_review else 'Pending review'),
                'reviewer_role': ('PIT Lead · ' + log.reviewed_by_year) if log.reviewed_by_role == 'pit_lead' else ('Admin' if log.reviewed_by_role == 'admin' else ('Not recorded' if has_review else 'Not applicable')),
                'reviewed_at': timezone.localtime(log.reviewed_at).isoformat() if log.reviewed_at else ('Not recorded' if has_review else 'Not reviewed'),
                'review_history': '\n'.join(
                    f'{review.created_at.isoformat()} | {review.reviewer_name} '
                    f'({"PIT Lead - " + review.reviewer_year if review.reviewer_role == "pit_lead" else ("Admin" if review.reviewer_role == "admin" else "Role not recorded")}) | '
                    f'{review.get_from_status_display()} -> {review.get_to_status_display()} | {review.reason}'
                    for review in log.reviews.all()
                ) or 'No review history recorded',
            })

        if log_id and len(logs) == 1:
            title = f"Audit Evidence Certificate — Entry #{log_id}"
            filename = f"DefenSYS_Audit_Evidence_#{log_id}_{datetime.now().strftime('%Y-%m-%d')}"
        else:
            title = "Institutional Audit & Compliance Register"
            filename = f"DefenSYS_Audit_Register_{datetime.now().strftime('%Y-%m-%d')}"

        include_signatures, signatories = _parse_signature_params(request)

        if (export_format or '').strip().lower() in ('xlsx', 'excel', 'sheet'):
            return generate_audit_trail_xlsx(
                logs, title, metadata, columns, rows, filename, generated_by,
                include_signatures=include_signatures, signatories=signatories,
            )

        return handle_export_or_preview(
            export_format=export_format,
            title=title,
            subtitle=f"Log extract generated on {datetime.now().strftime('%Y-%m-%d %I:%M %p')}",
            xlsx_generator_func=lambda: generate_audit_trail_xlsx(
                logs, title, metadata, columns, rows, filename, generated_by,
                include_signatures=include_signatures, signatories=signatories,
            ),
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename, generated_by=generated_by,
            include_signatures=include_signatures, signatories=signatories,
            pdf_generator_func=lambda: generate_audit_trail_pdf(
                logs, filters_desc, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )
