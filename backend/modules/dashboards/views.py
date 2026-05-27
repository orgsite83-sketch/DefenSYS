from django.contrib.auth import get_user_model
from django.db.models import Q
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from user_management.permissions import (
    IsAdminRole,
    IsFacultyRole,
    IsPanelist,
    IsPitLead,
    IsStudentRole,
)

from academic_period_management.models import Semester
from repository.deliverables.models import DeliverableSubmission
from curriculum_analytics.services import (
    analytics_academic_year_count,
    analytics_entries_count,
    analytics_top_tech,
)
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from repository.vault.services import restricted_vault_entries_count, visible_vault_entries_count
from grading.grades.models import TeamGrade
from grading.grades.services import default_weights, weights_for_schedule
from grading.grades.peer_eval import peer_criteria_payload, peer_submissions_for_evaluator
from repository.audit.services import (
    repository_approved_count,
    repository_entries_count,
    repository_pending_count,
)
from grading.rubrics.models import Rubric
from user_management.academic_records.models import StudentAcademicRecord
from student_teams.models import StudentTeam, TeamMembership
from student_teams.term_scope import (
    apply_team_scope,
    get_active_semester,
    pit_lead_operating_message,
    pit_lead_operating_mode,
    pit_roster_student_ids,
)
from .pit_repository_assistant import current_repo_assistant_for_year


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
        'repo_assistant': user.is_repo_assistant,
        'repo_assistant_year': getattr(user, 'repo_assistant_year', '') or '',
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


def _pit_teams_queryset(user, *, scope='active'):
    if not getattr(user, 'is_pit_lead', False) or not (getattr(user, 'pit_lead_year', None) or '').strip():
        return StudentTeam.objects.none()
    base = StudentTeam.objects.filter(
        year_level=user.pit_lead_year,
        level__icontains='PIT',
    ).select_related(
        'semester',
        'semester__school_year',
        'leader',
        'adviser',
    ).prefetch_related('memberships', 'memberships__student', 'deliverable_submissions')
    return apply_team_scope(base, scope=scope, user=user)


def _pit_lead_scope(user):
    pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
    if not getattr(user, 'is_pit_lead', False) or not pit_year:
        return None, None
    return pit_year, get_active_semester()


def _pit_team_membership_by_student(pit_year, active_semester, *, historical=False):
    memberships = TeamMembership.objects.filter(
        team__year_level=pit_year,
        team__level__icontains='PIT',
    ).select_related('team', 'student')
    if active_semester:
        if historical:
            memberships = memberships.exclude(team__semester_id=active_semester.id)
        else:
            memberships = memberships.filter(team__semester_id=active_semester.id)
    by_student = {}
    for membership in memberships:
        by_student[membership.student_id] = {
            'team_id': membership.team_id,
            'team_name': membership.team.name,
            'is_leader': membership.is_leader,
            'term_label': membership.team.semester.display_name,
        }
    return by_student


def _pit_cohort_student_payload(student, membership, *, is_historical=False):
    on_team = membership is not None
    return {
        'id': student.id,
        'username': student.username,
        'name': _display_name(student),
        'email': student.email,
        'team_status': 'on_team' if on_team else 'unassigned',
        'team_id': membership['team_id'] if on_team else None,
        'team_name': membership['team_name'] if on_team else None,
        'is_leader': membership['is_leader'] if on_team else None,
        'is_historical': is_historical,
        'term_label': membership['term_label'] if on_team else None,
    }


