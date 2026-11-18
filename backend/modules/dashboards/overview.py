"""Read-only active-term overview. Legacy dashboard counters remain compatible."""
from django.utils import timezone


def admin_overview(semester, stages, legacy_items, ready_count):
    from defense.stages.readiness import stage_setup_readiness
    from student_teams.models import StudentTeam
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade
    from grading.grades.services import grade_review_queryset
    from user_management.academic_records.models import StudentAcademicRecord

    teams = StudentTeam.objects.filter(semester=semester) if semester else StudentTeam.objects.none()
    grades = TeamGrade.objects.filter(semester=semester) if semester else TeamGrade.objects.none()
    schedules = DefenseSchedule.objects.filter(semester=semester, status='scheduled') if semester else DefenseSchedule.objects.none()
    items = [dict(item) for item in legacy_items if item['id'] in ('pending_panelist_requests', 'no_active_period')]
    for stage in stages if semester else []:
        config = stage.active_configs[0] if getattr(stage, 'active_configs', None) else None
        if config and config.is_officially_complete:
            continue
        readiness = stage_setup_readiness(stage, config, semester)
        if readiness['ready']:
            continue
        issues = readiness['issues']
        tab = 1 if any('rubric' in issue.lower() or 'grading' in issue.lower() or 'weights' in issue.lower() for issue in issues) else 2 if any('submission' in issue.lower() for issue in issues) else 0
        items.append({'id': f'stage_setup:{stage.pk}', 'title': stage.label,
            'description': 'Missing required evaluation rubrics' if tab == 1 else issues[0], 'reasons': issues, 'scope': 'capstone',
            'severity': 'danger', 'category_label': 'STAGE SETUP', 'target_section': 'defenseStages',
            'target_route': f'/admin/defense-stages/{stage.pk}/edit?tab={tab}&semester_id={semester.pk}&fromOverview=1',
            'button_label': 'Fix rubric' if tab == 1 else 'Review requirements' if tab == 2 else 'Review stage'})
    missing_advisers = teams.filter(level__icontains='Capstone', adviser__isnull=True).count()
    if missing_advisers:
        items.append({'id': 'unassigned_advisers', 'title': f'{missing_advisers} Capstone teams need an adviser',
            'description': 'Assign advisers to the affected current-semester teams.', 'scope': 'capstone',
            'target_section': 'studentTeams', 'button_label': 'Assign adviser', 'severity': 'warning'})
    if ready_count:
        items.append({'id': 'unscheduled_ready_teams', 'title': f'{ready_count} Capstone teams ready to schedule',
            'description': 'Review the current readiness queue.', 'scope': 'capstone',
            'target_section': 'defenseBoardReadiness', 'button_label': 'Review readiness', 'severity': 'action'})
    pending = grade_review_queryset(grades).exclude(status=TeamGrade.STATUS_PUBLISHED)
    for scope in ('capstone', 'pit'):
        count = pending.filter(scope=scope).count()
        if count:
            items.append({'id': f'pending_grades:{scope}', 'title': f'{count} {scope.upper()} grades need review',
                'description': 'Review the applicable assessment before publication.', 'scope': scope,
                'target_section': 'gradeCenter', 'button_label': 'Review grades', 'severity': 'warning'})
    # Reuse the release service, including evaluator completion, holds, deadline
    # and recipient checks. Never report a partial sample as a semester total.
    release_summaries = {}
    for program in ('capstone', 'pit'):
        candidates = list(grades.filter(scope=program, schedule__isnull=False)
                          .select_related('team', 'semester', 'schedule').order_by('pk')[:21])
        release_summaries[program] = None
        if len(candidates) <= 20:
            from grading.grades.dissemination import hydrate, reviewed_entry
            entries = [reviewed_entry(grade) for grade in hydrate(candidates)] if candidates else []
            summary = {
                'ready': sum(entry['metadata']['can_release'] and bool(entry['recipient_ids']) for entry in entries),
                'released': sum(entry['metadata']['status'] == 'released' for entry in entries),
            }
            release_summaries[program] = summary
            if summary['ready']:
                items.append({'id': f'outcomes_ready:{program}', 'title': f"{summary['ready']} {program.title()} outcomes ready for release",
                    'description': 'Review eligible outcomes before dissemination.', 'scope': program,
                    'target_section': 'gradeCenter', 'button_label': 'Review outcomes', 'severity': 'warning'})
    release_summary = release_summaries['capstone']
    priority = {'danger': 0, 'warning': 1, 'action': 2}
    items.sort(key=lambda item: priority.get(item.get('severity'), 3))
    counts = {}
    for item in items:
        section = item['target_section']
        counts[section] = counts.get(section, 0) + 1
    totals = {}
    for scope in ('all', 'capstone', 'pit'):
        scoped_teams = teams if scope == 'all' else teams.filter(level__icontains=scope)
        scoped_schedules = schedules if scope == 'all' else schedules.filter(scope=scope)
        totals[scope] = {'teams': scoped_teams.count(), 'scheduled': scoped_schedules.count(),
            'scheduled_teams': scoped_schedules.values('team_id').distinct().count(),
            'ready': ready_count if scope != 'pit' else None}
    # Cohort reads stay bounded independently of roster size. Do not apply
    # Capstone eligibility rules to PIT or invent setup/completion states.
    from django.contrib.auth import get_user_model
    from defense.scheduler.models import PitEventGradingConfig
    from django.db.models import Count
    event_counts = dict(PitEventGradingConfig.objects.filter(semester=semester)
                        .values('year_level').annotate(total=Count('pk')).values_list('year_level', 'total')) if semester else {}
    users = get_user_model()
    leads = list(users.objects.filter(is_active=True, is_pit_lead=True)
                 .values('first_name', 'last_name', 'pit_lead_year'))
    pit_cohorts = []
    for year in ('1st Year', '2nd Year', '3rd Year'):
        events = PitEventGradingConfig.objects.filter(semester=semester, year_level=year) if semester else PitEventGradingConfig.objects.none()
        booked = schedules.filter(scope='pit', team__year_level=year).order_by('scheduled_date', 'start_time')
        next_booking = booked.filter(scheduled_date__gte=timezone.localdate()).values('scheduled_date', 'start_time').first()
        pit_cohorts.append({'year': year,
            'leads': [' '.join(filter(None, (lead['first_name'], lead['last_name']))) for lead in leads if lead['pit_lead_year'] == year],
            'teams': teams.filter(level__icontains='PIT', year_level=year).count(),
            'event_count': event_counts.get(year, 0),
            'events': list(events.order_by('id').values('id', 'event_name', 'is_officially_complete')[:20]),
            'next_defense': next_booking['scheduled_date'].isoformat() if next_booking else None})
    capstone = totals['capstone']
    setup_count = sum(item['id'].startswith('stage_setup:') for item in items)
    review_count = pending.filter(scope='capstone').count()
    students = StudentAcademicRecord.objects.filter(semester=semester, student__is_active=True).values('student_id').distinct().count() if semester else 0
    workflow = [
        {'title': 'Users', 'value': str(students) if semester else '—', 'label': 'Enrolled students', 'detail': 'All years · Active semester', 'status': 'Manage enrollment' if students else 'No enrollment records' if semester else 'No active semester', 'action': False, 'section': 'userManagement'},
        {'title': 'Stage setup', 'value': f'{len(stages) - setup_count} / {len(stages)}', 'label': 'Stages configured', 'detail': f'{setup_count} stages need setup', 'status': f'{setup_count} setup actions' if setup_count else 'No reported setup issues' if stages else 'No stages configured', 'action': bool(setup_count), 'section': 'defenseStages'},
        {'title': 'Teams', 'value': str(capstone['teams']), 'label': 'Active teams', 'detail': f"Advisers: {capstone['teams'] - missing_advisers} assigned · {missing_advisers} unassigned", 'status': 'Assignment needed' if missing_advisers else 'Advisers assigned', 'action': bool(missing_advisers), 'section': 'studentTeams'},
        {'title': 'Scheduling', 'value': str(capstone['scheduled_teams']), 'label': 'Teams scheduled', 'detail': f'{ready_count} ready to schedule', 'status': 'Ready for action' if ready_count else 'Defenses scheduled' if capstone['scheduled_teams'] else 'Waiting for teams', 'action': bool(ready_count), 'section': 'defenseBoardSchedules'},
        {'title': 'Results', 'value': str(release_summary['ready']) if release_summary is not None else '—', 'label': 'Ready for release', 'detail': f"{review_count} assessments need review · " + (f"{release_summary['released']} released" if release_summary is not None else 'Open grades for release eligibility'), 'status': 'Needs review' if review_count else 'Ready for action' if release_summary and release_summary['ready'] else 'No release action' if release_summary is not None else 'Summary unavailable', 'action': bool(review_count or release_summary and release_summary['ready']), 'section': 'gradeCenter'},
    ]
    return {'semester_id': semester.pk if semester else None, 'generated_at': timezone.now().isoformat(),
        'action_items': items, 'action_counts': counts, 'totals': totals, 'students': students,
        'stage_count': len(stages), 'workflow': workflow, 'pit_cohorts': pit_cohorts,
        'missing_advisers': missing_advisers,
        'partial': any(summary is None for summary in release_summaries.values())}
