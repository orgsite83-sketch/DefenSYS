"""Operational notices never disclose an un-released academic decision."""
def changed(appointment_id, actor_id, action):
    from django.contrib.auth import get_user_model
    from notifications.models import Notification, NotificationCategory
    from grading.grades.dissemination_models import OutcomeRelease
    from .models import ReDemoAppointment
    demo = ReDemoAppointment.objects.select_related('source__schedule__team').get(pk=appointment_id)
    schedule = demo.source.schedule
    targets = {(pk, 'panelist') for pk in demo.panelists.values_list('pk', flat=True)}
    if schedule.team.adviser_id:
        targets.add((schedule.team.adviser_id, 'adviser'))
    releases = OutcomeRelease.objects.filter(control__schedule=schedule,
        snapshot__panel_decision__id=demo.source_id, snapshot__panel_decision__revision=demo.source_revision)
    for release in releases:
        targets |= {(pk, 'student') for pk in release.recipient_ids}
    users = {row.pk: row for row in get_user_model().objects.filter(pk__in={pk for pk, _ in targets}, is_active=True)}
    for pk, workspace in sorted(targets):
        person = users.get(pk)
        if not person:
            continue
        if person.role == 'admin':
            workspace = 'admin'
        Notification.objects.create(recipient=person, sender_id=actor_id,
            title=f'Re-demo {action.replace("_", " ")}',
            message=f'{schedule.team.name}: {demo.scheduled_date} {demo.start_time}, {demo.room}.',
            category=NotificationCategory.DEFENSE, workspace=workspace,
            action_route={'panelist': '/panelist', 'admin': '/admin/defense-board',
                          'student': '/student'}.get(workspace, '/faculty/defense-board'),
            action_payload={'activity_type': 're_demo', 'activity_id': f'redemo:{demo.pk}',
                're_demo_id': demo.pk, 'source_schedule_id': schedule.pk, 'team_id': schedule.team_id})
    from realtime.broadcast import notify_capstone_evaluation_flags
    notify_capstone_evaluation_flags(schedule.semester)
