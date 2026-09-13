from django.db.models import Q
from django.core.exceptions import ValidationError
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.serializers import SemesterSerializer
from .serializers import (
    DeliverableActionSerializer,
    DeliverableUploadSerializer,
    DeliverableReviewSerializer,
)
from .services import (
    STAGE_OPTIONS,
    active_semester,
    counts_payload,
    endorse_team,
    unendorse_team,
    filter_teams,
    remove_submission,
    team_payload,
    team_queryset_for_user,
    upsert_submission,
)


class CanManageDeliverables(BasePermission):
    message = 'Only administrators, assigned advisers, PIT leads, Section instructors, and team members can manage deliverables.'

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False):
            return True
        if getattr(user, 'role', None) == 'student':
            return True
        if getattr(user, 'role', None) == 'faculty':
            if getattr(user, 'is_adviser', False) or getattr(user, 'is_pit_lead', False):
                return True
            from user_management.models import SectionInstructorAssignment
            return SectionInstructorAssignment.objects.filter(faculty=user, is_active=True).exists()
        return False


def check_deliverable_write_permission(user, team):
    # Admins and superusers can always manage
    if getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False):
        return True
    
    # Team members (students) can upload/manage their own deliverables
    if getattr(user, 'role', None) == 'student':
        if team.memberships.filter(student=user).exists():
            return True
        return False
        
    if getattr(user, 'role', None) == 'faculty':
        # Advisers can manage deliverables for teams they advise
        if getattr(user, 'is_adviser', False) and team.adviser == user:
            return True
            
        # PIT Leads can manage deliverables for PIT teams in their year
        if getattr(user, 'is_pit_lead', False) and team.is_pit:
            from student_teams.team_levels import normalize_year_level
            pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
            if not pit_year or normalize_year_level(team.year_level) == normalize_year_level(pit_year):
                return True
                
        # Section Instructors can manage deliverables for PIT teams in their section
        if team.is_pit:
            from user_management.models import SectionInstructorAssignment
            from student_teams.team_levels import normalize_year_level
            team_year = normalize_year_level(team.year_level)
            sec = (team.section or '').strip()
            if SectionInstructorAssignment.objects.filter(
                Q(section='') | Q(section__isnull=True) | Q(section__iexact=sec),
                faculty=user,
                semester=team.semester,
                year_level=team_year,
                is_active=True
            ).exists():
                return True
                
    return False


def deliverables_payload(request, queryset=None, selected_stage=None, scope=None):
    if scope is None:
        scope = request.query_params.get('scope', 'capstone')

    base = team_queryset_for_user(request.user)
    if scope == 'pit':
        base = base.filter(level__icontains='PIT')
    else:
        base = base.exclude(level__icontains='PIT')

    current = queryset if queryset is not None else base
    if queryset is not None:
        if scope == 'pit':
            current = current.filter(level__icontains='PIT')
        else:
            current = current.exclude(level__icontains='PIT')

    team_id = request.query_params.get('team_id', '').strip()
    if team_id:
        current = current.filter(id=team_id)

    semester = active_semester()
    if scope == 'pit':
        from defense.scheduler.models import PitEventGradingConfig
        from authentication_access_control.scopes import is_pit_lead_only, _pit_year
        pit_lead = is_pit_lead_only(request.user)
        pit_year = _pit_year(request.user) if pit_lead else None
        requested_year = (request.query_params.get('year_level') or pit_year or '').strip()

        if not requested_year and current.exists():
            team_years = set(current.values_list('year_level', flat=True))
            if len(team_years) == 1:
                requested_year = list(team_years)[0]
            elif getattr(request.user, 'role', None) == 'student':
                requested_year = current.first().year_level or ''

        configs_qs = PitEventGradingConfig.objects.filter(semester=semester)
        if requested_year:
            from repository.project_archive.services import PIT_YEAR_EVENT_HINTS
            exclude_filter = Q()
            for y, hints in PIT_YEAR_EVENT_HINTS.items():
                if y != requested_year:
                    for hint in hints:
                        exclude_filter |= Q(event_name__icontains=hint)
            if exclude_filter:
                configs_qs = configs_qs.exclude(exclude_filter)

        stage_options = list(
            configs_qs.order_by('event_name')
            .values_list('event_name', flat=True)
        )
    else:
        stage_options = list(STAGE_OPTIONS)

    requested_stage = selected_stage or request.query_params.get('stage_label') or ''
    if not requested_stage and current.exists():
        from .services import current_stage_for_team
        default_team_stage = current_stage_for_team(current.first())
        if default_team_stage and default_team_stage in stage_options:
            requested_stage = default_team_stage

    stage = (
        requested_stage
        if requested_stage in stage_options
        else (stage_options[0] if stage_options else '')
    )
    return {
        'teams': [team_payload(team, selected_stage=stage) for team in current],
        'counts': counts_payload(current, selected_stage=stage),
        'stage_options': stage_options,
        'selected_stage': stage,
        'scope': scope,
        'statuses': [
            {'value': '', 'label': 'All Teams'},
            {'value': 'ready', 'label': 'Ready / Endorsed'},
            {'value': 'pending_review', 'label': 'Pending Review'},
            {'value': 'missing', 'label': 'Missing Requirements'},
        ],
        'active_semester': SemesterSerializer(semester).data if semester else None,
    }


