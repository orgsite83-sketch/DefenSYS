from django.contrib.auth import get_user_model
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academic_period_management.models import Semester
from capstone_deliverables.models import DeliverableSubmission
from curriculum_analytics.services import (
    analytics_academic_year_count,
    analytics_entries_count,
    analytics_top_tech,
)
from defense_scheduler.models import DefenseSchedule
from defense_stages.models import DefenseStage
from digital_vault.services import restricted_vault_entries_count, visible_vault_entries_count
from grade_center.models import TeamGrade
from repository_audit.services import (
    repository_approved_count,
    repository_entries_count,
    repository_pending_count,
)
from rubric_engine.models import Rubric
from student_academic_records.models import StudentAcademicRecord
from student_teams.models import StudentTeam


User = get_user_model()


def _display_name(user):
    full_name = f"{user.first_name} {user.last_name}".strip()
    return full_name or user.username


def _user_payload(user):
    return {
        'id': user.id,
        'username': user.username,
        'name': _display_name(user),
        'email': user.email,
        'role': user.role,
        'team_id': user.team_id,
    }


def _faculty_roles(user):
    return {
        'panelist': user.is_panelist,
        'pit_lead': user.is_pit_lead,
        'pit_lead_year': user.pit_lead_year,
        'adviser': user.is_adviser,
        'adviser_phase': user.adviser_phase,
        'repo_assistant': user.is_repo_assistant,
        'uploader': user.is_uploader,
    }


def _active_role_labels(user):
    labels = []
    if user.is_panelist:
        labels.append('Panelist')
    if user.is_pit_lead:
        label = 'PIT Lead'
        if user.pit_lead_year:
            label = f'{label}: {user.pit_lead_year}'
        labels.append(label)
    if user.is_adviser:
        labels.append('Project Adviser')
    if user.is_repo_assistant:
        labels.append('Repository Assistant')
    if user.is_uploader:
        labels.append('Document Uploader')
    return labels


def _active_semester_label():
    semester = Semester.objects.select_related('school_year').filter(is_active=True).first()
    return semester.display_name if semester else 'Not configured'


def _latest_academic_record(user):
    return (
        StudentAcademicRecord.objects.select_related('semester', 'semester__school_year')
        .filter(student=user)
        .order_by('-created_at', '-id')
        .first()
    )


def _team_payload(team):
    memberships = list(team.memberships.select_related('student').all())
    return {
        'id': team.id,
        'name': team.name,
        'projectTitle': team.project_title,
        'level': team.level,
        'yearLevel': team.year_level,
        'semester': team.semester.label,
        'schoolYear': team.semester.school_year.label,
        'status': team.status,
        'isCapstone': team.is_capstone,
        'currentStage': team.current_defense_stage or team.ready_for_stage or ('Concept Proposal' if team.is_capstone else None),
        'readyForStage': team.ready_for_stage,
        'deliverableCount': team.deliverable_submissions.count() if team.is_capstone else 0,
        'adviserName': _display_name(team.adviser) if team.adviser else None,
        'leaderName': _display_name(team.leader),
        'memberCount': len(memberships),
        'members': [
            {
                'id': membership.student.id,
                'username': membership.student.username,
                'name': _display_name(membership.student),
                'isLeader': membership.is_leader,
            }
            for membership in memberships
        ],
    }


def _schedule_payload(schedule):
    if schedule is None:
        return None
    return {
        'id': schedule.id,
        'stage': schedule.stage_label,
        'date': schedule.scheduled_date,
        'startTime': schedule.start_time,
        'slotDuration': schedule.slot_duration,
        'room': schedule.room,
        'status': schedule.status,
        'teamId': schedule.team_id,
        'teamName': schedule.team.name,
    }


class AdminDashboardView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        student_count = User.objects.filter(role='student').count()
        faculty_count = User.objects.filter(role__in=['faculty', 'admin']).count()
        team_count = StudentTeam.objects.count()
        stage_count = DefenseStage.objects.filter(is_active=True).count()
        published_rubric_count = Rubric.objects.filter(status=Rubric.STATUS_PUBLISHED).count()
        upcoming_defense_count = DefenseSchedule.objects.filter(status=DefenseSchedule.STATUS_SCHEDULED).count()
        published_grade_count = TeamGrade.objects.filter(status=TeamGrade.STATUS_PUBLISHED).count()
        pending_grade_count = TeamGrade.objects.exclude(status=TeamGrade.STATUS_PUBLISHED).count()
        submitted_deliverable_count = DeliverableSubmission.objects.count()
        vault_file_count = visible_vault_entries_count()
        restricted_vault_file_count = restricted_vault_entries_count()
        repository_file_count = repository_entries_count()
        pending_repository_file_count = repository_pending_count()
        approved_repository_file_count = repository_approved_count()
        analytics_entry_count = analytics_entries_count()
        analytics_year_count = analytics_academic_year_count()
        analytics_top_technology = analytics_top_tech()
        ready_capstone_count = StudentTeam.objects.filter(
            level__icontains='Capstone',
            ready_for_stage__isnull=False,
        ).exclude(ready_for_stage='').count()
        active_semester = _active_semester_label()
        period_configured = active_semester != 'Not configured'

        return Response({
            'stats': {
                'total_students': student_count,
                'total_faculty': faculty_count,
                'total_teams': team_count,
                'upcoming_defenses': upcoming_defense_count,
                'active_defense_stages': stage_count,
                'published_rubrics': published_rubric_count,
                'published_grades': published_grade_count,
                'pending_grades': pending_grade_count,
                'submitted_deliverables': submitted_deliverable_count,
                'vault_files': vault_file_count,
                'restricted_vault_files': restricted_vault_file_count,
                'repository_files': repository_file_count,
                'pending_repository_files': pending_repository_file_count,
                'approved_repository_files': approved_repository_file_count,
                'analytics_entries': analytics_entry_count,
                'analytics_academic_years': analytics_year_count,
                'analytics_top_tech': analytics_top_technology,
                'ready_capstone_teams': ready_capstone_count,
            },
            'active_semester': active_semester,
            'alerts': [
                {
                    'type': 'success' if period_configured else 'warning',
                    'message': (
                        f'{active_semester} is active for write-enabled modules.'
                        if period_configured
                        else 'No active semester is configured. Create an academic period before migrating write-enabled modules.'
                    ),
                },
                {
                    'type': 'success',
                    'message': 'Authentication and dashboard APIs are now served by Django.',
                },
                {
                    'type': 'success',
                    'message': 'All 15 migration phases are Django-backed, including curriculum analytics and rule-based classification.',
                },
            ],
            'migration': {
                'phase': 15,
                'source': 'django',
                'pending_modules': [],
            },
        })


