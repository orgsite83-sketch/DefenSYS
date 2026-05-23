#!/usr/bin/env python
"""
Probe capstone deliverable upload on the isolated test database only.

Preferred regression check:
  python manage.py test repository.deliverables.tests.CapstoneDeliverablesApiTests.test_multipart_upload_with_pdf_file -v 2
"""

from __future__ import annotations

import os
import sys

BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from django.core.management import call_command

from defensys_backend.db_guard import bootstrap_test_db_script


def main() -> None:
    bootstrap_test_db_script()
    print('Running deliverables API tests on test database...')
    call_command(
        'test',
        'repository.deliverables.tests.CapstoneDeliverablesApiTests.test_multipart_upload_with_pdf_file',
        verbosity=2,
    )


if __name__ == '__main__':
    main()
