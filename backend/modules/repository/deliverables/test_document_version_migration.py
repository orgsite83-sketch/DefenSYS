from importlib import import_module
from types import SimpleNamespace
from django.apps import apps
from django.db import connection
from django.utils import timezone
from rest_framework.test import APITestCase
from . import test_submission_timing as fixtures
from .models import DeliverableSubmission, DeliverableSubmissionFile


class DocumentVersionMigrationTests(APITestCase):
    setUp = fixtures.SubmissionTimingTests.setUp

    def test_existing_reviewed_uploads_can_be_initialized_before_index_creation(self):
        self.assertTrue(connection.settings_dict['NAME'].startswith('test_'))
        submission = DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label,
            deliverable_id='PAPER', label='Concept paper', deliverable_type='pre', status='accepted',
            feedback='Verified original paper.', reviewed_by=self.adviser, reviewed_at=timezone.now())
        old = DeliverableSubmissionFile.objects.create(submission=submission, file_name='earlier.pdf', is_current=False)
        latest = DeliverableSubmissionFile.objects.create(submission=submission, file_name='latest.pdf')
        migration = import_module('repository.migrations.0023_initialize_document_versions')
        migration.initialize_versions(apps, SimpleNamespace(connection=connection))
        # Exercise PostgreSQL's real deferred-FK/index interaction with existing data.
        with connection.cursor() as cursor:
            cursor.execute('SET CONSTRAINTS ALL IMMEDIATE')
            cursor.execute('CREATE UNIQUE INDEX test_document_version_migration_index '
                           'ON capstone_deliverables_deliverablesubmissionfile (submission_id, slot_key) WHERE is_current')
            cursor.execute('DROP INDEX test_document_version_migration_index')
        old.refresh_from_db()
        latest.refresh_from_db()
        self.assertFalse(old.is_current)
        self.assertTrue(latest.is_current)
        self.assertEqual(latest.revision, 2)
        self.assertEqual(latest.status, 'accepted')
        self.assertEqual(latest.reviewed_by_id, self.adviser.pk)
