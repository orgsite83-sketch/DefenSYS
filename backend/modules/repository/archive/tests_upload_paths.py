from datetime import datetime, timezone as dt_timezone

from django.test import SimpleTestCase

from repository.archive.models import ArchiveEntry
from repository.archive.upload_paths import slugify_year_level, archive_entry_upload_to


class ArchiveUploadPathTests(SimpleTestCase):
    def test_slugify_year_level(self):
        self.assertEqual(slugify_year_level('3rd Year'), '3rd-Year')
        self.assertEqual(slugify_year_level(''), 'unknown-year')

    def test_archive_entry_upload_to_uses_metadata(self):
        entry = ArchiveEntry(
            entry_type=ArchiveEntry.TYPE_PIT,
            year_level='3rd Year',
            academic_year='2026-2027',
            uploaded_at=datetime(2026, 5, 15, tzinfo=dt_timezone.utc),
        )
        path = archive_entry_upload_to(entry, '3rdYear.PIT301.Project.1stSemester.pdf')
        self.assertEqual(
            path,
            'archive_entries/pit/3rd-Year/2026-2027/05/3rdYear.PIT301.Project.1stSemester.pdf',
        )
