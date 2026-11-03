from decimal import Decimal
from datetime import date, time

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from grading.grades.models import StudentStageGrade, TeamGrade
from student_teams.models import StudentTeam, TeamMembership
from user_management.academic_records.models import StudentAcademicRecord


class GradeMasterlistTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.admin = User.objects.create_user(username='master-admin', role='admin')
        cls.lead = User.objects.create_user(username='master-lead', role='faculty', is_pit_lead=True, pit_lead_year='2nd Year')
        cls.no_year = User.objects.create_user(username='master-no-year', role='faculty', is_pit_lead=True)
        cls.faculty = User.objects.create_user(username='master-unassigned-faculty', role='faculty')
        cls.year = SchoolYear.objects.create(label='2048-2049')
        cls.term = Semester.objects.create(school_year=cls.year, label='1st Semester', is_active=True)
        cls.event = PitEventGradingConfig.objects.create(semester=cls.term, year_level='2nd Year', event_name='Masterlist Prototype', panel_weight=80, peer_weight=20)
        cls.event2 = PitEventGradingConfig.objects.create(semester=cls.term, year_level='2nd Year', event_name='Masterlist Exhibit', panel_weight=80, peer_weight=20)
        cls.students = []
        for index in range(13):
            student = User.objects.create_user(username=f'master-{index:03}', role='student', first_name=f'Student {index:02}', last_name='Masterlist')
            StudentAcademicRecord.objects.create(student=student, semester=cls.term, year_level='2nd Year', section='BSIT-2A')
            cls.students.append(student)
        cls.other = User.objects.create_user(username='master-other-year', role='student')
        StudentAcademicRecord.objects.create(student=cls.other, semester=cls.term, year_level='1st Year', section='BSIT-1A')
        cls.team = StudentTeam.objects.create(name='Masterlist Team', project_title='Prototype', level=StudentTeam.LEVEL_2_PIT,
                                             year_level='2nd Year', section='BSIT-2A', semester=cls.term, leader=cls.students[0])
        for student in cls.students[:2]:
            TeamMembership.objects.create(team=cls.team, student=student)
        cls.schedule = DefenseSchedule.objects.create(team=cls.team, semester=cls.term, scope='pit',
            event_name=cls.event.event_name, scheduled_date=date(2048, 10, 15), start_time=time(9), room='Room A')
        cls.grade = TeamGrade.objects.create(team=cls.team, semester=cls.term, scope='pit', pit_event_config=cls.event,
                                            schedule=cls.schedule, stage_label=cls.event.event_name, panel_weight=80, peer_weight=20,
                                            panel_score=90, peer_score=80)
        StudentStageGrade.objects.update_or_create(team_grade=cls.grade, student=cls.students[0],
                                                  defaults={'panel_score': 85, 'peer_score': 90, 'final_grade': 86})
        StudentStageGrade.objects.filter(team_grade=cls.grade, student=cls.students[1]).update(
            panel_score=None, peer_score=None, final_grade=None)

    def setUp(self):
        self.client.force_authenticate(self.admin)

    def fetch(self, **params):
        return self.client.get('/api/grading/grades/masterlist/', {
            'scope': 'pit', 'semester_id': self.term.pk, 'pit_event_config_id': self.event.pk, **params})

    def test_assessment_contains_scheduled_members_including_ungraded_students_without_writes(self):
        before = (TeamGrade.all_objects.count(), StudentStageGrade.objects.count(), StudentTeam.objects.count())
        response = self.fetch()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['total'], 2)
        rows = {r['student_id']: r for r in response.data['rows']}
        self.assertEqual(rows[self.students[0].pk]['assessments'][0]['final_grade'], Decimal('86'))
        self.assertIsNone(rows[self.students[1].pk]['assessments'][0]['final_grade'])
        self.assertNotIn(self.students[12].pk, rows)
        self.assertEqual(before, (TeamGrade.all_objects.count(), StudentStageGrade.objects.count(), StudentTeam.objects.count()))

    def test_semester_cohort_retains_unassigned_students(self):
        response = self.fetch(coverage='semester', year_level='2nd Year')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['total'], 13)
        row = next(r for r in response.data['rows'] if r['student_id'] == self.students[12].pk)
        self.assertTrue(all(cell['status'] == 'no_team' for cell in row['assessments']))

    def test_team_final_is_recorded_team_result(self):
        response = self.fetch(entity='teams')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['total'], 1)
        self.assertEqual(response.data['rows'][0]['assessments'][0]['final_grade'], Decimal('88'))

    def test_search_sort_and_pagination_apply_to_complete_cohort(self):
        for student in self.students[2:]:
            TeamMembership.objects.create(team=self.team, student=student)
        first = self.fetch(page_size=10, ordering='-name')
        second = self.fetch(page_size=10, page=2, ordering='-name')
        self.assertEqual(first.status_code, 200, first.data)
        self.assertEqual(len(first.data['rows']), 10)
        self.assertEqual(len(second.data['rows']), 3)
        self.assertFalse({r['id'] for r in first.data['rows']} & {r['id'] for r in second.data['rows']})
        searched = self.fetch(search=self.students[12].username)
        self.assertEqual(searched.data['total'], 1)
        self.assertEqual(searched.data['rows'][0]['student_id'], self.students[12].pk)
        self.assertEqual(self.fetch(page_size=7).status_code, 400)
        self.assertEqual(self.fetch(ordering='password').status_code, 400)

    def test_semester_cells_keep_exact_assessment_context(self):
        response = self.fetch(coverage='semester')
        self.assertEqual(response.status_code, 200, response.data)
        row = next(r for r in response.data['rows'] if r['student_id'] == self.students[0].pk)
        cells = {c['assessment_id']: c for c in row['assessments']}
        self.assertEqual(cells[self.event.pk]['grade_id'], self.grade.pk)
        self.assertIsNone(cells[self.event2.pk]['grade_id'])
        self.assertNotIn('semester_total', row)

    def test_semester_does_not_mark_another_years_event_as_missing(self):
        response = self.fetch(coverage='semester', pit_event_config_id='')
        self.assertEqual(response.status_code, 200, response.data)
        other_year = next(r for r in response.data['rows'] if r['student_id'] == self.other.pk)
        self.assertEqual(other_year['assessments'], [])

    def test_lead_access_is_enforced_for_direct_requests_and_counts(self):
        self.client.force_authenticate(self.lead)
        self.assertEqual(self.fetch().data['total'], 2)
        self.assertEqual(self.fetch(year_level='1st Year').status_code, 403)
        self.assertEqual(self.fetch(scope='capstone').status_code, 403)
        other_event = PitEventGradingConfig.objects.create(semester=self.term, year_level='1st Year', event_name='Other Year')
        self.assertEqual(self.fetch(pit_event_config_id=other_event.pk).status_code, 403)
        self.client.force_authenticate(self.no_year)
        response = self.fetch(pit_event_config_id='')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['total'], 0)

    def test_unassigned_faculty_and_students_cannot_read_an_admin_cohort(self):
        self.client.force_authenticate(self.faculty)
        self.assertEqual(self.fetch(pit_event_config_id='').data['total'], 0)
        self.client.force_authenticate(self.students[0])
        self.assertEqual(self.fetch().status_code, 403)

    def test_full_detail_retains_zero_and_disabled_components(self):
        self.grade.panel_score = 0
        self.grade.peer_score = 0
        self.grade.save()
        sg = self.grade.student_grades.get(student=self.students[0])
        sg.panel_score = sg.peer_score = sg.final_grade = Decimal('0')
        sg.save()
        response = self.fetch(detail_level='full', student_id=self.students[0].pk)
        self.assertEqual(response.status_code, 200, response.data)
        cell = response.data['rows'][0]['assessments'][0]
        self.assertEqual(cell['final_grade'], 0)
        self.assertEqual(cell['components']['panel']['weighted'], 0)
        self.assertFalse(cell['components']['adviser']['enabled'])

    def panel_evidence(self):
        """Create real evaluator evidence on the isolated test database."""
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        from grading.grades.models import PanelistGradeSubmission, PanelistCriterionScore, PeerEvaluationSubmission
        from grading.rubrics.models import Rubric, RubricCriterion
        rubric = Rubric.objects.create(name='Masterlist individual rubric', scope='pit', semester=self.term,
            event_name=self.event.event_name, evaluation_type='panel', target_type='individual', status='published')
        criteria = [RubricCriterion.objects.create(rubric=rubric, name=name, scale=Rubric.SCALE_10,
            max_score=10, weight=50, target_type='individual', display_order=index)
            for index, name in enumerate(('Implementation', 'Demonstration'))]
        self.event.panel_rubric = rubric
        self.event.save(update_fields=['panel_rubric'])
        schedule = self.schedule
        schedule.rubric = rubric
        schedule.save()
        panelists = [get_user_model().objects.create_user(username=f'master-panel-{index}', role='faculty',
            first_name='Evaluator', last_name=str(index)) for index in (1, 2)]
        for index, panelist in enumerate(panelists):
            SchedulePanelist.objects.create(schedule=schedule, panelist=panelist, order=index)
            for member_index, member in enumerate(self.students[:2]):
                submission = PanelistGradeSubmission.objects.create(team_grade=self.grade, schedule=schedule,
                    panelist=panelist, student=member, remarks=f'Evidence from evaluator {index + 1}.')
                for criterion in criteria:
                    PanelistCriterionScore.objects.create(submission=submission, criterion=criterion,
                        criterion_name_snapshot=criterion.name, score=9 - member_index,
                        max_score_snapshot=10, weight_snapshot=50)
        for evaluator in self.students[:2]:
            for recipient in self.students[:2]:
                PeerEvaluationSubmission.objects.create(team_grade=self.grade, evaluator=evaluator, evaluatee=recipient,
                    total_score=8, max_score=10, weighted_score=80, attempt_number=self.grade.attempt_count,
                    breakdown=[{'criteriaName': 'Contribution', 'score': 4, 'max': 5, 'weight_snapshot': '50'},
                               {'criteriaName': 'Collaboration', 'score': 4, 'max': 5, 'weight_snapshot': '50'}])
        for index, member in enumerate(self.students[:2]):
            StudentStageGrade.objects.update_or_create(team_grade=self.grade, student=member,
                defaults={'panel_score': 90 - index * 10, 'peer_score': 80, 'final_grade': 88 - index * 8})
        self.grade.schedule, self.grade.panel_score, self.grade.peer_score = schedule, Decimal('85'), Decimal('80')
        self.grade.save()
        return panelists

    def test_panel_identity_scores_and_voided_evidence_match_both_table_modes(self):
        from grading.grades.models import PanelistGradeSubmission
        panelists = self.panel_evidence()
        full = self.fetch(detail_level='full', student_id=self.students[0].pk)
        self.assertEqual(full.status_code, 200, full.data)
        cell = full.data['rows'][0]['assessments'][0]
        self.assertEqual([entry['score'] for entry in cell['evaluators']], [90, 90])
        self.assertEqual(cell['panel_submitted'], 2)
        PanelistGradeSubmission.objects.filter(team_grade=self.grade, panelist=panelists[1]).update(is_void=True)
        for detail in ('summary', 'full'):
            response = self.fetch(detail_level=detail, status='awaiting_evaluations')
            self.assertEqual(response.status_code, 200, response.data)
            row = next(row for row in response.data['rows'] if row['student_id'] == self.students[0].pk)
            self.assertIsNone(row['assessments'][0]['final_grade'])
            self.assertEqual(row['assessments'][0]['panel_submitted'], 1)

    def test_raw_peer_evidence_is_oversight_only(self):
        panelists = self.panel_evidence()
        detail = self.client.get(f'/api/grading/grades/{self.grade.pk}/')
        self.assertEqual(detail.status_code, 200, detail.data)
        self.assertEqual(len(detail.data['grade']['peer_rating_evidence']), 4)
        self.client.force_authenticate(panelists[0])
        detail = self.client.get(f'/api/grading/grades/{self.grade.pk}/')
        self.assertEqual(detail.status_code, 200, detail.data)
        self.assertEqual(detail.data['grade']['peer_rating_evidence'], [])
        listing = self.fetch()
        self.assertEqual(listing.status_code, 200, listing.data)
        self.assertEqual(listing.data['total'], 2)

    def test_recorded_legacy_assessment_does_not_create_configuration(self):
        legacy = TeamGrade.objects.create(team=self.team, semester=self.term, scope='pit', stage_label='Legacy showcase',
            panel_weight=80, peer_weight=20, panel_score=90, peer_score=80)
        before = PitEventGradingConfig.objects.count()
        response = self.fetch(coverage='semester', pit_event_config_id='', stage_label='Legacy showcase', year_level='2nd Year')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNone(response.data['context']['assessment_id'])
        row = next(r for r in response.data['rows'] if r['student_id'] == self.students[0].pk)
        cell = next(c for c in row['assessments'] if c['assessment_label'] == 'Legacy showcase')
        self.assertEqual(cell['grade_id'], legacy.pk)
        self.assertEqual(PitEventGradingConfig.objects.count(), before)

    def test_section_options_do_not_disappear_after_filtering(self):
        StudentAcademicRecord.objects.filter(student=self.students[1], semester=self.term).update(section='BSIT-2B')
        response = self.fetch(section='BSIT-2A')
        self.assertEqual(response.data['total'], 1)
        self.assertEqual(response.data['options']['sections'], ['BSIT-2A', 'BSIT-2B'])

    def test_assessment_filters_cancelled_and_other_event_schedules(self):
        for change in ({'status': DefenseSchedule.STATUS_CANCELLED}, {'event_name': self.event2.event_name}):
            DefenseSchedule.objects.filter(pk=self.schedule.pk).update(**change)
            for entity in ('students', 'teams'):
                response = self.fetch(entity=entity)
                self.assertEqual(response.status_code, 200, response.data)
                self.assertEqual(response.data['total'], 0)
                self.assertEqual(response.data['options']['sections'], [])
            DefenseSchedule.objects.filter(pk=self.schedule.pk).update(
                status=DefenseSchedule.STATUS_SCHEDULED, event_name=self.event.event_name)

    def test_assessment_does_not_restore_a_team_outside_the_event_roster(self):
        from student_teams.models import PITEventRoster
        roster, _ = PITEventRoster.objects.update_or_create(event=self.event, section=self.team.section,
            defaults={'source': 'custom'})
        roster.teams.clear()
        for entity in ('students', 'teams'):
            response = self.fetch(entity=entity)
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['total'], 0)

    def test_assessment_requires_a_schedule_and_preserves_completed_hearings(self):
        self.team.ready_for_stage = self.event.event_name
        self.team.save(update_fields=['ready_for_stage'])
        for schedule, expected in ((None, 0), (self.schedule, 2)):
            TeamGrade.all_objects.filter(pk=self.grade.pk).update(schedule=schedule)
            if schedule is None:
                DefenseSchedule.objects.filter(pk=self.schedule.pk).update(status=DefenseSchedule.STATUS_CANCELLED)
            else:
                DefenseSchedule.objects.filter(pk=self.schedule.pk).update(status=DefenseSchedule.STATUS_DONE)
            response = self.fetch()
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['total'], expected)

    def test_scheduled_roster_without_grade_rows_is_read_only(self):
        self.grade.delete()
        before = (TeamGrade.all_objects.count(), StudentStageGrade.objects.count())
        for entity, count in (('students', 2), ('teams', 1)):
            response = self.fetch(entity=entity)
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['total'], count)
            self.assertTrue(all(r['assessments'][0]['grade_id'] is None for r in response.data['rows']))
        self.assertEqual(before, (TeamGrade.all_objects.count(), StudentStageGrade.objects.count()))

    def test_capstone_stage_excludes_other_stages_and_endorsed_unscheduled_teams(self):
        from defense.stages.models import DefenseStage, StageGradingConfig
        from student_teams.models import TeamStageProgress
        from django.utils import timezone
        stages = [DefenseStage.objects.create(label=label, display_order=90 + index)
                  for index, label in enumerate(('Masterlist Concept', 'Masterlist Final'))]
        for stage in stages:
            StageGradingConfig.objects.create(defense_stage=stage, semester=self.term,
                panel_weight=100, adviser_weight=0, peer_weight=0)
        for index, student in enumerate(self.students[:4]):
            StudentAcademicRecord.objects.filter(student=student, semester=self.term).update(
                year_level='4th Year', section='BSIT-4A')
            if index == 3:
                continue  # Enrolled student without a Capstone team.
            team = StudentTeam.objects.create(name=f'Capstone team {index}', project_title=f'Capstone project {index}',
                level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', section='BSIT-4A',
                semester=self.term, leader=student)
            TeamMembership.objects.create(team=team, student=student)
            stage = stages[1] if index == 2 else stages[0]
            TeamStageProgress.objects.update_or_create(team=team, semester=self.term, defense_stage=stage,
                defaults={'status': TeamStageProgress.STATUS_READY, 'ready_at': timezone.now()})
            schedule = None if index == 1 else DefenseSchedule.objects.create(team=team, semester=self.term,
                scope='capstone', defense_stage=stage, scheduled_date=date(2048, 10, 15),
                start_time=time(10 + index), room='Capstone room')
            TeamGrade.objects.create(team=team, semester=self.term, scope='capstone', defense_stage=stage,
                schedule=schedule, stage_label=stage.label, panel_weight=100, adviser_weight=0, peer_weight=0)
        for entity in ('students', 'teams'):
            response = self.fetch(scope='capstone', pit_event_config_id='', defense_stage_id=stages[0].pk, entity=entity)
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['total'], 1)
            self.assertEqual(response.data['rows'][0]['team_name'], 'Capstone team 0')
            self.assertEqual(response.data['rows'][0]['assessments'][0]['status'], 'awaiting_evaluations')

    def test_zero_weight_panel_does_not_block_a_stored_individual_result(self):
        self.panel_evidence()
        TeamGrade.all_objects.filter(pk=self.grade.pk).update(panel_weight=0, peer_weight=100)
        self.grade.student_grades.update(panel_score=None, peer_score=80, final_grade=80)
        from grading.grades.models import PanelistGradeSubmission
        PanelistGradeSubmission.objects.filter(team_grade=self.grade).update(is_void=True)
        cell = self.fetch(student_id=self.students[0].pk).data['rows'][0]['assessments'][0]
        self.assertEqual(cell['final_grade'], 80)
        self.assertFalse(cell['components']['panel']['enabled'])

    def test_semester_cells_resolve_different_event_rosters(self):
        from student_teams.models import PITEventRoster
        first, _ = PITEventRoster.objects.update_or_create(event=self.event, section='BSIT-2A', defaults={'source': 'custom'})
        first.teams.set([self.team])
        other_team = StudentTeam.objects.create(name='Exhibit Team', project_title='Exhibit', level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year', section='BSIT-2A', semester=self.term, leader=self.students[0])
        second, _ = PITEventRoster.objects.update_or_create(event=self.event2, section='BSIT-2A', defaults={'source': 'custom'})
        second.teams.set([other_team])
        other_grade = TeamGrade.objects.create(team=other_team, semester=self.term, scope='pit', pit_event_config=self.event2,
            stage_label=self.event2.event_name, panel_weight=100, peer_weight=0, panel_score=95)
        response = self.fetch(coverage='semester', student_id=self.students[0].pk)
        self.assertEqual(response.status_code, 200, response.data)
        row = response.data['rows'][0]
        cells = {cell['assessment_id']: cell for cell in row['assessments']}
        self.assertEqual(cells[self.event.pk]['team']['id'], self.team.pk)
        self.assertEqual(cells[self.event2.pk]['team']['id'], other_team.pk)
        self.assertEqual(cells[self.event2.pk]['grade_id'], other_grade.pk)
        self.assertEqual(row['team_name'], 'Varies by assessment')

    def test_query_count_does_not_grow_with_displayed_students(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext
        self.panel_evidence()
        with CaptureQueriesContext(connection) as one:
            response = self.fetch(student_id=self.students[0].pk, detail_level='full')
        self.assertEqual(response.status_code, 200, response.data)
        with CaptureQueriesContext(connection) as cohort:
            response = self.fetch(detail_level='full')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertLessEqual(len(cohort), len(one) + 1)

    def test_external_evaluator_slot_uses_public_stable_identity(self):
        from django.utils import timezone
        from datetime import timedelta
        from user_management.models import ExternalEvaluator, GuestPanelistCode
        self.panel_evidence()
        evaluator = ExternalEvaluator.objects.create(name='External Expert', status='approved')
        invitation = GuestPanelistCode.objects.create(evaluator=evaluator, guest_name='Outdated name',
            defense_schedule=self.grade.schedule, expires_at=timezone.now() + timedelta(days=1))
        invitation.schedules.add(self.grade.schedule)
        response = self.fetch(detail_level='full', student_id=self.students[0].pk)
        self.assertEqual(response.status_code, 200, response.data)
        cell = response.data['rows'][0]['assessments'][0]
        self.assertEqual(cell['panel_required'], 3)
        self.assertEqual(cell['panel_submitted'], 2)
        self.assertEqual(len([e for e in cell['evaluators'] if e['name'] == 'External Expert']), 1)
        self.assertNotIn(invitation.code, str(response.data))

    def test_closed_capstone_term_uses_captured_team_context(self):
        from django.utils import timezone
        from student_teams.models import TeamTermParticipation
        from defense.stages.models import DefenseStage, StageGradingConfig
        StudentAcademicRecord.objects.filter(student=self.students[0], semester=self.term).update(year_level='4th Year')
        team = StudentTeam.objects.create(name='Current team name', project_title='Current project',
            level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', section='BSIT-4B',
            semester=self.term, leader=self.students[0])
        stage = DefenseStage.objects.create(label='Masterlist historic defense', display_order=98)
        StageGradingConfig.objects.create(defense_stage=stage, semester=self.term, panel_weight=100, adviser_weight=0, peer_weight=0)
        schedule = DefenseSchedule.objects.create(team=team, semester=self.term, scope='capstone', defense_stage=stage,
            scheduled_date=date(2048, 10, 15), start_time=time(11), room='Room B', status=DefenseSchedule.STATUS_DONE)
        grade = TeamGrade.objects.create(team=team, semester=self.term, scope='capstone', defense_stage=stage,
            schedule=schedule, stage_label=stage.label, panel_weight=100, adviser_weight=0, peer_weight=0, panel_score=91)
        StudentStageGrade.objects.update_or_create(team_grade=grade, student=self.students[0],
            defaults={'panel_score': 91, 'final_grade': 91})
        TeamTermParticipation.objects.update_or_create(team=team, semester=self.term, defaults={
            'closed_at': timezone.now(), 'snapshot': {'name': 'Captured team name', 'project_title': 'Captured project',
                'year_level': '4th Year', 'section': 'BSIT-4A', 'members': [{'student_id': self.students[0].pk}]}})
        response = self.fetch(scope='capstone', pit_event_config_id='', defense_stage_id=stage.pk, student_id=self.students[0].pk)
        self.assertEqual(response.status_code, 200, response.data)
        cell = response.data['rows'][0]['assessments'][0]
        self.assertEqual(cell['team']['name'], 'Captured team name')
        self.assertEqual(cell['team']['section'], 'BSIT-4A')
        self.assertTrue(cell['team']['historical'])
        self.assertEqual(cell['final_grade'], 91)
