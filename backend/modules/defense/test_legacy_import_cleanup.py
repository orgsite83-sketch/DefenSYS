"""Verify legacy schema cleanup and normal flush on the isolated test DB."""

from unittest import skipUnless

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import DatabaseError, connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase

from academic_period_management.models import SchoolYear


@skipUnless(connection.vendor == 'postgresql', 'PostgreSQL legacy schema cleanup')
class LegacyScheduleImportCleanupTests(TransactionTestCase):
    legacy_table = 'defense_scheduler_import_attempt'
    dependent_table = 'test_legacy_import_attempt_dependency'

    def setUp(self):
        self.actor = get_user_model().objects.create_user(
            username='legacy-import-cleanup-test', role='admin',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')

    def tearDown(self):
        # Unregistered test tables must be removed before Django's own flush,
        # including when a test assertion fails before cleanup is applied.
        with connection.cursor() as cursor:
            for table in (self.dependent_table, self.legacy_table):
                cursor.execute(f'DROP TABLE IF EXISTS {connection.ops.quote_name(table)}')
        super().tearDown()

    def create_legacy_table(self):
        actor_table = connection.ops.quote_name(get_user_model()._meta.db_table)
        legacy_table = connection.ops.quote_name(self.legacy_table)
        with connection.cursor() as cursor:
            cursor.execute(f'''
                CREATE TABLE {legacy_table} (
                    key uuid PRIMARY KEY,
                    request_digest varchar(64) NOT NULL,
                    response jsonb NOT NULL,
                    created_at timestamptz NOT NULL,
                    actor_id bigint NOT NULL REFERENCES {actor_table}(id)
                        DEFERRABLE INITIALLY DEFERRED
                )
            ''')

    def apply_cleanup(self):
        executor = MigrationExecutor(connection)
        migration = executor.loader.get_migration(
            'defense', '0033_remove_legacy_schedule_import_attempt',
        )
        state = executor.loader.project_state([
            ('defense', '0032_minutes_external_panelists'),
        ])
        with connection.schema_editor() as editor:
            migration.apply(state, editor)

    def assert_sample_records_preserved(self):
        self.assertTrue(get_user_model().objects.filter(pk=self.actor.pk).exists())
        self.assertTrue(SchoolYear.objects.filter(pk=self.school_year.pk).exists())

    def test_cleanup_preserves_samples_and_unblocks_normal_flush(self):
        self.create_legacy_table()

        # Reproduce the failure even though the unregistered table is empty.
        with self.assertRaises(CommandError):
            call_command('flush', interactive=False, verbosity=0)
        self.assert_sample_records_preserved()

        self.apply_cleanup()
        self.assertNotIn(self.legacy_table, connection.introspection.table_names())
        self.assert_sample_records_preserved()

        # Exercise the standard command without allow_cascade.
        call_command('flush', interactive=False, verbosity=0)
        self.assertFalse(get_user_model().objects.filter(pk=self.actor.pk).exists())
        self.assertFalse(SchoolYear.objects.filter(pk=self.school_year.pk).exists())

    def test_cleanup_is_safe_when_legacy_table_is_already_absent(self):
        self.assertNotIn(self.legacy_table, connection.introspection.table_names())
        self.apply_cleanup()
        self.apply_cleanup()
        self.assert_sample_records_preserved()

    def test_cleanup_refuses_to_remove_unexpected_dependencies(self):
        self.create_legacy_table()
        with connection.cursor() as cursor:
            cursor.execute(f'''
                CREATE TABLE {connection.ops.quote_name(self.dependent_table)} (
                    attempt_key uuid REFERENCES {connection.ops.quote_name(self.legacy_table)}(key)
                )
            ''')

        with self.assertRaises(DatabaseError):
            self.apply_cleanup()

        tables = connection.introspection.table_names()
        self.assertIn(self.legacy_table, tables)
        self.assertIn(self.dependent_table, tables)
        self.assert_sample_records_preserved()
