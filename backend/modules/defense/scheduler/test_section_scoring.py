from decimal import Decimal

from django.core.exceptions import ValidationError
from rest_framework.test import APITestCase

from grading.grades.models import PanelistSectionScore
from grading.grades.section_scoring import section_definitions
from grading.rubrics.models import Rubric, RubricCriterion
from . import test_panelist_evaluation as fixtures
from .panelist_evaluation import evaluation_context, validate_evaluation_submissions


class SectionScoringTests(APITestCase):
    setUp = fixtures.PanelistEvaluationTests.setUp
    schedule = fixtures.PanelistEvaluationTests.schedule
    _complete_prior_stages = fixtures.PanelistEvaluationTests._complete_prior_stages

    def setup_section(self, target='team'):
        self.rubric.scale = Rubric.SCALE_POINTS
        self.rubric.target_type = target
        self.rubric.save()
        self.rubric.criteria.all().delete()
        for index, maximum in enumerate([40, 40, 20]):
            RubricCriterion.objects.create(rubric=self.rubric, name=f'Guide {index}',
                section='Oral Examination', max_score=maximum, weight=maximum / 5 if target == 'both' else maximum,
                target_type='individual' if target == 'both' else target,
                scale=Rubric.SCALE_POINTS, display_order=index)
        if target == 'both':
            RubricCriterion.objects.create(rubric=self.rubric, name='System quality', section='System',
                max_score=50, weight=80, target_type='team', scale=Rubric.SCALE_POINTS, display_order=3)
        schedule = self.schedule()
        section = next(s for s in section_definitions(self.rubric) if s['name'] == 'Oral Examination')
        block = {'student_id': None, 'criteria_scores': [],
                 'section_scores': [{'section_key': section['section_key'], 'score': 90}], 'remarks': ''}
        return schedule, section, block

    def test_mixed_targets_combine_team_criteria_and_individual_overall_once(self):
        schedule, section, block = self.setup_section('both')
        system = self.rubric.criteria.get(name='System quality')
        members = list(self.team.memberships.order_by('student_id'))
        blocks = [{'student_id': None, 'criteria_scores': [{'criterion_id': system.pk, 'score': 40}]}]
        for index, member in enumerate(members):
            blocks.append({'student_id': member.student_id, 'criteria_scores': [],
                'section_scores': [{'section_key': section['section_key'], 'score': 95 - index * 5}]})
        response = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk, 'evaluation_context': evaluation_context(schedule),
            'section_scoring_version': 1, 'submissions': blocks}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        grade = schedule.grade_records.get()
        for index, member in enumerate(members):
            self.assertEqual(grade.student_grades.get(student_id=member.student_id).panel_score, Decimal(83 - index))
        self.assertEqual(grade.panel_score, sum((Decimal(83 - i) for i in range(len(members))), Decimal(0)) / len(members))
        self.assertEqual(PanelistSectionScore.objects.count(), len(members))

    def test_guest_section_only_submission_and_results(self):
        from authentication_access_control.guest_authentication import GuestPanelistPrincipal
        from user_management.models import GuestPanelistCode
        schedule, section, block = self.setup_section()
        invitation = GuestPanelistCode.objects.create(guest_name='External section evaluator', defense_schedule=schedule)
        invitation.schedules.add(schedule)
        guest = GuestPanelistPrincipal({'guest_code_id': str(invitation.pk), 'guest_code': invitation.code,
            'defense_schedule_id': schedule.pk, 'team_id': self.team.pk, 'guest_name': invitation.guest_name}, invitation=invitation)
        self.client.force_authenticate(user=guest)
        response = self.client.post('/api/defense/schedules/guest-submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk, 'evaluation_context': evaluation_context(schedule),
            'section_scoring_version': 1, 'submissions': [block]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        response = self.client.get('/api/defense/schedules/guest-assignments/')
        self.assertTrue(response.data['teams'][0]['is_posted'])
        result = self.client.get('/api/defense/schedules/guest-panelist-results/').data['results'][0]
        self.assertEqual(result['percentage'], 90)
        self.assertEqual(result['criteria'][0]['score_kind'], 'section')

    def test_section_only_draft_submission_readback_and_real_snapshots(self):
        schedule, section, block = self.setup_section()
        payload = {'schedule_id': schedule.pk, 'evaluation_context': evaluation_context(schedule),
                   'submissions': [block], 'section_scoring_version': 1}
        response = self.client.post('/api/defense/schedules/grade-draft/', payload, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        assignment = self.client.get('/api/defense/schedules/panelist-assignments/').data['teams'][0]
        self.assertEqual(assignment['panel_rubric']['scoring_sections'][0]['section_key'], section['section_key'])
        payload.update(team_id=self.team.pk, evaluation_context=assignment['evaluation_context'])
        response = self.client.post('/api/defense/schedules/submit-grades/', payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        row = PanelistSectionScore.objects.get()
        self.assertEqual(row.score, Decimal('90'))
        self.assertEqual(row.max_score_snapshot, Decimal('100'))
        self.assertEqual(row.criteria_snapshot[0]['name'], 'Guide 0')
        self.assertFalse(row.submission.criterion_scores.exists())
        row.submission.team_grade.refresh_from_db()
        self.assertEqual(row.submission.team_grade.panel_score, Decimal('90'))
        self.assertEqual(row.submission.breakdown_rows.get().score_kind, 'section')
        assignment = self.client.get('/api/defense/schedules/panelist-assignments/').data['teams'][0]
        self.assertTrue(assignment['is_posted'])
        self.assertEqual(assignment['submissions'][0]['section_scores'][0]['score'], 90)
        from grading.grades.corrections import correction_details, _perform_change
        details = correction_details(row.submission.team_grade)
        self.assertEqual(details['scores'][0]['score_kind'], 'section')
        self.assertEqual(details['completion']['submitted'], 1)
        _perform_change(row.submission.team_grade, {'section': {'id': row.pk, 'score': 85}})
        row.submission.team_grade.refresh_from_db()
        self.assertEqual(row.submission.team_grade.panel_score, Decimal('85'))
        self.assertEqual(row.submission.breakdown_rows.get().score, Decimal('85'))
        import io
        import pdfplumber
        from reports.generators.team_grade_report import generate_team_grade_pdf
        pdf = generate_team_grade_pdf(row.submission.team_grade, self.admin)
        with pdfplumber.open(io.BytesIO(pdf)) as document:
            text = '\n'.join(page.extract_text() or '' for page in document.pages)
        self.assertIn('Overall section score', text)
        self.assertIn('Oral Examination', text)

    def test_concept_overall_score_does_not_complete_other_concepts(self):
        from repository.deliverables.models import ConceptRound
        schedule, section, block = self.setup_section()
        schedule.assessment_policy = {**schedule.assessment_policy, 'per_concept': True,
                                      'shared_module_scope_version': 0}
        schedule.save(update_fields=['assessment_policy'])
        ConceptRound.objects.create(team=self.team, defense_stage=self.stage, schedule=schedule,
            number=99, concepts=[{'key': 'c1', 'title': 'First'}, {'key': 'c2', 'title': 'Second'}])
        block['concept_key'] = 'c1'
        with self.assertRaises(ValidationError):
            validate_evaluation_submissions(schedule, [block])
        second = {**block, 'concept_key': 'c2'}
        self.assertEqual(len(validate_evaluation_submissions(schedule, [block, second])), 2)

    def test_section_uses_sum_of_maxima_and_retains_its_recorded_weight(self):
        schedule, section, block = self.setup_section()
        criteria = list(self.rubric.criteria.all())
        for criterion, maximum, weight in zip(criteria, [10, 5, 5], [80, 10, 10]):
            criterion.max_score, criterion.weight = maximum, weight
            criterion.save()
        block['section_scores'][0]['score'] = 15
        response = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk, 'evaluation_context': evaluation_context(schedule),
            'section_scoring_version': 1, 'submissions': [block]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        row = PanelistSectionScore.objects.get()
        self.assertEqual(row.max_score_snapshot, Decimal('20'))
        self.assertEqual(row.submission.team_grade.panel_score, Decimal('75'))
        from grading.grades.services import recompute_panel_score
        self.rubric.criteria.update(max_score=100, weight=1)
        recompute_panel_score(row.submission.team_grade)
        row.submission.team_grade.refresh_from_db()
        self.assertEqual(row.submission.team_grade.panel_score, Decimal('75'))

    def test_overlap_invalid_scores_and_wrong_sections_rejected(self):
        schedule, section, block = self.setup_section()
        for value in [-1, 101, 'NaN', 'Infinity', '8.555']:
            block['section_scores'][0]['score'] = value
            with self.subTest(value=value), self.assertRaises(ValidationError):
                validate_evaluation_submissions(schedule, [block])
        block['section_scores'][0]['score'] = 0
        validate_evaluation_submissions(schedule, [block])
        block['criteria_scores'] = [{'criterion_id': section['criterion_ids'][0], 'score': 0}]
        with self.assertRaises(ValidationError):
            validate_evaluation_submissions(schedule, [block], partial=True)
        block['criteria_scores'] = []
        block['section_scores'][0]['section_key'] = 'unknown'
        with self.assertRaises(ValidationError):
            validate_evaluation_submissions(schedule, [block], partial=True)

    def test_legacy_client_cannot_erase_overall_draft(self):
        schedule, section, block = self.setup_section()
        payload = {'schedule_id': schedule.pk, 'evaluation_context': evaluation_context(schedule),
                   'submissions': [block], 'section_scoring_version': 1}
        self.assertEqual(self.client.post('/api/defense/schedules/grade-draft/', payload, format='json').status_code, 200)
        payload.pop('section_scoring_version')
        payload['submissions'] = [{'student_id': None, 'criteria_scores': [], 'remarks': ''}]
        response = self.client.post('/api/defense/schedules/grade-draft/', payload, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(schedule.evaluation_drafts.get().submissions[0]['section_scores'][0]['score'], 90)
