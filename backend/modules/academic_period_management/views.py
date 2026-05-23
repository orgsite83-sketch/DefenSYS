from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

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


def active_semester_payload():
    semester = active_semester()
    return SemesterSerializer(semester).data if semester else None


class AcademicPeriodListCreateView(APIView):
    permission_classes = [IsAuthenticated]

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
    permission_classes = [IsAuthenticated]

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
    permission_classes = [IsAuthenticated]

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

        capstone_fields = normalize_capstone_flags(semester)
        update_fields.extend(capstone_fields)

        if update_fields:
            semester.save(update_fields=list(dict.fromkeys(update_fields)))

        payload = SemesterSerializer(semester).data
        payload.update(capstone_mode_payload(semester if semester.is_active else active_semester()))

        return Response({
            'semester': payload,
            'active_semester': active_semester_payload(),
        })
