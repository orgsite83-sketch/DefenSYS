from django.contrib.auth import get_user_model
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

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
from .models import FacultyRoleAssignment, GuestPanelistCode
from .permissions import IsSystemAdmin
from student_teams.models import TeamAdviserAssignment
from student_teams.serializers import TeamAdviserAssignmentSerializer

from .serializers import (
    BulkUserRowSerializer,
    DefenseScheduleOptionSerializer,
    FacultyRoleAssignmentSerializer,
    GuestPanelistCodeCreateSerializer,
    GuestPanelistCodeSerializer,
    ManagedUserSerializer,
)


User = get_user_model()


def user_counts():
    return {
        'all': User.objects.count(),
        'admins': User.objects.filter(role='admin').count(),
        'faculty': User.objects.filter(role__in=['faculty', 'admin']).count(),
        'students': User.objects.filter(role='student').count(),
        'active': User.objects.filter(is_active=True).count(),
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
        elif role == 'repo_assistant':
            users = users.filter(role__in=['faculty', 'admin'], is_repo_assistant=True)
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

        user.delete()
        return Response({'counts': user_counts()}, status=status.HTTP_200_OK)


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


class BulkImportUsersView(APIView):
    permission_classes = [IsSystemAdmin]

    def post(self, request):
        rows = request.data.get('users', [])
        if not isinstance(rows, list):
            return Response({'detail': 'users must be a list.'}, status=status.HTTP_400_BAD_REQUEST)

        student_context = request.data.get('student_context') or {}
        context_semester = self._resolve_context_semester(student_context)
        context_year_level = (student_context.get('year_level') or '').strip()

        created = []
        records_created = []
        skipped = []
        errors = []

        for index, row in enumerate(rows, start=1):
            serializer = BulkUserRowSerializer(data=row)
            if not serializer.is_valid():
                errors.append({'row': index, 'errors': serializer.errors})
                continue

            data = serializer.validated_data
            username = data['id_number'].strip()
            if User.objects.filter(username=username).exists():
                skipped.append({'row': index, 'id_number': username, 'reason': 'duplicate'})
                continue

            user = User.objects.create_user(
                username=username,
                password=username,
                first_name=data.get('first_name', ''),
                last_name=data.get('last_name', ''),
                email=data.get('email', ''),
                role=data.get('role', 'student'),
            )
            created.append(user)
            year_level = (data.get('year_level') or context_year_level or '').strip()
            if user.role == 'student' and context_semester is not None and year_level:
                records_created.append(StudentAcademicRecord.objects.create(
                    student=user,
                    semester=context_semester,
                    year_level=year_level,
                ))

        return Response({
            'created': ManagedUserSerializer(created, many=True).data,
            'created_count': len(created),
            'records_created_count': len(records_created),
            'skipped': skipped,
            'skipped_count': len(skipped),
            'errors': errors,
            'error_count': len(errors),
            'counts': user_counts(),
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    def _resolve_context_semester(self, context):
        if not isinstance(context, dict):
            return None

        semester_id = context.get('semester_id')
        if semester_id:
            return Semester.objects.filter(pk=semester_id).first()

        if context.get('use_active_semester'):
            return Semester.objects.select_related('school_year').filter(is_active=True).first()

        return None


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


class GuestCodeValidateView(APIView):
    """Public endpoint to validate guest panelist codes"""
    permission_classes = [AllowAny]
    
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
