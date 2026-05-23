from repository.deliverables.services import display_name

from .models import RepositoryAuditLog


def audit_trail(entry_type, source_id, file_name):
    logs = RepositoryAuditLog.objects.filter(entry_type=entry_type)
    if source_id:
        logs = logs.filter(source_id=source_id)
    else:
        logs = logs.filter(file_name=file_name)
    return [
        {
            'id': log.id,
            'action': log.action,
            'previous_status': log.previous_status,
            'new_status': log.new_status,
            'message': log.message,
            'actor': display_name(log.actor) or 'System',
            'created_at': log.created_at,
        }
        for log in logs.select_related('actor')[:8]
    ]


def audit_trail_for_request(request):
    entry_type = (request.query_params.get('entry_type') or '').strip()
    source_id = request.query_params.get('source_id')
    file_name = (request.query_params.get('file_name') or '').strip()
    if not entry_type:
        return []
    try:
        source_id = int(source_id) if source_id not in (None, '') else None
    except (TypeError, ValueError):
        source_id = None
    return audit_trail(entry_type, source_id, file_name)


def log_action(entry_type, source_id, file_name, action, actor, previous_status='', new_status='', message=''):
    return RepositoryAuditLog.objects.create(
        entry_type=entry_type,
        source_id=source_id,
        file_name=file_name,
        action=action,
        previous_status=previous_status or '',
        new_status=new_status or '',
        message=message,
        actor=actor,
    )
