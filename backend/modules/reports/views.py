import json
from decimal import Decimal
from datetime import datetime, date, timedelta
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.db.models import Q
from django.utils.dateparse import parse_date
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

from grading.grades.models import TeamGrade, StudentStageGrade
from defense.scheduler.models import DefenseSchedule
from academic_period_management.models import Semester
from academic_period_management.services import active_semester
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.audit import log_high_impact_action

# PDF Generators
from reports.generators.team_grade_report import generate_team_grade_pdf
from reports.generators.individual_grade_report import generate_individual_grade_pdf
from reports.generators.semester_grades_report import generate_semester_grades_pdf
from reports.generators.defense_schedule_report import generate_defense_schedule_pdf
from reports.generators.team_roster_report import generate_team_roster_pdf
from reports.generators.user_directory_report import generate_user_directory_pdf
from reports.generators.audit_trail_report import generate_audit_trail_pdf

# Multi-Format & Preview Dispatcher
from reports.export_formatters import handle_export_or_preview

User = get_user_model()


def _parse_signature_params(request):
    """
    Extracts include_signatures (bool) and signatories (list of dicts) from request query params.
    """
    raw_inc = request.query_params.get('include_signatures')
    include_signatures = True
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


class TeamGradeReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, team_id):
        visible_grades = grade_records_for(request.user).filter(team_id=team_id)
        if not visible_grades.exists():
            raise PermissionDenied("You do not have permission to view grade reports for this team.")
        
        grade_id = request.query_params.get('grade_id')
        stage_id = request.query_params.get('stage_id')
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        
        if grade_id:
            grade_record = get_object_or_404(visible_grades, pk=grade_id)
        elif stage_id:
            grade_record = get_object_or_404(visible_grades, defense_stage_id=stage_id)
        else:
            grade_record = visible_grades.order_by('-created_at').first()
            
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        
        team = grade_record.team
        semester = grade_record.semester
        
        # Build Summary KPIs
        summary_kpis = [
            {'label': 'Final Grade', 'value': f"{grade_record.final_grade:.2f}%" if grade_record.final_grade is not None else "Pending", 'badge': grade_record.result.upper() if grade_record.result else 'PENDING'},
            {'label': 'Panel Score', 'value': f"{grade_record.panel_score:.2f}% ({grade_record.panel_weight}%)" if grade_record.panel_score is not None else "N/A"},
            {'label': 'Adviser Score', 'value': f"{grade_record.adviser_score:.2f}% ({grade_record.adviser_weight}%)" if grade_record.adviser_score is not None else "N/A"},
            {'label': 'Peer Score', 'value': f"{grade_record.peer_score:.2f}% ({grade_record.peer_weight}%)" if grade_record.peer_score is not None else "N/A"},
        ]
        
        leader_name = f"{team.leader.first_name} {team.leader.last_name}".strip() or team.leader.username if team.leader else 'N/A'
        adviser_name = f"{team.adviser.first_name} {team.adviser.last_name}".strip() or team.adviser.username if team.adviser else 'N/A'

        metadata = [
            {'label': 'Team Name', 'value': team.name},
            {'label': 'Project Title', 'value': team.project_title or 'N/A'},
            {'label': 'Section / Year', 'value': f"{team.section or ''} {team.year_level or ''}".strip() or 'N/A'},
            {'label': 'Defense Stage', 'value': grade_record.stage_label},
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} {semester.label}" if semester else 'N/A'},
            {'label': 'Leader', 'value': leader_name},
            {'label': 'Adviser', 'value': adviser_name},
            {'label': 'Overall Result', 'value': grade_record.result.upper() if grade_record.result else 'PENDING'},
        ]
        
        # Build distinct panelists list
        submissions = list(grade_record.panelist_submissions.all().prefetch_related('criterion_scores', 'panelist'))
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

        # Columns for Master Student Grade Sheet Matrix
        columns = [
            {'key': 'no', 'label': 'No.', 'align': 'center'},
            {'key': 'name', 'label': 'Names', 'align': 'left'},
        ]

        for pan in distinct_panelists:
            columns.append({
                'key': f'panel_{pan["index"]}',
                'label': f'Panel {pan["index"]} ({pan["name"]})',
                'align': 'center',
            })

        columns.append({'key': 'panel_avg', 'label': 'Average', 'align': 'center'})
        columns.append({'key': 'panel_weighted', 'label': f'GRADE {grade_record.panel_weight}%', 'align': 'center'})

        if grade_record.is_capstone and grade_record.adviser_weight > 0:
            columns.append({'key': 'adviser_rating', 'label': "Adviser's Rating", 'align': 'center'})
            columns.append({'key': 'adviser_weighted', 'label': f'{grade_record.adviser_weight}%', 'align': 'center'})

        columns.append({'key': 'peer_rating', 'label': 'Peer Rating', 'align': 'center'})
        columns.append({'key': 'peer_weighted', 'label': f'{grade_record.peer_weight}%', 'align': 'center'})
        columns.append({'key': 'total', 'label': 'TOTAL', 'align': 'center'})
        columns.append({'key': 'final_grade', 'label': 'FINAL GRADE', 'align': 'center'})

        # Rows for Master Student Grade Sheet Matrix
        members = []
        if team.leader:
            members.append((team.leader, True))
        for m in team.members.all():
            if m != team.leader:
                members.append((m, False))

        rows = []
        for idx, (student, is_leader) in enumerate(members, start=1):
            st_name = student.get_full_name() or student.username
            st_name_display = f"{st_name} (LEADER)" if is_leader else st_name
            sg = grade_record.student_grades.filter(student=student).first()

            row_data = {
                'no': str(idx),
                'name': st_name_display,
            }

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
                    row_data[f'panel_{pan["index"]}'] = f"{p_score:.1f}%"
                else:
                    row_data[f'panel_{pan["index"]}'] = "—"

            p_avg = (sum(panel_scores, Decimal('0')) / Decimal(len(panel_scores))).quantize(Decimal('0.01')) if panel_scores else grade_record.panel_score
            row_data['panel_avg'] = f"{p_avg:.2f}%" if p_avg is not None else "—"

            p_w = (p_avg * Decimal(grade_record.panel_weight) / Decimal('100')).quantize(Decimal('0.01')) if p_avg is not None else Decimal('0.00')
            row_data['panel_weighted'] = f"{p_w:.2f}" if p_avg is not None else "—"

            adv_score = grade_record.adviser_score
            adv_w = (adv_score * Decimal(grade_record.adviser_weight) / Decimal('100')).quantize(Decimal('0.01')) if (adv_score is not None and grade_record.adviser_weight > 0) else Decimal('0.00')
            if grade_record.is_capstone and grade_record.adviser_weight > 0:
                row_data['adviser_rating'] = f"{adv_score:.2f}%" if adv_score is not None else "—"
                row_data['adviser_weighted'] = f"{adv_w:.2f}" if adv_score is not None else "—"

            peer_score = sg.peer_score if (sg and sg.peer_score is not None) else grade_record.peer_score
            peer_w = (peer_score * Decimal(grade_record.peer_weight) / Decimal('100')).quantize(Decimal('0.01')) if peer_score is not None else Decimal('0.00')
            row_data['peer_rating'] = f"{peer_score:.2f}%" if peer_score is not None else "—"
            row_data['peer_weighted'] = f"{peer_w:.2f}" if peer_score is not None else "—"

            total = p_w + adv_w + peer_w
            row_data['total'] = f"{total:.2f}"

            final_g = sg.final_grade if (sg and sg.final_grade is not None) else total
            status_str = "PASSED" if (final_g is not None and final_g >= Decimal('75.00')) else ("FAILED" if final_g is not None else "PENDING")
            row_data['final_grade'] = f"{final_g:.2f}%  [{status_str}]" if final_g is not None else "PENDING"

            rows.append(row_data)

        # Fallback if no members found
        if not rows:
            rows.append({
                'no': '1',
                'name': leader_name,
                'panel_avg': f"{grade_record.panel_score:.2f}%" if grade_record.panel_score is not None else "—",
                'panel_weighted': f"{(grade_record.panel_score * Decimal(grade_record.panel_weight) / Decimal('100')):.2f}" if grade_record.panel_score is not None else "—",
                'peer_rating': f"{grade_record.peer_score:.2f}%" if grade_record.peer_score is not None else "—",
                'peer_weighted': f"{(grade_record.peer_score * Decimal(grade_record.peer_weight) / Decimal('100')):.2f}" if grade_record.peer_score is not None else "—",
                'total': f"{grade_record.final_grade:.2f}" if grade_record.final_grade is not None else "—",
                'final_grade': f"{grade_record.final_grade:.2f}%  [{grade_record.result.upper() if grade_record.result else 'PENDING'}]" if grade_record.final_grade is not None else "PENDING",
            })
            
        team_name_safe = "".join(c for c in grade_record.team.name if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        stage_safe = "".join(c for c in grade_record.stage_label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_Team_Grade_{team_name_safe}_{stage_safe}"

        # Audit Trail Logging if not preview
        if export_format not in ('json', 'preview', 'data'):
            log_high_impact_action(
                category='compliance',
                action='report.generate_team_grade',
                target=grade_record.team,
                target_id=grade_record.team.id,
                reason=f"Exported Team Grade Report ({export_format or 'pdf'}) for {grade_record.team.name} ({grade_record.stage_label})",
                request=request,
                new_values={
                    'team_id': grade_record.team.id,
                    'team_name': grade_record.team.name,
                    'stage': grade_record.stage_label,
                    'format': export_format or 'pdf',
                },
            )

        include_signatures, signatories = _parse_signature_params(request)

        return handle_export_or_preview(
            export_format=export_format,
            title=f"Team Grade Report — {grade_record.team.name}",
            subtitle=f"Stage: {grade_record.stage_label} • Period: {semester.school_year.label} {semester.label}" if semester else grade_record.stage_label,
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename,
            pdf_generator_func=lambda: generate_team_grade_pdf(
                grade_record, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class IndividualGradeReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, student_id):
        student = get_object_or_404(User, pk=student_id, role='student')
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        
        is_self = request.user.id == student.id
        team = None
        if hasattr(student, 'led_teams') and student.led_teams.exists():
            team = student.led_teams.first()
        if not team:
            membership = getattr(student, 'team_memberships', None)
            if membership and membership.exists():
                team = membership.first().team
        if not team:
            team = StudentTeam.objects.filter(Q(leader=student) | Q(members=student)).first()
        
        if not is_self:
            if team:
                visible_grades = grade_records_for(request.user).filter(team=team)
                if not visible_grades.exists() and not is_admin_user(request.user):
                    raise PermissionDenied("You do not have permission to generate individual grade audit cards for this student.")
            else:
                if not is_admin_user(request.user):
                    raise PermissionDenied("You do not have permission to view this student's grade audit card.")

        if not team:
            return Response(
                {"detail": "This student is not currently assigned to a team."},
                status=status.HTTP_404_NOT_FOUND,
            )

        grade_id = request.query_params.get('grade_id')
        stage_id = request.query_params.get('stage_id')
        semester_id = request.query_params.get('semester_id')

        team_grades = TeamGrade.objects.filter(team=team)
        if semester_id:
            team_grades = team_grades.filter(semester_id=semester_id)
        if grade_id:
            team_grade = get_object_or_404(team_grades, pk=grade_id)
        elif stage_id:
            team_grade = get_object_or_404(team_grades, defense_stage_id=stage_id)
        else:
            team_grade = team_grades.order_by('-updated_at', '-id').first()

        if not team_grade:
            return Response(
                {"detail": "No evaluation records found for this student."},
                status=status.HTTP_404_NOT_FOUND,
            )

        student_grade = StudentStageGrade.objects.filter(team_grade=team_grade, student=student).first()
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        
        student_name = student.get_full_name() or student.username
        semester = team_grade.semester
        
        # Effective individual grades
        st_final = student_grade.final_grade if student_grade and student_grade.final_grade is not None else team_grade.final_grade
        st_result = "PASSED" if (st_final is not None and st_final >= Decimal('75.00')) else ("FAILED" if st_final is not None else (team_grade.result.upper() if team_grade.result else 'PENDING'))
        peer_score_str = f"{student_grade.peer_score:.2f}%" if (student_grade and student_grade.peer_score is not None) else (f"{team_grade.peer_score:.2f}%" if team_grade.peer_score is not None else "N/A")

        summary_kpis = [
            {'label': 'Student ID', 'value': student.username},
            {'label': 'Individual Final Grade', 'value': f"{st_final:.2f}%" if st_final is not None else "Pending", 'badge': st_result},
            {'label': 'Base Team Grade', 'value': f"{team_grade.final_grade:.2f}%" if team_grade.final_grade is not None else "Pending"},
            {'label': 'Peer Score', 'value': peer_score_str},
        ]

        metadata = [
            {'label': 'Student Name', 'value': student_name},
            {'label': 'Student ID', 'value': student.username},
            {'label': 'Assigned Team', 'value': team.name},
            {'label': 'Project Title', 'value': team.project_title or 'N/A'},
            {'label': 'Section / Year', 'value': f"{team.section or ''} {team.year_level or ''}".strip() or 'N/A'},
            {'label': 'Defense Stage', 'value': team_grade.stage_label},
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} {semester.label}" if semester else 'N/A'},
            {'label': 'Final Outcome', 'value': st_result},
        ]

        columns = [
            {'key': 'component', 'label': 'Grade Component', 'align': 'left'},
            {'key': 'weight', 'label': 'Contribution', 'align': 'center'},
            {'key': 'score', 'label': 'Score / Rating', 'align': 'center'},
            {'key': 'remarks', 'label': 'Evaluation & Peer Remarks', 'align': 'left'},
        ]

        rows = [
            {
                'component': 'Base Team Defense Score',
                'weight': f"{team_grade.panel_weight}% Panel",
                'score': f"{team_grade.panel_score:.2f}%" if team_grade.panel_score is not None else "Pending",
                'remarks': 'Panelists defense deliberation average',
            },
            {
                'component': 'Adviser Evaluation Score',
                'weight': f"{team_grade.adviser_weight}% Adviser",
                'score': f"{team_grade.adviser_score:.2f}%" if team_grade.adviser_score is not None else "N/A",
                'remarks': f"Assessed by {team.adviser.first_name} {team.adviser.last_name}".strip() if team.adviser else "Faculty Adviser",
            },
            {
                'component': 'Peer Evaluation Score',
                'weight': f"{team_grade.peer_weight}% Peer",
                'score': peer_score_str,
                'remarks': 'Peer group individual contribution rating',
            },
            {
                'component': 'FINAL INDIVIDUAL CERTIFIED GRADE',
                'weight': 'Composite',
                'score': f"{st_final:.2f}%" if st_final is not None else "Pending",
                'remarks': f"Official Audit Status: {st_result}",
            },
        ]

        student_name_safe = "".join(c for c in student_name if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        stage_safe = "".join(c for c in team_grade.stage_label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_Individual_Grade_{student_name_safe}_{stage_safe}"

        if export_format not in ('json', 'preview', 'data'):
            log_high_impact_action(
                category='compliance',
                action='report.generate_individual_grade',
                target=student,
                target_id=student.id,
                reason=f"Exported Individual Grade Audit ({export_format or 'pdf'}) for {student.username} ({team_grade.stage_label})",
                request=request,
                new_values={
                    'student_id': student.id,
                    'student_name': student_name,
                    'team_id': team.id,
                    'team_name': team.name,
                    'stage': team_grade.stage_label,
                    'format': export_format or 'pdf',
                },
            )

        include_signatures, signatories = _parse_signature_params(request)

        return handle_export_or_preview(
            export_format=export_format,
            title=f"Individual Grade Audit — {student_name}",
            subtitle=f"ID: {student.username} • Team: {team.name} • Stage: {team_grade.stage_label}",
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename,
            pdf_generator_func=lambda: generate_individual_grade_pdf(
                student, student_grade, team_grade, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class SemesterGradesReportView(APIView):
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
                
        base_queryset = grade_records_for(request.user).filter(semester=semester)
        
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
            queryset = queryset.filter(team__year_level=year_level)
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
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        
        # Summary metrics
        total_records = len(grade_records)
        passed_count = sum(1 for g in grade_records if g.result == 'passed')
        failed_count = sum(1 for g in grade_records if g.result == 'failed')
        pending_count = sum(1 for g in grade_records if g.result == 'pending' or not g.result)
        completed_grades = [g.final_grade for g in grade_records if g.final_grade is not None]
        avg_grade = sum(completed_grades) / len(completed_grades) if completed_grades else Decimal('0.00')

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
            {'label': 'Total Graded Teams', 'value': str(total_records)},
            {'label': 'Passed Count', 'value': str(passed_count), 'badge': 'PASSED'},
            {'label': 'Revisions / Failed', 'value': str(failed_count), 'badge': 'REVISION' if failed_count > 0 else 'NONE'},
            {'label': 'Cohort Average', 'value': f"{avg_grade:.2f}%" if completed_grades else "N/A"},
        ]

        metadata = [
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} — {semester.label}"},
            {'label': 'Academic Scope', 'value': scope_label},
            {'label': 'Total Graded Teams', 'value': str(total_records)},
            {'label': 'Passed / Failed / Pending', 'value': f"{passed_count} Passed / {failed_count} Failed / {pending_count} Pending"},
            {'label': 'Cohort Average Grade', 'value': f"{avg_grade:.2f}%" if completed_grades else "N/A"},
        ]

        columns = [
            {'key': 'team_name', 'label': 'Team Name', 'align': 'left'},
            {'key': 'project_title', 'label': 'Project Title', 'align': 'left'},
            {'key': 'section', 'label': 'Section', 'align': 'center'},
            {'key': 'stage', 'label': 'Stage / Event', 'align': 'left'},
            {'key': 'adviser', 'label': 'Adviser', 'align': 'left'},
            {'key': 'panel_score', 'label': 'Panel Score', 'align': 'center'},
            {'key': 'adviser_score', 'label': 'Adviser Score', 'align': 'center'},
            {'key': 'peer_score', 'label': 'Peer Score', 'align': 'center'},
            {'key': 'final_grade', 'label': 'Final Grade', 'align': 'center'},
            {'key': 'result', 'label': 'Result', 'align': 'center'},
        ]

        rows = []
        for gr in grade_records:
            sec = gr.team.section or gr.team.year_level or 'N/A'
            adv = f"{gr.team.adviser.first_name} {gr.team.adviser.last_name}".strip() if gr.team.adviser else "Unassigned"
            rows.append({
                'team_name': gr.team.name,
                'project_title': gr.team.project_title or 'N/A',
                'section': sec,
                'stage': gr.stage_label,
                'adviser': adv,
                'panel_score': f"{gr.panel_score:.2f}%" if gr.panel_score is not None else "Pending",
                'adviser_score': f"{gr.adviser_score:.2f}%" if gr.adviser_score is not None else "N/A",
                'peer_score': f"{gr.peer_score:.2f}%" if gr.peer_score is not None else "Pending",
                'final_grade': f"{gr.final_grade:.2f}%" if gr.final_grade is not None else "Pending",
                'result': gr.result.upper() if gr.result else "PENDING",
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
            filename=filename,
            pdf_generator_func=lambda: generate_semester_grades_pdf(
                semester, grade_records, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class DefenseScheduleReportView(APIView):
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
                queryset = queryset.filter(Q(stage_label__icontains=stage_filter) | Q(event_name__icontains=stage_filter))
        if status_filter:
            queryset = queryset.filter(status=status_filter)
        if date_filter:
            queryset = queryset.filter(scheduled_date=date_filter)
            
        schedules = list(
            queryset.select_related('team', 'defense_stage', 'team__adviser')
            .prefetch_related('panel_assignments', 'panel_assignments__panelist')
            .order_by('scheduled_date', 'start_time')
        )
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        
        confirmed_count = sum(1 for s in schedules if s.status == 'confirmed')
        completed_count = sum(1 for s in schedules if s.status == 'completed')
        pending_count = len(schedules) - confirmed_count - completed_count

        summary_kpis = [
            {'label': 'Total Schedules', 'value': str(len(schedules))},
            {'label': 'Completed Defenses', 'value': str(completed_count)},
            {'label': 'Confirmed / Upcoming', 'value': str(confirmed_count)},
            {'label': 'Pending Assignment', 'value': str(pending_count)},
        ]

        metadata = [
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} — {semester.label}"},
            {'label': 'Total Events', 'value': str(len(schedules))},
            {'label': 'Confirmed / Completed', 'value': f"{confirmed_count + completed_count} of {len(schedules)}"},
        ]

        columns = [
            {'key': 'scheduled_date', 'label': 'Date', 'align': 'center'},
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
                'scheduled_date': s.scheduled_date.strftime('%Y-%m-%d') if s.scheduled_date else "Unscheduled",
                'time_slot': time_slot_str,
                'team_name': t_name,
                'stage': stage_lbl,
                'room': s.room or "TBA",
                'panelists': ", ".join(panelists_list) if panelists_list else "None assigned",
                'adviser': adv,
                'status': s.status.upper() if s.status else "PENDING",
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
            filename=filename,
            pdf_generator_func=lambda: generate_defense_schedule_pdf(
                semester, schedules, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class TeamRosterReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        semester_id = request.query_params.get('semester_id')
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = active_semester()
            
        queryset = visible_teams_for(request.user)
        if semester:
            queryset = queryset.filter(semester=semester)
            
        level = request.query_params.get('level', '').strip()
        year_level = request.query_params.get('year_level', '').strip()
        
        if level:
            queryset = queryset.filter(level__icontains=level)
        if year_level:
            queryset = queryset.filter(year_level=year_level)
            
        teams = list(
            queryset.select_related('leader', 'adviser')
            .prefetch_related('memberships', 'memberships__student')
            .order_by('name')
        )
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        
        total_members_count = sum(t.memberships.count() for t in teams)

        summary_kpis = [
            {'label': 'Total Teams', 'value': str(len(teams))},
            {'label': 'Total Enrolled Students', 'value': str(total_members_count)},
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} {semester.label}" if semester else "All Semesters"},
        ]

        metadata = [
            {'label': 'Academic Period', 'value': f"{semester.school_year.label} — {semester.label}" if semester else "All Records"},
            {'label': 'Total Active Teams', 'value': str(len(teams))},
            {'label': 'Total Members Enrolled', 'value': str(total_members_count)},
        ]

        columns = [
            {'key': 'team_name', 'label': 'Team Name', 'align': 'left'},
            {'key': 'project_title', 'label': 'Project Title', 'align': 'left'},
            {'key': 'section', 'label': 'Section / Year', 'align': 'center'},
            {'key': 'leader', 'label': 'Team Leader', 'align': 'left'},
            {'key': 'adviser', 'label': 'Faculty Adviser', 'align': 'left'},
            {'key': 'members_count', 'label': 'Size', 'align': 'center'},
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
            rows.append({
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
            filename=filename,
            pdf_generator_func=lambda: generate_team_roster_pdf(
                semester, teams, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class UserDirectoryReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if not is_admin_user(request.user):
            raise PermissionDenied("Only administrators can export the complete user directory.")
            
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        role = request.query_params.get('role', '').strip()
        status_filter = request.query_params.get('status', '').strip()
        
        queryset = User.objects.all()
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
            {'key': 'date_joined', 'label': 'Date Registered', 'align': 'center'},
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
            filename=filename,
            pdf_generator_func=lambda: generate_user_directory_pdf(
                users, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )


class AuditTrailReportView(APIView):
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
            queryset = queryset.filter(category=category)
            filters_desc['Category'] = category
        if action:
            queryset = queryset.filter(action=action)
            filters_desc['Action'] = action
        if review_status:
            queryset = queryset.filter(review_status=review_status)
            filters_desc['Review Status'] = review_status
        if actor_id:
            queryset = queryset.filter(actor_id=actor_id)
            actor = User.objects.filter(id=actor_id).first()
            if actor:
                filters_desc['Responsible User'] = f"{actor.first_name} {actor.last_name}".strip() or actor.username
        if start_date:
            queryset = queryset.filter(created_at__date__gte=start_date)
            filters_desc['Start Date'] = start_date.strftime('%Y-%m-%d')
        if end_date:
            queryset = queryset.filter(created_at__date__lte=end_date)
            filters_desc['End Date'] = end_date.strftime('%Y-%m-%d')
        if track:
            filters_desc['Academic Track'] = track.upper()
            pit_marker = (
                Q(old_values__entry_type='pit')
                | Q(new_values__entry_type='pit')
                | Q(old_values__scope='pit')
                | Q(new_values__scope='pit')
                | Q(old_values__track='pit')
                | Q(new_values__track='pit')
            )
            if track == 'pit':
                queryset = queryset.filter(pit_marker)
            elif track == 'capstone':
                pit_ids = queryset.filter(pit_marker).values_list('id', flat=True)
                queryset = queryset.exclude(id__in=pit_ids)
        if year_level:
            filters_desc['Year Level'] = year_level
            year_marker = (
                Q(old_values__year_level=year_level)
                | Q(new_values__year_level=year_level)
                | Q(old_values__team_year_level=year_level)
                | Q(new_values__team_year_level=year_level)
                | Q(old_values__pit_year_level=year_level)
                | Q(new_values__pit_year_level=year_level)
            )
            queryset = queryset.filter(year_marker)
        if search:
            queryset = queryset.filter(
                Q(action__icontains=search)
                | Q(target_type__icontains=search)
                | Q(target_id__icontains=search)
                | Q(reason__icontains=search)
            )
            filters_desc['Search query'] = search
            
        queryset = queryset.order_by('-created_at')
        limit = min(max(int(request.query_params.get('limit', 1000)), 1), 2000)
        logs = list(queryset.select_related('actor')[:limit])
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
        ]

        columns = [
            {'key': 'created_at', 'label': 'Timestamp', 'align': 'center'},
            {'key': 'actor', 'label': 'Responsible User', 'align': 'left'},
            {'key': 'category', 'label': 'Category', 'align': 'center'},
            {'key': 'action', 'label': 'Action', 'align': 'left'},
            {'key': 'target', 'label': 'Target Entity', 'align': 'left'},
            {'key': 'reason', 'label': 'Audit Reason / Description', 'align': 'left'},
        ]

        rows = []
        for log in logs:
            actor_name = f"{log.actor.first_name} {log.actor.last_name}".strip() or log.actor.username if log.actor else (log.actor_display or "System")
            rows.append({
                'created_at': log.created_at.strftime('%Y-%m-%d %H:%M') if log.created_at else "N/A",
                'actor': actor_name,
                'category': log.category.upper() if log.category else "SYSTEM",
                'action': log.action,
                'target': f"{log.target_type or 'Entity'}: {log.target_id or ''}".strip(': '),
                'reason': log.reason or "No details provided",
            })

        if log_id and len(logs) == 1:
            title = f"Audit Evidence Certificate — Entry #{log_id}"
            filename = f"DefenSYS_Audit_Evidence_#{log_id}_{datetime.now().strftime('%Y-%m-%d')}"
        else:
            title = "Institutional Audit & Compliance Register"
            filename = f"DefenSYS_Audit_Register_{datetime.now().strftime('%Y-%m-%d')}"

        include_signatures, signatories = _parse_signature_params(request)

        return handle_export_or_preview(
            export_format=export_format,
            title=title,
            subtitle=f"Log extract generated on {datetime.now().strftime('%Y-%m-%d %I:%M %p')}",
            summary_kpis=summary_kpis,
            metadata=metadata,
            columns=columns,
            rows=rows,
            filename=filename,
            pdf_generator_func=lambda: generate_audit_trail_pdf(
                logs, filters_desc, generated_by, signatories=signatories, include_signatures=include_signatures
            ),
        )
