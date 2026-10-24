"""Read-only provenance assessment; never backfills or grants an allowance."""
import json
from django.core.management.base import BaseCommand
from django.db import connection, transaction
from student_teams.models import StudentTeam
from student_teams.capstone_lifecycle import cohort_context


class Command(BaseCommand):
    help = 'Report Capstone cohort provenance and term history without changing records.'
    requires_system_checks = []

    def handle(self, *args, **options):
        with transaction.atomic():
            if connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
            rows = []
            teams = StudentTeam.objects.filter(level__in=(StudentTeam.LEVEL_3_CAPSTONE, StudentTeam.LEVEL_4_CAPSTONE))
            for team in teams.select_related('semester__school_year').order_by('pk'):
                context = cohort_context(team)
                rows.append({'team_id': team.pk, 'name': team.name,
                    'operating_term': team.semester.display_name, 'is_extended': team.capstone_phase == 'extended',
                    'cohort': context['intake'].display_name if context else None,
                    'normal_completion_year': context['normal_year'] if context else None,
                    'extension_end_year': context['end_year'] if context else None,
                    'provenance': 'known' if context else 'needs_review',
                    'recorded_terms': team.term_participations.count()})
        self.stdout.write(json.dumps({'read_only': True, 'teams': len(rows),
            'needs_review': sum(r['provenance'] == 'needs_review' for r in rows), 'rows': rows}, indent=2))
