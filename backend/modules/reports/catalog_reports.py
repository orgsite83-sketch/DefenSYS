"""Read-only datasets for contextual exports and the Report Center catalog."""

from xml.sax.saxutils import escape

from django.contrib.auth import get_user_model
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from rest_framework.response import Response
from datetime import date

from academic_period_management.models import Semester, SchoolYear
from academic_period_management.services import active_semester
from authentication_access_control.scopes import is_admin_user, is_pit_lead_only, visible_teams_for, visible_schedules_for, grade_records_for
from reports.export_formatters import handle_export_or_preview, generate_xlsx_response
from reports.pdf_builder import DefensysPdfReportBuilder


def name(user):
    return user.get_full_name().strip() or user.username if user else 'Unassigned'


def column(key, label, width=24, **options):
    return {'key': key, 'label': label, 'width': width, **options}


def dataset(title, columns, rows, **options):
    return {'title': title, 'columns': columns, 'rows': rows, **options}


def require_admin(request):
    if not is_admin_user(request.user):
        raise PermissionDenied('This report is available to administrators.')


def require_manager(request):
    if not is_admin_user(request.user) and not is_pit_lead_only(request.user):
        raise PermissionDenied('This report is available to administrators and assigned PIT leads.')
    if is_pit_lead_only(request.user) and not (request.user.pit_lead_year or '').strip():
        raise PermissionDenied('An assigned PIT year is required to export this report.')


def period(request, *, default_active=True):
    value = request.query_params.get('semester_id', '')
    if value:
        if not value.isdigit():
            raise ValidationError({'semester_id': 'Choose a valid academic period.'})
        return get_object_or_404(Semester.objects.select_related('school_year'), pk=value)
    return active_semester() if default_active else None


def team_rows_queryset(request, *, readiness_status=False):
    # List/export share the operating-term and PIT-year visibility rules.
    queryset = visible_teams_for(request.user)
    selected = period(request)
    if selected:
        queryset = queryset.filter(semester=selected)
    scope = request.query_params.get('scope', '')
    if scope in ('capstone', 'pit'):
        queryset = queryset.filter(level__icontains=scope)
    if request.query_params.get('level'):
        queryset = queryset.filter(level__icontains=request.query_params['level'])
    for key in ('year_level', 'section', 'status'):
        if key == 'status' and readiness_status:
            continue
        value = request.query_params.get(key, '')
        if value:
            queryset = queryset.filter(**{key: value})
    search = request.query_params.get('search', '').strip()
    if search:
        queryset = queryset.filter(Q(name__icontains=search) | Q(project_title__icontains=search) | Q(section__icontains=search))
    return queryset


def academic_periods(request):
    require_admin(request)
    years = SchoolYear.objects.prefetch_related('semesters').order_by('-label')
    selected = request.query_params.get('school_year')
    if selected:
        years = years.filter(label=selected)
    rows = []
    for year in years:
        semesters = list(year.semesters.all())
        for sem in semesters or [None]:
            if request.query_params.get('semester_id') and (not sem or str(sem.pk) != request.query_params['semester_id']):
                continue
            rows.append({'school_year': year.label, 'semester': sem.label if sem else 'No semesters configured',
                         'active': 'Active' if sem and sem.is_active else 'Inactive',
                         'phase': sem.get_capstone_program_phase_display() if sem else '',
                         'adviser': sem.capstone_adviser_grading_enabled if sem else None,
                         'peer': sem.capstone_peer_evaluation_enabled if sem else None})
    return dataset('School Year & Semester Register', [column('school_year', 'School Year'), column('semester', 'Semester'),
        column('active', 'Status'), column('phase', 'Capstone Phase'), column('adviser', 'Adviser Grading'), column('peer', 'Peer Evaluation')], rows)


