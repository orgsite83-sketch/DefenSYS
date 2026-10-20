"""A partial manual reset must not leave last hearing's system labels in a fresh pitch."""
from io import StringIO
from unittest.mock import patch

from django.core.management import call_command, CommandError
from rest_framework.test import APITestCase

from authentication_access_control.models import SystemAuditLog
from repository.deliverables import concepts
from . import services, tests as fixtures


class UnscheduledSystemReconciliationTests(APITestCase):
    setUp = fixtures.SharedSystemConceptTests.setUp
    configure = fixtures.SharedSystemConceptTests.configure
    rubric = fixtures.SharedSystemConceptTests.rubric
    data = fixtures.SharedSystemConceptTests.data
    slot = fixtures.SharedSystemConceptTests.slot
    titles = fixtures.SharedSystemConceptTests.titles
    action = fixtures.SharedSystemConceptTests.action
    prepare_shared = fixtures.SharedSystemConceptTests.prepare_shared
    prepare_team = fixtures.SharedSystemConceptTests.prepare_team

    def prepare_reset(self):
        self.prepare_shared()
        for team in (self.team, self.module_team):
            self.prepare_team(team)
        current = services.latest(self.project)
        current.systems.filter(key='c1').update(decision='approved')
        current.systems.exclude(key='c1').update(decision='not_selected')
        return current

    def reconcile(self, **options):
        call_command('reconcile_unscheduled_system_decisions', project_id=self.project.pk,
            round_id=services.latest(self.project).pk, stdout=StringIO(), **options)

    def test_preview_is_read_only_and_apply_preserves_endorsements_files_and_scheduling(self):
        current = self.prepare_reset()
        before = list(current.systems.values('key', 'title', 'confirmed'))
        papers = list(current.systems.values('papers__id', 'papers__status'))
        endorsed = list(current.module_rounds.values('id', 'endorsed_at', 'endorsement_snapshot'))
        self.reconcile()
        self.assertEqual(current.systems.get(key='c1').decision, 'approved')
        self.reconcile(apply=True, reason='Restore the requested ready-to-schedule demo state.')
        self.assertTrue(all(not s.decision for s in current.systems.all()))
        self.assertEqual(before, list(current.systems.values('key', 'title', 'confirmed')))
        self.assertEqual(papers, list(current.systems.values('papers__id', 'papers__status')))
        self.assertEqual(endorsed, list(current.module_rounds.values('id', 'endorsed_at', 'endorsement_snapshot')))
        self.assertTrue(all(concepts.pit_ready(t, self.event) for t in (self.team, self.module_team)))
        self.assertFalse(services.payload(self.project, self.pm)['post_unlocked'])
        audit = SystemAuditLog.objects.get(action='section_concepts.unscheduled_system_labels_reconciled')
        self.assertEqual(audit.old_values['systems'][0]['decision'], 'approved')
        self.reconcile(apply=True, reason='Idempotence check.')
        self.assertEqual(SystemAuditLog.objects.filter(action=audit.action).count(), 1)
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/defense/schedules/', self.slot(self.team,
            chair_panelist_id=self.panelist.pk), format='json')
        self.assertEqual(response.status_code, 201, response.data)

    def test_live_hearing_and_module_outcomes_cannot_be_erased(self):
        current = self.prepare_reset()
        current.selected_key = 'c1'
        current.save(update_fields=['selected_key'])
        with self.assertRaises(CommandError):
            self.reconcile(apply=True, reason='Must not rewind a decision.')
        current.selected_key = ''
        current.save(update_fields=['selected_key'])
        module = current.module_rounds.first()
        module.verdict = 'approved'
        module.save(update_fields=['verdict'])
        with self.assertRaises(CommandError):
            self.reconcile(apply=True, reason='Must not erase a module outcome.')
        self.assertEqual(current.systems.get(key='c1').decision, 'approved')

    def test_an_existing_schedule_prevents_repair(self):
        current = self.prepare_reset()
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/defense/schedules/', self.slot(self.team,
            chair_panelist_id=self.panelist.pk), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        with self.assertRaises(CommandError):
            self.reconcile(apply=True, reason='Must not change a scheduled hearing.')
        self.assertEqual(current.systems.get(key='c1').decision, 'approved')

    def test_audit_failure_rolls_back_the_label_change(self):
        current = self.prepare_reset()
        with patch('repository.management.commands.reconcile_unscheduled_system_decisions.log_high_impact_action',
                side_effect=RuntimeError('audit unavailable')):
            with self.assertRaises(RuntimeError):
                self.reconcile(apply=True, reason='Atomic recovery check.')
        self.assertEqual(current.systems.get(key='c1').decision, 'approved')
