from authentication_access_control.scopes import is_admin_user, is_pit_lead_only
from authentication_access_control.workspace_roles import is_institutional_staff
from django.db.models import Q
from django.core.exceptions import ValidationError
from django.shortcuts import get_object_or_404
from django.http import Http404
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from defensys_backend.read_projection import ReadAPIView as APIView, read_projection

from academic_period_management.serializers import SemesterSerializer
from .batches import batch_options
from .serializers import (
    DeliverableActionSerializer,
    DeliverableUploadSerializer,
    DeliverableReviewSerializer,
    ReviewEndorseSerializer,
    StageAccessScopeSerializer,
    StageAccessChangeSerializer,
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
    can_submit_files,
)


class CanManageDeliverables(BasePermission):
    message = 'Only administrators, assigned advisers, PIT leads, Section instructors, and team members can manage deliverables.'

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if is_admin_user(user):
            return True
        if getattr(user, 'role', None) == 'student':
            return True
        if is_institutional_staff(user):
            if getattr(user, 'is_adviser', False) or getattr(user, 'is_pit_lead', False):
                return True
            from user_management.models import SectionInstructorAssignment
            if SectionInstructorAssignment.objects.filter(faculty=user, is_active=True).exists():
                return True
            from defense.scheduler.models import SchedulePanelist
            return SchedulePanelist.objects.filter(panelist=user, is_chair=True).exists()
        return False


def check_deliverable_write_permission(user, team):
    # Admins and superusers can always manage
    if is_admin_user(user):
        return True
    
    # Team members (students) can upload/manage their own deliverables
    if getattr(user, 'role', None) == 'student':
        if team.memberships.filter(student=user).exists():
            return True
        return False
        
    if is_institutional_staff(user):
        # Advisers can manage deliverables for teams they advise
        if getattr(user, 'is_adviser', False) and team.adviser == user:
            return True
            
        # PIT Leads can manage deliverables for PIT teams in their year
        if getattr(user, 'is_pit_lead', False) and team.is_pit:
            from student_teams.team_levels import normalize_year_level
            pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
            if pit_year and normalize_year_level(team.year_level) == normalize_year_level(pit_year):
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


def workspace_deliverable_teams(request):
    from student_teams.capstone_workspace import enabled, projection
    if request.method == 'GET' and enabled(request):
        return projection(request)['teams']
    base = team_queryset_for_user(request.user)
    workspace = request.query_params.get('workspace', '').strip()
    if workspace:
        from authentication_access_control.workspaces import workspace_teams_for
        base = base.filter(pk__in=workspace_teams_for(request.user, workspace).values('pk'))
    return base


def deliverables_payload(request, queryset=None, selected_stage=None, scope=None):
    if scope is None:
        scope = request.query_params.get('scope', 'capstone')

    base = workspace_deliverable_teams(request)
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
    from student_teams.capstone_workspace import enabled, projection
    phase_view = projection(request) if enabled(request) else None
    if phase_view:
        semester = phase_view['semester']
    if scope == 'pit':
        from defense.scheduler.models import PitEventGradingConfig
        from authentication_access_control.scopes import is_pit_lead_only, _pit_year
        pit_lead = is_pit_lead_only(request.user) and request.query_params.get('workspace', '') in ('', 'operations', 'pit_lead')
        pit_year = _pit_year(request.user) if pit_lead else None
        requested_year = (request.query_params.get('year_level') or pit_year or '').strip()

        if not requested_year and current.exists():
            team_years = set(current.values_list('year_level', flat=True))
            if len(team_years) == 1:
                requested_year = list(team_years)[0]
            elif getattr(request.user, 'role', None) == 'student':
                requested_year = current.first().year_level or ''

        from defense.scheduler.event_scope import pit_events_for_user
        configs_qs = pit_events_for_user(request.user, semester=semester,
            workspace=request.query_params.get('workspace')) if semester else PitEventGradingConfig.objects.none()
        if requested_year:
            configs_qs = configs_qs.filter(year_level=requested_year)

        stage_options = list(
            configs_qs.order_by('event_name')
            .values_list('event_name', flat=True)
        )
    else:
        from student_teams.capstone_context import phase_requirements
        from student_teams.capstone_lifecycle import requirements_for
        visible_requirements = requirements_for if request.user.role == 'student' else phase_requirements
        stage_options = list(dict.fromkeys(r['label'] for team in current
            for r in visible_requirements(phase_view['contexts'][team.pk] if phase_view else team)))

    requested_stage = selected_stage or request.query_params.get('stage_label') or ''
    if phase_view and request.query_params.get('stage_sequence') == 'all':
        requested_stage = phase_view['metadata']['selected_stage_label']
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
    if scope == 'pit' and stage:
        from student_teams.pit_rosters import filter_teams as roster_teams
        current = roster_teams(current, stage)
    teams = [team_payload(phase_view['contexts'][team.pk] if phase_view else team,
        selected_stage=stage, evaluator=request.user) for team in current]
    return {
        **({'capstone_workspace': phase_view['metadata']} if phase_view else {}),
        'teams': teams,
        'batch_options': batch_options(base) if scope != 'pit' else [],
        'counts': counts_payload(current, selected_stage=stage, serialized_teams=teams),
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
    from student_teams.capstone_workspace import enabled, projection
    if request.method != 'GET' and enabled(request):
        from rest_framework.exceptions import PermissionDenied
        context = projection(request)['contexts'].get(team_id)
        if context is None or getattr(context, '_recorded_term', None) or not context.semester.is_active:
            raise PermissionDenied('Past phase records are read-only.')
    qs = workspace_deliverable_teams(request)
    team = qs.filter(pk=team_id).first()
    if not team:
        from student_teams.models import StudentTeam
        from repository.deliverables.pit_decisions import can_manage
        team = StudentTeam.objects.filter(pk=team_id).first()
        if not team or not can_manage(request.user, team):
            raise Http404('No StudentTeam matches the given query.')
    return team


def deliverables_action_payload(request, team, stage_label):
    """Opt-in row refresh; legacy clients retain the full list response."""
    # Start a fresh read scope after the action commits. Reuse repeated domain
    # reads while building this response, without caching write-side decisions.
    with read_projection():
        return _deliverables_action_payload(request, team, stage_label)


def _deliverables_action_payload(request, team, stage_label):
    scope = 'pit' if team.is_pit else 'capstone'
    selected_stage = request.query_params.get('stage_label') or stage_label
    queryset = workspace_deliverable_teams(request)
    if request.query_params.get('response_mode') == 'team':
        # Re-read after the transaction: review/endorsement may update a different
        # model instance and invalidate the pre-write prefetched submissions.
        updated = queryset.filter(pk=team.pk).first()
        if not updated:
            from student_teams.models import StudentTeam
            updated = StudentTeam.objects.filter(pk=team.pk).first()
            if not updated:
                raise Http404('No StudentTeam matches the given query.')
        return {
            'response_mode': 'team',
            'team': team_payload(updated, selected_stage=selected_stage, evaluator=request.user),
            'matches_filters': filter_teams(request, queryset.filter(pk=team.pk)).exists(),
            'selected_stage': selected_stage,
            'scope': scope,
        }
    return deliverables_payload(
        request, filter_teams(request, queryset), selected_stage=selected_stage, scope=scope,
    )


def deliverable_error_response(exc):
    """Map service/model errors to JSON API responses."""
    if hasattr(exc, 'message_dict'):
        return Response(exc.message_dict, status=status.HTTP_400_BAD_REQUEST)
    return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)


class CapstoneDeliverablesListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = filter_teams(request, workspace_deliverable_teams(request))
        return Response(deliverables_payload(request, queryset))


class CapstoneDeliverableUploadView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        serializer = DeliverableUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = serializer.validated_data
        team = get_allowed_team(request, attrs['team_id'])
        
        if not can_submit_files(request.user, team):
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
                file_id=attrs.get('file_id'),
                slot_key=attrs.get('slot_key', ''),
            )
        except (PermissionError, ValueError, ValidationError) as exc:
            return deliverable_error_response(exc)
        return Response(
            {
                'submission_id': submission.id,
                **deliverables_action_payload(request, team, attrs['stage_label']),
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
        
        if not can_submit_files(request.user, team):
            return Response({'detail': 'You do not have permission to manage deliverables for this team.'}, status=status.HTTP_403_FORBIDDEN)
            
        try:
            remove_submission(team, attrs['stage_label'], attrs['deliverable_id'], file_id=attrs.get('file_id'))
        except (PermissionError, ValueError, ValidationError) as exc:
            return deliverable_error_response(exc)
        return Response(deliverables_action_payload(request, team, attrs['stage_label']), status=status.HTTP_200_OK)


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
            endorse_team(team, attrs['stage_label'], user=request.user)
        except ValueError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(deliverables_action_payload(request, team, attrs['stage_label']), status=status.HTTP_200_OK)


class ReviewEndorseView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        if request.user.role == 'student':
            return Response({'detail': 'Students cannot review and endorse teams.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = ReviewEndorseSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = serializer.validated_data
        team = get_allowed_team(request, attrs['team_id'])
        from .endorsement import review_and_endorse, StaleEndorsementReview
        try:
            review_and_endorse(team, attrs['stage_label'], actor=request.user, review_token=attrs['review_token'])
        except StaleEndorsementReview as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_409_CONFLICT)
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)
        except (ValueError, ValidationError) as exc:
            return deliverable_error_response(exc)
        return Response(deliverables_action_payload(request, team, attrs['stage_label']))


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
        return Response(deliverables_action_payload(request, team, attrs['stage_label']), status=status.HTTP_200_OK)


class CompileWeeklyReportsView(APIView):
    """Retired write path; historical compiled PDFs retain their file endpoints."""
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        return Response({'detail': 'Weekly reports are managed and reviewed individually in Deliverables. '
            'Existing historical compilations remain available for download.'}, status=status.HTTP_410_GONE)


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
                clear_defense_revisions=attrs.get('clear_defense_revisions', False),
                file_id=attrs.get('file_id'),
                revision_scope=attrs.get('revision_scope', 'paper'),
                title_review_token=attrs.get('title_review_token'),
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
            deliverables_action_payload(request, team, attrs['stage_label']),
            status=status.HTTP_200_OK
        )


class CapstoneDeliverableUnlockView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = StageAccessChangeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = dict(serializer.validated_data)
        team = get_allowed_team(request, attrs.pop('team_id')) if attrs['scope'] == 'team' else None
        attrs.pop('team_id', None)
        from .stage_access import set_access, access_payload
        try:
            unlocked = set_access(request.user, team=team, request=request, **attrs)
            access = access_payload(request.user, team=team, scope=attrs['scope'],
                                    program_scope=attrs['program_scope'], year_level=attrs.get('year_level'))
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)
        except ValidationError as exc:
            return deliverable_error_response(exc)
        return Response({'unlocked': unlocked, 'stage_access': access})


class StageFileAccessView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = StageAccessScopeSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        attrs = dict(serializer.validated_data)
        team = get_allowed_team(request, attrs.pop('team_id')) if attrs['scope'] == 'team' else None
        attrs.pop('team_id', None)
        from .stage_access import access_payload
        try:
            return Response(access_payload(request.user, team=team, **attrs))
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_403_FORBIDDEN)
        except ValidationError as exc:
            return deliverable_error_response(exc)