def get_allowed_team(request, team_id):
    return get_object_or_404(team_queryset_for_user(request.user), pk=team_id)


def deliverable_error_response(exc):
    """Map service/model errors to JSON API responses."""
    if hasattr(exc, 'message_dict'):
        return Response(exc.message_dict, status=status.HTTP_400_BAD_REQUEST)
    return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)


class CapstoneDeliverablesListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = filter_teams(request, team_queryset_for_user(request.user))
        return Response(deliverables_payload(request, queryset))


class CapstoneDeliverableUploadView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        serializer = DeliverableUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = serializer.validated_data
        team = get_allowed_team(request, attrs['team_id'])
        
        if not check_deliverable_write_permission(request.user, team):
            return Response({'detail': 'You do not have permission to manage deliverables for this team.'}, status=status.HTTP_403_FORBIDDEN)
        
        # Get uploaded file from request
        uploaded_file = request.FILES.get('file')
        
        try:
            submission = upsert_submission(
                team=team,
                stage_label=attrs['stage_label'],
                deliverable_id=attrs['deliverable_id'],
                file_name=attrs['file_name'],
                file_size=attrs.get('file_size', ''),
                user=request.user,
                file=uploaded_file,  # Pass the actual file
                file_id=attrs.get('file_id'),  # Pass file_id
            )
        except (PermissionError, ValueError, ValidationError) as exc:
            return deliverable_error_response(exc)
        return Response(
            {
                'submission_id': submission.id,
                **deliverables_payload(request, scope='pit' if team.is_pit else 'capstone'),
            },
            status=status.HTTP_200_OK,
        )


class CapstoneDeliverableRemoveView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        serializer = DeliverableActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = serializer.validated_data
        if not attrs.get('deliverable_id'):
            return Response({'deliverable_id': 'This field is required.'}, status=status.HTTP_400_BAD_REQUEST)
        team = get_allowed_team(request, attrs['team_id'])
        
        if not check_deliverable_write_permission(request.user, team):
            return Response({'detail': 'You do not have permission to manage deliverables for this team.'}, status=status.HTTP_403_FORBIDDEN)
            
        remove_submission(team, attrs['stage_label'], attrs['deliverable_id'], file_id=attrs.get('file_id'))
        return Response(deliverables_payload(request, scope='pit' if team.is_pit else 'capstone'), status=status.HTTP_200_OK)


