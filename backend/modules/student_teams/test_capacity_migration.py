"""Exercise the migration itself with existing rows on an isolated database."""
from django.conf import settings
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase
from django.utils import timezone
from unittest.mock import patch


class CapacityMigrationTests(TransactionTestCase):
    migrate_from = ('student_teams', '0026_adviser_capacity_exception')

    def setUp(self):
        super().setUp()
        if connection.vendor != 'postgresql':
            self.skipTest('Regression requires PostgreSQL deferred FK triggers')
        executor = MigrationExecutor(connection)
        self.latest = executor.loader.graph.leaf_nodes()
        self.addCleanup(self.restore_schema)
        executor.migrate([self.migrate_from])
        self.old_apps = executor.loader.project_state([self.migrate_from]).apps

    def restore_schema(self):
        executor = MigrationExecutor(connection)
        # If an atomic upgrade failed, remove only these isolated test fixtures
        # before restoring the latest schema for the remaining test classes.
        if ('student_teams', '0027_adviser_capacity_batch') not in executor.loader.applied_migrations:
            self.old_apps.get_model('student_teams', 'AdviserCapacityException').objects.all().delete()
        executor.migrate(self.latest)

    def legacy_context(self):
        User = self.old_apps.get_model(settings.AUTH_USER_MODEL)
        Year = self.old_apps.get_model('academic_period_management', 'SchoolYear')
        Semester = self.old_apps.get_model('academic_period_management', 'Semester')
        adviser = User.objects.create(username='migration-adviser', role='faculty')
        year = Year.objects.create(label='2026-2027')
        term = Semester.objects.create(school_year=year, label='2nd Semester')
        return adviser, term

    def test_populated_legacy_table_migrates_and_preserves_authorizations(self):
        adviser, term = self.legacy_context()
        User = self.old_apps.get_model(settings.AUTH_USER_MODEL)
        Legacy = self.old_apps.get_model('student_teams', 'AdviserCapacityException')
        other = User.objects.create(username='migration-ended-adviser', role='faculty')
        active = Legacy.objects.create(adviser=adviser, semester=term, approved_limit=5,
            authorization='Existing department decision', reason='Approved fifth project',
            reference='EXISTING-1', created_by=adviser, updated_by=adviser)
        ended = Legacy.objects.create(adviser=other, semester=term, approved_limit=6,
            authorization='Previous department decision', reason='Previous approval',
            ended_at=timezone.now(), ended_by=other, end_reason='Withdrawn', created_by=other)
        before = {row['id']: row for row in Legacy.objects.values()}

        executor = MigrationExecutor(connection)
        executor.migrate(self.latest)
        Current = executor.loader.project_state(self.latest).apps.get_model(
            'student_teams', 'AdviserCapacityException')
        after = {row['id']: row for row in Current.objects.values()}
        self.assertEqual(set(after), {active.pk, ended.pk})
        for pk, original in before.items():
            for field, value in original.items():
                self.assertEqual(after[pk][field], value, (pk, field))
            self.assertEqual(after[pk]['intake_semester_id'], term.pk)
        self.assertIsNone(after[active.pk]['ended_at'])
        self.assertEqual(after[ended.pk]['end_kind'], 'legacy_ended')

    def test_already_applied_0027_preserves_mappings_and_later_revocation(self):
        adviser, term = self.legacy_context()
        schema_target = ('student_teams', '0027_adviser_capacity_batch')
        executor = MigrationExecutor(connection)
        executor.migrate([schema_target])
        apps = executor.loader.project_state([schema_target]).apps
        Approval = apps.get_model('student_teams', 'AdviserCapacityException')
        Year = apps.get_model('academic_period_management', 'SchoolYear')
        Semester = apps.get_model('academic_period_management', 'Semester')
        Transition = apps.get_model('academic_period_management', 'SemesterTransitionLog')
        # Simulate a database where the original 0027 already mapped an approval
        # and an administrator subsequently changed/revoked it.
        approval = Approval.objects.create(adviser_id=adviser.pk, semester_id=term.pk, intake_semester_id=term.pk,
            approved_limit=7, authorization='Later department decision', reason='Later change',
            ended_at=timezone.now(), end_kind='revoked', end_reason='Explicit revocation')
        year = Year.objects.create(label='2027-2028')
        continuation = Semester.objects.create(school_year=year, label='1st Semester')
        Transition.objects.create(from_semester_id=term.pk, to_semester=continuation,
            impact_snapshot={'capstone_review': {'kind': 'continue'}, 'applied_team_ids': [1]})
        conflict = Approval.objects.create(adviser_id=adviser.pk, semester=continuation,
            approved_limit=5, authorization='Legacy decision', reason='Conflicting legacy scope')
        before = list(Approval.objects.order_by('pk').values())

        executor = MigrationExecutor(connection)
        executor.migrate(self.latest)
        self.assertEqual(list(Approval.objects.order_by('pk').values()), before)
        approval.refresh_from_db()
        conflict.refresh_from_db()
        self.assertEqual(approval.end_kind, 'revoked')
        self.assertIsNone(conflict.intake_semester_id)
        # Execute the backfill again, beyond a normal already-applied no-op.
        migration = executor.loader.get_migration('student_teams', '0028_backfill_adviser_capacity_batch')
        with connection.schema_editor() as editor:
            migration.apply(executor.loader.project_state([schema_target]), editor)
        self.assertEqual(list(Approval.objects.order_by('pk').values()), before)

    def test_backfill_failure_rolls_back_data_and_can_be_retried(self):
        adviser, term = self.legacy_context()
        schema_target = ('student_teams', '0027_adviser_capacity_batch')
        data_target = ('student_teams', '0028_backfill_adviser_capacity_batch')
        executor = MigrationExecutor(connection)
        executor.migrate([schema_target])
        Approval = executor.loader.project_state([schema_target]).apps.get_model(
            'student_teams', 'AdviserCapacityException')
        approval = Approval.objects.create(adviser_id=adviser.pk, semester_id=term.pk, approved_limit=5,
            authorization='Department decision', reason='Legacy ended approval', ended_at=timezone.now())
        before = Approval.objects.values().get(pk=approval.pk)
        executor = MigrationExecutor(connection)
        migration = executor.loader.get_migration(*data_target)
        operation = migration.operations[0]
        original = operation.code

        def fail_after_mapping(apps, editor):
            original(apps, editor)
            raise RuntimeError('Simulated backfill failure')

        with patch.object(operation, 'code', fail_after_mapping):
            with self.assertRaisesMessage(RuntimeError, 'Simulated backfill failure'):
                executor.migrate([data_target])
        self.assertEqual(Approval.objects.values().get(pk=approval.pk), before)
        executor = MigrationExecutor(connection)
        self.assertNotIn(data_target, executor.loader.applied_migrations)
        executor.migrate(self.latest)
        approval.refresh_from_db()
        self.assertEqual(approval.intake_semester_id, term.pk)
        self.assertEqual(approval.end_kind, 'legacy_ended')
        self.assertEqual(approval.ended_at, before['ended_at'])
