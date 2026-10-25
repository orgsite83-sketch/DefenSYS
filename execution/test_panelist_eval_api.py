"""Panel automation uses existing API views and the isolated Django test database.

Run from the repository root:
  backend/venv/Scripts/python.exe backend/manage.py test execution.test_panelist_eval_api --pythonpath . --keepdb --noinput
"""
from contextlib import redirect_stdout
from datetime import timedelta
from io import StringIO
from unittest.mock import patch
from urllib.parse import urlsplit

from django.contrib.auth import get_user_model
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from defense.scheduler.models import PanelistEvaluationDraft, PitEventGradingConfig, SchedulePanelist
from grading.grades import tests as grade_fixtures
from grading.grades import test_concept_workflow as concept_fixtures
from grading.grades import test_outcome_rules as outcome_fixtures
from grading.grades.models import PanelistGradeSubmission, TeamGrade
from grading.rubrics.models import Rubric, RubricCriterion
from repository.deliverables.models import ConceptRound
from user_management.models import ExternalEvaluator, GuestPanelistCode

from execution import auto_panelist_eval as automation


class _Response:
    def __init__(self, response):
        self.status_code = response.status_code
        self.data = response.data
        self.text = response.content.decode('utf-8', errors='replace')

    def json(self):
        return self.data


class _Session:
    """Keep real JWT authentication and API validation; replace only the HTTP socket."""
    def __init__(self, calls):
        self.headers = {}
        self.calls = calls

    def request(self, method, url, *, json=None, headers=None, **kwargs):
        path = urlsplit(url).path
        credentials = {**self.headers, **(headers or {})}
        auth = {'HTTP_AUTHORIZATION': credentials['Authorization']} if credentials.get('Authorization') else {}
        response = getattr(APIClient(), method.lower())(path, json or {}, format='json', **auth)
        self.calls.append({'method': method, 'path': path, 'payload': json,
                           'actor': response.wsgi_request.user, 'status': response.status_code})
        return _Response(response)

    def get(self, url, **kwargs):
        return self.request('GET', url, **kwargs)

    def post(self, url, **kwargs):
        return self.request('POST', url, **kwargs)

    def close(self):
        pass


