from unittest.mock import patch

from . import test_read_performance as performance


class AdminOverviewTests(performance.DashboardReadPerformanceTests):
    def test_empty_stages_add_one_stage_task_without_rubric_task(self):
        from defense.stages.models import DefenseStage
        DefenseStage.objects.all().delete()
        payload, _, _ = self.dashboard()
        overview = payload['overview']
        self.assertEqual(overview['action_counts']['defenseStages'], 1)
        self.assertNotIn('rubrics', overview['action_counts'])
        self.assertTrue(any(item['id'] == 'stage_setup_empty' for item in overview['action_items']))

    def test_draft_stage_counts_with_roster_but_is_not_schedulable(self):
        from defense.stages.models import DefenseStage
        draft = DefenseStage.objects.create(label='Draft proposal', code='draft-proposal',
            display_order=10, is_active=False, setup_semester=self.semester)
        self.add_teams(1)
        payload, _, _ = self.dashboard()
        task = next(item for item in payload['overview']['action_items']
                    if item['id'] == f'stage_setup:{draft.pk}')
        self.assertIn('rubrics', task['related_sections'])
        self.assertNotIn(draft.label, [row['label'] for row in payload['team_pipeline']['stage_distribution']])

    def test_configured_published_stages_clear_badges_but_draft_needs_publication(self):
        from defense.stages.models import DefenseStage
        with patch('defense.stages.readiness.stage_setup_readiness', return_value={
            'ready': True, 'issues': [], 'required_rubric_roles': [],
        }):
            payload, _, _ = self.dashboard()
            self.assertNotIn('defenseStages', payload['overview']['action_counts'])
            self.assertNotIn('rubrics', payload['overview']['action_counts'])
            DefenseStage.objects.filter(pk=DefenseStage.objects.first().pk).update(is_active=False)
            payload, _, _ = self.dashboard()
        self.assertEqual(payload['overview']['action_counts']['defenseStages'], 1)
        self.assertNotIn('rubrics', payload['overview']['action_counts'])

    def test_users_card_counts_enrollment_across_all_years_without_teams(self):
        from django.contrib.auth import get_user_model
        from user_management.academic_records.models import StudentAcademicRecord
        model = get_user_model()
        for index, year in enumerate(('1st Year', '2nd Year', '3rd Year', '4th Year')):
            student = model.objects.create_user(username=f'overview-enrolled-{index}', role='student')
            StudentAcademicRecord.objects.create(student=student, semester=self.semester, year_level=year)
        inactive = model.objects.create_user(username='overview-inactive', role='student', is_active=False)
        StudentAcademicRecord.objects.create(student=inactive, semester=self.semester, year_level='1st Year')
        payload, _, _ = self.dashboard()
        card = payload['overview']['workflow'][0]
        self.assertEqual(card['value'], '4')
        self.assertEqual(card['section'], 'userManagement')
        self.assertEqual(payload['overview']['totals']['capstone']['teams'], 0)

    def test_workflow_and_pit_oversight_contract(self):
        payload, _, _ = self.dashboard()
        overview = payload['overview']
        self.assertEqual(len(overview['workflow']), 5)
        self.assertEqual(overview['workflow'][0]['title'], 'Users')
        self.assertEqual(overview['workflow'][0]['section'], 'userManagement')
        self.assertEqual(overview['workflow'][0]['value'], str(overview['students']))
        self.assertEqual(overview['workflow'][3]['section'], 'defenseBoardSchedules')
        self.assertEqual(len(overview['pit_cohorts']), 3)
        for cohort in overview['pit_cohorts']:
            self.assertEqual(cohort['teams'], 0)
            self.assertEqual(cohort['event_count'], 0)
            self.assertIsNone(cohort['next_defense'])
        self.assertEqual(overview['totals']['capstone']['scheduled_teams'], 0)

    # Inherit fixtures, but avoid inheriting unrelated legacy budget assertions.
    def test_unendorsed_teams_do_not_add_per_team_readiness_queries(self):
        self.add_teams(32)
        with patch('dashboards.overview.admin_overview', return_value={}):
            _, baseline_queries, _ = self.dashboard()
        payload, overview_queries, _ = self.dashboard()
        print(f'32 teams: existing dashboard {baseline_queries} queries; with overview {overview_queries} queries')
        self.assertLessEqual(overview_queries - baseline_queries, 30)
        self.assertEqual(payload['overview']['totals']['capstone']['teams'], 32)

    def test_stage_tasks_have_exact_term_and_editor_destination(self):
        payload, _, _ = self.dashboard()
        tasks = payload['overview']['action_items']
        stage_tasks = [item for item in tasks if item['id'].startswith('stage_setup:')]
        self.assertTrue(stage_tasks)
        for task in stage_tasks:
            self.assertEqual(task['button_label'], 'Create rubrics')
            self.assertIn('/edit?tab=', task['target_route'])
            self.assertIn(f'semester_id={self.semester.pk}', task['target_route'])
            self.assertIn('fromOverview=1', task['target_route'])
        self.assertEqual(payload['overview']['action_counts']['defenseStages'], len(stage_tasks))
        self.assertEqual(payload['overview']['action_counts']['rubrics'], len(stage_tasks))
        for task in stage_tasks:
            self.assertIn('rubrics', task['related_sections'])

    def test_non_rubric_stage_issues_do_not_count_toward_rubrics(self):
        with patch('defense.stages.readiness.stage_setup_readiness', return_value={
            'ready': False, 'issues': ['Add student file submission requirements.'],
            'required_rubric_roles': [],
        }):
            payload, _, _ = self.dashboard()
        overview = payload['overview']
        self.assertGreater(overview['action_counts']['defenseStages'], 0)
        self.assertNotIn('rubrics', overview['action_counts'])

    def test_previous_semester_teams_do_not_enter_overview_totals(self):
        from academic_period_management.models import SchoolYear, Semester
        from student_teams.models import StudentTeam
        historical = Semester.objects.create(school_year=SchoolYear.objects.create(label='2044-2045'), label=Semester.FIRST)
        StudentTeam.objects.create(name='Historical only', semester=historical, leader=self.leader, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        payload, _, _ = self.dashboard()
        self.assertEqual(payload['overview']['totals']['all']['teams'], 0)
        self.assertFalse(any(item['id'] == 'unassigned_advisers' for item in payload['overview']['action_items']))
