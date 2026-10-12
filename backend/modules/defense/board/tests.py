from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.stages.models import DefenseStage
from student_teams.models import StudentTeam, TeamMembership


User = get_user_model()


class DefenseBoardApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.pit_lead = User.objects.create_user(
            username='pit-lead',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        self.panelist = User.objects.create_user(
            username='panel-1',
            password='pass12345',
            role='faculty',
            first_name='Grace',
            last_name='Hopper',
            is_panelist=True,
        )
        self.student = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
        )
        self.pit_student = User.objects.create_user(
            username='2025-0001',
            password='pass12345',
            role='student',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        self.first_semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
        )
        self.stage = DefenseStage.objects.get(label='Project Proposal')
        self.capstone_team = StudentTeam.objects.create(
            name='Team VaultSync',
            project_title='Cloud File Sync',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            ready_for_stage=self.stage.label,
        )
        TeamMembership.objects.create(team=self.capstone_team, student=self.student, is_leader=True)
        self.pit_team = StudentTeam.objects.create(
            name='Team Circuit',
            project_title='Circuit Trainer',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.first_semester,
            leader=self.pit_student,
        )
        TeamMembership.objects.create(team=self.pit_team, student=self.pit_student, is_leader=True)
        self.capstone_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.capstone_team,
            defense_stage=self.stage,
            scheduled_date='2099-05-15',
            start_time='08:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        self.pit_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.first_semester,
            team=self.pit_team,
            event_name='PIT Expo',
            scheduled_date='2099-05-16',
            start_time='09:00',
            slot_duration=45,
            room='Lab 2',
            status=DefenseSchedule.STATUS_DONE,
            created_by=self.admin,
        )
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=self.panelist)
        SchedulePanelist.objects.create(schedule=self.pit_schedule, panelist=self.panelist)
        self.client.force_authenticate(user=self.admin)

    def test_deletion_blockers_are_computed_once_per_schedule(self):
        from unittest.mock import patch
        from defense.scheduler.services import deletion_blockers
        with patch('defense.scheduler.services.deletion_blockers', wraps=deletion_blockers) as checks:
            response = self.client.get('/api/defense/board/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(checks.call_count, len(response.data['schedules']))
        for row in response.data['schedules']:
            self.assertEqual(row['can_delete'], not row['deletion_blockers'])

    def test_students_and_advisers_see_upcoming_defenses_without_creating_minutes(self):
        from defense.minutes.models import DefenseMinutes
        adviser = User.objects.create_user(username='record-adviser', role='faculty')
        documenter = User.objects.create_user(username='record-documenter', role='faculty', is_documenter=True)
        self.capstone_team.adviser = adviser
        self.capstone_team.save(update_fields=['adviser'])
        self.capstone_schedule.documenter = documenter
        self.capstone_schedule.save(update_fields=['documenter'])
        SchedulePanelist.objects.filter(schedule=self.capstone_schedule).update(is_chair=True)
        for actor in (self.student, adviser):
            self.client.force_authenticate(actor)
            response = self.client.get('/api/defense/board/', {'scope': 'capstone'})
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(len(response.data['schedules']), 1)
            record = response.data['schedules'][0]
            self.assertEqual(record['id'], self.capstone_schedule.pk)
            self.assertIsNone(record['minutes_status'])
            self.assertEqual(record['display_status'], 'scheduled')
            self.assertTrue(record['panelists'][0]['is_chair'])
            self.assertEqual(record['documenter'], documenter.pk)
        self.assertFalse(DefenseMinutes.objects.exists())
        self.client.force_authenticate(self.student)
        team = self.client.get('/api/dashboards/student/').data['team']
        self.assertEqual(team['project_version'], self.capstone_team.project_version)
        self.assertEqual(team['semester_id'], self.capstone_team.semester_id)
        from repository.deliverables.services import team_payload
        dossier = team_payload(self.capstone_team)
        self.assertEqual(dossier['project_version'], self.capstone_team.project_version)
        self.assertEqual(dossier['semester_id'], self.capstone_team.semester_id)

    def test_record_keeps_legacy_and_inactive_external_participants_without_duplicates(self):
        from user_management.models import ExternalEvaluator, GuestPanelistCode
        evaluator = ExternalEvaluator.objects.create(name='Dr. Lina Santos', status='approved')
        invitation = GuestPanelistCode.objects.create(evaluator=evaluator, guest_name=evaluator.name,
            defense_schedule=self.capstone_schedule, is_active=False)
        invitation.schedules.add(self.capstone_schedule)
        GuestPanelistCode.objects.create(guest_name='Prof. Rivera', defense_schedule=self.capstone_schedule,
            is_active=False)
        self.client.force_authenticate(self.student)
        response = self.client.get('/api/defense/board/', {'scope': 'capstone'})
        self.assertEqual(response.status_code, 200)
        panel = response.data['schedules'][0]['external_evaluators']
        self.assertEqual([person['name'] for person in panel], ['Dr. Lina Santos', 'Prof. Rivera'])
        self.assertTrue(all(not person['is_active'] for person in panel))

    def test_recorded_verdict_and_revision_requirements_do_not_wait_for_publication_or_minutes(self):
        from datetime import date
        from grading.grades.models import TeamGrade
        from grading.grades.services import GradeContextService
        grade, _, _ = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)
        TeamGrade.objects.filter(pk=grade.pk).update(verdict='approved_with_revisions',
            verdict_remarks='Calibrate the soil sensors.', revision_deadline=date(2099, 5, 22))
        DefenseSchedule.objects.filter(pk=self.capstone_schedule.pk).update(status='done')
        self.client.force_authenticate(self.student)
        response = self.client.get('/api/defense/board/', {'scope': 'capstone'})
        record = response.data['schedules'][0]
        self.assertEqual(record['display_status'], 'revisions_pending')
        self.assertIsNone(record['minutes_status'])
        self.assertEqual(record['assessment']['verdict'], 'approved_with_revisions')
        self.assertEqual(record['assessment']['revision_deadline'], '2099-05-22')
        self.assertEqual(record['assessment']['verdict_remarks'], 'Calibrate the soil sensors.')
        self.assertIsNone(record['assessment']['published_result'])
        self.assertFalse(record['assessment']['is_completed'])

    def test_record_uses_the_earlier_attempt_snapshot_instead_of_current_stage_grade(self):
        from datetime import date
        from grading.grades.models import GradeAttemptHistory, TeamGrade
        from grading.grades.services import GradeContextService
        grade, _, _ = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)
        GradeAttemptHistory.objects.create(team_grade=grade, schedule=self.capstone_schedule,
            attempt_number=1, verdict='for_redefense', verdict_remarks='Repeat the field evaluation.',
            revision_deadline=date(2099, 5, 22))
        TeamGrade.objects.filter(pk=grade.pk).update(schedule=None, verdict='approved', status='published', final_grade=80)
        DefenseSchedule.objects.filter(pk=self.capstone_schedule.pk).update(status='archived')
        self.client.force_authenticate(self.student)
        response = self.client.get('/api/defense/board/', {'scope': 'capstone'})
        record = response.data['schedules'][0]
        self.assertEqual(record['display_status'], 'archived')
        self.assertEqual(record['assessment']['verdict'], 'for_redefense')
        self.assertEqual(record['assessment']['revision_deadline'], '2099-05-22')
        self.assertIsNone(record['assessment']['grade_status'])
        self.assertIsNone(record['assessment']['published_result'])

    def test_board_lists_schedules_with_counts_and_stage_options(self):
        response = self.client.get('/api/defense/board/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 2)
        self.assertEqual(response.data['counts']['scheduled'], 1)
        self.assertEqual(response.data['counts']['done'], 0)
        self.assertEqual(response.data['counts']['assessed'], 1)
        self.assertIn('Project Proposal', response.data['stage_options'])
        self.assertIn('PIT Expo', response.data['stage_options'])

    def test_board_filters_by_stage_status_and_search(self):
        response = self.client.get(
            '/api/defense/board/',
            {'stage': 'Project Proposal', 'status': 'scheduled', 'search': 'Vault'},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['filtered'], 1)
        self.assertEqual(response.data['schedules'][0]['team_name'], 'Team VaultSync')

    def test_pit_lead_only_sees_assigned_year_pit_schedules(self):
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/defense/board/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 1)
        self.assertEqual(response.data['schedules'][0]['team_name'], 'Team Circuit')

    def test_board_can_update_status_and_delete_schedule(self):
        update = self.client.patch(
            f'/api/defense/board/{self.capstone_schedule.id}/',
            {'status': DefenseSchedule.STATUS_DONE},
            format='json',
        )
        self.pit_schedule.status = DefenseSchedule.STATUS_SCHEDULED
        self.pit_schedule.scheduled_date = '2099-05-16'
        self.pit_schedule.save()
        delete = self.client.delete(f'/api/defense/board/{self.pit_schedule.id}/')
        self.capstone_schedule.status = DefenseSchedule.STATUS_DONE
        self.capstone_schedule.save()
        delete_completed = self.client.delete(f'/api/defense/board/{self.capstone_schedule.id}/')

        self.assertEqual(update.status_code, 400)
        self.assertEqual(delete.status_code, 200)
        self.assertFalse(DefenseSchedule.objects.filter(pk=self.pit_schedule.id).exists())
        self.assertEqual(delete_completed.status_code, 409)

    def test_admin_dashboard_reports_phase_ten(self):
        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['migration']['phase'], 15)

    def test_pit_lead_only_sees_assigned_year_pit_schedules_with_unnormalized_year(self):
        unnormalized_pit_lead = User.objects.create_user(
            username='pit-lead-unnorm',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year=' 2nd Year ',
        )
        self.client.force_authenticate(user=unnormalized_pit_lead)

        response = self.client.get('/api/defense/board/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 1)
        self.assertEqual(response.data['schedules'][0]['team_name'], 'Team Circuit')

    def test_stage_options_are_deduplicated(self):
        # Create another schedule with the exact same stage as capstone_schedule
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.capstone_team,
            defense_stage=self.stage,
            scheduled_date='2026-05-18',
            start_time='10:00',
            slot_duration=60,
            room='Room 302',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )

        response = self.client.get('/api/defense/board/')
        self.assertEqual(response.status_code, 200)
        stage_opts = response.data['stage_options']
        self.assertEqual(len(stage_opts), len(set(stage_opts)))
        self.assertEqual(stage_opts.count('Project Proposal'), 1)