def student_enrollment(request):
    require_admin(request)
    from user_management.academic_records.views import records_queryset, filter_academic_records
    queryset = filter_academic_records(records_queryset(), request.query_params)
    for key, lookup in (('semester_id', 'semester_id'),):
        value = request.query_params.get(key)
        if value:
            queryset = queryset.filter(**{lookup: value})
    rows = [{'student_id': item.student.username, 'name': name(item.student), 'school_year': item.school_year.label,
             'semester': item.semester.label, 'year_level': item.year_level, 'section': item.section,
             'action': item.get_action_display(), 'email': item.student.email} for item in queryset]
    return dataset('Student Enrollment Register', [column('student_id', 'Student ID', 20), column('name', 'Student Name', 32),
        column('school_year', 'School Year', 18), column('semester', 'Semester', 20), column('year_level', 'Year Level', 16),
        column('section', 'Section', 18), column('action', 'Enrollment Action', 20), column('email', 'Email', 34)], rows)


def faculty_directory(request):
    require_admin(request)
    users = get_user_model().objects.exclude(role='student').order_by('username')
    search = request.query_params.get('search', '').strip()
    if search:
        users = users.filter(Q(first_name__icontains=search) | Q(last_name__icontains=search) | Q(username__icontains=search) | Q(email__icontains=search))
    role = request.query_params.get('role', '')
    if role in ('panelist', 'pit_lead', 'adviser', 'documenter', 'uploader'):
        users = users.filter(**{f'is_{role}': True})
    elif role in ('faculty', 'admin'):
        users = users.filter(role__in=['faculty', 'admin']) if role == 'faculty' else users.filter(role='admin')
    if request.query_params.get('status') in ('active', 'inactive'):
        users = users.filter(is_active=request.query_params['status'] == 'active')
    rows = []
    for user in users:
        roles = [label for flag, label in (('is_panelist', 'Panelist'), ('is_adviser', 'Adviser'),
                 ('is_documenter', 'Documenter'), ('is_pit_lead', 'PIT Lead'), ('is_uploader', 'Uploader')) if getattr(user, flag, False)]
        rows.append({'name': name(user), 'username': user.username, 'email': user.email,
                     'role': user.get_role_display(), 'duties': ', '.join(roles) or 'None',
                     'pit_year': user.pit_lead_year or '', 'status': 'Active' if user.is_active else 'Inactive'})
    return dataset('Faculty & Staff Directory', [column('name', 'Name', 32), column('username', 'Username'), column('email', 'Email', 34),
        column('role', 'System Role'), column('duties', 'Assigned Roles', 40), column('pit_year', 'PIT Year'), column('status', 'Status')], rows)


def rubric_reports(request, rubric_id=None):
    from grading.rubrics.views import rubric_queryset_for_read, filter_rubrics
    from grading.rubrics.serializers import RubricSerializer
    if is_pit_lead_only(request.user):
        require_manager(request)
    queryset = filter_rubrics(request, rubric_queryset_for_read(request.user))
    if is_pit_lead_only(request.user):
        queryset = queryset.filter(scope='pit')
    selected = period(request, default_active=False)
    if selected:
        queryset = queryset.filter(semester=selected)
    if rubric_id is not None:
        queryset = queryset.filter(pk=get_object_or_404(queryset, pk=rubric_id).pk)
    rubrics = list(queryset.order_by('name', 'pk'))
    rows, criteria, details = [], [], []
    for rubric, values in zip(rubrics, RubricSerializer(rubrics, many=True).data):
        effective = values.get('weights')
        if rubric.scope == 'pit':
            from defense.scheduler.models import PitEventGradingConfig
            config = PitEventGradingConfig.objects.filter(semester=rubric.semester).filter(Q(panel_rubric=rubric) | Q(peer_rubric=rubric)).first()
            effective = {'panel': config.panel_weight, 'peer': config.peer_weight} if config else None
        weights = ', '.join(f'{key.title()}: {value}%' for key, value in (effective or {}).items()) or 'Not assigned to a grading configuration'
        row = {'name': rubric.name, 'scope': rubric.get_scope_display(), 'semester': rubric.semester.display_name,
               'stage': values.get('event_name') if rubric.scope == 'pit' else values.get('defense_stage_label') or 'All Stages',
               'evaluation_type': rubric.get_evaluation_type_display(), 'target': rubric.get_target_type_display(),
               'status': rubric.get_status_display(), 'criteria': len(values['criteria']), 'weights': weights}
        rows.append(row)
        details.append({'rubric': row, 'criteria': list(rubric.criteria.all())})
        for criterion in rubric.criteria.all():
            description = criterion.description or ''
            parts = [description[i:i + 1000] for i in range(0, len(description), 1000)] or ['']
            for index, part in enumerate(parts):
                criteria.append({'rubric': rubric.name, 'criterion': criterion.name, 'description': part,
                                 'part': index + 1, 'order': criterion.display_order, 'scale': criterion.get_scale_display(),
                                 'max_score': criterion.max_score, 'weight': str(criterion.weight),
                                 'target': criterion.get_target_type_display()})
    criteria_columns = [column('rubric', 'Rubric', 32), column('criterion', 'Criterion', 32), column('description', 'Description', 66),
        column('part', 'Text Part', 12), column('order', 'Order', 12), column('scale', 'Scoring Scale', 22),
        column('max_score', 'Maximum Score', 18), column('weight', 'Criterion Weight', 18), column('target', 'Target', 20)]
    return dataset('Rubric Details' if rubric_id else 'Rubric Catalog', [column('name', 'Rubric', 34), column('scope', 'Scope', 16),
        column('semester', 'Academic Period', 36), column('stage', 'Stage / Event', 28), column('evaluation_type', 'Evaluator Type', 20),
        column('target', 'Target', 18), column('status', 'Status', 18), column('criteria', 'Criteria', 12), column('weights', 'Grade Distribution', 38)],
        rows, details=details, extra_sheets=[{'name': 'Criteria', 'title': 'Complete Rubric Criteria', 'metadata': [],
                                            'columns': criteria_columns, 'rows': criteria}],
        sections=[{'title': 'Complete Rubric Criteria', 'columns': criteria_columns, 'rows': criteria}])


