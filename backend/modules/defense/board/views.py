from django.db.models import Q, Case, When, F, CharField
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.serializers import SemesterSerializer
from defense.scheduler.models import DefenseSchedule
from defense.scheduler.serializers import (
    DefenseScheduleSerializer,
    DefenseScheduleStatusSerializer,
    active_semester,
    schedule_queryset,
)
from user_management.permissions import CanManageModule


def board_queryset_for_user(user):
    queryset = schedule_queryset()
    if getattr(user, 'is_pit_lead', False) and getattr(user, 'role', None) != 'admin':
        from student_teams.team_levels import normalize_year_level
        pit_year = normalize_year_level(getattr(user, 'pit_lead_year', None))
        if not pit_year:
            return queryset.none()
        queryset = queryset.filter(
            scope=DefenseSchedule.SCOPE_PIT,
            team__level__icontains='PIT',
            team__year_level=pit_year,
        )
    return queryset


def counts_payload(base_queryset, current_queryset=None):
    current = current_queryset if current_queryset is not None else base_queryset
    return {
        'all': base_queryset.count(),
        'filtered': current.count(),
        'scheduled': current.filter(status=DefenseSchedule.STATUS_SCHEDULED).count(),
        'done': current.filter(status=DefenseSchedule.STATUS_DONE).count(),
        'cancelled': current.filter(status=DefenseSchedule.STATUS_CANCELLED).count(),
        'archived': current.filter(status=DefenseSchedule.STATUS_ARCHIVED).count(),
    }


def stage_options(queryset):
    return sorted(
        queryset.annotate(
            computed_stage_label=Case(
                When(scope=DefenseSchedule.SCOPE_PIT, then=F('event_name')),
                default=F('defense_stage__label'),
                output_field=CharField()
            )
        )
        .exclude(computed_stage_label__in=[None, ''])
        .values_list('computed_stage_label', flat=True)
        .distinct()
    )



def filter_board_queryset(request, queryset):
    search = request.query_params.get('search', '').strip()
    stage = request.query_params.get('stage', '').strip()
    status_filter = request.query_params.get('status', '').strip()
    scope = request.query_params.get('scope', '').strip()

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
    if stage:
        queryset = queryset.filter(Q(defense_stage__label=stage) | Q(event_name=stage))
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    if scope:
        queryset = queryset.filter(scope=scope)
    return queryset


def board_payload(request, queryset=None):
    base = board_queryset_for_user(request.user)
    current = queryset if queryset is not None else base
    semester = active_semester()
    return {
        'schedules': DefenseScheduleSerializer(current, many=True).data,
        'counts': counts_payload(base, current),
        'stage_options': stage_options(base),
        'statuses': [choice[0] for choice in DefenseSchedule.STATUS_CHOICES],
        'scopes': [
            {'value': key, 'label': label}
            for key, label in DefenseSchedule.SCOPE_CHOICES
        ],
        'active_semester': SemesterSerializer(semester).data if semester else None,
    }


class DefenseBoardListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = filter_board_queryset(request, board_queryset_for_user(request.user))
        return Response(board_payload(request, queryset))


class DefenseBoardDetailView(APIView):
    permission_classes = [CanManageModule]

    def get_object(self, request, schedule_id):
        return get_object_or_404(board_queryset_for_user(request.user), pk=schedule_id)

    def patch(self, request, schedule_id):
        schedule = self.get_object(request, schedule_id)
        serializer = DefenseScheduleStatusSerializer(
            data=request.data,
            context={'schedule': schedule, 'request': request},
        )
        serializer.is_valid(raise_exception=True)
        schedule = serializer.save()
        schedule = board_queryset_for_user(request.user).get(pk=schedule.pk)
        return Response({
            'schedule': DefenseScheduleSerializer(schedule).data,
            **board_payload(request),
        })

    def delete(self, request, schedule_id):
        schedule = self.get_object(request, schedule_id)
        from defense.scheduler.services import delete_schedule
        delete_schedule(schedule, actor=request.user, request=request)
        return Response(board_payload(request), status=status.HTTP_200_OK)
