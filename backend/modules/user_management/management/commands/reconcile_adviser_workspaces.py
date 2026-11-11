"""Report missing adviser flags; apply only explicitly reviewed account IDs."""
import json

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from student_teams.adviser_assignments import active_teams_by_adviser
from user_management.models import FacultyRoleAssignment
from user_management.role_assignments import record_role_changes, snapshot_role_flags


class Command(BaseCommand):
    help = 'Dry-run missing adviser capabilities. --apply requires --user-id and --actor-id.'

    def add_arguments(self, parser):
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--user-id', action='append', type=int, default=[])
        parser.add_argument('--actor-id', type=int)

    @transaction.atomic
    def handle(self, *args, **options):
        User = get_user_model()
        apply = options['apply']
        actor = None
        if apply:
            if not options['user_id'] or not options['actor_id']:
                raise CommandError('--apply requires reviewed --user-id values and --actor-id.')
            actor = User.objects.filter(pk=options['actor_id'], is_active=True, role='admin').first()
            if actor is None:
                raise CommandError('--actor-id must identify an active administrator.')
        users = User.objects.filter(role__in=('faculty', 'admin'), is_active=True, is_adviser=False)
        if options['user_id']:
            users = users.filter(pk__in=options['user_id'])
        users = list(users.select_for_update() if apply else users)
        active = active_teams_by_adviser([u.pk for u in users])
        rows = []
        for user in users:
            latest = FacultyRoleAssignment.objects.filter(user=user, role_key='adviser').order_by('-changed_at', '-pk').first()
            teams = active.get(user.pk, [])
            status = ('explicitly_revoked' if latest and latest.action == FacultyRoleAssignment.ACTION_REVOKED
                      else 'eligible' if teams else 'historical_only_or_unassigned')
            if apply and status == 'eligible':
                before = snapshot_role_flags(user)
                user.is_adviser = True
                user.save(update_fields=['is_adviser'])
                record_role_changes(user, before, changed_by=actor)
                status = 'applied'
            rows.append({'user_id': user.pk, 'username': user.username, 'role': user.role,
                         'status': status, 'active_team_ids': [t.pk for t in teams]})
        self.stdout.write(json.dumps({'mode': 'apply' if apply else 'dry_run', 'accounts': rows}, indent=2))