class FacultyDashboardView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        advised_teams = StudentTeam.objects.filter(adviser=user).select_related(
            'semester',
            'semester__school_year',
            'leader',
            'adviser',
        ).prefetch_related('memberships', 'memberships__student', 'deliverable_submissions')
        pit_teams = StudentTeam.objects.none()
        if user.is_pit_lead and user.pit_lead_year:
            pit_teams = StudentTeam.objects.filter(
                year_level=user.pit_lead_year,
                level__icontains='PIT',
            ).select_related(
                'semester',
                'semester__school_year',
                'leader',
                'adviser',
            ).prefetch_related('memberships', 'memberships__student', 'deliverable_submissions')

        return Response({
            'faculty': _user_payload(user),
            'roles': _faculty_roles(user),
            'active_roles': _active_role_labels(user),
            'advised_teams': [_team_payload(team) for team in advised_teams],
            'panelist_assignments': [],
            'pit_teams': [_team_payload(team) for team in pit_teams],
            'pit_lead_year': user.pit_lead_year if user.is_pit_lead else None,
            'is_repo_assistant': user.is_repo_assistant,
            'message': 'Team, schedule, and grading data will be populated as later modules are migrated.',
        })


class StudentDashboardView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        
        # First, try to find team through memberships relationship (most reliable)
        team = (
            StudentTeam.objects.filter(memberships__student=user)
            .select_related('semester', 'semester__school_year', 'leader', 'adviser')
            .prefetch_related('memberships', 'memberships__student', 'deliverable_submissions')
            .order_by('-updated_at', '-id')
            .first()
        )
        
        # Fallback: If no team found via memberships but user has team_id, try to find by team_id
        if not team and user.team_id:
            try:
                team = (
                    StudentTeam.objects
                    .select_related('semester', 'semester__school_year', 'leader', 'adviser')
                    .prefetch_related('memberships', 'memberships__student', 'deliverable_submissions')
                    .get(id=int(user.team_id))
                )
            except (StudentTeam.DoesNotExist, ValueError):
                # team_id is invalid or team doesn't exist
                pass
        
        academic_record = _latest_academic_record(user)
        team_payload = _team_payload(team) if team else None
        schedule = (
            DefenseSchedule.objects.select_related('team', 'defense_stage')
            .filter(team=team, status=DefenseSchedule.STATUS_SCHEDULED)
            .order_by('scheduled_date', 'start_time')
            .first()
            if team
            else None
        )
        grade = (
            TeamGrade.objects.filter(team=team, status=TeamGrade.STATUS_PUBLISHED)
            .order_by('-updated_at', '-id')
            .first()
            if team
            else None
        )
        active_sem = Semester.objects.filter(is_active=True).first()
        peer_eval_on = getattr(active_sem, 'capstone_peer_evaluation_enabled', True) if active_sem else True
        adviser_grading_on = getattr(active_sem, 'capstone_adviser_grading_enabled', True) if active_sem else True

        return Response({
            'student': _user_payload(user),
            'academic_record': {
                'school_year': academic_record.school_year.label,
                'semester': academic_record.semester.label,
                'year_level': academic_record.year_level,
            } if academic_record else None,
            'team': team_payload,
            'schedule': _schedule_payload(schedule),
            'grades': {
                'panelist': {'total': grade.panel_score, 'max': 100} if grade and grade.panel_score is not None else None,
                'adviser': {'total': grade.adviser_score, 'max': 100} if grade and grade.adviser_score is not None else None,
                'peer': {'total': grade.peer_score, 'max': 100} if grade and grade.peer_score is not None else None,
                'finalGrade': grade.final_grade,
                'status': grade.status,
                'stage': grade.stage_label,
            } if grade else None,
            'members': team_payload['members'] if team_payload else [],
            'weights': {'panel': 50, 'adviser': 30, 'peer': 20},
            'peerEvalEnabled': peer_eval_on,
            'adviserGradingEnabled': adviser_grading_on,
            'peerCriteria': [],
            'myPeerGrade': None,
            'team_name': team_payload['name'] if team_payload else None,
            'project_title': team_payload['projectTitle'] if team_payload else None,
            'status': team_payload['status'] if team_payload else 'No team assigned',
            'final_grade': grade.final_grade if grade else None,
        })


class PanelistDashboardView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({
            'panelist': _user_payload(request.user),
            'upcoming_defenses': [],
            'assignments': [],
            'results': [],
            'message': 'Panelist assignments will move from the bridge server during the scheduling and grade center phases.',
        })
