from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from rest_framework.test import APITestCase



from academic_period_management.models import SchoolYear, Semester

from defense.scheduler.models import DefenseSchedule

from defense.stages.models import DefenseStage, StageDeliverable

from repository.deliverables.services import endorse_team, remove_submission, upsert_submission

from student_teams.models import StudentTeam, TeamMembership, TeamStageProgress



from .deliverable_templates import SUGGESTED_DELIVERABLE_TEMPLATES

from .models import DeliverableSubmission





User = get_user_model()





def seed_stage_deliverables(stage, templates):

    for order, item in enumerate(templates, start=1):

        StageDeliverable.objects.create(

            defense_stage=stage,

            deliverable_id=item['id'],

            label=item['label'],

            deliverable_type=item['type'],

            required=item['required'],

            display_order=order,

            archive_note=item.get('archive_note', ''),

        )





class CapstoneDeliverablesApiTests(APITestCase):

    def setUp(self):

        self.admin = User.objects.create_user(

            username='admin-user',

            password='pass12345',

            role='admin',

            is_staff=True,

        )

        self.adviser = User.objects.create_user(

            username='adviser-1',

            password='pass12345',

            role='faculty',

            first_name='Ada',

            last_name='Lovelace',

            is_adviser=True,

        )

        self.other_adviser = User.objects.create_user(

            username='adviser-2',

            password='pass12345',

            role='faculty',

            is_adviser=True,

        )

        self.student = User.objects.create_user(

            username='2024-0001',

            password='pass12345',

            role='student',

        )

        self.other_student = User.objects.create_user(

            username='2024-0002',

            password='pass12345',

            role='student',

        )

        self.school_year = SchoolYear.objects.create(label='2026-2027')

        self.semester = Semester.objects.create(

            school_year=self.school_year,

            label=Semester.SECOND,

            is_active=True,

        )

        self.stage = DefenseStage.objects.get(label='Concept Proposal')

        StageDeliverable.objects.filter(defense_stage=self.stage).delete()

        seed_stage_deliverables(

            self.stage,

            SUGGESTED_DELIVERABLE_TEMPLATES['Concept Proposal'],

        )

        self.team = StudentTeam.objects.create(

            name='Team VaultSync',

            project_title='Cloud File Sync',

            level=StudentTeam.LEVEL_3_CAPSTONE,

            year_level='3rd Year',

            semester=self.semester,

            leader=self.student,

            adviser=self.adviser,

            status=StudentTeam.STATUS_PENDING,

        )

        self.other_team = StudentTeam.objects.create(

            name='Team Other',

            project_title='Another Capstone',

            level=StudentTeam.LEVEL_4_CAPSTONE,

            year_level='4th Year',

            semester=self.semester,

            leader=self.other_student,

            adviser=self.other_adviser,

            status=StudentTeam.STATUS_PENDING,

        )

        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)

        TeamMembership.objects.create(team=self.other_team, student=self.other_student, is_leader=True)

        self.client.force_authenticate(user=self.admin)



    def upload_payload(self, **overrides):

        payload = {

            'team_id': self.team.id,

            'stage_label': 'Concept Proposal',

            'deliverable_id': 'D1',

            'file_name': 'D1_acceptance.pdf',

            'file_size': '120 KB',

        }

        payload.update(overrides)

        return payload



    def test_admin_lists_capstone_deliverable_payload(self):

        response = self.client.get('/api/repository/deliverables/')



        self.assertEqual(response.status_code, 200)

        self.assertEqual(response.data['counts']['teams'], 2)

        self.assertEqual(response.data['stage_options'][0], 'Concept Proposal')

        self.assertEqual(response.data['teams'][0]['selected_stage']['required_total'], 6)


    def test_stage_options_follow_admin_configured_stages_only(self):

        DefenseStage.objects.all().delete()

        custom_stage = DefenseStage.objects.create(

            label='Concept Proposql',

            display_order=1,

            is_active=True,

        )

        seed_stage_deliverables(

            custom_stage,

            SUGGESTED_DELIVERABLE_TEMPLATES['Concept Proposal'],

        )


        response = self.client.get('/api/repository/deliverables/')


        self.assertEqual(response.status_code, 200)

        self.assertEqual(response.data['stage_options'], ['Concept Proposql'])

        self.assertEqual(response.data['selected_stage'], 'Concept Proposql')

        self.assertEqual(

            response.data['teams'][0]['selected_stage']['stage_label'],

            'Concept Proposql',

        )

        self.assertNotIn('Concept Proposal', response.data['stage_options'])



    def test_empty_stage_returns_no_deliverables(self):

        StageDeliverable.objects.filter(defense_stage=self.stage).delete()



        response = self.client.get('/api/repository/deliverables/')



        self.assertEqual(response.status_code, 200)

        stage_payload = response.data['teams'][0]['selected_stage']

        self.assertEqual(stage_payload['required_total'], 0)

        self.assertEqual(stage_payload['pre_total'], 0)

        self.assertEqual(stage_payload['deliverables'], [])

        self.assertFalse(stage_payload['deliverables_configured'])

        self.assertFalse(stage_payload['required_complete'])



    def test_endorse_blocked_when_stage_not_configured(self):

        StageDeliverable.objects.filter(defense_stage=self.stage).delete()



        response = self.client.post(

            '/api/repository/deliverables/endorse/',

            {'team_id': self.team.id, 'stage_label': 'Concept Proposal'},

            format='json',

        )



        self.assertEqual(response.status_code, 400)



    def test_upload_fails_when_deliverable_not_in_db(self):

        StageDeliverable.objects.filter(defense_stage=self.stage, deliverable_id='D1').delete()



        response = self.client.post(

            '/api/repository/deliverables/upload/',

            self.upload_payload(),

            format='json',

        )



        self.assertEqual(response.status_code, 400)



    def test_adviser_only_sees_assigned_capstone_teams(self):

        self.client.force_authenticate(user=self.adviser)



        response = self.client.get('/api/repository/deliverables/')



        self.assertEqual(response.status_code, 200)

        self.assertEqual(response.data['counts']['teams'], 1)

        self.assertEqual(response.data['teams'][0]['name'], 'Team VaultSync')



    def test_multipart_upload_with_pdf_file(self):

        pdf = SimpleUploadedFile(

            'D1_acceptance.pdf',

            b'%PDF-1.4 test content',

            content_type='application/pdf',

        )

        response = self.client.post(

            '/api/repository/deliverables/upload/',

            {

                'team_id': self.team.id,

                'stage_label': 'Concept Proposal',

                'deliverable_id': 'D1',

                'file_name': 'D1_acceptance.pdf',

                'file_size': '1 KB',

                'file': pdf,

            },

            format='multipart',

        )



        self.assertEqual(response.status_code, 200, getattr(response, 'data', response.content))

        submission = DeliverableSubmission.objects.get(deliverable_id='D1')

        self.assertTrue(submission.file.name)

        self.assertEqual(submission.file_name, 'D1_acceptance.pdf')



    def test_unknown_deliverable_returns_json_error_not_500(self):

        response = self.client.post(

            '/api/repository/deliverables/upload/',

            self.upload_payload(deliverable_id='UNKNOWN-ID'),

            format='json',

        )



        self.assertEqual(response.status_code, 400)

        self.assertTrue('detail' in response.data or 'deliverable_id' in response.data)



    def test_pit_team_rejected_for_capstone_stage_deliverable(self):
        pit_team = StudentTeam.objects.create(
            name='Team PIT Only',
            project_title='PIT Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.other_student,
        )

        with self.assertRaises(ValueError) as ctx:
            upsert_submission(
                pit_team,
                'Concept Proposal',
                'D1',
                'acceptance.pdf',
                '10 KB',
                self.admin,
            )

        self.assertIn('Deliverable does not exist', str(ctx.exception))



    def test_upload_replace_and_remove_deliverable(self):

        upload = self.client.post('/api/repository/deliverables/upload/', self.upload_payload(), format='json')

        replace = self.client.post(

            '/api/repository/deliverables/upload/',

            self.upload_payload(file_name='D1_acceptance_revised.pdf'),

            format='json',

        )

        self.assertEqual(upload.status_code, 200)

        self.assertEqual(replace.status_code, 200)

        self.assertEqual(DeliverableSubmission.objects.get().file_name, 'D1_acceptance_revised.pdf')



        remove = self.client.post(

            '/api/repository/deliverables/remove/',

            {

                'team_id': self.team.id,

                'stage_label': 'Concept Proposal',

                'deliverable_id': 'D1',

            },

            format='json',

        )



        self.assertEqual(remove.status_code, 200)

        self.assertEqual(DeliverableSubmission.objects.count(), 0)



    def test_endorse_requires_all_required_pre_defense_files(self):

        blocked = self.client.post(

            '/api/repository/deliverables/endorse/',

            {'team_id': self.team.id, 'stage_label': 'Concept Proposal'},

            format='json',

        )

        for definition in SUGGESTED_DELIVERABLE_TEMPLATES['Concept Proposal']:

            DeliverableSubmission.objects.create(

                team=self.team,

                stage_label='Concept Proposal',

                deliverable_id=definition['id'],

                label=definition['label'],

                deliverable_type=definition['type'],

                required=definition['required'],

                file_name=f"{definition['id']}.pdf",

                uploaded_by=self.admin,

                status=DeliverableSubmission.STATUS_ACCEPTED,

            )

        endorsed = self.client.post(

            '/api/repository/deliverables/endorse/',

            {'team_id': self.team.id, 'stage_label': 'Concept Proposal'},

            format='json',

        )



        self.assertEqual(blocked.status_code, 400)

        self.assertEqual(endorsed.status_code, 200)

        self.team.refresh_from_db()

        self.assertEqual(self.team.ready_for_stage, 'Concept Proposal')
        progress = TeamStageProgress.objects.get(team=self.team, defense_stage__label='Concept Proposal')
        self.assertEqual(progress.status, TeamStageProgress.STATUS_READY)



    def test_archive_submission_is_locked_until_defense_done(self):
        locked = self.client.post(

            '/api/repository/deliverables/upload/',

            self.upload_payload(deliverable_id='D4.1', file_name='CloudFileSync.pdf'),

            format='json',

        )

        DefenseSchedule.objects.create(

            scope=DefenseSchedule.SCOPE_CAPSTONE,

            semester=self.semester,

            team=self.team,

            defense_stage=self.stage,

            scheduled_date='2026-05-20',

            start_time='09:00',

            slot_duration=60,

            room='Room 301',

            status=DefenseSchedule.STATUS_DONE,

            created_by=self.admin,

        )

        unlocked = self.client.post(

            '/api/repository/deliverables/upload/',

            self.upload_payload(deliverable_id='D4.1', file_name='CloudFileSync.pdf'),

            format='json',

        )



        self.assertEqual(locked.status_code, 400)

        self.assertEqual(unlocked.status_code, 200)

        self.assertEqual(DeliverableSubmission.objects.filter(deliverable_type='post').count(), 1)




    def test_archive_required_progress_connected_to_defense_done(self):

        StageDeliverable.objects.update_or_create(

            defense_stage=self.stage,

            deliverable_id='D4.1',

            defaults={

                'label': 'Approved Concept Paper',

                'deliverable_type': 'post',

                'required': True,

                'display_order': 99,

            },

        )

        def stage_for_team(payload, team_id):
            for row in payload['teams']:
                if row['id'] == team_id:
                    return row['selected_stage']
            raise AssertionError(f'Team {team_id} not in payload')

        response = self.client.get(

            '/api/repository/deliverables/',

            {'stage_label': 'Concept Proposal'},

        )

        stage = stage_for_team(response.data, self.team.id)

        self.assertFalse(stage['archive_unlocked'])

        self.assertEqual(stage['archive_required_total'], 1)

        self.assertEqual(stage['archive_required_uploaded'], 0)

        self.assertFalse(stage['archive_complete'])



        DefenseSchedule.objects.create(

            scope=DefenseSchedule.SCOPE_CAPSTONE,

            semester=self.semester,

            team=self.team,

            defense_stage=self.stage,

            scheduled_date='2026-05-20',

            start_time='09:00',

            slot_duration=60,

            room='Room 301',

            status=DefenseSchedule.STATUS_DONE,

            created_by=self.admin,

        )

        self.client.post(

            '/api/repository/deliverables/upload/',

            self.upload_payload(deliverable_id='D4.1', file_name='CloudFileSync.pdf'),

            format='json',

        )

        response = self.client.get(

            '/api/repository/deliverables/',

            {'stage_label': 'Concept Proposal'},

        )

        stage = stage_for_team(response.data, self.team.id)

        self.assertTrue(stage['archive_unlocked'])
        self.assertTrue(stage['vault_unlocked'])
        self.assertEqual(stage['archive_required_uploaded'], 1)
        self.assertTrue(stage['archive_complete'])

    def test_officially_complete_stage_unlocks_archive_deliverables(self):
        from defense.stages.models import StageGradingConfig
        config, _ = StageGradingConfig.objects.get_or_create(
            defense_stage=self.stage,
            semester=self.semester,
        )
        config.is_officially_complete = True
        config.save()

        response = self.client.get(
            '/api/repository/deliverables/',
            {'stage_label': 'Concept Proposal'},
        )
        team_data = next(t for t in response.data['teams'] if t['id'] == self.team.id)
        stage = team_data['selected_stage']
        self.assertTrue(stage['archive_unlocked'])
        self.assertTrue(stage['vault_unlocked'])



    def test_admin_dashboard_counts_deliverables_and_reports_current_phase(self):

        for definition in SUGGESTED_DELIVERABLE_TEMPLATES['Concept Proposal']:

            DeliverableSubmission.objects.create(

                team=self.team,

                stage_label='Concept Proposal',

                deliverable_id=definition['id'],

                label=definition['label'],

                deliverable_type=definition['type'],

                required=definition['required'],

                file_name=f"{definition['id']}.pdf",

                uploaded_by=self.admin,

                status=DeliverableSubmission.STATUS_ACCEPTED,

            )

        self.client.post(

            '/api/repository/deliverables/endorse/',

            {'team_id': self.team.id, 'stage_label': 'Concept Proposal'},

            format='json',

        )



        response = self.client.get('/api/dashboards/admin/')



        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['submitted_deliverables'], 7)
        self.assertEqual(response.data['stats']['ready_capstone_teams'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)

    def test_removing_required_deliverable_locks_stage_progress(self):
        required_pre = [
            item for item in SUGGESTED_DELIVERABLE_TEMPLATES['Concept Proposal']
            if item['type'] == DeliverableSubmission.TYPE_PRE and item['required']
        ]
        for definition in required_pre:
            DeliverableSubmission.objects.create(
                team=self.team,
                stage_label='Concept Proposal',
                deliverable_id=definition['id'],
                label=definition['label'],
                deliverable_type=definition['type'],
                required=definition['required'],
                file_name=f"{definition['id']}.pdf",
                uploaded_by=self.admin,
                status=DeliverableSubmission.STATUS_ACCEPTED,
            )
        endorse_team(self.team, 'Concept Proposal')

        remove_submission(self.team, 'Concept Proposal', required_pre[0]['id'])

        progress = TeamStageProgress.objects.get(team=self.team, defense_stage=self.stage)
        self.assertEqual(progress.status, TeamStageProgress.STATUS_LOCKED)

    def test_suggested_file_name_uses_archive_file_template(self):
        d = StageDeliverable.objects.get(defense_stage=self.stage, deliverable_id='D4.1')
        d.archive_file_template = '{year}.{course}.{project}.{stage}.{deliverable}.{semester}'
        d.save()

        response = self.client.get('/api/repository/deliverables/', {'stage_label': 'Concept Proposal'})
        self.assertEqual(response.status_code, 200)

        team_payload = None
        for team in response.data['teams']:
            if team['id'] == self.team.id:
                team_payload = team['selected_stage']
                break
        self.assertIsNotNone(team_payload)

        d41_payload = None
        for row in team_payload['deliverables']:
            if row['id'] == 'D4.1':
                d41_payload = row
                break
        self.assertIsNotNone(d41_payload)

        self.assertEqual(
            d41_payload['suggested_file_name'],
            '3rdYear.CAP301.CloudFileSync.ConceptProposal.D41ApprovedConceptPaper.2ndSemester.pdf'
        )

    def test_archive_submission_enforces_naming_convention(self):
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            scheduled_date='2026-05-20',
            start_time='09:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_DONE,
            created_by=self.admin,
        )
        
        # Uploading with student's local filename succeeds without rigid blocking
        response_success = self.client.post(
            '/api/repository/deliverables/upload/',
            self.upload_payload(deliverable_id='D4.1', file_name='ArbitraryStudentDraft.pdf'),
            format='json',
        )
        self.assertEqual(response_success.status_code, 200)
        self.assertIn('submission_id', response_success.data)

    def test_pit_lead_scoping_for_deliverables(self):
        # Create a PIT lead user (3rd Year)
        pit_lead = User.objects.create_user(
            username='pit-lead-3',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        
        # Create PIT teams for 3rd Year and 2nd Year
        pit_team_3 = StudentTeam.objects.create(
            name='PIT Team 3',
            project_title='PIT 3 Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.other_student,
        )
        pit_team_2 = StudentTeam.objects.create(
            name='PIT Team 2',
            project_title='PIT 2 Project',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.semester,
            leader=self.other_student,
        )
        
        # Authenticate as PIT lead
        self.client.force_authenticate(user=pit_lead)
        
        # Fetch deliverables in 'pit' scope
        response = self.client.get('/api/repository/deliverables/', {'scope': 'pit'})
        self.assertEqual(response.status_code, 200)
        
        # Counts should only include the 3rd Year PIT team (not the 3rd Year Capstone team or 2nd Year PIT team)
        self.assertEqual(response.data['counts']['teams'], 1)
        self.assertEqual(response.data['teams'][0]['name'], 'PIT Team 3')

    def test_pit_deliverables_serialization_choices_validation(self):
        from defense.scheduler.models import PitEventGradingConfig, PitEventDeliverable
        from grading.rubrics.models import Rubric
        
        # Create rubrics
        panel_rubric = Rubric.objects.create(
            name='PIT Panel Rubric',
            evaluation_type='panel',
            scope='pit',
            status='published',
            semester=self.semester,
        )
        peer_rubric = Rubric.objects.create(
            name='PIT Peer Rubric',
            evaluation_type='peer',
            scope='pit',
            status='published',
            semester=self.semester,
        )
        
        # Configure PIT event
        config = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='PIT Expo 2026',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
            panel_weight=80,
            peer_weight=20,
        )
        PitEventDeliverable.objects.create(
            pit_event_config=config,
            deliverable_id='PIT_D1',
            label='PIT Project Poster',
            required=True,
        )
        
        pit_team = StudentTeam.objects.create(
            name='PIT Team 3',
            project_title='PIT 3 Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.other_student,
        )
        
        # Attempt upload with Capstone stage (should fail serializer validation for PIT team)
        response_fail = self.client.post(
            '/api/repository/deliverables/upload/',
            {
                'team_id': pit_team.id,
                'stage_label': 'Concept Proposal',
                'deliverable_id': 'D1',
                'file_name': 'test.pdf',
            },
            format='json',
        )
        self.assertEqual(response_fail.status_code, 400)
        self.assertIn('stage_label', response_fail.data)
        
        # Attempt upload with correct PIT event (should succeed validation)
        response_success = self.client.post(
            '/api/repository/deliverables/upload/',
            {
                'team_id': pit_team.id,
                'stage_label': 'PIT Expo 2026',
                'deliverable_id': 'PIT_D1',
                'file_name': 'test.pdf',
            },
            format='json',
        )
        self.assertEqual(response_success.status_code, 200)

    def test_student_upload_and_delete_success(self):
        self.client.force_authenticate(user=self.student)
        response_upload = self.client.post(
            '/api/repository/deliverables/upload/',
            {
                'team_id': self.team.id,
                'stage_label': 'Concept Proposal',
                'deliverable_id': 'D1',
                'file_name': 'student_doc.pdf',
            },
            format='json',
        )
        self.assertEqual(response_upload.status_code, 200)
        self.assertTrue(DeliverableSubmission.objects.filter(team=self.team, deliverable_id='D1').exists())
        
        response_remove = self.client.post(
            '/api/repository/deliverables/remove/',
            {
                'team_id': self.team.id,
                'stage_label': 'Concept Proposal',
                'deliverable_id': 'D1',
            },
            format='json',
        )
        self.assertEqual(response_remove.status_code, 200)
        self.assertFalse(DeliverableSubmission.objects.filter(team=self.team, deliverable_id='D1').exists())

    def test_student_endorse_forbidden(self):
        self.client.force_authenticate(user=self.student)
        response = self.client.post(
            '/api/repository/deliverables/endorse/',
            {
                'team_id': self.team.id,
                'stage_label': 'Concept Proposal',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_pit_instructor_scoping(self):
        from user_management.models import SectionInstructorAssignment
        instructor = User.objects.create_user(
            username='instructor-1',
            password='pass12345',
            role='faculty',
        )
        SectionInstructorAssignment.objects.create(
            faculty=instructor,
            semester=self.semester,
            year_level='3rd Year',
            section='IT3A',
            is_active=True,
        )
        pit_team_assigned = StudentTeam.objects.create(
            name='PIT Team Assigned',
            project_title='PIT Assigned Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            section='IT3A',
            semester=self.semester,
            leader=self.other_student,
        )
        pit_team_other = StudentTeam.objects.create(
            name='PIT Team Other',
            project_title='PIT Other Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            section='IT3B',
            semester=self.semester,
            leader=self.other_student,
        )
        self.client.force_authenticate(user=instructor)
        response = self.client.get('/api/repository/deliverables/', {'scope': 'pit'})
        self.assertEqual(response.status_code, 200)
        team_ids = [team['id'] for team in response.data['teams']]
        self.assertIn(pit_team_assigned.id, team_ids)
        self.assertNotIn(pit_team_other.id, team_ids)

    def test_review_submission_validation_error_returns_400(self):
        sub = DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='Concept Proposal',
            deliverable_id='D1',
            label='System Concept',
            deliverable_type=DeliverableSubmission.TYPE_PRE,
            file_name='test.pdf',
            uploaded_by=self.admin,
            status=DeliverableSubmission.STATUS_PENDING,
        )
        from unittest.mock import patch
        from django.core.exceptions import ValidationError
        with patch.object(DeliverableSubmission, 'save', side_effect=ValidationError('Naming convention violation')):
            response = self.client.post(
                '/api/repository/deliverables/review/',
                {
                    'team_id': self.team.id,
                    'stage_label': 'Concept Proposal',
                    'deliverable_id': 'D1',
                    'status': DeliverableSubmission.STATUS_ACCEPTED,
                    'feedback': 'Good',
                },
                format='json',
            )
            self.assertEqual(response.status_code, 400)
            self.assertIn('Naming convention violation', response.data['detail'])

    def test_replacement_deletes_old_file_and_avoids_suffixing(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        pdf1 = SimpleUploadedFile('doc.pdf', b'content1', content_type='application/pdf')
        pdf2 = SimpleUploadedFile('doc.pdf', b'content2', content_type='application/pdf')
        
        sub1 = upsert_submission(
            self.team,
            'Concept Proposal',
            'D1',
            'doc.pdf',
            '8 bytes',
            self.student,
            file=pdf1
        )
        file_path_1 = sub1.file.name
        
        sub2 = upsert_submission(
            self.team,
            'Concept Proposal',
            'D1',
            'doc.pdf',
            '8 bytes',
            self.student,
            file=pdf2
        )
        file_path_2 = sub2.file.name
        
        # Verify that the new file took the exact same path instead of suffixing with _1
        self.assertEqual(file_path_1, file_path_2)
        from django.core.files.storage import default_storage
        self.assertTrue(default_storage.exists(file_path_2))

    def test_deliverables_payload_resolves_pit_events_for_requested_year_level(self):
        from defense.scheduler.models import PitEventGradingConfig
        from grading.rubrics.models import Rubric
        panel_rubric = Rubric.objects.create(
            name='PIT Panel Rubric',
            evaluation_type='panel',
            scope='pit',
            status='published',
            semester=self.semester,
        )
        peer_rubric = Rubric.objects.create(
            name='PIT Peer Rubric',
            evaluation_type='peer',
            scope='pit',
            status='published',
            semester=self.semester,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='1st Year Expo',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year Expo',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
        )
        response = self.client.get('/api/repository/deliverables/?scope=pit&year_level=1st+Year')
        self.assertEqual(response.status_code, 200)
        self.assertIn('1st Year Expo', response.data['stage_options'])
        self.assertNotIn('2nd Year Expo', response.data['stage_options'])

    def test_deliverables_payload_auto_infers_student_team_year_level(self):
        from defense.scheduler.models import PitEventGradingConfig
        from grading.rubrics.models import Rubric
        panel_rubric = Rubric.objects.create(
            name='PIT Panel Rubric 2',
            evaluation_type='panel',
            scope='pit',
            status='published',
            semester=self.semester,
        )
        peer_rubric = Rubric.objects.create(
            name='PIT Peer Rubric 2',
            evaluation_type='peer',
            scope='pit',
            status='published',
            semester=self.semester,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='1st year Expo',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year Expo',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
        )
        student2 = User.objects.create_user(
            username='student-2nd-yr',
            password='pass12345',
            role='student',
        )
        team2 = StudentTeam.objects.create(
            name='Team ByteForce',
            semester=self.semester,
            leader=student2,
            level='2nd Year PIT',
            year_level='2nd Year',
        )
        TeamMembership.objects.create(team=team2, student=student2)

        self.client.force_authenticate(user=student2)
        response = self.client.get('/api/repository/deliverables/?scope=pit')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['selected_stage'], '2nd Year Expo')
        self.assertIn('2nd Year Expo', response.data['stage_options'])
        self.assertNotIn('1st year Expo', response.data['stage_options'])

    def test_pit_deliverables_filtered_by_team_id_scopes_stage_options_to_team_year(self):
        from defense.scheduler.models import PitEventGradingConfig
        from grading.rubrics.models import Rubric
        panel_rubric = Rubric.objects.create(
            name='PIT Panel Rubric 3',
            evaluation_type='panel',
            scope='pit',
            status='published',
            semester=self.semester,
        )
        peer_rubric = Rubric.objects.create(
            name='PIT Peer Rubric 3',
            evaluation_type='peer',
            scope='pit',
            status='published',
            semester=self.semester,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='1st Year Concept Pitch',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year Architecture Pitch',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
        )
        pit_student_1 = User.objects.create_user(
            username='pit-student-1st',
            password='pass12345',
            role='student',
        )
        pit_team_1 = StudentTeam.objects.create(
            name='Team CyberShield',
            semester=self.semester,
            leader=pit_student_1,
            level='1st Year PIT',
            year_level='1st Year',
        )
        TeamMembership.objects.create(team=pit_team_1, student=pit_student_1)

        pit_student_2 = User.objects.create_user(
            username='pit-student-2nd',
            password='pass12345',
            role='student',
        )
        pit_team_2 = StudentTeam.objects.create(
            name='Team ArchGuard',
            semester=self.semester,
            leader=pit_student_2,
            level='2nd Year PIT',
            year_level='2nd Year',
        )
        TeamMembership.objects.create(team=pit_team_2, student=pit_student_2)

        # As admin, query with team_id for 1st Year team
        self.client.force_authenticate(user=self.admin)
        response = self.client.get(f'/api/repository/deliverables/?scope=pit&team_id={pit_team_1.id}')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['teams']), 1)
        self.assertEqual(response.data['teams'][0]['id'], pit_team_1.id)
        self.assertIn('1st Year Concept Pitch', response.data['stage_options'])
        self.assertNotIn('2nd Year Architecture Pitch', response.data['stage_options'])

    def test_post_defense_review_locked_for_faculty_and_unlocked_by_admin(self):
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            scheduled_date='2026-05-20',
            start_time='09:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_DONE,
        )
        sub = DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='Concept Proposal',
            deliverable_id='D1',
            label='Adviser Acceptance Form',
            deliverable_type='pre',
            required=True,
            uploaded_by=self.student,
            status=DeliverableSubmission.STATUS_PENDING,
        )

        self.client.force_authenticate(user=self.adviser)
        res = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
            'deliverable_id': 'D1',
            'status': 'rejected',
        })
        self.assertEqual(res.status_code, 403)
        self.assertIn('view-only for faculty', res.data['detail'])

        self.client.force_authenticate(user=self.admin)
        unlock_res = self.client.post('/api/repository/deliverables/unlock/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
        })
        self.assertEqual(unlock_res.status_code, 200)
        self.assertTrue(unlock_res.data['unlocked'])

        self.client.force_authenticate(user=self.adviser)
        res2 = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
            'deliverable_id': 'D1',
            'status': 'accepted',
        })
        self.assertEqual(res2.status_code, 200)

    def test_faculty_can_review_post_defense_deliverables_when_defense_is_done(self):
        from django.utils import timezone
        from defense.scheduler.models import DefenseSchedule
        from defense.stages.models import DefenseStage
        stage = DefenseStage.objects.filter(label='Concept Proposal').first() or DefenseStage.objects.create(
            label='Concept Proposal',
            display_order=1,
        )
        stage.deliverables.filter(deliverable_id='POST_D1').delete()
        stage.deliverables.create(
            deliverable_id='POST_D1',
            label='Concept Paper',
            deliverable_type='post',
            required=True,
        )
        DefenseSchedule.objects.create(
            semester=self.semester,
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            team=self.team,
            defense_stage=stage,
            scheduled_date=timezone.now().date(),
            start_time='09:00:00',
            room='Room 301',
            status=DefenseSchedule.STATUS_DONE,
        )
        post_sub = DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='Concept Proposal',
            deliverable_id='POST_D1',
            label='Concept Paper',
            deliverable_type='post',
            required=True,
            uploaded_by=self.student,
            status=DeliverableSubmission.STATUS_PENDING,
        )

        # Faculty adviser can review post-defense deliverable directly
        self.client.force_authenticate(user=self.adviser)
        res = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
            'deliverable_id': 'POST_D1',
            'status': 'accepted',
        })
        self.assertEqual(res.status_code, 200)
        post_sub.refresh_from_db()
        self.assertEqual(post_sub.status, DeliverableSubmission.STATUS_ACCEPTED)
        self.assertEqual(post_sub.reviewed_by, self.adviser)

    def test_endorsed_stage_with_approved_team_status_keeps_post_deliverables_locked_until_defense_done(self):
        from django.utils import timezone
        from defense.stages.models import DefenseStage
        from defense.scheduler.models import DefenseSchedule
        from student_teams.services import mark_stage_ready, mark_stage_result
        from grading.grades.models import TeamGrade

        # Create next stage 'Project Proposal'
        stage2, _ = DefenseStage.objects.get_or_create(
            label='Project Proposal',
            defaults={'display_order': 2, 'is_active': True},
        )
        stage2.deliverables.filter(deliverable_id='POST_D2').delete()
        stage2.deliverables.create(
            deliverable_id='POST_D2',
            label='Project Paper Final',
            deliverable_type='post',
            required=True,
        )

        # Team previously passed Stage 1 (so team.status == 'Approved')
        self.team.status = StudentTeam.STATUS_APPROVED
        self.team.save(update_fields=['status', 'updated_at'])

        # Adviser endorses team for Stage 2
        mark_stage_ready(self.team, stage2, user=self.adviser)

        # Retrieve deliverables for Stage 2
        self.client.force_authenticate(user=self.student)
        res = self.client.get('/api/repository/deliverables/', {'stage_label': 'Project Proposal'})
        self.assertEqual(res.status_code, 200)

        team_data = next(t for t in res.data['teams'] if t['id'] == self.team.id)
        selected_stage = team_data['selected_stage']

        # Post-defense deliverables MUST remain locked because defense for Stage 2 is not done
        self.assertFalse(selected_stage['archive_unlocked'])
        self.assertFalse(selected_stage['vault_unlocked'])
        post_items = [d for d in selected_stage['deliverables'] if d['type'] == 'post']
        self.assertTrue(all(d['locked'] for d in post_items))

        # Attempting to upload post-defense deliverable before defense done must fail
        upload_res = self.client.post(
            '/api/repository/deliverables/upload/',
            self.upload_payload(
                deliverable_id='POST_D2',
                stage_label='Project Proposal',
                file_name='Chapter1-3.pdf',
            ),
            format='json',
        )
        self.assertEqual(upload_res.status_code, 400)
        self.assertIn('Post-Defense submissions are locked until this defense is done.', upload_res.data['detail'])

        # Now defense happens and is completed
        DefenseSchedule.objects.create(
            semester=self.semester,
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            team=self.team,
            defense_stage=stage2,
            scheduled_date=timezone.now().date(),
            start_time='10:00:00',
            room='Room 302',
            status=DefenseSchedule.STATUS_DONE,
        )

        # Post-defense deliverables should now be unlocked
        res2 = self.client.get('/api/repository/deliverables/', {'stage_label': 'Project Proposal'})
        team_data2 = next(t for t in res2.data['teams'] if t['id'] == self.team.id)
        selected_stage2 = team_data2['selected_stage']
        self.assertTrue(selected_stage2['archive_unlocked'])
        self.assertTrue(selected_stage2['vault_unlocked'])

    def test_endorsement_and_unendorse_flow(self):
        StageDeliverable.objects.filter(defense_stage=self.stage).delete()
        self.stage.deliverables.create(
            deliverable_id='D1',
            label='Concept Paper Draft',
            deliverable_type='pre',
            required=True,
        )

        # Student uploads pre-defense deliverable
        self.client.force_authenticate(user=self.student)
        self.client.post(
            '/api/repository/deliverables/upload/',
            self.upload_payload(
                deliverable_id='D1',
                stage_label='Concept Proposal',
                file_name='Manuscript_Draft.pdf',
            ),
            format='json',
        )

        # Faculty adviser accepts deliverable
        self.client.force_authenticate(user=self.adviser)
        accept_res = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
            'deliverable_id': 'D1',
            'status': 'accepted',
        })
        self.assertEqual(accept_res.status_code, 200)

        # Faculty adviser can still reject/change review before endorsement
        reject_res = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
            'deliverable_id': 'D1',
            'status': 'rejected',
            'feedback': 'Needs more details in Section 2',
        })
        self.assertEqual(reject_res.status_code, 200)

        # Re-accept deliverable
        self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
            'deliverable_id': 'D1',
            'status': 'accepted',
        })

        # Endorse team
        endorse_res = self.client.post('/api/repository/deliverables/endorse/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
        })
        self.assertEqual(endorse_res.status_code, 200)

        team_info = next(t for t in endorse_res.data['teams'] if t['id'] == self.team.id)
        selected_stg = team_info['selected_stage']
        self.assertTrue(selected_stg['endorsed'])
        self.assertTrue(selected_stg['can_cancel_endorsement'])
        self.assertFalse(selected_stg['can_faculty_review_pre'])

        # Students cannot cancel endorsement
        self.client.force_authenticate(user=self.student)
        stud_unendorse = self.client.post('/api/repository/deliverables/unendorse/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
        })
        self.assertEqual(stud_unendorse.status_code, 403)

        # Faculty adviser cancels endorsement
        self.client.force_authenticate(user=self.adviser)
        unendorse_res = self.client.post('/api/repository/deliverables/unendorse/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
        })
        self.assertEqual(unendorse_res.status_code, 200)

        team_info_unend = next(t for t in unendorse_res.data['teams'] if t['id'] == self.team.id)
        selected_stg_unend = team_info_unend['selected_stage']
        self.assertFalse(selected_stg_unend['endorsed'])
        self.assertTrue(selected_stg_unend['can_faculty_review_pre'])

        # Re-endorse and create a defense schedule
        self.client.post('/api/repository/deliverables/endorse/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
        })

        DefenseSchedule.objects.create(
            semester=self.semester,
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            team=self.team,
            defense_stage=self.stage,
            scheduled_date=timezone.now().date(),
            start_time='14:00:00',
            room='Room 101',
            status=DefenseSchedule.STATUS_SCHEDULED,
        )

        # Cancelling endorsement should now be blocked because defense is scheduled
        blocked_unendorse = self.client.post('/api/repository/deliverables/unendorse/', {
            'team_id': self.team.id,
            'stage_label': 'Concept Proposal',
        })
        self.assertEqual(blocked_unendorse.status_code, 400)
        self.assertIn('already scheduled', blocked_unendorse.data['detail'])

    def test_pit_post_deliverables_lifecycle_and_safeguards(self):
        from defense.scheduler.models import PitEventGradingConfig, PitEventDeliverable, DefenseSchedule
        from grading.rubrics.models import Rubric
        from grading.grades.models import TeamGrade
        from repository.deliverables.services import archive_unlocked

        panel_rubric = Rubric.objects.create(
            name='PIT Panel Rubric Event',
            evaluation_type=Rubric.EVAL_PANEL,
            scope=Rubric.SCOPE_PIT,
            status=Rubric.STATUS_PUBLISHED,
            semester=self.semester,
        )
        peer_rubric = Rubric.objects.create(
            name='PIT Peer Rubric Event',
            evaluation_type=Rubric.EVAL_PEER,
            scope=Rubric.SCOPE_PIT,
            status=Rubric.STATUS_PUBLISHED,
            semester=self.semester,
        )
        pit_cfg = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year PIT Showcase',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
            panel_weight=80,
            peer_weight=20,
        )
        PitEventDeliverable.objects.create(
            pit_event_config=pit_cfg,
            deliverable_id='PIT_PRE',
            label='Project Brief',
            deliverable_type=PitEventDeliverable.TYPE_PRE,
            required=True,
        )
        PitEventDeliverable.objects.create(
            pit_event_config=pit_cfg,
            deliverable_id='PIT_POST',
            label='Final Source Code & Manual',
            deliverable_type=PitEventDeliverable.TYPE_POST,
            required=True,
        )

        pit_team = StudentTeam.objects.create(
            name='Alpha Coders',
            project_title='Alpha PIT Project',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.semester,
            leader=self.other_student,
        )

        # 1. Before presentation is done: post-deliverable is locked
        self.assertFalse(archive_unlocked(pit_team, '2nd Year PIT Showcase', deliverable_type='post'))

        # 2. Schedule created and defense presentation marked DONE
        sched = DefenseSchedule.objects.create(
            semester=self.semester,
            scope=DefenseSchedule.SCOPE_PIT,
            team=pit_team,
            event_name='2nd Year PIT Showcase',
            scheduled_date=timezone.now().date(),
            start_time='10:00:00',
            room='Expo Hall',
            status=DefenseSchedule.STATUS_DONE,
        )

        # Post deliverable unlocks immediately upon presentation completion (STATUS_DONE)
        self.assertTrue(archive_unlocked(pit_team, '2nd Year PIT Showcase', deliverable_type='post'))

        # 3. Student can now upload post-deliverable
        self.client.force_authenticate(user=self.admin)
        res_upload = self.client.post(
            '/api/repository/deliverables/upload/',
            {
                'team_id': pit_team.id,
                'stage_label': '2nd Year PIT Showcase',
                'deliverable_id': 'PIT_POST',
                'file_name': 'alphapitproject_manual.pdf',
            },
            format='json',
        )
        self.assertEqual(res_upload.status_code, 200)

        # 4. If team grade result is recorded as failed (< 75%), post-deliverables lock
        from decimal import Decimal
        team_grade = TeamGrade.objects.create(
            team=pit_team,
            schedule=sched,
            semester=self.semester,
            scope=TeamGrade.SCOPE_PIT,
            stage_label='2nd Year PIT Showcase',
            pit_event_config=pit_cfg,
            panel_score=Decimal('60.00'),
            peer_score=Decimal('60.00'),
            final_grade=Decimal('60.00'),
            panel_weight=80,
            peer_weight=20,
            status=TeamGrade.STATUS_PUBLISHED,
        )
        self.assertEqual(team_grade.result, 'failed')
        self.assertFalse(archive_unlocked(pit_team, '2nd Year PIT Showcase', deliverable_type='post'))