def _cohort_rows_for_scope(user, pit_year, active_semester, *, historical=False, search='', team_status='all', limit=None):
    if not pit_year or not active_semester:
        return [], {'all': 0, 'unassigned': 0, 'on_team': 0}

    student_ids = pit_roster_student_ids(
        active_semester,
        pit_lead_year=pit_year,
        historical=historical,
    )
    students = User.objects.filter(
        pk__in=student_ids,
        role='student',
        is_active=True,
    ).order_by('last_name', 'first_name', 'username')

    search = (search or '').strip()
    if search:
        students = students.filter(
            Q(username__icontains=search)
            | Q(first_name__icontains=search)
            | Q(last_name__icontains=search)
            | Q(email__icontains=search)
        )

    membership_by_student = _pit_team_membership_by_student(
        pit_year,
        active_semester,
        historical=historical,
    )
    rows = []
    for student in students:
        membership = membership_by_student.get(student.id)
        rows.append(_pit_cohort_student_payload(student, membership, is_historical=historical))

    counts = {
        'all': len(rows),
        'unassigned': sum(1 for row in rows if row['team_status'] == 'unassigned'),
        'on_team': sum(1 for row in rows if row['team_status'] == 'on_team'),
    }

    team_status = (team_status or 'all').strip().lower()
    if team_status == 'unassigned':
        rows = [row for row in rows if row['team_status'] == 'unassigned']
    elif team_status == 'on_team':
        rows = [row for row in rows if row['team_status'] == 'on_team']

    if limit is not None:
        rows = rows[:limit]

    return rows, counts


def _pit_lead_cohort_students(user, *, search='', team_status='all', limit=None, cohort_scope='active'):
    pit_year, active_semester = _pit_lead_scope(user)
    if not pit_year:
        return [], pit_year, active_semester, {'all': 0, 'unassigned': 0, 'on_team': 0}

    if not active_semester:
        return [], pit_year, active_semester, {'all': 0, 'unassigned': 0, 'on_team': 0}

    historical = cohort_scope == 'history'
    rows, counts = _cohort_rows_for_scope(
        user,
        pit_year,
        active_semester,
        historical=historical,
        search=search,
        team_status=team_status,
        limit=limit,
    )
    return rows, pit_year, active_semester, counts


def _pit_lead_cohort_payload(user, *, search='', team_status='all', limit=None, cohort_scope='active'):
    pit_year, active_semester = _pit_lead_scope(user)
    mode = pit_lead_operating_mode(user, active=active_semester) if pit_year else 'active'

    if cohort_scope == 'history' or mode == 'audit':
        history_rows, history_counts = _cohort_rows_for_scope(
            user,
            pit_year,
            active_semester,
            historical=True,
            search=search,
            team_status=team_status,
            limit=limit,
        )
        if cohort_scope == 'history':
            return {
                'pit_lead_year': pit_year,
                'active_semester': active_semester.display_name if active_semester else None,
                'operating_mode': mode,
                'operating_message': pit_lead_operating_message(user, active=active_semester),
                'students': history_rows,
                'counts': history_counts,
                'history_students': history_rows,
                'history_counts': history_counts,
            }

    active_rows, active_counts = _cohort_rows_for_scope(
        user,
        pit_year,
        active_semester,
        historical=False,
        search=search,
        team_status=team_status,
        limit=limit,
    )
    history_rows, history_counts = _cohort_rows_for_scope(
        user,
        pit_year,
        active_semester,
        historical=True,
        search=search,
        team_status=team_status,
    )

    students = history_rows if mode == 'audit' else active_rows
    counts = history_counts if mode == 'audit' else active_counts

    return {
        'pit_lead_year': pit_year,
        'active_semester': active_semester.display_name if active_semester else None,
        'operating_mode': mode,
        'operating_message': pit_lead_operating_message(user, active=active_semester),
        'students': students,
        'counts': counts,
        'history_students': history_rows,
        'history_counts': history_counts,
    }