def project_records(request):
    require_manager(request)
    from repository.project_archive.services import scoped_entries, filter_entries, augment_deliverable_missing_rows
    entries, visibility = scoped_entries(request.user, request=request)
    params = request.query_params.copy()
    if params.get('scope') in ('capstone', 'pit') and not params.get('type'):
        params['type'] = params['scope']
    if visibility['scope'] != 'admin':
        params['type'] = 'pit'
    if params.get('deliverable_id') and visibility['scope'] == 'admin':
        entries = augment_deliverable_missing_rows(entries, params['deliverable_id'], params.get('stage', ''))
    entries = filter_entries(entries, params)
    rows = []
    for entry in entries:
        uploaded = entry.get('uploaded_at')
        if hasattr(uploaded, 'isoformat'):
            uploaded = uploaded.isoformat()
        rows.append({'scope': (entry.get('type') or '').title(), 'file_name': entry.get('file_name') or 'Not uploaded',
                     'deliverable': entry.get('deliverable_label') or '', 'team': entry.get('team_name') or 'Unassigned',
                     'year_level': entry.get('year_level'), 'academic_year': entry.get('academic_year'),
                     'semester': entry.get('semester'), 'stage': entry.get('stage'), 'status': entry.get('status'),
                     'uploader': entry.get('uploaded_by') or 'Not recorded', 'uploaded_at': uploaded or ''})
    return dataset('Project Archive Register', [column('scope', 'Scope', 14), column('file_name', 'File Name', 52),
        column('deliverable', 'Deliverable', 32), column('team', 'Team', 30), column('year_level', 'Year Level', 16),
        column('academic_year', 'School Year', 18), column('semester', 'Semester', 20), column('stage', 'Stage / Event', 28),
        column('status', 'Status', 20), column('uploader', 'Uploaded By', 30),
        column('uploaded_at', 'Uploaded At', 24, type='datetime', number_format='m/d/yyyy hh:mm')], rows)


