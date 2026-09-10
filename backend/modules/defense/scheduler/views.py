from django.core.exceptions import ValidationError
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from grading.grades.models import GradeBreakdown, TeamGrade, PanelistGradeSubmission
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
from user_management.permissions import IsPanelist, CanManageModule

from .models import DefenseSchedule, SchedulePanelist, PitEventGradingConfig
from academic_period_management.models import Semester

from .pit_config import check_pit_event_locked, get_pit_event_config, pit_event_config_payload, upsert_pit_event_config
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


from .services import schedule_audit_values


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
        return [CanManageModule()]

    def get(self, request):
        base = visible_schedules_for(request.user)
        can_manage = CanManageModule().has_permission(request, self)
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
    permission_classes = [CanManageModule]

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

        from authentication_access_control.scopes import is_pit_lead_only, _pit_year
        pit_lead = is_pit_lead_only(request.user)
        pit_year = _pit_year(request.user) if pit_lead else None

        event_name = request.query_params.get('event_name', '').strip()
        if not event_name:
            configs = PitEventGradingConfig.objects.filter(semester=semester).prefetch_related('deliverables').order_by('event_name')
            if pit_lead:
                if pit_year:
                    from repository.project_archive.services import PIT_YEAR_EVENT_HINTS
                    exclude_filter = Q()
                    for y, hints in PIT_YEAR_EVENT_HINTS.items():
                        if y != pit_year:
                            for hint in hints:
                                exclude_filter |= Q(event_name__icontains=hint)
                    if exclude_filter:
                        configs = configs.exclude(exclude_filter)
                else:
                    configs = configs.none()
            return Response({'configs': [pit_event_config_payload(c) for c in configs]})

        if pit_lead and pit_year:
            from repository.project_archive.services import PIT_YEAR_EVENT_HINTS
            is_forbidden = False
            for y, hints in PIT_YEAR_EVENT_HINTS.items():
                if y != pit_year:
                    if any(hint in event_name.lower() for hint in hints):
                        is_forbidden = True
                        break
            if is_forbidden:
                return Response(
                    {'detail': f'You are not authorized to view event configuration for "{event_name}" as your PIT scope is {pit_year}.'},
                    status=status.HTTP_403_FORBIDDEN,
                )

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
                'archive_file_template': '',
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

        from authentication_access_control.scopes import is_pit_lead_only, _pit_year
        pit_lead = is_pit_lead_only(request.user)
        if pit_lead:
            pit_year = _pit_year(request.user)
            if not pit_year:
                return Response(
                    {'detail': 'Your account is not assigned to a PIT year level.'},
                    status=status.HTTP_403_FORBIDDEN,
                )
            from repository.project_archive.services import PIT_YEAR_EVENT_HINTS
            is_forbidden = False
            for y, hints in PIT_YEAR_EVENT_HINTS.items():
                if y != pit_year:
                    if any(hint in config.event_name.lower() for hint in hints):
                        is_forbidden = True
                        break
            if is_forbidden:
                return Response(
                    {'detail': f'Cannot delete configuration. Event name does not correspond to your assigned PIT year level ({pit_year}).'},
                    status=status.HTTP_403_FORBIDDEN,
                )

        is_locked, lock_reason = check_pit_event_locked(config)
        if is_locked:
            return Response(
                {'detail': f'Cannot delete PIT event configuration "{config.event_name}": {lock_reason}'},
                status=status.HTTP_409_CONFLICT,
            )

        config.delete()
        return Response({'success': True}, status=status.HTTP_200_OK)

    def post(self, request):
        event_name = request.data.get('event_name', '').strip()
        if not event_name:
            return Response(
                {'detail': 'event_name is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        from authentication_access_control.scopes import is_pit_lead_only, _pit_year
        pit_lead = is_pit_lead_only(request.user)
        if pit_lead:
            pit_year = _pit_year(request.user)
            if not pit_year:
                return Response(
                    {'detail': 'Your account is not assigned to a PIT year level.'},
                    status=status.HTTP_403_FORBIDDEN,
                )
            from repository.project_archive.services import PIT_YEAR_EVENT_HINTS
            is_forbidden = False
            for y, hints in PIT_YEAR_EVENT_HINTS.items():
                if y != pit_year:
                    if any(hint in event_name.lower() for hint in hints):
                        is_forbidden = True
                        break
            if is_forbidden:
                return Response(
                    {'detail': f'Cannot save configuration. Event name must correspond to your assigned PIT year level ({pit_year}).'},
                    status=status.HTTP_403_FORBIDDEN,
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

        archive_file_template = request.data.get('archive_file_template')
        event_code = request.data.get('event_code')
        deliverables = request.data.get('deliverables')
        if deliverables is not None and not isinstance(deliverables, list):
            return Response(
                {'detail': 'deliverables must be a list.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Retrieve Rubrics (optional)
        panel_rubric = Rubric.objects.filter(pk=panel_rubric_id).first() if panel_rubric_id else None
        peer_rubric = Rubric.objects.filter(pk=peer_rubric_id).first() if peer_rubric_id else None

        if pit_lead:
            rubric_check = Q(created_by=request.user) | Q(created_by__isnull=True)
            if pit_year:
                rubric_check |= Q(created_by__pit_lead_year=pit_year)
            if panel_rubric_id and not Rubric.objects.filter(rubric_check, pk=panel_rubric_id).exists():
                return Response(
                    {'detail': 'Selected Panel Rubric is not permitted for your PIT year level.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if peer_rubric_id and not Rubric.objects.filter(rubric_check, pk=peer_rubric_id).exists():
                return Response(
                    {'detail': 'Selected Peer Rubric is not permitted for your PIT year level.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        try:
            config = upsert_pit_event_config(
                semester=semester,
                event_name=event_name,
                event_code=event_code,
                panel_rubric=panel_rubric,
                peer_rubric=peer_rubric,
                panel_weight=panel_weight,
                peer_weight=peer_weight,
                archive_file_template=archive_file_template,
                deliverables=deliverables,
            )
            return Response({'config': pit_event_config_payload(config)}, status=status.HTTP_200_OK)
        except ValidationError as e:
            return Response(
                {'detail': e.message if hasattr(e, 'message') else str(e)},
                status=status.HTTP_400_BAD_REQUEST,
            )


class DefenseScheduleGeneratePlanView(APIView):
    permission_classes = [CanManageModule]

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
    permission_classes = [CanManageModule]

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
    permission_classes = [CanManageModule]

    def get_object(self, schedule_id):
        return get_object_or_404(visible_schedules_for(self.request.user), pk=schedule_id)

    def patch(self, request, schedule_id):
        schedule = self.get_object(schedule_id)
        serializer = DefenseSchedulePatchSerializer(
            data=request.data,
            context={'schedule': schedule, 'request': request},
        )
        serializer.is_valid(raise_exception=True)
        schedule = serializer.save()
        base = visible_schedules_for(request.user)
        schedule = base.get(pk=schedule.pk)
        return Response({
            'schedule': DefenseScheduleSerializer(schedule).data,
            **list_payload(base_queryset=base, user=request.user),
        })

    def delete(self, request, schedule_id):
        schedule = self.get_object(schedule_id)
        from .services import delete_schedule
        delete_schedule(schedule, actor=request.user, request=request)
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
                'target_type': criterion.target_type,
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

        submitted_subs = (
            PanelistGradeSubmission.objects.filter(panelist_id=panelist_id)
            .select_related('schedule')
            .prefetch_related('criterion_scores')
        )
        sub_map = {}
        for sub in submitted_subs:
            sub_map.setdefault(sub.schedule_id, []).append(sub)

        locked_schedule_ids = set(
            TeamGrade.objects.filter(
                schedule_id__in=[s.id for s in schedules],
                status__in=TeamGrade.LOCKED_STATUSES,
            ).values_list('schedule_id', flat=True)
        )

        # Get set of schedule IDs where this panelist is designated as chair
        chair_schedule_ids = set(
            SchedulePanelist.objects.filter(
                schedule_id__in=[s.id for s in schedules],
                panelist_id=panelist_id,
                is_chair=True,
            ).values_list('schedule_id', flat=True)
        )

        team_grades = (
            TeamGrade.objects.filter(schedule_id__in=[s.id for s in schedules])
            .select_related('verdict_by')
        )
        grade_map = {tg.schedule_id: tg for tg in team_grades}

        teams_data = []
        rubrics_data = []
        seen_rubric_ids = set()

        for schedule in schedules:
            subs = sub_map.get(schedule.id, [])
            is_posted = bool(subs) or (schedule.id in locked_schedule_ids)

            submissions_data = []
            for sub in subs:
                submissions_data.append({
                    'student_id': sub.student_id,
                    'remarks': sub.remarks or '',
                    'criteria_scores': [
                        {
                            'criterion_id': cs.criterion_id,
                            'score': float(cs.score),
                            'max_score': float(cs.max_score_snapshot),
                        }
                        for cs in sub.criterion_scores.all()
                    ],
                })

            is_chair = schedule.id in chair_schedule_ids
            team_grade = grade_map.get(schedule.id)

            team_payload = _team_assignment_payload(
                schedule,
                is_posted=is_posted,
                submissions=submissions_data,
                is_chair=is_chair,
                team_grade=team_grade,
            )
            teams_data.append(team_payload)

            if schedule.rubric_id and schedule.rubric_id not in seen_rubric_ids:
                rubrics_data.append(team_payload.get('panel_rubric'))
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
            .select_related('team', 'team__leader', 'schedule', 'verdict_by')
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

            if not team.semester:
                return Response(
                    {'detail': 'This team has no semester assigned.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            semester = team.semester

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
                {'detail': f'Failed to submit grades: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


def _team_assignment_payload(schedule, is_posted=False, submissions=None, is_chair=False, team_grade=None):
    team = schedule.team
    raw_weights = weights_for_schedule(schedule)
    grade_weights = _grade_weights_payload(schedule, raw_weights)
    panel_rubric = _panel_rubric_payload(schedule.rubric, grade_weights)

    verdict = None
    verdict_remarks = ''
    verdict_by_name = ''
    revision_deadline = None
    attempt_count = 1
    grade_id = None
    if team_grade:
        verdict = team_grade.verdict or ''
        verdict_remarks = team_grade.verdict_remarks or ''
        if team_grade.verdict_by:
            verdict_by_name = (
                f"{team_grade.verdict_by.first_name} {team_grade.verdict_by.last_name}".strip()
                or team_grade.verdict_by.username
            )
        revision_deadline = (
            team_grade.revision_deadline.isoformat()
            if team_grade.revision_deadline
            else None
        )
        attempt_count = team_grade.attempt_count or 1
        grade_id = team_grade.id

    from repository.deliverables.services import stage_payload
    stage_info = stage_payload(team, schedule.stage_label)
    defense_materials = [
        item for item in stage_info.get('pre', [])
        if item.get('is_defense_material', True) and item.get('uploaded')
    ]

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
        'is_posted': is_posted,
        'is_submitted': is_posted,
        'submissions': submissions or [],
        'defense_materials': defense_materials,
        'is_chair': is_chair,
        'verdict': verdict,
        'verdict_remarks': verdict_remarks,
        'verdict_by_name': verdict_by_name,
        'revision_deadline': revision_deadline,
        'attempt_count': attempt_count,
        'grade_id': grade_id,
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

        subs = list(
            PanelistGradeSubmission.objects.filter(
                schedule=schedule,
                guest_code_id=principal.guest_code_id,
            ).prefetch_related('criterion_scores')
        )
        is_posted = bool(subs) or TeamGrade.objects.filter(
            schedule=schedule,
            status__in=TeamGrade.LOCKED_STATUSES,
        ).exists()

        submissions_data = []
        for sub in subs:
            submissions_data.append({
                'student_id': sub.student_id,
                'remarks': sub.remarks or '',
                'criteria_scores': [
                    {
                        'criterion_id': cs.criterion_id,
                        'score': float(cs.score),
                        'max_score': float(cs.max_score_snapshot),
                    }
                    for cs in sub.criterion_scores.all()
                ],
            })

        team_payload = _team_assignment_payload(
            schedule,
            is_posted=is_posted,
            submissions=submissions_data,
        )
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

            if not team.semester:
                return Response(
                    {'detail': 'This team has no semester assigned.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            semester = team.semester

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
                {'detail': f'Failed to submit grades: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class DefenseScheduleVerdictView(APIView):
    """
    API endpoint for the panel chair or an administrator to issue the official defense verdict.
    """
    permission_classes = [IsAuthenticated]

    def patch(self, request, schedule_id):
        schedule = get_object_or_404(DefenseSchedule, id=schedule_id)

        is_admin = (
            request.user.is_staff
            or request.user.is_superuser
            or getattr(request.user, 'role', None) == 'admin'
        )
        is_chair = schedule.panel_assignments.filter(
            panelist=request.user,
            is_chair=True,
        ).exists()

        if not (is_admin or is_chair):
            return Response(
                {'detail': 'Only the panel chair or an administrator can issue defense verdicts.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        verdict = request.data.get('verdict')
        valid_verdicts = [v[0] for v in TeamGrade.VERDICT_CHOICES]
        if not verdict or verdict not in valid_verdicts:
            return Response(
                {
                    'detail': f'Invalid verdict "{verdict}". Must be one of: {", ".join(valid_verdicts)}.',
                    'valid_verdicts': valid_verdicts,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        from grading.grades.services import GradeContextService, _apply_team_result_from_grade
        from grading.grades.serializers import TeamGradeSerializer

        team_grade = schedule.grade_records.first()
        if not team_grade:
            team_grade, _created, _changed = GradeContextService.get_or_create_for_schedule(schedule)

        if team_grade.panel_score is None:
            return Response(
                {'detail': 'Panel grading must be submitted before issuing a verdict.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        verdict_remarks = (request.data.get('verdict_remarks') or '').strip()
        revision_deadline = request.data.get('revision_deadline')
        parsed_deadline = None
        if revision_deadline:
            from django.utils.dateparse import parse_date
            parsed_deadline = parse_date(str(revision_deadline).strip())
            if not parsed_deadline:
                return Response(
                    {'detail': 'Invalid revision_deadline format (YYYY-MM-DD expected).'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        team_grade.verdict = verdict
        team_grade.verdict_remarks = verdict_remarks
        team_grade.verdict_by = request.user
        team_grade.verdict_at = timezone.now()
        team_grade.revision_deadline = parsed_deadline
        team_grade.save(update_fields=[
            'verdict',
            'verdict_remarks',
            'verdict_by',
            'verdict_at',
            'revision_deadline',
            'updated_at',
        ])

        _apply_team_result_from_grade(team_grade)

        from authentication_access_control.models import SystemAuditLog
        from authentication_access_control.audit import log_high_impact_action
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='defense.verdict_submitted',
            target=team_grade,
            target_type='TeamGrade',
            target_id=team_grade.pk,
            actor=request.user,
            new_values={
                'schedule_id': schedule.id,
                'team_id': schedule.team_id,
                'team_name': getattr(schedule.team, 'name', '') or getattr(team_grade.team, 'name', ''),
                'stage_label': getattr(team_grade, 'stage_label', ''),
                'verdict': verdict,
                'verdict_remarks': verdict_remarks,
                'revision_deadline': str(parsed_deadline) if parsed_deadline else None,
            },
        )

        return Response({
            'success': True,
            'message': f'Defense verdict "{verdict}" recorded successfully.',
            'team_grade': TeamGradeSerializer(team_grade).data,
        }, status=status.HTTP_200_OK)

