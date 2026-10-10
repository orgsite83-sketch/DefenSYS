"""Resolve workflow state from domain records; reading never completes an action.

One query per target kind for an entire notification page, rather than per row.
This resolver does not create minutes or otherwise write to workflow records.
"""
from authentication_access_control.scopes import is_admin_user
from urllib.parse import urlencode


def target(notification):
    payload = notification.action_payload or {}
    kind = payload.get('action_kind')
    if payload.get('team_id') and payload.get('stage_label'):
        kind = kind or 'deliverables'
    if payload.get('panelist_eligibility') and payload.get('request_id'):
        kind = 'panelist_request'
    if notification.category in ('MINUTES', 'DEFENSE') and payload.get('schedule_id'):
        kind = kind or {
            'minutes ready for review': 'minutes_adviser',
            'minutes awaiting final signature': 'minutes_chairman',
            'documenter assignment': 'minutes_documenter',
            'minutes finalized': 'minutes_finalized',
        }.get(notification.title.lower())
    key = 'request_id' if kind == 'panelist_request' else 'evaluator_id' if kind == 'external_evaluator' else 'team_id' if kind == 'deliverables' else 'schedule_id'
    value = payload.get(key)
    return kind, value if isinstance(value, int) and not isinstance(value, bool) and value > 0 else None


def _state(status, label, route=None, cta=None, completed_at=None):
    return {'status': status, 'label': label, 'is_complete': status == 'completed',
            'route': route, 'cta': cta,
            'completed_at': completed_at.isoformat() if completed_at else None}


def resolve_actions(notifications, actor):
    from user_management.models import PanelistEligibilityRequest, ExternalEvaluator
    from defense.scheduler.models import DefenseSchedule
    from defense.minutes.models import DefenseMinutes

    notifications = list(notifications)
    targets = {n.pk: target(n) for n in notifications}
    def ids(kind):
        return {pk for current, pk in targets.values() if current == kind and pk}
    requests = PanelistEligibilityRequest.objects.filter(pk__in=ids('panelist_request'))
    evaluators = ExternalEvaluator.objects.filter(pk__in=ids('external_evaluator'))
    admin = is_admin_user(actor)
    if not admin:
        requests = requests.filter(requested_by=actor)
        evaluators = evaluators.filter(created_by=actor)
    requests = {r.pk: r for r in requests}
    evaluators = {e.pk: e for e in evaluators}
    minutes_ids = {pk for kind, pk in targets.values() if kind and kind.startswith('minutes_') and pk}
    schedules = {s.pk: s for s in DefenseSchedule.objects.filter(pk__in=minutes_ids)
                 .select_related('team').prefetch_related('panel_assignments')}
    minutes = {m.schedule_id: m for m in DefenseMinutes.objects.filter(schedule_id__in=minutes_ids)}
    teams = {}
    if ids('deliverables'):
        from repository.deliverables.services import team_queryset_for_user
        teams = {t.pk: t for t in team_queryset_for_user(actor).filter(pk__in=ids('deliverables'))}
    stage_states = {}
    base = 'admin' if admin else 'faculty'
    result = {}
    for notification in notifications:
        kind, pk = targets[notification.pk]
        if not kind:
            result[notification.pk] = None
            continue
        action = _state('unavailable', 'No longer available')
        if kind in ('panelist_request', 'external_evaluator'):
            item = (requests if kind == 'panelist_request' else evaluators).get(pk)
            if item:
                pending = item.status == 'pending'
                route_kind = 'panelist' if kind == 'panelist_request' else 'external'
                label = 'Awaiting approval' if pending else item.status.title()
                if kind == 'external_evaluator' and not item.is_active:
                    label = 'Inactive'
                    pending = False
                action = _state('pending' if pending else 'completed', label,
                    (f'/admin/users?tab=faculty&view=panelists&section=requests&request={pk}' if admin else
                     f'/faculty/defense-board?panelistRequest={pk}') if route_kind == 'panelist' else
                    f'/{base}/defense-board/requests/{route_kind}/{pk}',
                    ('Review panelist request' if route_kind == 'panelist' else 'Review evaluator request')
                    if pending and admin else 'View request', item.reviewed_at)
        elif kind == 'deliverables':
            team = teams.get(pk)
            stage = (notification.action_payload or {}).get('stage_label')
            if team and isinstance(stage, str) and stage.strip():
                from repository.deliverables.services import team_stage_status
                key = (pk, stage)
                if key not in stage_states:
                    stage_states[key] = team_stage_status(team, stage)
                status = stage_states[key]
                # Legacy reminders sometimes asked for endorsement rather than
                # uploads. Without their original task, only endorsement is final.
                task = notification.action_payload.get('deliverable_task')
                done = status == 'endorsed' or (task == 'submit' and status == 'complete')
                query = urlencode({'stage': stage, 'scope': 'capstone' if team.is_capstone else 'pit'})
                route = f'/student?tab=stages&subtab=deliverables&{query}' if actor.role == 'student' else (
                    f'/admin/student-teams/{pk}?tab=deliverables&{query}' if admin else
                    f'/faculty/deliverables/teams/{pk}?{query}')
                action = _state('completed' if done else 'pending', 'Completed' if done else 'Action needed',
                                route, 'View deliverables')
        elif kind.startswith('minutes_'):
            schedule = schedules.get(pk)
            item = minutes.get(pk)
            allowed = schedule and (admin or schedule.documenter_id == actor.pk or
                schedule.team.adviser_id == actor.pk or
                any(p.panelist_id == actor.pk for p in schedule.panel_assignments.all()))
            if allowed:
                route = f'/documenter/minutes/{pk}' if notification.workspace == 'documenter' else f'/{base}/defense-board/minutes/{pk}'
                if schedule.status == DefenseSchedule.STATUS_CANCELLED:
                    action = _state('cancelled', 'Cancelled', route if item else None, 'View minutes' if item else None)
                else:
                    stamp = getattr(item, {
                        'minutes_adviser': 'adviser_signed_at', 'minutes_chairman': 'chairman_signed_at',
                        'minutes_documenter': 'documenter_signed_at', 'minutes_finalized': 'chairman_signed_at',
                    }.get(kind, ''), None)
                    done = bool(stamp) or bool(item and item.status == DefenseMinutes.STATUS_COMPLETED)
                    action = _state('completed' if done else 'pending', 'Completed' if done else 'Action needed',
                                    route, 'View minutes' if done else 'Open minutes', stamp)
        result[notification.pk] = action
    return result