def external_evaluators(request):
    require_manager(request)
    from user_management.external_evaluators import visible_evaluators, evaluator_payload, visible_invitations, invitation_schedules, invitation_is_available
    data = {'evaluators': [evaluator_payload(item) for item in visible_evaluators(request.user)]}
    search = request.query_params.get('search', '').strip().lower()
    status = request.query_params.get('status', '')
    rows = []
    assignments = []
    assignment_view = request.query_params.get('view') == 'assignments'
    selected = period(request, default_active=False)
    for item in data['evaluators']:
        if not assignment_view and search and search not in ' '.join(str(item.get(key, '')) for key in ('name', 'email', 'institution')).lower():
            continue
        if status and item['status'] != status:
            continue
        rows.append({'name': item['name'], 'email': item.get('email'), 'institution': item.get('institution'),
                     'status': item['status'].title(), 'active': 'Active' if item.get('is_active') else 'Inactive'})
    exported_evaluators = {row['name'] for row in rows}
    for invitation in visible_invitations(request.user):
        evaluator_name = invitation.evaluator.name if invitation.evaluator_id else invitation.guest_name
        if assignment_view and search and search not in f'{invitation.guest_name} {invitation.email} {invitation.evaluator.institution if invitation.evaluator_id else ""}'.lower():
            continue
        if not assignment_view and evaluator_name not in exported_evaluators:
            continue
        for schedule in invitation_schedules(invitation):
                if selected and schedule.semester_id != selected.pk:
                    continue
                assignments.append({'evaluator': invitation.guest_name or evaluator_name, 'team': schedule.team.name, 'stage': schedule.stage_label,
                                    'date': schedule.scheduled_date.isoformat(), 'time': schedule.start_time.strftime('%H:%M'),
                                    'room': schedule.room, 'active': 'Active' if invitation_is_available(invitation) else 'Expired / revoked'})
    assignment_columns = [column('evaluator', 'Evaluator', 32), column('team', 'Team', 30), column('stage', 'Stage / Event', 30),
                          column('date', 'Date', 18), column('time', 'Time', 18), column('room', 'Room'), column('active', 'Assignment Status')]
    if assignment_view:
        return dataset('External Evaluator Defense Assignments', assignment_columns, assignments)
    return dataset('External Evaluators & Defense Assignments', [column('name', 'Evaluator', 32), column('email', 'Email', 34),
        column('institution', 'Institution', 36), column('status', 'Approval Status'), column('active', 'Account Status')], rows,
        extra_sheets=[{'name': 'Defense Assignments', 'title': 'Defense Assignments', 'metadata': [], 'columns': assignment_columns, 'rows': assignments}],
        sections=[{'title': 'Defense Assignments', 'columns': assignment_columns, 'rows': assignments}])


def setup_report(request, *, pit=False):
    from defense.stages.models import DefenseStage, StageGradingConfig
    from defense.scheduler.models import PitEventGradingConfig
    from repository.project_archive.services import pit_event_matches_year_level
    require_manager(request) if pit else require_admin(request)
    selected = period(request)
    rows, requirements = [], []
    if pit:
        items = PitEventGradingConfig.objects.select_related('semester__school_year', 'panel_rubric', 'peer_rubric').prefetch_related('deliverables')
        if selected:
            items = items.filter(semester=selected)
    else:
        items = DefenseStage.objects.prefetch_related('deliverables').order_by('display_order', 'pk')
    for item in items:
        label = item.event_name if pit else item.label
        if is_pit_lead_only(request.user) and not pit_event_matches_year_level(label, request.user.pit_lead_year):
            continue
        search = request.query_params.get('search', '').strip().lower()
        if search and search not in label.lower():
            continue
        if request.query_params.get('stage') and request.query_params['stage'] != label:
            continue
        config = item if pit else StageGradingConfig.objects.filter(defense_stage=item, semester=selected).select_related('panel_rubric', 'adviser_rubric', 'peer_rubric').first()
        row = {'stage': label, 'scope': 'PIT' if pit else 'Capstone', 'semester': item.semester.display_name if pit else selected.display_name if selected else 'No active semester',
               'status': 'Officially complete' if config and config.is_officially_complete else 'Configured' if config else 'Not configured',
               'requirements': len(item.deliverables.all()), 'panel': name_rubric(config, 'panel'),
               'adviser': 'Not applicable' if pit else name_rubric(config, 'adviser'), 'peer': name_rubric(config, 'peer'),
               'weights': ', '.join(f'{role.title()}: {getattr(config, role + "_weight", 0)}%' for role in (('panel', 'peer') if pit else ('panel', 'adviser', 'peer'))) if config else 'Not configured'}
        rows.append(row)
        for deliverable in item.deliverables.all():
            requirements.append({'stage': label, 'code': deliverable.deliverable_id, 'label': deliverable.label,
                                 'type': deliverable.get_deliverable_type_display(), 'required': deliverable.required})
    requirement_columns = [column('stage', 'Stage / Event', 30), column('code', 'Deliverable Code', 22),
                           column('label', 'Requirement', 44), column('type', 'Submission Phase'), column('required', 'Required', 16)]
    return dataset('PIT Event Configuration & Requirements' if pit else 'Defense Stage Configuration & Requirements',
        [column('stage', 'Stage / Event', 30), column('scope', 'Scope', 14), column('semester', 'Academic Period', 36),
         column('status', 'Setup Status'), column('requirements', 'Requirements', 16), column('panel', 'Panel Rubric', 34),
         column('adviser', 'Adviser Rubric', 34), column('peer', 'Peer Rubric', 34), column('weights', 'Grade Distribution', 38)], rows,
        extra_sheets=[{'name': 'Requirements', 'title': 'Deliverable Requirements', 'metadata': [], 'columns': requirement_columns, 'rows': requirements}],
        sections=[{'title': 'Deliverable Requirements', 'columns': requirement_columns, 'rows': requirements}])


