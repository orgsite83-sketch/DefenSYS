from django.db import transaction
from django.db.models import ProtectedError
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from defensys_backend.read_projection import ReadAPIView as APIView

from user_management.permissions import IsSystemAdmin

from .capstone_mode import capstone_mode_payload, normalize_capstone_flags
from .models import SchoolYear, Semester
from .serializers import (
    SchoolYearCreateSerializer,
    SchoolYearSerializer,
    SchoolYearUpdateSerializer,
    SemesterCreateSerializer,
    SemesterSerializer,
    SemesterActivationSerializer,
    SemesterCalendarSerializer,
)
from .services import build_semester_transition_preview, switch_active_semester, active_semester


def semester_payload(semester, *, include_capstone_mode=False):
    if semester is None:
        return None
    payload = SemesterSerializer(semester).data
    if include_capstone_mode:
        mode_semester = semester if semester.is_active else active_semester()
        if mode_semester is not None:
            payload.update(capstone_mode_payload(mode_semester))
    return payload


def active_semester_payload():
    return semester_payload(active_semester(), include_capstone_mode=True)


class AcademicPeriodListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [IsAuthenticated(), IsSystemAdmin()]

    def get(self, request):
        school_years = SchoolYear.objects.prefetch_related('semesters').all()
        return Response({
            'school_years': SchoolYearSerializer(school_years, many=True).data,
            'active_semester': active_semester_payload(),
        })

    def post(self, request):
        serializer = SchoolYearCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        school_year = serializer.save()

        return Response({
            'school_year': SchoolYearSerializer(school_year).data,
            'active_semester': active_semester_payload(),
        }, status=status.HTTP_201_CREATED)


