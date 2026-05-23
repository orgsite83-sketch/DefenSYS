from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from grading.grades.services import default_weights, weights_for_schedule

from .models import DefenseSchedule
from academic_period_management.models import Semester

from .pit_config import get_pit_event_config, pit_event_config_payload
from .serializers import (
    ConfirmSchedulePlanSerializer,
    DefenseScheduleSerializer,
    DefenseScheduleStatusSerializer,
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


def counts_payload(queryset=None):
    base = schedule_queryset()
    current = queryset if queryset is not None else base
    return {
        'all': base.count(),
        'filtered': current.count(),
        'scheduled': current.filter(status=DefenseSchedule.STATUS_SCHEDULED).count(),
        'done': current.filter(status=DefenseSchedule.STATUS_DONE).count(),
        'cancelled': current.filter(status=DefenseSchedule.STATUS_CANCELLED).count(),
        'archived': current.filter(status=DefenseSchedule.STATUS_ARCHIVED).count(),
    }


def list_payload(queryset=None):
    current = queryset if queryset is not None else schedule_queryset()
    return {
        'schedules': DefenseScheduleSerializer(current, many=True).data,
        'counts': counts_payload(current),
        **schedule_options_payload(),
    }


def filter_schedules(request):
    queryset = schedule_queryset()
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
        return Response(list_payload(filter_schedules(request)))

    def post(self, request):
        serializer = DefenseScheduleWriteSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        schedule = serializer.save()
        schedule = schedule_queryset().get(pk=schedule.pk)
        return Response(
            {
                'schedule': DefenseScheduleSerializer(schedule).data,
                **list_payload(),
            },
            status=status.HTTP_201_CREATED,
        )


class PitEventConfigLookupView(APIView):
    permission_classes = [CanManageSchedules]

    def get(self, request):
        event_name = request.query_params.get('event_name', '').strip()
        if not event_name:
            return Response(
                {'detail': 'event_name query parameter is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

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

        config = get_pit_event_config(semester, event_name)
        return Response({'config': pit_event_config_payload(config)})


class DefenseScheduleGeneratePlanView(APIView):
    permission_classes = [CanManageSchedules]

    def post(self, request):
        serializer = GenerateSchedulePlanSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        slots = serializer.generate_slots()
        return Response({
            'slots': slots,
            'slot_count': len(slots),
            **schedule_options_payload(),
        })


class DefenseScheduleConfirmPlanView(APIView):
    permission_classes = [CanManageSchedules]

    def post(self, request):
        serializer = ConfirmSchedulePlanSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        schedules = serializer.save()
        schedules = schedule_queryset().filter(pk__in=[schedule.pk for schedule in schedules])
        return Response(
            {
                'schedules_created': DefenseScheduleSerializer(schedules, many=True).data,
                'created_count': schedules.count(),
                **list_payload(),
            },
            status=status.HTTP_201_CREATED,
        )


class DefenseScheduleDetailView(APIView):
    permission_classes = [CanManageSchedules]

    def get_object(self, schedule_id):
        return get_object_or_404(schedule_queryset(), pk=schedule_id)

    def patch(self, request, schedule_id):
        schedule = self.get_object(schedule_id)
        serializer = DefenseScheduleStatusSerializer(
            data=request.data,
            context={'schedule': schedule},
        )
        serializer.is_valid(raise_exception=True)
        schedule = serializer.save()
        schedule = schedule_queryset().get(pk=schedule.pk)
        return Response({
            'schedule': DefenseScheduleSerializer(schedule).data,
            **list_payload(),
        })

    def delete(self, request, schedule_id):
        schedule = self.get_object(schedule_id)
        schedule.delete()
        return Response(list_payload(), status=status.HTTP_200_OK)


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
        'criteria': [
            {
                'name': criterion.name,
                'max_score': criterion.max_score,
                'scale': criterion.scale,
                'description': criterion.description,
            }
            for criterion in rubric.criteria.all()
        ],
        'weights': grade_weights,
    }


class PanelistAssignmentsView(APIView):
    """
    API endpoint for panelists to view their assigned defense schedules.
    Returns teams and rubrics assigned to the authenticated panelist.
    """
    
    def get(self, request):
        # Get panelist ID from query params (for mobile app without auth)
        panelist_id = request.query_params.get('panelist_id', '').strip()
        
        if not panelist_id:
            return Response(
                {'error': 'panelist_id parameter is required'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            panelist_id = int(panelist_id)
        except ValueError:
            return Response(
                {'error': 'panelist_id must be a valid integer'},
                status=status.HTTP_400_BAD_REQUEST
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



class PanelistGradeSubmissionView(APIView):
    """
    API endpoint for panelists to submit their grades for a team.
    Creates or updates grade breakdown entries for the panelist's evaluation.
    """
    
    def post(self, request):
        # Get required parameters
        panelist_id = request.data.get('panelist_id')
        team_id = request.data.get('team_id')
        schedule_id = request.data.get('schedule_id')
        criteria_scores = request.data.get('criteria_scores', [])  # List of {name, score, max_score}
        remarks = request.data.get('remarks', '')
        
        # Validate required fields
        if not all([panelist_id, team_id, criteria_scores]):
            return Response(
                {'error': 'panelist_id, team_id, and criteria_scores are required'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            from django.contrib.auth import get_user_model
            from student_teams.models import StudentTeam
            from grading.grades.models import TeamGrade, GradeBreakdown
            from academic_period_management.models import Semester
            from decimal import Decimal
            
            User = get_user_model()
            
            # Get panelist
            try:
                panelist = User.objects.get(id=panelist_id)
            except User.DoesNotExist:
                return Response(
                    {'error': 'Panelist not found'},
                    status=status.HTTP_404_NOT_FOUND
                )
            
            # Get team
            try:
                team = StudentTeam.objects.get(id=team_id)
            except StudentTeam.DoesNotExist:
                return Response(
                    {'error': 'Team not found'},
                    status=status.HTTP_404_NOT_FOUND
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

            semester = team.semester or Semester.objects.filter(is_active=True).first()
            if not semester:
                return Response(
                    {'error': 'No active semester found'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            stage_label = schedule.stage_label if schedule else 'Unscheduled'
            scope = schedule.scope if schedule else ('capstone' if team.is_capstone else 'pit')
            weight_defaults = weights_for_schedule(schedule) if schedule else default_weights(scope)

            team_grade, created = TeamGrade.objects.get_or_create(
                team=team,
                semester=semester,
                scope=scope,
                stage_label=stage_label,
                defaults={
                    'schedule': schedule,
                    **weight_defaults,
                },
            )
            if team_grade.schedule_id != (schedule.id if schedule else None):
                team_grade.schedule = schedule
            for field, value in weight_defaults.items():
                setattr(team_grade, field, value)
            team_grade.save()
            
            # Delete existing breakdowns for this panelist (to allow re-submission)
            GradeBreakdown.objects.filter(
                team_grade=team_grade,
                evaluation_type='panel',
                remarks__contains=f'Panelist: {panelist.username}'
            ).delete()
            
            # Create new grade breakdowns
            for idx, criterion in enumerate(criteria_scores):
                GradeBreakdown.objects.create(
                    team_grade=team_grade,
                    rubric=schedule.rubric if schedule else None,
                    evaluation_type='panel',
                    criterion_name=criterion.get('name', 'Criterion'),
                    score=Decimal(str(criterion.get('score', 0))),
                    max_score=Decimal(str(criterion.get('max_score', 10))),
                    remarks=f'Panelist: {panelist.username}\n{remarks}',
                    display_order=idx,
                )
            
            # Calculate panel score (average of all criteria percentages)
            total_score = sum(Decimal(str(c.get('score', 0))) for c in criteria_scores)
            total_max = sum(Decimal(str(c.get('max_score', 10))) for c in criteria_scores)
            
            if total_max > 0:
                panel_percentage = (total_score / total_max * Decimal('100')).quantize(Decimal('0.01'))
                
                # Update team_grade panel_score (this will be averaged with other panelists later)
                # For now, just store this panelist's score
                # TODO: Implement proper averaging of multiple panelist scores
                team_grade.panel_score = panel_percentage
                team_grade.save()
            
            return Response({
                'success': True,
                'message': 'Grades submitted successfully',
                'team_grade_id': team_grade.id,
                'panel_score': float(team_grade.panel_score) if team_grade.panel_score else None,
            }, status=status.HTTP_201_CREATED)
            
        except Exception as e:
            return Response(
                {'error': f'Failed to submit grades: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
