from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as ModelValidationError
from django.db import IntegrityError
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.models import SchoolYear, Semester
from academic_period_management.serializers import SchoolYearSerializer, SemesterSerializer
from user_management.permissions import IsSystemAdmin

from .models import StudentAcademicRecord
from .rollover import (
    active_semester, clean_spaces as _clean_spaces, confirm_rollover,
    latest_records_by_student, next_academic_step,
    next_rollover_semester, normalize_year_level as _normalize_year_level,
    semester_key, YEAR_LEVELS,
)
from .serializers import (
    EnrollmentSectionPreviewRowSerializer,
    RolloverActionSerializer,
    StudentAcademicRecordSerializer,
    StudentAcademicRecordWriteSerializer,
    StudentOptionSerializer,
)


User = get_user_model()


def records_queryset():
    return StudentAcademicRecord.objects.select_related(
        'student', 'semester', 'semester__school_year', 'rolled_from__semester__school_year',
    )


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


def filter_academic_records(queryset, params):
    search = params.get('search', '').strip()
    school_year = params.get('school_year', '').strip()
    semester = params.get('semester', '').strip()
    if search:
        queryset = queryset.filter(Q(student__username__icontains=search) | Q(student__first_name__icontains=search)
                                  | Q(student__last_name__icontains=search) | Q(student__email__icontains=search))
    if school_year:
        queryset = queryset.filter(semester__school_year__label=school_year)
    if semester:
        queryset = queryset.filter(semester__label=semester)
    for key in ('year_level', 'section'):
        value = params.get(key, '')
        if value == 'UNASSIGNED' and key == 'section':
            queryset = queryset.filter(Q(section='') | Q(section__iexact='BSIT'))
        elif value and value != 'ALL':
            queryset = queryset.filter(**{key: value})
    return queryset


class StudentAcademicRecordListCreateView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request):
        queryset = filter_academic_records(records_queryset(), request.query_params)

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


