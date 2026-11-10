"""Read-only adoption report. Existing overloads are never auto-reassigned."""
import json
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from student_teams.adviser_assignments import active_teams_by_adviser
from student_teams.adviser_capacity import capacity_projections


class Command(BaseCommand):
    help = 'Report advisers exceeding their effective Capstone capacity; makes no changes.'

    def handle(self, *args, **options):
        report = []
        advisers = list(get_user_model().objects.filter(advised_student_teams__level__icontains='Capstone').distinct())
        workloads = active_teams_by_adviser([user.pk for user in advisers])
        capacities = capacity_projections([user.pk for user in advisers], workloads=workloads)
        for adviser in advisers:
            teams = workloads[adviser.pk]
            capacity = capacities[adviser.pk]
            if capacity['is_overloaded']:
                report.append({'adviser_id': adviser.pk, 'adviser': adviser.get_full_name() or adviser.username,
                    'count': len(teams), 'team_ids': [t.pk for t in teams], **capacity})
        self.stdout.write(json.dumps({'overloaded_advisers': report}, indent=2))
