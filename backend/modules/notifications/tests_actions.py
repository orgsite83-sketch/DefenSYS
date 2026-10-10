from importlib import import_module
from datetime import date, time

from django.apps import apps
from django.contrib.auth import get_user_model
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from defense.stages.models import StageDeliverable
from repository.deliverables.models import DeliverableSubmission
from defense.minutes.models import DefenseMinutes
from student_teams.models import StudentTeam, TeamMembership
from user_management.models import PanelistEligibilityRequest, ExternalEvaluator
from user_management.panelist_eligibility import nominate_panelist, review_nomination
from user_management.external_evaluators import register_evaluator, update_evaluator
from notifications.actions import resolve_actions
from notifications.models import Notification

User = get_user_model()


class NotificationActionTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.admin = User.objects.create_user(username='action-admin', role='admin')
        cls.lead = User.objects.create_user(username='action-lead', role='faculty', is_pit_lead=True, pit_lead_year='1st Year')
        cls.other = User.objects.create_user(username='action-other', role='faculty', is_pit_lead=True, pit_lead_year='2nd Year')
        cls.faculty = User.objects.create_user(username='action-faculty', role='faculty', first_name='Ana', last_name='Cruz', is_adviser=True)
        cls.doc = User.objects.create_user(username='action-documenter', role='faculty', is_documenter=True)
        cls.student = User.objects.create_user(username='action-student', role='student')

    def nomination(self):
        item, _ = nominate_panelist(self.lead, self.faculty.pk, 'Project expertise')
        alert = Notification.objects.get(recipient=self.admin, title='Panelist eligibility request')
        self.client.force_authenticate(self.admin)
        return item, alert

    def action(self, alert, workspace='admin'):
        response = self.client.get(f'/api/notifications/{alert.pk}/?workspace={workspace}')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data['notification']['action']

    def test_read_is_separate_from_approval_and_pending_alert_updates_after_review(self):
        item, alert = self.nomination()
        action = self.action(alert)
        self.assertEqual(action['status'], 'pending')
        self.assertEqual(action['route'], f'/admin/users?tab=faculty&view=panelists&section=requests&request={item.pk}')
        self.client.post(f'/api/notifications/{alert.pk}/read/?workspace=admin')
        self.assertEqual(self.action(alert)['status'], 'pending')
        review_nomination(self.admin, item, 'approved', 'Approved after review')
        action = self.action(alert)
        self.assertTrue(action['is_complete'])
        self.assertEqual(action['label'], 'Approved')
        self.assertEqual(action['cta'], 'View request')
        detail = self.client.get(f'/api/users/panelist-requests/{item.pk}/')
        self.assertEqual(detail.data['request']['review_note'], 'Approved after review')
        self.assertTrue(detail.data['can_review'])

    def test_review_does_not_mark_original_alert_read(self):
        item, alert = self.nomination()
        review_nomination(self.admin, item, 'declined', 'Insufficient experience')
        self.assertEqual(self.action(alert)['label'], 'Declined')
        alert.refresh_from_db()
        self.assertFalse(alert.is_read)
        self.client.force_authenticate(self.lead)
        detail = self.client.get(f'/api/users/panelist-requests/{item.pk}/')
        self.assertEqual(detail.status_code, 200)
        self.assertFalse(detail.data['can_review'])
        self.assertEqual(detail.data['request']['review_note'], 'Insufficient experience')
        self.assertEqual(self.client.patch(f'/api/users/panelist-requests/{item.pk}/', {'decision': 'approved'}, format='json').status_code, 403)
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get(f'/api/users/panelist-requests/{item.pk}/').status_code, 404)

    def test_deleted_target_is_unavailable_and_scoped_to_recipient(self):
        item, alert = self.nomination()
        item.delete()
        action = self.action(alert)
        self.assertEqual(action['status'], 'unavailable')
        self.assertIsNone(action['route'])
        self.assertEqual(self.client.get(f'/api/notifications/{alert.pk}/?workspace=pit_lead').status_code, 404)
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get(f'/api/notifications/{alert.pk}/?workspace=admin').status_code, 404)

    def test_central_request_history_keeps_reviewed_decisions_and_actor_scope(self):
        item, alert = self.nomination()
        review_nomination(self.admin, item, 'declined', 'More experience needed')
        response = self.client.get('/api/users/panelist-requests/?status=reviewed')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['pending_count'], 0)
        self.assertEqual(response.data['reviewed_count'], 1)
        self.assertEqual(response.data['panelist_requests'][0]['review_note'], 'More experience needed')
        PanelistEligibilityRequest.objects.create(faculty=self.faculty, requested_by=self.other, pit_year='2nd Year', status='declined')
        self.client.force_authenticate(self.lead)
        response = self.client.get('/api/users/panelist-requests/?status=all')
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['panelist_requests'][0]['requested_by_id'], self.lead.pk)
        notification = Notification.objects.get(recipient=self.lead, title='Panelist eligibility request declined')
        self.assertEqual(self.action(notification, 'pit_lead')['route'], f'/faculty/defense-board?panelistRequest={item.pk}')

    def test_central_request_history_paginates_and_rejects_invalid_filters(self):
        item, _ = self.nomination()
        for _ in range(25):
            PanelistEligibilityRequest.objects.create(faculty=self.faculty, requested_by=self.lead, pit_year='1st Year', status='declined')
        response = self.client.get('/api/users/panelist-requests/?status=reviewed')
        self.assertEqual(response.data['count'], 25)
        self.assertEqual(len(response.data['panelist_requests']), 20)
        self.assertIsNotNone(response.data['next'])
        self.assertEqual(response.data['pending_count'], 1)
        response = self.client.get('/api/users/panelist-requests/?status=reviewed&page=2')
        self.assertEqual(len(response.data['panelist_requests']), 5)
        self.assertIsNone(response.data['next'])
        self.assertEqual(self.client.get('/api/users/panelist-requests/?status=invalid').status_code, 400)
        self.assertEqual(self.client.get('/api/users/panelist-requests/?faculty_id=-1').status_code, 400)

    def test_central_requests_search_full_names_and_requester_ids(self):
        item, _ = self.nomination()
        self.faculty.first_name = 'Ana'
        self.faculty.last_name = 'Cruz'
        self.faculty.save(update_fields=['first_name', 'last_name'])
        for search in ('Ana Cruz', 'Cruz Ana', self.lead.username):
            response = self.client.get('/api/users/panelist-requests/', {'search': search})
            self.assertEqual(response.status_code, 200)
            self.assertEqual([r['id'] for r in response.data['panelist_requests']], [item.pk])
        response = self.client.get('/api/users/panelist-requests/', {'search': 'Ana Absent'})
        self.assertEqual(response.data['count'], 0)

    def test_external_approval_has_direct_target_and_live_status(self):
        item, _ = register_evaluator(self.lead, {'name': 'External Expert', 'email': 'external-actions@example.com'})
        alert = Notification.objects.get(recipient=self.admin, title='External evaluator approval requested')
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.action(alert)['route'], f'/admin/defense-board/requests/external/{item.pk}')
        update_evaluator(self.admin, item, {'status': 'approved'})
        self.assertEqual(self.action(alert)['label'], 'Approved')
        self.client.force_authenticate(self.lead)
        self.assertEqual(self.client.get(f'/api/users/external-evaluators/{item.pk}/').status_code, 200)
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get(f'/api/users/external-evaluators/{item.pk}/').status_code, 404)

    def test_resolver_batches_requests_in_one_query(self):
        item, alert = self.nomination()
        alerts = [alert] + [Notification.objects.create(recipient=self.admin, title='Duplicate fixture',
                   action_payload={'action_kind': 'panelist_request', 'request_id': item.pk}) for _ in range(19)]
        with CaptureQueriesContext(connection) as queries:
            actions = resolve_actions(alerts, self.admin)
        self.assertEqual(len(queries), 1)
        self.assertEqual(len(actions), 20)

    def test_minutes_completion_is_for_the_requested_signature(self):
        semester = Semester.objects.create(school_year=SchoolYear.objects.create(label='2026-2027'), label=Semester.FIRST, is_active=True)
        team = StudentTeam.objects.create(name='Action Team', project_title='Action Project', level=StudentTeam.LEVEL_3_CAPSTONE,
                                        semester=semester, adviser=self.faculty, year_level='3rd Year', leader=self.student)
        schedule = DefenseSchedule.objects.create(scope='capstone', team=team, semester=semester, scheduled_date=date(2026, 10, 20),
                                                  start_time=time(9), room='Room 101', documenter=self.doc,
                                                  defense_stage=DefenseStage.objects.get_or_create(label='Concept Proposal')[0])
        minutes = DefenseMinutes.objects.create(schedule=schedule, team_name=team.name, project_title=team.project_title,
            adviser_name='Ana Cruz', defense_stage_label='Proposal', defense_date=date(2026, 10, 20), defense_time=time(9),
            room='Room 101', documenter_name='Documenter', status='submitted', documenter_signed_at=timezone.now())
        adviser = Notification.objects.create(recipient=self.faculty, title='Minutes Ready for Review', category='MINUTES', workspace='adviser', action_payload={'schedule_id': schedule.pk})
        chair = Notification.objects.create(recipient=self.admin, title='Minutes Awaiting Final Signature', category='MINUTES', workspace='admin', action_payload={'schedule_id': schedule.pk})
        self.client.force_authenticate(self.faculty)
        self.assertEqual(self.action(adviser, 'adviser')['status'], 'pending')
        minutes.adviser_signed_at = timezone.now()
        minutes.status = 'adviser_signed'
        minutes.save()
        self.assertTrue(self.action(adviser, 'adviser')['is_complete'])
        self.assertEqual(self.action(adviser, 'adviser')['route'], f'/faculty/defense-board/minutes/{schedule.pk}')
        self.client.force_authenticate(self.admin)
        self.assertFalse(self.action(chair)['is_complete'])
        schedule.status = 'cancelled'
        schedule.save()
        self.assertEqual(self.action(chair)['status'], 'cancelled')

    def test_legacy_migration_matches_one_request_and_leaves_ambiguous_alerts(self):
        item, alert = self.nomination()
        alert.action_payload = {'panelist_eligibility': True}
        alert.action_route = '/admin/defense-board'
        alert.save()
        migration = import_module('notifications.migrations.0005_notification_action_targets')
        migration.backfill_action_targets(apps, type('Editor', (), {'connection': connection})())
        alert.refresh_from_db()
        self.assertEqual(alert.action_payload['request_id'], item.pk)
        self.assertFalse(alert.is_read)
        # A second request with the same author/name/time cannot be guessed.
        PanelistEligibilityRequest.objects.create(faculty=self.faculty, requested_by=self.lead,
                                                  pit_year='1st Year', status='declined')
        alert.action_payload = {'panelist_eligibility': True}
        alert.action_route = '/admin/defense-board'
        alert.save()
        migration.backfill_action_targets(apps, type('Editor', (), {'connection': connection})())
        alert.refresh_from_db()
        self.assertNotIn('request_id', alert.action_payload)

    def test_deliverable_reminder_targets_stage_and_waits_for_accepted_files(self):
        semester = Semester.objects.create(school_year=SchoolYear.objects.create(label='2026-2027'), label=Semester.FIRST, is_active=True)
        team = StudentTeam.objects.create(name='Reminder Team', project_title='Reminder Project', level=StudentTeam.LEVEL_3_CAPSTONE,
            semester=semester, adviser=self.faculty, year_level='3rd Year', leader=self.student)
        TeamMembership.objects.create(team=team, student=self.student, is_leader=True)
        stage = DefenseStage.objects.get_or_create(label='Project Proposal')[0]
        StageDeliverable.objects.create(defense_stage=stage, deliverable_id='action-pre', label='Proposal', required=True, deliverable_type='pre')
        self.client.force_authenticate(self.admin)
        response = self.client.post(f'/api/teams/{team.pk}/remind/', {'stage_label': stage.label}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        alert = Notification.objects.get(recipient=self.student, workspace='student')
        self.assertEqual(alert.action_payload['deliverable_task'], 'submit')
        self.client.force_authenticate(self.student)
        action = self.action(alert, 'student')
        self.assertEqual(action['status'], 'pending')
        self.assertIn('stage=Project+Proposal', action['route'])
        self.assertIn('subtab=deliverables', action['route'])
        submission = DeliverableSubmission.objects.create(team=team, stage_label=stage.label, deliverable_id='action-pre',
            label='Proposal', deliverable_type='pre', required=True, status='rejected', file_name='proposal.pdf')
        self.assertFalse(self.action(alert, 'student')['is_complete'])
        submission.status = 'accepted'
        submission.save()
        self.assertTrue(self.action(alert, 'student')['is_complete'])
        alert.action_payload['deliverable_task'] = 'endorse'
        alert.save()
        self.assertFalse(self.action(alert, 'student')['is_complete'])
        # Old alerts without an original task cannot falsely finish on uploads.
        alert.action_payload.pop('deliverable_task')
        alert.save()
        self.assertFalse(self.action(alert, 'student')['is_complete'])
