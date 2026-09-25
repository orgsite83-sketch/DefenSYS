import logging
import re

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import ProtectedError, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.throttling import AnonRateThrottle

from academic_period_management.models import Semester
from defense.scheduler.models import DefenseSchedule
from user_management.academic_records.models import StudentAcademicRecord
from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.guest_tokens import (
    create_guest_access_token,
    get_guest_code_or_none,
    guest_user_payload,
)
from authentication_access_control.models import SystemAuditLog
from .models import FacultyRoleAssignment, GuestPanelistCode, SectionInstructorAssignment
from .permissions import IsFacultyRole, IsPitLead, IsPitLeadOrAdmin, IsSystemAdmin
from student_teams.models import TeamAdviserAssignment
from student_teams.serializers import TeamAdviserAssignmentSerializer

from .serializers import (
    BulkUserRowSerializer,
    DefenseScheduleOptionSerializer,
    FacultyRoleAssignmentSerializer,
    GuestPanelistCodeCreateSerializer,
    GuestPanelistCodeSerializer,
    ManagedUserSerializer,
    OfficialClassListStudentSerializer,
    SectionInstructorAssignmentSerializer,
)


logger = logging.getLogger(__name__)
User = get_user_model()


def user_counts():
    return {
        'all': User.objects.count(),
        'admins': User.objects.filter(role='admin').count(),
        'faculty': User.objects.filter(role__in=['faculty', 'admin']).count(),
        'students': User.objects.filter(role='student').count(),
        'active': User.objects.filter(is_active=True).count(),
        'advisers': User.objects.filter(role__in=['faculty', 'admin'], is_adviser=True).count(),
        'panelists': User.objects.filter(role__in=['faculty', 'admin'], is_panelist=True).count(),
    }


def guest_code_counts():
    return {
        'total': GuestPanelistCode.objects.count(),
        'active': GuestPanelistCode.objects.filter(is_active=True).count(),
        'revoked': GuestPanelistCode.objects.filter(is_active=False).count(),
    }


def guest_codes_queryset():
    return GuestPanelistCode.objects.select_related(
        'defense_schedule',
        'defense_schedule__semester',
        'defense_schedule__semester__school_year',
        'defense_schedule__team',
        'defense_schedule__defense_stage',
        'created_by',
    )


def guest_schedule_options_queryset():
    return (
        DefenseSchedule.objects.select_related(
            'semester',
            'semester__school_year',
            'team',
            'defense_stage',
        )
        .exclude(status__in=[DefenseSchedule.STATUS_CANCELLED, DefenseSchedule.STATUS_ARCHIVED])
        .order_by('-scheduled_date', '-start_time', 'team__name')
    )


def guest_codes_payload():
    codes = guest_codes_queryset()
    schedules = guest_schedule_options_queryset()
    return {
        'guest_codes': GuestPanelistCodeSerializer(codes, many=True).data,
        'defense_schedules': DefenseScheduleOptionSerializer(schedules, many=True).data,
        'guest_counts': guest_code_counts(),
    }


class UserListCreateView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request):
        users = User.objects.all().order_by('username')
        search = request.query_params.get('search', '').strip()
        role = request.query_params.get('role', '').strip()

        if search:
            users = users.filter(
                Q(username__icontains=search)
                | Q(first_name__icontains=search)
                | Q(last_name__icontains=search)
                | Q(email__icontains=search)
            )

        if role == 'faculty':
            users = users.filter(role__in=['faculty', 'admin'])
        elif role == 'panelist':
            users = users.filter(role__in=['faculty', 'admin'], is_panelist=True)
        elif role == 'pit_lead':
            users = users.filter(role__in=['faculty', 'admin'], is_pit_lead=True)
        elif role == 'adviser':
            users = users.filter(role__in=['faculty', 'admin'], is_adviser=True)
        elif role == 'documenter':
            users = users.filter(role__in=['faculty', 'admin'], is_documenter=True)
        elif role == 'pit_instructor':
            from user_management.models import SectionInstructorAssignment
            active_sem = _active_semester()
            instructor_qs = SectionInstructorAssignment.objects.filter(is_active=True)
            if active_sem:
                instructor_qs = instructor_qs.filter(semester=active_sem)
            instructor_ids = instructor_qs.values_list('faculty_id', flat=True)
            users = users.filter(pk__in=instructor_ids)
        elif role in dict(User.ROLE_CHOICES):
            users = users.filter(role=role)

        return Response({
            'users': ManagedUserSerializer(
                users, many=True, context={'request': request}
            ).data,
            'counts': user_counts(),
        })

    def post(self, request):
        serializer = ManagedUserSerializer(
            data=request.data, context={'request': request}
        )
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        return Response(
            {'user': ManagedUserSerializer(user).data, 'counts': user_counts()},
            status=status.HTTP_201_CREATED,
        )


