from django.contrib.auth import get_user_model
from django.db import connection
from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from . import tests as fixtures, services
from .models import SectionConceptRound, SectionSystemConcept, SharedDeliverableSet


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedSystemHistoryTests(APITestCase):
    rubric = fixtures.SharedSystemConceptTests.rubric
    data = fixtures.SharedSystemConceptTests.data
    slot = fixtures.SharedSystemConceptTests.slot
    configure = fixtures.SharedSystemConceptTests.configure
    setUp = fixtures.SharedSystemConceptTests.setUp

    def read(self, actor=None):
        self.client.force_authenticate(actor or self.pm)
        return self.client.get(f'/api/repository/section-concepts/{self.project.pk}/history/')

    def test_roster_counts_belong_to_each_recorded_attempt_and_get_is_read_only(self):
        first = services.latest(self.project)
        teams = [{'team_id': self.team.pk, 'project_version': self.team.project_version},
                 {'team_id': self.module_team.pk, 'project_version': self.module_team.project_version}]
        first.decision_snapshot = {'teams': teams}
        first.verdict = 'for_redefense'
        first.save(update_fields=['decision_snapshot', 'verdict'])
        second = SectionConceptRound.objects.create(project=self.project, number=2,
            verdict='approved', selected_key='c1', decision_snapshot={'teams': teams[:1]})
        SectionSystemConcept.objects.create(round=second, key='c1', title='Recorded approved system', decision='approved')
        with CaptureQueriesContext(connection) as queries:
            response = self.read()
        self.assertEqual(response.status_code, 200, response.data)
        records = next(s for s in response.data['stages'] if s['id'] == self.event.pk)['records']
        hearings = [record for record in records if record['kind'] == 'hearing']
        self.assertEqual([row['team_count'] for row in hearings], [2, 1])
        self.assertEqual(hearings[1]['left_count'], 1)
        self.assertEqual(hearings[1]['systems'][0]['title'], 'Recorded approved system')
        self.assertFalse(any(q['sql'].lstrip().upper().startswith(('INSERT', 'UPDATE', 'DELETE')) for q in queries))
        first.refresh_from_db()
        self.assertEqual(first.decision_snapshot['teams'], teams)

    def test_legacy_approval_does_not_claim_the_current_roster_was_present(self):
        hearing = services.latest(self.project)
        hearing.verdict = 'approved'
        hearing.save(update_fields=['verdict'])
        response = self.read()
        self.assertEqual(response.status_code, 200)
        records = next(s for s in response.data['stages'] if s['id'] == self.event.pk)['records']
        self.assertIsNone(records[0]['team_count'])
        self.assertIsNone(records[0]['teams'])

    def test_selection_correction_preserves_the_original_choice_and_its_reason(self):
        hearing = services.latest(self.project)
        hearing.verdict, hearing.selected_key = 'approved', 'c2'
        hearing.decision_snapshot = {'teams': [], 'selection_corrections': [{
            'from_key': 'c1', 'to_key': 'c2', 'reason': 'Correct the recorded selection.',
            'by_name': 'Recorded chair', 'at': '2026-11-03T08:00:00+00:00',
            'previous_decision': {'selected_key': 'c1', 'verdict': 'approved',
                'decided_at': '2026-11-02T08:00:00+00:00',
                'systems': [{'key': 'c1', 'title': 'Original choice'}]},
        }]}
        hearing.save(update_fields=['verdict', 'selected_key', 'decision_snapshot'])
        response = self.read()
        self.assertEqual(response.status_code, 200)
        records = next(s for s in response.data['stages'] if s['id'] == self.event.pk)['records']
        original = next(row for row in records if row['kind'] == 'hearing')
        self.assertEqual(original['selected_key'], 'c1')
        self.assertEqual(original['systems'][0]['title'], 'Original choice')
        change = next(row for row in records if row['kind'] == 'selection_correction')
        self.assertEqual(change['remarks'], 'Correct the recorded selection.')
        self.assertEqual(change['recorded_by'], 'Recorded chair')

    def test_shared_submission_keeps_its_captured_system_and_team_versions(self):
        captured = SharedDeliverableSet.objects.create(section=self.project.section,
            pit_event_config=self.event, source_project=self.project, identity='captured-history',
            project_manager=self.pm, requirements=[],
            team_snapshot=[{'id': self.team.pk, 'version': 1}],
            system_snapshot=[{'key': 'c2', 'title': 'Original shared system'}])
        response = self.read()
        self.assertEqual(response.status_code, 200)
        records = next(s for s in response.data['stages'] if s['id'] == self.event.pk)['records']
        record = next(row for row in records if row['id'] == f'shared-{captured.pk}')
        self.assertEqual(record['systems'][0]['title'], 'Original shared system')
        self.assertEqual(record['team_count'], 1)
        self.assertEqual(record['teams'][0]['project_version'], 1)

    def test_unrelated_student_cannot_read_the_section_history_or_post_to_it(self):
        outsider = get_user_model().objects.create_user(username='history-outsider', role='student')
        self.assertEqual(self.read(outsider).status_code, 404)
        self.client.force_authenticate(self.pm)
        response = self.client.post(f'/api/repository/section-concepts/{self.project.pk}/history/', {})
        self.assertEqual(response.status_code, 405)


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedCapstoneHistoryTests(APITestCase):
    setUp = fixtures.SharedCapstoneConceptTests.setUp
    project = fixtures.SharedCapstoneConceptTests.project

    def test_shared_status_uses_recorded_schedule_and_presentation_without_get_writes(self):
        from defense.scheduler.models import DefenseSchedule
        from django.utils import timezone
        project = self.project()
        hearing = services.latest(project)
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, scheduled_date='2020-01-01', start_time='08:00', room='Recorded hearing')
        hearing.schedules.add(schedule)
        self.client.force_authenticate(self.student)
        with CaptureQueriesContext(connection) as queries:
            response = self.client.get(f'/api/repository/section-concepts/{project.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['hearing_progress'], 'scheduled')
        self.assertEqual(response.data['hearing_schedule_ids'], [schedule.pk])
        self.assertIsNone(response.data['presentation_started_at'])
        self.assertFalse(any(q['sql'].lstrip().upper().startswith(('INSERT', 'UPDATE', 'DELETE')) for q in queries))
        hearing.presentation_started_at = timezone.now()
        hearing.save(update_fields=['presentation_started_at'])
        response = self.client.get(f'/api/repository/section-concepts/{project.pk}/')
        self.assertIsNotNone(response.data['presentation_started_at'])
        schedule.status = 'cancelled'
        schedule.save(update_fields=['status'])
        response = self.client.get(f'/api/repository/section-concepts/{project.pk}/')
        self.assertEqual(response.data['hearing_progress'], 'cancelled')
        self.assertEqual(response.data['hearing_schedule_ids'], [])

    def test_student_api_omits_scores_in_concepts_deliverables_grades_and_schedule(self):
        from decimal import Decimal
        from defense.scheduler.models import DefenseSchedule
        from grading.grades.models import TeamGrade
        from repository.deliverables import concepts
        project = self.project()
        current = concepts.get_round(self.team, self.stage)
        current.concepts = [{'key': f'c{i}', 'title': f'Module {i}',
            'decision': 'approved' if i == 1 else 'not_selected', 'panel_score': 80 + i}
            for i in range(1, 4)]
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, scheduled_date='2026-11-03', start_time='08:00', room='Privacy test')
        current.schedule, current.verdict = schedule, 'approved'
        current.save(update_fields=['concepts', 'schedule', 'verdict'])
        grade = TeamGrade.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, schedule=schedule, stage_label=self.stage.label,
            panel_score=Decimal('82.5'), final_grade=Decimal('85'), verdict='approved')
        self.client.force_authenticate(self.student)
        endpoints = [
            f'/api/repository/deliverables/concepts/?team_id={self.team.pk}&stage_label={self.stage.label}',
            f'/api/repository/deliverables/?team_id={self.team.pk}&stage_label={self.stage.label}',
            f'/api/repository/section-concepts/{project.pk}/',
            f'/api/repository/section-concepts/{project.pk}/history/',
            f'/api/grading/grades/{grade.pk}/',
            f'/api/grading/grades/{grade.pk}/workflow/',
            '/api/grading/grades/',
            f'/api/defense/schedules/?team_id={self.team.pk}',
        ]

        def assert_private(item):
            if isinstance(item, dict):
                for key, value in item.items():
                    self.assertNotIn(key, {'panel_score', 'final_grade', 'student_scores', 'criterion_scores'})
                    assert_private(value)
            elif isinstance(item, (list, tuple)):
                for value in item:
                    assert_private(value)

        for endpoint in endpoints:
            response = self.client.get(endpoint)
            self.assertEqual(response.status_code, 200, (endpoint, response.data))
            assert_private(response.data)
        current.refresh_from_db()
        self.assertEqual(current.concepts[0]['panel_score'], 81)
        self.assertEqual(concepts.payload(self.team, self.stage, actor=self.adviser)['concepts'][0]['panel_score'], 81)
        self.client.force_authenticate(self.adviser)
        response = self.client.get(f'/api/grading/grades/{grade.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(float(response.data['grade']['panel_score']), 82.5)

    def test_custom_later_stage_includes_only_defenses_of_captured_team_versions(self):
        from defense.stages.models import DefenseStage
        from defense.scheduler.models import DefenseSchedule
        from student_teams.models import StudentTeam
        project = self.project()
        later = DefenseStage.objects.create(label='Configured deployment review', display_order=90)
        SharedDeliverableSet.objects.create(section=project.section, defense_stage=later,
            source_project=project, identity='later-history', project_manager=self.student,
            requirements=[], team_snapshot=[{'id': self.team.pk, 'version': self.team.project_version}],
            system_snapshot=[{'key': 'c1', 'title': 'Preserved shared system'}])
        related = DefenseSchedule.objects.create(team=self.team, project_version=self.team.project_version,
            semester=self.semester, defense_stage=later, scheduled_date='2026-11-01', start_time='08:00', room='History room')
        unrelated = StudentTeam.objects.create(name='Unrelated history team', semester=self.semester,
            level=self.team.level, year_level=self.team.year_level, section=self.team.section,
            leader=get_user_model().objects.create_user(username='stage-history-unrelated-leader', role='student'))
        other = DefenseSchedule.objects.create(team=unrelated, semester=self.semester,
            defense_stage=later, scheduled_date='2026-11-01', start_time='09:00', room='Other room')
        self.client.force_authenticate(self.student)
        response = self.client.get(f'/api/repository/section-concepts/{project.pk}/history/')
        self.assertEqual(response.status_code, 200, response.data)
        stage = next(row for row in response.data['stages'] if row['id'] == later.pk)
        self.assertEqual(stage['label'], 'Configured deployment review')
        ids = {row['id'] for row in stage['records']}
        self.assertIn(f'defense-{related.pk}', ids)
        self.assertNotIn(f'defense-{other.pk}', ids)
