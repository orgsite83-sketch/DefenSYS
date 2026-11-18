"""Grade save recovery uses isolated Django test data, never production records."""
from unittest.mock import patch

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase
from authentication_access_control.guest_authentication import GuestPanelistPrincipal
from user_management.models import GuestPanelistCode

from grading.grades.corrections import evaluator_completion
from grading.grades.models import PanelistGradeSubmission
from grading.grades.services import GradeContextService, submit_panelist_grade
from student_teams.models import TeamMembership
from . import test_panelist_evaluation as fixtures
from .models import PanelistEvaluationDraft
from .panelist_evaluation import evaluation_context


class EvaluationRecoveryTests(APITestCase):
    setUp = fixtures.PanelistEvaluationTests.setUp
    schedule = fixtures.PanelistEvaluationTests.schedule
    scores = fixtures.PanelistEvaluationTests.scores
    save_draft = fixtures.PanelistEvaluationTests.save_draft
    _complete_prior_stages = fixtures.PanelistEvaluationTests._complete_prior_stages

    def test_delayed_older_save_cannot_overwrite_newer_acknowledged_scores(self):
        schedule = self.schedule()
        first = self.save_draft(schedule, draft_version='')
        self.assertEqual(first.status_code, 200, first.data)
        version = first.data['draft']['version']
        newer = [{'student_id': None, 'criteria_scores': [self.scores(9)[0]]}]
        accepted = self.save_draft(schedule, submissions=newer, draft_version=version)
        self.assertEqual(accepted.status_code, 200, accepted.data)
        delayed = self.save_draft(schedule, draft_version=version)
        self.assertEqual(delayed.status_code, 409, delayed.data)
        self.assertEqual(delayed.data['draft'], accepted.data['draft'])
        self.assertEqual(PanelistEvaluationDraft.objects.get().submissions[0]['criteria_scores'][0]['score'], 9)

    def test_identical_retry_recovers_lost_ack_without_changing_version(self):
        schedule = self.schedule()
        first = self.save_draft(schedule, draft_version='')
        retry = self.save_draft(schedule, draft_version='')
        self.assertEqual(retry.status_code, 200, retry.data)
        self.assertEqual(retry.data, first.data)
        self.assertEqual(PanelistEvaluationDraft.objects.count(), 1)

    def test_identical_stale_retry_upgrades_legacy_draft_protection(self):
        schedule = self.schedule()
        self.save_draft(schedule)
        recovered = self.save_draft(schedule, draft_version='lost-version')
        self.assertEqual(recovered.status_code, 200, recovered.data)
        self.assertTrue(PanelistEvaluationDraft.objects.get().versioned)
        self.assertEqual(self.save_draft(schedule).status_code, 409)

    def test_older_app_cannot_overwrite_or_submit_a_versioned_draft(self):
        schedule = self.schedule()
        saved = self.save_draft(schedule, draft_version='')
        rejected = self.save_draft(schedule)
        self.assertEqual(rejected.status_code, 409, rejected.data)
        self.assertEqual(rejected.data['draft'], saved.data['draft'])
        final = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk,
            'criteria_scores': self.scores(8),
        }, format='json')
        self.assertEqual(final.status_code, 400, final.data)
        self.assertFalse(PanelistGradeSubmission.objects.exists())

    def test_legacy_drafts_keep_working_until_upgraded(self):
        schedule = self.schedule()
        first = self.save_draft(schedule)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(self.save_draft(schedule, submissions=[{
            'student_id': None, 'criteria_scores': [self.scores(9)[0]],
        }]).status_code, 200)
        upgraded = self.save_draft(schedule, draft_version=first.data['draft']['version'])
        self.assertEqual(upgraded.status_code, 409)  # A stale version still cannot bypass the lock.
        latest = upgraded.data['draft']['version']
        self.assertEqual(self.save_draft(schedule, draft_version=latest).status_code, 200)
        self.assertTrue(PanelistEvaluationDraft.objects.get().versioned)

    def test_recovery_read_is_private_read_only_and_draft_is_never_submitted(self):
        schedule = self.schedule()
        saved = self.save_draft(schedule, draft_version='')
        with CaptureQueriesContext(connection) as queries:
            response = self.client.get('/api/defense/schedules/grade-draft/', {'schedule_id': schedule.pk})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['is_submitted'])
        self.assertEqual(response.data['draft'], saved.data['draft'])
        self.assertEqual(response.data['submissions'], [])
        self.assertFalse(any(q['sql'].lstrip().upper().startswith(('INSERT', 'UPDATE', 'DELETE')) for q in queries))
        self.client.force_authenticate(user=self.second_panelist)
        other = self.client.get('/api/defense/schedules/grade-draft/', {'schedule_id': schedule.pk})
        self.assertIsNone(other.data['draft'])
        self.client.force_authenticate(user=self.adviser)
        self.assertIn(self.client.get('/api/defense/schedules/grade-draft/', {'schedule_id': schedule.pk}).status_code, (403, 404))

    def test_recovery_rejects_invalid_schedule_id(self):
        for value in ('invalid', ''):
            response = self.client.get('/api/defense/schedules/grade-draft/', {'schedule_id': value})
            self.assertEqual(response.status_code, 400)

    def test_final_submission_requires_latest_draft_and_returns_persisted_state(self):
        schedule = self.schedule()
        saved = self.save_draft(schedule, draft_version='')
        payload = {'team_id': self.team.pk, 'schedule_id': schedule.pk,
                   'evaluation_context': evaluation_context(schedule),
                   'submissions': [{'student_id': None, 'criteria_scores': self.scores(8)}],
                   'draft_version': ''}
        stale = self.client.post('/api/defense/schedules/submit-grades/', payload, format='json')
        self.assertEqual(stale.status_code, 400, stale.data)
        self.assertFalse(PanelistGradeSubmission.objects.exists())
        payload['draft_version'] = saved.data['draft']['version']
        accepted = self.client.post('/api/defense/schedules/submit-grades/', payload, format='json')
        self.assertEqual(accepted.status_code, 201, accepted.data)
        state = accepted.data['evaluation']
        self.assertTrue(state['is_submitted'])
        self.assertEqual(state['schedule_id'], schedule.pk)
        self.assertIsNone(state['draft'])
        recovered = self.client.get('/api/defense/schedules/grade-draft/', {'schedule_id': schedule.pk})
        self.assertEqual(recovered.data, state)

    def _four_member_evaluation(self, target):
        self.rubric.target_type = target
        self.rubric.save(update_fields=['target_type'])
        self.second_criterion.target_type = 'individual'
        self.second_criterion.save(update_fields=['target_type'])
        for index in range(3):
            student = fixtures.fixtures.User.objects.create_user(username=f'recovery-member-{index}', role='student')
            TeamMembership.objects.create(team=self.team, student=student, order=index + 1)
        schedule = self.schedule()
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        members = list(self.team.memberships.order_by('order'))
        team_score, individual_score = self.scores(8)
        rows = []
        if target == 'both':
            rows.append({'student_id': None, 'criteria_scores': [team_score]})
            submit_panelist_grade(schedule, grade, [team_score], panelist=self.panelist)
        for member in members[:2]:
            scores = [individual_score] if target == 'both' else self.scores(8)
            rows.append({'student_id': member.student_id, 'criteria_scores': scores})
            submit_panelist_grade(schedule, grade, scores, panelist=self.panelist, student=member.student)
        state = self.client.get('/api/defense/schedules/grade-draft/', {'schedule_id': schedule.pk}).data
        assignment = self.client.get('/api/defense/schedules/panelist-assignments/').data['teams'][0]
        self.assertFalse(state['is_submitted'])
        self.assertFalse(assignment['is_submitted'])
        self.assertEqual(evaluator_completion(grade)['submitted'], 0)
        before = PanelistGradeSubmission.objects.count()
        incomplete = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk, 'submissions': rows,
        }, format='json')
        self.assertEqual(incomplete.status_code, 400, incomplete.data)
        self.assertEqual(PanelistGradeSubmission.objects.count(), before)
        for member in members[2:]:
            rows.append({'student_id': member.student_id,
                         'criteria_scores': [individual_score] if target == 'both' else self.scores(8)})
        accepted = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk, 'submissions': rows,
        }, format='json')
        self.assertEqual(accepted.status_code, 201, accepted.data)
        self.assertTrue(accepted.data['evaluation']['is_submitted'])
        self.assertEqual(evaluator_completion(grade)['submitted'], 1)

    def test_two_missing_individual_members_stay_incomplete_everywhere(self):
        self._four_member_evaluation('individual')

    def test_two_missing_members_in_mixed_rubric_stay_incomplete_everywhere(self):
        self._four_member_evaluation('both')

    def test_error_during_batch_rolls_back_all_member_submissions(self):
        schedule = self.schedule()
        original = submit_panelist_grade

        def fail_after_write(*args, **kwargs):
            original(*args, **kwargs)
            raise RuntimeError('Interrupted after recording scores')

        with patch('defense.scheduler.views.submit_panelist_grade', side_effect=fail_after_write):
            response = self.client.post('/api/defense/schedules/submit-grades/', {
                'team_id': self.team.pk, 'schedule_id': schedule.pk,
                'criteria_scores': self.scores(8),
            }, format='json')
        self.assertEqual(response.status_code, 500)
        self.assertFalse(PanelistGradeSubmission.objects.exists())

    def test_guest_recovery_and_versions_are_scoped_to_the_invitation(self):
        schedule = self.schedule()
        invitation = GuestPanelistCode.objects.create(guest_name='Recovery Guest', defense_schedule=schedule)
        invitation.schedules.add(schedule)
        guest = GuestPanelistPrincipal({'guest_code_id': str(invitation.pk),
            'defense_schedule_id': schedule.pk, 'team_id': self.team.pk,
            'guest_name': invitation.guest_name})
        self.client.force_authenticate(user=guest)
        payload = {'schedule_id': schedule.pk, 'evaluation_context': evaluation_context(schedule),
                   'draft_version': '', 'submissions': [{'student_id': None, 'criteria_scores': self.scores(8)}]}
        saved = self.client.post('/api/defense/schedules/guest-grade-draft/', payload, format='json')
        self.assertEqual(saved.status_code, 200, saved.data)
        state = self.client.get('/api/defense/schedules/guest-grade-draft/', {'schedule_id': schedule.pk})
        self.assertEqual(state.status_code, 200, state.data)
        self.assertFalse(state.data['is_submitted'])
        self.assertEqual(state.data['draft'], saved.data['draft'])
        denied = self.client.get('/api/defense/schedules/guest-grade-draft/', {'schedule_id': schedule.pk + 1})
        self.assertEqual(denied.status_code, 403)
        payload.update(team_id=self.team.pk, draft_version=saved.data['draft']['version'])
        submitted = self.client.post('/api/defense/schedules/guest-submit-grades/', payload, format='json')
        self.assertEqual(submitted.status_code, 201, submitted.data)
        self.assertTrue(submitted.data['evaluation']['is_submitted'])
        recovered = self.client.get('/api/defense/schedules/guest-grade-draft/', {'schedule_id': schedule.pk})
        self.assertEqual(recovered.data, submitted.data['evaluation'])
