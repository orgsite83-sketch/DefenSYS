from django.contrib.auth import get_user_model
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.capstone_mode import (
    assert_capstone_team_creation_allowed,
    capstone_mode_payload,
)
from academic_period_management.models import Semester
from academic_period_management.serializers import SemesterSerializer
from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.scopes import visible_teams_for
from user_management.academic_records.models import StudentAcademicRecord
from user_management.academic_records.serializers import StudentOptionSerializer
from user_management.permissions import IsSystemAdmin, CanManageTeams
from .bulk_import import (
    format_bulk_import_errors,
    ADVISER_FILTER_ALL,
    build_team_payload_from_row,
    preview_bulk_teams,
    prepare_bulk_row,
    resolve_user_by_full_name,
    validate_bulk_team_row,
)
from .team_levels import levels_for_user, user_is_admin, user_is_pit_lead_only
from .term_scope import (
    apply_team_scope,
    get_active_semester,
    pit_lead_operating_mode,
    pit_roster_student_ids,
    term_scope_payload,
)
from .models import StudentTeam, TeamAdviserAssignment, TeamMembership, SectionAssignment
from .serializers import (
    AdviserOptionSerializer,
    BulkTeamRowSerializer,
    StudentTeamSerializer,
    StudentTeamWriteSerializer,
    TeamAdviserAssignmentSerializer,
    SectionAssignmentSerializer,
)


User = get_user_model()


def team_audit_values(team, **extra):
    scope = 'pit' if team.is_pit else 'capstone' if team.is_capstone else ''
    values = {
        **audit_scope_metadata(scope=scope, team=team),
        'level': team.level,
        'semester_id': team.semester_id,
    }
    values.update(extra)
    return values


def teams_queryset():
    return (
        StudentTeam.objects.select_related('semester', 'semester__school_year', 'leader', 'adviser')
        .prefetch_related('memberships', 'memberships__student')
    )


def teams_queryset_for_user(user):
    return visible_teams_for(user)


def user_can_see_full_team_directory(user):
    if not user or not user.is_authenticated:
        return False
    if user.is_superuser or getattr(user, 'role', None) == 'admin':
        return True
    if getattr(user, 'is_pit_lead', False):
        return True
    if getattr(user, 'is_uploader', False):
        return True
    return False


def active_semester():
    return get_active_semester()


def filter_students_for_pit_roster(students, active, *, pit_lead_year=None, user=None):
    if not active:
        return students.none()
    if user and user_is_pit_lead_only(user) and pit_lead_operating_mode(user, active=active) == 'audit':
        return students.none()

    pit_year = (pit_lead_year or '').strip() or None
    if user and user_is_pit_lead_only(user) and not pit_year:
        pit_year = (getattr(user, 'pit_lead_year', None) or '').strip() or None

    student_ids = pit_roster_student_ids(active, pit_lead_year=pit_year or '', historical=False)
    if not student_ids:
        return students.none()
    return students.filter(pk__in=student_ids)