class CapstoneDeliverableEndorseView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        if getattr(request.user, 'role', None) == 'student':
            return Response({'detail': 'Students cannot endorse deliverables.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = DeliverableActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = serializer.validated_data
        team = get_allowed_team(request, attrs['team_id'])
        
        if not check_deliverable_write_permission(request.user, team):
            return Response({'detail': 'You do not have permission to endorse deliverables for this team.'}, status=status.HTTP_403_FORBIDDEN)
            
        try:
            endorse_team(team, attrs['stage_label'])
        except ValueError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(deliverables_payload(request, scope='pit' if team.is_pit else 'capstone'), status=status.HTTP_200_OK)


class CapstoneDeliverableUnendorseView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        if getattr(request.user, 'role', None) == 'student':
            return Response({'detail': 'Students cannot cancel endorsement.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = DeliverableActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = serializer.validated_data
        team = get_allowed_team(request, attrs['team_id'])
        
        if not check_deliverable_write_permission(request.user, team):
            return Response({'detail': 'You do not have permission to modify endorsement for this team.'}, status=status.HTTP_403_FORBIDDEN)
            
        try:
            unendorse_team(team, attrs['stage_label'])
        except ValueError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(deliverables_payload(request, scope='pit' if team.is_pit else 'capstone'), status=status.HTTP_200_OK)


class CompileWeeklyReportsView(APIView):
    """Generate PDF compilation of weekly progress reports"""
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        from student_teams.models import StudentTeam
        from .models import DeliverableSubmission
        from .pdf_generator import generate_weekly_reports_pdf
        
        team_id = request.data.get('team_id')
        stage_label = request.data.get('stage_label')
        
        if not team_id or not stage_label:
            return Response(
                {'error': 'team_id and stage_label are required.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            # Get team
            team = StudentTeam.objects.get(id=team_id)
            
            # Import WeeklyProgressReport model
            try:
                from student_teams.weekly_progress.models import WeeklyProgressReport
            except ImportError:
                return Response(
                    {'error': 'Weekly progress module not found.'},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR
                )
            
            # Get all weekly reports for this team
            reports = WeeklyProgressReport.objects.filter(
                team=team
            ).order_by('week_number')
            
            if not reports.exists():
                return Response(
                    {'error': 'No weekly progress reports found for this team.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            # Generate PDF
            pdf_content = generate_weekly_reports_pdf(team, reports)
            
            # Save as deliverable
            file_name = f'{team.name.replace(" ", "_")}_WeeklyReports_Compiled.pdf'
            file_size = f'{len(pdf_content) / 1024:.2f} KB'
            
            submission, created = DeliverableSubmission.objects.update_or_create(
                team=team,
                stage_label=stage_label,
                deliverable_id='WPR',
                defaults={
                    'label': 'Weekly Progress Report',
                    'deliverable_type': DeliverableSubmission.TYPE_PRE,
                    'required': True,
                    'file_name': file_name,
                    'file_size': file_size,
                    'uploaded_by': request.user,
                }
            )
            
            # Optionally save PDF file to storage
            # from django.core.files.base import ContentFile
            # submission.file.save(file_name, ContentFile(pdf_content))
            
            return Response({
                'success': True,
                'file_name': file_name,
                'file_size': file_size,
                'report_count': reports.count(),
                'created': created,
            }, status=status.HTTP_200_OK)
            
        except StudentTeam.DoesNotExist:
            return Response(
                {'error': 'Team not found.'},
                status=status.HTTP_404_NOT_FOUND
            )
        except Exception as e:
            return Response(
                {'error': str(e)},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class CapstoneDeliverableReviewView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        serializer = DeliverableReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = serializer.validated_data
        team = get_allowed_team(request, attrs['team_id'])

        try:
            from .services import review_submission
            review_submission(
                team=team,
                stage_label=attrs['stage_label'],
                deliverable_id=attrs['deliverable_id'],
                status_val=attrs['status'],
                feedback_val=attrs.get('feedback', ''),
                reviewer_user=request.user,
            )
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)
        except (ValueError, ValidationError) as exc:
            msg = str(exc)
            if hasattr(exc, 'message_dict'):
                msg = str(exc.message_dict)
            elif hasattr(exc, 'messages'):
                msg = ", ".join(exc.messages)
            return Response({'detail': msg}, status=status.HTTP_400_BAD_REQUEST)

        return Response(
            deliverables_payload(request, scope='pit' if team.is_pit else 'capstone'),
            status=status.HTTP_200_OK
        )


class CapstoneDeliverableUnlockView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        stage_label = request.data.get('stage_label')
        unlock_type = request.data.get('unlock_type', 'all')
        scope = request.data.get('scope', 'team')
        team_id = request.data.get('team_id')
        year_level = request.data.get('year_level')
        target_state = request.data.get('target_state')

        if not stage_label:
            return Response({'detail': 'stage_label is required.'}, status=status.HTTP_400_BAD_REQUEST)

        from .services import toggle_stage_deliverables_unlock, toggle_global_stage_deliverables_unlock
        try:
            if scope == 'global':
                target_program_scope = request.data.get('program_scope', 'capstone')
                unlocked = toggle_global_stage_deliverables_unlock(
                    stage_label=stage_label,
                    user=user,
                    scope=target_program_scope,
                    year_level=year_level,
                    unlock_type=unlock_type,
                    target_state=target_state,
                )
                payload_scope = target_program_scope
            else:
                if not team_id:
                    return Response({'detail': 'team_id is required for team scope unlock.'}, status=status.HTTP_400_BAD_REQUEST)
                team = get_allowed_team(request, team_id)
                unlocked = toggle_stage_deliverables_unlock(
                    team=team,
                    stage_label=stage_label,
                    user=user,
                    unlock_type=unlock_type,
                    target_state=target_state,
                )
                payload_scope = 'pit' if team.is_pit else 'capstone'

        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)

        return Response({
            'unlocked': unlocked,
            **deliverables_payload(request, scope=payload_scope),
        }, status=status.HTTP_200_OK)

