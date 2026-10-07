"""Preview or refresh only derived project classifications from existing text."""
import json
from collections import Counter
from pathlib import Path

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from defensys_backend.db_guard import assert_safe_for_orm_writes
from curriculum_analytics.explorer import CurriculumExplorer
from repository.archive.models import ArchiveEntry
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from repository.deliverables.project_classification import classification_for_document


class Command(BaseCommand):
    help = 'Preview refreshed classifications; --apply updates derived fields only, with a backup.'

    def add_arguments(self, parser):
        parser.add_argument('--scope', choices=['capstone', 'pit', 'all'], default='all')
        parser.add_argument('--academic-year', default='')
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--backup', help='Required JSON backup path when applying changes.')

    def handle(self, *args, **options):
        if options['apply']:
            assert_safe_for_orm_writes()
            if not options['backup']:
                raise CommandError('--backup is required before updating classifications.')
        admin = get_user_model().objects.filter(role='admin').first()
        if not admin:
            raise CommandError('An existing admin is required to resolve eligible project documents.')
        scopes = ['capstone', 'pit'] if options['scope'] == 'all' else [options['scope']]
        ids = set()
        for scope in scopes:
            for level in ['1', '2', '3'] if scope == 'pit' else ['']:
                explorer = CurriculumExplorer(admin, {'scope': scope, 'year_level': level,
                                                      'academic_year': options['academic_year']})
                for project in explorer.projects.values():
                    ids.update(d['id'] for d in explorer._documents(project))
        models = {'submission': DeliverableSubmission, 'file': DeliverableSubmissionFile,
                  'archive': ArchiveEntry}
        changes, counts = [], Counter()
        for identifier in sorted(ids):
            source, pk = identifier.split(':')
            obj = models[source]._base_manager.get(pk=pk)
            result = classification_for_document(obj.extracted_text, obj.classification)
            counts[result['predicted_category']] += 1
            if obj.classification == result and obj.category == result['predicted_category']:
                continue
            changes.append({'source': source, 'pk': obj.pk, 'text': obj.extracted_text,
                            'before': {'category': obj.category, 'category_confidence': obj.category_confidence,
                                       'classification': obj.classification},
                            'after': {'category': result['predicted_category'],
                                      'category_confidence': result['confidence_score'], 'classification': result}})
        if options['apply']:
            backup = Path(options['backup']).resolve()
            backup.parent.mkdir(parents=True, exist_ok=True)
            # Exclusive creation prevents replacing an earlier rollback snapshot.
            with backup.open('x', encoding='utf-8') as output:
                json.dump([{k: v for k, v in row.items() if k != 'text'} for row in changes], output, indent=2)
            with transaction.atomic():
                for row in changes:
                    updated = models[row['source']]._base_manager.filter(
                        pk=row['pk'], extracted_text=row['text']).update(**row['after'])
                    if updated != 1:
                        raise CommandError('A document changed during classification. No updates were committed.')
            self.stdout.write(f'Updated {len(changes)} derived classifications. Backup: {backup}')
        else:
            self.stdout.write(f'Dry run: {len(changes)} classifications would change. No records updated.')
        self.stdout.write(json.dumps({'eligible_records': len(ids), 'categories': counts}, indent=2))
