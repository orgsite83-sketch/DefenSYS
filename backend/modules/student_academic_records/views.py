from django.contrib.auth import get_user_model
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.models import SchoolYear
from academic_period_management.serializers import SchoolYearSerializer, SemesterSerializer
from user_management.permissions import IsSystemAdmin
from student_teams.models import StudentTeam
from .models import StudentAcademicRecord
from .rollover import active_semester, latest_records_by_student, next_academic_step, rollover_target_semester
from .serializers import (
    RolloverActionSerializer,
    StudentAcademicRecordSerializer,
    StudentAcademicRecordWriteSerializer,
    StudentOptionSerializer,
)


User = get_user_model()


def records_queryset():
    return StudentAcademicRecord.objects.select_related('student', 'semester', 'semester__school_year')


def options_payload():
    school_years = SchoolYear.objects.prefetch_related('semesters').all()
    active = active_semester()
    students = User.objects.filter(role='student', is_active=True).order_by('username')

    return {
        'school_years': SchoolYearSerializer(school_years, many=True).data,
        'active_semester': SemesterSerializer(active).data if active else None,
        'students': StudentOptionSerializer(students, many=True).data,
    }


def counts_payload(queryset=None):
    all_records = records_queryset()
    return {
        'all': all_records.count(),
        'filtered': queryset.count() if queryset is not None else all_records.count(),
        'students_with_records': all_records.values('student_id').distinct().count(),
    }


class StudentAcademicRecordListCreateView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request):
        queryset = records_queryset()
        search = request.query_params.get('search', '').strip()
        school_year = request.query_params.get('school_year', '').strip()
        semester = request.query_params.get('semester', '').strip()

        if search:
            queryset = queryset.filter(
                Q(student__username__icontains=search)
                | Q(student__first_name__icontains=search)
                | Q(student__last_name__icontains=search)
                | Q(student__email__icontains=search)
            )
        if school_year:
            queryset = queryset.filter(semester__school_year__label=school_year)
        if semester:
            queryset = queryset.filter(semester__label=semester)

        return Response({
            'records': StudentAcademicRecordSerializer(queryset, many=True).data,
            'counts': counts_payload(queryset),
            **options_payload(),
        })

    def post(self, request):
        serializer = StudentAcademicRecordWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        record = serializer.save()

        return Response(
            {
                'record': StudentAcademicRecordSerializer(record).data,
                'counts': counts_payload(),
            },
            status=status.HTTP_201_CREATED,
        )


class StudentAcademicRecordDetailView(APIView):
    permission_classes = [IsSystemAdmin]

    def get_object(self, record_id):
        return get_object_or_404(records_queryset(), pk=record_id)

    def patch(self, request, record_id):
        record = self.get_object(record_id)
        serializer = StudentAcademicRecordWriteSerializer(
            record,
            data=request.data,
            context={'record_id': record.id},
        )
        serializer.is_valid(raise_exception=True)
        record = serializer.save()

        return Response({
            'record': StudentAcademicRecordSerializer(record).data,
            'counts': counts_payload(),
        })

    def delete(self, request, record_id):
        record = self.get_object(record_id)
        record.delete()
        return Response({'counts': counts_payload()}, status=status.HTTP_200_OK)


class RolloverPreviewView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request):
        from academic_period_management.models import Semester as SemesterModel
        active = active_semester()
        latest = latest_records_by_student()
        rows = []

        for record in latest:
            next_year_level, next_semester = next_academic_step(record.year_level, record.semester.label)

            # Within-year (1st → 2nd): target stays in the record's own school year.
            # Cross-year (2nd → 1st): target is the active school year.
            if record.semester.label == SemesterModel.FIRST:
                lookup_year = record.semester.school_year
            else:
                lookup_year = active.school_year if active else None

            target_semester = (
                lookup_year.semesters.filter(label=next_semester).first()
                if lookup_year else None
            )
            rows.append({
                'record': StudentAcademicRecordSerializer(record).data,
                'promote_result': {
                    'year_level': next_year_level,
                    'semester': next_semester,
                    'target_semester_id': target_semester.id if target_semester else None,
                },
                'retain_result': {
                    'year_level': record.year_level,
                    'semester': record.semester.label,
                },
            })

        return Response({
            'active_semester': SemesterSerializer(active).data if active else None,
            'rows': rows,
        })


class RolloverConfirmView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request):
        active = active_semester()
        if active is None:
            return Response({'detail': 'No active semester is configured.'}, status=status.HTTP_400_BAD_REQUEST)

        serializer = RolloverActionSerializer(data=request.data.get('actions', []), many=True)
        serializer.is_valid(raise_exception=True)

        created = []
        skipped = []
        promoted_student_ids = set()

        for item in serializer.validated_data:
            record = records_queryset().filter(pk=item['record_id']).first()
            if record is None:
                skipped.append({'record_id': item['record_id'], 'reason': 'missing'})
                continue

            action = item['action']
            if action == 'drop':
                skipped.append({'record_id': record.id, 'reason': 'dropped'})
                continue
            if action == 'promote':
                promoted_student_ids.add(record.student_id)

            year_level, semester_label, target_semester = rollover_target_semester(
                record,
                active.school_year,
                action,
            )
            if target_semester is None:
                skipped.append({
                    'record_id': record.id,
                    'reason': f'{semester_label} does not exist in {active.school_year.label}',
                })
                continue

            if StudentAcademicRecord.objects.filter(student=record.student, semester=target_semester).exists():
                skipped.append({'record_id': record.id, 'reason': 'duplicate'})
                continue

            created.append(StudentAcademicRecord.objects.create(
                student=record.student,
                semester=target_semester,
                year_level=year_level,
                action=action,
                rolled_from=record,
            ))

        team_updates = self._advance_capstone_teams(active)

        return Response({
            'created': StudentAcademicRecordSerializer(created, many=True).data,
            'created_count': len(created),
            'skipped': skipped,
            'skipped_count': len(skipped),
            'team_updates': team_updates,
            'schedules_archived': 0,
            'counts': counts_payload(),
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    def _advance_capstone_teams(self, active):
        first_semester = active.school_year.semesters.filter(label='1st Semester').first()
        if first_semester is None:
            return 0

        updates = 0
        capstone_teams = StudentTeam.objects.filter(level__icontains='Capstone')
        for team in capstone_teams:
            if team.year_level == '3rd Year' and team.semester.label == '2nd Semester':
                team.year_level = '4th Year'
                team.level = StudentTeam.LEVEL_4_CAPSTONE
                team.semester = first_semester
                team.capstone_phase = StudentTeam.PHASE_ACTIVE
                team.save()
                updates += 1
            elif team.year_level == '4th Year' and team.semester.label == '2nd Semester':
                team.semester = first_semester
                team.capstone_phase = StudentTeam.PHASE_EXTENDED
                team.status = StudentTeam.STATUS_DELAYED
                team.save()
                updates += 1
        return updates