class EnrollmentSectionPreviewView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request):
        """Resolve defaults and preflight row validations without creating users or enrollment."""
        from student_teams.continuation_sections import section_decisions
        from student_teams.section_years import enrollment_section_issue

        semester_id = request.data.get('semester_id')
        if not isinstance(semester_id, int) or isinstance(semester_id, bool):
            return Response({'detail': 'semester_id must be an integer.'}, status=400)
        semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        students = request.data.get('students')
        if not isinstance(students, list) or len(students) > 1000:
            return Response({'detail': 'Provide up to 1000 student rows.'}, status=400)
        if any(not isinstance(s, dict) for s in students):
            return Response({'detail': 'Each student must be an object.'}, status=400)

        serializer = EnrollmentSectionPreviewRowSerializer(data=students, many=True)
        serializer.is_valid(raise_exception=True)
        validated_students = serializer.validated_data

        names = [_clean_spaces(s.get('id_number')) for s in validated_students]
        all_users = {u.username: u for u in User.objects.filter(username__in=names)}
        student_users = {uname: u for uname, u in all_users.items() if u.role == 'student'}

        years = {
            student_users[name].pk: _normalize_year_level(s.get('year_level', ''))
            for name, s in zip(names, validated_students)
            if name in student_users
        }
        explicit = {
            student_users[name].pk: _clean_spaces(s.get('section', ''))
            for name, s in zip(names, validated_students)
            if name in student_users
        }
        decisions = section_decisions(semester, years, explicit)

        student_pks = [u.pk for u in student_users.values()]
        active_records = {
            r.student_id: r
            for r in StudentAcademicRecord.objects.filter(student_id__in=student_pks, semester=semester)
        }
        latest_records = {
            r.student_id: r
            for r in latest_records_by_student(student_pks)
        }
        year_rank = {yr: idx for idx, yr in enumerate(YEAR_LEVELS, start=1)}

        results = []
        seen_in_request = {}
        for idx, (name, s) in enumerate(zip(names, validated_students)):
            raw_student_dict = students[idx] if idx < len(students) else {}
            client_error = _clean_spaces(str(raw_student_dict.get('_client_validation_error') or ''))
            norm_year = _normalize_year_level(s.get('year_level', ''))
            supplied_sec = _clean_spaces(s.get('section', ''))

            # Base decision dictionary
            if name in student_users:
                base = dict(id_number=name, **decisions[student_users[name].pk])
            else:
                sec_issue = enrollment_section_issue(supplied_sec, norm_year, semester) if norm_year in year_rank else ''
                base = {
                    'id_number': name,
                    'section': supplied_sec,
                    'source': 'review' if sec_issue else ('explicit' if supplied_sec else 'unassigned'),
                    'message': sec_issue,
                }

            blocking = False
            status_code = 'ready'
            status_label = 'Ready to Enroll'

            # 1. Cross-file / within-batch conflict
            prev_pair = seen_in_request.get(name)
            if prev_pair is not None and prev_pair != (norm_year, supplied_sec):
                blocking = True
                status_code = 'duplicate_conflict'
                status_label = 'Blocked (Conflicting Duplicate)'
                base['source'] = 'review'
                base['message'] = f"Conflicting rows for student '{name}' across staged files."
            seen_in_request[name] = (norm_year, supplied_sec)

            if client_error and not blocking:
                blocking = True
                status_code = 'client_conflict'
                status_label = 'Blocked (File Conflict)'
                base['source'] = 'review'
                base['message'] = client_error

            # 2. Missing or invalid year level
            if not blocking and norm_year not in year_rank:
                blocking = True
                status_code = 'invalid_year'
                status_label = 'Blocked (Invalid Year Level)'
                base['source'] = 'review'
                base['message'] = 'A valid year level (1st Year to 4th Year) is required.'

            # 3. ID belongs to faculty / admin
            existing_any = all_users.get(name)
            if not blocking and existing_any is not None and existing_any.role != 'student':
                blocking = True
                status_code = 'role_conflict'
                status_label = f"Blocked ({existing_any.role.title()} ID)"
                base['source'] = 'review'
                base['message'] = f"ID '{name}' is already assigned to a {existing_any.role} account."

            # 4. Existing student progression & active-term checks
            student_user = student_users.get(name)
            if not blocking and student_user is not None:
                active_rec = active_records.get(student_user.pk)
                latest_rec = latest_records.get(student_user.pk)

                if active_rec is not None:
                    if active_rec.year_level != norm_year:
                        blocking = True
                        status_code = 'year_conflict'
                        status_label = f'Blocked (Enrolled as {active_rec.year_level})'
                        base['source'] = 'review'
                        base['message'] = (
                            f'Student is already enrolled in {semester.display_name} as {active_rec.year_level}, '
                            f'but file specifies {norm_year}.'
                        )
                    elif supplied_sec and supplied_sec != active_rec.section:
                        status_code = 'update_section'
                        status_label = 'Already Enrolled (Updates Section)'
                    else:
                        status_code = 'already_enrolled'
                        status_label = 'Already Enrolled'
                elif latest_rec is not None:
                    if semester_key(semester) < semester_key(latest_rec.semester):
                        blocking = True
                        status_code = 'term_regression'
                        status_label = 'Blocked (Newer Term Exists)'
                        base['source'] = 'review'
                        base['message'] = (
                            f'Student already has a record in a later term ({latest_rec.semester.display_name}).'
                        )
                    elif year_rank.get(norm_year, 0) < year_rank.get(latest_rec.year_level, 0):
                        blocking = True
                        status_code = 'year_regression'
                        status_label = f'Blocked (Was {latest_rec.year_level})'
                        base['source'] = 'review'
                        base['message'] = (
                            f'Year level cannot regress from {latest_rec.year_level} '
                            f'({latest_rec.semester.display_name}) to {norm_year}.'
                        )
                    else:
                        expected_year, _ = next_academic_step(
                            latest_rec.year_level, latest_rec.semester.label
                        )
                        if (
                            latest_rec.semester.label == Semester.SECOND
                            and semester.label == Semester.FIRST
                            and norm_year == latest_rec.year_level
                            and expected_year != norm_year
                        ):
                            blocking = True
                            status_code = 'progression_mismatch'
                            status_label = f'Blocked (Expected {expected_year})'
                            base['source'] = 'review'
                            base['message'] = (
                                f'Student completed {latest_rec.year_level} in {latest_rec.semester.display_name}. '
                                f'Expected {expected_year} for 1st Semester (or use Semester Rollover to retain).'
                            )
                        else:
                            status_code = 'existing_student'
                            status_label = 'Existing Student — Ready'

            # 5. Section / Capstone continuation review flag from section_decisions
            if not blocking and base.get('source') == 'review':
                blocking = True
                status_code = 'section_review'
                status_label = 'Needs Review'

            base['blocking'] = blocking
            base['status_code'] = status_code
            base['status_label'] = status_label
            results.append(base)

        return Response({'sections': results})


