from decimal import Decimal

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from student_teams.models import StudentTeam, TeamMembership
from user_management.academic_records.models import StudentAcademicRecord


User = get_user_model()


class DashboardApiTests(APITestCase):
    def test_admin_dashboard_uses_django_user_counts(self):
        admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
        )
        User.objects.create_user(username='student-1', password='pass12345', role='student')
        User.objects.create_user(username='faculty-1', password='pass12345', role='faculty')

        self.client.force_authenticate(user=admin)
        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['total_students'], 1)
        self.assertEqual(response.data['stats']['total_faculty'], 2)
        self.assertEqual(response.data['stats']['total_teams'], 0)
        self.assertEqual(response.data['stats']['upcoming_defenses'], 0)
        self.assertNotEqual(response.data['stats']['total_students'], 150)

    def test_faculty_dashboard_reflects_request_user_roles(self):
        faculty = User.objects.create_user(
            username='faculty-1',
            password='pass12345',
            role='faculty',
            is_panelist=True,
            is_pit_lead=True,
            pit_lead_year='3rd Year',
            is_documenter=True,
        )

        self.client.force_authenticate(user=faculty)
        response = self.client.get('/api/dashboards/faculty/')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['roles']['panelist'])
        self.assertTrue(response.data['roles']['pit_lead'])
        self.assertEqual(response.data['roles']['pit_lead_year'], '3rd Year')
        self.assertTrue(response.data['roles']['documenter'])
        self.assertEqual(response.data['advised_teams'], [])
        self.assertIsNotNone(response.data['pit_lead_overview'])
        self.assertIn('stats', response.data['pit_lead_overview'])

    def test_pure_adviser_has_no_pit_lead_overview(self):
        adviser = User.objects.create_user(
            username='adviser-only',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )
        self.client.force_authenticate(user=adviser)
        response = self.client.get('/api/dashboards/faculty/')

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.data['pit_lead_overview'])

    def test_pit_lead_overview_counts_year_scoped_pit_teams(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-3',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        student = User.objects.create_user(
            username='pit-student',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        StudentAcademicRecord.objects.create(
            student=student,
            semester=semester,
            year_level='3rd Year',
        )
        StudentTeam.objects.create(
            name='PIT Alpha',
            project_title='Smart Campus',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=semester,
            leader=student,
        )
        StudentTeam.objects.create(
            name='Capstone Beta',
            project_title='Other Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=semester,
            leader=student,
        )

        self.client.force_authenticate(user=pit_lead)
        response = self.client.get('/api/dashboards/faculty/')

        self.assertEqual(response.status_code, 200)
        overview = response.data['pit_lead_overview']
        self.assertIsNotNone(overview)
        self.assertEqual(overview['stats']['pit_teams'], 1)
        self.assertEqual(overview['stats']['students_in_cohort'], 1)
        self.assertEqual(len(overview['recent_pit_teams']), 1)
        self.assertEqual(len(response.data['pit_teams']), 1)
        self.assertEqual(len(overview['cohort_preview']), 1)
        self.assertEqual(overview['cohort_preview'][0]['name'], 'pit-student')

    def test_pit_lead_cohort_lists_year_scoped_students_with_team_status(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-cohort',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        assigned = User.objects.create_user(
            username='third-year-a',
            password='pass12345',
            role='student',
            first_name='Alex',
            last_name='Assigned',
        )
        unassigned = User.objects.create_user(
            username='third-year-b',
            password='pass12345',
            role='student',
            first_name='Blake',
            last_name='Open',
        )
        other_year = User.objects.create_user(
            username='fourth-year-student',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        for student, year in (
            (assigned, '3rd Year'),
            (unassigned, '3rd Year'),
            (other_year, '4th Year'),
        ):
            StudentAcademicRecord.objects.create(
                student=student,
                semester=semester,
                year_level=year,
            )
        pit_team = StudentTeam.objects.create(
            name='PIT Cohort Team',
            project_title='IoT Lab',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=semester,
            leader=assigned,
        )
        TeamMembership.objects.create(team=pit_team, student=assigned, is_leader=True)

        self.client.force_authenticate(user=pit_lead)
        response = self.client.get('/api/dashboards/pit-lead/cohort/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['pit_lead_year'], '3rd Year')
        self.assertEqual(response.data['counts']['all'], 2)
        self.assertEqual(response.data['counts']['on_team'], 1)
        self.assertEqual(response.data['counts']['unassigned'], 1)

        by_username = {row['username']: row for row in response.data['students']}
        self.assertEqual(by_username['third-year-a']['team_status'], 'on_team')
        self.assertEqual(by_username['third-year-a']['team_name'], 'PIT Cohort Team')
        self.assertEqual(by_username['third-year-b']['team_status'], 'unassigned')
        self.assertNotIn('fourth-year-student', by_username)

    def test_pit_lead_cohort_search_and_team_status_filters(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-filter',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        student = User.objects.create_user(
            username='second-year-student',
            password='pass12345',
            role='student',
            first_name='Casey',
            last_name='Searchable',
            email='casey@school.edu',
        )
        school_year = SchoolYear.objects.create(label='2027-2028')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        StudentAcademicRecord.objects.create(
            student=student,
            semester=semester,
            year_level='2nd Year',
        )

        self.client.force_authenticate(user=pit_lead)
        search_response = self.client.get(
            '/api/dashboards/pit-lead/cohort/',
            {'search': 'casey@school.edu'},
        )
        self.assertEqual(search_response.status_code, 200)
        self.assertEqual(len(search_response.data['students']), 1)

        filtered_response = self.client.get(
            '/api/dashboards/pit-lead/cohort/',
            {'team_status': 'unassigned'},
        )
        self.assertEqual(filtered_response.status_code, 200)
        self.assertEqual(len(filtered_response.data['students']), 1)
        self.assertEqual(filtered_response.data['students'][0]['team_status'], 'unassigned')

    def test_pit_lead_cohort_forbidden_for_non_pit_lead(self):
        adviser = User.objects.create_user(
            username='adviser-cohort',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )
        self.client.force_authenticate(user=adviser)
        response = self.client.get('/api/dashboards/pit-lead/cohort/')
        self.assertEqual(response.status_code, 403)

    def test_pit_lead_rollover_creates_scoped_capstone_intake_records_only(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-rollover',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        student = User.objects.create_user(
            username='third-year-rollover',
            password='pass12345',
            role='student',
            first_name='Rhea',
            last_name='Rollover',
        )
        other_year = User.objects.create_user(
            username='second-year-nope',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        first_semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        second_semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            capstone_team_creation_enabled=True,
            capstone_program_phase=Semester.PHASE_CAPSTONE_1,
        )
        source_record = StudentAcademicRecord.objects.create(
            student=student,
            semester=first_semester,
            year_level='3rd Year',
            section='BSIT-3A',
        )
        StudentAcademicRecord.objects.create(
            student=other_year,
            semester=first_semester,
            year_level='2nd Year',
            section='BSIT-2A',
        )
        pit_team = StudentTeam.objects.create(
            name='PIT Rollover Team',
            project_title='Scoped Records',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=first_semester,
            leader=student,
        )
        TeamMembership.objects.create(team=pit_team, student=student, is_leader=True)

        self.client.force_authenticate(user=pit_lead)
        preview = self.client.get('/api/dashboards/pit-lead/cohort/rollover-preview/')
        response = self.client.post('/api/dashboards/pit-lead/cohort/rollover/', {}, format='json')
        repeat = self.client.post('/api/dashboards/pit-lead/cohort/rollover/', {}, format='json')

        self.assertEqual(preview.status_code, 200)
        self.assertEqual(preview.data['source_semester']['id'], first_semester.id)
        self.assertEqual(preview.data['target_semester']['id'], second_semester.id)
        self.assertTrue(preview.data['is_capstone_intake'])
        self.assertEqual(preview.data['counts']['will_create'], 1)

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 1)
        target_record = StudentAcademicRecord.objects.get(
            student=student,
            semester=second_semester,
        )
        self.assertEqual(target_record.year_level, '3rd Year')
        self.assertEqual(target_record.section, 'BSIT-3A')
        self.assertEqual(target_record.rolled_from, source_record)
        self.assertFalse(
            StudentAcademicRecord.objects.filter(
                student=other_year,
                semester=second_semester,
            ).exists(),
        )
        self.assertTrue(
            TeamMembership.objects.filter(student=student, team=pit_team).exists(),
        )
        self.assertEqual(repeat.status_code, 200)
        self.assertEqual(repeat.data['created_count'], 0)
        self.assertEqual(repeat.data['skipped_count'], 1)

    def test_pit_lead_rollover_forbidden_for_non_pit_lead(self):
        adviser = User.objects.create_user(
            username='adviser-rollover',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )
        self.client.force_authenticate(user=adviser)
        response = self.client.get('/api/dashboards/pit-lead/cohort/rollover-preview/')
        self.assertEqual(response.status_code, 403)

    def test_pit_lead_rollover_promotes_to_next_year_level_across_school_year(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-year-boundary',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        student = User.objects.create_user(
            username='second-year-rollover',
            password='pass12345',
            role='student',
        )
        source_year = SchoolYear.objects.create(label='2026-2027')
        target_year = SchoolYear.objects.create(label='2027-2028')
        source_semester = Semester.objects.create(
            school_year=source_year,
            label=Semester.SECOND,
            is_active=True,
        )
        target_semester = Semester.objects.create(
            school_year=target_year,
            label=Semester.FIRST,
        )
        StudentAcademicRecord.objects.create(
            student=student,
            semester=source_semester,
            year_level='2nd Year',
            section='BSIT-2A',
        )

        self.client.force_authenticate(user=pit_lead)
        preview = self.client.get('/api/dashboards/pit-lead/cohort/rollover-preview/')
        response = self.client.post('/api/dashboards/pit-lead/cohort/rollover/', {}, format='json')

        self.assertEqual(preview.status_code, 200)
        self.assertEqual(preview.data['target_semester']['id'], target_semester.id)
        self.assertEqual(preview.data['target_year_level'], '3rd Year')
        self.assertEqual(response.status_code, 201)
        self.assertTrue(
            StudentAcademicRecord.objects.filter(
                student=student,
                semester=target_semester,
                year_level='3rd Year',
                section='BSIT-2A',
            ).exists(),
        )

    def test_student_dashboard_returns_phase_two_empty_team_contract(self):
        student = User.objects.create_user(
            username='student-1',
            password='pass12345',
            role='student',
        )

        self.client.force_authenticate(user=student)
        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.data['team'])
        self.assertEqual(response.data['members'], [])
        self.assertFalse(response.data['peerEvalEnabled'])

    def test_student_dashboard_does_not_invent_capstone_stage(self):
        student = User.objects.create_user(
            username='student-no-stage',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        team = StudentTeam.objects.create(
            name='Capstone No Stage Team',
            project_title='No Stage Yet',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=semester,
            leader=student,
        )
        TeamMembership.objects.create(team=team, student=student, is_leader=True)

        self.client.force_authenticate(user=student)
        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.data['team']['currentStage'])
        self.assertIsNone(response.data['team']['readyForStage'])

    def test_student_dashboard_does_not_show_previous_stage_grade_for_current_schedule(self):
        student = User.objects.create_user(
            username='student-current-stage',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        concept_stage = DefenseStage.objects.get(label='Concept Proposal')
        project_stage = DefenseStage.objects.get(label='Project Proposal')
        team = StudentTeam.objects.create(
            name='Capstone Stage Team',
            project_title='Stage Scoped Grades',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=semester,
            leader=student,
            ready_for_stage=project_stage.label,
        )
        TeamMembership.objects.create(team=team, student=student, is_leader=True)
        TeamGrade.objects.create(
            team=team,
            semester=semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label=concept_stage.label,
            panel_score=Decimal('91.00'),
            adviser_score=Decimal('90.00'),
            peer_score=Decimal('92.00'),
            status=TeamGrade.STATUS_PUBLISHED,
        )
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=semester,
            team=team,
            defense_stage=project_stage,
            scheduled_date='2026-05-27',
            start_time='08:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_SCHEDULED,
        )

        self.client.force_authenticate(user=student)
        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['schedule']['stage'], project_stage.label)
        self.assertIsNone(response.data['grades'])

    def test_student_cannot_get_admin_dashboard(self):
        student = User.objects.create_user(
            username='student-admin-block',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)
        response = self.client.get('/api/dashboards/admin/')
        self.assertEqual(response.status_code, 403)

    def test_student_cannot_get_faculty_dashboard(self):
        student = User.objects.create_user(
            username='student-faculty-block',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)
        response = self.client.get('/api/dashboards/faculty/')
        self.assertEqual(response.status_code, 403)

    def test_multi_hat_faculty_can_access_faculty_and_panelist_dashboards(self):
        faculty = User.objects.create_user(
            username='multi-hat-faculty',
            password='pass12345',
            role='faculty',
            is_panelist=True,
            is_adviser=True,
        )
        self.client.force_authenticate(user=faculty)

        faculty_response = self.client.get('/api/dashboards/faculty/')
        panelist_response = self.client.get('/api/dashboards/panelist/')
        admin_response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(faculty_response.status_code, 200)
        self.assertEqual(panelist_response.status_code, 200)
        self.assertEqual(admin_response.status_code, 403)

    def test_panelist_dashboard_returns_empty_phase_two_collections(self):
        panelist = User.objects.create_user(
            username='panelist-1',
            password='pass12345',
            role='faculty',
            is_panelist=True,
        )

        self.client.force_authenticate(user=panelist)
        response = self.client.get('/api/dashboards/panelist/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['upcoming_defenses'], [])
        self.assertEqual(response.data['assignments'], [])
        self.assertEqual(response.data['results'], [])
