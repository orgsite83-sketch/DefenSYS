import uuid
from types import SimpleNamespace
from unittest.mock import patch

from django.core.exceptions import ValidationError as ModelValidationError
from rest_framework.exceptions import ValidationError, PermissionDenied
from rest_framework.test import APITestCase

from . import test_automatic_outcomes as fixtures
from . import dissemination
from .dissemination_models import OutcomeRelease, OutcomeReleaseBatch, OutcomeReleaseControl
from .student_visibility import student_assessment_payload, require_student_release


class OutcomeDisseminationTests(APITestCase):
    _rubric = fixtures.AutomaticConceptOutcomeTests._rubric
    prepare = fixtures.AutomaticConceptOutcomeTests.prepare
    scores = fixtures.AutomaticConceptOutcomeTests.scores
    submit = fixtures.AutomaticConceptOutcomeTests.submit
    post = fixtures.AutomaticConceptOutcomeTests.post

    def setUp(self):
        fixtures.AutomaticConceptOutcomeTests.setUp(self)
        self.filters = {'scope': 'capstone', 'entity': 'teams', 'semester_id': self.semester.pk,
                        'defense_stage_id': self.stage.pk, 'coverage': 'assessment'}
        self.request = SimpleNamespace(user=self.admin)

    def ready(self):
        self.submit([6, 8, 6])
        self.grade.refresh_from_db()

    def preview(self, selected=True):
        return dissemination.preview(self.request, {'filters': self.filters,
            **({'grade_ids': [self.grade.pk]} if selected else {})})

    def release(self, preview=None, batch_id=None):
        return dissemination.confirm(self.request, {'review_token': (preview or self.preview())['review_token'],
                                                  'batch_id': batch_id or str(uuid.uuid4())})

    def test_completed_outcome_stays_private_and_does_not_notify(self):
        self.ready()
        from notifications.models import Notification
        self.assertFalse(Notification.objects.filter(title='Defense outcome recorded').exists())
        public = student_assessment_payload({'schedule_id': self.grade.schedule_id, 'verdict': self.grade.verdict,
            'verdict_remarks': 'Private feedback', 'panel_score': 80}, self.student)
        self.assertEqual(public['verdict'], '')
        self.assertEqual(public['verdict_remarks'], '')
        self.assertNotIn('panel_score', public)
        self.assertEqual(public['dissemination']['status'], 'awaiting_release')

    def test_admin_overview_counts_release_eligibility_without_releasing(self):
        from dashboards.overview import admin_overview
        self.ready()
        before = admin_overview(self.semester, [], [], 0)
        self.assertEqual(before['workflow'][-1]['value'], '1')
        self.assertTrue(any(item['id'] == 'outcomes_ready:capstone' for item in before['action_items']))
        self.assertFalse(OutcomeRelease.objects.exists())
        self.release()
        after = admin_overview(self.semester, [], [], 0)
        self.assertEqual(after['workflow'][-1]['value'], '0')
        self.assertIn('1 released', after['workflow'][-1]['detail'])
        self.assertFalse(any(item['id'] == 'outcomes_ready:capstone' for item in after['action_items']))

    def test_review_release_snapshot_and_retry_are_idempotent(self):
        self.ready()
        preview = self.preview()
        batch_id = str(uuid.uuid4())
        result = self.release(preview, batch_id)
        repeated = self.release(preview, batch_id)
        self.assertEqual(result, repeated)
        self.assertEqual(OutcomeRelease.objects.count(), 1)
        from notifications.models import Notification
        self.assertEqual(Notification.objects.filter(title='Defense outcome released').count(), result['student_count'])
        public = student_assessment_payload({'schedule_id': self.grade.schedule_id, 'verdict': 'failed',
            'verdict_remarks': 'Unreviewed replacement', 'panel_score': 1}, self.student)
        self.assertEqual(public['verdict'], 'approved')
        self.assertEqual(public['verdict_remarks'], '')
        self.assertNotIn('panel_score', public)

    def test_changed_included_feedback_rejects_stale_confirmation(self):
        self.ready()
        preview = self.preview()
        self.grade.verdict_remarks = 'Updated feedback'
        self.grade.save()
        with self.assertRaises(ValidationError):
            self.release(preview)
        self.assertFalse(OutcomeRelease.objects.exists())

    def test_confirm_never_reexecutes_matching_query(self):
        self.ready()
        preview = self.preview(False)
        with patch.object(dissemination, 'scope_data', side_effect=AssertionError('Must not widen reviewed selection')):
            self.release(preview)
        self.assertEqual(OutcomeRelease.objects.count(), 1)

    def test_hold_and_remove_hold_do_not_release(self):
        self.ready()
        info = dissemination.metadata(self.grade)
        held = dissemination.hold(self.request, self.grade.pk, {'version': info['version'],
            'schedule_id': self.grade.schedule_id, 'held': True, 'reason': 'Administrative review'})
        self.assertEqual(held['status'], 'held')
        with self.assertRaises(ValidationError):
            self.preview()
        removed = dissemination.hold(self.request, self.grade.pk, {'version': held['version'],
            'schedule_id': self.grade.schedule_id, 'held': False})
        self.assertEqual(removed['status'], 'ready')
        self.assertFalse(OutcomeRelease.objects.exists())

    def test_student_and_panelist_cannot_preview_or_confirm(self):
        self.ready()
        for actor in (self.student, self.panelist):
            with self.assertRaises(PermissionDenied):
                dissemination.preview(SimpleNamespace(user=actor), {'filters': self.filters})
            with self.assertRaises(PermissionDenied):
                dissemination.confirm(SimpleNamespace(user=actor), {})

    def test_student_rows_deduplicate_one_team_and_preview_is_read_only(self):
        self.ready()
        from user_management.academic_records.models import StudentAcademicRecord
        for member in self.capstone_team.memberships.all():
            StudentAcademicRecord.objects.update_or_create(student_id=member.student_id, semester=self.semester,
                defaults={'year_level': '4th Year', 'section': self.capstone_team.section})
        self.filters['entity'] = 'students'
        preview = self.preview(False)
        self.assertEqual(preview['team_count'], 1)
        self.assertEqual(preview['student_count'], self.capstone_team.memberships.count())
        self.assertFalse(OutcomeReleaseControl.objects.exists())
        self.assertFalse(OutcomeReleaseBatch.objects.exists())

    def test_missing_panel_and_pending_concept_selection_are_blocked(self):
        with self.assertRaises(ValidationError):
            self.preview()
        self.submit([8, 9, 6])
        with self.assertRaises(ValidationError):
            self.preview()

    def test_redefense_releases_without_passing_grade_and_submission_gate_opens(self):
        self.submit([5, 6, 7])
        self.grade.refresh_from_db()
        with self.assertRaises(ModelValidationError):
            require_student_release(self.student, self.capstone_team, self.stage)
        result = self.release()
        self.assertEqual(result['entries'][0]['snapshot']['verdict'], 'for_redefense')
        require_student_release(self.student, self.capstone_team, self.stage)

    def test_notifications_and_release_rollback_when_audit_fails(self):
        self.ready()
        from notifications.models import Notification
        with patch('grading.grades.defense_workflow.audit', side_effect=RuntimeError('Audit unavailable')):
            with self.assertRaises(RuntimeError):
                self.release()
        self.assertFalse(OutcomeRelease.objects.exists())
        self.assertFalse(Notification.objects.filter(title='Defense outcome released').exists())

    def test_historical_snapshot_immutable_and_another_attempt_does_not_inherit(self):
        self.ready()
        self.release()
        release = OutcomeRelease.objects.get()
        release.snapshot['verdict'] = 'failed'
        with self.assertRaises(ModelValidationError):
            release.save()
        public = student_assessment_payload({'schedule_id': self.grade.schedule_id + 10000, 'verdict': 'approved'}, self.student)
        self.assertEqual(public['verdict'], '')

    def test_api_scope_permissions_and_history(self):
        self.ready()
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/grading/grades/outcome-dissemination/preview/', {'filters': self.filters}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        response = self.client.post('/api/grading/grades/outcome-dissemination/confirm/', {
            'review_token': response.data['review_token'], 'batch_id': str(uuid.uuid4())}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        history = self.client.get('/api/grading/grades/outcome-dissemination/history/', self.filters)
        self.assertEqual(len(history.data['batches']), 1)
        self.client.force_authenticate(self.student)
        denied = self.client.get('/api/grading/grades/outcome-dissemination/history/', self.filters)
        self.assertEqual(denied.status_code, 403)

    def test_six_reviewed_teams_do_not_include_four_completed_later(self):
        from copy import deepcopy
        from django.contrib.auth import get_user_model
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        from repository.deliverables.models import ConceptRound
        from student_teams.models import StudentTeam, TeamMembership
        from .services import GradeContextService
        original = (self.capstone_team, self.capstone_schedule, self.grade)
        template = ConceptRound.objects.get(schedule=self.capstone_schedule)
        teams = [original]
        for index in range(1, 10):
            student = get_user_model().objects.create_user(username=f'dissemination-batch-{index}', role='student')
            adviser = get_user_model().objects.create_user(username=f'dissemination-adviser-{index}', role='faculty', is_adviser=True)
            team = StudentTeam.objects.create(name=f'Release batch team {index}', level=self.capstone_team.level,
                project_title='New research proposal', year_level=self.capstone_team.year_level,
                section=self.capstone_team.section, semester=self.semester, adviser=adviser, leader=student)
            TeamMembership.objects.create(team=team, student=student)
            ConceptRound.objects.create(team=team, defense_stage=self.stage, project_version=team.project_version,
                number=1, concepts=deepcopy(template.concepts), policy_snapshot=deepcopy(template.policy_snapshot))
            previous_team, previous_student, previous_adviser = self.capstone_team, self.student, self.adviser
            self.capstone_team, self.student, self.adviser = team, student, adviser
            self.prepare()
            from repository.deliverables.services import endorse_team
            endorse_team(team, self.stage.label, self.adviser)
            self.capstone_team, self.student, self.adviser = previous_team, previous_student, previous_adviser
            schedule = DefenseSchedule.objects.create(team=team, semester=self.semester, defense_stage=self.stage,
                rubric=self.panel_rubric, scheduled_date='2026-05-15', start_time=f'{index + 8:02}:00', room=f'Batch {index}')
            SchedulePanelist.objects.create(schedule=schedule, panelist=self.panelist, is_chair=True)
            grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
            schedule.assessment_policy['automatic_outcomes'] = True
            schedule.save(update_fields=['assessment_policy'])
            teams.append((team, schedule, grade))
        for team, schedule, grade in teams[:6]:
            self.capstone_team, self.capstone_schedule, self.grade = team, schedule, grade
            self.ready()
        self.capstone_team, self.capstone_schedule, self.grade = original
        reviewed = self.preview(False)
        self.assertEqual(reviewed['team_count'], 6)
        self.assertEqual(reviewed['excluded_count'], 4)
        for team, schedule, grade in teams[6:]:
            self.capstone_team, self.capstone_schedule, self.grade = team, schedule, grade
            self.ready()
        self.capstone_team, self.capstone_schedule, self.grade = original
        result = self.release(reviewed)
        self.assertEqual(result['team_count'], 6)
        for team, schedule, grade in teams[6:]:
            self.assertFalse(OutcomeRelease.objects.filter(control__schedule=schedule).exists())
        self.assertEqual(self.preview(False)['team_count'], 4)

    def test_content_can_be_corrected_back_to_an_earlier_released_version(self):
        self.ready()
        first = self.release()
        self.grade.verdict_remarks = 'Revised public feedback'
        self.grade.save()
        self.release()
        self.grade.verdict_remarks = ''
        self.grade.save()
        self.release()
        self.assertEqual(list(OutcomeRelease.objects.order_by('version').values_list('version', flat=True)), [1, 2, 3])
        self.assertEqual(OutcomeRelease.objects.order_by('version').first().snapshot, first['entries'][0]['snapshot'])

    def test_real_student_payloads_withhold_feedback_and_numeric_evidence(self):
        import json
        from repository.deliverables.services import stage_payload, team_payload
        from repository.deliverables.models import ConceptRound
        self.ready()
        self.grade.verdict_remarks = 'PRIVATE-DISSEMINATION-FEEDBACK'
        self.grade.save()
        ConceptRound.objects.filter(schedule=self.grade.schedule).update(remarks=self.grade.verdict_remarks)
        before = [stage_payload(self.capstone_team, self.stage.label, self.student),
                  team_payload(self.capstone_team, self.stage.label, self.student)]
        encoded = json.dumps(before, default=str)
        self.assertNotIn('PRIVATE-DISSEMINATION-FEEDBACK', encoded)
        self.assertNotIn('"verdict": "approved"', encoded)
        self.assertNotIn('"panel_score"', encoded)
        self.release()
        after = stage_payload(self.capstone_team, self.stage.label, self.student)
        self.assertIn('PRIVATE-DISSEMINATION-FEEDBACK', json.dumps(after, default=str))
        self.assertNotIn('"panel_score"', json.dumps(after, default=str))

    def test_legacy_notification_and_grade_exports_do_not_disclose_results(self):
        from notifications.models import Notification
        from notifications.serializers import NotificationSerializer
        self.ready()
        alert = Notification.objects.create(recipient=self.student, workspace='student', title='Defense outcome recorded',
            message='PRIVATE LEGACY RESULT: Approved', category='DEFENSE', action_payload={'schedule_id': self.grade.schedule_id})
        data = NotificationSerializer(alert).data
        self.assertNotIn('PRIVATE LEGACY RESULT', data['message'])
        self.assertEqual(data['message'], 'Awaiting official release.')
        self.client.force_authenticate(self.student)
        for path in (f'/api/reports/team-grade/{self.capstone_team.pk}/',
                     f'/api/reports/individual-grade/{self.student.pk}/', '/api/reports/semester-grades/'):
            response = self.client.get(path)
            self.assertEqual(response.status_code, 403, response.data)

    def test_released_repeat_instructions_remain_frozen_until_released_again(self):
        from repository.deliverables import concepts
        self.submit([5, 6, 7])
        self.grade.refresh_from_db()
        self.grade.verdict_remarks = 'First released instructions'
        self.grade.save()
        self.release()
        before = concepts.payload(self.capstone_team, self.stage, actor=self.student)
        self.assertEqual(before['concepts'][0]['panel_feedback'], 'First released instructions')
        self.grade.verdict_remarks = 'Unreviewed updated instructions'
        self.grade.save()
        after = concepts.payload(self.capstone_team, self.stage, actor=self.student)
        self.assertEqual(after['concepts'][0]['panel_feedback'], 'First released instructions')
        self.release()
        updated = concepts.payload(self.capstone_team, self.stage, actor=self.student)
        self.assertEqual(updated['concepts'][0]['panel_feedback'], 'Unreviewed updated instructions')
