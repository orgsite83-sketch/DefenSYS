"""Shared final-paper ownership remains distinct from accepted team modules."""
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from repository.deliverables.services import post_deliverables_state, upsert_submission, review_submission
from repository.project_archive.shared_concepts import shared_project_entries, attach_shared_team_context
from repository.project_archive.folders import archive_folder_payload
from . import services, shared_deliverables as shared, tests as fixtures, test_hearing_flow as hearing_fixtures
from .models import SectionConceptRound, SharedDeliverableSet


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedCompletionProjectionTests(APITestCase):
    configure = fixtures.SharedSystemConceptTests.configure
    rubric = fixtures.SharedSystemConceptTests.rubric
    data = fixtures.SharedSystemConceptTests.data
    slot = fixtures.SharedSystemConceptTests.slot
    titles = fixtures.SharedSystemConceptTests.titles
    action = fixtures.SharedSystemConceptTests.action
    prepare_shared = fixtures.SharedSystemConceptTests.prepare_shared
    prepare_team = fixtures.SharedSystemConceptTests.prepare_team
    hearing = fixtures.SharedSystemConceptTests.hearing
    decision = hearing_fixtures.SharedHearingFlowTests.decision
    outcome = hearing_fixtures.SharedHearingFlowTests.outcome
    finish = hearing_fixtures.SharedHearingFlowTests.finish

    def setUp(self):
        media = tempfile.TemporaryDirectory()
        self.addCleanup(media.cleanup)
        settings = self.settings(MEDIA_ROOT=media.name)
        settings.enable()
        self.addCleanup(settings.disable)
        fixtures.SharedSystemConceptTests.setUp(self)
        self.finish()
        for team in (self.team, self.module_team):
            submission = upsert_submission(team, self.event.label, 'APPROVED_PAPER', 'module.pdf', '20 B',
                team.leader, file=SimpleUploadedFile('module.pdf', b'%PDF-1.4 final module'))
            review_submission(team, self.event.label, 'APPROVED_PAPER', 'accepted', '', self.first,
                file_id=submission.files.get(is_current=True).pk)

    def test_accepted_team_files_do_not_claim_shared_pm_upload_is_an_adviser_review(self):
        before = (SectionConceptRound.objects.count(), SharedDeliverableSet.objects.count())
        states = [post_deliverables_state(team, self.event.label) for team in (self.team, self.module_team)]
        for state in states:
            self.assertTrue(state['team_complete'])
            self.assertFalse(state['complete'])
            self.assertFalse(state['shared_complete'])
            self.assertEqual(state['shared']['status'], 'awaiting_pm_upload')
            self.assertEqual(state['shared']['selected_key'], 'c2')
            self.assertEqual(state['shared']['selected_system_title'], 'System c2')
            self.assertEqual(state['shared']['documents_required'], 1)
        self.assertEqual(states[0]['shared']['identity'], states[1]['shared']['identity'])
        self.assertEqual(before, (SectionConceptRound.objects.count(), SharedDeliverableSet.objects.count()))

    def test_pm_upload_then_actual_shared_review_release_completion(self):
        profile = shared.for_round(services.latest(self.project))
        before = shared.payload(profile, self.pm)
        final = next(row for row in before['requirements'] if row['deliverable_type'] == 'post')
        suggested = final['documents'][0]['suggested_file_name']
        self.assertTrue(suggested.endswith('.pdf'))
        self.assertIn('Systemc2', suggested)
        self.assertTrue(all(not doc['suggested_file_name'] for row in before['requirements']
            if row['deliverable_type'] == 'pre' for doc in row['documents']))
        paper = services.upload(self.project, self.pm, 'c2',
            SimpleUploadedFile('system-final.pdf', b'%PDF-1.4 shared final'), purpose='final')
        self.assertEqual(paper.file_name, suggested)
        state = post_deliverables_state(self.team, self.event.label)
        self.assertEqual(state['shared']['status'], 'awaiting_review')
        self.assertFalse(state['complete'])
        services.review(self.project, self.first, paper.pk, 'accepted')
        state = shared.payload(shared.for_round(services.latest(self.project)), self.first)
        requirement = next(row for row in state['requirements'] if row['deliverable_type'] == 'post')
        document = requirement['documents'][0]
        self.assertFalse(document['can_review'])
        self.assertFalse(document['can_upload'])
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/repository/section-concepts/shared-deliverables/', {
            'team_id': self.team.pk, 'stage_label': self.event.label,
            'review_token': state['review_token'], 'deliverable_id': requirement['deliverable_id'],
            'slot_key': document['key'], 'file_id': paper.pk, 'legacy': True,
            'action': 'review', 'status': 'rejected', 'feedback': 'An archived file must not reopen here.',
        }, format='json')
        self.assertEqual(response.status_code, 400)
        paper.refresh_from_db()
        self.assertEqual(paper.status, 'accepted')
        for team in (self.team, self.module_team):
            self.assertTrue(post_deliverables_state(team, self.event.label)['complete'])
        entries = shared_project_entries({'scope': 'admin'})
        self.assertFalse(any(row.get('is_shared_requirement') for row in entries))
        archived = next(row for row in entries if row['id'] == f'section-final-{paper.pk}')
        definition = next(d for d in services.latest(self.project).shared_requirements_snapshot
            if d.get('legacy_purpose') == 'final')
        self.assertEqual(archived['deliverable_id'], definition['deliverable_id'])

    def test_grade_readiness_carries_one_shared_identity_for_linked_teams(self):
        from grading.grades.services import cohort_grading_teams_for_group
        rows = cohort_grading_teams_for_group(self.semester, 'pit', self.event.label, config=self.event)
        self.assertEqual(len(rows), 2)
        for row in rows:
            self.assertIn('post_defense', row['missing_components'])
            self.assertTrue(row['post_defense_completion']['team_complete'])
            self.assertEqual(row['post_defense_completion']['shared']['status'], 'awaiting_pm_upload')
        self.assertEqual(len({row['post_defense_completion']['shared']['identity'] for row in rows}), 1)

    def test_adviser_shared_checklist_identifies_the_selected_system(self):
        payload = shared.payload(shared.for_round(services.latest(self.project)), self.first)
        self.assertEqual(payload['selected_key'], 'c2')
        self.assertEqual(len(payload['systems']), 3)  # Earlier proposals remain readable.
        self.assertEqual(payload['post_completion']['selected_system_title'], 'System c2')
        self.assertFalse(any(document['can_upload'] for row in payload['requirements']
            if row['deliverable_type'] == 'post' for document in row['documents']))

    def test_archive_retains_shared_proposals_and_shows_only_one_missing_pm_paper(self):
        entries = shared_project_entries({'scope': 'admin'})
        pending = [row for row in entries if row.get('is_shared_requirement')]
        self.assertEqual(len(pending), 1)
        self.assertEqual(pending[0]['workflow_status'], 'awaiting_pm_upload')
        self.assertIsNone(pending[0]['team_id'])
        self.assertEqual(len([row for row in entries if row.get('is_proposal_history')]), 3)
        browser = archive_folder_payload(entries)
        for _ in range(4):
            browser = archive_folder_payload(entries, folder_key=browser['folders'][0]['key'])
        self.assertEqual(len(browser['folders']), 1)
        self.assertEqual(browser['folders'][0]['missing_count'], 1)
        section = archive_folder_payload(entries, folder_key=browser['folders'][0]['key'])
        self.assertEqual({row['title'] for row in section['folders']}, {'Selected shared system', 'Proposal history'})
        self.assertEqual(section['shared_context']['selected_system_title'], 'System c2')

    def test_archive_links_module_documents_by_identity_and_keeps_alternatives_in_history(self):
        entries = [{'team_id': self.team.pk, 'project_version': self.team.project_version,
            'type': 'pit', 'stage': self.event.label, 'academic_year': self.semester.school_year.label,
            'semester': self.semester.label, 'slot_key': key} for key in ('c1:paper', 'c2:paper', 'code')]
        attach_shared_team_context(entries)
        self.assertTrue(entries[0]['is_proposal_history'])
        self.assertFalse(entries[1]['is_proposal_history'])
        self.assertFalse(entries[2]['is_proposal_history'])
        self.assertEqual(entries[0]['section_project_id'], self.project.pk)
        unrelated = {**entries[0], 'project_version': self.team.project_version + 1}
        for field in ('section_project_id', 'section_round_id', 'shared_owner'):
            unrelated.pop(field)
        attach_shared_team_context([unrelated])
        self.assertNotIn('section_project_id', unrelated)
        self.assertEqual(shared_project_entries({'scope': 'pit_lead', 'pit_year_level': '4th Year'}), [])
        self.assertEqual(shared_project_entries({'scope': 'student'}), [])


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedStageNavigationTests(APITestCase):
    def test_stage_labels_follow_real_publication_and_required_file_clearance(self):
        from academic_period_management.models import SchoolYear, Semester
        from defense.stages.models import DefenseStage, StageDeliverable
        from grading.grades.models import TeamGrade
        from django.contrib.auth import get_user_model
        from student_teams.models import StudentTeam
        year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(school_year=year, label=Semester.SECOND, is_active=True)
        leader = get_user_model().objects.create_user(username='stage-navigation-student', role='student')
        team = StudentTeam.objects.create(name='Stage navigation team', semester=semester,
            year_level='3rd Year', level=StudentTeam.LEVEL_3_CAPSTONE, leader=leader)
        DefenseStage.objects.update(is_active=False)
        stages = [DefenseStage.objects.create(label=label, display_order=index, is_active=True)
            for index, label in enumerate(('Navigation Concept', 'Navigation Proposal', 'Navigation Final'), 1)]
        StageDeliverable.objects.create(defense_stage=stages[0], deliverable_id='OPTIONAL',
            label='Optional supporting document', deliverable_type='pre', required=False)
        StageDeliverable.objects.create(defense_stage=stages[0], deliverable_id='FINAL', label='Final paper',
            deliverable_type='post', required=True, file_format='pdf')
        self.assertEqual(shared.stage_navigation_states(team), {
            'Navigation Concept': 'current', 'Navigation Proposal': 'upcoming', 'Navigation Final': 'upcoming'})
        from repository.deliverables.models import DeliverableSubmission
        paper = DeliverableSubmission.objects.create(team=team, stage_label=stages[0].label,
            deliverable_id='FINAL', label='Final paper', deliverable_type='post',
            status='accepted', file_name='final.pdf', uploaded_by=leader)
        TeamGrade.objects.create(team=team, semester=semester, defense_stage=stages[0], scope='capstone',
            stage_label=stages[0].label, status='published', panel_weight=100, adviser_weight=0, peer_weight=0,
            panel_score=80, adviser_score=0, peer_score=0, final_grade=80, verdict='approved')
        self.assertEqual(shared.stage_navigation_states(team), {
            'Navigation Concept': 'complete', 'Navigation Proposal': 'current', 'Navigation Final': 'upcoming'})
        DeliverableSubmission.objects.filter(pk=paper.pk).update(status='rejected')
        self.assertEqual(shared.stage_navigation_states(team)['Navigation Concept'], 'current')
