from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import patch

from django.core.cache import cache
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework.exceptions import ValidationError
from rest_framework_simplejwt.tokens import AccessToken

from authentication_access_control.guest_tokens import create_guest_access_token
from authentication_access_control.guest_authentication import GuestPanelistPrincipal
from defense.scheduler import tests as fixtures
from defense.stages.models import DefenseStage
from defense.scheduler.models import DefenseSchedule, PanelistEvaluationDraft, PitEventGradingConfig
from defense.scheduler.serializers import ConfirmSchedulePlanSerializer
from defense.scheduler.panelist_evaluation import evaluation_context
from grading.grades.models import PanelistGradeSubmission
from notifications.models import Notification
from student_teams.models import StudentTeam
from grading.rubrics.models import Rubric, RubricCriterion
from .external_evaluators import create_invitations
from .models import ExternalEvaluator, GuestPanelistCode

DIRECTORY = '/api/users/external-evaluators/'
INVITATIONS = '/api/users/external-invitations/'
SCHEDULES = '/api/defense/schedules/'


class ExternalEvaluatorTests(APITestCase):
    def setUp(self):
        fixtures.DefenseSchedulerApiTests.setUp(self)
        self.lead = fixtures.User.objects.create_user(username='external-lead', role='faculty', is_pit_lead=True, pit_lead_year='1st Year')
        self.evaluator = ExternalEvaluator.objects.create(name='Dr. Lina Santos', email='lina@example.edu', institution='Partner University', status='approved', created_by=self.admin, reviewed_by=self.admin)
        cache.clear()

    def schedule(self, team=None, **values):
        defaults = dict(scope='capstone', semester=self.semester, team=team or self.team, defense_stage=self.stage, rubric=self.rubric, scheduled_date=timezone.localdate(), start_time='08:00', slot_duration=60, room='Lab 1', created_by=self.admin)
        defaults.update(values)
        return DefenseSchedule.objects.create(**defaults)

    def invite(self, schedules=None):
        schedules = schedules or [self.schedule()]
        return create_invitations([self.evaluator], schedules, self.admin)[0]

    def guest(self, invitation):
        self.client.force_authenticate(user=None)
        token = create_guest_access_token(invitation)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        return token

    def payload(self, **values):
        return fixtures.DefenseSchedulerApiTests.schedule_payload(self, scheduled_date=timezone.localdate().isoformat(), external_evaluator_ids=[self.evaluator.pk], **values)

    def test_admin_creates_approved_reusable_record_without_credentials(self):
        before = fixtures.User.objects.count()
        response = self.client.post(DIRECTORY, {'name': 'Guest Expert', 'email': 'EXPERT@example.edu'}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['evaluator']['status'], 'approved')
        self.assertEqual(fixtures.User.objects.count(), before)
        self.assertFalse(GuestPanelistCode.objects.exists())
        repeated = self.client.post(DIRECTORY, {'name': 'Same email', 'email': 'expert@example.edu'}, format='json')
        self.assertEqual(repeated.status_code, 200)
        self.assertEqual(repeated.data['evaluator']['id'], response.data['evaluator']['id'])

    def test_institutional_account_uses_faculty_pool(self):
        self.panelist.email = 'faculty@example.edu'
        self.panelist.save(update_fields=['email'])
        response = self.client.post(DIRECTORY, {'name': 'Faculty', 'email': self.panelist.email}, format='json')
        self.assertEqual(response.status_code, 400)

    def test_lead_requests_once_then_reuses_admin_approval(self):
        self.client.force_authenticate(self.lead)
        data = {'name': 'PIT Expert', 'email': 'pit-expert@example.edu'}
        first = self.client.post(DIRECTORY, data, format='json')
        count = Notification.objects.filter(title='External evaluator approval requested').count()
        repeated = self.client.post(DIRECTORY, data, format='json')
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(first.data['evaluator']['status'], 'pending')
        self.assertEqual(first.data['evaluator']['id'], repeated.data['evaluator']['id'])
        self.assertEqual(Notification.objects.filter(title='External evaluator approval requested').count(), count)
        url = f"{DIRECTORY}{first.data['evaluator']['id']}/"
        self.assertEqual(self.client.patch(url, {'status': 'approved'}, format='json').status_code, 403)
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.client.patch(url, {'status': 'approved'}, format='json').status_code, 200)
        self.client.force_authenticate(self.lead)
        repeated = self.client.post(DIRECTORY, data, format='json')
        self.assertEqual(repeated.data['evaluator']['status'], 'approved')
        self.assertEqual(Notification.objects.filter(title='External evaluator approval requested').count(), count)

    def test_faculty_and_students_cannot_manage_evaluators(self):
        for user in [self.panelist, self.student]:
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get(DIRECTORY).status_code, 403)

    def test_preview_creates_no_access_confirm_creates_one_batch_invitation(self):
        response = self.client.post(SCHEDULES + 'generate-plan/', self.payload(), format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(GuestPanelistCode.objects.exists())
        other = fixtures.DefenseSchedulerApiTests.create_ready_team(self)
        response = self.client.post(SCHEDULES + 'confirm-plan/', self.payload(slots=[{'team_id': self.team.pk}, {'team_id': other.pk}]), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        invitation = GuestPanelistCode.objects.get()
        self.assertEqual(invitation.schedules.count(), 2)
        self.assertEqual(len(response.data['created_invitations']), 1)
        self.assertIsNotNone(invitation.expires_at)

    def test_approval_withdrawn_before_confirmation_rolls_back_schedule(self):
        serializer = ConfirmSchedulePlanSerializer(data=self.payload(slots=[{'team_id': self.team.pk}]), context={'request': SimpleNamespace(user=self.admin)})
        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.evaluator.is_active = False
        self.evaluator.save(update_fields=['is_active'])
        with self.assertRaises(ValidationError):
            serializer.save()
        self.assertFalse(DefenseSchedule.objects.exists())
        self.assertFalse(GuestPanelistCode.objects.exists())

    def test_manual_schedule_returns_invitation(self):
        response = self.client.post(SCHEDULES, self.payload(team_id=self.team.pk), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(len(response.data['created_invitations']), 1)

    def test_inviting_twice_reuses_identity_and_partial_overlap_is_rejected(self):
        schedule = self.schedule()
        first = self.invite([schedule])
        second = self.invite([schedule])
        self.assertEqual(first.pk, second.pk)
        other = self.schedule(fixtures.DefenseSchedulerApiTests.create_ready_team(self), start_time='09:00')
        with self.assertRaises(ValidationError):
            self.invite([schedule, other])
        self.assertEqual(GuestPanelistCode.objects.count(), 1)

    def test_external_evaluator_conflicting_defense_is_rejected(self):
        self.invite()
        other = self.schedule(fixtures.DefenseSchedulerApiTests.create_ready_team(self), start_time='08:30', room='Lab 2')
        with self.assertRaises(ValidationError):
            self.invite([other])

    def test_assigning_multiple_capstone_stages_creates_separate_access_for_each_evaluator(self):
        first = self.schedule()
        stage = DefenseStage.objects.create(label='External final defense', display_order=90)
        final = self.schedule(defense_stage=stage, rubric=None, scheduled_date=timezone.localdate() + timedelta(days=7))
        second_evaluator = ExternalEvaluator.objects.create(name='Dr. Alex Reyes', status='approved', created_by=self.admin)
        data = {'evaluator_ids': [self.evaluator.pk, second_evaluator.pk], 'schedule_ids': [first.pk, final.pk]}
        response = self.client.post(INVITATIONS, data, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(len(response.data['created_invitations']), 4)
        self.assertEqual(GuestPanelistCode.objects.count(), 4)
        for invitation in GuestPanelistCode.objects.all():
            self.assertEqual(invitation.schedules.count(), 1)
        codes = set(GuestPanelistCode.objects.values_list('code', flat=True))
        response = self.client.post(INVITATIONS, data, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(set(GuestPanelistCode.objects.values_list('code', flat=True)), codes)
        first_invitation = GuestPanelistCode.objects.get(evaluator=self.evaluator, schedules=first)
        self.guest(first_invitation)
        response = self.client.get(SCHEDULES + 'guest-assignments/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([team['schedule_id'] for team in response.data['teams']], [first.pk])

    def test_pit_lead_can_assign_multiple_events_in_their_year(self):
        own = StudentTeam.objects.create(name='PIT event team', level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', semester=self.semester, leader=self.student)
        pitch = self.schedule(own, scope='pit', defense_stage=None, rubric=None, event_name='Concept Pitch')
        demo = self.schedule(own, scope='pit', defense_stage=None, rubric=None, event_name='Prototype Demo', scheduled_date=timezone.localdate() + timedelta(days=7))
        self.client.force_authenticate(self.lead)
        response = self.client.post(INVITATIONS, {'evaluator_ids': [self.evaluator.pk], 'schedule_ids': [pitch.pk, demo.pk]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(len(response.data['created_invitations']), 2)
        self.assertEqual({i['schedules'][0]['stage_label'] for i in response.data['created_invitations']}, {'Concept Pitch', 'Prototype Demo'})

    def test_selected_sessions_with_overlapping_times_are_rejected_atomically(self):
        first = self.schedule()
        stage = DefenseStage.objects.create(label='Overlapping external stage', display_order=91)
        other = self.schedule(defense_stage=stage, rubric=None, start_time='08:30', room='Lab 2')
        response = self.client.post(INVITATIONS, {'evaluator_ids': [self.evaluator.pk], 'schedule_ids': [first.pk, other.pk]}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('overlap', str(response.data))
        self.assertFalse(GuestPanelistCode.objects.exists())

    def test_later_session_failure_rolls_back_earlier_assignments(self):
        stage = DefenseStage.objects.create(label='Later external stage', display_order=92)
        other_team = fixtures.DefenseSchedulerApiTests.create_ready_team(self)
        reserved = self.schedule(other_team, defense_stage=stage, rubric=None, start_time='08:30', scheduled_date=timezone.localdate() + timedelta(days=7))
        original = self.invite([reserved])
        first = self.schedule()
        final = self.schedule(defense_stage=stage, rubric=None, scheduled_date=reserved.scheduled_date)
        response = self.client.post(INVITATIONS, {'evaluator_ids': [self.evaluator.pk], 'schedule_ids': [first.pk, final.pk]}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(list(GuestPanelistCode.objects.values_list('pk', flat=True)), [original.pk])

    def test_multi_event_request_cannot_expand_pit_lead_scope(self):
        own = StudentTeam.objects.create(name='Own event year', level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', semester=self.semester, leader=self.student)
        other = StudentTeam.objects.create(name='Other event year', level=StudentTeam.LEVEL_2_PIT, year_level='2nd Year', semester=self.semester, leader=self.student)
        first = self.schedule(own, scope='pit', defense_stage=None, rubric=None, event_name='Pitch')
        second = self.schedule(other, scope='pit', defense_stage=None, rubric=None, event_name='Demo', start_time='10:00')
        self.client.force_authenticate(self.lead)
        response = self.client.post(INVITATIONS, {'evaluator_ids': [self.evaluator.pk], 'schedule_ids': [first.pk, second.pk]}, format='json')
        self.assertEqual(response.status_code, 403, response.data)
        self.assertFalse(GuestPanelistCode.objects.exists())

    def test_multi_stage_expiry_must_cover_the_last_defense(self):
        first = self.schedule()
        stage = DefenseStage.objects.create(label='Future external stage', display_order=93)
        final = self.schedule(defense_stage=stage, rubric=None, scheduled_date=timezone.localdate() + timedelta(days=10))
        response = self.client.post(INVITATIONS, {'evaluator_ids': [self.evaluator.pk], 'schedule_ids': [first.pk, final.pk], 'expires_at': (timezone.now() + timedelta(days=2)).isoformat()}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('last assigned defense', str(response.data))
        self.assertFalse(GuestPanelistCode.objects.exists())

    def test_pit_lead_is_limited_to_own_year(self):
        own = StudentTeam.objects.create(name='PIT own', level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', semester=self.semester, leader=self.student)
        other = StudentTeam.objects.create(name='PIT other', level=StudentTeam.LEVEL_2_PIT, year_level='2nd Year', semester=self.semester, leader=self.student)
        own_slot = self.schedule(own, scope='pit', defense_stage=None, rubric=None, event_name='PIT Demo')
        other_slot = self.schedule(other, scope='pit', defense_stage=None, rubric=None, event_name='PIT Demo', start_time='10:00')
        self.client.force_authenticate(self.lead)
        for schedule, expected in [(own_slot, 201), (other_slot, 403), (self.schedule(start_time='11:00'), 403)]:
            response = self.client.post(INVITATIONS, {'evaluator_ids': [self.evaluator.pk], 'schedule_ids': [schedule.pk]}, format='json')
            self.assertEqual(response.status_code, expected, response.data)
        self.assertEqual(len(self.client.get(DIRECTORY).data['invitations']), 1)

    def test_expired_access_is_rejected_at_exchange_and_after_login(self):
        invitation = self.invite()
        self.guest(invitation)
        invitation.expires_at = timezone.now() - timedelta(seconds=1)
        invitation.save(update_fields=['expires_at'])
        self.assertEqual(self.client.get(SCHEDULES + 'guest-assignments/').status_code, 401)
        self.client.credentials()
        self.assertEqual(self.client.post('/api/users/guest-codes/exchange/', {'code': invitation.code}, format='json').status_code, 401)

    def test_deactivation_and_revoke_block_existing_token(self):
        invitation = self.invite()
        self.guest(invitation)
        self.assertEqual(self.client.get(SCHEDULES + 'guest-assignments/').status_code, 200)
        self.evaluator.is_active = False
        self.evaluator.save(update_fields=['is_active'])
        self.assertEqual(self.client.get(SCHEDULES + 'guest-assignments/').status_code, 401)
        self.evaluator.is_active = True
        self.evaluator.save(update_fields=['is_active'])
        self.client.credentials()
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f'{INVITATIONS}{invitation.pk}/', {'is_active': False}, format='json')
        self.assertEqual(response.status_code, 200)
        self.guest(invitation)
        self.assertEqual(self.client.get(SCHEDULES + 'guest-assignments/').status_code, 401)

    def test_exchange_tracks_last_access_and_caps_token_expiry(self):
        invitation = self.invite()
        invitation.expires_at = timezone.now() + timedelta(minutes=30)
        invitation.save(update_fields=['expires_at'])
        self.client.force_authenticate(user=None)
        response = self.client.post('/api/users/guest-codes/exchange/', {'code': invitation.code.lower()}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        invitation.refresh_from_db()
        self.assertIsNotNone(invitation.used_at)
        self.assertIsNotNone(invitation.last_access_at)
        self.assertEqual(AccessToken(response.data['access'])['exp'], int(invitation.expires_at.timestamp()))

    def test_deleting_one_defense_keeps_remaining_guest_access_and_draft(self):
        first = self.schedule()
        remaining = self.schedule(fixtures.DefenseSchedulerApiTests.create_ready_team(self), start_time='09:00')
        invitation = self.invite([first, remaining])
        self.guest(invitation)
        draft = {'schedule_id': remaining.pk, 'evaluation_context': evaluation_context(remaining, remaining.grade_records.first()), 'submissions': [{'student_id': None, 'criteria_scores': fixtures.DefenseSchedulerApiTests.criteria_scores(self, 8)}]}
        self.assertEqual(self.client.post(SCHEDULES + 'guest-grade-draft/', draft, format='json').status_code, 200)
        first.delete()
        invitation.refresh_from_db()
        self.assertIsNone(invitation.defense_schedule_id)
        response = self.client.get(SCHEDULES + 'guest-assignments/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['schedules_count'], 1)
        self.assertEqual(response.data['teams'][0]['schedule_id'], remaining.pk)
        self.assertIsNotNone(response.data['teams'][0]['draft'])
        self.client.credentials()
        response = self.client.post('/api/users/guest-codes/exchange/', {'code': invitation.code}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['user']['defense_schedule_id'], remaining.pk)
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.client.get(DIRECTORY).data['invitations'][0]['schedule_ids'], [remaining.pk])

    def test_invitation_with_no_remaining_defenses_cannot_login_or_renew(self):
        schedule = self.schedule()
        invitation = self.invite([schedule])
        self.guest(invitation)
        schedule.delete()
        self.assertEqual(self.client.get(SCHEDULES + 'guest-assignments/').status_code, 401)
        self.client.credentials()
        self.assertEqual(self.client.post('/api/users/guest-codes/exchange/', {'code': invitation.code}, format='json').status_code, 401)
        self.client.force_authenticate(self.admin)
        response = self.client.get(DIRECTORY)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['invitations'][0]['schedule_ids'], [])
        self.assertEqual(response.data['invitations'][0]['status'], 'Revoked')
        self.assertEqual(self.client.patch(f'{INVITATIONS}{invitation.pk}/', {'is_active': True, 'expires_at': (timezone.now() + timedelta(days=1)).isoformat()}, format='json').status_code, 400)
        self.client.force_authenticate(self.lead)
        self.assertEqual(self.client.get(DIRECTORY).data['invitations'], [])

    def test_forged_invitation_claims_no_longer_authenticate(self):
        token = AccessToken()
        token['guest_panelist'] = True
        token['guest_code_id'] = 98765
        token['guest_code'] = 'DEF-NONE'
        token['defense_schedule_id'] = self.schedule().pk
        self.client.force_authenticate(user=None)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        self.assertEqual(self.client.get(SCHEDULES + 'guest-assignments/').status_code, 401)

    def test_multi_defense_draft_submission_and_renewal_preserve_scores(self):
        first = self.schedule()
        other = self.schedule(fixtures.DefenseSchedulerApiTests.create_ready_team(self), start_time='09:00')
        unassigned = self.schedule(start_time='11:00')
        invitation = self.invite([first, other])
        original_token = self.guest(invitation)
        assignments = self.client.get(SCHEDULES + 'guest-assignments/')
        self.assertEqual(assignments.data['schedules_count'], 2)
        scores = fixtures.DefenseSchedulerApiTests.criteria_scores(self, 8)
        first_draft = {'schedule_id': first.pk, 'evaluation_context': evaluation_context(first, first.grade_records.first()), 'submissions': [{'student_id': None, 'criteria_scores': [scores[0]]}]}
        self.assertEqual(self.client.post(SCHEDULES + 'guest-grade-draft/', first_draft, format='json').status_code, 200)
        draft = {'schedule_id': other.pk, 'evaluation_context': evaluation_context(other, other.grade_records.first()), 'submissions': [{'student_id': None, 'criteria_scores': scores}]}
        response = self.client.post(SCHEDULES + 'guest-grade-draft/', draft, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        blocked = self.client.post(SCHEDULES + 'guest-grade-draft/', {**draft, 'schedule_id': unassigned.pk}, format='json')
        self.assertEqual(blocked.status_code, 403)
        response = self.client.post(SCHEDULES + 'guest-submit-grades/', {'team_id': other.team_id, 'schedule_id': other.pk, 'criteria_scores': scores}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertFalse(PanelistEvaluationDraft.objects.filter(schedule=other).exists())
        before = list(PanelistGradeSubmission.objects.values_list('pk', flat=True))
        self.client.credentials()
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f'{INVITATIONS}{invitation.pk}/', {'is_active': True, 'expires_at': (timezone.now() + timedelta(days=1)).isoformat()}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        invitation.refresh_from_db()
        self.client.force_authenticate(user=None)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {original_token}')
        self.assertEqual(self.client.get(SCHEDULES + 'guest-assignments/').status_code, 401)
        self.guest(invitation)
        assignments = self.client.get(SCHEDULES + 'guest-assignments/')
        self.assertIsNotNone(next(t for t in assignments.data['teams'] if t['schedule_id'] == first.pk)['draft'])
        self.assertTrue(next(t for t in assignments.data['teams'] if t['schedule_id'] == other.pk)['is_submitted'])
        results = self.client.get(SCHEDULES + 'guest-panelist-results/')
        self.assertEqual(results.status_code, 200, results.data)
        self.assertEqual(len(results.data['results']), 1)
        duplicate = self.client.post(SCHEDULES + 'guest-submit-grades/', {'team_id': other.team_id, 'schedule_id': other.pk, 'criteria_scores': scores}, format='json')
        self.assertEqual(duplicate.status_code, 400)
        self.assertEqual(before, list(PanelistGradeSubmission.objects.values_list('pk', flat=True)))

    def test_pit_guest_uses_event_rubric_and_weights(self):
        own = StudentTeam.objects.create(name='PIT Demo Team', level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', semester=self.semester, leader=self.student)
        panel = Rubric.objects.create(name='PIT panel', scope='pit', semester=self.semester, evaluation_type='panel', status='published', created_by=self.lead)
        peer = Rubric.objects.create(name='PIT peer', scope='pit', semester=self.semester, evaluation_type='peer', status='published', created_by=self.lead)
        criterion = RubricCriterion.objects.create(rubric=panel, name='Prototype', max_score=10, scale=Rubric.SCALE_10)
        PitEventGradingConfig.objects.create(semester=self.semester, event_name='PIT Demo', panel_rubric=panel, peer_rubric=peer, panel_weight=80, peer_weight=20)
        slot = self.schedule(own, scope='pit', defense_stage=None, rubric=panel, event_name='PIT Demo')
        self.guest(self.invite([slot]))
        response = self.client.get(SCHEDULES + 'guest-assignments/')
        self.assertEqual(response.data['teams'][0]['panel_rubric']['id'], panel.pk)
        response = self.client.post(SCHEDULES + 'guest-submit-grades/', {'team_id': own.pk, 'schedule_id': slot.pk, 'criteria_scores': [{'criterion_id': criterion.pk, 'score': 8}]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(PanelistGradeSubmission.objects.get().schedule_id, slot.pk)

    def test_material_access_accepts_both_invited_teams_and_denies_other_teams(self):
        from defensys_backend.media_access import _can_read_submission
        first = self.schedule()
        other = self.schedule(fixtures.DefenseSchedulerApiTests.create_ready_team(self), start_time='09:00')
        invitation = self.invite([first, other])
        principal = GuestPanelistPrincipal(AccessToken(create_guest_access_token(invitation)), invitation)
        with patch('repository.deliverables.services.definition_for', return_value={'type': 'pre', 'is_defense_material': True}):
            for slot in [first, other]:
                submission = SimpleNamespace(team=slot.team, team_id=slot.team_id, stage_label=slot.stage_label, deliverable_id='manuscript')
                self.assertTrue(_can_read_submission(principal, submission))
            submission = SimpleNamespace(team=other.team, team_id=98765, stage_label=other.stage_label, deliverable_id='manuscript')
            self.assertFalse(_can_read_submission(principal, submission))
        self.evaluator.is_active = False
        self.evaluator.save(update_fields=['is_active'])
        with patch('repository.deliverables.services.definition_for', return_value={'type': 'pre', 'is_defense_material': True}):
            self.assertFalse(_can_read_submission(principal, SimpleNamespace(team=first.team, team_id=first.team_id, stage_label=first.stage_label, deliverable_id='manuscript')))

    def test_deactivate_and_reactivate_does_not_restore_old_invitation(self):
        invitation = self.invite()
        original = invitation.access_version
        for active in [False, True]:
            self.assertEqual(self.client.patch(f'{DIRECTORY}{self.evaluator.pk}/', {'is_active': active}, format='json').status_code, 200)
        invitation.refresh_from_db()
        self.assertFalse(invitation.is_active)
        self.assertGreater(invitation.access_version, original)

    def test_evaluator_edit_preserves_invitation_and_grade_identity(self):
        invitation = self.invite()
        response = self.client.patch(f'{DIRECTORY}{self.evaluator.pk}/', {'name': 'Dr. Lina Santos Cruz', 'institution': 'Updated University'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.evaluator.refresh_from_db()
        invitation.refresh_from_db()
        self.assertEqual(self.evaluator.name, 'Dr. Lina Santos Cruz')
        self.assertEqual(invitation.guest_name, 'Dr. Lina Santos')

    def test_expiry_cannot_precede_an_assigned_future_defense(self):
        slot = self.schedule(scheduled_date=timezone.localdate() + timedelta(days=2))
        response = self.client.post(INVITATIONS, {'evaluator_ids': [self.evaluator.pk], 'schedule_ids': [slot.pk], 'expires_at': (timezone.now() + timedelta(hours=1)).isoformat()}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(GuestPanelistCode.objects.exists())