class _AutomationMixin:
    _rubric = grade_fixtures.GradeCenterApiTests._rubric

    def exercise(self, *extra, scope='capstone', year='3', score='8'):
        self.calls = []
        args = ['--all-panelists', '--base-url', 'http://testserver', '--delay', '0',
                '--scope', scope, '--year', year, '--min-score', score, '--max-score', score]
        with patch.object(automation.requests, 'Session', side_effect=lambda: _Session(self.calls)), \
                patch.object(automation.requests, 'patch', side_effect=lambda url, **kw:
                    _Session(self.calls).request('PATCH', url, **kw)), redirect_stdout(StringIO()) as output:
            result = automation.run(args + list(extra))
        self.output = output.getvalue()
        return result

    def add_guest(self):
        evaluator = ExternalEvaluator.objects.create(name='Demo Expert', status='approved')
        invitation = GuestPanelistCode.objects.create(evaluator=evaluator, guest_name=evaluator.name,
            defense_schedule=self.capstone_schedule, expires_at=timezone.now() + timedelta(days=1))
        invitation.schedules.add(self.capstone_schedule)
        return invitation

    def writes(self):
        return [call for call in self.calls if call['method'] != 'GET']


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PanelAutomationApiTests(_AutomationMixin, APITestCase):
    def setUp(self):
        outcome_fixtures.ConfiguredOutcomeTests.setUp(self)

    new_hearing = outcome_fixtures.ConfiguredOutcomeTests.new_hearing

    def test_dry_run_does_not_save_grades_tokens_verdicts_or_change_credentials(self):
        from rest_framework_simplejwt.token_blacklist.models import OutstandingToken
        from authentication_access_control.models import SystemAuditLog
        credentials = dict(get_user_model().objects.values_list('pk', 'password'))
        before = (TeamGrade.objects.count(), PanelistGradeSubmission.objects.count(),
                  OutstandingToken.objects.count(), SystemAuditLog.objects.count())
        self.assertEqual(self.exercise('--dry-run'), 2, self.output)
        self.assertEqual(self.writes(), [])
        self.assertEqual(before, (TeamGrade.objects.count(), PanelistGradeSubmission.objects.count(),
            OutstandingToken.objects.count(), SystemAuditLog.objects.count()))
        self.assertEqual(credentials, dict(get_user_model().objects.values_list('pk', 'password')))
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertIn('Verdicts Pending    : 1', self.output)

    def test_faculty_and_guest_finish_before_actual_chair_issues_passing_verdict(self):
        invitation = self.add_guest()
        self.assertEqual(self.exercise(), 0, self.output)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(float(self.grade.panel_score), 80)
        self.assertEqual(set(self.grade.panelist_submissions.values_list('panelist_id', 'guest_code_id')),
                         {(self.panelist.pk, None), (None, str(invitation.pk))})
        writes = self.writes()
        self.assertEqual([call['path'].rsplit('/', 2)[1] for call in writes],
                         ['submit-grades', 'guest-submit-grades', 'verdict'])
        self.assertEqual(writes[0]['actor'].pk, self.panelist.pk)
        self.assertEqual(writes[-1]['actor'].pk, self.panelist.pk)

    def test_below_cutoff_requests_redefense_instead_of_approval(self):
        self.assertEqual(self.exercise(score='7'), 0, self.output)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'for_redefense')
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(self.capstone_schedule.status, 'done')

    def test_explicit_approval_cannot_override_cutoff(self):
        self.assertEqual(self.exercise('--verdict', 'approved', score='7'), 2, self.output)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertEqual(len(self.writes()), 1)
        self.assertIn('not permitted', self.output)

    def test_partial_roster_cannot_issue_verdict_until_guest_submits(self):
        self.add_guest()
        self.assertEqual(self.exercise('--panelists', self.panelist.username), 2, self.output)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertEqual(self.grade.panelist_submissions.count(), 1)
        self.assertFalse(any(call['method'] == 'PATCH' for call in self.calls))
        self.assertEqual(self.exercise('--external-only'), 0, self.output)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')

    def test_rerun_keeps_existing_final_scores_and_verdict(self):
        self.assertEqual(self.exercise(), 0, self.output)
        before = list(self.grade.breakdowns.values_list('pk', 'score', 'remarks'))
        self.assertEqual(self.exercise(score='10'), 0, self.output)
        self.assertEqual(self.writes(), [])
        self.assertEqual(before, list(self.grade.breakdowns.values_list('pk', 'score', 'remarks')))
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')

    def test_missing_chair_does_not_impersonate_admin(self):
        SchedulePanelist.objects.filter(schedule=self.capstone_schedule).update(is_chair=False)
        self.assertEqual(self.exercise(), 2, self.output)
        self.assertFalse(any(call['method'] == 'PATCH' for call in self.calls))
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')

    def test_future_and_paused_defenses_remain_blocked(self):
        for changes in ({'scheduled_date': timezone.localdate() + timedelta(days=1)},
                        {'scheduled_date': timezone.localdate(), 'operation_state': 'paused'}):
            with self.subTest(changes=changes):
                for key, value in changes.items():
                    setattr(self.capstone_schedule, key, value)
                self.capstone_schedule.save()
                self.assertEqual(self.exercise(), 2, self.output)
                self.assertEqual(self.writes(), [])

    def test_saved_partial_draft_is_preserved_and_only_completed_with_opt_in(self):
        criterion = self.panel_rubric.criteria.first()
        extra = RubricCriterion.objects.create(rubric=self.panel_rubric, name='Second criterion', max_score=10, display_order=1)
        session = _Session([])
        session.headers['Authorization'] = f'Bearer {automation.get_jwt_token_for_user(self.panelist.username)}'
        rows = session.get('http://testserver/api/defense/schedules/panelist-assignments/').json()['teams']
        row = next(row for row in rows if row['schedule_id'] == self.capstone_schedule.pk)
        response = session.post('http://testserver/api/defense/schedules/grade-draft/', json={
            'schedule_id': self.capstone_schedule.pk, 'evaluation_context': row['evaluation_context'],
            'submissions': [{'student_id': None, 'criteria_scores': [{'criterion_id': criterion.pk, 'score': 0}],
                             'remarks': 'Keep this deliberate zero and my feedback.'}]})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.exercise('--no-verdict'), 2, self.output)
        self.assertEqual(self.writes(), [])
        self.assertTrue(PanelistEvaluationDraft.objects.filter(schedule=self.capstone_schedule).exists())
        self.assertEqual(self.exercise('--no-verdict', '--include-drafts'), 0, self.output)
        payload = self.writes()[0]['payload']['submissions'][0]
        self.assertEqual(payload['criteria_scores'], [{'criterion_id': criterion.pk, 'score': 0},
                                                     {'criterion_id': extra.pk, 'score': 8}])
        self.assertEqual(payload['remarks'], 'Keep this deliberate zero and my feedback.')
        self.assertFalse(PanelistEvaluationDraft.objects.filter(schedule=self.capstone_schedule).exists())

    def test_mixed_rubric_submits_team_and_all_current_members(self):
        self.panel_rubric.target_type = 'both'
        self.panel_rubric.save(update_fields=['target_type'])
        RubricCriterion.objects.create(rubric=self.panel_rubric, name='Individual contribution',
            target_type='individual', max_score=5, display_order=1)
        self.assertEqual(self.exercise(), 0, self.output)
        self.assertEqual(set(self.grade.panelist_submissions.values_list('student_id', flat=True)),
                         {None, self.student.pk, self.second_student.pk})
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')

    def test_discovery_filters_cohort_term_and_previous_project(self):
        self.assertEqual(automation.fetch_target_schedule_ids(scope='pit', year='2nd Year'), [])
        self.assertEqual(automation.fetch_target_schedule_ids(scope='pit', year='2nd Year',
            semester_id=self.first_semester.pk), [self.pit_schedule.pk])
        self.assertEqual(automation.fetch_target_schedule_ids(scope='capstone', year='1st Year'), [])
        self.capstone_team.project_version += 1
        self.capstone_team.save(update_fields=['project_version'])
        self.assertEqual(automation.fetch_target_schedule_ids(scope='capstone'), [])

    def test_no_matching_cohort_is_a_clean_skip_with_no_api_calls(self):
        self.assertEqual(self.exercise('--year', '1'), 0, self.output)
        self.assertEqual(self.calls, [])
        self.assertIn('No current scheduled defenses', self.output)


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PitPanelAutomationApiTests(_AutomationMixin, APITestCase):
    def setUp(self):
        grade_fixtures.GradeCenterApiTests.setUp(self)
        rubric = Rubric.objects.create(name='PIT panel', scope='pit', semester=self.first_semester,
            event_name='PIT Expo', evaluation_type='panel', status='published')
        RubricCriterion.objects.create(rubric=rubric, name='Technical quality', max_score=10)
        PitEventGradingConfig.objects.update_or_create(semester=self.first_semester, event_name='PIT Expo',
            defaults={'year_level': '2nd Year', 'panel_rubric': rubric})
        self.pit_schedule.rubric = rubric
        self.pit_schedule.save(update_fields=['rubric'])

    def test_pit_scores_only_and_repeat_does_not_overwrite(self):
        self.assertEqual(self.exercise('--semester-id', str(self.first_semester.pk), scope='pit', year='2'), 0, self.output)
        grade = TeamGrade.objects.get(schedule=self.pit_schedule)
        self.assertEqual(float(grade.panel_score), 80)
        self.assertEqual(grade.verdict, '')
        self.assertEqual(len(self.writes()), 1)
        self.assertEqual(self.writes()[0]['actor'].pk, self.panelist.pk)
        self.assertEqual(self.exercise('--semester-id', str(self.first_semester.pk), scope='pit', year='2'), 0, self.output)
        self.assertEqual(self.writes(), [])


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class ConceptPanelAutomationApiTests(_AutomationMixin, APITestCase):
    prepare = concept_fixtures.ConceptHearingWorkflowTests.prepare

    def setUp(self):
        outcome_fixtures.PerConceptOutcomeTests.setUp(self)

    def test_every_concept_is_scored_by_faculty_and_guest_without_selecting_one(self):
        self.add_guest()
        self.assertEqual(self.exercise(), 0, self.output)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panelist_submissions.count(), 6)
        self.assertEqual(set(self.grade.panelist_submissions.values_list('concept_key', flat=True)), {'c1', 'c2', 'c3'})
        self.assertIsNone(self.grade.panel_score)
        self.assertEqual(self.grade.verdict, '')
        self.assertEqual([call['method'] for call in self.writes()], ['POST', 'POST'])
        hearing = ConceptRound.objects.get(schedule=self.capstone_schedule)
        self.assertFalse(any(concept.get('decision') == 'approved' for concept in hearing.concepts))


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class LegacyConceptPanelAutomationApiTests(_AutomationMixin, APITestCase):
    prepare = concept_fixtures.ConceptHearingWorkflowTests.prepare

    def setUp(self):
        concept_fixtures.ConceptHearingWorkflowTests.setUp(self)
        SchedulePanelist.objects.filter(schedule=self.capstone_schedule).update(is_chair=True)

    def test_non_per_concept_hearing_still_requires_manual_concept_decisions(self):
        self.assertEqual(self.exercise(), 0, self.output)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panelist_submissions.count(), 1)
        self.assertEqual(self.grade.verdict, '')
        self.assertEqual([call['method'] for call in self.writes()], ['POST'])
        self.assertIn('chair must review the concepts', self.output)
