from datetime import datetime, timezone as dt_timezone

from django.test import SimpleTestCase

from repository.vault.models import VaultEntry
from repository.vault.upload_paths import slugify_year_level, vault_entry_upload_to


class VaultUploadPathTests(SimpleTestCase):
    def test_slugify_year_level(self):
        self.assertEqual(slugify_year_level('3rd Year'), '3rd-Year')
        self.assertEqual(slugify_year_level(''), 'unknown-year')

    def test_vault_entry_upload_to_uses_metadata(self):
        entry = VaultEntry(
            entry_type=VaultEntry.TYPE_PIT,
            year_level='3rd Year',
            academic_year='2026-2027',
            uploaded_at=datetime(2026, 5, 15, tzinfo=dt_timezone.utc),
        )
        path = vault_entry_upload_to(entry, '3rdYear.PIT301.Project.1stSemester.pdf')
        self.assertEqual(
            path,
            'vault_entries/pit/3rd-Year/2026-2027/05/3rdYear.PIT301.Project.1stSemester.pdf',
        )
