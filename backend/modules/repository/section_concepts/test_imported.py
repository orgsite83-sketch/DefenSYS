from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from student_teams.models import SectionAssignment, StudentTeam, TeamMembership
from student_teams.concept_policy import context_key
from repository.deliverables import concepts
from repository.deliverables.models import ConceptRound
from repository.deliverables.services import upsert_submission
from repository.deliverables import test_submission_timing as timing_fixtures
from . import services
from .models import SectionConceptProject

URL = '/api/repository/section-concepts/imported/'


class ImportedSharedProposalTests(APITestCase):
    def setUp(self):
        timing_fixtures.SubmissionTimingTests.setUp(self)
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save()
        self.paper.file_policy = {'mode': 'concepts'}
        self.paper.save()
        self.team.section = 'BSIT-3A'
        self.team.concept_assignment = {'mode': 'proposals', 'project_version': 1,
            'context_key': context_key(self.stage), 'seed_title': 'Imported first module'}
        self.team.save()
        self.other_adviser = get_user_model().objects.create_user(username='second-section-adviser',
            first_name='Grace', last_name='Hopper', role='faculty', is_adviser=True)
        self.member = get_user_model().objects.create_user(username='other-module-leader', role='student')
        self.other = StudentTeam.objects.create(name='Second module team', level=self.team.level,
            year_level=self.team.year_level, section=self.team.section, semester=self.semester,
            adviser=self.other_adviser, leader=self.member)
        TeamMembership.objects.create(team=self.other, student=self.member, is_leader=True)
        self.assignment = SectionAssignment.objects.create(semester=self.semester, section=self.team.section,
            year_level=self.team.year_level, system_name='Imported shared architecture', project_manager=self.student)
        self.client.force_authenticate(self.student)

    def load(self):
        response = self.client.get(URL, {'team_id': self.team.pk, 'stage_label': self.stage.label})
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def save(self, state, **values):
        return self.client.post(URL, {'team_id': self.team.pk, 'stage_label': self.stage.label,
            'review_token': state['review_token'], **values}, format='json')

    def titles(self, count=3):
        return [{'key': f'c{i}', 'title': 'Imported shared architecture' if i == 1 else f'Alternative system {i}'}
            for i in range(1, count + 1)]

    def test_import_preview_shows_system_a_pm_both_advisers_and_upload_without_creating_work(self):
        state = self.load()
        self.assertEqual([s['title'] for s in state['systems']], ['Imported shared architecture', '', ''])
        self.assertEqual(state['project_manager_id'], self.student.pk)
        self.assertEqual({r['id'] for r in state['reviewers']}, {self.adviser.pk, self.other_adviser.pk})
        self.assertTrue(state['can_edit_names'])
        self.assertEqual([s['can_upload'] for s in state['systems']], [True, False, False])
        self.assertEqual(state['selected_key'], '')
        self.assertFalse(SectionConceptProject.objects.exists())
        self.assertFalse(ConceptRound.objects.exists())
        self.assertIn('Project Manager', services.module_blocker(self.team, self.stage, None))
        summary = concepts.summary(self.team, self.stage)
        self.assertTrue(summary['shared_import_pending'])
        self.assertEqual([s['title'] for s in summary['system_concepts']], ['Imported shared architecture', '', ''])
        self.assertEqual([c['title'] for c in summary['concepts']], ['Imported first module', '', ''])
        workflow = concepts.payload(self.team, self.stage, actor=self.student)
        self.assertTrue(workflow['shared_import_pending'])
        self.assertEqual(workflow['concepts'][0]['system_title'], 'Imported shared architecture')
        self.assertEqual(workflow['concepts'][1]['system_title'], '')
        self.assertEqual(len(workflow['system_concepts']), 3)
        self.assertFalse(SectionConceptProject.objects.exists())

    def test_pm_save_uses_configured_count_and_keeps_existing_module_titles_and_files(self):
        current = concepts.save_titles(self.team, self.stage, [
            {'key': 'c1', 'title': 'Imported first module'}, {'key': 'c2', 'title': 'Second draft'},
            {'key': 'c3', 'title': ''}], actor=self.student, draft=True)
        sub = upsert_submission(self.team, self.stage.label, 'PAPER', 'module.pdf', '10 B', self.student,
            file=SimpleUploadedFile('module.pdf', b'%PDF-1.4 original module'), slot_key='c1:paper')
        file = sub.files.get(is_current=True)
        result = self.save(self.load(), concepts=self.titles())
        self.assertEqual(result.status_code, 201, result.data)
        current.refresh_from_db()
        file.refresh_from_db()
        self.assertTrue(current.section_round_id)
        self.assertEqual([c['title'] for c in current.concepts], ['Imported first module', 'Second draft', ''])
        self.assertTrue(file.is_current)
        self.assertTrue(file.file.storage.exists(file.file.name))
        self.assertEqual(services.policy_for(self.team, self.stage)['required_count'], 3)
        self.assertEqual([s['title'] for s in result.data['systems']], [t['title'] for t in self.titles()])
        self.assertEqual(len(result.data['teams']), 2)

    def test_import_preview_includes_each_team_roster_before_shared_setup(self):
        teammate = get_user_model().objects.create_user(username='module-teammate',
            first_name='Maya', last_name='Santos', role='student')
        TeamMembership.objects.create(team=self.team, student=teammate)
        expected = {
            self.team.pk: [
                {'id': self.student.pk, 'name': self.student.username, 'is_leader': True},
                {'id': teammate.pk, 'name': 'Maya Santos', 'is_leader': False},
            ],
            self.other.pk: [
                {'id': self.member.pk, 'name': self.member.username, 'is_leader': True},
            ],
        }
        state = self.load()
        for team in state['teams']:
            self.assertCountEqual(team['members'], expected[team['id']])
        self.assertFalse(SectionConceptProject.objects.exists())
        self.assertFalse(ConceptRound.objects.exists())
        opened = self.save(state)
        self.assertEqual(opened.status_code, 201, opened.data)
        for team in opened.data['teams']:
            self.assertCountEqual(team['members'], expected[team['id']])

    def test_pm_can_open_and_upload_system_a_before_proposing_b_and_c(self):
        opened = self.save(self.load())
        self.assertEqual(opened.status_code, 201, opened.data)
        self.assertEqual([s['title'] for s in opened.data['systems']], ['Imported shared architecture', '', ''])
        project = SectionConceptProject.objects.get()
        uploaded = self.client.post(f'/api/repository/section-concepts/{project.pk}/upload/', {
            'round_id': opened.data['round_id'], 'key': 'c1',
            'file': SimpleUploadedFile('system-a.pdf', b'%PDF-1.4 shared system')}, format='multipart')
        self.assertEqual(uploaded.status_code, 201, uploaded.data)
        self.assertEqual(uploaded.data['systems'][0]['papers'][0]['file_name'], 'system-a.pdf')
        self.assertFalse(uploaded.data['cleared'])

    def test_both_section_advisers_can_review_shared_papers_but_other_faculty_cannot(self):
        self.assertEqual(self.save(self.load(), concepts=self.titles()).status_code, 201)
        project = SectionConceptProject.objects.get()
        paper = services.upload(project, self.student, 'c1', SimpleUploadedFile('shared.pdf', b'%PDF-1.4 shared'))
        for actor in (self.adviser, self.other_adviser):
            state = services.payload(project, actor)
            self.assertTrue(state['can_review'])
            self.assertTrue(state['can_edit_names'])
            self.client.force_authenticate(actor)
            reviewed = self.client.post(f'/api/repository/section-concepts/{project.pk}/', {
                'action': 'review', 'round_id': state['round_id'], 'review_token': state['review_token'],
                'paper_id': paper.pk, 'status': 'accepted'}, format='json')
            self.assertEqual(reviewed.status_code, 200, reviewed.data)
        outsider = get_user_model().objects.create_user(username='unassigned-shared-faculty', role='faculty')
        self.assertFalse(services.is_reviewer(outsider, project))
        with self.assertRaises(PermissionError):
            services.review(project, outsider, paper.pk, 'accepted')

    def test_only_assigned_pm_can_initialize_and_stale_or_incomplete_names_roll_back(self):
        state = self.load()
        self.client.force_authenticate(self.member)
        self.assertIn(self.save(state, concepts=self.titles()).status_code, (403, 404))
        self.client.force_authenticate(self.student)
        self.assertEqual(self.save(state, concepts=[{'key': 'c1', 'title': 'Only one'}]).status_code, 400)
        self.assertFalse(SectionConceptProject.objects.exists())
        self.assignment.system_name = 'New imported name'
        self.assignment.save()
        self.assertEqual(self.save(state, concepts=self.titles()).status_code, 400)
        self.assertFalse(SectionConceptProject.objects.exists())

    def test_captured_or_endorsed_module_work_requires_staff_review(self):
        current = concepts.get_round(self.team, self.stage)
        current.verdict = 'approved'
        current.save()
        state = self.load()
        self.assertFalse(state['can_edit_names'])
        self.assertFalse(state['systems'][0]['can_upload'])
        self.assertEqual(self.save(state, concepts=self.titles()).status_code, 403)
        self.assertFalse(SectionConceptProject.objects.exists())

    def test_four_configured_systems_leave_three_for_pm(self):
        self.stage.concept_config['required_count'] = 4
        self.stage.save()
        state = self.load()
        self.assertEqual([s['title'] for s in state['systems']], ['Imported shared architecture', '', '', ''])
        result = self.save(state, concepts=self.titles(4))
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(len(result.data['systems']), 4)

    def test_ordinary_section_member_can_read_but_cannot_edit_or_upload_shared_systems(self):
        self.client.force_authenticate(self.member)
        response = self.client.get(URL, {'team_id': self.other.pk, 'stage_label': self.stage.label})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['can_edit_names'])
        self.assertFalse(any(s['can_upload'] for s in response.data['systems']))
        result = self.client.post(URL, {'team_id': self.other.pk, 'stage_label': self.stage.label,
            'review_token': response.data['review_token']}, format='json')
        self.assertEqual(result.status_code, 403)

    def test_import_does_not_seed_or_block_an_unrelated_concept_context(self):
        from defense.stages.models import DefenseStage
        other = DefenseStage.objects.create(label='Another concept hearing', display_order=50,
            concept_config={'enabled': True, 'required_count': 3})
        response = self.client.get(URL, {'team_id': self.team.pk, 'stage_label': other.label})
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(services.module_blocker(self.team, other, None), '')

    def test_completed_context_is_read_only_and_initialization_creates_nothing(self):
        from defense.stages.models import StageGradingConfig
        StageGradingConfig.objects.update_or_create(defense_stage=self.stage, semester=self.semester,
            defaults={'is_officially_complete': True})
        state = self.load()
        self.assertFalse(state['can_edit_names'])
        self.assertEqual(self.save(state).status_code, 403)
        self.assertFalse(SectionConceptProject.objects.exists())
