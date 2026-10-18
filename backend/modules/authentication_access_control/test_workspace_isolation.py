"""One faculty account's independent roles never widen a selected workspace."""
from datetime import date

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.workspaces import (
    workspace_grades_for, workspace_schedules_for, workspace_teams_for,
)
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig, SchedulePanelist
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from student_teams.models import StudentTeam, TeamMembership
from user_management.models import SectionInstructorAssignment


class MultiRoleWorkspaceTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.user = User.objects.create_user(username='multi-workspace-faculty', role='faculty',
            is_pit_lead=True, pit_lead_year='3rd Year', is_adviser=True,
            is_panelist=True, is_documenter=True, is_uploader=True)
        self.semester = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2094-2095'),
            label=Semester.FIRST, is_active=True)
        self.stage = DefenseStage.objects.create(label='Workspace Capstone Hearing')
        self.rows = {}
        for key, year, scope in [('operations', '3rd Year', 'pit'),
                                 ('instructor', '2nd Year', 'pit'),
                                 ('panelist', '1st Year', 'pit'),
                                 ('adviser', '4th Year', 'capstone'),
                                 ('documenter', '4th Year', 'capstone')]:
            student = User.objects.create_user(username=f'workspace-{key}', role='student')
            team = StudentTeam.objects.create(name=f'Workspace {key}', leader=student,
                semester=self.semester, year_level=year,
                level=f'{year} {"PIT" if scope == "pit" else "Capstone"}',
                section=f'BSIT-{key}', adviser=self.user if key == 'adviser' else None)
            TeamMembership.objects.create(team=team, student=student, is_leader=True)
            event = PitEventGradingConfig.objects.create(semester=self.semester,
                year_level=year, event_name=f'Workspace {key} event') if scope == 'pit' else None
            schedule = DefenseSchedule.objects.create(team=team, semester=self.semester,
                scope=scope, event_name=event.event_name if event else '',
                defense_stage=self.stage if scope == 'capstone' else None,
                documenter=self.user if key == 'documenter' else None,
                scheduled_date=date(2094, 10, 20), start_time='08:00', room='Room 301')
            grade = TeamGrade.objects.create(team=team, semester=self.semester,
                scope=scope, schedule=schedule, pit_event_config=event,
                panel_weight=80 if scope == 'pit' else 50,
                peer_weight=20, adviser_weight=0 if scope == 'pit' else 30,
                defense_stage=self.stage if scope == 'capstone' else None)
            self.rows[key] = (team, schedule, grade)
        SectionInstructorAssignment.objects.create(faculty=self.user, semester=self.semester,
            year_level='2nd Year', section='BSIT-instructor', is_active=True)
        SchedulePanelist.objects.create(schedule=self.rows['panelist'][1], panelist=self.user)
        self.client.force_authenticate(self.user)

    def test_each_schedule_workspace_keeps_only_its_own_assignment(self):
        for workspace, (_, schedule, _) in self.rows.items():
            with self.subTest(workspace=workspace):
                self.assertEqual(set(workspace_schedules_for(self.user, workspace).values_list('pk', flat=True)),
                                 {schedule.pk})
                for endpoint in ('board', 'schedules'):
                    response = self.client.get(f'/api/defense/{endpoint}/', {'workspace': workspace})
                    self.assertEqual(response.status_code, 200, response.data)
                    self.assertEqual({row['id'] for row in response.data['schedules']}, {schedule.pk})
                    self.assertEqual(response.data['counts']['all'], 1)
                    if endpoint == 'schedules' and workspace == 'operations':
                        self.assertEqual({row['id'] for row in response.data['teams']},
                                         {self.rows['operations'][0].pk})
                    elif endpoint == 'schedules':
                        self.assertNotIn('teams', response.data)
                    if endpoint == 'board' and workspace != 'operations':
                        self.assertFalse(any(row['can_manage'] for row in response.data['schedules']))

    def test_team_and_grade_workspaces_do_not_union_roles_or_uploader_access(self):
        for workspace in ('operations', 'adviser', 'instructor'):
            team, _, grade = self.rows[workspace]
            with self.subTest(workspace=workspace):
                self.assertEqual(set(workspace_teams_for(self.user, workspace).values_list('pk', flat=True)), {team.pk})
                self.assertEqual(set(workspace_grades_for(self.user, workspace).values_list('pk', flat=True)), {grade.pk})
                for path, key in (('/api/teams/', 'teams'), ('/api/grading/grades/', 'grades')):
                    response = self.client.get(path, {'workspace': workspace})
                    self.assertEqual(response.status_code, 200, response.data)
                    self.assertEqual({row['id'] for row in response.data[key]},
                                     {team.pk if key == 'teams' else grade.pk})
                    if key == 'teams' and workspace != 'operations':
                        self.assertEqual(response.data['students'], [])
                        self.assertEqual(response.data['advisers'], [])
        panel_grade = self.rows['panelist'][2]
        self.assertEqual(set(workspace_grades_for(self.user, 'panelist').values_list('pk', flat=True)), {panel_grade.pk})
        self.assertFalse(workspace_grades_for(self.user, 'documenter').exists())

    def test_explicit_workspace_applies_to_direct_record_lookups_and_writes(self):
        team, schedule, grade = self.rows['instructor']
        self.assertEqual(self.client.get(f'/api/teams/{team.pk}/', {'workspace': 'operations'}).status_code, 404)
        self.assertEqual(self.client.patch(f'/api/teams/{team.pk}/?workspace=operations',
            {'name': 'Wrong workspace'}, format='json').status_code, 404)
        self.assertEqual(self.client.get(f'/api/grading/grades/{grade.pk}/', {'workspace': 'operations'}).status_code, 404)
        self.assertEqual(self.client.get(f'/api/grading/grades/{grade.pk}/', {'workspace': 'instructor'}).status_code, 200)
        self.assertEqual(self.client.post(f'/api/grading/grades/{grade.pk}/publish/', {}, format='json').status_code, 404)
        team.refresh_from_db()
        self.assertEqual(team.name, 'Workspace instructor')
        grade.refresh_from_db()
        self.assertNotEqual(grade.status, TeamGrade.STATUS_PUBLISHED)

    def test_unknown_workspace_and_missing_lead_year_fail_closed(self):
        for selector in (workspace_teams_for, workspace_schedules_for, workspace_grades_for):
            self.assertFalse(selector(self.user, 'unknown-role').exists())
        self.user.pit_lead_year = ''
        self.user.save(update_fields=['pit_lead_year'])
        for selector in (workspace_teams_for, workspace_schedules_for, workspace_grades_for):
            self.assertFalse(selector(self.user, 'operations').exists())
        self.assertEqual(workspace_schedules_for(self.user, 'instructor').count(), 1)
        self.assertEqual(workspace_schedules_for(self.user, 'panelist').count(), 1)

    def test_deliverable_workspaces_isolate_teams_events_and_actions(self):
        for workspace in ('operations', 'adviser', 'instructor'):
            team, _, grade = self.rows[workspace]
            scope = 'pit' if team.is_pit else 'capstone'
            response = self.client.get('/api/repository/deliverables/',
                {'workspace': workspace, 'scope': scope})
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual({row['id'] for row in response.data['teams']}, {team.pk})
            if workspace == 'instructor':
                self.assertEqual(response.data['stage_options'], [grade.pit_event_config.event_name])
        instructor_team, _, instructor_grade = self.rows['instructor']
        response = self.client.post('/api/repository/deliverables/endorse/?workspace=operations',
            {'team_id': instructor_team.pk,
             'stage_label': instructor_grade.pit_event_config.event_name}, format='json')
        self.assertEqual(response.status_code, 404, response.data)
        # A Lead's cohort authority cannot be borrowed by an Instructor request.
        own = self.rows['operations'][1]
        response = self.client.post('/api/defense/board/operations/?workspace=instructor',
            {'action': 'preview_update', 'anchor_id': own.pk,
             'changes': {'room': 'Wrong workspace'}}, format='json')
        self.assertEqual(response.status_code, 403, response.data)
