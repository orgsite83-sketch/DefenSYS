from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError
from django.db.models import F
from django.shortcuts import get_object_or_404
from rest_framework import serializers
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from authentication_access_control.scopes import manageable_schedules_for
from grading.grades.outcome_models import DefenseOutcome
from user_management.permissions import CanManageModule
from . import services


def require_management(request, view, source):
    if not CanManageModule().has_permission(request, view) or not manageable_schedules_for(request.user).filter(pk=source.schedule_id).exists():
        from rest_framework.exceptions import PermissionDenied
        raise PermissionDenied('Only an authorized administrator can schedule this re-demo.')


def failure(exc):
    if isinstance(exc, PermissionError):
        return Response({'detail': str(exc)}, status=403)
    return Response({'detail': ' '.join(exc.messages)}, status=400)


class ReDemoListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        query = services.visible(request.user)
        if request.query_params.get('start') or request.query_params.get('end'):
            start = serializers.DateField().run_validation(request.query_params.get('start'))
            end = serializers.DateField().run_validation(request.query_params.get('end'))
            if end < start or (end - start).days > 41:
                raise serializers.ValidationError('Choose a calendar range of 1 to 42 days.')
            query = query.filter(scheduled_date__range=(start, end))
        for name, field in [('source_schedule_id', 'source__schedule_id'), ('semester_id', 'source__schedule__semester_id')]:
            if request.query_params.get(name):
                query = query.filter(**{field: serializers.IntegerField(min_value=1).run_validation(request.query_params[name])})
        if request.query_params.get('status') in ('scheduled', 'done', 'cancelled'):
            query = query.filter(status=request.query_params['status'])
        offset = serializers.IntegerField(min_value=0).run_validation(request.query_params.get('offset', 0))
        limit = serializers.IntegerField(min_value=1, max_value=200).run_validation(request.query_params.get('limit', 50))
        eligible = []
        panelist_options = []
        if CanManageModule().has_permission(request, self):
            from django.contrib.auth import get_user_model
            panelist_options = [{'id': person.pk, 'name': person.get_full_name() or person.username}
                for person in get_user_model().objects.filter(is_active=True, is_panelist=True,
                    role__in=['faculty', 'admin']).order_by('first_name', 'pk')]
            sources = DefenseOutcome.objects.filter(schedule_id__in=manageable_schedules_for(request.user).values('pk'),
                verdict='approved_with_revisions', grade__schedule_id=F('schedule_id')).exclude(demo_requirements=[])
            if request.query_params.get('source_schedule_id'):
                sources = sources.filter(schedule_id=request.query_params['source_schedule_id'])
            if request.query_params.get('semester_id'):
                sources = sources.filter(schedule__semester_id=request.query_params['semester_id'])
            sources = sources.select_related('schedule__team', 'grade').prefetch_related('re_demos', 'schedule__panel_assignments')
            for source in sources.order_by('-pk'):
                try:
                    services._current(source)
                except DjangoValidationError:
                    continue
                if services.outstanding(source) and not source.re_demos.filter(status='scheduled').exists():
                    eligible.append({'outcome_id': source.pk, 'source_revision': source.revision,
                        'source_schedule_id': source.schedule_id, 'team_name': source.schedule.team.name,
                        'stage_label': source.schedule.stage_label, 'chair_id': source.confirmed_by_id,
                        'room': source.schedule.room, 'adviser_id': source.schedule.team.adviser_id,
                        'panelist_ids': list(source.schedule.panel_assignments.values_list('panelist_id', flat=True)),
                        'requirements': services.outstanding(source)})
        eligible_offset = serializers.IntegerField(min_value=0).run_validation(request.query_params.get('eligible_offset', 0))
        eligible_total = len(eligible)
        return Response({'appointments': [services.serialize(row, request.user) for row in query[offset:offset + limit]],
                         'total': query.count(), 'offset': offset, 'limit': limit,
                         'eligible': eligible[eligible_offset:eligible_offset + limit], 'eligible_total': eligible_total,
                         'can_manage': CanManageModule().has_permission(request, self), 'panelist_options': panelist_options})

    def post(self, request):
        source_id = serializers.IntegerField(min_value=1).run_validation(request.data.get('outcome_id'))
        source = get_object_or_404(DefenseOutcome.objects.select_related('schedule__team', 'grade'), pk=source_id)
        require_management(request, self, source)
        try:
            appointment = services.book(source, actor=request.user, data=request.data)
        except (DjangoValidationError, PermissionError) as exc:
            return failure(exc)
        return Response({'appointment': services.serialize(appointment, request.user)}, status=201)


class ReDemoDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, appointment_id):
        appointment = get_object_or_404(services.visible(request.user), pk=appointment_id)
        return Response({'appointment': services.serialize(appointment, request.user)})


class ReDemoVerifyView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, appointment_id):
        appointment = get_object_or_404(services.visible(request.user), pk=appointment_id)
        try:
            result = services.verify(appointment, actor=request.user, data=request.data)
        except (DjangoValidationError, PermissionError) as exc:
            return failure(exc)
        except IntegrityError:
            return Response({'detail': 'This verification request was used concurrently. Refresh the appointment.'}, status=409)
        return Response({'appointment': services.serialize(result, request.user)})


class ReDemoOperationView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, appointment_id):
        appointment = get_object_or_404(services.visible(request.user), pk=appointment_id)
        require_management(request, self, appointment.source)
        try:
            result = services.operate(appointment, actor=request.user, data=request.data)
        except (DjangoValidationError, PermissionError) as exc:
            return failure(exc)
        return Response({'appointment': services.serialize(result, request.user)})