def options_payload(team_id=None, team_level=None, user=None, include_roster_options=True):
    """
    Get options for team creation/editing.
    
    Args:
        team_id: If provided, includes current team members even if they're in this team
        team_level: If provided, filters students based on team level (PIT/Capstone)
        user: The requesting user (to auto-detect PIT Lead filtering)
        include_roster_options: When False, omits student/adviser pick lists (list API privacy).
    """
    active = active_semester()
    role_levels = levels_for_user(user) if user else [choice[0] for choice in StudentTeam.LEVEL_CHOICES]
    capstone_window = capstone_mode_payload(active)
    if not include_roster_options:
        return {
            'active_semester': SemesterSerializer(active).data if active else None,
            'students': [],
            'advisers': [],
            'levels': role_levels,
            'statuses': [choice[0] for choice in StudentTeam.STATUS_CHOICES],
            **capstone_window,
        }

    # Get all active students
    students = User.objects.filter(role='student', is_active=True).order_by('username')
    
    # Filter out students who are already in teams
    # But if editing a team, include students from the current team
    if team_id:
        # Get students who are NOT in any team OR are in the current team being edited
        students = students.filter(
            Q(team_memberships__isnull=True) | Q(team_memberships__team_id=team_id)
        ).distinct()
    else:
        # Creating new team - only show students not in any team
        students = students.filter(team_memberships__isnull=True)
    
    # Auto-detect PIT Lead and apply filtering
    is_pit_lead = user and getattr(user, 'is_pit_lead', False)
    is_admin = user and (getattr(user, 'role', None) == 'admin' or user.is_superuser)
    
    # If user is PIT Lead (and not admin), automatically filter for PIT students
    if is_pit_lead and not is_admin:
        team_level = 'PIT'  # Force PIT filtering for PIT Leads
    
    # Filter students based on team level (PIT restrictions via academic records)
    if team_level and 'PIT' in team_level.upper():
        pit_year = None
        if is_pit_lead and not is_admin:
            pit_year = (getattr(user, 'pit_lead_year', None) or '').strip() or None
        students = filter_students_for_pit_roster(
            students,
            active,
            pit_lead_year=pit_year,
            user=user,
        )
    
    advisers = User.objects.filter(
        role__in=['faculty', 'admin'],
        is_active=True,
        is_adviser=True,
    ).order_by('username')
    if not advisers.exists():
        advisers = User.objects.filter(
            role__in=['faculty', 'admin'],
            is_active=True,
        ).order_by('username')
    active = active_semester()
    
    payload = {
        'active_semester': SemesterSerializer(active).data if active else None,
        'students': StudentOptionSerializer(students, many=True).data,
        'advisers': AdviserOptionSerializer(advisers, many=True).data,
        'levels': role_levels,
        'statuses': [choice[0] for choice in StudentTeam.STATUS_CHOICES],
        **capstone_window,
    }
    if user:
        # term_scope_payload must not redefine active_semester (SemesterSerializer dict above).
        payload.update(term_scope_payload(user))
    return payload


def counts_payload(queryset=None, stats_base=None):
    base = stats_base if stats_base is not None else teams_queryset()
    current = queryset if queryset is not None else base
    return {
        'all': base.count(),
        'filtered': current.count(),
        'pending': current.filter(status=StudentTeam.STATUS_PENDING).count(),
        'approved': current.filter(status=StudentTeam.STATUS_APPROVED).count(),
        'failed': current.filter(status=StudentTeam.STATUS_FAILED).count(),
        'no_adviser': current.filter(
            adviser__isnull=True,
            level__icontains='Capstone',
        ).count(),
    }


class StudentTeamListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [CanManageTeams()]

    def _serialize_teams(self, queryset, user):
        return StudentTeamSerializer(
            queryset,
            many=True,
            context={'user': user},
        ).data

    def get(self, request):
        visible = teams_queryset_for_user(request.user)
        scope = request.query_params.get('scope', 'active').strip()
        queryset = apply_team_scope(visible, scope=scope, user=request.user)
        search = request.query_params.get('search', '').strip()
        level = request.query_params.get('level', '').strip()
        status_filter = request.query_params.get('status', '').strip()

        if search:
            queryset = queryset.filter(
                Q(name__icontains=search)
                | Q(project_title__icontains=search)
                | Q(leader__first_name__icontains=search)
                | Q(leader__last_name__icontains=search)
                | Q(leader__username__icontains=search)
                | Q(adviser__first_name__icontains=search)
                | Q(adviser__last_name__icontains=search)
                | Q(adviser__username__icontains=search)
            )
        if level == 'Capstone':
            queryset = queryset.filter(level__icontains='Capstone')
        elif level == 'PIT':
            queryset = queryset.filter(level__icontains='PIT')
        elif level:
            queryset = queryset.filter(level=level)
        if status_filter:
            queryset = queryset.filter(status=status_filter)

        # Get team_level from query params for filtering students
        team_level_filter = request.query_params.get('team_level', '').strip()
        full_dir = user_can_see_full_team_directory(request.user)

        stats_base = apply_team_scope(visible, scope='active', user=request.user)

        return Response({
            'teams': self._serialize_teams(queryset, request.user),
            'counts': counts_payload(queryset, stats_base=stats_base),
            **options_payload(
                team_level=team_level_filter if team_level_filter else None,
                user=request.user,
                include_roster_options=full_dir,
            ),
        })

    def post(self, request):
        serializer = StudentTeamWriteSerializer(
            data=request.data,
            context={'assigned_by': request.user, 'user': request.user},
        )
        serializer.is_valid(raise_exception=True)
        team = serializer.save()
        team = teams_queryset().get(pk=team.pk)

        return Response({
            'team': StudentTeamSerializer(team, context={'user': request.user}).data,
            'counts': counts_payload(),
        }, status=status.HTTP_201_CREATED)


