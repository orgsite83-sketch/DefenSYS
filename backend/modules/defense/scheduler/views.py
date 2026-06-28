from django.core.exceptions import ValidationError
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from grading.grades.models import GradeBreakdown, TeamGrade
from grading.rubrics.models import Rubric
from grading.grades.services import (
    GradeContextService,
    guest_panelist_remark_key,
    panelist_remark_key_for_user,
    panelist_result_payload,
    require_grade_editable,
    submit_panelist_grade,
    weights_for_schedule,
)
from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.guest_authentication import (
    GuestJWTAuthentication,
    IsGuestPanelist,
)
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.scopes import visible_schedules_for
from user_management.permissions import IsPanelist

from .models import DefenseSchedule, SchedulePanelist, PitEventGradingConfig
from academic_period_management.models import Semester

from .pit_config import get_pit_event_config, pit_event_config_payload, upsert_pit_event_config
from .serializers import (
    ConfirmSchedulePlanSerializer,
    DefenseScheduleSerializer,
    DefenseScheduleStatusSerializer,
    DefenseSchedulePatchSerializer,
    DefenseScheduleWriteSerializer,
    GenerateSchedulePlanSerializer,
    active_semester,
    schedule_options_payload,
    schedule_queryset,
)


class CanManageSchedules(BasePermission):
    message = 'Only administrators and PIT leads can manage defense schedules.'

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and (
                getattr(user, 'role', None) == 'admin'
                or user.is_superuser
                or getattr(user, 'is_pit_lead', False)
            )
        )


def counts_payload(queryset=None, base_queryset=None):
    base = base_queryset if base_queryset is not None else schedule_queryset()
    current = queryset if queryset is not None else base
    return {
        'all': base.count(),
        'filtered': current.count(),
        'scheduled': current.filter(status=DefenseSchedule.STATUS_SCHEDULED).count(),
        'done': current.filter(status=DefenseSchedule.STATUS_DONE).count(),
        'cancelled': current.filter(status=DefenseSchedule.STATUS_CANCELLED).count(),
        'archived': current.filter(status=DefenseSchedule.STATUS_ARCHIVED).count(),
    }


def schedule_audit_values(schedule, **extra):
    values = {
        **audit_scope_metadata(scope=schedule.scope, team=schedule.team),
        'schedule_id': schedule.pk,
        'scheduled_date': schedule.scheduled_date.isoformat() if schedule.scheduled_date else '',
        'start_time': schedule.start_time.isoformat() if schedule.start_time else '',
        'room': schedule.room,
        'stage_label': schedule.stage_label,
    }
    values.update(extra)
    return values


def list_payload(queryset=None, base_queryset=None, user=None, include_options=True):
    base = base_queryset if base_queryset is not None else schedule_queryset()
    current = queryset if queryset is not None else base
    payload = {
        'schedules': DefenseScheduleSerializer(current, many=True).data,
        'counts': counts_payload(current, base_queryset=base),
    }
    if include_options:
        payload.update(schedule_options_payload(user=user))
    return payload


def filter_schedules(request, queryset=None):
    queryset = queryset if queryset is not None else schedule_queryset()
    search = request.query_params.get('search', '').strip()
    scope = request.query_params.get('scope', '').strip()
    status_filter = request.query_params.get('status', '').strip()
    date = request.query_params.get('date', '').strip()

    if search:
        queryset = queryset.filter(
            Q(team__name__icontains=search)
            | Q(team__project_title__icontains=search)
            | Q(room__icontains=search)
            | Q(event_name__icontains=search)
            | Q(defense_stage__label__icontains=search)
            | Q(panel_assignments__panelist__first_name__icontains=search)
            | Q(panel_assignments__panelist__last_name__icontains=search)
            | Q(panel_assignments__panelist__username__icontains=search)
        ).distinct()
    if scope:
        queryset = queryset.filter(scope=scope)
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    if date:
        queryset = queryset.filter(scheduled_date=date)
    return queryset


class DefenseScheduleListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [CanManageSchedules()]

    def get(self, request):
        base = visible_schedules_for(request.user)
        can_manage = CanManageSchedules().has_permission(request, self)
        return Response(
            list_payload(
                filter_schedules(request, base),
                base_queryset=base,
                user=request.user,
                include_options=can_manage,
            )
        )

    def post(self, request):
        serializer = DefenseScheduleWriteSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        schedule = serializer.save()
        base = visible_schedules_for(request.user)
        schedule = base.get(pk=schedule.pk)
        return Response(
            {
                'schedule': DefenseScheduleSerializer(schedule).data,
                **list_payload(base_queryset=base, user=request.user),
            },
            status=status.HTTP_201_CREATED,
        )


class PitEventConfigLookupView(APIView):
    permission_classes = [CanManageSchedules]

    def get(self, request):
        semester_id = request.query_params.get('semester_id')
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = active_semester()
            if semester is None:
                return Response(
                    {'detail': 'No active semester is configured.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        event_name = request.query_params.get('event_name', '').strip()
        if not event_name:
            configs = PitEventGradingConfig.objects.filter(semester=semester).prefetch_related('deliverables').order_by('event_name')
            return Response({'configs': [pit_event_config_payload(c) for c in configs]})

        config = get_pit_event_config(semester, event_name)
        if config is None:
            default_config = {
                'id': None,
                'event_name': event_name,
                'panel_rubric_id': None,
                'peer_rubric_id': None,
                'panel_weight': 80,
                'peer_weight': 20,
                'is_officially_complete': False,
                'peer_grading_enabled': False,
                'vault_file_template': '',
                'deliverables': [],
            }
            return Response({'config': default_config})
        return Response({'config': pit_event_config_payload(config)})

    def delete(self, request):
        config_id = request.query_params.get('config_id')
        if not config_id:
            return Response(
                {'detail': 'config_id query parameter is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        config = get_object_or_404(PitEventGradingConfig, pk=config_id)
        config.delete()
        return Response({'success': True}, status=status.HTTP_200_OK)

    def post(self, request):
        event_name = request.data.get('event_name', '').strip()
        if not event_name:
            return Response(
                {'detail': 'event_name is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        semester_id = request.data.get('semester_id')
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = active_semester()
            if semester is None:
                return Response(
                    {'detail': 'No active semester is configured.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        panel_rubric_id = request.data.get('panel_rubric_id')
        peer_rubric_id = request.data.get('peer_rubric_id')
        
        try:
            panel_weight = int(request.data.get('panel_weight'))
            peer_weight = int(request.data.get('peer_weight'))
        except (TypeError, ValueError):
            return Response(
                {'detail': 'panel_weight and peer_weight must be integers.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        vault_file_template = request.data.get('vault_file_template')
        deliverables = request.data.get('deliverables')
        if deliverables is not None and not isinstance(deliverables, list):
            return Response(
                {'detail': 'deliverables must be a list.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Retrieve Rubrics
        panel_rubric = get_object_or_404(Rubric, pk=panel_rubric_id)
        peer_rubric = get_object_or_404(Rubric, pk=peer_rubric_id)

        try:
            config = upsert_pit_event_config(
                semester=semester,
                event_name=event_name,
                panel_rubric=panel_rubric,
                peer_rubric=peer_rubric,
                panel_weight=panel_weight,
                peer_weight=peer_weight,
                vault_file_template=vault_file_template,
                deliverables=deliverables,
            )
            return Response({'config': pit_event_config_payload(config)}, status=status.HTTP_200_OK)
        except ValidationError as e:
            return Response(
                {'detail': e.message if hasattr(e, 'message') else str(e)},
                status=status.HTTP_400_BAD_REQUEST,
            )


class DefenseScheduleGeneratePlanView(APIView):
    permission_classes = [CanManageSchedules]

    def post(self, request):
        serializer = GenerateSchedulePlanSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        slots = serializer.generate_slots()
        return Response({
            'slots': slots,
            'slot_count': len(slots),
            **schedule_options_payload(user=request.user),
        })


class DefenseScheduleConfirmPlanView(APIView):
    permission_classes = [CanManageSchedules]

    def post(self, request):
        serializer = ConfirmSchedulePlanSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        schedules = serializer.save()
        base = visible_schedules_for(request.user)
        schedules = base.filter(pk__in=[schedule.pk for schedule in schedules])
        return Response(
            {
                'schedules_created': DefenseScheduleSerializer(schedules, many=True).data,
                'created_count': schedules.count(),
                **list_payload(base_queryset=base, user=request.user),
            },
            status=status.HTTP_201_CREATED,
        )


class DefenseScheduleDetailView(APIView):
    permission_classes = [CanManageSchedules]

    def get_object(self, schedule_id):
        return get_object_or_404(visible_schedules_for(self.request.user), pk=schedule_id)

    def patch(self, request, schedule_id):
        schedule = self.get_object(schedule_id)
        old_status = schedule.status
        serializer = DefenseSchedulePatchSerializer(
            data=request.data,
            context={'schedule': schedule},
        )
        serializer.is_valid(raise_exception=True)
        schedule = serializer.save()
        if old_status != schedule.status:
            log_high_impact_action(
                category=SystemAuditLog.CATEGORY_SCHEDULING,
                action='schedule.status_change',
                target=schedule,
                old_values=schedule_audit_values(schedule, status=old_status),
                new_values=schedule_audit_values(schedule, status=schedule.status),
                request=request,
            )
        base = visible_schedules_for(request.user)
        schedule = base.get(pk=schedule.pk)
        return Response({
            'schedule': DefenseScheduleSerializer(schedule).data,
            **list_payload(base_queryset=base, user=request.user),
        })

    def delete(self, request, schedule_id):
        schedule = self.get_object(schedule_id)
        audit_values = schedule_audit_values(schedule, status=schedule.status)
        schedule_pk = schedule.pk
        schedule.delete()
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_SCHEDULING,
            action='schedule.delete',
            target=schedule,
            target_type='DefenseSchedule',
            target_id=schedule_pk,
            old_values=audit_values,
            new_values={'deleted': True},
            request=request,
        )
        base = visible_schedules_for(request.user)
        return Response(list_payload(base_queryset=base, user=request.user), status=status.HTTP_200_OK)


def _grade_weights_payload(schedule, raw_weights):
    payload = {
        'panel': raw_weights['panel_weight'],
        'peer': raw_weights['peer_weight'],
    }
    if schedule.scope == DefenseSchedule.SCOPE_CAPSTONE:
        payload['adviser'] = raw_weights.get('adviser_weight', 0)
    return payload


def _panel_rubric_payload(rubric, grade_weights):
    if rubric is None:
        return None
    return {
        'id': rubric.id,
        'name': rubric.name,
        'status': rubric.status,
        'evaluation_type': rubric.evaluation_type,
        'scope': rubric.scope,
        'context_label': rubric.context_label,
        'display_semester': rubric.semester.display_name,
        'target_type': rubric.target_type,
        'criteria': [
            {
                'id': criterion.id,
                'name': criterion.name,
                'max_score': criterion.max_score,
                'scale': criterion.scale,
                'description': criterion.description,
            }
            for criterion in rubric.criteria.all()
        ],
        'weights': grade_weights,
    }


def _panelist_has_schedule_assignment(user, team_id, schedule_id=None):
    qs = SchedulePanelist.objects.filter(
        panelist=user,
        schedule__team_id=team_id,
        schedule__status=DefenseSchedule.STATUS_SCHEDULED,
    )
    if schedule_id is not None:
        qs = qs.filter(schedule_id=schedule_id)
    return qs.exists()


class PanelistAssignmentsView(APIView):
    """
    API endpoint for panelists to view their assigned defense schedules.
    Returns teams and rubrics assigned to the authenticated panelist.
    """
    permission_classes = [IsAuthenticated, IsPanelist]

    def get(self, request):
        panelist_id = request.user.id
        requested_id = request.query_params.get('panelist_id', '').strip()
        if requested_id:
            try:
                if int(requested_id) != panelist_id:
                    return Response(
                        {'detail': 'You do not have permission to view another panelist\'s assignments.'},
                        status=status.HTTP_403_FORBIDDEN,
                    )
            except ValueError:
                return Response(
                    {'detail': 'panelist_id must be a valid integer.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        schedules = (
            schedule_queryset()
            .filter(
                panel_assignments__panelist_id=panelist_id,
                status=DefenseSchedule.STATUS_SCHEDULED,
            )
            .select_related('rubric__semester', 'semester', 'defense_stage')
            .prefetch_related('team__memberships__student', 'rubric__criteria')
            .distinct()
            .order_by('scheduled_date', 'start_time', 'team__name')
        )

        teams_data = []
        rubrics_data = []
        seen_rubric_ids = set()

        for schedule in schedules:
            team = schedule.team
            raw_weights = weights_for_schedule(schedule)
            grade_weights = _grade_weights_payload(schedule, raw_weights)
            panel_rubric = _panel_rubric_payload(schedule.rubric, grade_weights)

            teams_data.append({
                'id': team.id,
                'schedule_id': schedule.id,
                'scope': schedule.scope,
                'is_capstone': schedule.scope == DefenseSchedule.SCOPE_CAPSTONE,
                'event_name': schedule.event_name or '',
                'name': team.name,
                'project_title': team.project_title or '',
                'defense_stage': schedule.stage_label,
                'scheduled_date': schedule.scheduled_date.isoformat(),
                'start_time': schedule.start_time.strftime('%H:%M'),
                'room': schedule.room,
                'grade_weights': grade_weights,
                'panel_rubric': panel_rubric,
                'members': [
                    {
                        'id': m.student_id,
                        'name': f'{m.student.first_name} {m.student.last_name}'.strip() or m.student.username,
                        'username': m.student.username,
                    }
                    for m in team.memberships.all()
                ],
            })

            if schedule.rubric_id and schedule.rubric_id not in seen_rubric_ids:
                rubrics_data.append(panel_rubric)
                seen_rubric_ids.add(schedule.rubric_id)

        return Response({
            'teams': teams_data,
            'rubrics': [item for item in rubrics_data if item is not None],
            'schedules_count': schedules.count(),
        })



class PanelistResultsView(APIView):
    """Completed panel grades for the authenticated panelist (Results tab)."""

    permission_classes = [IsAuthenticated, IsPanelist]

    def get(self, request):
        panelist_key = panelist_remark_key_for_user(request.user)
        grade_ids = (
            GradeBreakdown.objects.filter(
                evaluation_type=GradeBreakdown.EVAL_PANEL,
                remarks__startswith=panelist_key,
            )
            .values_list('team_grade_id', flat=True)
            .distinct()
        )
        team_grades = (
            TeamGrade.objects.filter(id__in=grade_ids)
            .select_related('team', 'team__leader', 'schedule')
            .prefetch_related(
                'breakdowns',
                'student_grades',
                'student_grades__student',
                'team__memberships',
                'team__memberships__student',
            )
            .order_by('-schedule__scheduled_date', '-schedule__start_time', 'team__name')
        )

        results = []
        for grade in team_grades:
            if not _panelist_has_schedule_assignment(
                request.user,
                grade.team_id,
                grade.schedule_id,
            ):
                continue
            item = panelist_result_payload(grade, panelist_key)
            if item:
                results.append(item)

        results.sort(
            key=lambda row: (
                row.pop('_sort_date', None) or '',
                str(row.pop('_sort_time', None) or ''),
                row.get('teamName', ''),
            ),
            reverse=True,
        )

        return Response({'results': results})


class PanelistGradeSubmissionView(APIView):
    """
    API endpoint for panelists to submit their grades for a team.
    Creates or updates grade breakdown entries for the panelist's evaluation.
    """
    permission_classes = [IsAuthenticated, IsPanelist]

    def post(self, request):
        team_id = request.data.get('team_id')
        schedule_id = request.data.get('schedule_id')
        body_panelist_id = request.data.get('panelist_id')

        submissions_payload = request.data.get('submissions')
        if not submissions_payload:
            criteria_scores = request.data.get('criteria_scores', [])
            remarks = request.data.get('remarks', '')
            if not criteria_scores:
                return Response(
                    {'detail': 'team_id and criteria_scores or submissions are required.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            submissions_payload = [{
                'student_id': None,
                'criteria_scores': criteria_scores,
                'remarks': remarks,
            }]

        if not team_id:
            return Response(
                {'detail': 'team_id is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not isinstance(submissions_payload, list) or not submissions_payload:
            return Response(
                {'detail': 'submissions must be a non-empty list.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if body_panelist_id is not None and str(body_panelist_id) != str(request.user.id):
            return Response(
                {'detail': 'You do not have permission to submit grades for another panelist.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        try:
            from student_teams.models import StudentTeam
            from academic_period_management.models import Semester

            panelist = request.user

            try:
                team = StudentTeam.objects.get(id=team_id)
            except StudentTeam.DoesNotExist:
                return Response(
                    {'detail': 'Team not found.'},
                    status=status.HTTP_404_NOT_FOUND,
                )

            schedule = None
            if schedule_id:
                schedule = (
                    schedule_queryset()
                    .filter(pk=schedule_id, team=team)
                    .first()
                )
            if schedule is None:
                schedule = (
                    schedule_queryset()
                    .filter(
                        team=team,
                        panel_assignments__panelist=panelist,
                        status=DefenseSchedule.STATUS_SCHEDULED,
                    )
                    .first()
                )

            if not _panelist_has_schedule_assignment(
                panelist,
                team.id,
                schedule.id if schedule else None,
            ):
                return Response(
                    {'detail': 'You are not assigned to grade this team.'},
                    status=status.HTTP_403_FORBIDDEN,
                )

            if schedule:
                from django.utils import timezone
                current_date = timezone.localtime(timezone.now()).date()
                if schedule.scheduled_date > current_date:
                    return Response(
                        {'detail': f'Grading is locked until the scheduled date: {schedule.scheduled_date.strftime("%B %d, %Y")}.'},
                        status=status.HTTP_400_BAD_REQUEST,
                    )

            semester = team.semester or Semester.objects.filter(is_active=True).first()
            if not semester:
                return Response(
                    {'error': 'No active semester found'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            if schedule:
                team_grade = GradeContextService.get_for_panel_submission(schedule, panelist=panelist)
            else:
                team_grade, _created = GradeContextService.get_or_create_unscheduled_team(
                    team=team,
                )

            if team_grade.status in TeamGrade.LOCKED_STATUSES:
                return Response(
                    {'detail': 'Grades for this team have already been finalized and cannot be changed.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            try:
                require_grade_editable(team_grade)
            except ValidationError as e:
                return Response(
                    {'detail': e.message if hasattr(e, 'message') else str(e)},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            target_type = 'team'
            if schedule and schedule.rubric:
                target_type = schedule.rubric.target_type

            is_individual = (target_type == 'individual')
            is_both = (target_type == 'both')

            memberships = list(team.memberships.select_related('student').all())
            team_student_ids = {m.student_id for m in memberships}

            from django.db import transaction
            with transaction.atomic():
                for item in submissions_payload:
                    student_id = item.get('student_id')
                    student = None
                    if is_individual:
                        if student_id in (None, ''):
                            return Response(
                                {'detail': 'student_id is required for individual rubric grading.'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                        try:
                            student_id_int = int(student_id)
                        except (TypeError, ValueError):
                            return Response(
                                {'detail': 'student_id must be an integer.'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                        if student_id_int not in team_student_ids:
                            return Response(
                                {'detail': f'Student with ID {student_id} is not a member of this team.'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                        student = next(m.student for m in memberships if m.student_id == student_id_int)
                    elif is_both:
                        if student_id not in (None, ''):
                            try:
                                student_id_int = int(student_id)
                            except (TypeError, ValueError):
                                return Response(
                                    {'detail': 'student_id must be an integer.'},
                                    status=status.HTTP_400_BAD_REQUEST,
                                )
                            if student_id_int not in team_student_ids:
                                return Response(
                                    {'detail': f'Student with ID {student_id} is not a member of this team.'},
                                    status=status.HTTP_400_BAD_REQUEST,
                                )
                            student = next(m.student for m in memberships if m.student_id == student_id_int)

                    item_criteria_scores = item.get('criteria_scores', [])
                    item_remarks = item.get('remarks', '')

                    submit_panelist_grade(
                        schedule,
                        team_grade,
                        item_criteria_scores,
                        panelist=panelist,
                        remarks=item_remarks,
                        student=student,
                    )

            team_grade.refresh_from_db()
            return Response({
                'success': True,
                'message': 'Grades submitted successfully',
                'team_grade_id': team_grade.id,
                'panel_score': float(team_grade.panel_score) if team_grade.panel_score else None,
            }, status=status.HTTP_201_CREATED)

        except ValidationError as e:
            errors = e.message_dict if hasattr(e, 'message_dict') else {'detail': e.messages[0] if e.messages else str(e)}
            if isinstance(errors, dict) and 'detail' not in errors and 'error' not in errors:
                first_key = list(errors.keys())[0]
                first_val = errors[first_key]
                first_msg = first_val[0] if isinstance(first_val, list) else first_val
                errors['detail'] = f"{first_key}: {first_msg}"
            return Response(
                errors,
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as e:
            return Response(
                {'error': f'Failed to submit grades: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


def _team_assignment_payload(schedule):
    team = schedule.team
    raw_weights = weights_for_schedule(schedule)
    grade_weights = _grade_weights_payload(schedule, raw_weights)
    panel_rubric = _panel_rubric_payload(schedule.rubric, grade_weights)
    return {
        'id': team.id,
        'schedule_id': schedule.id,
        'scope': schedule.scope,
        'is_capstone': schedule.scope == DefenseSchedule.SCOPE_CAPSTONE,
        'event_name': schedule.event_name or '',
        'name': team.name,
        'project_title': team.project_title or '',
        'defense_stage': schedule.stage_label,
        'scheduled_date': schedule.scheduled_date.isoformat(),
        'start_time': schedule.start_time.strftime('%H:%M'),
        'room': schedule.room,
        'grade_weights': grade_weights,
        'panel_rubric': panel_rubric,
        'members': [
            {
                'id': m.student_id,
                'name': f'{m.student.first_name} {m.student.last_name}'.strip() or m.student.username,
                'username': m.student.username,
            }
            for m in team.memberships.all()
        ],
    }


class GuestPanelistResultsView(APIView):
    """Completed panel grades for a guest panelist (Results tab)."""

    authentication_classes = [GuestJWTAuthentication]
    permission_classes = [IsGuestPanelist]

    def get(self, request):
        principal = request.user
        panelist_key = guest_panelist_remark_key(principal.guest_name, principal.guest_code)
        grade_ids = (
            GradeBreakdown.objects.filter(
                evaluation_type=GradeBreakdown.EVAL_PANEL,
                remarks__startswith=panelist_key,
            )
            .values_list('team_grade_id', flat=True)
            .distinct()
        )
        team_grades = (
            TeamGrade.objects.filter(
                id__in=grade_ids,
                schedule_id=principal.defense_schedule_id,
            )
            .select_related('team', 'team__leader', 'schedule')
            .prefetch_related(
                'breakdowns',
                'student_grades',
                'student_grades__student',
                'team__memberships',
                'team__memberships__student',
            )
        )

        results = []
        for grade in team_grades:
            item = panelist_result_payload(grade, panelist_key)
            if item:
                results.append(item)

        return Response({'results': results})


class GuestPanelistAssignmentsView(APIView):
    """Assignments for a guest panelist JWT (single defense schedule)."""

    authentication_classes = [GuestJWTAuthentication]
    permission_classes = [IsGuestPanelist]

    def get(self, request):
        principal = request.user
        schedule = (
            schedule_queryset()
            .filter(
                pk=principal.defense_schedule_id,
                status=DefenseSchedule.STATUS_SCHEDULED,
            )
            .select_related('rubric__semester', 'semester', 'defense_stage', 'team')
            .prefetch_related('team__memberships__student', 'rubric__criteria')
            .first()
        )
        if schedule is None:
            return Response(
                {'detail': 'Defense schedule is not available for grading.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        team_payload = _team_assignment_payload(schedule)
        rubric = team_payload.get('panel_rubric')
        return Response({
            'teams': [team_payload],
            'rubrics': [rubric] if rubric else [],
            'schedules_count': 1,
        })


class GuestPanelistGradeSubmissionView(APIView):
    """Submit panel grades for the guest's assigned defense schedule."""

    authentication_classes = [GuestJWTAuthentication]
    permission_classes = [IsGuestPanelist]

    def post(self, request):
        principal = request.user
        team_id = request.data.get('team_id')
        schedule_id = request.data.get('schedule_id')

        submissions_payload = request.data.get('submissions')
        if not submissions_payload:
            criteria_scores = request.data.get('criteria_scores', [])
            remarks = request.data.get('remarks', '')
            if not criteria_scores:
                return Response(
                    {'detail': 'team_id and criteria_scores or submissions are required.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            submissions_payload = [{
                'student_id': None,
                'criteria_scores': criteria_scores,
                'remarks': remarks,
            }]

        if not team_id:
            return Response(
                {'detail': 'team_id is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not isinstance(submissions_payload, list) or not submissions_payload:
            return Response(
                {'detail': 'submissions must be a non-empty list.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if str(team_id) != str(principal.team_id):
            return Response(
                {'detail': 'You are not assigned to grade this team.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        if schedule_id is not None and str(schedule_id) != str(principal.defense_schedule_id):
            return Response(
                {'detail': 'You are not assigned to grade this schedule.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        try:
            from student_teams.models import StudentTeam

            try:
                team = StudentTeam.objects.get(id=team_id)
            except StudentTeam.DoesNotExist:
                return Response(
                    {'detail': 'Team not found.'},
                    status=status.HTTP_404_NOT_FOUND,
                )

            schedule = (
                schedule_queryset()
                .filter(
                    pk=principal.defense_schedule_id,
                    team=team,
                    status=DefenseSchedule.STATUS_SCHEDULED,
                )
                .first()
            )
            if schedule is None:
                return Response(
                    {'detail': 'You are not assigned to grade this team.'},
                    status=status.HTTP_403_FORBIDDEN,
                )

            from django.utils import timezone
            current_date = timezone.localtime(timezone.now()).date()
            if schedule.scheduled_date > current_date:
                return Response(
                    {'detail': f'Grading is locked until the scheduled date: {schedule.scheduled_date.strftime("%B %d, %Y")}.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            semester = team.semester or Semester.objects.filter(is_active=True).first()
            if not semester:
                return Response(
                    {'error': 'No active semester found'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            team_grade = GradeContextService.get_for_guest_panel_submission(schedule, guest=principal)

            if team_grade.status in TeamGrade.LOCKED_STATUSES:
                return Response(
                    {'detail': 'Grades for this team have already been finalized and cannot be changed.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            try:
                require_grade_editable(team_grade)
            except ValidationError as e:
                return Response(
                    {'detail': e.message if hasattr(e, 'message') else str(e)},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            target_type = 'team'
            if schedule and schedule.rubric:
                target_type = schedule.rubric.target_type

            is_individual = (target_type == 'individual')
            is_both = (target_type == 'both')

            memberships = list(team.memberships.select_related('student').all())
            team_student_ids = {m.student_id for m in memberships}

            from django.db import transaction
            with transaction.atomic():
                for item in submissions_payload:
                    student_id = item.get('student_id')
                    student = None
                    if is_individual:
                        if student_id in (None, ''):
                            return Response(
                                {'detail': 'student_id is required for individual rubric grading.'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                        try:
                            student_id_int = int(student_id)
                        except (TypeError, ValueError):
                            return Response(
                                {'detail': 'student_id must be an integer.'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                        if student_id_int not in team_student_ids:
                            return Response(
                                {'detail': f'Student with ID {student_id} is not a member of this team.'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                        student = next(m.student for m in memberships if m.student_id == student_id_int)
                    elif is_both:
                        if student_id not in (None, ''):
                            try:
                                student_id_int = int(student_id)
                            except (TypeError, ValueError):
                                return Response(
                                    {'detail': 'student_id must be an integer.'},
                                    status=status.HTTP_400_BAD_REQUEST,
                                )
                            if student_id_int not in team_student_ids:
                                return Response(
                                    {'detail': f'Student with ID {student_id} is not a member of this team.'},
                                    status=status.HTTP_400_BAD_REQUEST,
                                )
                            student = next(m.student for m in memberships if m.student_id == student_id_int)

                    item_criteria_scores = item.get('criteria_scores', [])
                    item_remarks = item.get('remarks', '')

                    submit_panelist_grade(
                        schedule,
                        team_grade,
                        item_criteria_scores,
                        guest=principal,
                        remarks=item_remarks,
                        student=student,
                    )

            team_grade.refresh_from_db()
            return Response({
                'success': True,
                'message': 'Grades submitted successfully',
                'team_grade_id': team_grade.id,
                'panel_score': float(team_grade.panel_score) if team_grade.panel_score else None,
            }, status=status.HTTP_201_CREATED)

        except ValidationError as e:
            return Response(
                e.message_dict if hasattr(e, 'message_dict') else {'detail': e.messages},
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as e:
            return Response(
                {'error': f'Failed to submit grades: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
