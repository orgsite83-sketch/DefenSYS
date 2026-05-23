from django.core.management.base import BaseCommand

from repository.deliverables.models import DeliverableSubmission
from repository.vault.ml_indexing import apply_ml_from_pdf
from repository.vault.models import VaultEntry


class Command(BaseCommand):
    help = 'Re-extract PDF text, TF-IDF topics, and Naive Bayes categories for vault files.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--force',
            action='store_true',
            help='Re-run extraction even when extracted_text is already populated.',
        )
        parser.add_argument(
            '--pit-only',
            action='store_true',
            help='Only reindex VaultEntry PIT rows.',
        )
        parser.add_argument(
            '--capstone-only',
            action='store_true',
            help='Only reindex capstone DeliverableSubmission rows with files.',
        )

    def handle(self, *args, **options):
        force = options['force']
        pit_only = options['pit_only']
        capstone_only = options['capstone_only']
        pit_done = 0
        capstone_done = 0

        if not capstone_only:
            queryset = VaultEntry.objects.exclude(file='').exclude(file__isnull=True)
            for entry in queryset.iterator():
                if force:
                    entry.extracted_text = ''
                if apply_ml_from_pdf(entry, force=force):
                    if entry.status == VaultEntry.STATUS_PENDING:
                        entry.status = VaultEntry.STATUS_APPROVED
                    entry.save()
                    pit_done += 1
                    self.stdout.write(self.style.SUCCESS(f'Indexed PIT: {entry.file_name}'))

        if not pit_only:
            submissions = DeliverableSubmission.objects.exclude(file='').exclude(file__isnull=True)
            for submission in submissions.iterator():
                if force:
                    submission.extracted_text = ''
                submission.save()
                capstone_done += 1
                self.stdout.write(self.style.SUCCESS(f'Indexed capstone: {submission.file_name}'))

        self.stdout.write(
            self.style.SUCCESS(
                f'Reindex complete. PIT vault entries: {pit_done}; capstone submissions: {capstone_done}.',
            ),
        )
