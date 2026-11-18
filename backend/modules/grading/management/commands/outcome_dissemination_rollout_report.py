"""Read-only adoption evidence. This command never grants student access."""
import json

from django.core.management.base import BaseCommand

from grading.grades.dissemination import hydrate, snapshot, latest_release
from grading.grades.models import TeamGrade
from notifications.models import Notification


class Command(BaseCommand):
    help = 'Report resolved outcomes without explicit dissemination; never releases or backfills records.'

    def add_arguments(self, parser):
        parser.add_argument('--semester-id', type=int)

    def handle(self, *args, **options):
        grades = TeamGrade.all_objects.select_related('team', 'semester', 'schedule').order_by('pk')
        if options['semester_id']:
            grades = grades.filter(semester_id=options['semester_id'])
        rows = []
        for grade in hydrate(grades):
            public = snapshot(grade)
            if not public['verdict']:
                continue
            rows.append({'grade_id': grade.pk, 'team_id': grade.team_id, 'semester_id': grade.semester_id,
                'schedule_id': grade.schedule_id, 'attempt': grade.attempt_count,
                'has_explicit_release': bool(latest_release(grade.schedule_id)),
                'missing_attempt_identity': not bool(grade.schedule_id)})
        self.stdout.write(json.dumps({'policy': 'Private unless explicitly disseminated', 'writes': False,
            'resolved_attempts': len(rows), 'unreleased_attempts': sum(not r['has_explicit_release'] for r in rows),
            'legacy_outcome_notifications': Notification.objects.filter(workspace='student', title='Defense outcome recorded').count(),
            'attempts': rows}, indent=2))
