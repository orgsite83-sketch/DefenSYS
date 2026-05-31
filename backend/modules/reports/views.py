from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.db.models import Q
from django.utils.dateparse import parse_date
from datetime import datetime
from rest_framework import status
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from django.contrib.auth import get_user_model

from authentication_access_control.scopes import (
    is_admin_user,
    is_pit_lead_only,
    can_review_audit_logs,
    visible_teams_for,
    visible_schedules_for,
    grade_records_for,
    audit_logs_for,
)

from grading.grades.models import TeamGrade
from defense.scheduler.models import DefenseSchedule
from academic_period_management.models import Semester
from authentication_access_control.models import SystemAuditLog

# Import PDF Generators
from reports.generators.team_grade_report import generate_team_grade_pdf
from reports.generators.semester_grades_report import generate_semester_grades_pdf
from reports.generators.defense_schedule_report import generate_defense_schedule_pdf
from reports.generators.team_roster_report import generate_team_roster_pdf
from reports.generators.user_directory_report import generate_user_directory_pdf
from reports.generators.audit_trail_report import generate_audit_trail_pdf

User = get_user_model()


class TeamGradeReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, team_id):
        # Retrieve all team grade records visible to this user for the specified team
        visible_grades = grade_records_for(request.user).filter(team_id=team_id)
        if not visible_grades.exists():
            raise PermissionDenied("You do not have permission to view grade reports for this team.")
        
        # If a specific grade record ID or stage ID is requested
        grade_id = request.query_params.get('grade_id')
        stage_id = request.query_params.get('stage_id')
        
        if grade_id:
            grade_record = get_object_or_404(visible_grades, pk=grade_id)
        elif stage_id:
            grade_record = get_object_or_404(visible_grades, defense_stage_id=stage_id)
        else:
            # Default to the most recently created grade record for the team
            grade_record = visible_grades.order_by('-created_at').first()
            
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        pdf_data = generate_team_grade_pdf(grade_record, generated_by)
        
        # Filename safe format
        team_name_safe = "".join(c for c in grade_record.team.name if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        stage_safe = "".join(c for c in grade_record.stage_label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_Grade_Report_{team_name_safe}_{stage_safe}.pdf"
        
        response = HttpResponse(pdf_data, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


class SemesterGradesReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Fetch active or specified semester
        semester_id = request.query_params.get('semester_id')
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = Semester.objects.filter(is_active=True).first()
            if not semester:
                return Response(
                    {"detail": "No active semester is configured."},
                    status=status.HTTP_400_BAD_REQUEST
                )
                
        # Retrieve grades scoped to user's permissions
        base_queryset = grade_records_for(request.user).filter(semester=semester)
        
        # Apply query parameter filters matching Grade Center main screen
        search = request.query_params.get('search', '').strip()
        year_level = request.query_params.get('year_level', '').strip()
        status_filter = request.query_params.get('status', '').strip()
        scope = request.query_params.get('scope', '').strip()
        
        queryset = base_queryset
        if search:
            queryset = queryset.filter(
                Q(team__name__icontains=search)
                | Q(team__project_title__icontains=search)
                | Q(stage_label__icontains=search)
            ).distinct()
        if year_level:
            queryset = queryset.filter(team__year_level=year_level)
        if status_filter:
            queryset = queryset.filter(status=status_filter)
        if scope and scope != 'all':
            queryset = queryset.filter(scope=scope)
            
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        pdf_data = generate_semester_grades_pdf(semester, list(queryset), generated_by)
        
        sem_label_safe = "".join(c for c in semester.school_year.label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_Semester_Grades_{sem_label_safe}_{semester.label.replace(' ', '_')}.pdf"
        
        response = HttpResponse(pdf_data, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


class DefenseScheduleReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Fetch active or specified semester
        semester_id = request.query_params.get('semester_id')
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = Semester.objects.filter(is_active=True).first()
            if not semester:
                return Response(
                    {"detail": "No active semester is configured."},
                    status=status.HTTP_400_BAD_REQUEST
                )
                
        # Retrieve schedules scoped to user's permissions
        base_queryset = visible_schedules_for(request.user).filter(semester=semester)
        
        # Apply filters matching scheduler list
        search = request.query_params.get('search', '').strip()
        scope = request.query_params.get('scope', '').strip()
        status_filter = request.query_params.get('status', '').strip()
        date_filter = request.query_params.get('date', '').strip()
        
        queryset = base_queryset
        if search:
            queryset = queryset.filter(
                Q(team__name__icontains=search)
                | Q(team__project_title__icontains=search)
                | Q(room__icontains=search)
                | Q(event_name__icontains=search)
            ).distinct()
        if scope:
            queryset = queryset.filter(scope=scope)
        if status_filter:
            queryset = queryset.filter(status=status_filter)
        if date_filter:
            queryset = queryset.filter(scheduled_date=date_filter)
            
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        pdf_data = generate_defense_schedule_pdf(semester, list(queryset), generated_by)
        
        sem_label_safe = "".join(c for c in semester.school_year.label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_Defense_Schedules_{sem_label_safe}_{semester.label.replace(' ', '_')}.pdf"
        
        response = HttpResponse(pdf_data, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


class TeamRosterReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Fetch active or specified semester
        semester_id = request.query_params.get('semester_id')
        if semester_id:
            semester = get_object_or_404(Semester.objects.select_related('school_year'), pk=semester_id)
        else:
            semester = Semester.objects.filter(is_active=True).first()
            
        # Retrieve teams scoped to user's permissions
        queryset = visible_teams_for(request.user)
        if semester:
            queryset = queryset.filter(semester=semester)
            
        # Apply filters
        level = request.query_params.get('level', '').strip()
        year_level = request.query_params.get('year_level', '').strip()
        
        if level:
            queryset = queryset.filter(level__icontains=level)
        if year_level:
            queryset = queryset.filter(year_level=year_level)
            
        # Select related for prefetching inside roster generator
        queryset = queryset.select_related('leader', 'adviser').prefetch_related('memberships', 'memberships__student')
        
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        pdf_data = generate_team_roster_pdf(semester, list(queryset), generated_by)
        
        sem_label = f"_{semester.school_year.label}_{semester.label}" if semester else ""
        sem_label_safe = "".join(c for c in sem_label if c.isalnum() or c in (' ', '_', '-')).strip().replace(' ', '_')
        filename = f"DefenSYS_Team_Roster{sem_label_safe}.pdf"
        
        response = HttpResponse(pdf_data, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


class UserDirectoryReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # User list is restricted to admin roles initially
        if not is_admin_user(request.user):
            raise PermissionDenied("Only administrators can export the complete user directory.")
            
        role = request.query_params.get('role', '').strip()
        status_filter = request.query_params.get('status', '').strip()
        
        queryset = User.objects.all()
        if role:
            queryset = queryset.filter(role=role)
        if status_filter:
            is_active = status_filter.lower() == 'active'
            queryset = queryset.filter(is_active=is_active)
            
        queryset = queryset.order_by('role', 'username')
        
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        pdf_data = generate_user_directory_pdf(list(queryset), generated_by)
        
        filename = f"DefenSYS_User_Directory_{datetime.now().strftime('%Y-%m-%d')}.pdf"
        
        response = HttpResponse(pdf_data, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response


class AuditTrailReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if not can_review_audit_logs(request.user):
            raise PermissionDenied("You do not have permission to view or export the Audit Trail logs.")
            
        base_queryset = audit_logs_for(request.user)
        queryset = base_queryset
        
        # Apply filters matching SystemAuditLogListView
        category = request.query_params.get('category', '').strip()
        action = request.query_params.get('action', '').strip()
        review_status = request.query_params.get('review_status', '').strip()
        actor_id = request.query_params.get('actor', '').strip()
        search = request.query_params.get('search', '').strip()
        start_date = parse_date(request.query_params.get('start_date', '').strip())
        end_date = parse_date(request.query_params.get('end_date', '').strip())
        track = request.query_params.get('track', '').strip().lower()
        year_level = request.query_params.get('year_level', '').strip()

        filters_desc = {}
        if category:
            queryset = queryset.filter(category=category)
            filters_desc['Category'] = category
        if action:
            queryset = queryset.filter(action=action)
            filters_desc['Action'] = action
        if review_status:
            queryset = queryset.filter(review_status=review_status)
            filters_desc['Review Status'] = review_status
        if actor_id:
            queryset = queryset.filter(actor_id=actor_id)
            actor = User.objects.filter(id=actor_id).first()
            if actor:
                filters_desc['Responsible User'] = f"{actor.first_name} {actor.last_name}".strip() or actor.username
        if start_date:
            queryset = queryset.filter(created_at__date__gte=start_date)
            filters_desc['Start Date'] = start_date.strftime('%Y-%m-%d')
        if end_date:
            queryset = queryset.filter(created_at__date__lte=end_date)
            filters_desc['End Date'] = end_date.strftime('%Y-%m-%d')
        if track:
            filters_desc['Academic Track'] = track.upper()
            pit_marker = (
                Q(old_values__entry_type='pit')
                | Q(new_values__entry_type='pit')
                | Q(old_values__scope='pit')
                | Q(new_values__scope='pit')
                | Q(old_values__track='pit')
                | Q(new_values__track='pit')
            )
            if track == 'pit':
                queryset = queryset.filter(pit_marker)
            elif track == 'capstone':
                pit_ids = queryset.filter(pit_marker).values_list('id', flat=True)
                queryset = queryset.exclude(id__in=pit_ids)
        if year_level:
            filters_desc['Year Level'] = year_level
            year_marker = (
                Q(old_values__year_level=year_level)
                | Q(new_values__year_level=year_level)
                | Q(old_values__team_year_level=year_level)
                | Q(new_values__team_year_level=year_level)
                | Q(old_values__pit_year_level=year_level)
                | Q(new_values__pit_year_level=year_level)
            )
            queryset = queryset.filter(year_marker)
        if search:
            queryset = queryset.filter(
                Q(action__icontains=search)
                | Q(target_type__icontains=search)
                | Q(target_id__icontains=search)
                | Q(reason__icontains=search)
            )
            filters_desc['Search query'] = search
            
        queryset = queryset.order_by('-created_at')
        
        # Enforce page limits for safety in standard reports, but allow up to 1000 items in PDF exports
        limit = min(max(int(request.query_params.get('limit', 1000)), 1), 2000)
        logs = list(queryset[:limit])
        
        generated_by = f"{request.user.first_name} {request.user.last_name}".strip() or request.user.username
        pdf_data = generate_audit_trail_pdf(logs, filters_desc, generated_by)
        
        filename = f"DefenSYS_Audit_Register_{datetime.now().strftime('%Y-%m-%d')}.pdf"
        
        response = HttpResponse(pdf_data, content_type='application/pdf')
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        return response
