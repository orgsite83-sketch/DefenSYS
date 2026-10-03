from types import SimpleNamespace

from django.contrib.auth import get_user_model
from rest_framework.exceptions import ValidationError
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.scheduler.serializers import DefenseScheduleWriteSerializer
from grading.rubrics.models import Rubric
from notifications.models import Notification
from student_teams.models import StudentTeam
from .models import FacultyRoleAssignment, PanelistEligibilityRequest


User = get_user_model()
REQUESTS = '/api/users/panelist-requests/'
SCHEDULES = '/api/defense/schedules/'


class PanelistEligibilityTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.admin = User.objects.create_user(username='elig-admin', role='admin')
        cls.lead = User.objects.create_user(username='elig-lead', role='faculty', is_pit_lead=True, pit_lead_year='1st Year')
        cls.other_lead = User.objects.create_user(username='elig-other-lead', role='faculty', is_pit_lead=True, pit_lead_year='2nd Year')
        cls.faculty = User.objects.create_user(username='elig-faculty', first_name='Lina', last_name='Santos', role='faculty')
        cls.student = User.objects.create_user(username='elig-student', role='student')
        cls.semester = Semester.objects.create(school_year=SchoolYear.objects.create(label='2026-2027'), label=Semester.FIRST, is_active=True)
        cls.team = StudentTeam.objects.create(name='Eligibility Team', project_title='Prototype', level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', semester=cls.semester, leader=cls.student)
        cls.panel = Rubric.objects.create(name='PIT eligibility panel', scope=Rubric.SCOPE_PIT, semester=cls.semester, evaluation_type=Rubric.EVAL_PANEL, status=Rubric.STATUS_PUBLISHED, created_by=cls.lead)
        cls.peer = Rubric.objects.create(name='PIT eligibility peer', scope=Rubric.SCOPE_PIT, semester=cls.semester, evaluation_type=Rubric.EVAL_PEER, status=Rubric.STATUS_PUBLISHED, created_by=cls.lead)

    def payload(self, **changes):
        data = {'scope': 'pit', 'team_id': self.team.pk, 'semester_id': self.semester.pk, 'event_name': 'PIT 1 Presentation', 'rubric_id': self.panel.pk, 'peer_rubric_id': self.peer.pk, 'scheduled_date': '2026-10-20', 'start_time': '08:00', 'slot_duration': 60, 'room': 'Lab 1', 'panelist_ids': [self.faculty.pk]}
        data.update(changes)
        return data

    def nominate(self, actor=None):
        self.client.force_authenticate(actor or self.lead)
        response = self.client.post(REQUESTS, {'faculty_id': self.faculty.pk, 'reason': 'Relevant project expertise'}, format='json')
        self.assertIn(response.status_code, (200, 201), response.data)
        return response.data['request']

    def test_admin_schedule_approves_and_pool_is_reusable(self):
        request = self.nominate()
        self.client.force_authenticate(self.admin)
        response = self.client.post(SCHEDULES, self.payload(), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.faculty.refresh_from_db()
        self.assertTrue(self.faculty.is_panelist)
        self.assertTrue(FacultyRoleAssignment.objects.filter(user=self.faculty, role_key='panelist', action='assigned', changed_by=self.admin).exists())
        self.assertEqual(PanelistEligibilityRequest.objects.get(pk=request['id']).status, 'approved')
        self.client.force_authenticate(self.lead)
        other_team = StudentTeam.objects.create(name='Second Eligibility Team', project_title='Another Prototype', level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', semester=self.semester, leader=self.student)
        response = self.client.post(SCHEDULES, self.payload(team_id=other_team.pk, start_time='10:00'), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(PanelistEligibilityRequest.objects.count(), 1)
        self.assertEqual(FacultyRoleAssignment.objects.filter(user=self.faculty, role_key='panelist').count(), 1)

    def test_rbac_grant_without_nomination_preserves_other_duties_and_credentials(self):
        self.faculty.is_documenter = True
        self.faculty.is_adviser = True
        self.faculty.save(update_fields=['is_documenter', 'is_adviser'])
        password_before = self.faculty.password
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f'/api/users/{self.faculty.pk}/', {'is_panelist': True}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.faculty.refresh_from_db()
        self.assertTrue(self.faculty.is_panelist)
        self.assertTrue(self.faculty.is_documenter)
        self.assertTrue(self.faculty.is_adviser)
        self.assertEqual(self.faculty.role, 'faculty')
        self.assertEqual(self.faculty.password, password_before)
        self.assertFalse(PanelistEligibilityRequest.objects.exists())
        self.assertEqual(FacultyRoleAssignment.objects.filter(user=self.faculty, role_key='panelist', action='assigned', changed_by=self.admin).count(), 1)

    def test_rbac_grant_resolves_pending_requests_without_duplicate_role_history(self):
        request = self.nominate()
        self.client.force_authenticate(self.admin)
        for _ in range(2):
            response = self.client.patch(f'/api/users/{self.faculty.pk}/', {'is_panelist': True}, format='json')
            self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(PanelistEligibilityRequest.objects.get(pk=request['id']).status, 'approved')
        self.assertEqual(Notification.objects.filter(title='Panelist eligibility approved').count(), 1)
        self.assertEqual(FacultyRoleAssignment.objects.filter(user=self.faculty, role_key='panelist', action='assigned').count(), 1)

    def test_rbac_removal_revokes_only_panelist_duty_and_updates_scheduler_pool(self):
        self.client.force_authenticate(self.admin)
        url = f'/api/users/{self.lead.pk}/'
        self.assertEqual(self.client.patch(url, {'is_panelist': True}, format='json').status_code, 200)
        response = self.client.patch(url, {'is_panelist': False}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.lead.refresh_from_db()
        self.assertFalse(self.lead.is_panelist)
        self.assertTrue(self.lead.is_pit_lead)
        self.assertEqual(self.lead.pit_lead_year, '1st Year')
        self.assertTrue(FacultyRoleAssignment.objects.filter(user=self.lead, role_key='panelist', action='revoked', changed_by=self.admin).exists())
        self.client.force_authenticate(self.lead)
        response = self.client.get(SCHEDULES)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertNotIn(self.lead.pk, [p['id'] for p in response.data['panelists']])

    def test_pit_lead_cannot_change_eligibility_through_rbac(self):
        self.client.force_authenticate(self.lead)
        response = self.client.patch(f'/api/users/{self.faculty.pk}/', {'is_panelist': True}, format='json')
        self.assertEqual(response.status_code, 403, response.data)
        self.faculty.refresh_from_db()
        self.assertFalse(self.faculty.is_panelist)
        self.assertFalse(FacultyRoleAssignment.objects.exists())

    def test_lead_cannot_promote_using_manual_generate_or_confirm(self):
        self.client.force_authenticate(self.lead)
        for suffix, extra in [('', {}), ('generate-plan/', {}), ('confirm-plan/', {'slots': [{'team_id': self.team.pk}]})]:
            response = self.client.post(SCHEDULES + suffix, self.payload(**extra), format='json')
            self.assertEqual(response.status_code, 400, response.data)
            self.assertIn('panelist_ids', response.data)
        self.faculty.refresh_from_db()
        self.assertFalse(self.faculty.is_panelist)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_admin_preview_does_not_approve_until_confirmation(self):
        self.client.force_authenticate(self.admin)
        generated = self.client.post(SCHEDULES + 'generate-plan/', self.payload(), format='json')
        self.assertEqual(generated.status_code, 200, generated.data)
        self.faculty.refresh_from_db()
        self.assertFalse(self.faculty.is_panelist)
        response = self.client.post(SCHEDULES + 'confirm-plan/', self.payload(slots=[{'team_id': self.team.pk, 'start_time': '08:00'}]), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.faculty.refresh_from_db()
        self.assertTrue(self.faculty.is_panelist)

    def test_duplicate_nomination_does_not_notify_again(self):
        first = self.nominate()
        count = Notification.objects.filter(recipient=self.admin).count()
        second = self.nominate()
        self.assertEqual(first['id'], second['id'])
        self.assertEqual(PanelistEligibilityRequest.objects.count(), 1)
        self.assertEqual(Notification.objects.filter(recipient=self.admin).count(), count)

    def test_approval_resolves_all_requests_for_same_faculty(self):
        first = self.nominate()
        self.nominate(self.other_lead)
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f"{REQUESTS}{first['id']}/", {'decision': 'approved'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(PanelistEligibilityRequest.objects.filter(status='approved').count(), 2)
        self.assertEqual(Notification.objects.filter(title='Panelist eligibility approved').count(), 2)
        self.client.force_authenticate(self.lead)
        response = self.client.post(REQUESTS, {'faculty_id': self.faculty.pk}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['already_eligible'])
        self.assertEqual(PanelistEligibilityRequest.objects.count(), 2)

    def test_decline_does_not_grant_and_allows_later_nomination(self):
        item = self.nominate()
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f"{REQUESTS}{item['id']}/", {'decision': 'declined', 'review_note': 'Please clarify expertise.'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.faculty.refresh_from_db()
        self.assertFalse(self.faculty.is_panelist)
        self.assertNotEqual(self.nominate()['id'], item['id'])

    def test_lead_cannot_review_or_read_other_leads_requests(self):
        own = self.nominate()
        other = self.nominate(self.other_lead)
        self.client.force_authenticate(self.lead)
        response = self.client.patch(f"{REQUESTS}{own['id']}/", {'decision': 'approved'}, format='json')
        self.assertEqual(response.status_code, 403)
        ids = {item['id'] for item in self.client.get(REQUESTS).data['panelist_requests']}
        self.assertEqual(ids, {own['id']})
        self.assertNotIn(other['id'], ids)
        for actor in (self.faculty, self.student):
            self.client.force_authenticate(actor)
            self.assertEqual(self.client.get(REQUESTS).status_code, 403)
            self.assertEqual(self.client.post(REQUESTS, {'faculty_id': self.faculty.pk}, format='json').status_code, 403)

    def test_nomination_rejects_students_and_inactive_faculty(self):
        self.client.force_authenticate(self.lead)
        self.assertEqual(self.client.post(REQUESTS, {'faculty_id': self.student.pk}, format='json').status_code, 400)
        self.faculty.is_active = False
        self.faculty.save(update_fields=['is_active'])
        self.assertEqual(self.client.post(REQUESTS, {'faculty_id': self.faculty.pk}, format='json').status_code, 400)

    def test_revocation_after_validation_blocks_commit(self):
        self.faculty.is_panelist = True
        self.faculty.save(update_fields=['is_panelist'])
        serializer = DefenseScheduleWriteSerializer(data=self.payload(), context={'request': SimpleNamespace(user=self.lead)})
        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.faculty.is_panelist = False
        self.faculty.save(update_fields=['is_panelist'])
        with self.assertRaises(ValidationError):
            serializer.save()
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_eligibility_alone_does_not_grant_assigned_defense_access(self):
        item = self.nominate()
        self.client.force_authenticate(self.admin)
        self.client.patch(f"{REQUESTS}{item['id']}/", {'decision': 'approved'}, format='json')
        self.faculty.refresh_from_db()
        self.client.force_authenticate(self.faculty)
        response = self.client.get(SCHEDULES + 'panelist-assignments/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['teams'], [])
        self.assertFalse(self.client.get(SCHEDULES).data['schedules'])

    def test_faculty_account_import_resolves_request_and_audits_approval(self):
        item = self.nominate()
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/users/bulk-import/', {'users': [{'id_number': self.faculty.username, 'role': 'faculty', 'is_panelist': True}]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(PanelistEligibilityRequest.objects.get(pk=item['id']).status, 'approved')
        self.assertTrue(FacultyRoleAssignment.objects.filter(user=self.faculty, role_key='panelist', changed_by=self.admin).exists())

    def test_scheduler_options_report_authority_and_eligibility(self):
        for actor, can_approve in [(self.admin, True), (self.lead, False)]:
            self.client.force_authenticate(actor)
            options = self.client.get(SCHEDULES).data
            self.assertEqual(options['can_approve_panelists'], can_approve)
            self.assertEqual(options['requires_panelist_approval'], not can_approve)
            faculty = next(p for p in options['faculty'] if p['id'] == self.faculty.pk)
            self.assertFalse(faculty['is_panelist'])
