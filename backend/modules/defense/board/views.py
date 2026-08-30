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
from authentication_access_control.scopes import visible_schedules_for
from user_management.permissions import CanManageModule


def board_queryset_for_user(user):
    return visible_schedules_for(user)


def counts_payload(base_queryset, current_queryset=None):
    current = current_queryset if current_queryset is not None else base_queryset
    from django.utils import timezone
    now = timezone.localtime()

    scheduled_qs = current.filter(status=DefenseSchedule.STATUS_SCHEDULED)
    ongoing_qs = scheduled_qs.filter(
        Q(scheduled_date__lt=now.date())
        | Q(scheduled_date=now.date(), start_time__lte=now.time())
    )
    upcoming_qs = scheduled_qs.exclude(pk__in=ongoing_qs)

    return {
        'all': base_queryset.count(),
        'filtered': current.count(),
        'scheduled': upcoming_qs.count(),
        'ongoing': ongoing_qs.count(),
        'done': current.filter(status=DefenseSchedule.STATUS_DONE).count(),
        'cancelled': current.filter(status=DefenseSchedule.STATUS_CANCELLED).count(),
        'archived': current.filter(status=DefenseSchedule.STATUS_ARCHIVED).count(),
    }


def stage_options(queryset):
    return sorted(
        set(
            queryset.order_by()
            .annotate(
                computed_stage_label=Case(
                    When(scope=DefenseSchedule.SCOPE_PIT, then=F('event_name')),
                    default=F('defense_stage__label'),
                    output_field=CharField(),
                )
            )
            .exclude(computed_stage_label__in=[None, ''])
            .values_list('computed_stage_label', flat=True)
            .distinct()
        )
    )



def adviser_options(queryset):
    from django.db.models import Count
    adviser_data = (
        queryset.filter(team__adviser__isnull=False)
        .values(
            'team__adviser__id',
            'team__adviser__first_name',
            'team__adviser__last_name',
            'team__adviser__username',
        )
        .annotate(total_schedules=Count('id'))
        .order_by('team__adviser__first_name', 'team__adviser__last_name')
    )
    result = []
    for item in adviser_data:
        first = item['team__adviser__first_name'] or ''
        last = item['team__adviser__last_name'] or ''
        name = f"{first} {last}".strip() or item['team__adviser__username']
        result.append({
            'id': item['team__adviser__id'],
            'name': name,
            'count': item['total_schedules'],
        })
    return result


def section_options(queryset):
    from django.db.models import Count
    section_data = (
        queryset.filter(team__section__isnull=False)
        .exclude(team__section='')
        .values('team__section')
        .annotate(total_schedules=Count('id'))
        .order_by('team__section')
    )
    return [
        {
            'name': item['team__section'],
            'count': item['total_schedules'],
        }
        for item in section_data
    ]


def filter_board_queryset(request, queryset):
    search = request.query_params.get('search', '').strip()
    stage = request.query_params.get('stage', '').strip()
    status_filter = request.query_params.get('status', '').strip()
    scope = request.query_params.get('scope', '').strip()
    adviser = request.query_params.get('adviser', '').strip()
    section = request.query_params.get('section', '').strip()

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
            | Q(team__adviser__first_name__icontains=search)
            | Q(team__adviser__last_name__icontains=search)
            | Q(team__section__icontains=search)
        ).distinct()
    if stage:
        queryset = queryset.filter(Q(defense_stage__label=stage) | Q(event_name=stage))
    if adviser:
        if adviser.isdigit():
            queryset = queryset.filter(team__adviser_id=int(adviser))
        else:
            queryset = queryset.filter(
                Q(team__adviser__first_name__icontains=adviser)
                | Q(team__adviser__last_name__icontains=adviser)
                | Q(team__adviser__username__icontains=adviser)
            )
    if section:
        queryset = queryset.filter(team__section__iexact=section)
    if status_filter == 'ongoing':
        from django.utils import timezone
        now = timezone.localtime()
        queryset = queryset.filter(status=DefenseSchedule.STATUS_SCHEDULED).filter(
            Q(scheduled_date__lt=now.date())
            | Q(scheduled_date=now.date(), start_time__lte=now.time())
        )
    elif status_filter == 'scheduled':
        from django.utils import timezone
        now = timezone.localtime()
        queryset = queryset.filter(status=DefenseSchedule.STATUS_SCHEDULED).exclude(
            Q(scheduled_date__lt=now.date())
            | Q(scheduled_date=now.date(), start_time__lte=now.time())
        )
    elif status_filter:
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
        'advisers': adviser_options(base),
        'sections': section_options(base),
        'statuses': [
            DefenseSchedule.STATUS_SCHEDULED,
            'ongoing',
            DefenseSchedule.STATUS_DONE,
            DefenseSchedule.STATUS_CANCELLED,
            DefenseSchedule.STATUS_ARCHIVED,
        ],
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
