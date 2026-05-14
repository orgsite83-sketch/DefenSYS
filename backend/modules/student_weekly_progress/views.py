from django.shortcuts import get_object_or_404
from django.http import FileResponse, Http404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.parsers import MultiPartParser, FormParser

from student_teams.models import StudentTeam
from .models import WeeklyProgressReport
from .serializers import WeeklyProgressReportSerializer


class StudentWeeklyProgressListCreateView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser)
    
    def get(self, request):
        """Get all progress reports for the current student or team"""
        user = request.user
        
        if user.role == 'student':
            # Students see only their own reports
            reports = WeeklyProgressReport.objects.filter(student=user).select_related('team', 'student')
        elif user.role == 'faculty' and user.is_adviser:
            # Advisers see reports from their advised teams
            reports = WeeklyProgressReport.objects.filter(
                team__adviser=user
            ).select_related('team', 'student')
        elif user.role == 'admin':
            # Admins see all reports
            reports = WeeklyProgressReport.objects.all().select_related('team', 'student')
        else:
            reports = WeeklyProgressReport.objects.none()
        
        serializer = WeeklyProgressReportSerializer(reports, many=True)
        return Response({
            'reports': serializer.data,
            'count': reports.count(),
        })
    
    def post(self, request):
        """Create a new weekly progress report - Only team leaders can submit"""
        import logging
        logger = logging.getLogger(__name__)
        
        logger.info(f"=== Weekly Progress POST Request ===")
        logger.info(f"User: {request.user}")
        logger.info(f"User role: {getattr(request.user, 'role', 'NO ROLE')}")
        logger.info(f"Request data: {request.data}")
        
        user = request.user
        
        if user.role != 'student':
            logger.warning(f"Non-student tried to submit: {user.role}")
            return Response(
                {'detail': 'Only students can submit progress reports.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Get student's team
        team = StudentTeam.objects.filter(memberships__student=user).first()
        logger.info(f"Found team: {team}")
        
        if not team:
            logger.warning(f"Student {user} has no team")
            return Response(
                {'detail': 'You are not assigned to a team.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Check if user is the team leader
        logger.info(f"Team leader: {team.leader}, Current user: {user}")
        if team.leader != user:
            logger.warning(f"Non-leader tried to submit: {user} (leader is {team.leader})")
            return Response(
                {'detail': 'Only the team leader can submit weekly progress reports.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Add student and team to data
        data = request.data.copy()
        data['student'] = user.id
        data['team'] = team.id
        
        # Auto-calculate week_number if not provided
        if 'week_number' not in data or not data['week_number']:
            # Get the highest week number for this student and team
            last_report = WeeklyProgressReport.objects.filter(
                student=user,
                team=team
            ).order_by('-week_number').first()
            
            if last_report:
                data['week_number'] = last_report.week_number + 1
            else:
                data['week_number'] = 1
            
            logger.info(f"Auto-calculated week_number: {data['week_number']}")
        
        logger.info(f"Serializer data: {data}")
        
        serializer = WeeklyProgressReportSerializer(data=data)
        if serializer.is_valid():
            logger.info("Serializer is valid, saving...")
            report = serializer.save(student=user, team=team)
            logger.info(f"Report saved successfully! ID: {report.id}")
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        
        logger.error(f"Serializer errors: {serializer.errors}")
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class StudentWeeklyProgressDetailView(APIView):
    permission_classes = [IsAuthenticated]
    
    def get_object(self, pk, user):
        report = get_object_or_404(WeeklyProgressReport, pk=pk)
        
        # Check permissions
        if user.role == 'student' and report.student != user:
            return None
        elif user.role == 'faculty' and user.is_adviser and report.team.adviser != user:
            return None
        elif user.role not in ['student', 'faculty', 'admin']:
            return None
        
        return report
    
    def get(self, request, pk):
        """Get a specific progress report"""
        report = self.get_object(pk, request.user)
        if not report:
            return Response(
                {'detail': 'Not found or access denied.'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        serializer = WeeklyProgressReportSerializer(report)
        return Response(serializer.data)
    
    def put(self, request, pk):
        """Update a progress report - Only team leaders can edit"""
        report = self.get_object(pk, request.user)
        if not report:
            return Response(
                {'detail': 'Not found or access denied.'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Check if user is the team leader
        if request.user.role != 'student' or report.team.leader != request.user:
            return Response(
                {'detail': 'Only the team leader can edit weekly progress reports.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        serializer = WeeklyProgressReportSerializer(report, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    
    def delete(self, request, pk):
        """Delete a progress report - Only team leaders can delete"""
        report = self.get_object(pk, request.user)
        if not report:
            return Response(
                {'detail': 'Not found or access denied.'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        # Check if user is the team leader
        if request.user.role != 'student' or report.team.leader != request.user:
            return Response(
                {'detail': 'Only the team leader can delete weekly progress reports.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        report.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)



class WeeklyProgressReportFileView(APIView):
    """View to download/view weekly progress report files"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request, pk):
        """Download or view a weekly progress report file"""
        # Try to get token from query parameter if not in header
        token = request.GET.get('token')
        if token and not request.auth:
            from rest_framework_simplejwt.authentication import JWTAuthentication
            jwt_auth = JWTAuthentication()
            try:
                validated_token = jwt_auth.get_validated_token(token)
                user = jwt_auth.get_user(validated_token)
                request.user = user
            except Exception:
                pass
        
        user = request.user
        report = get_object_or_404(WeeklyProgressReport, pk=pk)
        
        # Check permissions
        can_access = False
        if user.role == 'student' and report.student == user:
            can_access = True
        elif user.role == 'faculty' and user.is_adviser and report.team.adviser == user:
            can_access = True
        elif user.role == 'admin':
            can_access = True
        
        if not can_access:
            return Response(
                {'detail': 'You do not have permission to access this file.'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Check if file exists
        if not report.report_file:
            raise Http404("No file attached to this report.")
        
        try:
            # Get file extension
            file_name = report.report_file.name.split('/')[-1]
            file_extension = file_name.lower().split('.')[-1]
            
            # Set content type based on file extension
            content_types = {
                'pdf': 'application/pdf',
                'doc': 'application/msword',
                'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            }
            content_type = content_types.get(file_extension, 'application/octet-stream')
            
            # Return the file
            response = FileResponse(report.report_file.open('rb'), content_type=content_type)
            
            # Use inline disposition to display in browser (PDF viewer)
            response['Content-Disposition'] = f'inline; filename="{file_name}"'
            
            return response
        except FileNotFoundError:
            raise Http404("File not found on server.")