class RolloverPreviewView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request):
        active = active_semester()
        latest = latest_records_by_student()
        rows = []

        from student_teams.continuation_sections import section_decisions
        steps = {record.pk: next_rollover_semester(record) for record in latest}
        groups = {}
        for record in latest:
            year, _, term = steps[record.pk]
            if term:
                groups.setdefault(term.pk, (term, {}))[1][record.student_id] = year
        decisions = {pk: section_decisions(term, years) for pk, (term, years) in groups.items()}

        for record in latest:
            next_year_level, next_semester, target_semester = steps[record.pk]
            decision = decisions[target_semester.pk].get(record.student_id) if target_semester else None
            from student_teams.section_years import enrollment_section_issue
            fallback_section = '' if enrollment_section_issue(record.section,
                next_year_level, target_semester) else record.section
            rows.append({
                'record': StudentAcademicRecordSerializer(record).data,
                'promote_result': {
                    'year_level': next_year_level,
                    'semester': next_semester,
                    'target_semester_id': target_semester.id if target_semester else None,
                    'section': decision['section'] if decision and decision.get('team_id') else fallback_section,
                    'section_automatic': bool(decision and decision.get('team_id')),
                    'section_resolution': decision if decision and decision.get('team_id') else None,
                },
                'retain_result': {
                    'year_level': record.year_level,
                    'semester': next_semester,
                    'target_semester_id': target_semester.id if target_semester else None,
                    'section': record.section,
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

        for s in students_data:
            if not isinstance(s, dict):
                return Response({'detail': 'Each student must be an object.'}, status=status.HTTP_400_BAD_REQUEST)
            file_meta = s.get('_fileMetadata') if isinstance(s.get('_fileMetadata'), dict) else {}
            file_sy = _clean_spaces(file_meta.get('school_year'))
            file_sem = _clean_spaces(file_meta.get('semester'))
            if (file_sy and file_sy != active.school_year.label) or (file_sem and file_sem != active.label):
                file_term = f'{file_sem}, A.Y. {file_sy}'.strip(', ')
                return Response(
                    {'detail': f'Academic term mismatch: The uploaded class list is for {file_term}, but the active semester is {active.display_name}.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        latest = latest_records_by_student()
        latest_by_username = {r.student.username: r for r in latest}
        
        # Build map of CSV students
        csv_students = {}
        for s in students_data:
            if not isinstance(s, dict):
                return Response({'detail': 'Each student must be an object.'}, status=status.HTTP_400_BAD_REQUEST)
            id_num = _clean_spaces(s.get('id_number') or s.get('student_number'))
            if id_num:
                if id_num in csv_students and csv_students[id_num] != s:
                    return Response({'detail': f"Conflicting enrollment rows for student '{id_num}'."}, status=status.HTTP_400_BAD_REQUEST)
                csv_students[id_num] = s

        # Find existing users
        existing_users = {
            u.username: u 
            for u in User.objects.filter(username__in=csv_students.keys())
        }
        from student_teams.continuation_sections import section_decisions
        section_defaults = section_decisions(active,
            {u.pk: _normalize_year_level(csv_students[name].get('year_level', ''))
                for name, u in existing_users.items() if u.role == 'student'},
            {u.pk: _clean_spaces(csv_students[name].get('section', ''))
                for name, u in existing_users.items() if u.role == 'student'})

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
            decision = section_defaults.get(user.pk) if user else None
            automatic_section = bool(decision and decision.get('team_id') and not target_section)
            if decision and decision.get('team_id'):
                target_section = decision['section']
            if target_year not in dict(StudentAcademicRecord.YEAR_LEVEL_CHOICES):
                val_error = 'Invalid or missing year level.'
            if len(target_section) > 80:
                val_error = 'Section must be at most 80 characters.'
            if user and not user.is_active:
                val_error = 'Student account is inactive.'

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
                    'section_automatic': automatic_section,
                    'section_resolution': decision if decision and decision.get('team_id') else None,
                },
                'retain_result': {
                    'year_level': latest_record.year_level if latest_record else target_year,
                    'semester': active.label,
                    'target_semester_id': active.id,
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
                    'semester': active.label,
                    'target_semester_id': active.id,
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

        try:
            created, skipped, team_updates = confirm_rollover(serializer.validated_data, active)
        except ModelValidationError as exc:
            return Response({'detail': exc.message_dict if hasattr(exc, 'message_dict') else exc.messages},
                            status=status.HTTP_400_BAD_REQUEST)
        except IntegrityError:
            return Response({'detail': 'Enrollment changed during rollover. Refresh the preview and try again.'},
                            status=status.HTTP_409_CONFLICT)

        return Response({
            'created': StudentAcademicRecordSerializer(created, many=True).data,
            'created_count': len(created),
            'skipped': skipped,
            'skipped_count': len(skipped),
            'team_updates': team_updates,
            'schedules_archived': 0,
            'counts': counts_payload(),
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