def _pit_lead_overview_payload(user):
    pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
    if not getattr(user, 'is_pit_lead', False) or not pit_year:
        return None

    pit_teams = _pit_teams_queryset(user)
    active_semester = Semester.objects.select_related('school_year').filter(is_active=True).first()

    student_count = 0
    if active_semester:
        student_count = StudentAcademicRecord.objects.filter(
            semester=active_semester,
            year_level=pit_year,
        ).values('student_id').distinct().count()

    pit_team_ids = list(pit_teams.values_list('id', flat=True))
    scheduled_events = DefenseSchedule.objects.filter(
        scope=DefenseSchedule.SCOPE_PIT,
        team_id__in=pit_team_ids,
        status=DefenseSchedule.STATUS_SCHEDULED,
    ).count() if pit_team_ids else 0

    grade_qs = TeamGrade.objects.filter(team_id__in=pit_team_ids) if pit_team_ids else TeamGrade.objects.none()
    pending_grades = grade_qs.exclude(status=TeamGrade.STATUS_PUBLISHED).count() if pit_team_ids else 0
    published_grades = grade_qs.filter(status=TeamGrade.STATUS_PUBLISHED).count() if pit_team_ids else 0
    alerts = []
    active_label = _active_semester_label()
    if active_label == 'Not configured':
        alerts.append({
            'type': 'warning',
            'message': 'No active semester is configured. Set an academic period before managing PIT teams.',
        })
    else:
        alerts.append({
            'type': 'success',
            'message': f'{active_label} is active. PIT workspace is scoped to {pit_year}.',
        })
    if scheduled_events == 0 and pit_teams.exists():
        alerts.append({
            'type': 'warning',
            'message': 'No PIT events scheduled yet. Open Defense Scheduler to plan presentations.',
        })

    recent_pit_teams = [
        _team_payload(team)
        for team in pit_teams.order_by('-updated_at', 'name')[:5]
    ]

    cohort_preview = _pit_lead_cohort_students(user, limit=8)[0]

    return {
        'stats': {
            'students_in_cohort': student_count,
            'pit_teams': pit_teams.count(),
            'scheduled_events': scheduled_events,
            'pending_grades': pending_grades,
            'published_grades': published_grades,
        },
        'alerts': alerts,
        'recent_pit_teams': recent_pit_teams,
        'cohort_preview': cohort_preview,
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


def _student_visible_grade(team, schedule):
    if team is None:
        return None

    if schedule is not None:
        scheduled_grade = (
            TeamGrade.objects.filter(
                team=team,
                semester=schedule.semester,
                scope=schedule.scope,
                stage_label=schedule.stage_label,
                status=TeamGrade.STATUS_PUBLISHED,
            )
            .order_by('-updated_at', '-id')
            .first()
        )
        return scheduled_grade

    return (
        TeamGrade.objects.filter(team=team, status=TeamGrade.STATUS_PUBLISHED)
        .order_by('-updated_at', '-id')
        .first()
    )


class AdminDashboardView(APIView):
    permission_classes = [IsAuthenticated, IsAdminRole]

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


class PitLeadCohortView(APIView):
    permission_classes = [IsAuthenticated, IsPitLead]

    def get(self, request):
        user = request.user
        pit_year, _active = _pit_lead_scope(user)

        search = request.query_params.get('search', '').strip()
        team_status = request.query_params.get('team_status', 'all').strip() or 'all'
        if team_status not in {'all', 'unassigned', 'on_team'}:
            team_status = 'all'
        cohort_scope = request.query_params.get('scope', 'active').strip() or 'active'

        return Response(
            _pit_lead_cohort_payload(
                user,
                search=search,
                team_status=team_status,
                cohort_scope=cohort_scope,
            )
        )


class FacultyDashboardView(APIView):
    """Faculty dashboard: scoped to request.user (advised teams, PIT scope). No cross-adviser PII."""
    permission_classes = [IsAuthenticated, IsFacultyRole]

    def get(self, request):
        user = request.user
        advised_teams = StudentTeam.objects.filter(adviser=user).select_related(
            'semester',
            'semester__school_year',
            'leader',
            'adviser',
        ).prefetch_related('memberships', 'memberships__student', 'deliverable_submissions')
        pit_teams = _pit_teams_queryset(user)
        pit_lead_overview = _pit_lead_overview_payload(user)
        pit_assistant = (
            current_repo_assistant_for_year(user.pit_lead_year)
            if user.is_pit_lead and user.pit_lead_year
            else None
        )

        return Response({
            'faculty': _user_payload(user),
            'roles': _faculty_roles(user),
            'active_roles': _active_role_labels(user),
            'advised_teams': [_team_payload(team) for team in advised_teams],
            'panelist_assignments': [],
            'pit_teams': [_team_payload(team) for team in pit_teams],
            'pit_lead_year': user.pit_lead_year if user.is_pit_lead else None,
            'pit_lead_overview': pit_lead_overview,
            'active_semester': _active_semester_label(),
            'is_repo_assistant': user.is_repo_assistant,
            'repo_assistant_year': getattr(user, 'repo_assistant_year', '') or '',
            'repository_assistant': (
                {
                    'id': pit_assistant.id,
                    'name': _display_name(pit_assistant),
                    'email': pit_assistant.email,
                }
                if pit_assistant
                else None
            ),
        })


class PitLeadRepositoryAssistantView(APIView):
    permission_classes = [IsAuthenticated, IsPitLead]

    def get(self, request):
        from .pit_repository_assistant import repository_assistant_assignment_payload

        return Response(repository_assistant_assignment_payload(request.user))

    def post(self, request):
        from .pit_repository_assistant import assign_repository_assistant

        faculty_id = request.data.get('faculty_id')
        payload = assign_repository_assistant(request.user, faculty_id)
        return Response(payload)


class StudentDashboardView(APIView):
    permission_classes = [IsAuthenticated, IsStudentRole]

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
        grade = _student_visible_grade(team, schedule)
        active_sem = Semester.objects.filter(is_active=True).first()
        from grading.grades.services import (
            canonical_capstone_grade_for_team,
            peer_grading_allowed_for_grade,
            resolve_canonical_capstone_grade,
        )

        peer_grade_row = None
        if team:
            if team.is_capstone:
                peer_grade_row = canonical_capstone_grade_for_team(team, team.semester)
                if peer_grade_row is not None:
                    peer_grade_row = resolve_canonical_capstone_grade(peer_grade_row)
            else:
                peer_grade_row = (
                    TeamGrade.objects.filter(team=team, scope=TeamGrade.SCOPE_PIT)
                    .order_by('-updated_at', '-id')
                    .first()
                )

        peer_eval_on = bool(peer_grade_row and peer_grading_allowed_for_grade(peer_grade_row))
        from grading.grades.peer_eval import (
            is_evaluator_peer_complete,
            is_team_peer_eval_complete,
        )

        peer_eval_complete = bool(
            team and peer_grade_row and is_team_peer_eval_complete(peer_grade_row)
        )
        my_peer_eval_complete = bool(
            team
            and peer_grade_row
            and is_evaluator_peer_complete(peer_grade_row, user)
        )
        adviser_grading_on = getattr(active_sem, 'capstone_adviser_grading_enabled', True) if active_sem else True
        if grade:
            raw_weights = {
                'panel_weight': grade.panel_weight,
                'peer_weight': grade.peer_weight,
                'adviser_weight': grade.adviser_weight,
            }
        elif schedule:
            raw_weights = weights_for_schedule(schedule)
        elif team:
            raw_weights = default_weights(
                TeamGrade.SCOPE_CAPSTONE if team.is_capstone else TeamGrade.SCOPE_PIT
            )
        else:
            raw_weights = default_weights(TeamGrade.SCOPE_CAPSTONE)

        weights = {
            'panel': raw_weights['panel_weight'],
            'peer': raw_weights['peer_weight'],
        }
        if team and team.is_capstone:
            weights['adviser'] = raw_weights['adviser_weight']

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
            'weights': weights,
            'peerEvalEnabled': peer_eval_on,
            'peerEvalComplete': peer_eval_complete,
            'myPeerEvalComplete': my_peer_eval_complete,
            'adviserGradingEnabled': adviser_grading_on,
            'peerCriteria': peer_criteria_payload(team),
            'myPeerSubmissions': peer_submissions_for_evaluator(team, user),
            'myPeerGrade': None,
            'team_name': team_payload['name'] if team_payload else None,
            'project_title': team_payload['projectTitle'] if team_payload else None,
            'status': team_payload['status'] if team_payload else 'No team assigned',
            'final_grade': grade.final_grade if grade else None,
        })


class PanelistDashboardView(APIView):
    permission_classes = [IsAuthenticated, IsPanelist]

    def get(self, request):
        return Response({
            'panelist': _user_payload(request.user),
            'upcoming_defenses': [],
            'assignments': [],
            'results': [],
            'message': 'Panelist assignments will move from the bridge server during the scheduling and grade center phases.',
        })