def name_rubric(config, role):
    rubric = getattr(config, f'{role}_rubric', None) if config else None
    return rubric.name if rubric else 'Not assigned'


def readiness(request):
    require_manager(request)
    from defense.scheduler.serializers import ScheduleTeamSerializer
    from repository.deliverables.services import required_complete
    from student_teams.services import stage_progression_blocker
    from defense.stages.models import DefenseStage
    rows = []
    selected_stage = request.query_params.get('stage', '')
    stages = list(DefenseStage.objects.filter(is_active=True).order_by('display_order', 'pk'))
    for team in team_rows_queryset(request, readiness_status=True).prefetch_related('stage_progress__defense_stage', 'defense_schedules__defense_stage'):
        # Only invoke read-only serializer methods; eligible_stages can normalize
        # stored schedules, and report generation must never perform that write.
        serializer = ScheduleTeamSerializer()
        statuses = serializer.get_stage_progress(team)
        labels = [selected_stage] if selected_stage else [stage.label for stage in stages] if team.is_capstone else list(statuses) or [team.ready_for_stage or 'PIT event not configured']
        for label in labels:
            status = statuses.get(label, 'pending')
            if request.query_params.get('status') and request.query_params['status'] != status:
                continue
            stage = next((item for item in stages if item.label == label), None) if team.is_capstone else None
            blocker = stage_progression_blocker(team, stage) if stage else ''
            complete = required_complete(team, label) if stage or label != 'PIT event not configured' else False
            if status == 'ready' and (blocker or not complete):
                status = 'pending'
            outstanding = '' if status == 'completed' else blocker or ('Pre-defense submissions are incomplete.' if not complete else 'Awaiting endorsement.' if status == 'pending' else '')
            rows.append({'team': team.name, 'project': team.project_title, 'scope': 'Capstone' if team.is_capstone else 'PIT',
                         'year_level': team.year_level, 'section': team.section, 'stage': label,
                         'status': status.replace('_', ' ').title(), 'complete': complete, 'outstanding': outstanding})
    return dataset('Pre-Defense Readiness Register', [column('team', 'Team', 30), column('project', 'Project', 40), column('scope', 'Scope', 14),
        column('year_level', 'Year Level', 16), column('section', 'Section'), column('stage', 'Stage / Event', 30),
        column('status', 'Readiness Status', 24), column('complete', 'Pre-Defense Complete', 22), column('outstanding', 'Outstanding Requirements', 52)], rows)


def overview(request):
    require_manager(request)
    teams = team_rows_queryset(request)
    schedules = visible_schedules_for(request.user).filter(team__in=teams)
    grades = grade_records_for(request.user).filter(team__in=teams)
    rows = [{'metric': 'Student teams', 'value': teams.count()}, {'metric': 'Scheduled defenses', 'value': schedules.filter(status='scheduled').count()},
            {'metric': 'Completed defenses', 'value': schedules.filter(status='done').count()},
            {'metric': 'Published assessment records', 'value': grades.filter(status='published').count()},
            {'metric': 'Teams without an adviser', 'value': teams.filter(adviser__isnull=True).count()}]
    return dataset('Academic Overview Summary', [column('metric', 'Metric', 48), column('value', 'Count', 22)], rows)


