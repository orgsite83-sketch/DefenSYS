"""Exercise the standalone uploader against real API views in the test DB."""
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from urllib.parse import urlencode, urlsplit
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APIClient, APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventGradingConfig, PitEventDeliverable
from defense.stages.models import DefenseStage, StageDeliverable
from student_teams.models import StudentTeam, TeamMembership
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
from execution.upload_deliverables import ApiClient, StudentLeaderBatch, UploadError, prepare_plan, run_plan, main, batch_stage


class _ApiSession:
    """Adapt requests' multipart interface to Django's in-process test client."""
    def __init__(self, actor=None):
        self.client = APIClient()
        self.headers = {}
        if actor is not None:
            self.client.force_authenticate(actor)
        self.posts = 0

    def close(self):
        pass

    def request(self, method, url, *, params=None, data=None, files=None, **_kwargs):
        path = urlsplit(url).path
        if params:
            path += '?' + urlencode(params)
        authorization = {'HTTP_AUTHORIZATION': self.headers['Authorization']} if self.headers.get('Authorization') else {}
        if method == 'GET':
            return self.client.get(path, **authorization)
        if method != 'POST' or not files:
            raise AssertionError('Unexpected uploader operation')
        self.posts += 1
        name, stream, content_type = files['file']
        return self.client.post(path, {**data, 'file': SimpleUploadedFile(
            name, stream.read(), content_type=content_type)}, format='multipart', **authorization)