class SchoolYearDetailView(APIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    @transaction.atomic
    def patch(self, request, school_year_id):
        school_year = get_object_or_404(SchoolYear.objects.select_for_update(), pk=school_year_id)
        old_label = school_year.label
        serializer = SchoolYearUpdateSerializer(
            instance=school_year,
            data=request.data,
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        school_year = serializer.save()
        if school_year.label != old_label:
            from authentication_access_control.audit import log_high_impact_action
            from authentication_access_control.models import SystemAuditLog
            log_high_impact_action(
                category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD,
                action='school_year.renamed', target=school_year, request=request,
                old_values={'label': old_label}, new_values={'label': school_year.label},
                reason='Corrected an unused school year before adding semesters.', strict=True,
            )

        school_years = SchoolYear.objects.prefetch_related('semesters').all()
        return Response({
            'school_year': SchoolYearSerializer(school_year).data,
            'school_years': SchoolYearSerializer(school_years, many=True).data,
            'active_semester': active_semester_payload(),
            'message': f'School year renamed to {school_year.label}.',
        })

    def delete(self, request, school_year_id):
        school_year = get_object_or_404(SchoolYear.objects.prefetch_related('semesters'), pk=school_year_id)
        if school_year.semesters.exists():
            raise ValidationError({
                'detail': 'Cannot delete school year with existing semesters. Please delete all semesters first.'
            })
        label = school_year.label
        try:
            school_year.delete()
        except ProtectedError:
            raise ValidationError({
                'detail': f'Cannot delete school year {label} because it is referenced by other records.'
            })

        school_years = SchoolYear.objects.prefetch_related('semesters').all()
        return Response({
            'detail': f'School year {label} deleted.',
            'school_years': SchoolYearSerializer(school_years, many=True).data,
            'active_semester': active_semester_payload(),
        }, status=status.HTTP_200_OK)


class SemesterCreateView(APIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    def post(self, request, school_year_id):
        school_year = get_object_or_404(SchoolYear, pk=school_year_id)
        serializer = SemesterCreateSerializer(
            data=request.data,
            context={'school_year': school_year, 'request': request},
        )
        serializer.is_valid(raise_exception=True)
        semester = serializer.save()

        return Response({
            'semester': SemesterSerializer(semester).data,
            'active_semester': active_semester_payload(),
        }, status=status.HTTP_201_CREATED)


class SemesterStatusView(APIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    def patch(self, request, semester_id):
        semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        update_fields = []
        if 'starts_on' in request.data or 'ends_on' in request.data:
            if 'is_active' in request.data or 'active' in request.data:
                raise ValidationError('Save calendar dates before starting a semester activation review.')
            from django.db import transaction
            from .calendar import calendar_schedule_issues
            with transaction.atomic():
                semester = Semester.objects.select_for_update().get(pk=semester_id)
                old_calendar = {'starts_on': str(semester.starts_on) if semester.starts_on else None,
                                'ends_on': str(semester.ends_on) if semester.ends_on else None}
                calendar = SemesterCalendarSerializer(data=request.data, partial=True, context={'semester': semester})
                calendar.is_valid(raise_exception=True)
                for name, value in calendar.validated_data.items():
                    setattr(semester, name, value)
                semester.save(update_fields=list(calendar.validated_data))
                issues = calendar_schedule_issues(semester)
                from authentication_access_control.audit import log_high_impact_action
                from authentication_access_control.models import SystemAuditLog
                log_high_impact_action(category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD,
                    action='semester.calendar_updated', target=semester, actor=request.user, request=request,
                    old_values=old_calendar,
                    new_values={'starts_on': semester.starts_on.isoformat(), 'ends_on': semester.ends_on.isoformat(),
                                'out_of_range_schedule_ids': issues['schedule_ids']}, strict=True)
            return Response({'semester': SemesterSerializer(semester).data,
                             'active_semester': active_semester_payload(), 'calendar_issues': issues})

        if 'is_active' in request.data or 'active' in request.data:
            is_active = request.data.get('is_active', request.data.get('active'))
            if isinstance(is_active, str):
                is_active = is_active.lower() in ['1', 'true', 'yes', 'on']
            else:
                is_active = bool(is_active)
            if not is_active:
                raise ValidationError({
                    'is_active': 'Choose another semester to activate instead of deactivating the active semester directly.',
                })
            activation = SemesterActivationSerializer(data=request.data)
            activation.is_valid(raise_exception=True)
            switch_active_semester(semester, request.user, **activation.validated_data)
            semester.refresh_from_db()
            return Response({
                'semester': semester_payload(
                    semester,
                    include_capstone_mode=True,
                ),
                'active_semester': active_semester_payload(),
            })

        if 'capstone_peer_evaluation_enabled' in request.data:
            value = request.data['capstone_peer_evaluation_enabled']
            if isinstance(value, str):
                value = value.lower() in ['1', 'true', 'yes', 'on']
            semester.capstone_peer_evaluation_enabled = bool(value)
            update_fields.append('capstone_peer_evaluation_enabled')

        if 'capstone_adviser_grading_enabled' in request.data:
            value = request.data['capstone_adviser_grading_enabled']
            if isinstance(value, str):
                value = value.lower() in ['1', 'true', 'yes', 'on']
            semester.capstone_adviser_grading_enabled = bool(value)
            update_fields.append('capstone_adviser_grading_enabled')

        if 'capstone_team_creation_enabled' in request.data:
            value = request.data['capstone_team_creation_enabled']
            if isinstance(value, str):
                value = value.lower() in ['1', 'true', 'yes', 'on']
            semester.capstone_team_creation_enabled = bool(value)
            update_fields.append('capstone_team_creation_enabled')

        capstone_fields = normalize_capstone_flags(semester)
        update_fields.extend(capstone_fields)

        if update_fields:
            semester.save(update_fields=list(dict.fromkeys(update_fields)))
            if 'capstone_peer_evaluation_enabled' in update_fields or 'capstone_adviser_grading_enabled' in update_fields:
                from realtime.broadcast import notify_capstone_evaluation_flags

                notify_capstone_evaluation_flags(
                    semester,
                    peer_eval_enabled=semester.capstone_peer_evaluation_enabled
                    if 'capstone_peer_evaluation_enabled' in update_fields
                    else None,
                    adviser_grading_enabled=semester.capstone_adviser_grading_enabled
                    if 'capstone_adviser_grading_enabled' in update_fields
                    else None,
                )

        return Response({
            'semester': semester_payload(
                semester,
                include_capstone_mode=True,
            ),
            'active_semester': active_semester_payload(),
        })

    def delete(self, request, semester_id):
        semester = get_object_or_404(
            Semester.objects.select_related('school_year'),
            pk=semester_id,
        )
        if semester.is_active:
            raise ValidationError({
                'detail': 'Cannot delete the currently active semester. Activate another semester first.'
            })

        if hasattr(semester, 'student_records') and semester.student_records.exists():
            raise ValidationError({
                'detail': 'Cannot delete semester: Enrolled student records exist for this term.'
            })

        display_name = semester.display_name
        try:
            semester.delete()
        except ProtectedError:
            raise ValidationError({
                'detail': 'Cannot delete semester: It contains dependent records (teams, grades, schedules, or rubrics).'
            })

        school_years = SchoolYear.objects.prefetch_related('semesters').all()
        return Response({
            'detail': f'Semester {display_name} deleted.',
            'school_years': SchoolYearSerializer(school_years, many=True).data,
            'active_semester': active_semester_payload(),
        }, status=status.HTTP_200_OK)


class SemesterCreatePreviewView(APIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    def post(self, request, school_year_id):
        from .services import proposed_semester
        school_year = get_object_or_404(SchoolYear, pk=school_year_id)
        serializer = SemesterCreateSerializer(data=request.data,
            context={'school_year': school_year, 'request': request})
        serializer.is_valid(raise_exception=True)
        if Semester.objects.filter(school_year=school_year, label=serializer.validated_data['label']).exists():
            raise ValidationError({'label': 'This semester already exists for the selected school year.'})
        return Response(build_semester_transition_preview(proposed_semester(school_year, **serializer.validated_data)))


class SemesterTransitionPreviewView(APIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    def get(self, request, semester_id):
        semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        return Response(build_semester_transition_preview(semester))


class SemesterActivateView(APIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    def post(self, request, semester_id):
        semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        activation = SemesterActivationSerializer(data=request.data)
        activation.is_valid(raise_exception=True)
        preview, log = switch_active_semester(
            semester,
            request.user,
            **activation.validated_data,
        )
        semester.refresh_from_db()
        return Response({
            'semester': semester_payload(
                semester,
                include_capstone_mode=True,
            ),
            'active_semester': active_semester_payload(),
            'transition_preview': preview,
            'transition_log_id': log.id if log else None,
        })


