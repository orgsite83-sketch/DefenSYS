"""Real semester activation, existing-continuation reads and shared-file access."""
from copy import deepcopy
import tempfile

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from student_teams.models import SectionAssignment, TeamTermParticipation
from student_teams import test_continuation_sections as fixtures
from . import services, shared_deliverables as shared
from .continuation import approved_source
from .models import (SectionConceptProject, SectionConceptRound, SectionProjectTeam,
    SectionSystemConcept, SectionConceptPaper, SharedDeliverableSet, SharedDeliverableFile)


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedSystemContinuationTests(APITestCase):
    assess = fixtures.ContinuationSectionTests.assess
    migrate = fixtures.ContinuationSectionTests.migrate
    transition_preview = fixtures.ContinuationSectionTests.transition_preview

    def setUp(self):
        fixtures.ContinuationSectionTests.setUp(self)
        media = tempfile.TemporaryDirectory()
        self.addCleanup(media.cleanup)
        setting = self.settings(MEDIA_ROOT=media.name)
        setting.enable()
        self.addCleanup(setting.disable)
        self.assignment = SectionAssignment.objects.create(semester=self.source,
            section=self.team.section, year_level=self.team.year_level,
            system_name='Original imported title', project_manager=self.student)
        self.project = SectionConceptProject.objects.create(section=self.assignment,
            defense_stage=self.stage, project_manager=self.student, reviewer=self.adviser)
        SectionProjectTeam.objects.create(project=self.project, team=self.team, project_version=1)
        self.hearing = SectionConceptRound.objects.create(project=self.project,
            selected_key='c1', verdict='approved')
        self.system = SectionSystemConcept.objects.create(round=self.hearing,
            key='c1', title='Approved continuing system', confirmed=True)
        SectionSystemConcept.objects.create(round=self.hearing,
            key='c2', title='Unselected alternative', confirmed=True)
        self.paper = SectionConceptPaper.objects.create(concept=self.system, purpose='final',
            file=SimpleUploadedFile('source.pdf', b'%PDF-1.4 source system'),
            file_name='source.pdf', uploaded_by=self.student, status='accepted')
        from defense.stages.models import DefenseStage
        self.final = DefenseStage.objects.get(label='Section test final')
        self.final.shared_deliverables = [{'deliverable_id': 'SYS', 'label': 'Current system paper',
            'deliverable_type': 'pre', 'required': True, 'file_format': 'pdf',
            'file_policy': {'mode': 'single'}}]
        self.final.save(update_fields=['shared_deliverables'])
        self.assess()

    def state(self, actor=None):
        return shared.payload(shared.resolve(self.team, self.final), actor or self.student)

    def legacy_continuation(self):
        self.migrate()
        SectionAssignment.objects.get(semester=self.target, section='BSIT-4A').delete()

    def test_activation_carries_system_without_copying_or_reopening_completed_stage(self):
        self.migrate()
        section = SectionAssignment.objects.get(semester=self.target, section='BSIT-4A')
        self.assertEqual(section.system_name, self.system.title)
        self.assertEqual(section.project_manager_id, self.student.pk)
        self.assignment.refresh_from_db()
        self.project.refresh_from_db()
        self.hearing.refresh_from_db()
        self.assertEqual((self.assignment.semester_id, self.assignment.section), (self.source.pk, 'BSIT-3A'))
        self.assertEqual(self.project.section_id, self.assignment.pk)
        self.assertEqual(self.hearing.verdict, 'approved')
        self.assertEqual(SectionConceptProject.objects.count(), 1)
        self.assertEqual(SectionConceptRound.objects.count(), 1)
        self.assertEqual(SectionConceptPaper.objects.count(), 1)
        self.assertEqual(SharedDeliverableSet.objects.count(), 0)
        self.assertEqual(self.state()['systems'], [{'key': 'c1', 'title': self.system.title}])
        self.assertTrue(self.state()['continued'])
        self.assertEqual([group['stage_label'] for group in shared.groups_for_team(self.team, self.student)],
            [self.final.label])
        historical = shared.resolve(self.team, self.stage)
        self.assertTrue(historical['historical'])
        self.assertEqual(historical['section'].semester_id, self.source.pk)
        with self.assertRaises(PermissionError):
            shared.ensure_editable(historical, {'deliverable_type': 'pre'})

    def test_existing_continuation_reads_restore_dashboard_and_workspace_without_writes(self):
        self.legacy_continuation()
        before = (SectionAssignment.objects.count(), SectionConceptRound.objects.count(),
            SharedDeliverableSet.objects.count(), SharedDeliverableFile.objects.count())
        self.client.force_authenticate(self.member)
        dashboard = self.client.get('/api/dashboards/student/')
        self.assertEqual(dashboard.status_code, 200, dashboard.data)
        self.assertEqual(dashboard.data['team']['system_name'], self.system.title)
        teams = self.client.get('/api/teams/')
        self.assertEqual(teams.status_code, 200, teams.data)
        detail = self.client.get(f'/api/repository/section-concepts/{self.project.pk}/',
            {'team_id': self.team.pk})
        self.assertEqual(detail.status_code, 200, detail.data)
        self.assertTrue(detail.data['historical'])
        self.assertFalse(detail.data['editable'])
        self.assertEqual([group['stage_label'] for group in detail.data['shared_contexts']], [self.final.label])
        group = detail.data['shared_contexts'][0]
        self.assertEqual(group['semester_id'], self.target.pk)
        self.assertEqual(group['section'], 'BSIT-4A')
        self.assertIsNone(group['requirements'][0]['documents'][0]['file'])
        listing = self.client.get('/api/repository/section-concepts/', {'team_id': self.team.pk})
        self.assertEqual([p['id'] for p in listing.data['projects']], [self.project.pk])
        self.client.force_authenticate(self.admin)
        section = self.client.get(f'/api/teams/{self.team.pk}/section/')
        self.assertEqual(section.status_code, 200, section.data)
        self.assertEqual(section.data['system_name'], self.system.title)
        self.assertEqual(section.data['project_manager_id'], self.student.pk)
        self.assertEqual(before, (SectionAssignment.objects.count(), SectionConceptRound.objects.count(),
            SharedDeliverableSet.objects.count(), SharedDeliverableFile.objects.count()))

    def test_first_current_upload_materializes_missing_section_with_fresh_evidence(self):
        self.legacy_continuation()
        token = self.state()['review_token']
        state = shared.upload(self.team, self.final, self.student, 'SYS', 'primary',
            SimpleUploadedFile('current.pdf', b'%PDF-1.4 current paper'), token)
        self.assertEqual(state['requirements'][0]['files'][0]['file_name'], 'current.pdf')
        captured = SharedDeliverableSet.objects.get()
        self.assertEqual(captured.section.semester_id, self.target.pk)
        self.assertEqual(captured.defense_stage_id, self.final.pk)
        self.assertEqual(captured.source_round_id, self.hearing.pk)
        self.assertEqual(captured.source_project_id, self.project.pk)
        row = captured.files.get()
        self.assertTrue(shared.can_read_file(self.member, row))
        self.assertTrue(shared.can_read_file(self.adviser, row))
        self.assertFalse(shared.can_read_file(get_user_model().objects.create_user(
            username='unrelated-reader', role='student'), row))
        self.paper.refresh_from_db()
        self.assertEqual(self.paper.status, 'accepted')
        self.assertEqual(SectionConceptPaper.objects.count(), 1)

    def test_source_paper_remains_accessible_to_continuing_members_only(self):
        self.migrate()
        url = f'/api/repository/section-concepts/{self.project.pk}/papers/{self.paper.pk}/'
        for actor in (self.student, self.member, self.adviser):
            self.client.force_authenticate(actor)
            response = self.client.get(url)
            self.assertEqual(response.status_code, 200)
            self.assertIn(b'source system', b''.join(response.streaming_content))
        outsider = get_user_model().objects.create_user(username='outside-system', role='student')
        self.client.force_authenticate(outsider)
        self.assertEqual(self.client.get(url).status_code, 404)

    def test_unverified_transition_cannot_inherit_the_system(self):
        self.migrate()
        row = TeamTermParticipation.objects.get(team=self.team, semester=self.target)
        log = row.transition
        for key in ('applied_team_ids', 'capstone_review'):
            original = deepcopy(log.impact_snapshot)
            log.impact_snapshot[key] = [] if key == 'applied_team_ids' else {}
            log.save(update_fields=['impact_snapshot'])
            self.assertIsNone(approved_source(self.team))
            log.impact_snapshot = original
            log.save(update_fields=['impact_snapshot'])

    def test_changed_project_version_cannot_reuse_source_approval(self):
        self.migrate()
        self.team.project_version += 1
        self.team.save(update_fields=['project_version'])
        self.assertIsNone(approved_source(self.team))
        self.assertIsNone(shared.resolve(self.team, self.final))
        self.assertFalse(services.team_display(self.team)['system_name'])
        self.assertTrue(services.can_read(self.member, self.project))  # Recorded source history.

    def test_existing_destination_manager_is_preserved(self):
        destination = SectionAssignment.objects.create(semester=self.target, section='BSIT-4A',
            year_level='4th Year', system_name='Admin metadata', project_manager=self.member)
        self.migrate()
        destination.refresh_from_db()
        self.assertEqual(destination.system_name, 'Admin metadata')
        self.assertEqual(destination.project_manager_id, self.member.pk)
        self.assertEqual(self.state()['project_manager_id'], self.member.pk)
        self.assertEqual(self.state()['systems'][0]['title'], self.system.title)

    def test_pending_shared_revisions_do_not_restore_an_approved_system(self):
        self.migrate()
        self.hearing.verdict = 'approved_with_revisions'
        self.hearing.save(update_fields=['verdict'])
        self.assertIsNone(approved_source(self.team))

    def test_source_shared_files_keep_their_period_and_member_access_after_continuation(self):
        captured = SharedDeliverableSet.objects.create(section=self.assignment, defense_stage=self.stage,
            source_project=self.project, source_round=self.hearing, identity='original-source',
            team_snapshot=[{'id': self.team.pk, 'version': self.team.project_version}],
            system_snapshot=[{'key': 'c1', 'title': self.system.title}],
            project_manager=self.student)
        row = SharedDeliverableFile.objects.create(submission_set=captured,
            deliverable_id='ORIGINAL', slot_key='primary', revision=1,
            file=SimpleUploadedFile('source-shared.pdf', b'%PDF-1.4 source shared evidence'),
            file_name='source-shared.pdf', file_size=30, uploaded_by=self.student)
        self.migrate()
        self.assertTrue(shared.can_read_file(self.member, row))
        self.assertTrue(shared.can_read_file(self.adviser, row))
        self.assertIsNone(self.state()['requirements'][0]['documents'][0]['file'])
        captured.refresh_from_db()
        self.assertEqual(captured.section_id, self.assignment.pk)
        self.assertEqual(captured.defense_stage_id, self.stage.pk)

    def test_unrelated_same_named_section_and_project_do_not_grant_continuation(self):
        self.migrate()
        self.team.intake_semester = self.target
        self.team.save(update_fields=['intake_semester'])
        self.assertIsNone(approved_source(self.team))
        self.assertIsNone(shared.resolve(self.team, self.final))

    def test_stale_upload_does_not_materialize_any_destination_records(self):
        from django.core.exceptions import ValidationError
        self.legacy_continuation()
        before = (SectionAssignment.objects.count(), SharedDeliverableSet.objects.count())
        with self.assertRaises(ValidationError):
            shared.upload(self.team, self.final, self.student, 'SYS', 'primary',
                SimpleUploadedFile('current.pdf', b'%PDF-1.4 current paper'), 'stale')
        self.assertEqual(before, (SectionAssignment.objects.count(), SharedDeliverableSet.objects.count()))