class StudentTeamDetailView(APIView):
    permission_classes = [CanManageTeams]

    def get_object(self, team_id):
        return get_object_or_404(teams_queryset_for_user(self.request.user), pk=team_id)

    def get(self, request, team_id):
        """Get team details with available students for editing"""
        team = self.get_object(team_id)
        return Response({
            'team': StudentTeamSerializer(team, context={'user': request.user}).data,
            **options_payload(team_id=team_id, team_level=team.level, user=request.user),
        })

    def patch(self, request, team_id):
        team = self.get_object(team_id)
        old_adviser_id = team.adviser_id
        serializer = StudentTeamWriteSerializer(
            team,
            data=request.data,
            context={'team_id': team.id, 'assigned_by': request.user, 'user': request.user},
        )
        serializer.is_valid(raise_exception=True)
        team = serializer.save()
        if old_adviser_id != team.adviser_id:
            log_high_impact_action(
                category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
                action='team.adviser_change',
                target=team,
                old_values=team_audit_values(team, adviser_id=old_adviser_id),
                new_values=team_audit_values(team, adviser_id=team.adviser_id),
                reason=request.data.get('adviser_change_reason', ''),
                request=request,
            )
        team = teams_queryset().get(pk=team.pk)

        return Response({
            'team': StudentTeamSerializer(team, context={'user': request.user}).data,
            'counts': counts_payload(),
        })

    def delete(self, request, team_id):
        team = self.get_object(team_id)
        from .term_scope import assert_team_writable
        from defense.scheduler.models import DefenseSchedule
        from grading.grades.models import TeamGrade

        assert_team_writable(request.user, team)

        has_schedules = DefenseSchedule.objects.filter(team=team).exists()
        has_grades = TeamGrade.objects.filter(team=team).exists()
        if has_schedules or has_grades:
            return Response(
                {
                    'warning': (
                        'This team has defense schedules or grade records. '
                        'Deleting it will permanently remove all grades, '
                        'panelist scores, and peer evaluations. '
                        'Consider changing the team status instead.'
                    ),
                },
                status=status.HTTP_409_CONFLICT,
            )

        member_ids = list(team.memberships.values_list('student_id', flat=True))
        audit_values = team_audit_values(
            team,
            name=team.name,
            adviser_id=team.adviser_id,
            member_ids=member_ids,
            status=team.status,
        )
        team_pk = team.pk
        team.delete()
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
            action='team.delete',
            target=team,
            target_type='StudentTeam',
            target_id=team_pk,
            old_values=audit_values,
            new_values={'deleted': True},
            request=request,
        )
        User.objects.filter(pk__in=member_ids, team_id=str(team_id)).update(team_id=None)
        return Response({'counts': counts_payload()}, status=status.HTTP_200_OK)



class TeamAdviserHistoryView(APIView):
    permission_classes = [CanManageTeams]

    def get(self, request, team_id):
        team = get_object_or_404(visible_teams_for(request.user), pk=team_id)
        assignments = (
            TeamAdviserAssignment.objects.filter(team=team)
            .select_related('adviser', 'assigned_by', 'team', 'team__semester')
            .order_by('-assigned_at', '-id')
        )
        return Response({
            'assignments': TeamAdviserAssignmentSerializer(assignments, many=True).data,
        })


def _normalize_adviser_filter(raw):
    value = (raw or ADVISER_FILTER_ALL).strip().lower()
    if value in ('with_adviser', 'without_adviser', 'all'):
        return value
    return ADVISER_FILTER_ALL


