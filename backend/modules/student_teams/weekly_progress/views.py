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

        if not report.report_file:
            raise Http404('No file attached to this report.')

        try:
            file_name = report.report_file.name.split('/')[-1]
            file_extension = file_name.lower().split('.')[-1]
            content_types = {
                'pdf': 'application/pdf',
                'doc': 'application/msword',
                'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            }
            content_type = content_types.get(file_extension, 'application/octet-stream')
            response = FileResponse(report.report_file.open('rb'), content_type=content_type)
            response['Content-Disposition'] = f'inline; filename="{file_name}"'
            return response
        except FileNotFoundError:
            raise Http404('File not found on server.') from None
