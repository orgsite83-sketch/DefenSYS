from django.contrib.auth import get_user_model
from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.capstone_mode import (
    derive_capstone_program_phase,
    sync_capstone_flags_after_rollover,
)
from academic_period_management.models import SchoolYear, Semester
from academic_period_management.serializers import SchoolYearSerializer, SemesterSerializer
from student_teams.models import StudentTeam, TeamMembership
from user_management.permissions import IsSystemAdmin

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
from django.contrib.auth import get_user_model
from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.capstone_mode import (
    derive_capstone_program_phase,
    sync_capstone_flags_after_rollover,
)
from academic_period_management.models import SchoolYear, Semester
from academic_period_management.serializers import SchoolYearSerializer, SemesterSerializer
from student_teams.models import StudentTeam, TeamMembership
from user_management.permissions import IsSystemAdmin

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


def _clean_spaces(value):
    return ' '.join((value or '').strip().split())


def _normalize_year_level(value):
    value = _clean_spaces(value)
    normalized = value.lower()
    if '1' in normalized:
        return StudentAcademicRecord.FIRST_YEAR
    if '2' in normalized:
        return StudentAcademicRecord.SECOND_YEAR
    if '3' in normalized:
        return StudentAcademicRecord.THIRD_YEAR
    if '4' in normalized:
        return StudentAcademicRecord.FOURTH_YEAR
    return value


