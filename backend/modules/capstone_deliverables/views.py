from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.serializers import SemesterSerializer
from defensys_backend.prototype_tools import require_prototype_tools
from .serializers import (
    DeliverableActionSerializer,
    DeliverableUploadSerializer,
    DemoFillSerializer,
)
from .services import (
    STAGE_OPTIONS,
    active_semester,
    counts_payload,
    demo_fill_required,
    endorse_team,
    filter_teams,
    remove_submission,
    team_payload,
    team_queryset_for_user,
    upsert_submission,
)


class CanManageDeliverables(BasePermission):
    message = 'Only administrators, assigned advisers, and team members can manage Capstone deliverables.'

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and (
                getattr(user, 'role', None) == 'admin'
                or getattr(user, 'is_superuser', False)
                or (getattr(user, 'role', None) == 'faculty' and getattr(user, 'is_adviser', False))
                or getattr(user, 'role', None) == 'student'  # Allow students to upload
            )
        )


def deliverables_payload(request, queryset=None, selected_stage=None):
    base = team_queryset_for_user(request.user)
    current = queryset if queryset is not None else base
    stage = selected_stage or request.query_params.get('stage_label') or STAGE_OPTIONS[0]
    semester = active_semester()
    return {
        'teams': [team_payload(team, selected_stage=stage) for team in current],
        'counts': counts_payload(current),
        'stage_options': STAGE_OPTIONS,
        'selected_stage': stage,
        'statuses': [
            {'value': '', 'label': 'All Teams'},
            {'value': 'ready', 'label': 'Ready / Endorsed'},
            {'value': 'missing', 'label': 'Missing Requirements'},
        ],
        'active_semester': SemesterSerializer(semester).data if semester else None,
    }


def get_allowed_team(request, team_id):
    return get_object_or_404(team_queryset_for_user(request.user), pk=team_id)


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
            )
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(
            {
                'submission_id': submission.id,
                **deliverables_payload(request),
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
        remove_submission(team, attrs['stage_label'], attrs['deliverable_id'])
        return Response(deliverables_payload(request), status=status.HTTP_200_OK)


class CapstoneDeliverableEndorseView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        serializer = DeliverableActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        attrs = serializer.validated_data
        team = get_allowed_team(request, attrs['team_id'])
        try:
            endorse_team(team, attrs['stage_label'])
        except ValueError as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(deliverables_payload(request), status=status.HTTP_200_OK)


class CapstoneDeliverableDemoFillView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        require_prototype_tools()
        serializer = DemoFillSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        stage_label = serializer.validated_data.get('stage_label') or STAGE_OPTIONS[0]
        teams = list(filter_teams(request, team_queryset_for_user(request.user)))
        created = demo_fill_required(teams, stage_label, request.user)
        return Response(
            {
                'created_count': created,
                **deliverables_payload(request, selected_stage=stage_label),
            },
            status=status.HTTP_200_OK,
        )


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
                from student_weekly_progress.models import WeeklyProgressReport
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
