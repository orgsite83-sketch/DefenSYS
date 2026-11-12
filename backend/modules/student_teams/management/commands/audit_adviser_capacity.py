"""Read-only adoption report. Existing overloads are never auto-reassigned."""
import json
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from student_teams.adviser_assignments import active_teams_by_adviser
from student_teams.adviser_capacity import capacity_projections, exception_status
from student_teams.models import AdviserCapacityException


class Command(BaseCommand):
    help = 'Report advisers exceeding their effective Capstone capacity; makes no changes.'

    def add_arguments(self, parser):
        parser.add_argument('--include-exceptions', action='store_true',
            help='Also list batch mappings and ended/unresolved authorizations for rollout review.')

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
        output = {'overloaded_advisers': report}
        if options['include_exceptions']:
            output['exceptions'] = [{'id': row.pk, 'adviser_id': row.adviser_id,
                'issued_semester_id': row.semester_id, 'intake_semester_id': row.intake_semester_id,
                'approved_limit': row.approved_limit, 'ended_at': row.ended_at.isoformat() if row.ended_at else None,
                'status': exception_status(row)}
                for row in AdviserCapacityException.objects.order_by('adviser_id', 'pk')]
        self.stdout.write(json.dumps(output, indent=2))
