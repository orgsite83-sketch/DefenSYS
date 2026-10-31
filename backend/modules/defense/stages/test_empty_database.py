"""New databases expose only stages explicitly configured by an administrator."""

from importlib import import_module
from unittest import skipUnless
from unittest.mock import patch
from uuid import uuid4

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import connection, transaction
from django.db.migrations.state import ProjectState
from rest_framework.test import APITestCase

from defense.stages.models import DefenseStage


class EmptyStageSetupTests(APITestCase):
    def setUp(self):
        # Arrange empty configuration even with legacy fixtures in --keepdb.
        # The separate schema test below checks real migration bootstrap.
        DefenseStage.objects.all().delete()
        self.admin = get_user_model().objects.create_user(username='empty-setup-admin', role='admin')
        self.client.force_authenticate(self.admin)

    @skipUnless(connection.vendor == 'postgresql', 'PostgreSQL bootstrap schema')
    def test_initial_migration_creates_no_stage_records(self):
        self.assertTrue(connection.settings_dict['NAME'].startswith('test_'))
        schema = connection.ops.quote_name('test_stage_bootstrap_' + uuid4().hex[:12])
        migration = import_module('defense.migrations.0001_initial').Migration('0001_initial', 'defense')
        with transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute(f'CREATE SCHEMA {schema}')
                cursor.execute(f'SET LOCAL search_path TO {schema}')
            with connection.schema_editor(atomic=False) as editor:
                migration.apply(ProjectState(), editor)
            with connection.cursor() as cursor:
                cursor.execute('SELECT count(*) FROM defense_stages_stage')
                self.assertEqual(cursor.fetchone()[0], 0)
                cursor.execute('SET LOCAL search_path TO public')
                cursor.execute(f'DROP SCHEMA {schema} CASCADE')

    def test_empty_configuration_and_repeated_api_reads_have_no_stages(self):
        self.assertFalse(DefenseStage.objects.exists())
        for _ in range(2):
            stages = self.client.get('/api/defense/stages/')
            self.assertEqual(stages.status_code, 200, stages.data)
            self.assertEqual(stages.data['stages'], [])
            self.assertEqual(stages.data['active_stages'], [])
            self.assertEqual(stages.data['sequence_stages'], [])
            self.assertEqual(stages.data['counts']['total'], 0)
            grades = self.client.get('/api/grading/grades/')
            self.assertEqual(grades.status_code, 200, grades.data)
            self.assertEqual(grades.data['capstone_stages'], [])
            self.assertEqual(grades.data['grades'], [])
            self.assertFalse(DefenseStage.objects.exists())

    def test_administrator_can_start_with_one_custom_stage(self):
        self.assertFalse(DefenseStage.objects.exists())
        response = self.client.post('/api/defense/stages/', {'label': 'Pilot review'}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual([s['label'] for s in response.data['stages']], ['Pilot review'])
        self.assertEqual(DefenseStage.objects.count(), 1)

    def test_fixture_command_cannot_seed_normal_or_sandbox_databases(self):
        for database in ('defensys_db', 'defensys_sandbox'):
            with self.subTest(database=database), patch(
                'defense.management.commands.seed_defense_stages.current_database_name', return_value=database,
            ):
                with self.assertRaisesMessage(CommandError, 'Stage fixtures are test-only'):
                    call_command('seed_defense_stages', verbosity=0)
                self.assertFalse(DefenseStage.objects.exists())
