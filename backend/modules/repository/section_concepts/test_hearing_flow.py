"""Early/late selection, section release and ownership of selected final papers."""
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from defense.document_policy import with_concept_papers, is_approved_concept
from grading.grades.services import submit_panelist_grade
from repository.deliverables import concepts
from repository.deliverables.services import archive_unlocked, upsert_submission, review_submission
from . import services, tests as fixtures
from repository.deliverables import test_submission_timing as timing_fixtures


class SharedHearingFlowTests(APITestCase):
    setUp = fixtures.SharedSystemConceptTests.setUp
    configure = fixtures.SharedSystemConceptTests.configure
    rubric = fixtures.SharedSystemConceptTests.rubric
    data = fixtures.SharedSystemConceptTests.data
    slot = fixtures.SharedSystemConceptTests.slot
    titles = fixtures.SharedSystemConceptTests.titles
    action = fixtures.SharedSystemConceptTests.action
    prepare_shared = fixtures.SharedSystemConceptTests.prepare_shared
    prepare_team = fixtures.SharedSystemConceptTests.prepare_team
    hearing = fixtures.SharedSystemConceptTests.hearing
    select = fixtures.SharedSystemConceptTests.select

    def decision(self, *, outcomes=None, actor=None):
        return self.action('decide', actor or self.panelist, verdict='approved', team_outcomes=outcomes or [], concepts=[
            {'key': key, 'decision': 'approved' if key == 'c2' else 'not_selected'} for key in services.KEYS])

    def outcome(self, team, verdict='approved', remarks=''):
        row = next(t for t in services.payload(self.project, self.panelist)['teams'] if t['id'] == team.pk)
        return {'team_id': team.pk, 'verdict': verdict, 'remarks': remarks,
                'review_token': row['module_outcome_review_token']}

    def finish(self):
        self.hearing()
        response = self.decision(outcomes=[self.outcome(self.team), self.outcome(self.module_team,
            'approved_with_revisions', 'Clarify the module architecture.')])
        self.assertEqual(response.status_code, 200, response.data)
        return response

    def test_setup_adds_both_required_definitions_once_and_keeps_authored_final_id(self):
        items = [{'deliverable_id': 'CUSTOM_FINAL', 'label': 'Approved Concept Paper', 'deliverable_type': 'post', 'required': False}]
        generated = with_concept_papers(items, {'enabled': True})
        self.assertEqual(generated, with_concept_papers(generated, {'enabled': True}))
        self.assertEqual(len(generated), 2)
        final = next(d for d in generated if is_approved_concept(d))
        self.assertEqual(final['deliverable_id'], 'CUSTOM_FINAL')
        self.assertTrue(final['required'])
        self.assertEqual(with_concept_papers(items, {'enabled': False}), items)

    def test_chair_can_start_and_select_before_any_panel_scores_without_approving_modules(self):
        self.hearing(evaluated=False)
        started = self.action('start_presentation', self.panelist)
        self.assertEqual(started.status_code, 200, started.data)
        self.assertTrue(started.data['presentation_started_at'])
        response = self.decision()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['selected_key'], 'c2')
        self.assertFalse(response.data['post_unlocked'])
        for team in (self.team, self.module_team):
            self.assertEqual(concepts.latest_round(team, self.event).verdict, '')
            self.assertEqual(concepts.latest_round(team, self.event).schedule.grade_records.get().project_title_snapshot, 'Module c2')
            self.assertFalse(archive_unlocked(team, self.event.label))

    def test_late_selection_finalizes_only_explicit_already_graded_team_outcomes(self):
        self.hearing()
        response = self.decision(outcomes=[self.outcome(self.team, 'approved_with_revisions', 'Keep this correction.')])
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(concepts.latest_round(self.team, self.event).verdict, 'approved_with_revisions')
        self.assertEqual(concepts.latest_round(self.module_team, self.event).verdict, '')
        self.assertFalse(response.data['post_unlocked'])
        self.assertTrue(all(len(t['concepts']) == 3 for t in response.data['teams']))
        for schedule in services.latest(self.project).schedules.all():
            self.assertIsNotNone(schedule.grade_records.get().panel_score)
            self.assertEqual(schedule.grade_records.get().verdict, '')

    def test_final_uploads_open_together_after_all_team_outcomes_including_revisions(self):
        response = self.finish()
        self.assertTrue(response.data['post_unlocked'])
        self.assertTrue(archive_unlocked(self.team, self.event.label))
        self.assertTrue(archive_unlocked(self.module_team, self.event.label))

    def test_ungraded_or_stale_batch_outcomes_roll_back_the_whole_choice(self):
        self.hearing(evaluated=False)
        response = self.decision(outcomes=[self.outcome(self.team)])
        self.assertEqual(response.status_code, 400)
        self.assertFalse(services.latest(self.project).selected_key)
        self.assertFalse(concepts.latest_round(self.team, self.event).verdict)

    def test_panel_scores_without_a_choice_do_not_unlock_post_defense(self):
        self.hearing()
        self.assertFalse(archive_unlocked(self.team, self.event.label))
        self.assertFalse(archive_unlocked(self.module_team, self.event.label))

    def test_only_pm_submits_shared_final_and_proposals_remain_preserved(self):
        self.finish()
        with self.assertRaises(PermissionError):
            services.upload(self.project, self.module_team.leader, 'c2',
                SimpleUploadedFile('final.pdf', b'%PDF-1.4 final'), purpose='final')
        row = services.upload(self.project, self.pm, 'c2',
            SimpleUploadedFile('final.pdf', b'%PDF-1.4 final'), purpose='final')
        services.review(self.project, self.first, row.pk, 'accepted')
        state = services.payload(self.project, self.pm)
        self.assertTrue(state['shared_final_archived'])
        self.assertEqual(sum(len(s['papers']) for s in state['systems']), 3)
        self.assertEqual(len(next(s for s in state['systems'] if s['key'] == 'c2')['final_papers']), 1)
        from repository.project_archive.shared_concepts import shared_final_entries
        entries = shared_final_entries({'scope': 'pit_lead', 'pit_year_level': self.team.year_level})
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]['section_project_id'], self.project.pk)
        self.assertIsNone(entries[0]['team_id'])
        self.assertEqual(shared_final_entries({'scope': 'pit_lead', 'pit_year_level': '3rd Year'}), [])
        with self.assertRaises(ValidationError):
            services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('wrong.pdf', b'%PDF-1.4'), purpose='final')

    def test_module_final_is_bound_to_selected_hearing_and_acceptance_clears_only_its_revisions(self):
        self.finish()
        team = self.module_team
        current = concepts.latest_round(team, self.event)
        row = upsert_submission(team, self.event.label, 'APPROVED_PAPER', 'final.pdf', '10 B', team.leader,
            file=SimpleUploadedFile('final.pdf', b'%PDF-1.4 final module'))
        paper = row.files.get(is_current=True)
        self.assertEqual((paper.concept_round_id, paper.selected_concept_key), (current.pk, 'c2'))
        review_submission(team, self.event.label, 'APPROVED_PAPER', 'accepted', 'Verified the correction.', self.first, file_id=paper.pk)
        current.refresh_from_db()
        self.assertIsNotNone(current.revisions_cleared_at)
        self.assertIsNone(services.latest(self.project).revisions_cleared_at)

    def test_unrelated_accepted_post_file_does_not_clear_module_revisions(self):
        from defense.scheduler.models import PitEventDeliverable
        self.finish()
        PitEventDeliverable.objects.create(pit_event_config=self.event, deliverable_id='CHECKLIST',
            label='Administrative checklist', deliverable_type='post', file_format='pdf')
        sub = upsert_submission(self.module_team, self.event.label, 'CHECKLIST', 'checklist.pdf', '10 B', self.module_team.leader,
            file=SimpleUploadedFile('checklist.pdf', b'%PDF-1.4 unrelated checklist'))
        review_submission(self.module_team, self.event.label, 'CHECKLIST', 'accepted', '', self.first)
        self.assertIsNone(concepts.latest_round(self.module_team, self.event).revisions_cleared_at)

    def test_multiple_selected_module_attachments_clear_revisions_only_after_all_reviews(self):
        from repository.deliverables.concept_completion import final_paper_complete
        # Establish the fixture's authored policy before any hearing documents.
        # Production setup edits remain locked once a shared project has begun.
        definition = self.event.deliverables.get(deliverable_id='APPROVED_PAPER')
        definition.file_policy = {'mode': 'multiple', 'min_files': 1, 'max_files': 3, 'purpose': 'approved_concept'}
        definition.save()
        self.finish()
        team = self.module_team
        sub = upsert_submission(team, self.event.label, 'APPROVED_PAPER', 'paper.pdf', '10 B', team.leader,
            file=SimpleUploadedFile('paper.pdf', b'%PDF-1.4 final module'))
        first = sub.files.get(is_current=True)
        sub = upsert_submission(team, self.event.label, 'APPROVED_PAPER', 'appendix.pdf', '10 B', team.leader,
            file=SimpleUploadedFile('appendix.pdf', b'%PDF-1.4 appendix'))
        review_submission(team, self.event.label, 'APPROVED_PAPER', 'accepted', '', self.first, file_id=first.pk)
        self.assertIsNone(concepts.latest_round(team, self.event).revisions_cleared_at)
        self.assertFalse(final_paper_complete(team, self.event))
        second = sub.files.filter(is_current=True).exclude(pk=first.pk).get()
        review_submission(team, self.event.label, 'APPROVED_PAPER', 'accepted', '', self.first, file_id=second.pk)
        self.assertIsNotNone(concepts.latest_round(team, self.event).revisions_cleared_at)
        self.assertTrue(final_paper_complete(team, self.event))
        self.assertIsNone(services.latest(self.project).revisions_cleared_at)

    def test_non_chair_cannot_start_or_decide_and_stale_batch_is_atomic(self):
        self.hearing()
        self.assertIn(self.action('start_presentation', self.unassigned).status_code, (403, 404))
        item = self.outcome(self.team)
        item['review_token'] = 'old-assessment'
        response = self.decision(outcomes=[item])
        self.assertEqual(response.status_code, 400)
        self.assertFalse(services.latest(self.project).selected_key)
        self.assertFalse(concepts.latest_round(self.team, self.event).verdict)

    def test_explicit_started_event_repair_adds_only_the_missing_requirement(self):
        from django.core.management import call_command
        from io import StringIO
        self.hearing(evaluated=False)
        self.event.deliverables.filter(file_policy__purpose='approved_concept').delete()
        before = concepts.latest_round(self.team, self.event).documents_snapshot
        output = StringIO()
        call_command('reconcile_concept_requirements', pit_event_id=self.event.pk, apply=True, stdout=output)
        self.assertFalse(self.event.deliverables.filter(file_policy__purpose='approved_concept').exists())
        call_command('reconcile_concept_requirements', pit_event_id=self.event.pk, include_started=True,
            reason='Approved required final-paper workflow repair.', apply=True, stdout=output)
        self.assertEqual(self.event.deliverables.filter(file_policy__purpose='approved_concept', required=True).count(), 1)
        self.assertEqual(concepts.latest_round(self.team, self.event).documents_snapshot, before)
        self.assertFalse(concepts.latest_round(self.team, self.event).verdict)

    def test_started_event_repair_never_adds_requirements_to_officially_completed_event(self):
        from django.core.management import call_command
        from io import StringIO
        self.hearing(evaluated=False)
        self.event.deliverables.filter(file_policy__purpose='approved_concept').delete()
        self.event.is_officially_complete = True
        self.event.save()
        call_command('reconcile_concept_requirements', pit_event_id=self.event.pk, include_started=True,
            reason='Requested repair.', apply=True, stdout=StringIO())
        self.assertFalse(self.event.deliverables.filter(file_policy__purpose='approved_concept').exists())