def _reject_capstone_bulk_import_if_closed(user, *, section=''):
    from .team_levels import user_is_admin

    if (section or '').strip():
        return None
    if not user_is_admin(user):
        return None
    active = active_semester()
    try:
        assert_capstone_team_creation_allowed(active)
    except ValueError as exc:
        return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
    return None


class BulkImportTeamsPreviewView(APIView):
    permission_classes = [CanManageTeams]

    def post(self, request):
        section = request.data.get('section', '').strip()
        blocked = _reject_capstone_bulk_import_if_closed(request.user, section=section)
        if blocked is not None:
            return blocked

        rows = request.data.get('teams', [])
        if not isinstance(rows, list):
            return Response({'detail': 'teams must be a list.'}, status=status.HTTP_400_BAD_REQUEST)

        adviser_filter = _normalize_adviser_filter(request.data.get('adviser_filter'))
        csv_columns = request.data.get('csv_columns')
        if csv_columns is not None and not isinstance(csv_columns, list):
            csv_columns = None
        preview_rows, summary = preview_bulk_teams(
            rows,
            adviser_filter=adviser_filter,
            user=request.user,
            csv_columns=csv_columns,
            section_import=bool(section),
            import_section=section,
        )

        system_name = request.data.get('system_name', '').strip()
        pm_name = request.data.get('project_manager', '').strip()
        section_assignment = None

        if section:
            pm_user = None
            pm_error = None
            if pm_name:
                pm_user, pm_error = resolve_user_by_full_name(pm_name, role='student', field_label='Project Manager')
            section_assignment = {
                'section': section,
                'system_name': system_name,
                'project_manager_name': pm_name,
                'project_manager_valid': pm_user is not None if pm_name else True,
                'project_manager_error': pm_error,
            }

        return Response({
            'rows': preview_rows,
            'summary': summary,
            'adviser_filter': adviser_filter,
            'section_assignment': section_assignment,
        })


