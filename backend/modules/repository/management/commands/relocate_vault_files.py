import re
from pathlib import Path

from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand

from repository.vault.models import VaultEntry
from repository.vault.upload_paths import vault_entry_upload_to

LEGACY_PATH_RE = re.compile(
    r'^vault_entries/\d{4}/\d{2}/',
)


class Command(BaseCommand):
    help = (
        'Move legacy vault_entries/YYYY/MM/ files into '
        'vault_entries/{pit|capstone}/{year-level}/{academic_year}/{month}/.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Print planned moves without changing storage or the database.',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        moved = 0
        skipped = 0
        errors = 0

        queryset = VaultEntry.objects.exclude(file='').exclude(file__isnull=True)
        for entry in queryset.iterator():
            old_name = entry.file.name
            if not old_name or not LEGACY_PATH_RE.match(old_name):
                skipped += 1
                continue

            filename = Path(old_name).name
            new_name = vault_entry_upload_to(entry, filename)
            if new_name == old_name:
                skipped += 1
                continue

            if dry_run:
                self.stdout.write(f'{old_name} -> {new_name}')
                moved += 1
                continue

            if not default_storage.exists(old_name):
                self.stderr.write(self.style.ERROR(f'Missing file: {old_name}'))
                errors += 1
                continue

            try:
                with entry.file.open('rb') as stored:
                    if default_storage.exists(new_name):
                        default_storage.delete(new_name)
                    default_storage.save(new_name, stored)
                default_storage.delete(old_name)
                entry.file.name = new_name
                entry.save(update_fields=['file', 'updated_at'])
            except OSError as exc:
                self.stderr.write(
                    self.style.ERROR(f'Failed {old_name} -> {new_name}: {exc}'),
                )
                errors += 1
                continue

            self.stdout.write(self.style.SUCCESS(f'Moved {old_name} -> {new_name}'))
            moved += 1

        label = 'Would move' if dry_run else 'Moved'
        self.stdout.write(
            f'{label} {moved} file(s); skipped {skipped}; errors {errors}.',
        )