class RolloverPreviewView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request):
        from academic_period_management.models import Semester as SemesterModel

        active = active_semester()
        latest = latest_records_by_student()
        rows = []

        for record in latest:
            next_year_level, next_semester = next_academic_step(record.year_level, record.semester.label)

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

    def post(self, request):
        active = active_semester()
        if active is None:
            return Response({'detail': 'No active semester is configured.'}, status=status.HTTP_400_BAD_REQUEST)

        students_data = request.data.get('students', [])
        if not isinstance(students_data, list):
            return Response({'detail': 'students must be a list.'}, status=status.HTTP_400_BAD_REQUEST)

        latest = latest_records_by_student()
        latest_by_username = {r.student.username: r for r in latest}
        
        # Build map of CSV students
        csv_students = {}
        for s in students_data:
            id_num = _clean_spaces(s.get('id_number') or s.get('student_number'))
            if id_num:
                csv_students[id_num] = s

        # Find existing users
        existing_users = {
            u.username: u 
            for u in User.objects.filter(username__in=csv_students.keys())
        }

        rows = []
        processed_usernames = set()

        for username, csv_student in csv_students.items():
            processed_usernames.add(username)
            user = existing_users.get(username)
            latest_record = latest_by_username.get(username)

            val_error = None
            if user is None:
                first_name = _clean_spaces(csv_student.get('first_name', ''))
                last_name = _clean_spaces(csv_student.get('last_name', ''))
                if not (first_name or last_name):
                    val_error = "Missing name for new student account creation."
            elif user.role != 'student':
                val_error = f"ID '{username}' is already in use by a {user.role} account."

            target_year = _normalize_year_level(csv_student.get('year_level', ''))
            target_section = _clean_spaces(csv_student.get('section', ''))

            if latest_record:
                record_data = StudentAcademicRecordSerializer(latest_record).data
            else:
                if user:
                    name = f"{user.first_name} {user.last_name}".strip() or user.username
                    first_name = user.first_name
                    last_name = user.last_name
                    email = user.email
                else:
                    first_name = _clean_spaces(csv_student.get('first_name', ''))
                    last_name = _clean_spaces(csv_student.get('last_name', ''))
                    name = f"{first_name} {last_name}".strip() or username
                    email = _clean_spaces(csv_student.get('email', ''))

                record_data = {
                    'id': None,
                    'student_id': user.id if user else None,
                    'student_username': username,
                    'student_name': name,
                    'first_name': first_name,
                    'last_name': last_name,
                    'student_email': email,
                    'year_level': '-',
                    'semester': '-',
                    'school_year': '-',
                    'section': '',
                }

            # If student has a latest record, suggest action
            if latest_record:
                if latest_record.year_level == target_year and latest_record.semester == active:
                    action_default = 'retain'
                else:
                    action_default = 'promote'
            else:
                action_default = 'create'

            rows.append({
                'record': record_data,
                'promote_result': {
                    'year_level': target_year,
                    'semester': active.label,
                    'target_semester_id': active.id,
                    'section': target_section,
                },
                'retain_result': {
                    'year_level': latest_record.year_level if latest_record else target_year,
                    'semester': latest_record.semester.label if latest_record else active.label,
                    'target_semester_id': latest_record.semester.id if latest_record else active.id,
                    'section': latest_record.section if latest_record else target_section,
                },
                'action_default': action_default,
                'is_new_student': user is None,
                'validation_error': val_error,
            })

        # Process non-enrolled students (in database previous semesters, not in CSV)
        for username, record in latest_by_username.items():
            if username in processed_usernames:
                continue
            if record.semester == active:
                continue

            rows.append({
                'record': StudentAcademicRecordSerializer(record).data,
                'promote_result': {
                    'year_level': record.year_level,
                    'semester': active.label,
                    'target_semester_id': None,  # Omit target semester ID to flag exclusion
                    'section': record.section,
                },
                'retain_result': {
                    'year_level': record.year_level,
                    'semester': record.semester.label,
                    'target_semester_id': record.semester.id,
                    'section': record.section,
                },
                'action_default': 'drop',
                'is_new_student': False,
                'validation_error': None,
                'not_in_csv': True,
            })

        return Response({
            'active_semester': SemesterSerializer(active).data,
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
        affected_student_ids = set()

        for item in serializer.validated_data:
            action = item['action']
            if action == 'drop':
                if item.get('record_id'):
                    skipped.append({'record_id': item['record_id'], 'reason': 'dropped'})
                else:
                    skipped.append({'username': item.get('username'), 'reason': 'dropped'})
                continue

            user = None
            record = None
            rolled_from = None

            if item.get('record_id'):
                record = StudentAcademicRecord.objects.select_related('student').filter(pk=item['record_id']).first()
                if record:
                    user = record.student
                    rolled_from = record

            if user is None and item.get('username'):
                username = _clean_spaces(item['username'])
                user = User.objects.filter(username=username).first()

            if action == 'create' and user is None:
                username = _clean_spaces(item['username'])
                first_name = _clean_spaces(item.get('first_name') or '')
                last_name = _clean_spaces(item.get('last_name') or '')
                email = _clean_spaces(item.get('email') or '')
                
                if not username:
                    skipped.append({'reason': 'Missing student ID for creation.'})
                    continue

                user = User.objects.create_user(
                    username=username,
                    password=username,
                    first_name=first_name,
                    last_name=last_name,
                    email=email,
                    role='student',
                )

            if user is None:
                skipped.append({'record_id': item.get('record_id'), 'reason': 'missing_user'})
                continue

            if user.role != 'student':
                skipped.append({'username': user.username, 'reason': 'not_a_student'})
                continue

            affected_student_ids.add(user.id)

            target_year = _normalize_year_level(item.get('year_level') or '')
            target_section = _clean_spaces(item.get('section') or '')

            if not target_year:
                if record:
                    calculated_year, calculated_semester_label, _ = rollover_target_semester(
                        record,
                        active.school_year,
                        action,
                    )
                    target_year = calculated_year
                else:
                    target_year = '1st Year'

            if StudentAcademicRecord.objects.filter(student=user, semester=active).exists():
                skipped.append({'username': user.username, 'reason': 'duplicate'})
                continue

            created.append(StudentAcademicRecord.objects.create(
                student=user,
                semester=active,
                year_level=target_year,
                section=target_section,
                action=action,
                rolled_from=rolled_from,
            ))

        team_updates = self._advance_capstone_teams(active)
        sync_capstone_flags_after_rollover(active, team_updates)

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
