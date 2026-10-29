"""Read-only provenance assessment; never backfills or grants an allowance."""
import json
from django.core.management.base import BaseCommand
from django.db import connection, transaction
from student_teams.models import StudentTeam
from student_teams.participation import intake_for


class Command(BaseCommand):
    help = 'Report Capstone cohort provenance and term history without changing records.'
    requires_system_checks = []

    def add_arguments(self, parser):
        parser.add_argument('--pre-cutover', action='store_true', help='Count original evidence using the existing schema only.')

    def handle(self, *args, **options):
        with transaction.atomic():
            if connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
            if options['pre_cutover']:
                with connection.cursor() as cursor:
                    tables = set(connection.introspection.table_names(cursor))
                    counts = {}
                    from django.apps import apps
                    evidence_tables = [apps.get_model(app, model)._meta.db_table for app, model in (
                        ('grading', 'TeamGrade'), ('grading', 'GradeAttemptHistory'),
                        ('repository', 'DeliverableSubmission'), ('repository', 'DeliverableSubmissionFile'),
                        ('repository', 'ConceptRound'))]
                    for table in evidence_tables + ['student_teams_studentteam', 'student_teams_teammembership',
                            'student_teams_teamtermparticipation', 'student_teams_teamrecoveryauthorization',
                            'student_teams_capstonejourney',
                            'student_teams_studentcapstoneparticipation', 'student_teams_studentcapstoneplacement']:
                        if table in tables:
                            cursor.execute('SELECT COUNT(*) FROM ' + connection.ops.quote_name(table))
                            counts[table] = cursor.fetchone()[0]
                    cursor.execute("SELECT capstone_phase, project_version, COUNT(*) FROM student_teams_studentteam WHERE level LIKE %s GROUP BY capstone_phase, project_version ORDER BY project_version", ['%Capstone%'])
                    contexts = [{'phase': phase, 'project_version': version, 'teams': count} for phase, version, count in cursor.fetchall()]
                self.stdout.write(json.dumps({'read_only': True, 'pre_cutover': True, 'evidence_counts': counts,
                    'capstone_contexts': contexts}, indent=2))
                return
            rows = []
            teams = StudentTeam.objects.filter(level__in=(StudentTeam.LEVEL_3_CAPSTONE, StudentTeam.LEVEL_4_CAPSTONE))
            for team in teams.select_related('semester__school_year').order_by('pk'):
                intake = intake_for(team)
                rows.append({'team_id': team.pk, 'name': team.name,
                    'operating_term': team.semester.display_name,
                    'intake': intake.display_name if intake else None,
                    'review_reason': team.participation_review_reason,
                    'provenance': 'known' if intake and not team.participation_review_reason else 'needs_review',
                    'recorded_terms': team.term_participations.count()})
        self.stdout.write(json.dumps({'read_only': True, 'teams': len(rows),
            'needs_review': sum(r['provenance'] == 'needs_review' for r in rows), 'rows': rows}, indent=2))
