"""Read-only diagnosis of saved PIT concept policies and adoption blockers."""
import json

from django.core.management.base import BaseCommand, CommandError
from django.db import connection, transaction

from grading.grades.models import TeamGrade
from grading.management.commands.automatic_outcome_adoption_report import adoption_row


class Command(BaseCommand):
    help = 'Inspect PIT concept grading for named teams/schedules without changing data.'

    def add_arguments(self, parser):
        parser.add_argument('--team-name')
        parser.add_argument('--schedule-id', nargs='+', type=int)

    def handle(self, *args, **options):
        if not options['team_name'] and not options['schedule_id']:
            raise CommandError('Provide --team-name or --schedule-id to scope this read-only report.')
        nested = connection.in_atomic_block
        with transaction.atomic():
            if not nested and connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
            grades = TeamGrade.all_objects.filter(scope='pit', schedule__isnull=False)
            if options['team_name']:
                grades = grades.filter(team__name__icontains=options['team_name'])
            if options['schedule_id']:
                grades = grades.filter(schedule_id__in=options['schedule_id'])
            rows = []
            for grade in grades.select_related('team', 'semester', 'schedule', 'pit_event_config').order_by('pk'):
                schedule, event = grade.schedule, grade.pit_event_config
                config = event.concept_config if event else {}
                policy = schedule.assessment_policy or {}
                hearing = getattr(schedule, 'concept_round', None)
                concepts = hearing.concepts if hearing else []
                review = adoption_row(grade)
                automatic = policy.get('version') == 1 and policy.get('automatic_outcomes') is True
                per_concept = policy.get('per_concept') is True
                blockers = list(review['blockers'])
                if not event or not config.get('enabled'):
                    blockers.append('The event does not have Concept selection enabled')
                if not hearing:
                    blockers.append('No captured concept hearing')
                if automatic:
                    blockers.append('This hearing already uses automatic outcomes')
                rows.append({
                    'team': grade.team.name, 'team_id': grade.team_id,
                    'schedule_id': schedule.pk, 'grade_id': grade.pk,
                    'event_id': grade.pit_event_config_id, 'event': schedule.event_name,
                    'active_semester': grade.semester.is_active,
                    'event_concept_enabled': bool(config.get('enabled')),
                    'event_cutoff': config.get('qualifying_score'),
                    'captured_policy': policy,
                    'automatic_outcomes': automatic, 'per_concept': per_concept,
                    'captured_concept_keys': [c.get('key') for c in concepts],
                    'grading_mode': 'per_concept' if per_concept else 'single_team_score',
                    'submitted_count': grade.panelist_submissions.filter(is_void=False).count(),
                    'submitted_concept_keys': list(grade.panelist_submissions.filter(is_void=False)
                        .order_by('concept_key').values_list('concept_key', flat=True).distinct()),
                    'draft_count': schedule.evaluation_drafts.count(),
                    'recorded_verdict': grade.verdict,
                    'untouched_adoption_candidate': not blockers,
                    'adoption_blockers': blockers,
                })
        self.stdout.write(json.dumps({'read_only': True, 'hearings': rows}, indent=2, default=str))
