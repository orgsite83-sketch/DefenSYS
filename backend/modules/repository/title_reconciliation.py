"""The same audited reconciliation is available to authenticated admins in-app."""
from io import StringIO
import json
from django.core.management import call_command, CommandError
from django.core.exceptions import ValidationError


def reconcile(actor, *, section_round=None, team_round=None, token=None):
    if not actor or not (actor.role == 'admin' or actor.is_superuser):
        raise PermissionError('An administrator must review and apply the legacy proposal upgrade.')
    stream = StringIO()
    options = {'stdout': stream, 'no_color': True}
    options['section_round' if section_round else 'team_round'] = section_round or team_round
    try:
        if token:
            call_command('reconcile_title_workflow', apply=True, token=token, actor=actor.pk, **options)
            return None
        call_command('reconcile_title_workflow', **options)
        return json.loads(stream.getvalue())
    except CommandError as exc:
        raise ValidationError(str(exc)) from exc
