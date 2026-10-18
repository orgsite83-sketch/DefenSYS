from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import PitEventGradingConfig
from .models import Rubric, RubricCriterion


class PitRubricAssignmentTests(APITestCase):
    def setUp(self):
        year = SchoolYear.objects.create(label='2097-2098')
        self.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        self.other_semester = Semester.objects.create(school_year=year, label=Semester.SECOND)
        self.lead = get_user_model().objects.create_user(
            username='assignment-lead', role='faculty', is_pit_lead=True, pit_lead_year='2nd Year')
        self.event = self.make_event('Configured event')
        self.other_event = self.make_event('Another event')
        self.client.force_authenticate(self.lead)

    def make_event(self, name, **changes):
        return PitEventGradingConfig.objects.create(**{
            'semester': self.semester, 'year_level': '2nd Year', 'event_name': name,
            'panel_weight': 75, 'peer_weight': 25, 'archive_file_template': '{event}_{project}',
            **changes,
        })

    def payload(self, **changes):
        return {
            'name': 'Event rubric', 'scope': 'pit', 'semester_id': self.semester.pk,
            'evaluation_type': 'panel', 'status': 'published', 'pit_event_id': self.event.pk,
            'criteria': [{'name': 'Quality', 'max_score': 10, 'weight': 100}],
            **changes,
        }

    def create(self, **changes):
        response = self.client.post('/api/grading/rubrics/', self.payload(**changes), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        return Rubric.objects.get(pk=response.data['rubric']['id']), response

    def update(self, rubric, **changes):
        return self.client.patch(f'/api/grading/rubrics/{rubric.pk}/', self.payload(**changes), format='json')

    def test_create_assigns_correct_slot_and_reload_keeps_event(self):
        for kind in ('panel', 'peer'):
            with self.subTest(kind=kind):
                rubric, response = self.create(evaluation_type=kind)
                self.event.refresh_from_db()
                self.assertEqual(getattr(self.event, f'{kind}_rubric_id'), rubric.pk)
                self.assertEqual(response.data['rubric']['pit_event_id'], self.event.pk)
                if kind == 'peer':
                    self.assertEqual(rubric.target_type, Rubric.TARGET_INDIVIDUAL)
        self.assertEqual((self.event.panel_weight, self.event.peer_weight), (75, 25))
        self.assertEqual(self.event.archive_file_template, '{event}_{project}')
        self.assertEqual(PitEventGradingConfig.objects.count(), 2)
        detail = self.client.get(f'/api/grading/rubrics/{rubric.pk}/')
        self.assertEqual(detail.data['rubric']['pit_event_id'], self.event.pk)
        log = SystemAuditLog.objects.filter(action='rubric.create').last()
        self.assertEqual(log.new_values['pit_event_id'], self.event.pk)
        self.assertTrue(SystemAuditLog.objects.filter(action='pit_event.update').exists())

    def test_update_assigns_existing_template_and_preserves_other_slot(self):
        peer, _ = self.create(evaluation_type='peer')
        panel, _ = self.create(pit_event_id=None)
        response = self.update(panel)
        self.assertEqual(response.status_code, 200, response.data)
        self.event.refresh_from_db()
        self.assertEqual(self.event.panel_rubric_id, panel.pk)
        self.assertEqual(self.event.peer_rubric_id, peer.pk)

    def test_move_and_clear_assignment_leave_no_stale_links(self):
        rubric, _ = self.create()
        response = self.update(rubric, pit_event_id=self.other_event.pk)
        self.assertEqual(response.status_code, 200, response.data)
        self.event.refresh_from_db()
        self.other_event.refresh_from_db()
        self.assertIsNone(self.event.panel_rubric_id)
        self.assertEqual(self.other_event.panel_rubric_id, rubric.pk)
        response = self.update(rubric, pit_event_id=None)
        self.assertEqual(response.status_code, 200, response.data)
        self.other_event.refresh_from_db()
        self.assertIsNone(self.other_event.panel_rubric_id)
        self.assertIsNone(response.data['rubric']['pit_event_id'])

    def test_changing_evaluation_type_moves_the_slot(self):
        rubric, _ = self.create()
        response = self.update(rubric, evaluation_type='peer')
        self.assertEqual(response.status_code, 200, response.data)
        self.event.refresh_from_db()
        self.assertIsNone(self.event.panel_rubric_id)
        self.assertEqual(self.event.peer_rubric_id, rubric.pk)

    def test_replacing_slot_detaches_previous_template(self):
        previous, _ = self.create()
        replacement, _ = self.create(name='Replacement')
        self.event.refresh_from_db()
        self.assertEqual(self.event.panel_rubric_id, replacement.pk)
        detail = self.client.get(f'/api/grading/rubrics/{previous.pk}/')
        self.assertIsNone(detail.data['rubric']['pit_event_id'])

    def test_options_are_year_scoped_and_include_lock_and_semester(self):
        other_year = self.make_event('Private first year', year_level='1st Year')
        self.event.is_officially_complete = True
        self.event.save(update_fields=['is_officially_complete'])
        response = self.client.get('/api/grading/rubrics/')
        options = {event['id']: event for event in response.data['pit_events']}
        self.assertNotIn(other_year.pk, options)
        self.assertEqual(options[self.event.pk]['semester_id'], self.semester.pk)
        self.assertTrue(options[self.event.pk]['is_locked'])
        self.assertTrue(options[self.event.pk]['lock_reason'])

    def test_invalid_foreign_year_and_wrong_semester_ids_roll_back_creation(self):
        foreign = self.make_event('Foreign', year_level='1st Year')
        wrong_term = self.make_event('Other term', semester=self.other_semester)
        for event_id in (99999999, foreign.pk, wrong_term.pk):
            with self.subTest(event_id=event_id):
                response = self.client.post('/api/grading/rubrics/', self.payload(pit_event_id=event_id), format='json')
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('pit_event_id', response.data)
                self.assertFalse(Rubric.objects.exists())

    def test_locked_destination_rolls_back_move_and_criterion_changes(self):
        rubric, _ = self.create()
        self.other_event.is_officially_complete = True
        self.other_event.save(update_fields=['is_officially_complete'])
        response = self.update(rubric, pit_event_id=self.other_event.pk, name='Should roll back',
                               criteria=[{'name': 'Changed', 'max_score': 10, 'weight': 100}])
        self.assertEqual(response.status_code, 400, response.data)
        rubric.refresh_from_db()
        self.event.refresh_from_db()
        self.other_event.refresh_from_db()
        self.assertEqual(rubric.name, 'Event rubric')
        self.assertEqual(rubric.criteria.get().name, 'Quality')
        self.assertEqual(self.event.panel_rubric_id, rubric.pk)
        self.assertIsNone(self.other_event.panel_rubric_id)

    def test_locked_source_cannot_be_unassigned(self):
        rubric, _ = self.create()
        self.event.is_officially_complete = True
        self.event.save(update_fields=['is_officially_complete'])
        response = self.update(rubric, pit_event_id=None)
        self.assertEqual(response.status_code, 400, response.data)
        self.event.refresh_from_db()
        self.assertEqual(self.event.panel_rubric_id, rubric.pk)

    def test_old_client_omitting_event_preserves_assignment_but_cannot_change_term(self):
        rubric, _ = self.create()
        data = self.payload(name='Edited template')
        data.pop('pit_event_id')
        response = self.client.patch(f'/api/grading/rubrics/{rubric.pk}/', data, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.event.refresh_from_db()
        self.assertEqual(self.event.panel_rubric_id, rubric.pk)
        data['semester_id'] = self.other_semester.pk
        response = self.client.patch(f'/api/grading/rubrics/{rubric.pk}/', data, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        rubric.refresh_from_db()
        self.assertEqual(rubric.semester_id, self.semester.pk)

    def test_capstone_rubric_cannot_be_assigned_to_pit_event(self):
        admin = get_user_model().objects.create_user(username='assignment-admin', role='admin')
        self.client.force_authenticate(admin)
        response = self.client.post('/api/grading/rubrics/', self.payload(scope='capstone'), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(Rubric.objects.exists())

    def test_failed_audit_rolls_back_template_and_assignment(self):
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('Offline')):
            response = self.client.post('/api/grading/rubrics/', self.payload(), format='json')
        self.assertEqual(response.status_code, 500)
        self.assertFalse(Rubric.objects.exists())
        self.assertFalse(RubricCriterion.objects.exists())
        self.event.refresh_from_db()
        self.assertIsNone(self.event.panel_rubric_id)
