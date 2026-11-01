"""Read-only adoption report. Existing overloads are never auto-reassigned."""
import json
from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from student_teams.adviser_assignments import active_adviser_teams, MAX_ACTIVE_CAPSTONE_TEAMS


class Command(BaseCommand):
    help = 'Report advisers with more than four concurrent active Capstone projects; makes no changes.'

    def handle(self, *args, **options):
        report = []
        for adviser in get_user_model().objects.filter(advised_student_teams__level__icontains='Capstone').distinct():
            teams = active_adviser_teams(adviser.pk)
            if len(teams) > MAX_ACTIVE_CAPSTONE_TEAMS:
                report.append({'adviser_id': adviser.pk, 'adviser': adviser.get_full_name() or adviser.username,
                    'count': len(teams), 'team_ids': [t.pk for t in teams]})
        self.stdout.write(json.dumps({'overloaded_advisers': report}, indent=2))
