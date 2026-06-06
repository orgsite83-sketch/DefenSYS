from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import PitInstructorAssignment
from .models import StudentTeam, TeamAdviserAssignment, TeamMembership, TeamStageProgress
from .services import mark_stage_ready
from .weekly_progress.models import WeeklyProgressReport


User = get_user_model()


class StudentTeamApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.adviser = User.objects.create_user(
            username='faculty-1',
            password='pass12345',
            role='faculty',
            first_name='Ada',
            last_name='Lovelace',
            is_adviser=True,
        )
        self.adviser_b = User.objects.create_user(
            username='faculty-2',
            password='pass12345',
            role='faculty',
            first_name='Grace',
            last_name='Hopper',
            is_adviser=True,
        )
        self.student_1 = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
            first_name='Juan',
            last_name='Dela Cruz',
        )
        self.student_2 = User.objects.create_user(
            username='2024-0002',
            password='pass12345',
            role='student',
            first_name='Maria',
            last_name='Santos',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.first_semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
            is_active=True,
            capstone_team_creation_enabled=False,
            capstone_program_phase=Semester.PHASE_NONE,
        )
        self.second_semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
            capstone_team_creation_enabled=True,
            capstone_program_phase=Semester.PHASE_CAPSTONE_1,
        )
        for student in (self.student_1, self.student_2):
            StudentAcademicRecord.objects.create(
                student=student,
                semester=self.first_semester,
                year_level='3rd Year',
            )
        self.client.force_authenticate(user=self.admin)

    def _activate_capstone_intake_semester(self):
        self.first_semester.is_active = False
        self.first_semester.save(update_fields=['is_active'])
        self.second_semester.is_active = True
        self.second_semester.save(update_fields=['is_active'])
        for student in (self.student_1, self.student_2):
            StudentAcademicRecord.objects.get_or_create(
                student=student,
                semester=self.second_semester,
                defaults={'year_level': '3rd Year'},
            )

    def test_team_stage_progress_keeps_independent_stage_statuses(self):
        team = StudentTeam.objects.create(
            name='Team Stage Ledger',
            project_title='Stage Ledger',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.second_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )
        concept = DefenseStage.objects.get(label='Concept Proposal')
        project = DefenseStage.objects.get(label='Project Proposal')
        TeamStageProgress.objects.create(
            team=team,
            semester=self.second_semester,
            defense_stage=concept,
            status=TeamStageProgress.STATUS_PASSED,
        )

        mark_stage_ready(team, project, user=self.adviser)

        self.assertEqual(
            TeamStageProgress.objects.get(team=team, defense_stage=concept).status,
            TeamStageProgress.STATUS_PASSED,
        )
        self.assertEqual(
            TeamStageProgress.objects.get(team=team, defense_stage=project).status,
            TeamStageProgress.STATUS_READY,
        )

    def test_create_team_blocked_during_capstone_off_season(self):
        response = self.client.post(
            '/api/teams/',
            {
                'name': 'Team OffSeason',
                'project_title': 'Should Not Create',
                'level': StudentTeam.LEVEL_3_CAPSTONE,
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id, self.student_2.id],
                'adviser_id': self.adviser.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('non_field_errors', response.data)

    def test_create_team_uses_members_leader_adviser_and_active_semester(self):
        self._activate_capstone_intake_semester()

        response = self.client.post(
            '/api/teams/',
            {
                'name': 'Team VaultSync',
                'project_title': 'Cloud File Sync for Students',
                'level': StudentTeam.LEVEL_3_CAPSTONE,
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id, self.student_2.id],
                'adviser_id': self.adviser.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['team']['semester'], Semester.SECOND)
        self.assertEqual(response.data['team']['member_count'], 2)
        self.assertEqual(response.data['team']['leader_name'], 'Juan Dela Cruz')
        self.assertEqual(response.data['team']['adviser_name'], 'Ada Lovelace')
        self.assertEqual(TeamAdviserAssignment.objects.filter(team_id=response.data['team']['id']).count(), 1)
        self.student_1.refresh_from_db()
        self.assertEqual(self.student_1.team_id, str(response.data['team']['id']))

    def test_teams_list_exposes_capstone_mode(self):
        response = self.client.get('/api/teams/?level=Capstone')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['capstone_mode'], 'off')
        self.assertFalse(response.data['can_create_capstone_teams'])
        self.assertIn('capstone_mode_message', response.data)

    def test_duplicate_name_level_is_rejected(self):
        self._activate_capstone_intake_semester()
        StudentTeam.objects.create(
            name='Team VaultSync',
            project_title='Cloud File Sync',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )

        response = self.client.post(
            '/api/teams/',
            {
                'name': 'Team VaultSync',
                'level': StudentTeam.LEVEL_3_CAPSTONE,
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    def test_update_team_members_and_status(self):
        team = StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )
        TeamMembership.objects.create(team=team, student=self.student_1, is_leader=True, order=0)

        response = self.client.patch(
            f'/api/teams/{team.id}/',
            {
                'name': 'Team Alpha',
                'project_title': 'Alpha Project Updated',
                'level': StudentTeam.LEVEL_4_CAPSTONE,
                'year_level': '4th Year',
                'semester_id': self.first_semester.id,
                'leader_id': self.student_2.id,
                'member_ids': [self.student_2.id],
                'adviser_id': self.adviser.id,
                'status': StudentTeam.STATUS_APPROVED,
            },
            format='json',
        )

        team.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(team.status, StudentTeam.STATUS_APPROVED)
        self.assertEqual(team.leader, self.student_2)
        self.assertEqual(team.memberships.count(), 1)

    def test_reassign_adviser_records_history_and_preserves_team(self):
        team = StudentTeam.objects.create(
            name='Team Reassign',
            project_title='Reassign Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )
        TeamMembership.objects.create(team=team, student=self.student_1, is_leader=True, order=0)
        TeamAdviserAssignment.objects.create(team=team, adviser=self.adviser, assigned_by=self.admin)

        response = self.client.patch(
            f'/api/teams/{team.id}/',
            {
                'name': team.name,
                'project_title': team.project_title,
                'level': team.level,
                'year_level': team.year_level,
                'semester_id': self.first_semester.id,
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id],
                'adviser_id': self.adviser_b.id,
                'adviser_change_reason': 'Previous adviser resigned',
            },
            format='json',
        )

        team.refresh_from_db()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(team.adviser, self.adviser_b)
        self.assertEqual(team.memberships.count(), 1)
        assignments = list(TeamAdviserAssignment.objects.filter(team=team).order_by('assigned_at'))
        self.assertEqual(len(assignments), 2)
        self.assertIsNotNone(assignments[0].ended_at)
        self.assertEqual(assignments[0].adviser, self.adviser)
        self.assertIsNone(assignments[1].ended_at)
        self.assertEqual(assignments[1].adviser, self.adviser_b)
        self.assertEqual(assignments[1].reason, 'Previous adviser resigned')

        history = self.client.get(f'/api/teams/{team.id}/adviser-history/')
        self.assertEqual(history.status_code, 200)
        self.assertEqual(len(history.data['assignments']), 2)

    def test_adviser_history_uses_team_visibility_scope(self):
        team = StudentTeam.objects.create(
            name='Team History Scope',
            project_title='History Scope Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )
        TeamMembership.objects.create(team=team, student=self.student_1, is_leader=True)
        TeamAdviserAssignment.objects.create(team=team, adviser=self.adviser, assigned_by=self.admin)
        pit_lead = User.objects.create_user(
            username='pit-lead-history',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        uploader = User.objects.create_user(
            username='uploader-history',
            password='pass12345',
            role='faculty',
            is_uploader=True,
        )

        self.client.force_authenticate(user=pit_lead)
        blocked = self.client.get(f'/api/teams/{team.id}/adviser-history/')
        self.client.force_authenticate(user=uploader)
        allowed = self.client.get(f'/api/teams/{team.id}/adviser-history/')

        self.assertEqual(blocked.status_code, 404)
        self.assertEqual(allowed.status_code, 200)
        self.assertEqual(len(allowed.data['assignments']), 1)

    def test_list_teams_returns_counts_and_options(self):
        StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )

        response = self.client.get('/api/teams/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 1)
        self.assertEqual(response.data['counts']['no_adviser'], 1)
        self.assertEqual(response.data['active_semester']['id'], self.first_semester.id)
        self.assertEqual(response.data['students'][0]['username'], '2024-0001')

    def test_bulk_import_creates_team_from_full_names(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team CSV',
                        'project_title': 'CSV Project',
                        'level': StudentTeam.LEVEL_3_CAPSTONE,
                        'year_level': '3rd Year',
                        'member_ids': ['Juan Dela Cruz', 'Maria Santos'],
                        'leader_id': 'Juan Dela Cruz',
                        'adviser_id': 'Ada Lovelace',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 1)
        self.assertEqual(response.data['imported_rows'], [1])
        team = StudentTeam.objects.get(name='Team CSV')
        self.assertEqual(team.memberships.count(), 2)
        self.assertEqual(team.adviser_id, self.adviser.id)

    def test_bulk_import_accepts_mixed_case_names(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team Mixed Case',
                        'project_title': 'Mixed Case Project',
                        'level': StudentTeam.LEVEL_3_CAPSTONE,
                        'year_level': '3rd Year',
                        'member_ids': ['juan dela cruz', 'maria santos'],
                        'leader_id': 'JUAN DELA CRUZ',
                        'adviser_id': 'ada lovelace',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertTrue(StudentTeam.objects.filter(name='Team Mixed Case').exists())

    def test_bulk_import_preview_flags_unknown_member_name(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/preview/',
            {'teams': [self._bulk_team_row('Team Bad Member', leader_id='Unknown Person')]},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        row = response.data['rows'][0]
        self.assertEqual(row['row'], 1)
        self.assertEqual(row['team_name'], 'Team Bad Member')
        self.assertFalse(row['ready'])
        self.assertTrue(any('Leader' in issue for issue in row['issues']))

    def test_bulk_import_preview_flags_ambiguous_student_name(self):
        self._activate_capstone_intake_semester()
        User.objects.create_user(
            username='2024-0099',
            password='pass12345',
            role='student',
            first_name='Juan',
            last_name='Dela Cruz',
        )
        response = self.client.post(
            '/api/teams/bulk-import/preview/',
            {'teams': [self._bulk_team_row('Team Ambiguous')]},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        row = response.data['rows'][0]
        self.assertFalse(row['ready'])
        self.assertTrue(
            any('multiple users match' in issue.lower() for issue in row['issues']),
        )

    def test_bulk_import_error_includes_team_name(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/',
            {'teams': [self._bulk_team_row('Team Error Name', adviser_id='Nobody Here')]},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['error_count'], 1)
        self.assertEqual(response.data['errors'][0]['team_name'], 'Team Error Name')
        self.assertEqual(response.data['errors'][0]['row'], 1)

    def _bulk_team_row(self, team_name, adviser_id='', leader_id='Juan Dela Cruz'):
        return {
            'team_name': team_name,
            'project_title': f'{team_name} Project',
            'level': StudentTeam.LEVEL_3_CAPSTONE,
            'year_level': '3rd Year',
            'member_ids': ['Juan Dela Cruz', 'Maria Santos'],
            'leader_id': leader_id,
            'adviser_id': adviser_id,
        }

    def test_bulk_import_preview_flags_existing_team_membership(self):
        self._activate_capstone_intake_semester()
        pit_team = StudentTeam.objects.create(
            name='Team CodeLearners',
            project_title='Smart Campus',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.second_semester,
            leader=self.student_1,
        )
        TeamMembership.objects.create(
            team=pit_team,
            student=self.student_1,
            is_leader=True,
            order=0,
        )
        TeamMembership.objects.create(team=pit_team, student=self.student_2, order=1)

        response = self.client.post(
            '/api/teams/bulk-import/preview/',
            {'teams': [self._bulk_team_row('Team CodeLearners')]},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        row = response.data['rows'][0]
        self.assertFalse(row['ready'])
        self.assertTrue(
            any('already assigned to team' in issue for issue in row['issues']),
        )

    def test_bulk_import_succeeds_after_pit_memberships_cleared(self):
        self._activate_capstone_intake_semester()
        pit_team = StudentTeam.objects.create(
            name='Team CodeLearners',
            project_title='Smart Campus',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )
        TeamMembership.objects.create(
            team=pit_team,
            student=self.student_1,
            is_leader=True,
            order=0,
        )
        TeamMembership.objects.create(team=pit_team, student=self.student_2, order=1)
        TeamMembership.objects.filter(team=pit_team).delete()

        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    self._bulk_team_row(
                        'Team CodeLearners',
                        adviser_id='Ada Lovelace',
                    ),
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 1)
        self.assertEqual(response.data['error_count'], 0)
        capstone = StudentTeam.objects.get(name='Team CodeLearners', level=StudentTeam.LEVEL_3_CAPSTONE)
        self.assertEqual(capstone.semester, self.second_semester)

    def test_bulk_import_error_messages_are_readable_strings(self):
        self._activate_capstone_intake_semester()
        pit_team = StudentTeam.objects.create(
            name='Team Blocked',
            project_title='Blocked',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.second_semester,
            leader=self.student_1,
        )
        TeamMembership.objects.create(
            team=pit_team,
            student=self.student_1,
            is_leader=True,
            order=0,
        )

        response = self.client.post(
            '/api/teams/bulk-import/',
            {'teams': [self._bulk_team_row('Team New', adviser_id='Ada Lovelace')]},
            format='json',
        )

        self.assertEqual(response.data['error_count'], 1)
        errors = response.data['errors'][0]['errors']
        self.assertIsInstance(errors, list)
        self.assertTrue(all(isinstance(item, str) for item in errors))
        self.assertTrue(any('already assigned' in item for item in errors))

    def test_bulk_import_preview_flags_invalid_adviser(self):
        self._activate_capstone_intake_semester()
        User.objects.create_user(
            username='faculty-plain',
            password='pass12345',
            role='faculty',
            first_name='Plain',
            last_name='Faculty',
            is_adviser=False,
        )

        response = self.client.post(
            '/api/teams/bulk-import/preview/',
            {
                'teams': [
                    self._bulk_team_row('Team Valid', 'Ada Lovelace'),
                    self._bulk_team_row('Team None', ''),
                    self._bulk_team_row('Team Bad', 'Nobody Here'),
                    self._bulk_team_row('Team Not Adviser', 'Plain Faculty'),
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        summary = response.data['summary']
        self.assertEqual(summary['total'], 4)
        self.assertEqual(summary['with_adviser'], 1)
        self.assertEqual(summary['without_adviser'], 1)
        self.assertEqual(summary['adviser_invalid'], 2)
        self.assertEqual(summary['ready'], 2)

        rows = {item['team_name']: item for item in response.data['rows']}
        self.assertEqual(rows['Team Valid']['adviser_status'], 'valid')
        self.assertTrue(rows['Team Valid']['ready'])
        self.assertEqual(rows['Team None']['adviser_status'], 'none')
        self.assertTrue(rows['Team None']['ready'])
        self.assertEqual(rows['Team Bad']['adviser_status'], 'user_not_found')
        self.assertFalse(rows['Team Bad']['ready'])
        self.assertEqual(rows['Team Not Adviser']['adviser_status'], 'not_adviser')
        self.assertFalse(rows['Team Not Adviser']['ready'])

    def test_bulk_import_rejects_invalid_adviser_row(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    self._bulk_team_row('Team Bad Adviser', 'Nobody Here'),
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['created_count'], 0)
        self.assertEqual(response.data['error_count'], 1)
        self.assertFalse(StudentTeam.objects.filter(name='Team Bad Adviser').exists())

    def test_admin_bulk_import_without_year_level_infers_from_members(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team Inferred Year',
                        'project_title': 'Inferred',
                        'member_ids': ['Juan Dela Cruz', 'Maria Santos'],
                        'leader_id': 'Juan Dela Cruz',
                        'adviser_id': 'Ada Lovelace',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        team = StudentTeam.objects.get(name='Team Inferred Year')
        self.assertEqual(team.level, StudentTeam.LEVEL_3_CAPSTONE)
        self.assertEqual(team.year_level, '3rd Year')

    def test_admin_bulk_import_with_year_level_only_creates_capstone(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team Capstone CSV',
                        'project_title': 'Capstone CSV',
                        'year_level': '3rd Year',
                        'member_ids': ['Juan Dela Cruz', 'Maria Santos'],
                        'leader_id': 'Juan Dela Cruz',
                        'adviser_id': 'Ada Lovelace',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        team = StudentTeam.objects.get(name='Team Capstone CSV')
        self.assertEqual(team.level, StudentTeam.LEVEL_3_CAPSTONE)

    def test_admin_bulk_import_rejects_pit_level_row(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team PIT Bad',
                        'project_title': 'PIT Bad',
                        'level': StudentTeam.LEVEL_3_PIT,
                        'year_level': '3rd Year',
                        'member_ids': ['Juan Dela Cruz'],
                        'leader_id': 'Juan Dela Cruz',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['error_count'], 1)
        self.assertFalse(StudentTeam.objects.filter(name='Team PIT Bad').exists())

    def test_admin_list_level_filters_capstone_pit_and_all(self):
        pit_team = StudentTeam.objects.create(
            name='Team PIT Only',
            project_title='PIT Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )
        StudentTeam.objects.create(
            name='Team Capstone Only',
            project_title='Capstone Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_2,
        )

        capstone_response = self.client.get('/api/teams/', {'level': 'Capstone'})
        self.assertEqual(capstone_response.status_code, 200)
        capstone_names = [team['name'] for team in capstone_response.data['teams']]
        self.assertIn('Team Capstone Only', capstone_names)
        self.assertNotIn('Team PIT Only', capstone_names)

        pit_response = self.client.get('/api/teams/', {'level': 'PIT'})
        self.assertEqual(pit_response.status_code, 200)
        pit_names = [team['name'] for team in pit_response.data['teams']]
        self.assertIn('Team PIT Only', pit_names)
        self.assertNotIn('Team Capstone Only', pit_names)

        all_response = self.client.get('/api/teams/')
        self.assertEqual(all_response.status_code, 200)
        all_names = [team['name'] for team in all_response.data['teams']]
        self.assertIn('Team Capstone Only', all_names)
        self.assertIn('Team PIT Only', all_names)
        self.assertEqual(all_response.data['counts']['all'], 2)

        detail_response = self.client.get(f'/api/teams/{pit_team.id}/')
        self.assertEqual(detail_response.status_code, 200)
        self.assertEqual(detail_response.data['team']['name'], 'Team PIT Only')

    def test_infer_year_level_rejects_mixed_members(self):
        from .team_levels import infer_year_level_from_members

        student_4th = User.objects.create_user(
            username='2024-0099',
            password='pass12345',
            role='student',
            first_name='Ana',
            last_name='Fourth',
        )
        StudentAcademicRecord.objects.create(
            student=student_4th,
            semester=self.first_semester,
            year_level='4th Year',
        )

        year, issues = infer_year_level_from_members(
            [self.student_1.id, student_4th.id],
            self.first_semester,
            leader_id=self.student_1.id,
        )

        self.assertEqual(year, '')
        self.assertEqual(len(issues), 1)

    def test_admin_bulk_import_rejects_mixed_member_year_levels(self):
        self._activate_capstone_intake_semester()
        student_4th = User.objects.create_user(
            username='2024-0003',
            password='pass12345',
            role='student',
            first_name='Ana',
            last_name='Fourth',
        )
        StudentAcademicRecord.objects.create(
            student=student_4th,
            semester=self.second_semester,
            year_level='4th Year',
        )
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team Mixed Years',
                        'project_title': 'Mixed',
                        'member_ids': ['Juan Dela Cruz', 'Ana Fourth'],
                        'leader_id': 'Juan Dela Cruz',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['error_count'], 1)
        self.assertFalse(StudentTeam.objects.filter(name='Team Mixed Years').exists())

    def test_admin_create_team_without_level_infers_capstone(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/',
            {
                'name': 'Team No Level Field',
                'project_title': 'Auto Level',
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id, self.student_2.id],
                'adviser_id': self.adviser.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['team']['level'], StudentTeam.LEVEL_3_CAPSTONE)
        self.assertEqual(response.data['team']['year_level'], '3rd Year')

    def test_pit_lead_bulk_import_creates_pit_team_for_assigned_year(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-3',
            password='pass12345',
            role='faculty',
            first_name='Pat',
            last_name='Lead',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        self.client.force_authenticate(user=pit_lead)

        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team PIT CSV',
                        'project_title': 'PIT CSV',
                        'member_ids': ['Juan Dela Cruz', 'Maria Santos'],
                        'leader_id': 'Juan Dela Cruz',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        team = StudentTeam.objects.get(name='Team PIT CSV')
        self.assertEqual(team.level, StudentTeam.LEVEL_3_PIT)
        self.assertEqual(team.year_level, '3rd Year')
        self.assertIsNone(team.adviser_id)

    def test_pit_instructor_sees_only_assigned_section_pit_teams(self):
        instructor = User.objects.create_user(
            username='pit-instructor-3a',
            password='pass12345',
            role='faculty',
            first_name='Ivy',
            last_name='Instructor',
        )
        PitInstructorAssignment.objects.create(
            faculty=instructor,
            semester=self.first_semester,
            year_level='3rd Year',
            section='BSIT 3A',
            assigned_by=self.admin,
        )
        team_a = StudentTeam.objects.create(
            name='Team Section A',
            project_title='Section A',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            section='BSIT 3A',
            semester=self.first_semester,
            leader=self.student_1,
        )
        StudentTeam.objects.create(
            name='Team Section B',
            project_title='Section B',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            section='BSIT 3B',
            semester=self.first_semester,
            leader=self.student_2,
        )
        self.client.force_authenticate(user=instructor)

        response = self.client.get('/api/teams/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual([team['id'] for team in response.data['teams']], [team_a.id])

    def test_pit_bulk_import_ignores_adviser_column(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-adviser-skip',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        self.client.force_authenticate(user=pit_lead)

        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team PIT No Adv',
                        'project_title': 'PIT',
                        'member_ids': ['Juan Dela Cruz'],
                        'leader_id': 'Juan Dela Cruz',
                        'adviser_id': 'Ada Lovelace',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        team = StudentTeam.objects.get(name='Team PIT No Adv')
        self.assertIsNone(team.adviser_id)

    def test_no_adviser_count_excludes_pit_teams(self):
        StudentTeam.objects.create(
            name='Team PIT Only',
            project_title='PIT',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )
        StudentTeam.objects.create(
            name='Team Cap No Adv',
            project_title='Cap',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_2,
        )

        response = self.client.get('/api/teams/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['no_adviser'], 1)

    def test_pit_team_defense_context_returns_event_label(self):
        team = StudentTeam.objects.create(
            name='Team PIT Event',
            project_title='PIT Event',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )
        from defense.scheduler.models import DefenseSchedule

        DefenseSchedule.objects.create(
            team=team,
            semester=self.first_semester,
            scope=DefenseSchedule.SCOPE_PIT,
            event_name='Midterm PIT Showcase',
            scheduled_date='2026-08-15',
            start_time='09:00',
            slot_duration=60,
            room='Room 101',
            status=DefenseSchedule.STATUS_SCHEDULED,
        )

        response = self.client.get(f'/api/teams/{team.id}/')

        self.assertEqual(response.status_code, 200)
        context = response.data['team']['defense_context']
        self.assertTrue(context['is_pit'])
        self.assertEqual(context['event_label'], 'Midterm PIT Showcase')

    def test_pit_team_defense_context_does_not_invent_event_label(self):
        team = StudentTeam.objects.create(
            name='Team PIT Blank Event',
            project_title='PIT Blank Event',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )
        from defense.scheduler.models import DefenseSchedule

        schedule = DefenseSchedule.objects.create(
            team=team,
            semester=self.first_semester,
            scope=DefenseSchedule.SCOPE_PIT,
            event_name='Temporary PIT Event',
            scheduled_date='2026-08-15',
            start_time='09:00',
            slot_duration=60,
            room='Room 101',
            status=DefenseSchedule.STATUS_SCHEDULED,
        )
        DefenseSchedule.objects.filter(pk=schedule.pk).update(event_name='')

        response = self.client.get(f'/api/teams/{team.id}/')

        self.assertEqual(response.status_code, 200)
        context = response.data['team']['defense_context']
        self.assertTrue(context['is_pit'])
        self.assertEqual(context['event_label'], '')

    def test_capstone_defense_context_does_not_invent_stage(self):
        team = StudentTeam.objects.create(
            name='Team Cap No Stage',
            project_title='Capstone Without Stage',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )

        response = self.client.get(f'/api/teams/{team.id}/')

        self.assertEqual(response.status_code, 200)
        context = response.data['team']['defense_context']
        self.assertFalse(context['is_pit'])
        self.assertIsNone(context['current_stage'])
        self.assertIsNone(context['ready_for_stage'])

    def test_bulk_import_with_adviser_filter_only_imports_valid_adviser_rows(self):
        self._activate_capstone_intake_semester()
        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'adviser_filter': 'with_adviser',
                'teams': [
                    self._bulk_team_row('Team No Adviser', ''),
                    self._bulk_team_row('Team With Adviser', 'Ada Lovelace'),
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 1)
        self.assertEqual(response.data['skipped_count'], 1)
        self.assertTrue(StudentTeam.objects.filter(name='Team With Adviser').exists())
        self.assertFalse(StudentTeam.objects.filter(name='Team No Adviser').exists())

    def test_student_dashboard_returns_real_team(self):
        team = StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
            adviser=self.adviser,
        )
        TeamMembership.objects.create(team=team, student=self.student_1, is_leader=True, order=0)
        TeamMembership.objects.create(team=team, student=self.student_2, order=1)
        self.client.force_authenticate(user=self.student_1)

        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['team']['name'], 'Team Alpha')
        self.assertEqual(response.data['team']['memberCount'], 2)
        self.assertEqual(response.data['members'][0]['username'], '2024-0001')

    def test_admin_dashboard_counts_teams(self):
        StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['total_teams'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)

    def test_rollover_advances_capstone_team_after_phase_six(self):
        record = StudentAcademicRecord.objects.create(
            student=self.student_1,
            semester=self.second_semester,
            year_level=StudentAcademicRecord.THIRD_YEAR,
        )
        team = StudentTeam.objects.create(
            name='Team Capstone',
            project_title='Capstone Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.second_semester,
            leader=self.student_1,
        )
        TeamMembership.objects.create(team=team, student=self.student_1, is_leader=True, order=0)

        response = self.client.post(
            '/api/users/academic-records/rollover/',
            {'actions': [{'record_id': record.id, 'action': 'promote'}]},
            format='json',
        )

        team.refresh_from_db()
        self.assertIn(response.status_code, (200, 201))
        self.assertEqual(response.data['team_updates'], 1)
        self.assertEqual(team.level, StudentTeam.LEVEL_4_CAPSTONE)
        self.assertEqual(team.capstone_phase, StudentTeam.PHASE_ACTIVE)

    def test_weekly_progress_list_filters_by_team_id(self):
        from datetime import date

        team_a = StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Alpha',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )
        team_b = StudentTeam.objects.create(
            name='Team Beta',
            project_title='Beta',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.first_semester,
            leader=self.student_2,
        )
        TeamMembership.objects.create(
            team=team_a, student=self.student_1, is_leader=True, order=0,
        )
        TeamMembership.objects.create(
            team=team_b, student=self.student_2, is_leader=True, order=0,
        )
        WeeklyProgressReport.objects.create(
            student=self.student_1,
            team=team_a,
            week_number=1,
            report_date=date(2026, 5, 10),
        )
        WeeklyProgressReport.objects.create(
            student=self.student_2,
            team=team_b,
            week_number=1,
            report_date=date(2026, 5, 11),
        )

        response = self.client.get(
            f'/api/teams/weekly-progress/?team_id={team_a.id}',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['reports'][0]['team'], team_a.id)

    def test_pit_team_leader_cannot_submit_weekly_progress(self):
        pit_team = StudentTeam.objects.create(
            name='PIT Team',
            project_title='PIT Project',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.first_semester,
            leader=self.student_1,
        )
        TeamMembership.objects.create(
            team=pit_team, student=self.student_1, is_leader=True, order=0,
        )
        self.client.force_authenticate(user=self.student_1)
        response = self.client.post(
            '/api/teams/weekly-progress/',
            {
                'week_number': 1,
                'report_date': '2026-05-10',
                'accomplishments': '[]',
                'contributions': '[]',
                'issues': '[]',
                'plans': '[]',
            },
            format='multipart',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('capstone', response.data['detail'].lower())

    def test_pit_lead_import_mismatched_student_year_level_is_rejected(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-1',
            password='pass12345',
            role='faculty',
            first_name='Pat',
            last_name='Lead',
            is_pit_lead=True,
            pit_lead_year='1st Year',
        )
        self.client.force_authenticate(user=pit_lead)

        response = self.client.post(
            '/api/teams/bulk-import/',
            {
                'teams': [
                    {
                        'team_name': 'Team PIT Mismatch',
                        'project_title': 'PIT Mismatch',
                        'member_ids': ['Juan Dela Cruz'],
                        'leader_id': 'Juan Dela Cruz',
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['created_count'], 0)
        self.assertEqual(response.data['error_count'], 1)
        self.assertTrue(
            any('PIT scope is 1st Year' in issue for error in response.data['errors'] for issue in error['errors'])
        )

    def test_pit_lead_create_mismatched_student_year_level_is_rejected(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-mismatch-manual',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='1st Year',
        )
        self.client.force_authenticate(user=pit_lead)

        response = self.client.post(
            '/api/teams/',
            {
                'name': 'Manual PIT Mismatch',
                'project_title': 'Manual PIT Mismatch',
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('member_ids', response.data)
        self.assertTrue(
            any('PIT scope is 1st Year' in msg for msg in response.data['member_ids'])
        )

    def test_admin_cannot_create_invalid_program_level_combination(self):
        self._activate_capstone_intake_semester()
        record = StudentAcademicRecord.objects.get(
            student=self.student_1,
            semester=self.second_semester,
        )
        record.year_level = '1st Year'
        record.save(update_fields=['year_level'])

        response = self.client.post(
            '/api/teams/',
            {
                'name': 'Invalid Capstone Level',
                'project_title': 'Invalid Level',
                'leader_id': self.student_1.id,
                'member_ids': [self.student_1.id],
                'adviser_id': self.adviser.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('level', response.data)
        self.assertIn('not a valid team program level', response.data['level'][0])