class UserDetailView(APIView):
    permission_classes = [IsSystemAdmin]

    def get_object(self, user_id):
        return get_object_or_404(User, pk=user_id)

    def get(self, request, user_id):
        user = self.get_object(user_id)
        return Response({
            'user': ManagedUserSerializer(user, context={'request': request}).data,
        })

    def patch(self, request, user_id):
        user = self.get_object(user_id)
        serializer = ManagedUserSerializer(
            user, data=request.data, partial=True, context={'request': request}
        )
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        return Response({
            'user': ManagedUserSerializer(user, context={'request': request}).data,
            'counts': user_counts(),
        })

    def delete(self, request, user_id):
        user = self.get_object(user_id)
        if user.pk == request.user.pk:
            return Response(
                {'detail': 'You cannot delete your own administrator account.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        username = user.username
        full_name = user.get_full_name() or username

        try:
            with transaction.atomic():
                log_high_impact_action(
                    category=SystemAuditLog.CATEGORY_USER_MANAGEMENT,
                    action='user.delete',
                    target=user,
                    target_type='User',
                    target_id=str(user.pk),
                    reason=f"Deleted user account {username} ({full_name})",
                    old_values={'username': username, 'role': user.role, 'email': user.email},
                    request=request,
                )
                user.delete()
        except ProtectedError:
            from student_teams.models import StudentTeam
            led_teams = list(StudentTeam.objects.filter(leader_id=user_id).values_list('name', flat=True))
            if led_teams:
                teams_str = ', '.join(led_teams[:3])
                return Response(
                    {
                        'detail': f'Cannot delete user "{username}" because they are currently designated as the Team Leader for: {teams_str}. Please reassign team leadership or remove the team before deleting this account.'
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response(
                {
                    'detail': f'Cannot delete user "{username}" because they are linked to active protected records in the system.'
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as e:
            logger.exception("Failed to delete user %s", user_id)
            return Response(
                {'detail': f'Failed to delete user: {str(e)}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return Response(
            {
                'detail': f'User account {username} deleted successfully.',
                'counts': user_counts(),
            },
            status=status.HTTP_200_OK,
        )


class UserAdviserAssignmentHistoryView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request, user_id):
        user = get_object_or_404(User, pk=user_id)
        assignments = (
            TeamAdviserAssignment.objects.filter(adviser=user)
            .select_related('adviser', 'assigned_by', 'team', 'team__semester')
            .order_by('-assigned_at', '-id')
        )
        return Response({
            'assignments': TeamAdviserAssignmentSerializer(assignments, many=True).data,
        })


class UserRoleAssignmentHistoryView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request, user_id):
        user = get_object_or_404(User, pk=user_id)
        assignments = (
            FacultyRoleAssignment.objects.filter(user=user)
            .select_related('semester', 'semester__school_year', 'changed_by')
            .order_by('-changed_at', '-id')
        )
        return Response({
            'assignments': FacultyRoleAssignmentSerializer(assignments, many=True).data,
        })


def _active_semester():
    from academic_period_management.services import active_semester
    return active_semester()


def _is_admin(user):
    return bool(user and (getattr(user, 'role', None) == 'admin' or user.is_superuser))


def _pit_instructor_scope_for(user, requested_year=''):
    if _is_admin(user):
        return (requested_year or '').strip()
    return (getattr(user, 'pit_lead_year', None) or '').strip()


def _clean_spaces(value):
    return ' '.join((value or '').strip().split())


def _split_official_full_name(full_name):
    full_name = _clean_spaces(full_name)
    if not full_name:
        return '', ''

    if ',' in full_name:
        last, rest = full_name.split(',', 1)
        parts = [part for part in _clean_spaces(rest).split(' ') if part]
        first = ' '.join(part for part in parts if len(part.rstrip('.')) > 1)
        return first or _clean_spaces(rest), _clean_spaces(last)

    parts = full_name.split(' ')
    if len(parts) == 1:
        return parts[0], ''
    return ' '.join(parts[:-1]), parts[-1]


def _normalize_person_name(value):
    value = (value or '').lower()
    value = re.sub(r'\b(prof|professor|engr|eng|dr|mr|mrs|ms)\.?\b', ' ', value)
    value = re.sub(r'[^a-z0-9]+', ' ', value)
    return _clean_spaces(value)


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


def _faculty_match_keys(user):
    first = _normalize_person_name(user.first_name)
    last = _normalize_person_name(user.last_name)
    username = _normalize_person_name(user.username)
    email = _normalize_person_name(user.email.split('@')[0] if user.email else '')
    keys = {key for key in [username, email] if key}
    if first and last:
        keys.add(f'{first} {last}')
        keys.add(f'{last} {first}')
    elif first or last:
        keys.add(first or last)
    return keys


def _match_faculty_by_name(faculty_name):
    normalized = _normalize_person_name(faculty_name)
    if not normalized:
        return None, 'missing'

    matches = []
    for faculty in User.objects.filter(role__in=['faculty', 'admin'], is_active=True):
        for key in _faculty_match_keys(faculty):
            if normalized == key or normalized.startswith(f'{key} ') or key.startswith(f'{normalized} '):
                matches.append(faculty)
                break

    unique = {faculty.pk: faculty for faculty in matches}
    if len(unique) == 1:
        return next(iter(unique.values())), 'matched'
    if len(unique) > 1:
        return None, 'ambiguous'
    return None, 'not_found'


class SectionInstructorAssignmentView(APIView):
    permission_classes = [IsPitLeadOrAdmin]

    def get(self, request):
        active = _active_semester()
        year_level = _pit_instructor_scope_for(
            request.user,
            request.query_params.get('year_level', ''),
        )
        assignments = SectionInstructorAssignment.objects.select_related(
            'faculty',
            'semester',
            'semester__school_year',
            'assigned_by',
        )
        if active:
            assignments = assignments.filter(semester=active)
        if year_level:
            assignments = assignments.filter(year_level=year_level)

        faculty = (
            User.objects.filter(role__in=['faculty', 'admin'], is_active=True)
            .order_by('last_name', 'first_name', 'username')
        )

        return Response({
            'assignments': SectionInstructorAssignmentSerializer(assignments, many=True).data,
            'faculty': ManagedUserSerializer(faculty, many=True, context={'request': request}).data,
            'active_semester': active.display_name if active else None,
            'year_level': year_level,
        })

    def post(self, request):
        active = _active_semester()
        if active is None:
            return Response({'detail': 'No active semester is configured.'}, status=status.HTTP_400_BAD_REQUEST)

        year_level = _pit_instructor_scope_for(request.user, request.data.get('year_level', ''))
        section = ' '.join((request.data.get('section') or '').strip().split())
        faculty_id = request.data.get('faculty_id') or request.data.get('faculty')

        if not year_level:
            return Response({'year_level': ['PIT Lead year level is required.']}, status=status.HTTP_400_BAD_REQUEST)
        if not section:
            return Response({'section': ['Section is required.']}, status=status.HTTP_400_BAD_REQUEST)

        from student_teams.team_levels import is_capstone_scope
        if is_capstone_scope(year_level, active):
            return Response(
                {'year_level': ['Section Instructors are only assigned for PIT scope (1st Year, 2nd Year, 3rd Year 1st Sem). Capstone scope assigns Project Advisers to teams directly.']},
                status=status.HTTP_400_BAD_REQUEST,
            )

        faculty = User.objects.filter(pk=faculty_id, role__in=['faculty', 'admin'], is_active=True).first()
        if faculty is None:
            return Response({'faculty_id': ['Select an active faculty user.']}, status=status.HTTP_400_BAD_REQUEST)

        assignment, _created = SectionInstructorAssignment.objects.update_or_create(
            faculty=faculty,
            semester=active,
            year_level=year_level,
            section=section,
            defaults={
                'assigned_by': request.user,
                'is_active': True,
            },
        )
        return Response(
            {'assignment': SectionInstructorAssignmentSerializer(assignment).data},
            status=status.HTTP_201_CREATED,
        )


class SectionInstructorAssignmentDetailView(APIView):
    permission_classes = [IsPitLeadOrAdmin]

    def patch(self, request, assignment_id):
        assignment = get_object_or_404(SectionInstructorAssignment, pk=assignment_id)
        if not _is_admin(request.user):
            pit_year = (getattr(request.user, 'pit_lead_year', None) or '').strip()
            if assignment.year_level != pit_year:
                return Response({'detail': 'This assignment is outside your PIT scope.'}, status=status.HTTP_403_FORBIDDEN)

        if 'is_active' in request.data:
            assignment.is_active = request.data.get('is_active') is True
        if _is_admin(request.user) and request.data.get('section') is not None:
            assignment.section = request.data.get('section')
        assignment.assigned_by = request.user
        assignment.save()
        return Response({'assignment': SectionInstructorAssignmentSerializer(assignment).data})


class BulkImportUsersMixin:
    force_student_only = False
    force_pit_lead_context = False

    def post(self, request):
        rows = request.data.get('users', [])
        if not isinstance(rows, list):
            return Response({'detail': 'users must be a list.'}, status=status.HTTP_400_BAD_REQUEST)

        student_context = request.data.get('student_context') or {}
        if self.force_pit_lead_context:
            context_semester = _active_semester()
            context_year_level = (getattr(request.user, 'pit_lead_year', None) or '').strip()
            if context_semester is None:
                return Response({'detail': 'No active semester is configured.'}, status=status.HTTP_400_BAD_REQUEST)
            if not context_year_level:
                return Response({'detail': 'Your PIT Lead account has no assigned year level.'}, status=status.HTTP_400_BAD_REQUEST)
        else:
            context_semester = self._resolve_context_semester(student_context)
            context_year_level = _normalize_year_level(student_context.get('year_level') or '')

        if (self.force_student_only or bool(request.data.get('student_context'))) and context_semester is None:
            return Response(
                {'detail': 'An active academic semester is required to import and enroll students. Please configure an active semester first.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        context_section = ' '.join((student_context.get('section') or '').strip().split())
        faculty_name = _clean_spaces(
            student_context.get('instructor_name')
            or student_context.get('instructor')
            or student_context.get('faculty_name')
            or student_context.get('faculty')
        )
        from student_teams.team_levels import is_capstone_scope
        if is_capstone_scope(context_year_level, context_semester):
            require_faculty_match = False
        else:
            require_faculty_match = student_context.get('require_faculty_match') is True

        instructor_assignment = None
        faculty_match_status = None
        if require_faculty_match:
            if context_semester is None:
                return Response({'semester_id': ['A target semester is required before assigning a PIT Instructor.']}, status=status.HTTP_400_BAD_REQUEST)
            if not context_year_level:
                return Response({'year_level': ['Year level is required before assigning a PIT Instructor.']}, status=status.HTTP_400_BAD_REQUEST)
            if not context_section:
                return Response({'section': ['Class section is required before assigning a PIT Instructor.']}, status=status.HTTP_400_BAD_REQUEST)
            if not faculty_name:
                return Response({'instructor_name': ['Instructor is required in the official class list before importing students.']}, status=status.HTTP_400_BAD_REQUEST)

            faculty, faculty_match_status = _match_faculty_by_name(faculty_name)
            if faculty is None:
                detail = (
                    'Instructor name matched multiple accounts. Resolve the faculty account before importing students.'
                    if faculty_match_status == 'ambiguous'
                    else 'Instructor could not be matched to an active faculty account. Import faculty first or correct the class list instructor name.'
                )
                return Response({'instructor_name': [detail]}, status=status.HTTP_400_BAD_REQUEST)

        created = []
        records_created = []
        skipped = []
        errors = []
        section_instructors = {}
        if faculty_name and context_year_level and context_section and not is_capstone_scope(context_year_level, context_semester):
            section_instructors[(context_year_level, context_section)] = faculty_name

        for index, row in enumerate(rows, start=1):
            serializer = BulkUserRowSerializer(data=row)
            if not serializer.is_valid():
                errors.append({'row': index, 'errors': serializer.errors})
                continue

            data = serializer.validated_data
            username = data['id_number'].strip()
            role = data.get('role', 'student')
            if self.force_student_only and role != 'student':
                errors.append({
                    'row': index,
                    'id_number': username,
                    'errors': {'role': ['PIT Leads can import student users only.']},
                })
                continue
            existing_user = User.objects.filter(username=username).first()
            year_level = _normalize_year_level(data.get('year_level') or context_year_level or '')
            if self.force_pit_lead_context:
                row_year = (data.get('year_level') or '').strip()
                if row_year and row_year != context_year_level:
                    errors.append({
                        'row': index,
                        'id_number': username,
                        'errors': {'year_level': [f'PIT Lead import is limited to {context_year_level}.']},
                    })
                    continue
                year_level = context_year_level
            section = ' '.join((data.get('section') or context_section or '').strip().split())

            row_instr = _clean_spaces(
                data.get('instructor')
                or data.get('instructor_name')
                or data.get('faculty')
                or row.get('instructor')
                or row.get('instructor_name')
                or row.get('faculty')
                or ''
            )
            if row_instr and year_level and section and not is_capstone_scope(year_level, context_semester):
                section_instructors[(year_level, section)] = row_instr

            if existing_user:
                if existing_user.role == 'student' and context_semester is not None and year_level:
                    update_defaults = {'year_level': year_level}
                    if section:
                        update_defaults['section'] = section
                    record, _ = StudentAcademicRecord.objects.update_or_create(
                        student=existing_user,
                        semester=context_semester,
                        defaults=update_defaults,
                    )
                    records_created.append(record)
                    updated_fields = []
                    if data.get('first_name') and existing_user.first_name != data['first_name']:
                        existing_user.first_name = data['first_name']
                        updated_fields.append('first_name')
                    if data.get('last_name') and existing_user.last_name != data['last_name']:
                        existing_user.last_name = data['last_name']
                        updated_fields.append('last_name')
                    if data.get('email') and existing_user.email != data['email']:
                        existing_user.email = data['email']
                        updated_fields.append('email')
                    if data.get('phone_number') and existing_user.phone_number != data['phone_number']:
                        existing_user.phone_number = data['phone_number']
                        updated_fields.append('phone_number')
                    if updated_fields:
                        existing_user.save(update_fields=updated_fields)
                elif existing_user.role == 'faculty' and not self.force_student_only:
                    updated_fields = []
                    if data.get('first_name') and existing_user.first_name != data['first_name']:
                        existing_user.first_name = data['first_name']
                        updated_fields.append('first_name')
                    if data.get('last_name') and existing_user.last_name != data['last_name']:
                        existing_user.last_name = data['last_name']
                        updated_fields.append('last_name')
                    if data.get('email') and existing_user.email != data['email']:
                        existing_user.email = data['email']
                        updated_fields.append('email')
                    if data.get('phone_number') and existing_user.phone_number != data['phone_number']:
                        existing_user.phone_number = data['phone_number']
                        updated_fields.append('phone_number')
                    if 'is_panelist' in data and existing_user.is_panelist != data['is_panelist']:
                        existing_user.is_panelist = data['is_panelist']
                        updated_fields.append('is_panelist')
                    if 'is_adviser' in data and existing_user.is_adviser != data['is_adviser']:
                        existing_user.is_adviser = data['is_adviser']
                        updated_fields.append('is_adviser')
                    if 'is_pit_lead' in data and existing_user.is_pit_lead != data['is_pit_lead']:
                        existing_user.is_pit_lead = data['is_pit_lead']
                        updated_fields.append('is_pit_lead')
                    if 'pit_lead_year' in data and existing_user.pit_lead_year != data['pit_lead_year']:
                        existing_user.pit_lead_year = data['pit_lead_year']
                        updated_fields.append('pit_lead_year')
                    if 'is_documenter' in data and existing_user.is_documenter != data['is_documenter']:
                        existing_user.is_documenter = data['is_documenter']
                        updated_fields.append('is_documenter')
                    if 'is_uploader' in data and existing_user.is_uploader != data['is_uploader']:
                        existing_user.is_uploader = data['is_uploader']
                        updated_fields.append('is_uploader')
                    if updated_fields:
                        existing_user.save(update_fields=updated_fields)
                        created.append(existing_user)
                    else:
                        skipped.append({'row': index, 'id_number': username, 'reason': 'duplicate'})
                else:
                    skipped.append({'row': index, 'id_number': username, 'reason': 'duplicate'})
                continue

            user = User.objects.create_user(
                username=username,
                password=username,
                first_name=data.get('first_name', ''),
                last_name=data.get('last_name', ''),
                email=data.get('email', ''),
                phone_number=data.get('phone_number', '').strip(),
                role='student' if self.force_student_only else role,
                is_panelist=False if self.force_student_only else data.get('is_panelist', False),
                is_adviser=False if self.force_student_only else data.get('is_adviser', False),
                is_pit_lead=False if self.force_student_only else data.get('is_pit_lead', False),
                pit_lead_year=None if self.force_student_only else data.get('pit_lead_year'),
                is_documenter=False if self.force_student_only else data.get('is_documenter', False),
                is_uploader=False if self.force_student_only else data.get('is_uploader', False),
            )
            created.append(user)
            if user.role == 'student' and context_semester is not None and year_level:
                records_created.append(StudentAcademicRecord.objects.create(
                    student=user,
                    semester=context_semester,
                    year_level=year_level,
                    section=section,
                ))

        instructor_warnings = []
        assigned_instructors = []
        if require_faculty_match and faculty is not None and not is_capstone_scope(context_year_level, context_semester):
            instructor_assignment, _assignment_created = SectionInstructorAssignment.objects.update_or_create(
                faculty=faculty,
                semester=context_semester,
                year_level=context_year_level,
                section=context_section,
                defaults={
                    'assigned_by': request.user,
                    'is_active': True,
                },
            )
            assigned_instructors.append(instructor_assignment)
        elif context_semester is not None and section_instructors:
            for (sec_year, sec_name), instr_name in section_instructors.items():
                if is_capstone_scope(sec_year, context_semester):
                    continue
                matched_faculty, match_status = _match_faculty_by_name(instr_name)
                if matched_faculty is not None:
                    assignment, _assignment_created = SectionInstructorAssignment.objects.update_or_create(
                        faculty=matched_faculty,
                        semester=context_semester,
                        year_level=sec_year,
                        section=sec_name,
                        defaults={
                            'assigned_by': request.user,
                            'is_active': True,
                        },
                    )
                    assigned_instructors.append(assignment)
                    if instructor_assignment is None:
                        instructor_assignment = assignment
                        faculty_match_status = match_status
                else:
                    instructor_warnings.append(
                        f"Instructor '{instr_name}' for section '{sec_name}' could not be matched to an active faculty account."
                    )

        return Response({
            'created': ManagedUserSerializer(created, many=True).data,
            'created_count': len(created),
            'records_created_count': len(records_created),
            'skipped': skipped,
            'skipped_count': len(skipped),
            'errors': errors,
            'error_count': len(errors),
            'faculty_match_status': faculty_match_status,
            'instructor_assignment': (
                SectionInstructorAssignmentSerializer(instructor_assignment).data
                if instructor_assignment is not None
                else None
            ),
            'instructor_assignments': SectionInstructorAssignmentSerializer(assigned_instructors, many=True).data,
            'instructor_warnings': instructor_warnings,
            'counts': user_counts(),
        }, status=status.HTTP_201_CREATED if (created or records_created) else status.HTTP_200_OK)

    def _resolve_context_semester(self, context):
        if not isinstance(context, dict):
            return _active_semester()

        semester_id = context.get('semester_id')
        if semester_id:
            return Semester.objects.filter(pk=semester_id).first()

        if context.get('use_active_semester') or not context:
            return _active_semester()

        return _active_semester()


class BulkImportUsersView(BulkImportUsersMixin, APIView):
    permission_classes = [IsSystemAdmin]


class PitLeadStudentImportView(BulkImportUsersMixin, APIView):
    permission_classes = [IsPitLead]
    force_student_only = True
    force_pit_lead_context = True


class PitLeadOfficialClassListImportView(APIView):
    permission_classes = [IsPitLead]

    def post(self, request):
        active = _active_semester()
        if active is None:
            return Response({'detail': 'No active semester is configured.'}, status=status.HTTP_400_BAD_REQUEST)

        pit_year = _normalize_year_level(getattr(request.user, 'pit_lead_year', None))
        if not pit_year:
            return Response({'detail': 'Your PIT Lead account has no assigned year level.'}, status=status.HTTP_400_BAD_REQUEST)

        from student_teams.team_levels import is_capstone_scope
        if is_capstone_scope(pit_year, active):
            return Response(
                {'detail': 'Student import for this term is handled under Capstone.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        metadata = request.data.get('metadata') or {}
        if not isinstance(metadata, dict):
            return Response({'metadata': ['metadata must be an object.']}, status=status.HTTP_400_BAD_REQUEST)

        section = _clean_spaces(
            metadata.get('section')
            or metadata.get('class_section')
            or request.data.get('section')
        )
        imported_year = _normalize_year_level(metadata.get('year_level') or request.data.get('year_level') or pit_year)
        faculty_name = _clean_spaces(
            metadata.get('instructor')
            or metadata.get('instructor_name')
            or metadata.get('faculty')
            or metadata.get('faculty_name')
        )
        rows = request.data.get('students') or request.data.get('users') or []

        if not isinstance(rows, list):
            return Response({'students': ['students must be a list.']}, status=status.HTTP_400_BAD_REQUEST)
        if not section:
            return Response({'section': ['Class section is required.']}, status=status.HTTP_400_BAD_REQUEST)
        if imported_year and imported_year != pit_year:
            return Response(
                {'year_level': [f'PIT Lead import is limited to {pit_year}.']},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not faculty_name:
            return Response(
                {'instructor_name': ['Instructor is required in the official class list before importing students.']},
                status=status.HTTP_400_BAD_REQUEST,
            )

        faculty, faculty_match_status = _match_faculty_by_name(faculty_name)
        if faculty is None:
            detail = (
                'Instructor name matched multiple accounts. Resolve the faculty account before importing students.'
                if faculty_match_status == 'ambiguous'
                else 'Instructor could not be matched to an active faculty account. Import faculty first or correct the class list instructor name.'
            )
            return Response({'instructor_name': [detail]}, status=status.HTTP_400_BAD_REQUEST)

        created = []
        updated = []
        records_created = 0
        records_updated = 0
        errors = []
        warnings = []
        seen_ids = {}

        with transaction.atomic():
            for index, row in enumerate(rows, start=1):
                serializer = OfficialClassListStudentSerializer(data=row)
                if not serializer.is_valid():
                    errors.append({'row': index, 'errors': serializer.errors})
                    continue

                data = serializer.validated_data
                username = _clean_spaces(data['id_number'])

                if username in seen_ids:
                    warnings.append(
                        f"Student ID '{username}' is duplicated in the class list (Row {index} and Row {seen_ids[username]})."
                    )
                else:
                    seen_ids[username] = index

                first_name = _clean_spaces(data.get('first_name'))
                last_name = _clean_spaces(data.get('last_name'))
                if not (first_name or last_name):
                    first_name, last_name = _split_official_full_name(data.get('full_name'))
                row_section = _clean_spaces(data.get('section') or section)
                if data.get('section') and row_section != section:
                    warnings.append(
                        f"Row {index} ('{username}'): section '{row_section}' differs from metadata section '{section}'."
                    )
                row_year = _normalize_year_level(data.get('year_level') or pit_year)

                if row_year != pit_year:
                    errors.append({
                        'row': index,
                        'id_number': username,
                        'errors': {'year_level': [f'PIT Lead import is limited to {pit_year}.']},
                    })
                    continue

                phone_number = _clean_spaces(data.get('phone_number') or data.get('contact') or '')
                user, was_created = User.objects.get_or_create(
                    username=username,
                    defaults={
                        'first_name': first_name,
                        'last_name': last_name,
                        'email': data.get('email', ''),
                        'phone_number': phone_number,
                        'role': 'student',
                    },
                )
                if not was_created and user.role != 'student':
                    errors.append({
                        'row': index,
                        'id_number': username,
                        'errors': {'id_number': ['Existing account is not a student.']},
                    })
                    continue
                if was_created:
                    user.set_password(username)
                    user.save(update_fields=['password'])

                changed_fields = []
                for field, value in {
                    'first_name': first_name,
                    'last_name': last_name,
                    'email': data.get('email', ''),
                    'phone_number': phone_number,
                }.items():
                    if value and getattr(user, field) != value:
                        setattr(user, field, value)
                        changed_fields.append(field)
                if changed_fields:
                    user.save(update_fields=changed_fields)

                record, record_created = StudentAcademicRecord.objects.update_or_create(
                    student=user,
                    semester=active,
                    defaults={
                        'year_level': pit_year,
                        'section': row_section,
                    },
                )
                if was_created:
                    created.append(user)
                else:
                    updated.append(user)
                if record_created:
                    records_created += 1
                else:
                    records_updated += 1

        instructor_assignment = None
        instructor_assignment, _assignment_created = SectionInstructorAssignment.objects.update_or_create(
            faculty=faculty,
            semester=active,
            year_level=pit_year,
            section=section,
            defaults={
                'assigned_by': request.user,
                'is_active': True,
            },
        )

        return Response({
            'created': ManagedUserSerializer(created, many=True).data,
            'created_count': len(created),
            'updated_count': len(updated),
            'records_created_count': records_created,
            'records_updated_count': records_updated,
            'errors': errors,
            'error_count': len(errors),
            'warnings': warnings,
            'warning_count': len(warnings),
            'faculty_match_status': faculty_match_status,
            'instructor_assignment': (
                SectionInstructorAssignmentSerializer(instructor_assignment).data
                if instructor_assignment is not None
                else None
            ),
            'section': section,
            'year_level': pit_year,
            'active_semester': active.display_name,
            'counts': user_counts(),
        }, status=status.HTTP_201_CREATED if created or records_created else status.HTTP_200_OK)


class GuestPanelistCodeListCreateView(APIView):
    permission_classes = [IsSystemAdmin]

    def get(self, request):
        return Response(guest_codes_payload())

    def post(self, request):
        serializer = GuestPanelistCodeCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        code = serializer.save(created_by=request.user)
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GUEST_ACCESS,
            action='guest_code.create',
            target=code,
            old_values={},
            new_values={
                'code_id': code.pk,
                'guest_name': code.guest_name,
                'defense_schedule_id': code.defense_schedule_id,
                'is_active': code.is_active,
            },
            request=request,
        )
        code = guest_codes_queryset().get(pk=code.pk)

        payload = guest_codes_payload()
        payload['guest_code'] = GuestPanelistCodeSerializer(code).data
        return Response(payload, status=status.HTTP_201_CREATED)


class GuestPanelistCodeDetailView(APIView):
    permission_classes = [IsSystemAdmin]

    def get_object(self, code_id):
        return get_object_or_404(GuestPanelistCode, pk=code_id)

    def patch(self, request, code_id):
        code = self.get_object(code_id)
        old_values = {'is_active': code.is_active}

        if 'is_active' in request.data:
            raw_status = request.data.get('is_active')
            if isinstance(raw_status, bool):
                code.is_active = raw_status
            else:
                code.is_active = str(raw_status).strip().lower() in ['1', 'true', 'yes', 'active']
            code.save(update_fields=['is_active', 'updated_at'])
            log_high_impact_action(
                category=SystemAuditLog.CATEGORY_GUEST_ACCESS,
                action='guest_code.status_change',
                target=code,
                old_values=old_values,
                new_values={'is_active': code.is_active},
                request=request,
            )

        code = guest_codes_queryset().get(pk=code.pk)
        payload = guest_codes_payload()
        payload['guest_code'] = GuestPanelistCodeSerializer(code).data
        return Response(payload)


class GuestCodeThrottle(AnonRateThrottle):
    scope = 'guest_code'


class GuestCodeValidateView(APIView):
    """Public endpoint to validate guest panelist codes"""
    permission_classes = [AllowAny]
    throttle_classes = [GuestCodeThrottle]
    
    def get(self, request, code):
        """Validate a guest code and return guest info if valid"""
        guest_code = get_guest_code_or_none(code)
        if guest_code is None:
            return Response(
                {'error': 'Invalid or expired code'},
                status=status.HTTP_404_NOT_FOUND,
            )

        schedule = guest_code.defense_schedule
        team = schedule.team
        return Response({
            'guestName': guest_code.guest_name,
            'defenseId': schedule.id,
            'defense_schedule_id': schedule.id,
            'team_id': team.id if team else None,
            'guest_code_id': guest_code.id,
            'teamName': team.name if team else 'Unknown',
            'stage': schedule.defense_stage.label if schedule.defense_stage else 'Unknown',
            'code': guest_code.code,
        })


class GuestCodeExchangeView(APIView):
    """Exchange a valid guest code for a short-lived guest panelist access JWT."""

    permission_classes = [AllowAny]
    throttle_classes = [GuestCodeThrottle]

    def post(self, request):
        code = (request.data.get('code') or '').strip().upper()
        if not code:
            return Response(
                {'detail': 'code is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        guest_code = get_guest_code_or_none(code)
        if guest_code is None:
            return Response(
                {'detail': 'Invalid or expired code.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        if guest_code.used_at is None:
            guest_code.used_at = timezone.now()
            guest_code.save(update_fields=['used_at', 'updated_at'])
            action = 'guest_code.first_use'
        else:
            action = 'guest_code.exchange'

        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GUEST_ACCESS,
            action=action,
            target=guest_code,
            target_type='GuestPanelistCode',
            target_id=guest_code.pk,
            old_values={'used_at': None if action == 'guest_code.first_use' else guest_code.used_at.isoformat()},
            new_values={
                'used_at': guest_code.used_at.isoformat() if guest_code.used_at else None,
                'defense_schedule_id': guest_code.defense_schedule_id,
            },
            request=request,
        )

        access = create_guest_access_token(guest_code)
        return Response({
            'access': access,
            'user': guest_user_payload(guest_code),
        })


class ESignatureUploadSerializer(serializers.Serializer):
    e_signature = serializers.ImageField(required=False)
    file = serializers.ImageField(required=False)

    def validate(self, attrs):
        if not attrs.get('e_signature') and not attrs.get('file'):
            raise serializers.ValidationError("Either 'e_signature' or 'file' is required.")
        return attrs


class UserESignatureView(APIView):
    permission_classes = [IsFacultyRole]

    def post(self, request):
        serializer = ESignatureUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        uploaded_file = serializer.validated_data.get('e_signature') or serializer.validated_data.get('file')
        user = request.user

        # Delete old e-signature if exists to avoid orphans
        if user.e_signature:
            try:
                user.e_signature.delete(save=False)
            except Exception:
                pass

        user.e_signature = uploaded_file
        user.save()

        return Response({
            'message': 'E-signature uploaded successfully.',
            'e_signature': user.e_signature.url if user.e_signature else None
        }, status=status.HTTP_200_OK)

    def delete(self, request):
        user = request.user
        if not user.e_signature:
            return Response({
                'message': 'No e-signature found to remove.'
            }, status=status.HTTP_400_BAD_REQUEST)

        try:
            user.e_signature.delete(save=False)
        except Exception:
            pass

        user.e_signature = None
        user.save()

        return Response({
            'message': 'E-signature removed successfully.'
        }, status=status.HTTP_200_OK)


class AdminResetPasswordView(APIView):
    """
    POST /api/users/<user_id>/reset-password/
    Resets a user's password back to their username (student/employee ID).
    Admin only.
    """
    permission_classes = [IsSystemAdmin]

    def post(self, request, user_id):
        user = get_object_or_404(User, pk=user_id)

        if user.pk == request.user.pk:
            return Response(
                {'detail': 'You cannot reset your own password from this screen. Use the Change Password feature.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user.set_password(user.username)
        user.save(update_fields=['password'])

        # Send notification email (best-effort).
        send_email = request.data.get('send_email', True)
        email_sent = False
        if send_email and user.email:
            from notifications.email_service import send_admin_password_reset_email
            email_sent = send_admin_password_reset_email(user)
            if not email_sent:
                logger.warning('admin_password_reset: notification email could not be sent to user_id=%s', user.pk)

        return Response({
            'detail': f'Password for {user.username} has been reset to their ID.',
            'email_sent': email_sent,
        })
