from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from user_management.permissions import IsSystemAdmin

from .capstone_mode import capstone_mode_payload, normalize_capstone_flags
from .models import SchoolYear, Semester
from .serializers import (
    SchoolYearCreateSerializer,
    SchoolYearSerializer,
    SemesterCreateSerializer,
    SemesterSerializer,
)


def active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


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


class SemesterCreateView(APIView):
    permission_classes = [IsAuthenticated, IsSystemAdmin]

    def post(self, request, school_year_id):
        school_year = get_object_or_404(SchoolYear, pk=school_year_id)
        serializer = SemesterCreateSerializer(
            data=request.data,
            context={'school_year': school_year},
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

        if 'is_active' in request.data or 'active' in request.data:
            is_active = request.data.get('is_active', request.data.get('active'))
            if isinstance(is_active, str):
                is_active = is_active.lower() in ['1', 'true', 'yes', 'on']
            else:
                is_active = bool(is_active)
            semester.is_active = is_active
            update_fields.append('is_active')

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
