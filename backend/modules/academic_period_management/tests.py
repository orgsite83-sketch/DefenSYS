from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from grading.rubrics.models import Rubric
from student_teams.models import StudentTeam

from .models import SchoolYear, Semester, SemesterTransitionLog


User = get_user_model()


class AcademicPeriodApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
        )
        self.client.force_authenticate(user=self.admin)

    def _student(self, username='student-user'):
        return User.objects.create_user(
            username=username,
            password='pass12345',
            role='student',
        )

    def _team(self, semester, name='Team Alpha', level=StudentTeam.LEVEL_3_CAPSTONE):
        return StudentTeam.objects.create(
            name=name,
            project_title=name,
            level=level,
            year_level='3rd Year',
            semester=semester,
            leader=self._student(f'{name.lower().replace(" ", "-")}-leader'),
        )

    def _stage(self):
        return DefenseStage.objects.create(
            label=f'Concept Proposal {self._testMethodName}',
            display_order=1,
        )

    def _pit_rubric(self, semester, evaluation_type, name):
        return Rubric.objects.create(
            name=name,
            scope=Rubric.SCOPE_PIT,
            semester=semester,
            evaluation_type=evaluation_type,
            status=Rubric.STATUS_PUBLISHED,
        )

    def test_create_school_year_uses_prototype_format(self):
        response = self.client.post(
            '/api/academic-periods/',
            {'school_year': '2026-2027'},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['school_year']['label'], '2026-2027')
        self.assertIsNone(response.data['active_semester'])
        self.assertTrue(SchoolYear.objects.filter(label='2026-2027').exists())

    def test_rejects_invalid_and_duplicate_school_years(self):
        invalid = self.client.post(
            '/api/academic-periods/',
            {'school_year': '2026-2028'},
            format='json',
        )
        self.assertEqual(invalid.status_code, 400)

        SchoolYear.objects.create(label='2026-2027')
        duplicate = self.client.post(
            '/api/academic-periods/',
            {'school_year': '2026-2027'},
            format='json',
        )

        self.assertEqual(duplicate.status_code, 400)

    def test_create_semester_for_school_year(self):
        school_year = SchoolYear.objects.create(label='2026-2027')

        response = self.client.post(
            f'/api/academic-periods/{school_year.id}/semesters/',
            {'label': Semester.FIRST},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['semester']['label'], Semester.FIRST)
        self.assertFalse(response.data['semester']['is_active'])

    def test_activation_keeps_only_one_semester_active(self):
        first_year = SchoolYear.objects.create(label='2026-2027')
        second_year = SchoolYear.objects.create(label='2027-2028')
        first = Semester.objects.create(school_year=first_year, label=Semester.FIRST)
        second = Semester.objects.create(school_year=second_year, label=Semester.SECOND)

        first_response = self.client.patch(
            f'/api/academic-periods/semesters/{first.id}/',
            {'is_active': True},
            format='json',
        )
        second_response = self.client.patch(
            f'/api/academic-periods/semesters/{second.id}/',
            {'is_active': True},
            format='json',
        )

        first.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual(first_response.status_code, 200)
        self.assertEqual(second_response.status_code, 200)
        self.assertFalse(first.is_active)
        self.assertTrue(second.is_active)
        self.assertEqual(
            second_response.data['active_semester']['display_name'],
            '2nd Semester, A.Y. 2027-2028',
        )
        self.assertEqual(SemesterTransitionLog.objects.count(), 2)

    def test_transition_preview_returns_impacts_and_clickable_routes(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        current = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        target = Semester.objects.create(school_year=school_year, label=Semester.SECOND)
        team = self._team(current)
        stage = self._stage()
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=current,
            team=team,
            defense_stage=stage,
            scheduled_date='2026-05-27',
            start_time='08:00',
            room='Room 301',
        )

        response = self.client.get(
            f'/api/academic-periods/semesters/{target.id}/transition-preview/',
        )

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['can_switch'])
        self.assertEqual(response.data['impact_counts']['active_teams'], 1)
        self.assertEqual(response.data['impact_counts']['open_schedules'], 1)
        issue = response.data['issues'][0]
        self.assertIn('message', issue)
        self.assertIn('route', issue)
        self.assertIn('action_label', issue)

    def test_activation_blocks_unfinished_workflows(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        current = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        target = Semester.objects.create(school_year=school_year, label=Semester.SECOND)
        team = self._team(current)
        stage = self._stage()
        TeamGrade.objects.create(
            team=team,
            semester=current,
            scope=TeamGrade.SCOPE_CAPSTONE,
            defense_stage=stage,
            status=TeamGrade.STATUS_PENDING,
        )

        response = self.client.post(
            f'/api/academic-periods/semesters/{target.id}/activate/',
            {},
            format='json',
        )

        current.refresh_from_db()
        target.refresh_from_db()
        self.assertEqual(response.status_code, 400)
        self.assertTrue(current.is_active)
        self.assertFalse(target.is_active)
        self.assertIn('preview', response.data)

    def test_forced_activation_requires_reason_and_logs_transition(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        current = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        target = Semester.objects.create(school_year=school_year, label=Semester.SECOND)
        self._team(current)

        missing_reason = self.client.post(
            f'/api/academic-periods/semesters/{target.id}/activate/',
            {'force': True},
            format='json',
        )
        forced = self.client.post(
            f'/api/academic-periods/semesters/{target.id}/activate/',
            {'force': True, 'reason': 'Manual rollover approved.'},
            format='json',
        )

        current.refresh_from_db()
        target.refresh_from_db()
        self.assertEqual(missing_reason.status_code, 400)
        self.assertEqual(forced.status_code, 200)
        self.assertFalse(current.is_active)
        self.assertTrue(target.is_active)
        log = SemesterTransitionLog.objects.get()
        self.assertTrue(log.forced)
        self.assertEqual(log.changed_by, self.admin)
        self.assertEqual(log.reason, 'Manual rollover approved.')

    def test_student_cannot_preview_or_activate_semester_transition(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(school_year=school_year, label=Semester.FIRST)
        student = self._student('student-transition')
        self.client.force_authenticate(user=student)

        preview = self.client.get(
            f'/api/academic-periods/semesters/{semester.id}/transition-preview/',
        )
        activate = self.client.post(
            f'/api/academic-periods/semesters/{semester.id}/activate/',
            {},
            format='json',
        )

        self.assertEqual(preview.status_code, 403)
        self.assertEqual(activate.status_code, 403)

    def test_incomplete_official_pit_workflow_blocks_activation(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        current = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        target = Semester.objects.create(school_year=school_year, label=Semester.SECOND)
        team = self._team(current, name='PIT Team', level=StudentTeam.LEVEL_3_PIT)
        panel = self._pit_rubric(current, Rubric.EVAL_PANEL, 'PIT Panel')
        peer = self._pit_rubric(current, Rubric.EVAL_PEER, 'PIT Peer')
        PitEventGradingConfig.objects.create(
            semester=current,
            event_name='3rd Year Expo',
            panel_rubric=panel,
            peer_rubric=peer,
            is_officially_complete=False,
        )
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=current,
            team=team,
            event_name='3rd Year Expo',
            scheduled_date='2026-05-27',
            start_time='08:00',
            room='Room 301',
        )

        response = self.client.get(
            f'/api/academic-periods/semesters/{target.id}/transition-preview/',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data['impact_counts']['incomplete_official_workflows'],
            1,
        )
        self.assertFalse(response.data['can_switch'])

    def test_student_cannot_patch_active_semester(self):
        student = User.objects.create_user(
            username='student-user',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(school_year=school_year, label=Semester.FIRST)

        self.client.force_authenticate(user=student)
        response = self.client.patch(
            f'/api/academic-periods/semesters/{semester.id}/',
            {'is_active': True},
            format='json',
        )

        self.assertEqual(response.status_code, 403)

    def test_student_cannot_create_school_year(self):
        student = User.objects.create_user(
            username='student-create',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)
        response = self.client.post(
            '/api/academic-periods/',
            {'school_year': '2028-2029'},
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_list_includes_capstone_mode_on_active_semester(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )

        response = self.client.get('/api/academic-periods/')

        self.assertEqual(response.status_code, 200)
        active = response.data['active_semester']
        self.assertEqual(active['capstone_mode'], 'capstone_1_intake')
        self.assertTrue(active['can_create_capstone_teams'])
        self.assertIn('capstone_mode_message', active)

    def test_patch_semester_evaluation_flags(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )

        response = self.client.patch(
            f'/api/academic-periods/semesters/{semester.id}/',
            {
                'capstone_peer_evaluation_enabled': False,
                'capstone_adviser_grading_enabled': False,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        semester.refresh_from_db()
        self.assertFalse(semester.capstone_peer_evaluation_enabled)
        self.assertFalse(semester.capstone_adviser_grading_enabled)
        self.assertEqual(
            response.data['semester']['capstone_peer_evaluation_enabled'],
            False,
        )

    def test_student_cannot_patch_evaluation_flags(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        student = User.objects.create_user(
            username='student-eval',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=student)
        response = self.client.patch(
            f'/api/academic-periods/semesters/{semester.id}/',
            {'capstone_peer_evaluation_enabled': False},
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_admin_dashboard_reads_active_semester(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['active_semester'], '1st Semester, A.Y. 2026-2027')
        self.assertEqual(response.data['migration']['phase'], 15)