class CapstoneSharedHearingFlowTests(APITestCase):
    setUp = timing_fixtures.faculty_review_setup

    def test_configured_module_outcome_uses_the_selected_systems_assessment(self):
        from grading.grades.outcome_rules import outcome_payload
        from grading.grades.defense_workflow import record_verdict
        self.stage.qualifying_score = 75
        self.stage.save()
        project, schedule, grade, criterion = self.prepare_hearing()
        services.start_presentation(project, self.chair)
        for key, score in [('c1', 9), ('c2', 6), ('c3', 8)]:
            submit_panelist_grade(schedule, grade, [{'criterion_id': criterion.pk, 'score': score}],
                panelist=self.chair, concept_key=key)
        self.assertEqual(outcome_payload(grade)['outcome'], 'pending')
        services.decide(project, self.chair, [{'key': key,
            'decision': 'approved' if key == 'c2' else 'not_selected'} for key in services.KEYS], 'approved', '')
        self.assertEqual(outcome_payload(grade)['outcome'], 'for_redefense')
        result = record_verdict(grade, actor=self.chair, verdict='for_redefense', remarks='Revise the selected module.',
            concept_decisions=[{'key': key, 'decision': 'revise' if key == 'c2' else 'not_selected',
                'remarks': 'Revise this module.' if key == 'c2' else ''} for key in services.KEYS])
        self.assertEqual(result.verdict, 'for_redefense')
        current = concepts.latest_round(self.team, self.stage)
        self.assertEqual([c['key'] for c in current.concepts], ['c2'])
        self.assertEqual(current.section_round_id, services.latest(project).pk)
        self.assertEqual(services.latest(project).selected_key, 'c2')
        self.assertEqual(services.latest(project).verdict, 'approved')
        self.assertEqual(current.concepts[0]['panel_feedback'], 'Revise this module.')

    def test_shared_system_denial_does_not_create_a_module_pass_from_qualifying_scores(self):
        self.stage.qualifying_score = 75
        self.stage.save()
        project, schedule, grade, criterion = self.prepare_hearing()
        services.start_presentation(project, self.chair)
        for key in services.KEYS:
            submit_panelist_grade(schedule, grade, [{'criterion_id': criterion.pk, 'score': 9}],
                panelist=self.chair, concept_key=key)
        services.decide(project, self.chair, [{'key': key, 'decision': 'rejected',
            'remarks': 'Replace the shared system.'} for key in services.KEYS],
            'for_redefense', 'Replace the shared system.')
        grade.refresh_from_db()
        self.assertEqual(grade.verdict, 'for_redefense')
        self.assertFalse(archive_unlocked(self.team, self.stage.label))

    def prepare_hearing(self):
        from django.contrib.auth import get_user_model
        from django.utils import timezone
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        from defense.stages.models import StageDeliverable, StageGradingConfig
        from grading.rubrics.models import Rubric, RubricCriterion
        from grading.grades.services import GradeContextService
        from repository.deliverables.services import endorse_team
        self.stage.deliverables.all().delete()
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save()
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='CONCEPTS',
            label='Concept Papers', required=True, file_policy={'mode': 'concepts'}, file_format='pdf')
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='FINAL_CONCEPT',
            label='Approved Concept Paper', required=True, deliverable_type='post', file_format='pdf',
            file_policy={'mode': 'single', 'purpose': 'approved_concept'})
        self.team.section = 'BSIT-3A'
        self.team.save()
        project = services.configure(self.admin, [self.team], self.stage,
            {'project_manager_id': self.student.pk, 'reviewer_id': self.adviser.pk})
        titles = [{'key': key, 'title': f'System {key}'} for key in services.KEYS]
        services.save_system_titles(project, self.adviser, titles)
        concepts.save_titles(self.team, self.stage, [{'key': key, 'title': f'Module {key}'} for key in services.KEYS], actor=self.adviser)
        for key in services.KEYS:
            shared = services.upload(project, self.student, key, SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 proposal'))
            services.review(project, self.adviser, shared.pk, 'accepted')
            sub = upsert_submission(self.team, self.stage.label, 'CONCEPTS', f'{key}.pdf', '10 B', self.student,
                file=SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 module'), slot_key=f'{key}:paper')
            review_submission(self.team, self.stage.label, 'CONCEPTS', 'accepted', '', self.adviser,
                file_id=sub.files.get(is_current=True, slot_key=f'{key}:paper').pk)
        endorse_team(self.team, self.stage.label, self.adviser)
        rubric = Rubric.objects.create(name='Shared Capstone panel', scope='capstone', semester=self.semester,
            defense_stage=self.stage, evaluation_type='panel', status='published', created_by=self.admin)
        criterion = RubricCriterion.objects.create(rubric=rubric, name='Presentation', scale=Rubric.SCALE_10, max_score=10)
        StageGradingConfig.objects.create(defense_stage=self.stage, semester=self.semester,
            panel_rubric=rubric, panel_weight=100, adviser_weight=0, peer_weight=0)
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            rubric=rubric, scheduled_date=timezone.localdate(), start_time='09:00', room='Shared Capstone')
        self.chair = get_user_model().objects.create_user(username='shared-capstone-chair', role='faculty')
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.chair, is_chair=True)
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        services.schedule_hearing(project, self.admin, [schedule.pk])
        return project, schedule, grade, criterion

    def test_capstone_early_selection_then_normal_verdict_final_review_and_clearance(self):
        from grading.grades.defense_workflow import record_verdict
        project, schedule, grade, criterion = self.prepare_hearing()
        services.start_presentation(project, self.chair)
        services.decide(project, self.chair, [{'key': key,
            'decision': 'approved' if key == 'c2' else 'not_selected'} for key in services.KEYS], 'approved', '')
        self.assertFalse(archive_unlocked(self.team, self.stage.label))
        submit_panelist_grade(schedule, grade, [{'criterion_id': criterion.pk, 'score': 8}], panelist=self.chair)
        record_verdict(grade, actor=self.chair, verdict='approved_with_revisions', remarks='Clarify module scope.',
            concept_decisions=[{'key': key, 'decision': 'approved_with_revisions' if key == 'c2' else 'not_selected',
                'remarks': 'Clarify module scope.' if key == 'c2' else ''} for key in services.KEYS])
        self.assertTrue(archive_unlocked(self.team, self.stage.label))
        sub = upsert_submission(self.team, self.stage.label, 'FINAL_CONCEPT', 'final.pdf', '10 B', self.student,
            file=SimpleUploadedFile('final.pdf', b'%PDF-1.4 corrected module'))
        review_submission(self.team, self.stage.label, 'FINAL_CONCEPT', 'accepted', 'Corrections verified.', self.adviser,
            file_id=sub.files.get(is_current=True).pk, clear_defense_revisions=True)
        grade.refresh_from_db()
        self.assertEqual(grade.verdict, 'approved_with_revisions')
        self.assertIsNotNone(grade.revisions_cleared_at)
        self.assertIsNotNone(grade.panel_score)

    def test_concept_off_final_paper_metadata_keeps_normal_upload_flow(self):
        from defense.stages.models import StageDeliverable
        from defense.scheduler.models import DefenseSchedule
        self.stage.concept_config = {'enabled': False}
        self.stage.save()
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='FINAL_CONCEPT',
            label='Approved Concept Paper', deliverable_type='post', file_policy={'mode': 'single', 'purpose': 'approved_concept'})
        DefenseSchedule.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=self.date, start_time='09:00', room='Normal defense', status='done')
        self.assertTrue(archive_unlocked(self.team, self.stage.label))
        sub = upsert_submission(self.team, self.stage.label, 'FINAL_CONCEPT', 'final.pdf', '10 B', self.student,
            file=SimpleUploadedFile('final.pdf', b'%PDF-1.4 normal final'))
        self.assertIsNone(sub.files.get(is_current=True).concept_round_id)
