"""Read-only Team Details summaries; workflow decisions stay in their services."""
from django.db.models import Q
from rest_framework.exceptions import ValidationError


def pit_progress(team, request):
    from defense.scheduler.event_scope import pit_events_for_team, pit_events_for_user
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade
    from .serializers import StudentTeamSerializer

    assigned = set(pit_events_for_team(team).values_list('pk', flat=True))
    historical = TeamGrade.objects.filter(team=team, scope='pit', semester_id=team.semester_id)
    event_ids = historical.values_list('pit_event_config_id', flat=True)
    labels = historical.filter(pit_event_config__isnull=True).values_list('stage_label', flat=True)
    events = list(pit_events_for_user(request.user, semester=team.semester,
        workspace=request.query_params.get('workspace')).filter(year_level=team.year_level).filter(
        Q(pk__in=assigned) | Q(pk__in=event_ids) | Q(event_name__in=labels)).order_by('pk'))
    selected = None
    raw_id = request.query_params.get('event_id')
    label = request.query_params.get('event_name') or request.query_params.get('stage')
    if raw_id:
        try:
            selected = next((e for e in events if e.pk == int(raw_id)), None)
        except ValueError:
            raise ValidationError({'event_id': 'Choose a valid assigned event.'})
    elif label:
        selected = next((e for e in events if e.event_name.casefold() == label.casefold()), None)
    if (raw_id or label) and selected is None:
        raise ValidationError({'event_id': 'This event is not available for this team.'})
    selected = selected or next((e for e in events if e.event_name == team.current_defense_stage),
                               events[0] if events else None)

    schedules = list(DefenseSchedule.objects.filter(team=team, semester_id=team.semester_id,
        scope='pit', project_version=team.project_version,
        status__in=('scheduled', 'done', 'archived')).order_by('scheduled_date', 'start_time', 'pk'))
    serializer = StudentTeamSerializer(context={'user': request.user})
    rows = []
    for event in events:
        slots = [s for s in schedules if s.event_name.casefold() == event.event_name.casefold()]
        schedule = next((s for s in slots if s.status == 'scheduled'), slots[-1] if slots else None)
        rows.append({
            'id': event.pk, 'event_name': event.event_name, 'semester_id': team.semester_id,
            'display_semester': team.semester.display_name, 'year_level': event.year_level,
            'historical': event.pk not in assigned,
            'is_officially_complete': event.is_officially_complete,
            'context': serializer._pit_event_defense_context(team, event),
            'schedule': None if schedule is None else {
                'id': schedule.pk, 'scheduled_date': schedule.scheduled_date.isoformat(),
                'start_time': schedule.start_time.isoformat(), 'room': schedule.room,
                'status': schedule.status,
            },
        })
    return selected, rows


def legacy_counts(team, user):
    from .documents.views import team_document_queryset_for_user
    counts = {'legacy_documents_count': team_document_queryset_for_user(user, team.pk).count(),
              'legacy_reports_count': 0}
    if team.is_capstone:
        from .weekly_progress.access import reports_for
        counts['legacy_reports_count'] = reports_for(user).filter(team=team, period__isnull=True).count()
    return counts