class UploadAutomationApiTests(APITestCase):
    def setUp(self):
        temporary_root = REPO_ROOT / '.tmp'
        temporary_root.mkdir(exist_ok=True)
        directory = TemporaryDirectory(dir=temporary_root)
        self.addCleanup(directory.cleanup)
        self.files = Path(directory.name) / 'files'
        self.files.mkdir()
        settings = override_settings(MEDIA_ROOT=str(Path(directory.name) / 'media'))
        settings.enable()
        self.addCleanup(settings.disable)
        extraction = patch('repository.deliverables.pdf_processor.extract_pdf_from_file_object',
                           return_value={'text': 'Upload automation test document'})
        extraction.start()
        self.addCleanup(extraction.stop)
        users = get_user_model()
        self.admin = users.objects.create_user(username='upload-runner-admin', role='admin')
        self.student = users.objects.create_user(username='upload-runner-student', role='student')
        self.adviser = users.objects.create_user(username='upload-runner-adviser', role='faculty', is_adviser=True)
        year = SchoolYear.objects.create(label='2038-2039')
        self.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        self.stage, _ = DefenseStage.objects.get_or_create(label='Concept Proposal', defaults={'display_order': 1})
        self.stage.is_active = True
        self.stage.concept_config = {}
        self.stage.save()
        self.stage.deliverables.all().delete()
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='PAPER', label='Proposal paper',
                                        file_format='pdf', required=True)
        self.capstone = StudentTeam.objects.create(name='Upload Capstone', project_title='Uploader check',
            leader=self.student, adviser=self.adviser, semester=self.semester, year_level='3rd Year',
            level=StudentTeam.LEVEL_3_CAPSTONE, status=StudentTeam.STATUS_APPROVED)
        TeamMembership.objects.create(team=self.capstone, student=self.student, is_leader=True)
        self.event = PitEventGradingConfig.objects.create(semester=self.semester, year_level='1st Year',
            event_name='Upload PIT Exhibit')
        PitEventDeliverable.objects.create(pit_event_config=self.event, deliverable_id='DOCS', label='Event documents',
            file_format='pdf', required=True, file_policy={'mode': 'named', 'slots': [
                {'key': 'paper', 'label': 'Paper', 'file_format': 'pdf', 'required': True},
                {'key': 'notes', 'label': 'Notes', 'file_format': 'pdf', 'required': True}]})
        self.pit = StudentTeam.objects.create(name='Upload PIT', project_title='Event uploader check',
            leader=self.student, semester=self.semester, year_level='1st Year', level=StudentTeam.LEVEL_1_PIT,
            status=StudentTeam.STATUS_APPROVED)
        TeamMembership.objects.create(team=self.pit, student=self.student, is_leader=True)

    def write(self, relative):
        path = self.files / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'%PDF-1.4\nAutomated uploader test fixture\n%%EOF')

    def api(self, actor):
        session = _ApiSession(actor)
        return ApiClient('http://testserver', session=session), session

    def test_capstone_preview_upload_and_rerun_preserve_file_bytes(self):
        self.write(f'{self.capstone.pk}/PAPER.pdf')
        client, session = self.api(self.admin)
        plan = prepare_plan(client, scope='capstone', stage=self.stage.label,
            files_root=self.files, team_ids=[self.capstone.pk])
        with redirect_stdout(StringIO()):
            self.assertEqual(run_plan(client, plan), 0)
        self.assertFalse(DeliverableSubmission.objects.exists())
        self.assertEqual(session.posts, 0)
        with redirect_stdout(StringIO()):
            self.assertEqual(run_plan(client, plan, apply=True), 0)
            self.assertEqual(run_plan(client, plan, apply=True), 0)
        self.assertEqual(session.posts, 1)
        self.assertEqual(DeliverableSubmissionFile.objects.count(), 1)
        submission = DeliverableSubmission.objects.get(team=self.capstone)
        self.assertEqual(Path(submission.file.path).read_bytes(), (self.files / plan['items'][0]['file']).read_bytes())
        self.assertEqual(submission.uploaded_by_id, self.admin.pk)

    def test_pit_grouped_uploads_use_real_slots_and_event_scope(self):
        for name in ['paper', 'notes']:
            self.write(f'{self.pit.pk}/DOCS/{name}.pdf')
        client, session = self.api(self.student)
        plan = prepare_plan(client, scope='pit', stage=self.event.event_name,
            files_root=self.files, team_ids=[self.pit.pk])
        with redirect_stdout(StringIO()):
            self.assertEqual(run_plan(client, plan, apply=True), 0)
            self.assertEqual(run_plan(client, plan, apply=True), 0)
        self.assertEqual(session.posts, 2)
        submission = DeliverableSubmission.objects.get(team=self.pit)
        self.assertEqual(submission.pit_event_config_id, self.event.pk)
        self.assertEqual(set(submission.files.values_list('slot_key', flat=True)), {'paper', 'notes'})
        self.assertEqual(submission.files.count(), 2)
        self.assertEqual(submission.uploaded_by_id, self.student.pk)

    def test_review_authority_does_not_grant_upload_permission(self):
        self.write(f'{self.capstone.pk}/PAPER.pdf')
        client, _ = self.api(self.admin)
        plan = prepare_plan(client, scope='capstone', stage=self.stage.label,
            files_root=self.files, team_ids=[self.capstone.pk])
        adviser_client, session = self.api(self.adviser)
        with redirect_stdout(StringIO()):
            self.assertEqual(run_plan(adviser_client, plan, apply=True), 2)
        self.assertEqual(session.posts, 0)
        self.assertFalse(DeliverableSubmission.objects.exists())

    def test_one_student_batch_uploads_distinct_team_files_with_real_student_attribution(self):
        second_leader = get_user_model().objects.create_user(username='upload-second-leader', role='student')
        second = StudentTeam.objects.create(name='Second upload PIT', project_title='A distinct project',
            leader=second_leader, semester=self.semester, year_level='1st Year', level=StudentTeam.LEVEL_1_PIT,
            status=StudentTeam.STATUS_APPROVED)
        TeamMembership.objects.create(team=second, student=second_leader, is_leader=True)
        original_credentials = dict(get_user_model().objects.values_list('pk', 'password'))
        from rest_framework_simplejwt.token_blacklist.models import OutstandingToken
        tokens_before = OutstandingToken.objects.count()
        expected = {}
        for selected in [self.pit, second]:
            for slot in ['paper', 'notes']:
                name = f'{selected.pk}__DOCS__{slot}.pdf'
                content = f'%PDF-1.4\n{selected.project_title}: {slot}\n%%EOF'.encode()
                (self.files / name).write_bytes(content)
                expected[(selected.pk, slot)] = content
        sessions = []
        def new_session():
            session = _ApiSession()
            sessions.append(session)
            return session
        with patch('execution.upload_deliverables.requests.Session', side_effect=new_session):
            batch = StudentLeaderBatch('http://testserver')
            self.addCleanup(batch.close)
            plan = prepare_plan(batch, scope='pit', stage=self.event.event_name,
                                files_root=self.files, all_teams=True)
            self.assertEqual(plan['upload_as'], 'student_leaders')
            self.assertEqual(set(plan['uploaders']), {str(self.pit.pk), str(second.pk)})
            with redirect_stdout(StringIO()):
                self.assertEqual(run_plan(batch, plan), 0)
            self.assertFalse(DeliverableSubmission.objects.exists())
            with redirect_stdout(StringIO()):
                self.assertEqual(run_plan(batch, plan, apply=True), 0)
                self.assertEqual(run_plan(batch, plan, apply=True), 0)
        self.assertEqual(sum(session.posts for session in sessions), 4)
        for selected in [self.pit, second]:
            submission = DeliverableSubmission.objects.get(team=selected)
            self.assertEqual(submission.uploaded_by_id, selected.leader_id)
            for file in submission.files.all():
                self.assertEqual(Path(file.file.path).read_bytes(), expected[(selected.pk, file.slot_key)])
        self.assertEqual(dict(get_user_model().objects.values_list('pk', 'password')), original_credentials)
        self.assertEqual(OutstandingToken.objects.count(), tokens_before)

    def test_student_discovery_requires_an_active_member_leader(self):
        TeamMembership.objects.filter(team=self.pit, student=self.student).delete()
        batch = StudentLeaderBatch('http://testserver', team_ids=[self.pit.pk])
        self.addCleanup(batch.close)
        with self.assertRaisesRegex(UploadError, 'student leader'):
            prepare_plan(batch, scope='pit', stage=self.event.event_name,
                         files_root=self.files, team_ids=[self.pit.pk])

    def test_team_filename_batch_uploads_only_selected_document_as_each_student_leader(self):
        self.pit.name = 'Team Upload PIT'
        self.pit.save(update_fields=['name'])
        second_leader = get_user_model().objects.create_user(username='flat-upload-leader', role='student')
        second = StudentTeam.objects.create(name='AlphaWave', project_title='Another project',
            leader=second_leader, semester=self.semester, year_level='1st Year', level=StudentTeam.LEVEL_1_PIT,
            status=StudentTeam.STATUS_APPROVED)
        TeamMembership.objects.create(team=second, student=second_leader, is_leader=True)
        PitEventDeliverable.objects.create(pit_event_config=self.event, deliverable_id='SLIDES',
            label='Pitch Deck', file_format='pdf', required=True)
        expected = {}
        for selected, filename in [(self.pit, 'Upload_PIT_Any_filename.pdf'),
                                   (second, 'AlphaWave_Concept_Paper.pdf')]:
            content = f'%PDF-1.4\n{selected.name} unique document\n%%EOF'.encode()
            (self.files / filename).write_bytes(content)
            expected[selected.pk] = content
        with patch('execution.upload_deliverables.requests.Session', side_effect=_ApiSession):
            batch = StudentLeaderBatch('http://testserver')
            self.addCleanup(batch.close)
            plan = prepare_plan(batch, scope='pit', stage=self.event.event_name,
                files_root=self.files, all_teams=True, deliverable='Event documents', slot='Paper')
            self.assertEqual(len(plan['items']), 2)
            self.assertEqual({(item['deliverable_id'], item['slot_key']) for item in plan['items']},
                             {('DOCS', 'paper')})
            with redirect_stdout(StringIO()):
                self.assertEqual(run_plan(batch, plan), 0)
            self.assertFalse(DeliverableSubmission.objects.exists())
            with redirect_stdout(StringIO()):
                self.assertEqual(run_plan(batch, plan, apply=True), 0)
                self.assertEqual(run_plan(batch, plan, apply=True), 0)
        self.assertEqual(DeliverableSubmission.objects.count(), 2)
        self.assertEqual(DeliverableSubmissionFile.objects.count(), 2)
        for selected in [self.pit, second]:
            saved = DeliverableSubmission.objects.get(team=selected, deliverable_id='DOCS')
            self.assertEqual(saved.uploaded_by_id, selected.leader_id)
            self.assertEqual(saved.files.get().slot_key, 'paper')
            self.assertEqual(Path(saved.files.get().file.path).read_bytes(), expected[selected.pk])

    def test_simple_command_uploads_all_pre_documents_and_excludes_post(self):
        PitEventDeliverable.objects.create(pit_event_config=self.event, deliverable_id='DECK',
            label='Pitch Deck', file_format='presentation', required=True)
        PitEventDeliverable.objects.create(pit_event_config=self.event, deliverable_id='FINAL',
            label='Final Paper', deliverable_type='post', file_format='pdf', required=True)
        for filename in ['DOCS/paper/Upload_PIT_Anything.pdf', 'DOCS/notes/Upload_PIT_Notes.pdf',
                         'Pitch Deck/01_Upload_PIT_Pitch.pptx', 'FINAL/Upload_PIT_Final.pdf']:
            self.write(filename)
        arguments = ['--all-teams', '--year', '1', '--files', str(self.files)]
        with patch('execution.upload_deliverables.requests.Session', side_effect=_ApiSession), redirect_stdout(StringIO()):
            self.assertEqual(main(arguments + ['--dry-run']), 0)
            self.assertFalse(DeliverableSubmission.objects.exists())
            self.assertEqual(main(arguments), 0)
            self.assertEqual(main(arguments), 0)
        self.assertEqual(set(DeliverableSubmission.objects.values_list('deliverable_id', flat=True)), {'DOCS', 'DECK'})
        self.assertEqual(DeliverableSubmissionFile.objects.count(), 3)
        for saved in DeliverableSubmission.objects.all():
            self.assertEqual(saved.uploaded_by_id, self.student.pk)

    def test_simple_command_requires_stage_when_year_has_multiple_events(self):
        self.assertEqual(batch_stage('pit', '1st Year', None), self.event.event_name)
        PitEventGradingConfig.objects.create(semester=self.semester, year_level='1st Year', event_name='Another exhibit')
        with self.assertRaisesRegex(UploadError, '--stage explicitly'):
            batch_stage('pit', '1st Year', None)

    def test_capstone_student_batch_uploads_under_leader_and_blocks_changed_leader(self):
        (self.files / f'{self.capstone.pk}__PAPER.pdf').write_bytes(b'%PDF-1.4\nCapstone-specific paper')
        with patch('execution.upload_deliverables.requests.Session', side_effect=_ApiSession):
            batch = StudentLeaderBatch('http://testserver', team_ids=[self.capstone.pk])
            self.addCleanup(batch.close)
            plan = prepare_plan(batch, scope='capstone', stage=self.stage.label,
                                files_root=self.files, team_ids=[self.capstone.pk])
            with redirect_stdout(StringIO()):
                self.assertEqual(run_plan(batch, plan, apply=True), 0)
            self.assertEqual(DeliverableSubmission.objects.get(team=self.capstone).uploaded_by_id, self.student.pk)
            new_leader = get_user_model().objects.create_user(username='upload-new-leader', role='student')
            TeamMembership.objects.create(team=self.capstone, student=new_leader)
            self.capstone.leader = new_leader
            self.capstone.save(update_fields=['leader'])
            with redirect_stdout(StringIO()):
                self.assertEqual(run_plan(batch, plan, apply=True), 2)
            self.assertEqual(DeliverableSubmission.objects.get(team=self.capstone).files.count(), 1)

    def test_named_team_folders_upload_without_ids_in_filenames(self):
        self.write(f'{self.capstone.name}/Proposal paper.pdf')
        client, _ = self.api(self.student)
        plan = prepare_plan(client, scope='capstone', stage=self.stage.label,
                            files_root=self.files, team_ids=[self.capstone.pk])
        self.assertEqual(plan['items'][0]['file'], f'{self.capstone.name}/Proposal paper.pdf')
        with redirect_stdout(StringIO()):
            self.assertEqual(run_plan(client, plan, apply=True), 0)
        saved = DeliverableSubmission.objects.get(team=self.capstone)
        self.assertEqual(saved.file_name, 'Proposal paper.pdf')
        self.assertEqual(saved.uploaded_by_id, self.student.pk)

    def test_post_upload_uses_server_archive_name_and_preserves_local_file(self):
        from repository.deliverables.stage_access import set_access
        post = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='FINAL',
            label='Final manuscript', deliverable_type='post', file_format='pdf',
            archive_file_template='{year}_{project}_{deliverable}_{semester}.pdf')
        set_access(self.admin, scope='team', program_scope='capstone', team=self.capstone,
            stage_label=self.stage.label, unlock_type='post', target_state=True, reason='Test post upload window.')
        original = self.files / self.capstone.name / 'Final manuscript' / 'Our final submission.pdf'
        original.parent.mkdir(parents=True)
        content = b'%PDF-1.4\nUnique Capstone final manuscript'
        original.write_bytes(content)
        client, _ = self.api(self.student)
        plan = prepare_plan(client, scope='capstone', stage=self.stage.label,
                            files_root=self.files, team_ids=[self.capstone.pk], timing='post')
        recommendation = plan['items'][0]['suggested_file_name']
        self.assertTrue(recommendation.endswith('.pdf'))
        with redirect_stdout(StringIO()):
            self.assertEqual(run_plan(client, plan, apply=True), 0)
        saved = DeliverableSubmission.objects.get(team=self.capstone, deliverable_id=post.deliverable_id)
        self.assertEqual(saved.file_name, recommendation)
        self.assertEqual(saved.uploaded_by_id, self.student.pk)
        self.assertEqual(Path(saved.file.path).read_bytes(), content)
        self.assertEqual(original.read_bytes(), content)
        self.assertEqual(original.name, 'Our final submission.pdf')

    def test_existing_api_preserves_the_caller_provided_filename(self):
        from repository.deliverables.stage_access import set_access
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='ARCHIVE',
            label='Source code', deliverable_type='post', file_format='archive',
            archive_file_template='{year}_{project}_{deliverable}.pdf')
        set_access(self.admin, scope='team', program_scope='capstone', team=self.capstone,
            stage_label=self.stage.label, unlock_type='post', target_state=True, reason='Test source code upload.')
        api = APIClient()
        api.force_authenticate(self.student)
        fields = {'team_id': self.capstone.pk, 'stage_label': self.stage.label,
                  'deliverable_id': 'ARCHIVE', 'file_name': 'my-source.zip'}
        response = api.post('/api/repository/deliverables/upload/', {
            **fields, 'file': SimpleUploadedFile('my-source.zip', b'source zip bytes')}, format='multipart')
        self.assertEqual(response.status_code, 200, response.data)
        saved = DeliverableSubmission.objects.get(team=self.capstone, deliverable_id='ARCHIVE')
        self.assertEqual(saved.file_name, 'my-source.zip')
        self.assertEqual(saved.files.count(), 1)

    def test_post_script_renaming_preserves_document_slots_and_unique_names(self):
        from repository.deliverables.stage_access import set_access
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='POSTDOCS',
            label='Final documents', deliverable_type='post', file_format='pdf',
            archive_file_template='{project}_{deliverable}.pdf', file_policy={'mode': 'named', 'slots': [
                {'key': 'paper', 'label': 'Paper', 'file_format': 'pdf', 'required': True},
                {'key': 'notes', 'label': 'Notes', 'file_format': 'pdf', 'required': True}]})
        set_access(self.admin, scope='team', program_scope='capstone', team=self.capstone,
            stage_label=self.stage.label, unlock_type='post', target_state=True, reason='Test post document group.')
        for label in ['Paper', 'Notes']:
            self.write(f'{self.capstone.name}/Final documents/{label}.pdf')
        client, _ = self.api(self.student)
        plan = prepare_plan(client, scope='capstone', stage=self.stage.label,
                            files_root=self.files, team_ids=[self.capstone.pk], timing='post')
        with redirect_stdout(StringIO()):
            self.assertEqual(run_plan(client, plan, apply=True), 0)
            self.assertEqual(run_plan(client, plan, apply=True), 0)
        saved = DeliverableSubmission.objects.get(team=self.capstone, deliverable_id='POSTDOCS')
        self.assertEqual(set(saved.files.values_list('slot_key', flat=True)), {'paper', 'notes'})
        self.assertEqual(saved.files.count(), 2)
        self.assertEqual(len(set(saved.files.values_list('file_name', flat=True))), 2)
        recommended_base = Path(plan['items'][0]['suggested_file_name']).stem
        self.assertTrue(all(name.startswith(recommended_base + '_')
                            for name in saved.files.values_list('file_name', flat=True)))

