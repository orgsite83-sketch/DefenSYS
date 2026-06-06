from django.contrib.auth import get_user_model

from django.core.files.uploadedfile import SimpleUploadedFile

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

            vault_note=item.get('vault_note', ''),

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

        )

        self.other_team = StudentTeam.objects.create(

            name='Team Other',

            project_title='Another Capstone',

            level=StudentTeam.LEVEL_4_CAPSTONE,

            year_level='4th Year',

            semester=self.semester,

            leader=self.other_student,

            adviser=self.other_adviser,

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



    def test_non_capstone_team_rejected_on_upsert(self):

        pit_team = StudentTeam.objects.create(

            name='Team PIT Only',

            project_title='PIT Project',

            level=StudentTeam.LEVEL_3_PIT,

            year_level='3rd Year',

            semester=self.semester,

            leader=self.other_student,

        )

        with self.assertRaises(PermissionError) as ctx:

            upsert_submission(

                pit_team,

                'Concept Proposal',

                'D1',

                'acceptance.pdf',

                '10 KB',

                self.admin,

            )

        self.assertIn('Capstone', str(ctx.exception))



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



    def test_vault_submission_is_locked_until_defense_done(self):

        locked = self.client.post(

            '/api/repository/deliverables/upload/',

            self.upload_payload(deliverable_id='D4.1', file_name='3rdYear.CAP301.CloudFileSync.2ndSemester.pdf'),

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

            self.upload_payload(deliverable_id='D4.1', file_name='3rdYear.CAP301.CloudFileSync.2ndSemester.pdf'),

            format='json',

        )



        self.assertEqual(locked.status_code, 400)

        self.assertEqual(unlocked.status_code, 200)

        self.assertEqual(DeliverableSubmission.objects.filter(deliverable_type='vault').count(), 1)




    def test_vault_required_progress_connected_to_defense_done(self):

        StageDeliverable.objects.update_or_create(

            defense_stage=self.stage,

            deliverable_id='D4.1',

            defaults={

                'label': 'Approved Concept Paper',

                'deliverable_type': 'vault',

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

        self.assertFalse(stage['vault_unlocked'])

        self.assertEqual(stage['vault_required_total'], 1)

        self.assertEqual(stage['vault_required_uploaded'], 0)

        self.assertFalse(stage['vault_complete'])



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

            self.upload_payload(deliverable_id='D4.1', file_name='3rdYear.CAP301.CloudFileSync.2ndSemester.pdf'),

            format='json',

        )

        response = self.client.get(

            '/api/repository/deliverables/',

            {'stage_label': 'Concept Proposal'},

        )

        stage = stage_for_team(response.data, self.team.id)

        self.assertTrue(stage['vault_unlocked'])

        self.assertEqual(stage['vault_required_uploaded'], 1)

        self.assertTrue(stage['vault_complete'])



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
            )
        endorse_team(self.team, 'Concept Proposal')

        remove_submission(self.team, 'Concept Proposal', required_pre[0]['id'])

        progress = TeamStageProgress.objects.get(team=self.team, defense_stage=self.stage)
        self.assertEqual(progress.status, TeamStageProgress.STATUS_LOCKED)

    def test_suggested_file_name_uses_vault_file_template(self):
        d = StageDeliverable.objects.get(defense_stage=self.stage, deliverable_id='D4.1')
        d.vault_file_template = '{year}.{course}.{project}.{stage}.{deliverable}.{semester}'
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

    def test_vault_submission_enforces_naming_convention(self):
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
        
        # Test 1: Uploading a file with incorrect name should fail
        response_fail = self.client.post(
            '/api/repository/deliverables/upload/',
            self.upload_payload(deliverable_id='D4.1', file_name='IncorrectFileName.pdf'),
            format='json',
        )
        self.assertEqual(response_fail.status_code, 400)
        self.assertIn('naming convention', response_fail.data['file_name'][0])

        # Test 2: Uploading with correct suggested name (case-insensitive) should succeed
        response_success = self.client.post(
            '/api/repository/deliverables/upload/',
            self.upload_payload(deliverable_id='D4.1', file_name='3RDYEAR.CAP301.CLOUDFILESYNC.2NDSEMESTER.pdf'),
            format='json',
        )
        self.assertEqual(response_success.status_code, 200)




