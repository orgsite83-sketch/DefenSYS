from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense_scheduler.models import DefenseSchedule
from defense_stages.models import DefenseStage
from student_teams.models import StudentTeam, TeamMembership
from .models import DeliverableSubmission
from .services import DELIVERABLE_DEFINITIONS


User = get_user_model()


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
        response = self.client.get('/api/capstone-deliverables/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['teams'], 2)
        self.assertEqual(response.data['stage_options'][0], 'Concept Proposal')
        self.assertEqual(response.data['teams'][0]['selected_stage']['required_total'], 5)

    def test_adviser_only_sees_assigned_capstone_teams(self):
        self.client.force_authenticate(user=self.adviser)

        response = self.client.get('/api/capstone-deliverables/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['teams'], 1)
        self.assertEqual(response.data['teams'][0]['name'], 'Team VaultSync')

    def test_upload_replace_and_remove_deliverable(self):
        upload = self.client.post('/api/capstone-deliverables/upload/', self.upload_payload(), format='json')
        replace = self.client.post(
            '/api/capstone-deliverables/upload/',
            self.upload_payload(file_name='D1_acceptance_revised.pdf'),
            format='json',
        )
        self.assertEqual(upload.status_code, 200)
        self.assertEqual(replace.status_code, 200)
        self.assertEqual(DeliverableSubmission.objects.get().file_name, 'D1_acceptance_revised.pdf')

        remove = self.client.post(
            '/api/capstone-deliverables/remove/',
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
            '/api/capstone-deliverables/endorse/',
            {'team_id': self.team.id, 'stage_label': 'Concept Proposal'},
            format='json',
        )
        for definition in DELIVERABLE_DEFINITIONS['Concept Proposal']:
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
            '/api/capstone-deliverables/endorse/',
            {'team_id': self.team.id, 'stage_label': 'Concept Proposal'},
            format='json',
        )

        self.assertEqual(blocked.status_code, 400)
        self.assertEqual(endorsed.status_code, 200)
        self.team.refresh_from_db()
        self.assertEqual(self.team.ready_for_stage, 'Concept Proposal')

    @override_settings(ENABLE_PROTOTYPE_TOOLS=True)
    def test_demo_fill_endpoint_is_developer_only(self):
        response = self.client.post(
            '/api/capstone-deliverables/demo-fill/',
            {'stage_label': 'Concept Proposal'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['created_count'], 10)

    def test_vault_submission_is_locked_until_defense_done(self):
        locked = self.client.post(
            '/api/capstone-deliverables/upload/',
            self.upload_payload(deliverable_id='D4.1', file_name='approved_concept.pdf'),
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
            '/api/capstone-deliverables/upload/',
            self.upload_payload(deliverable_id='D4.1', file_name='approved_concept.pdf'),
            format='json',
        )

        self.assertEqual(locked.status_code, 400)
        self.assertEqual(unlocked.status_code, 200)
        self.assertEqual(DeliverableSubmission.objects.filter(deliverable_type='vault').count(), 1)

    def test_admin_dashboard_counts_deliverables_and_reports_current_phase(self):
        for definition in DELIVERABLE_DEFINITIONS['Concept Proposal']:
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
            '/api/capstone-deliverables/endorse/',
            {'team_id': self.team.id, 'stage_label': 'Concept Proposal'},
            format='json',
        )

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['submitted_deliverables'], 6)
        self.assertEqual(response.data['stats']['ready_capstone_teams'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)
