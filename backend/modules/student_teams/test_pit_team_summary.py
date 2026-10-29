"""PIT team summary counts follow the selected event and never mutate on GET."""
from datetime import date
from unittest.mock import patch

from django.db import connection
from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, PitEventDeliverable, PitEventGradingConfig
from repository.deliverables import concepts
from user_management.models import SectionInstructorAssignment
from . import test_formation as fixtures
from .pit_rosters import register, set_endorsed


@override_settings(DEFENSYS_TITLE_WORKFLOW_VERSION=1)
class PITTeamSummaryTests(APITestCase):
    existing = fixtures.TeamFormationTests.existing

    def setUp(self):
        fixtures.TeamFormationTests.setUp(self)
        self.team = self.existing()
        self.team.current_defense_stage = None
        self.team.save(update_fields=['current_defense_stage'])
        register([self.team], self.lead)

    def context(self, event=None):
        event = event or self.event
        response = self.client.get('/api/teams/', {
            'workspace': 'operations', 'event_name': event.event_name,
        })
        self.assertEqual(response.status_code, 200, response.data)
        row = next(row for row in response.data['teams'] if row['id'] == self.team.pk)
        return row['defense_context']

    def schedule(self, event=None, **changes):
        return DefenseSchedule.objects.create(
            team=self.team, semester=self.term, scope=DefenseSchedule.SCOPE_PIT,
            event_name=(event or self.event).event_name, scheduled_date=date(2026, 11, 1),
            start_time='09:00', slot_duration=60, room='Room 101', **changes,
        )

    def disable_concepts(self):
        self.event.concept_config = {}
        self.event.save(update_fields=['concept_config'])

    def test_selected_event_ignores_other_event_schedule_and_endorsement(self):
        self.disable_concepts()
        self.schedule()
        later = PitEventGradingConfig.objects.create(semester=self.term,
            year_level='2nd Year', event_name='Later showcase')
        later_context = self.context(later)
        self.assertEqual(later_context['event_label'], later.event_name)
        self.assertEqual(later_context['scheduling_status'], 'ready')
        self.assertEqual(later_context['scheduled_date'], '')
        self.assertEqual(self.context()['scheduling_status'], 'scheduled')

    def test_cancelled_archived_and_previous_project_slots_are_not_scheduled(self):
        self.disable_concepts()
        slot = self.schedule()
        for status in (DefenseSchedule.STATUS_CANCELLED, DefenseSchedule.STATUS_ARCHIVED):
            with self.subTest(status=status):
                DefenseSchedule.objects.filter(pk=slot.pk).update(status=status)
                self.assertEqual(self.context()['scheduling_status'], 'ready')
        DefenseSchedule.objects.filter(pk=slot.pk).update(status=DefenseSchedule.STATUS_SCHEDULED,
            project_version=self.team.project_version + 1)
        self.assertEqual(self.context()['scheduling_status'], 'ready')

    def test_completed_event_is_not_ready_again(self):
        self.disable_concepts()
        self.schedule(status=DefenseSchedule.STATUS_DONE)
        self.assertEqual(self.context()['scheduling_status'], 'completed')

    def test_closed_event_is_neither_ready_nor_scheduled(self):
        self.schedule()
        self.event.is_officially_complete = True
        self.event.save(update_fields=['is_officially_complete'])
        self.assertEqual(self.context()['scheduling_status'], 'completed')

    def test_required_files_need_both_event_endorsement_and_completeness(self):
        self.disable_concepts()
        PitEventDeliverable.objects.create(pit_event_config=self.event,
            deliverable_id='paper', label='Project paper', required=True)
        self.assertEqual(self.context()['scheduling_status'], 'preparing')
        set_endorsed(self.team, self.event.event_name, True, self.lead)
        self.assertEqual(self.context()['scheduling_status'], 'preparing')
        with patch('repository.deliverables.services.required_complete', return_value=True):
            self.assertEqual(self.context()['scheduling_status'], 'ready')

    def test_concept_readiness_uses_clearance_and_get_does_not_write(self):
        self.assertEqual(self.context()['scheduling_status'], 'preparing')
        concepts.save_titles(self.team, self.event,
            [{'key': f'c{i}', 'title': f'Proposal {i}'} for i in range(1, 4)], actor=self.lead)
        concepts.endorse(self.team, self.event, self.lead)
        with CaptureQueriesContext(connection) as queries:
            context = self.context()
        self.assertEqual(context['scheduling_status'], 'ready')
        writes = [q['sql'] for q in queries if q['sql'].lstrip().split()[0].upper()
            in ('INSERT', 'UPDATE', 'DELETE')]
        self.assertEqual(writes, [])
        # Compact triage may retain its endorsement status while full clearance
        # detects changed documents. Scheduling counts must use the full guard.
        with patch('repository.deliverables.concepts.clearance_blocker', return_value='Review changed papers.'):
            self.assertEqual(self.context()['scheduling_status'], 'preparing')

    def test_instructor_comes_from_active_section_assignment(self):
        def instructor():
            response = self.client.get('/api/teams/', {'roster_view': 'current'})
            self.assertEqual(response.status_code, 200, response.data)
            return response.data['teams'][0]['instructor_name']

        self.assertEqual(instructor(), self.lead.username)
        self.lead.is_active = False
        self.lead.save(update_fields=['is_active'])
        self.client.force_authenticate(self.admin)
        self.assertIsNone(instructor())
        self.lead.is_active = True
        self.lead.save(update_fields=['is_active'])
        SectionInstructorAssignment.objects.filter(faculty=self.lead).update(is_active=False)
        self.assertIsNone(instructor())