class BulkImportTeamsView(APIView):
    permission_classes = [CanManageTeams]

    def post(self, request):
        section = request.data.get('section', '').strip()
        blocked = _reject_capstone_bulk_import_if_closed(request.user, section=section)
        if blocked is not None:
            return blocked

        rows = request.data.get('teams', [])
        if not isinstance(rows, list):
            return Response({'detail': 'teams must be a list.'}, status=status.HTTP_400_BAD_REQUEST)

        system_name = request.data.get('system_name', '').strip()
        pm_name = request.data.get('project_manager', '').strip()

        if section:
            pm_user = None
            if pm_name:
                pm_user, pm_error = resolve_user_by_full_name(pm_name, role='student', field_label='Project Manager')
                if pm_error:
                    return Response({'detail': pm_error}, status=status.HTTP_400_BAD_REQUEST)
            
            active = active_semester()
            if not active:
                return Response({'detail': 'No active semester is configured.'}, status=status.HTTP_400_BAD_REQUEST)
            
            year_level = (getattr(request.user, 'pit_lead_year', None) or '2nd Year').strip() or '2nd Year'
            SectionAssignment.objects.update_or_create(
                section=section,
                semester=active,
                defaults={
                    'system_name': system_name,
                    'project_manager': pm_user,
                    'year_level': year_level,
                }
            )

        adviser_filter = _normalize_adviser_filter(request.data.get('adviser_filter'))
        csv_columns = request.data.get('csv_columns')
        if csv_columns is not None and not isinstance(csv_columns, list):
            csv_columns = None
        created = []
        skipped = []
        errors = []
        imported_rows = []

        for index, row in enumerate(rows, start=1):
            team_name = (row.get('team_name') or '').strip()
            prepared, prep_issues = prepare_bulk_row(
                row,
                request.user,
                check_template=True,
                csv_columns=csv_columns,
                section_import=bool(section),
                import_section=section,
            )
            if prep_issues:
                errors.append({
                    'row': index,
                    'sheet_row': index + 1,
                    'team_name': team_name,
                    'errors': prep_issues,
                })
                continue

            row_serializer = BulkTeamRowSerializer(
                data=prepared,
                context={
                    'user': request.user,
                    'section_import': bool(section),
                    'import_section': section,
                },
            )
            if not row_serializer.is_valid():
                errors.append({
                    'row': index,
                    'sheet_row': index + 1,
                    'team_name': team_name,
                    'errors': format_bulk_import_errors(row_serializer.errors),
                })
                continue

            result = validate_bulk_team_row(
                row_serializer.validated_data,
                adviser_filter=adviser_filter,
                user=request.user,
                csv_columns=csv_columns,
                section_import=bool(section),
                import_section=section,
            )
            team_name = result['team_name']
            if not result['ready']:
                if result['issues']:
                    errors.append({
                        'row': index,
                        'sheet_row': index + 1,
                        'team_name': team_name,
                        'errors': result['issues'],
                    })
                else:
                    skipped.append({
                        'row': index,
                        'sheet_row': index + 1,
                        'team_name': team_name,
                        'reason': 'filtered_by_adviser',
                    })
                continue

            payload = build_team_payload_from_row(result, user=request.user)
            serializer = StudentTeamWriteSerializer(
                data=payload,
                context={
                    'assigned_by': request.user,
                    'user': request.user,
                    'section_import': bool(section),
                    'import_section': section,
                },
            )
            if not serializer.is_valid():
                errors.append({
                    'row': index,
                    'sheet_row': index + 1,
                    'team_name': team_name,
                    'errors': format_bulk_import_errors(serializer.errors),
                })
                continue

            created.append(serializer.save())
            imported_rows.append(index)

        return Response({
            'created': StudentTeamSerializer(created, many=True).data,
            'created_count': len(created),
            'imported_rows': imported_rows,
            'skipped': skipped,
            'skipped_count': len(skipped),
            'errors': errors,
            'error_count': len(errors),
            'counts': counts_payload(),
            'adviser_filter': adviser_filter,
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)


class SectionAssignmentListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [CanManageTeams()]

    def get(self, request):
        active = active_semester()
        if not active:
            return Response([])
        queryset = SectionAssignment.objects.filter(semester=active)
        serializer = SectionAssignmentSerializer(queryset, many=True)
        return Response(serializer.data)

    def post(self, request):
        active = active_semester()
        if not active:
            return Response({'detail': 'No active semester is configured.'}, status=status.HTTP_400_BAD_REQUEST)

        section = request.data.get('section', '').strip()
        year_level = request.data.get('year_level', '').strip()
        system_name = request.data.get('system_name', '').strip()
        pm_id = request.data.get('project_manager_id')

        if not section:
            return Response({'section': 'Section is required.'}, status=status.HTTP_400_BAD_REQUEST)
        if not year_level:
            return Response({'year_level': 'Year level is required.'}, status=status.HTTP_400_BAD_REQUEST)

        pm = None
        if pm_id:
            pm = get_object_or_404(User, pk=pm_id, role='student')

        assignment, created = SectionAssignment.objects.update_or_create(
            section=section,
            semester=active,
            defaults={
                'year_level': year_level,
                'system_name': system_name,
                'project_manager': pm,
            }
        )
        return Response(SectionAssignmentSerializer(assignment).data, status=status.HTTP_201_CREATED)


class SectionAssignmentDetailView(APIView):
    permission_classes = [CanManageTeams]

    def get_object(self, pk):
        return get_object_or_404(SectionAssignment, pk=pk)

    def get(self, request, pk):
        assignment = self.get_object(pk)
        return Response(SectionAssignmentSerializer(assignment).data)

    def patch(self, request, pk):
        assignment = self.get_object(pk)
        data = request.data
        if 'year_level' in data:
            assignment.year_level = data['year_level']
        if 'system_name' in data:
            assignment.system_name = data['system_name']
        if 'project_manager_id' in data:
            pm_id = data['project_manager_id']
            if pm_id:
                assignment.project_manager = get_object_or_404(User, pk=pm_id, role='student')
            else:
                assignment.project_manager = None
        assignment.save()
        return Response(SectionAssignmentSerializer(assignment).data)

    def delete(self, request, pk):
        assignment = self.get_object(pk)
        assignment.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

