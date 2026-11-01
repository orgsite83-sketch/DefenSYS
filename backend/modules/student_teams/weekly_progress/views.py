from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from student_teams.models import StudentTeam

from .models import WeeklyProgressReport
from .serializers import WeeklyProgressReportSerializer
from .access import reports_for, can_write_report


class StudentWeeklyProgressListCreateView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser)

    def get(self, request):
        user = request.user
        raw_team_id = request.query_params.get('team_id')
        team_id = None
        if raw_team_id is not None and str(raw_team_id).strip() != '':
            try:
                team_id = int(raw_team_id)
            except (TypeError, ValueError):
                return Response(
                    {'detail': 'Invalid team_id.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        reports = reports_for(user)

        if team_id is not None:
            reports = reports.filter(team_id=team_id)

        serializer = WeeklyProgressReportSerializer(reports, many=True)
        return Response({
            'reports': serializer.data,
            'count': reports.count(),
        })

    def post(self, request):
        import logging

        logger = logging.getLogger(__name__)
        user = request.user

        if user.role != 'student':
            return Response(
                {'detail': 'Only students can submit progress reports.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        eligible = StudentTeam.objects.filter(memberships__student=user, semester__is_active=True,
            level__icontains='Capstone').select_related('semester').distinct()
        team_id = request.data.get('team_id') or request.data.get('team')
        if request.data.get('team_id') and request.data.get('team') and str(request.data['team_id']) != str(request.data['team']):
            return Response({'team_id': 'Team selections must match.'}, status=400)
        if team_id:
            if not str(team_id).isdigit():
                return Response({'team_id': 'Choose a valid team.'}, status=400)
            team = eligible.filter(pk=int(team_id)).first()
        else:
            candidates = list(eligible[:2])
            team = candidates[0] if len(candidates) == 1 else None
        if not team:
            return Response(
                {'detail': 'Select an assigned active capstone team for this report.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not team.is_capstone:
            return Response(
                {'detail': 'Weekly progress reports apply to capstone teams only.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if team.leader != user:
            return Response(
                {'detail': 'Only the team leader can submit weekly progress reports.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        from defense.stages.models import DefenseStage
        if DefenseStage.objects.filter(setup_semester=team.semester, weekly_reporting__enabled=True).exists():
            return Response({'detail': 'Upload through the configured Weekly Accomplishment Reports requirement.'}, status=400)

        data = request.data.copy()
        data['student'] = user.id
        data['team'] = team.id

        if 'week_number' not in data or not data['week_number']:
            last_report = WeeklyProgressReport.objects.filter(
                student=user,
                team=team,
            ).order_by('-week_number').first()
            data['week_number'] = (last_report.week_number + 1) if last_report else 1

        serializer = WeeklyProgressReportSerializer(data=data)
        if serializer.is_valid():
            report = serializer.save(student=user, team=team)
            logger.info('Weekly progress report saved: %s', report.id)
            return Response(serializer.data, status=status.HTTP_201_CREATED)

        logger.error('Weekly progress serializer errors: %s', serializer.errors)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class StudentWeeklyProgressDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get_object(self, pk, user):
        return get_object_or_404(reports_for(user), pk=pk)

    def get(self, request, pk):
        report = self.get_object(pk, request.user)
        if not report:
            return Response(
                {'detail': 'Not found or access denied.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = WeeklyProgressReportSerializer(report)
        return Response(serializer.data)

    def put(self, request, pk):
        report = self.get_object(pk, request.user)
        if report.period_id:
            return Response({'detail': 'Use the weekly collection to submit a new report version.'}, status=400)
        if not report:
            return Response(
                {'detail': 'Not found or access denied.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        if not can_write_report(request.user, report):
            return Response(
                {'detail': 'Only the team leader can edit weekly progress reports.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        serializer = WeeklyProgressReportSerializer(report, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    def delete(self, request, pk):
        report = self.get_object(pk, request.user)
        if report.period_id:
            return Response({'detail': 'Weekly report versions are retained as submission history.'}, status=400)
        if not report:
            return Response(
                {'detail': 'Not found or access denied.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        if not can_write_report(request.user, report):
            return Response(
                {'detail': 'Only the team leader can delete weekly progress reports.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        report.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class WeeklyProgressReportFileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        token = request.GET.get('token')
        if token and not request.auth:
            from rest_framework_simplejwt.authentication import JWTAuthentication

            jwt_auth = JWTAuthentication()
            try:
                validated_token = jwt_auth.get_validated_token(token)
                request.user = jwt_auth.get_user(validated_token)
            except Exception:
                pass

        user = request.user
        report = get_object_or_404(reports_for(user), pk=pk)

        selected_file = report.report_file
        if report.period_id:
            versions = report.versions.all()
            version_id = request.query_params.get('version_id')
            if version_id is not None and not str(version_id).isdigit():
                return Response({'detail': 'Choose a valid report version.'}, status=400)
            version = get_object_or_404(versions, pk=version_id) if version_id and str(version_id).isdigit() else get_object_or_404(versions, is_current=True)
            selected_file = version.file
        if not selected_file:
            raise Http404('No file attached to this report.')

        try:
            file_name = selected_file.name.split('/')[-1]
            file_extension = file_name.lower().split('.')[-1]
            content_types = {
                'pdf': 'application/pdf',
                'doc': 'application/msword',
                'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            }
            content_type = content_types.get(file_extension, 'application/octet-stream')
            response = FileResponse(selected_file.open('rb'), content_type=content_type)
            response['Content-Disposition'] = f'inline; filename="{file_name}"'
            return response
        except FileNotFoundError:
            raise Http404('File not found on server.') from None


def collection_team(request, *, writing=False):
    """Resolve explicit team and captured context without widening report reads."""
    from repository.deliverables.services import team_queryset_for_user
    params = request.data if writing else request.query_params
    raw = params.get('team_id')
    if not str(raw).isdigit() or not params.get('stage_label'):
        from rest_framework.exceptions import ValidationError
        raise ValidationError('Choose a team and defense stage.')
    team = get_object_or_404(team_queryset_for_user(request.user), pk=int(raw))
    semester_id = params.get('semester_id')
    project = params.get('project_version')
    if any(value is not None and (not str(value).isdigit() or int(value) < 1)
            for value in (semester_id, project)):
        from rest_framework.exceptions import ValidationError
        raise ValidationError('Choose a valid semester and project version.')
    if ((semester_id is not None and str(team.semester_id) != str(semester_id))
            or (project is not None and str(team.project_version) != str(project))):
        if writing:
            from rest_framework.exceptions import ValidationError
            raise ValidationError('The team term or project changed. Reopen the selected reporting period.')
        row = get_object_or_404(team.term_participations.select_related('semester'),
            semester_id=semester_id, project_version=project or team.project_version)
        team.semester, team.project_version = row.semester, row.project_version
        team._recorded_term = row
        team._prefetched_objects_cache = {}
    return team, params['stage_label']


class WeeklyReportCollectionView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from .services import require_definition, collection_state
        team, label = collection_team(request)
        return Response(collection_state(team, require_definition(team, label), actor=request.user, details=True))

    def post(self, request):
        from .services import upload_report, require_definition, collection_state, version_payload
        team, label = collection_team(request, writing=True)
        try:
            version = upload_report(team, label, actor=request.user, week=request.data.get('week_number'),
                file=request.FILES.get('report_file'), request_id=request.data.get('request_id'))
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=403)
        team._prefetched_objects_cache = {}
        from repository.deliverables.views import deliverables_action_payload
        return Response({'version': version_payload(version),
            **(deliverables_action_payload(request, team, label) if request.query_params.get('response_mode') == 'team' else {}),
            'collection': collection_state(team, require_definition(team, label), actor=request.user, details=True)}, status=201)


class WeeklyReportReviewView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        from .services import review_report, require_definition, collection_state, version_payload
        team, label = collection_team(request, writing=True)
        raw_version = request.data.get('version_id')
        if not str(raw_version).isdigit():
            return Response({'detail': 'Select the current report version.'}, status=400)
        try:
            version = review_report(team, label, actor=request.user, version_id=int(raw_version),
                decision=request.data.get('status'), feedback=request.data.get('feedback', ''))
        except PermissionError as exc:
            return Response({'detail': str(exc)}, status=403)
        team._prefetched_objects_cache = {}
        from repository.deliverables.views import deliverables_action_payload
        return Response({'version': version_payload(version),
            **(deliverables_action_payload(request, team, label) if request.query_params.get('response_mode') == 'team' else {}),
            'collection': collection_state(team, require_definition(team, label), actor=request.user, details=True)})


class WeeklyReportVersionsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        from .services import version_payload
        report = get_object_or_404(reports_for(request.user), pk=pk)
        from authentication_access_control.models import SystemAuditLog
        versions = list(report.versions.select_related('reviewed_by', 'uploaded_by').all())
        reviews = {}
        for event in SystemAuditLog.objects.filter(target_type='WeeklyReportVersion',
                target_id__in=[str(v.pk) for v in versions], action='weekly_report.reviewed').order_by('created_at', 'pk'):
            values = event.new_values
            reviews.setdefault(event.target_id, []).append({
                'status': values.get('decision'), 'feedback': values.get('feedback', ''),
                'reviewer_name': values.get('reviewer_name', ''),
                'reviewed_at': values.get('reviewed_at') or event.created_at.isoformat(),
            })
        return Response({'versions': [{**version_payload(v), 'reviews': reviews.get(str(v.pk), [])} for v in versions]})
