"""PIT Lead explorer permissions, including historical and exported records."""
from django.contrib.auth import get_user_model
from unittest.mock import patch
from unittest.mock import patch
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventGradingConfig
from grading.grades.models import TeamGrade, GradeBreakdown
from grading.rubrics.models import Rubric, RubricCriterion
from repository.archive.models import ArchiveEntry
from repository.deliverables.models import DeliverableSubmission
from student_teams.models import StudentTeam, TeamMembership
from user_management.academic_records.models import StudentAcademicRecord


class PitLeadCurriculumTests(APITestCase):
    url = '/api/curriculum-analytics/explorer/'

    def setUp(self):
        users = get_user_model()
        self.admin = users.objects.create_user(username='curriculum-admin', role='admin')
        self.lead = users.objects.create_user(username='curriculum-lead', role='faculty',
                                             is_pit_lead=True, pit_lead_year='1st Year', is_adviser=True)
        self.year = SchoolYear.objects.create(label='2026-2027')
        self.sem = Semester.objects.create(school_year=self.year, label=Semester.FIRST, is_active=True)
        self.second = Semester.objects.create(school_year=self.year, label=Semester.SECOND)
        self.teams, self.events, self.grades = {}, {}, {}
        for number, label in [('1', '1st Year'), ('2', '2nd Year'), ('3', '3rd Year')]:
            student = users.objects.create_user(username=f'pit-{number}-student', role='student')
            team = StudentTeam.objects.create(name=f'PIT {number} team', project_title=f'Year {number} project',
                leader=student, level=f'{label} PIT', year_level=label, semester=self.sem)
            TeamMembership.objects.create(team=team, student=student)
            rubric = Rubric.objects.create(name=f'Year {number} panel', scope='pit', semester=self.sem,
                                            evaluation_type='panel', status='published')
            RubricCriterion.objects.create(rubric=rubric, name=f'Year {number} criterion', max_score=10)
            event = PitEventGradingConfig.objects.create(semester=self.sem, year_level=label,
                event_name=f'Year {number} expo', panel_rubric=rubric)
            grade = TeamGrade.objects.create(team=team, semester=self.sem, scope='pit', pit_event_config=event,
                                              panel_weight=80, peer_weight=20, adviser_weight=0)
            TeamGrade.all_objects.filter(pk=grade.pk).update(status='published', panel_score=80, final_grade=80)
            GradeBreakdown.objects.create(team_grade=grade, rubric=rubric, evaluation_type='panel',
                criterion_name=f'Year {number} criterion', score=8, max_score=10)
            self.teams[number], self.events[number], self.grades[number] = team, event, grade
        self.capstone = StudentTeam.objects.create(name='Private Capstone', project_title='Private Capstone title',
            leader=self.teams['1'].leader, level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year',
            semester=self.sem, adviser=self.lead)
        self.client.force_authenticate(self.lead)

    def get(self, **params):
        return self.client.get(self.url, params)

    def test_progressive_views_keep_assigned_year_scope(self):
        for view in ['overview', 'year', 'assessment', 'projects', 'project_output']:
            params = {'view': view}
            if view in ('year', 'assessment'):
                params['academic_year'] = self.year.label
            response = self.get(**params)
            self.assertEqual(response.status_code, 200, (view, response.data))
            self.assertEqual(response.data['year_level'], '1')
            self.assertNotIn('Year 2 criterion', str(response.data))
            self.assertEqual(self.get(**params, year_level='2').status_code, 403)

    def test_other_year_grading_rows_are_not_loaded_before_scope_filtering(self):
        loaded = []
        original = GradeBreakdown.from_db

        def materialize(*args, **kwargs):
            row = original(*args, **kwargs)
            loaded.append(row.team_grade_id)
            return row

        with patch.object(GradeBreakdown, 'from_db', side_effect=materialize):
            response = self.get(initial='true')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['academic_year'], self.year.label)
        self.assertEqual(loaded, [self.grades['1'].pk])

    def test_other_year_grading_rows_are_not_loaded_before_scope_filtering(self):
        loaded = []
        original = GradeBreakdown.from_db

        def materialize(*args, **kwargs):
            row = original(*args, **kwargs)
            loaded.append(row.team_grade_id)
            return row

        with patch.object(GradeBreakdown, 'from_db', side_effect=materialize):
            response = self.get(initial='true')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['academic_year'], self.year.label)
        self.assertEqual(loaded, [self.grades['1'].pk])

    def test_each_lead_defaults_to_their_year_with_panel_peer_and_project_insights(self):
        for number, label in [('1', '1st Year'), ('2', '2nd Year'), ('3', '3rd Year')]:
            self.lead.pit_lead_year = label
            response = self.get(academic_year=self.year.label)
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['scope'], 'pit')
            self.assertEqual(response.data['year_level'], number)
            self.assertEqual([p['team_id'] for p in response.data['projects']], [self.teams[number].pk])
            self.assertEqual([c['id'] for c in response.data['contexts']], [f'event:{self.events[number].pk}'])
            self.assertEqual({r['id'] for r in response.data['roles']}, {'panel', 'peer'})
            self.assertEqual(response.data['criteria'][0]['name'], f'Year {number} criterion')
            self.assertEqual(response.data['performance']['contexts'][0]['components'][0]['score'], 80)
            coverage = response.data['project_analytics']['coverage']
            self.assertEqual(coverage['classified'] + coverage['unresolved'], 1)

    def test_parameters_cannot_expand_lead_scope_even_with_adviser_role(self):
        for params in [{'scope': 'capstone'}, {'scope': 'pit', 'year_level': '2'},
                       {'scope': 'pit', 'year_level': '3'}, {'year_level': '4'}]:
            self.assertEqual(self.get(**params).status_code, 403)
        for params in [{'context': f'event:{self.events["2"].pk}'},
                       {'subject': f'team:{self.teams["2"].pk}'},
                       {'subject': f'student:{self.teams["2"].leader_id}'}]:
            self.assertEqual(self.get(academic_year=self.year.label, **params).status_code, 400)
        for team in [self.teams['2'], self.capstone]:
            response = self.client.get(f'{self.url}projects/{team.pk}:1/', {'all_assessments': 'true'})
            self.assertEqual(response.status_code, 404)

    def test_ordinary_faculty_students_and_unassigned_leads_are_denied(self):
        users = get_user_model()
        for actor in [self.teams['1'].leader,
                      users.objects.create_user(username='just-faculty', role='faculty'),
                      users.objects.create_user(username='unassigned-lead', role='faculty', is_pit_lead=True),
                      users.objects.create_user(username='invalid-lead', role='faculty', is_pit_lead=True,
                                                pit_lead_year='4th Year')]:
            self.client.force_authenticate(actor)
            for path in [self.url, f'{self.url}projects/{self.teams["1"].pk}:1/', f'{self.url}report/']:
                self.assertEqual(self.client.get(path, {'export_format': 'json'}).status_code, 403)

    def test_history_uses_past_year_and_title_after_team_promotes(self):
        old_year = SchoolYear.objects.create(label='2025-2026')
        old_sem = Semester.objects.create(school_year=old_year, label=Semester.FIRST)
        team = self.teams['2']
        StudentAcademicRecord.objects.create(student=team.leader, semester=old_sem, year_level='1st Year')
        event = PitEventGradingConfig.objects.create(semester=old_sem, year_level='1st Year', event_name='Old expo')
        StudentTeam.objects.filter(pk=team.pk).update(year_level='1st Year', level=StudentTeam.LEVEL_1_PIT,
            semester=old_sem, project_title='Original PIT project')
        team.refresh_from_db()
        old_grade = TeamGrade.objects.create(team=team, semester=old_sem, scope='pit', pit_event_config=event,
            panel_weight=80, peer_weight=20, adviser_weight=0)
        TeamGrade.all_objects.filter(pk=old_grade.pk).update(status='published', final_grade=72,
                                                           project_title_snapshot='Original PIT project')
        StudentTeam.objects.filter(pk=team.pk).update(year_level='2nd Year', level=StudentTeam.LEVEL_2_PIT,
            semester=self.sem, project_title='Promoted private project')
        response = self.get(academic_year=old_year.label)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['projects_count'], 1)
        self.assertEqual(response.data['projects'][0]['project_title'], 'Original PIT project')
        detail = self.client.get(f'{self.url}projects/{team.pk}:1/', {'all_assessments': 'true'})
        self.assertEqual([g['id'] for g in detail.data['assessments']], [old_grade.pk])
        annual = self.get().data['annual_performance']
        self.assertEqual([(y['academic_year'], y['score']) for y in annual],
                         [('2025-2026', 72), ('2026-2027', 80)])

    def test_documents_follow_captured_upload_scope_and_archive_year(self):
        team = self.teams['1']
        for code, workflow, year in [('OWN', '1st Year PIT', '1st Year'),
                                     ('OTHER', '2nd Year PIT', '2nd Year'),
                                     ('CAP', '4th Year Capstone', '4th Year')]:
            DeliverableSubmission.objects.create(team=team, stage_label=self.events['1'].event_name,
                deliverable_id=code, label='Project proposal', deliverable_type='pre',
                archive_team_level=workflow, archive_year_level=year,
                extracted_text=f'Private {code} project manuscript and documented implementation details.')
        for year in ['1st Year', '2nd Year']:
            ArchiveEntry.objects.create(entry_type='pit', team=team, year_level=year,
                academic_year=self.year.label, semester_label=self.sem.label,
                file_name=f'{year}-project-proposal.pdf', extracted_text='Historical project manuscript.')
        detail = self.client.get(f'{self.url}projects/{team.pk}:1/', {'academic_year': self.year.label})
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(len(detail.data['documents']), 2)
        text = str(detail.data['documents'])
        self.assertIn('OWN', text)
        self.assertNotIn('OTHER', text)
        self.assertNotIn('Private CAP', text)
        self.assertNotIn('2nd Year', text)

    def test_third_year_second_semester_capstone_intake_is_excluded(self):
        self.lead.pit_lead_year = '3rd Year'
        team = self.teams['3']
        StudentAcademicRecord.objects.create(student=team.leader, semester=self.sem, year_level='3rd Year')
        StudentTeam.objects.filter(pk=team.pk).update(semester=self.second)
        event = PitEventGradingConfig.objects.create(semester=self.second, year_level='3rd Year', event_name='Invalid PIT')
        TeamGrade.objects.create(team=team, semester=self.second, scope='pit', pit_event_config=event,
                                 panel_weight=80, peer_weight=20, adviser_weight=0)
        response = self.get(academic_year=self.year.label)
        self.assertEqual(response.data['projects_count'], 1)  # The valid first-semester assessment remains.
        self.assertNotIn(str(self.second.pk), [s['id'] for s in response.data['semesters']])
        self.assertNotIn(f'event:{event.pk}', [c['id'] for c in response.data['contexts']])
        self.assertEqual(self.get(academic_year=self.year.label, semester=self.second.pk).status_code, 400)

    def test_export_uses_the_same_scope_and_rejects_other_years(self):
        for fmt in ['json', 'csv', 'xlsx', 'pdf']:
            response = self.client.get(f'{self.url}report/', {'academic_year': self.year.label, 'export_format': fmt})
            self.assertEqual(response.status_code, 200, fmt)
            if fmt == 'json':
                self.assertIn('Year 1 criterion', str(response.data))
                self.assertNotIn('Year 2 criterion', str(response.data))
                self.assertIn('PIT / Year 1', str(response.data))
        for params in [{'scope': 'capstone'}, {'scope': 'pit', 'year_level': '2'}]:
            response = self.client.get(f'{self.url}report/', {'export_format': 'json', **params})
            self.assertEqual(response.status_code, 403)

    def test_admin_retains_all_workflows_and_years(self):
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.get().data['scope'], 'capstone')
        for year in ['1', '2', '3']:
            self.assertEqual(self.get(scope='pit', year_level=year).status_code, 200)
