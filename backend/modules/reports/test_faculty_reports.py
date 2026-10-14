from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventGradingConfig
from defense.stages.models import DefenseStage, StageDeliverable
from grading.grades.models import TeamGrade
from student_teams.models import StudentTeam, TeamMembership
from user_management.models import SectionInstructorAssignment


class FacultyReportTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.adviser = User.objects.create(username='faculty-report-adviser', role='faculty', is_adviser=True)
        cls.other_adviser = User.objects.create(username='faculty-report-other', role='faculty', is_adviser=True)
        cls.instructor = User.objects.create(username='faculty-report-instructor', role='faculty', is_pit_lead=True,
                                             pit_lead_year='1st Year')
        cls.student = User.objects.create(username='faculty-report-student', role='student')
        year = SchoolYear.objects.create(label='2050-2051')
        cls.semester = Semester.objects.create(school_year=year, label='1st Semester', is_active=True)
        cls.stage = DefenseStage.objects.create(label='Faculty Report Proposal')
        StageDeliverable.objects.create(defense_stage=cls.stage, deliverable_id='FINAL',
            label='Final Archive', deliverable_type='post', required=True)
        PitEventGradingConfig.objects.create(semester=cls.semester, event_name='Faculty Report PIT Event')
        cls.advised = StudentTeam.objects.create(name='Advised Report Team', project_title='Advised Project',
            level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', section='BSIT-4A',
            semester=cls.semester, leader=cls.student, adviser=cls.adviser)
        cls.foreign = StudentTeam.objects.create(name='Foreign Report Team', project_title='Foreign Project',
            level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', section='BSIT-4B',
            semester=cls.semester, leader=cls.student, adviser=cls.other_adviser)
        cls.pit = StudentTeam.objects.create(name='Assigned PIT Report Team', project_title='PIT Project',
            level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', section='BSIT-1A',
            semester=cls.semester, leader=cls.student)
        cls.other_pit = StudentTeam.objects.create(name='Other Section PIT Report Team', project_title='Other PIT',
            level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', section='BSIT-1B',
            semester=cls.semester, leader=cls.student)
        TeamMembership.objects.create(team=cls.advised, student=cls.student, is_leader=True)
        SectionInstructorAssignment.objects.create(faculty=cls.instructor, semester=cls.semester,
            year_level='1st Year', section='BSIT-1A')

    def test_adviser_overview_contains_only_selected_assigned_teams(self):
        self.client.force_authenticate(self.adviser)
        response = self.client.get('/api/reports/faculty-teams-overview/', {
            'workspace': 'adviser', 'team_ids': str(self.advised.id), 'export_format': 'json',
            'stage': self.stage.label,
        })
        self.assertEqual(response.status_code, 200, getattr(response, 'data', None))
        self.assertEqual(len(response.data['rows']), 1)
        self.assertEqual(response.data['rows'][0]['team'], self.advised.name)
        self.assertEqual(response.data['rows'][0]['grade'], 'Not published')
        excel = self.client.get('/api/reports/faculty-teams-overview/', {
            'workspace': 'adviser', 'team_ids': str(self.advised.id), 'export_format': 'xlsx',
            'stage': self.stage.label,
        })
        self.assertEqual(excel.status_code, 200)
        self.assertTrue(excel.content.startswith(b'PK'))
        blocked = self.client.get('/api/reports/faculty-teams-overview/', {
            'workspace': 'adviser', 'team_ids': f'{self.advised.id},{self.foreign.id}',
        })
        self.assertEqual(blocked.status_code, 403)

    def test_pit_lead_privilege_does_not_expand_instructor_export(self):
        self.client.force_authenticate(self.instructor)
        allowed = self.client.get(f'/api/reports/faculty-team/{self.pit.id}/', {
            'workspace': 'pit_instructor', 'stage': 'Faculty Report PIT Event', 'export_format': 'json',
        })
        self.assertEqual(allowed.status_code, 200, getattr(allowed, 'data', None))
        self.assertEqual(allowed.data['rows'][0]['value'], self.pit.name)
        pdf = self.client.get(f'/api/reports/faculty-team/{self.pit.id}/', {
            'workspace': 'pit_instructor', 'stage': 'Faculty Report PIT Event',
        })
        self.assertEqual(pdf.status_code, 200)
        self.assertTrue(pdf.content.startswith(b'%PDF'))
        blocked = self.client.get(f'/api/reports/faculty-team/{self.other_pit.id}/', {
            'workspace': 'pit_instructor',
        })
        self.assertEqual(blocked.status_code, 404)

    def test_team_summary_shows_only_published_grade(self):
        grade = TeamGrade.objects.create(team=self.advised, semester=self.semester,
            scope='capstone', defense_stage=self.stage, stage_label=self.stage.label,
            panel_score=80, peer_score=80, adviser_score=80)
        self.client.force_authenticate(self.adviser)
        path = f'/api/reports/faculty-team/{self.advised.id}/'
        query = {'workspace': 'adviser', 'stage': self.stage.label, 'export_format': 'json'}
        pending = self.client.get(path, query)
        self.assertEqual(pending.status_code, 200, getattr(pending, 'data', None))
        self.assertEqual(pending.data['rows'][-1]['value'], 'Not published')
        self.assertEqual(pending.data['sections'][1]['rows'], [])
        grade.publish(self.adviser)
        published = self.client.get(path, query)
        self.assertEqual(published.status_code, 200, getattr(published, 'data', None))
        self.assertEqual(published.data['rows'][-1]['value'], '80.00')

    def test_student_and_unassigned_faculty_cannot_export(self):
        self.client.force_authenticate(self.student)
        response = self.client.get(f'/api/reports/faculty-team/{self.advised.id}/', {'workspace': 'adviser'})
        self.assertEqual(response.status_code, 403)
        self.client.force_authenticate(self.other_adviser)
        response = self.client.get(f'/api/reports/faculty-team/{self.advised.id}/', {'workspace': 'adviser'})
        self.assertEqual(response.status_code, 404)
