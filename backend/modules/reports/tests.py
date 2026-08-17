from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from academic_period_management.models import SchoolYear, Semester
from student_teams.models import StudentTeam, TeamMembership
from grading.grades.models import TeamGrade
from defense.stages.models import DefenseStage

User = get_user_model()

class ReportsApiTests(APITestCase):
    def setUp(self):
        # 1. Users
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
            first_name='Alan',
            last_name='Turing',
            is_adviser=True,
        )
        self.pit_lead = User.objects.create_user(
            username='pit-lead-1',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        self.student = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
        )

        # 2. Semester Setup
        self.school_year, _ = SchoolYear.objects.get_or_create(label='2026-2027')
        self.semester, _ = Semester.objects.get_or_create(
            school_year=self.school_year,
            label=Semester.FIRST,
            defaults={'is_active': True},
        )

        # 3. Defense Stage (needed for TeamGrade)
        self.stage, _ = DefenseStage.objects.get_or_create(
            label='Concept Proposal',
            defaults={'is_active': True, 'display_order': 1}
        )

        # 4. Student Teams
        self.team_advised = StudentTeam.objects.create(
            name='Team Advised',
            project_title='Adviser\'s Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.adviser,
        )
        self.team_other = StudentTeam.objects.create(
            name='Team Other',
            project_title='Other Project',
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.other_adviser,
        )

        # 5. Team Grades
        self.grade_advised = TeamGrade.objects.create(
            team=self.team_advised,
            semester=self.semester,
            scope=TeamGrade.SCOPE_PIT,
            stage_label='Concept Proposal',
            defense_stage=self.stage,
            panel_score=85,
            adviser_score=0,
            peer_score=88,
            final_grade=87,
            panel_weight=80,
            adviser_weight=0,
            peer_weight=20,
            status=TeamGrade.STATUS_PUBLISHED,
        )

        self.grade_other = TeamGrade.objects.create(
            team=self.team_other,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label='Concept Proposal',
            defense_stage=self.stage,
            panel_score=75,
            adviser_score=80,
            peer_score=78,
            final_grade=77,
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
            status=TeamGrade.STATUS_PUBLISHED,
        )

    def test_anonymous_access_denied(self):
        endpoints = [
            f'/api/reports/team-grade/{self.team_advised.id}/',
            '/api/reports/semester-grades/',
            '/api/reports/defense-schedules/',
            '/api/reports/team-roster/',
            '/api/reports/user-directory/',
            '/api/reports/audit-trail/',
        ]
        for url in endpoints:
            response = self.client.get(url)
            self.assertEqual(response.status_code, 401)

    def test_admin_can_generate_all_reports(self):
        self.client.force_authenticate(user=self.admin)
        
        # Team Grade Report
        url = f'/api/reports/team-grade/{self.team_advised.id}/'
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')
        self.assertIn('attachment', response['Content-Disposition'])

        # Semester Grades
        response = self.client.get('/api/reports/semester-grades/', {'semester_id': self.semester.id})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')

        # Defense Schedules
        response = self.client.get('/api/reports/defense-schedules/', {'semester_id': self.semester.id})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')

        # Team Roster
        response = self.client.get('/api/reports/team-roster/', {'semester_id': self.semester.id})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')

        # User Directory
        response = self.client.get('/api/reports/user-directory/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')

        # Audit Trail
        response = self.client.get('/api/reports/audit-trail/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')

    def test_adviser_access_limits(self):
        self.client.force_authenticate(user=self.adviser)

        # Team Grade Report - team they advise
        url = f'/api/reports/team-grade/{self.team_advised.id}/'
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')

        # Team Grade Report - team they do not advise
        url = f'/api/reports/team-grade/{self.team_other.id}/'
        response = self.client.get(url)
        self.assertEqual(response.status_code, 403)

        # User Directory (adviser is not admin)
        response = self.client.get('/api/reports/user-directory/')
        self.assertEqual(response.status_code, 403)

        # Audit Trail (adviser cannot review audit logs)
        response = self.client.get('/api/reports/audit-trail/')
        self.assertEqual(response.status_code, 403)

    def test_pit_lead_access(self):
        self.client.force_authenticate(user=self.pit_lead)

        # Audit Trail - PIT Leads have permission to audit trail (if can_review_audit_logs is True)
        response = self.client.get('/api/reports/audit-trail/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')

    def test_report_search_filters(self):
        self.client.force_authenticate(user=self.admin)
        
        # Create a panelist user
        panelist = User.objects.create_user(
            username='panelist-1',
            password='pass12345',
            role='faculty',
            first_name='Charles',
            last_name='Babbage',
            is_panelist=True,
        )
        
        # Create a defense schedule
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        import datetime
        schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team_other,
            defense_stage=self.stage,
            scheduled_date=datetime.date(2026, 7, 4),
            start_time=datetime.time(10, 0),
            room='Room 101',
            created_by=self.admin,
        )
        
        # Assign panelist to schedule
        SchedulePanelist.objects.create(
            schedule=schedule,
            panelist=panelist,
            order=1,
            is_chair=True,
        )
        
        # Link schedule to TeamGrade
        self.grade_other.schedule = schedule
        self.grade_other.save()
        
        # 1. Test Semester Grades search
        # Search by team adviser first name 'Ada' (should match team_advised)
        response = self.client.get('/api/reports/semester-grades/', {
            'semester_id': self.semester.id,
            'search': 'Ada'
        })
        self.assertEqual(response.status_code, 200)
        
        # Search by panelist last name 'Babbage'
        response = self.client.get('/api/reports/semester-grades/', {
            'semester_id': self.semester.id,
            'search': 'Babbage'
        })
        self.assertEqual(response.status_code, 200)

        # 2. Test Defense Schedules search
        # Search by stage label 'Concept'
        response = self.client.get('/api/reports/defense-schedules/', {
            'semester_id': self.semester.id,
            'search': 'Concept'
        })
        self.assertEqual(response.status_code, 200)

        # Search by panelist first name 'Charles'
        response = self.client.get('/api/reports/defense-schedules/', {
            'semester_id': self.semester.id,
            'search': 'Charles'
        })
        self.assertEqual(response.status_code, 200)

    def test_individual_grade_report_generation(self):
        self.client.force_authenticate(user=self.admin)
        from authentication_access_control.models import SystemAuditLog

        url = f'/api/reports/individual-grade/{self.student.id}/'
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')
        self.assertIn('attachment', response['Content-Disposition'])

        # Verify audit trail was logged
        log = SystemAuditLog.objects.filter(action='report.generate_individual_grade').first()
        self.assertIsNotNone(log)
        self.assertEqual(log.category, 'compliance')
        self.assertEqual(log.target_id, str(self.student.id))


