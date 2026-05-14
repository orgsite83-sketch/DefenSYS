from django.contrib.auth import get_user_model
from django.db.models import Q
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.models import Semester
from academic_period_management.serializers import SemesterSerializer
from student_academic_records.serializers import StudentOptionSerializer
from user_management.permissions import IsSystemAdmin, CanManageTeams
from .models import StudentTeam
from .serializers import AdviserOptionSerializer, BulkTeamRowSerializer, StudentTeamSerializer, StudentTeamWriteSerializer


User = get_user_model()


def teams_queryset():
    return (
        StudentTeam.objects.select_related('semester', 'semester__school_year', 'leader', 'adviser')
        .prefetch_related('memberships', 'memberships__student')
    )


def teams_queryset_for_user(user):
    base = teams_queryset()
    if not user or not user.is_authenticated:
        return base.none()
    if user.is_superuser or getattr(user, 'role', None) == 'admin':
        return base
    if getattr(user, 'is_pit_lead', False):
        return base
    if getattr(user, 'is_uploader', False):
        return base
    if getattr(user, 'role', None) == 'faculty':
        return base.filter(adviser=user)
    if getattr(user, 'role', None) == 'student':
        return base.filter(Q(leader=user) | Q(memberships__student=user)).distinct()
    return base.none()


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
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


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
    if not include_roster_options:
        return {
            'active_semester': SemesterSerializer(active).data if active else None,
            'students': [],
            'advisers': [],
            'levels': [choice[0] for choice in StudentTeam.LEVEL_CHOICES],
            'statuses': [choice[0] for choice in StudentTeam.STATUS_CHOICES],
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
    
    # Filter students based on team level (PIT restrictions)
    if team_level and 'PIT' in team_level.upper():
        # PIT teams can only have 1st, 2nd, and 3rd year students
        # But 3rd year students are only available in 1st semester
        active = active_semester()
        
        if active and active.label == Semester.SECOND:
            # 2nd Semester: Only 1st and 2nd year students (3rd year doing Capstone)
            # Filter by username pattern: student1-20 (1st and 2nd year)
            students = students.filter(
                Q(username__regex=r'^student([1-9]|1[0-9]|20)$')  # student1-20
            )
        else:
            # 1st Semester: 1st, 2nd, and 3rd year students
            # Filter by username pattern: student1-30 (1st, 2nd, and 3rd year)
            students = students.filter(
                Q(username__regex=r'^student([1-9]|[12][0-9]|30)$')  # student1-30
            )
    
    advisers = User.objects.filter(role__in=['faculty', 'admin'], is_active=True).order_by('username')
    active = active_semester()
    
    return {
        'active_semester': SemesterSerializer(active).data if active else None,
        'students': StudentOptionSerializer(students, many=True).data,
        'advisers': AdviserOptionSerializer(advisers, many=True).data,
        'levels': [choice[0] for choice in StudentTeam.LEVEL_CHOICES],
        'statuses': [choice[0] for choice in StudentTeam.STATUS_CHOICES],
    }


def counts_payload(queryset=None, stats_base=None):
    base = stats_base if stats_base is not None else teams_queryset()
    current = queryset if queryset is not None else base
    return {
        'all': base.count(),
        'filtered': current.count(),
        'pending': current.filter(status=StudentTeam.STATUS_PENDING).count(),
        'approved': current.filter(status=StudentTeam.STATUS_APPROVED).count(),
        'failed': current.filter(status=StudentTeam.STATUS_FAILED).count(),
        'no_adviser': current.filter(adviser__isnull=True).count(),
    }


class StudentTeamListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [IsAuthenticated()]
        return [CanManageTeams()]

    def get(self, request):
        visible = teams_queryset_for_user(request.user)
        queryset = visible
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
        elif level:
            queryset = queryset.filter(level=level)
        if status_filter:
            queryset = queryset.filter(status=status_filter)

        # Get team_level from query params for filtering students
        team_level_filter = request.query_params.get('team_level', '').strip()
        full_dir = user_can_see_full_team_directory(request.user)

        return Response({
            'teams': StudentTeamSerializer(queryset, many=True).data,
            'counts': counts_payload(queryset, stats_base=visible),
            **options_payload(
                team_level=team_level_filter if team_level_filter else None,
                user=request.user,
                include_roster_options=full_dir,
            ),
        })

    def post(self, request):
        serializer = StudentTeamWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        team = serializer.save()
        team = teams_queryset().get(pk=team.pk)

        return Response({
            'team': StudentTeamSerializer(team).data,
            'counts': counts_payload(),
        }, status=status.HTTP_201_CREATED)


class StudentTeamDetailView(APIView):
    permission_classes = [CanManageTeams]

    def get_object(self, team_id):
        return get_object_or_404(teams_queryset(), pk=team_id)

    def get(self, request, team_id):
        """Get team details with available students for editing"""
        team = self.get_object(team_id)
        return Response({
            'team': StudentTeamSerializer(team).data,
            **options_payload(team_id=team_id, team_level=team.level, user=request.user),  # Pass team level for filtering
        })

    def patch(self, request, team_id):
        team = self.get_object(team_id)
        serializer = StudentTeamWriteSerializer(
            team,
            data=request.data,
            context={'team_id': team.id},
        )
        serializer.is_valid(raise_exception=True)
        team = serializer.save()
        team = teams_queryset().get(pk=team.pk)

        return Response({
            'team': StudentTeamSerializer(team).data,
            'counts': counts_payload(),
        })

    def delete(self, request, team_id):
        team = self.get_object(team_id)
        member_ids = list(team.memberships.values_list('student_id', flat=True))
        team.delete()
        User.objects.filter(pk__in=member_ids, team_id=str(team_id)).update(team_id=None)
        return Response({'counts': counts_payload()}, status=status.HTTP_200_OK)


class BulkImportTeamsView(APIView):
    permission_classes = [CanManageTeams]

    def post(self, request):
        rows = request.data.get('teams', [])
        if not isinstance(rows, list):
            return Response({'detail': 'teams must be a list.'}, status=status.HTTP_400_BAD_REQUEST)

        created = []
        skipped = []
        errors = []

        for index, row in enumerate(rows, start=1):
            row_serializer = BulkTeamRowSerializer(data=row)
            if not row_serializer.is_valid():
                errors.append({'row': index, 'errors': row_serializer.errors})
                continue

            data = row_serializer.validated_data
            member_users = User.objects.filter(username__in=data['member_ids'], role='student')
            member_id_map = {user.username: user.id for user in member_users}
            leader = User.objects.filter(username=data['leader_id'], role='student').first()
            adviser = None
            if data.get('adviser_id'):
                adviser = User.objects.filter(username=data['adviser_id'], role__in=['faculty', 'admin']).first()

            payload = {
                'name': data['team_name'],
                'project_title': data.get('project_title') or data['team_name'],
                'level': data['level'],
                'year_level': data.get('year_level') or '',
                'member_ids': [member_id_map[item] for item in data['member_ids'] if item in member_id_map],
                'leader_id': leader.id if leader else None,
                'adviser_id': adviser.id if adviser else None,
            }

            serializer = StudentTeamWriteSerializer(data=payload)
            if not serializer.is_valid():
                errors.append({'row': index, 'errors': serializer.errors})
                continue

            created.append(serializer.save())

        return Response({
            'created': StudentTeamSerializer(created, many=True).data,
            'created_count': len(created),
            'skipped': skipped,
            'skipped_count': len(skipped),
            'errors': errors,
            'error_count': len(errors),
            'counts': counts_payload(),
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
