"""Academic history reuses the existing transactional audit store."""
from django.db.models import Q


def record_team_event(team, action, *, actor=None, old_values=None, values=None, semester=None):
    from authentication_access_control.audit import log_high_impact_action
    from authentication_access_control.models import SystemAuditLog
    from .participation import intake_for
    intake = intake_for(team)
    term = semester or team.semester
    return log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
        action=action, target=team, actor=actor, strict=True, old_values=old_values,
        new_values={'scope': 'capstone', 'team_id': team.pk, 'team_name': team.name,
            'semester_id': term.pk, 'intake_id': intake.pk if intake else None,
            'project_version': team.project_version,
            'actor_snapshot': {'id': actor.pk, 'name': actor.get_full_name() or actor.username}
                if actor else {'name': 'System'}, **(values or {})})


def timeline_for(team, semester, *, stage_id=None, stage_label=None, stage_ids=()):
    from authentication_access_control.models import SystemAuditLog
    identity = Q(new_values__team_id=team.pk) | Q(old_values__team_id=team.pk) | Q(
        target_type='StudentTeam', target_id=str(team.pk))
    applicable_ids = [stage_id] if stage_id else stage_ids
    if applicable_ids:
        identity |= Q(target_type='DefenseStage', target_id__in=[str(i) for i in applicable_ids])
    term = (Q(new_values__semester_id=semester.pk) | Q(old_values__semester_id=semester.pk)
        | Q(new_values__source_semester_id=semester.pk) | Q(new_values__destination_semester_id=semester.pk))
    rows = SystemAuditLog.objects.filter(identity & term)
    if stage_id:
        rows = rows.filter(Q(new_values__defense_stage_id=stage_id) |
            Q(old_values__defense_stage_id=stage_id) | Q(new_values__stage_label=stage_label) |
            Q(old_values__stage_label=stage_label))
    return [{'id': r.pk, 'action': r.action, 'recorded_at': r.created_at.isoformat(),
        'actor': r.new_values.get('actor_snapshot', {}).get('name') or 'Recorded actor unavailable',
        'reason': r.reason, 'semester_id': semester.pk,
        'stage_label': r.new_values.get('stage_label')}
        for r in rows.order_by('created_at', 'pk')]