def curriculum(request):
    require_admin(request)
    from curriculum_analytics.services import analytics_payload
    data = analytics_payload(request.user, **{key: request.query_params.get(key) or None for key in ('academic_year', 'program', 'scope', 'rubric_id', 'stage_id')})
    rows = []
    for item in data['competency_matrix']:
        rows.append({'criterion': item.get('criterion') or item.get('name') or item.get('label', ''),
                     'score': item.get('average_score'), 'rubric': item.get('rubric_name', ''),
                     'evaluations': item.get('evaluations_count', ''), 'gap': item.get('status', '')})
    metrics = [{'metric': key.replace('_', ' ').title(), 'value': value} for key, value in data['kpi_summary'].items() if isinstance(value, (str, int, float, bool))]
    metric_columns = [column('metric', 'Metric', 42), column('value', 'Recorded Value', 36)]
    return dataset('Curriculum Summary & Criterion Coverage', [column('criterion', 'Criterion', 42), column('score', 'Average Score', 20),
        column('rubric', 'Rubric', 34), column('evaluations', 'Evaluations', 18), column('gap', 'Coverage Gap', 34)], rows,
        sections=[{'title': 'Curriculum Summary', 'columns': metric_columns, 'rows': metrics}],
        extra_sheets=[{'name': 'Summary', 'title': 'Curriculum Summary', 'metadata': [], 'columns': metric_columns, 'rows': metrics}])


BUILDERS = {'academic-periods': academic_periods, 'student-enrollment': student_enrollment, 'faculty-directory': faculty_directory,
            'rubrics': rubric_reports, 'project-records': project_records, 'external-evaluators': external_evaluators,
            'defense-stage-setup': setup_report, 'pit-event-setup': lambda request: setup_report(request, pit=True),
            'readiness': readiness, 'overview': overview, 'curriculum-summary': curriculum}


def validate_filters(params):
    for key in ('semester_id', 'rubric_id', 'team_id', 'student_id', 'stage_id', 'grade_id'):
        value = params.get(key)
        if value and (not value.isdigit() or int(value) < 1):
            raise ValidationError({key: 'Choose a valid record.'})
    for key in ('start_date', 'end_date', 'date'):
        value = params.get(key)
        if value:
            try:
                date.fromisoformat(value)
            except ValueError:
                raise ValidationError({key: 'Use a valid date in YYYY-MM-DD format.'})


