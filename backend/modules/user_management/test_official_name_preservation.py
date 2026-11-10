from django.test import SimpleTestCase

from defensys_backend.person_names import split_official_person_name
from .views import _split_official_full_name


class OfficialNamePreservationTests(SimpleTestCase):
    def test_account_import_retains_initials_suffixes_and_compound_surnames(self):
        for raw, expected in (
            ('TAC-AN, EDGAR, JR C', ('EDGAR JR C', 'TAC-AN')),
            ('BONGCAC, RYZA MAY G.', ('RYZA MAY G.', 'BONGCAC')),
            ('Dela Cruz, Juan A. III', ('Juan A. III', 'Dela Cruz')),
            ('MATABALAN, JOHNLEY L', ('JOHNLEY L', 'MATABALAN')),
            ('Juan Dela Cruz', ('Juan', 'Dela Cruz')),
            ('  Dela Cruz,\u00a0Juan  A.  ', ('Juan A.', 'Dela Cruz')),
            ('', ('', '')),
        ):
            with self.subTest(raw=raw):
                self.assertEqual(split_official_person_name(raw), expected)
                self.assertEqual(_split_official_full_name(raw), expected)