class CatalogOptionsView(APIView):
    """Names for selectors, with the same visibility as their report endpoints."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from grading.rubrics.views import rubric_queryset_for_read
        from defense.stages.models import DefenseStage
        validate_filters(request.query_params)
        teams = visible_teams_for(request.user)
        rubrics = rubric_queryset_for_read(request.user)
        if is_pit_lead_only(request.user):
            require_manager(request)
            rubrics = rubrics.filter(scope='pit')
        students = get_user_model().objects.filter(Q(team_memberships__team__in=teams) | Q(led_teams__in=teams)).distinct()
        return Response({
            'semesters': [{'id': item.pk, 'label': item.display_name} for item in Semester.objects.select_related('school_year').order_by('-school_year__label', 'label')],
            'rubrics': [{'id': item.pk, 'label': f'{item.name} — {item.semester.display_name}', 'semester_id': item.semester_id, 'scope': item.scope} for item in rubrics],
            'teams': [{'id': item.pk, 'label': f'{item.name} — {item.project_title}', 'semester_id': item.semester_id, 'scope': 'capstone' if item.is_capstone else 'pit'} for item in teams],
            'students': [{'id': item.pk, 'label': f'{name(item)} ({item.username})'} for item in students],
            'stages': [{'id': item.pk, 'label': item.label} for item in DefenseStage.objects.filter(is_active=True).order_by('display_order')],
        })


def render_pdf(spec, metadata, generated_by, include_signatures, signatories):
    detailed = bool(spec.get('details'))
    builder = DefensysPdfReportBuilder(title=spec['title'], generated_by=generated_by,
        orientation='portrait' if detailed else 'landscape', show_sidebar=False)
    builder.add_header()
    builder.add_metadata_grid([(escape(item['label']), escape(str(item['value']))) for item in metadata])
    if detailed:
        for detail in spec['details']:
            row = detail['rubric']
            builder.add_section_header(escape(row['name']))
            builder.add_paragraph(escape(f'{row["scope"]} / {row["semester"]} / {row["stage"]} / {row["status"]}'))
            builder.add_paragraph(escape(f'{row["evaluation_type"]} / {row["target"]} / {row["weights"]}'))
            for criterion in detail['criteria']:
                builder.add_subsection_header(escape(criterion.name))
                builder.add_paragraph(escape(f'{criterion.get_scale_display()} / Maximum: {criterion.max_score} / Weight: {criterion.weight} / {criterion.get_target_type_display()}'))
                if criterion.description:
                    builder.add_paragraph(escape(criterion.description).replace('\n', '<br/>'))
    else:
        for section in [spec, *spec.get('sections', [])]:
            builder.add_section_header(escape(section['title']))
            if not section['rows']:
                builder.add_paragraph('No records match the selected filters.')
                continue
            columns = section['columns']
            total = sum(item['width'] for item in columns)
            widths = [builder.usable_width * item['width'] / total for item in columns]
            rows = [[escape(str(row.get(item['key'], '') if row.get(item['key']) is not None else 'Not recorded')).replace('\n', '<br/>') for item in columns] for row in section['rows']]
            builder.add_table([escape(item['label']) for item in columns], rows, col_widths=widths, repeat_headers=True)
    builder.add_signatures(include_signatures=include_signatures, signatories=signatories, prepared_by=generated_by)
    return builder.build()


class CatalogReportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, report_kind, rubric_id=None):
        validate_filters(request.query_params)
        spec = rubric_reports(request, rubric_id) if rubric_id is not None else BUILDERS[report_kind](request)
        generated_by = name(request.user)
        metadata = [{'label': 'Records', 'value': len(spec['rows'])}, {'label': 'Generated by', 'value': generated_by},
                    {'label': 'Time Zone', 'value': timezone.get_current_timezone_name()}]
        for key, value in request.query_params.items():
            if value and key not in ('export_format', 'format', 'include_signatures', 'signatories', 'page', 'page_size', 'source'):
                if key == 'semester_id':
                    value = period(request, default_active=False).display_name
                elif key == 'rubric_id':
                    from grading.rubrics.views import rubric_queryset_for_read
                    value = get_object_or_404(rubric_queryset_for_read(request.user), pk=value).name
                elif key == 'team_id':
                    value = get_object_or_404(visible_teams_for(request.user), pk=value).name
                elif key.endswith('_id'):
                    continue
                metadata.append({'label': key.replace('_', ' ').title(), 'value': value})
        if is_pit_lead_only(request.user):
            metadata += [{'label': 'Scope', 'value': 'PIT'}, {'label': 'Assigned Year', 'value': request.user.pit_lead_year}]
        from reports.views import _parse_signature_params
        include_signatures, signatories = _parse_signature_params(request)
        filename = f'DefenSYS_{spec["title"].replace(" ", "_").replace("&", "and")}_{timezone.localdate():%Y-%m-%d}'
        export_format = request.query_params.get('export_format') or request.query_params.get('format')
        if (export_format or '').lower() in ('xlsx', 'excel', 'sheet'):
            return generate_xlsx_response(spec['title'], metadata, spec['columns'], spec['rows'], filename,
                extra_sheets=spec.get('extra_sheets'), generated_by=generated_by,
                include_signatures=include_signatures, signatories=signatories)
        return handle_export_or_preview(export_format, spec['title'], 'Filtered records from DefenSYS',
            [{'label': 'Records', 'value': str(len(spec['rows']))}], metadata, spec['columns'], spec['rows'], filename,
            lambda: render_pdf(spec, metadata, generated_by, include_signatures, signatories),
            sections=spec.get('sections'), generated_by=generated_by, include_signatures=include_signatures, signatories=signatories)
