"""PIT ownership and Capstone permissions are enforced independently of labels."""
from importlib import import_module
from types import SimpleNamespace
from unittest.mock import patch

from django.apps import apps
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.db import connection
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig, PitEventDeliverable
from defense.stages.models import DefenseStage, StageGradingConfig
from grading.grades.models import TeamGrade
from grading.grades.services import require_grade_editable, update_group_settings
from grading.rubrics.models import Rubric, RubricCriterion
from repository.deliverables.serializers import DeliverableUploadSerializer
from repository.deliverables.services import current_stage_for_team, is_stage_defense_done, get_deliverable_definitions_for_team
from student_teams.models import StudentTeam, TeamMembership

CONFIG = '/api/defense/schedules/pit-event-config/'
GROUP = '/api/grading/grades/group-settings/'
User = get_user_model()


class PitYearIsolationTests(APITestCase):
    def setUp(self):
        self.semester = Semester.objects.create(starts_on='2000-01-01', ends_on='2199-12-31', school_year=SchoolYear.objects.create(label='2098-2099'),
                                                label=Semester.FIRST, is_active=True)
        self.admin = User.objects.create_user(username='scope-admin', role='admin')
        self.first = User.objects.create_user(username='scope-first', role='faculty', is_pit_lead=True, pit_lead_year='1st Year')
        self.second = User.objects.create_user(username='scope-second', role='faculty', is_pit_lead=True, pit_lead_year='2nd Year')
        self.unassigned = User.objects.create_user(username='scope-unassigned', role='faculty', is_pit_lead=True)
        self.panelist = User.objects.create_user(username='scope-panelist', role='faculty', is_panelist=True)
        self.teams = []
        for n, level, year in [(1, StudentTeam.LEVEL_1_PIT, '1st Year'), (2, StudentTeam.LEVEL_2_PIT, '2nd Year'),
                               (3, StudentTeam.LEVEL_3_CAPSTONE, '3rd Year')]:
            student = User.objects.create_user(username=f'scope-student-{n}', role='student')
            team = StudentTeam.objects.create(name=f'Scope Team {n}', project_title='Project', semester=self.semester,
                                               leader=student, level=level, year_level=year)
            TeamMembership.objects.create(team=team, student=student, is_leader=True)
            self.teams.append(team)
        self.panel = self.rubric('Panel', 'panel')
        self.peer = self.rubric('Peer', 'peer')
        self.event = PitEventGradingConfig.objects.create(semester=self.semester, year_level='1st Year',
            event_name='System Concept Pitching', panel_rubric=self.panel, peer_rubric=self.peer)
        self.stage = DefenseStage.objects.create(label='Scope Capstone Stage')
        self.capstone_config = StageGradingConfig.objects.create(semester=self.semester, defense_stage=self.stage)
        self.client.force_authenticate(self.second)

    def rubric(self, name, kind):
        rubric = Rubric.objects.create(name=name, semester=self.semester, scope='pit', evaluation_type=kind,
                                       status='published', created_by=self.first)
        RubricCriterion.objects.create(rubric=rubric, name='Quality', weight=100)
        return rubric

    def data(self, **changes):
        return {'event_name': self.event.event_name, 'panel_weight': 80, 'peer_weight': 20,
                'panel_rubric_id': self.panel.pk, 'peer_rubric_id': self.peer.pk, **changes}

    def slot(self, team, **changes):
        return {'scope': 'pit', 'semester_id': self.semester.pk, 'team_id': team.pk,
                'event_name': self.event.event_name, 'scheduled_date': '2098-10-20', 'start_time': '09:00',
                'slot_duration': 30, 'room': 'Scope Room', 'panelist_ids': [self.panelist.pk], **changes}

    def test_neutral_event_is_visible_only_to_its_explicit_year(self):
        self.assertEqual(self.client.get(CONFIG).data['configs'], [])
        self.assertEqual(self.client.get(CONFIG, {'event_name': self.event.event_name}).status_code, 403)
        self.client.force_authenticate(self.first)
        self.assertEqual([c['id'] for c in self.client.get(CONFIG).data['configs']], [self.event.pk])

    def test_assigned_draft_names_are_returned_without_becoming_scheduler_choices(self):
        Rubric.objects.filter(pk__in=[self.panel.pk, self.peer.pk]).update(status=Rubric.STATUS_DRAFT)
        self.client.force_authenticate(self.first)
        response = self.client.get('/api/defense/schedules/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertNotIn(self.panel.pk, [r['id'] for r in response.data['rubrics']])
        self.assertNotIn(self.peer.pk, [r['id'] for r in response.data['peer_rubrics']])
        event = next(c for c in response.data['pit_events'] if c['id'] == self.event.pk)
        listed = self.client.get(CONFIG)
        named = self.client.get(CONFIG, {'event_name': self.event.event_name})
        self.assertEqual(listed.status_code, 200, listed.data)
        self.assertEqual(named.status_code, 200, named.data)
        for config in (event, listed.data['configs'][0], named.data['config']):
            with self.subTest(config=config['id']):
                self.assertEqual(config['panel_rubric_id'], self.panel.pk)
                self.assertEqual(config['panel_rubric_name'], self.panel.name)
                self.assertEqual(config['peer_rubric_id'], self.peer.pk)
                self.assertEqual(config['peer_rubric_name'], self.peer.name)

    def test_unassigned_rubric_names_are_null(self):
        self.event.panel_rubric = None
        self.event.peer_rubric = None
        self.event.save(update_fields=['panel_rubric', 'peer_rubric'])
        self.client.force_authenticate(self.first)
        response = self.client.get(CONFIG)
        self.assertEqual(response.status_code, 200, response.data)
        config = response.data['configs'][0]
        self.assertIsNone(config['panel_rubric_name'])
        self.assertIsNone(config['peer_rubric_name'])

    def test_missing_assignment_fails_closed_for_list_and_named_lookup(self):
        self.client.force_authenticate(self.unassigned)
        for query in ({}, {'event_name': self.event.event_name}):
            self.assertEqual(self.client.get(CONFIG, query).status_code, 403)

    def test_other_lead_cannot_update_delete_or_claim_event(self):
        before = self.event.panel_weight
        for data in (self.data(panel_weight=70, peer_weight=30), self.data(year_level='1st Year')):
            self.assertIn(self.client.post(CONFIG, data, format='json').status_code, (400, 403))
        self.assertEqual(self.client.delete(f'{CONFIG}?config_id={self.event.pk}').status_code, 403)
        self.event.refresh_from_db()
        self.assertEqual(self.event.panel_weight, before)

    def test_assigned_lead_can_create_neutral_event_and_audit_owns_year(self):
        self.client.force_authenticate(self.first)
        response = self.client.post(CONFIG, self.data(event_name='Prototype Demonstration', panel_rubric_id=None, peer_rubric_id=None), format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['config']['year_level'], '1st Year')
        log = SystemAuditLog.objects.get(action='pit_event.create')
        self.assertEqual(log.new_values['year_level'], '1st Year')
        self.assertEqual(log.actor_id, self.first.pk)

    def test_event_update_and_delete_are_audited_and_audit_failure_rolls_back(self):
        self.client.force_authenticate(self.first)
        with patch('authentication_access_control.models.SystemAuditLog.objects.create', side_effect=RuntimeError('audit unavailable')):
            response = self.client.post(CONFIG, self.data(panel_weight=70, peer_weight=30), format='json')
        self.assertEqual(response.status_code, 500)
        self.event.refresh_from_db()
        self.assertEqual(self.event.panel_weight, 80)
        response = self.client.post(CONFIG, self.data(panel_weight=70, peer_weight=30), format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(SystemAuditLog.objects.filter(action='pit_event.update').exists())
        self.assertEqual(self.client.delete(f'{CONFIG}?config_id={self.event.pk}').status_code, 200)
        self.assertTrue(SystemAuditLog.objects.filter(action='pit_event.delete', old_values__year_level='1st Year').exists())

    def test_rename_by_id_keeps_event_rubrics_and_checklist(self):
        self.client.force_authenticate(self.first)
        item = PitEventDeliverable.objects.create(
            pit_event_config=self.event, deliverable_id='PAPER', label='Concept paper')
        response = self.client.post(CONFIG, self.data(
            config_id=self.event.pk, event_name='IT Innovation Poster Showcase',
            event_code=self.event.event_code,
            deliverables=[{'id': item.pk, 'deliverable_id': 'PAPER', 'label': item.label}],
        ), format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.event.refresh_from_db()
        item.refresh_from_db()
        self.assertEqual(PitEventGradingConfig.objects.count(), 1)
        self.assertEqual(response.data['config']['id'], self.event.pk)
        self.assertEqual(self.event.event_name, 'IT Innovation Poster Showcase')
        self.assertEqual(self.event.event_code, 'it-innovation-poster-showcase')
        self.assertEqual((self.event.panel_rubric_id, self.event.peer_rubric_id),
                         (self.panel.pk, self.peer.pk))
        self.assertEqual(item.pit_event_config_id, self.event.pk)
        self.assertEqual(response.data['config']['deliverables'][0]['id'], item.pk)
        log = SystemAuditLog.objects.get(action='pit_event.update')
        self.assertEqual(log.old_values['event_name'], 'System Concept Pitching')
        self.assertEqual(log.new_values['event_name'], self.event.event_name)
        self.assertFalse(SystemAuditLog.objects.filter(action='pit_event.create').exists())

    def test_rename_preserves_current_submissions_pending_grades_and_team_access(self):
        from repository.deliverables.models import DeliverableSubmission

        self.client.force_authenticate(self.first)
        old_name = self.event.event_name
        team = self.teams[0]
        StudentTeam.objects.filter(pk=team.pk).update(
            current_defense_stage=old_name, ready_for_stage=old_name,
            unlocked_stages=[old_name, f'{old_name}:pre', 'Another event:all'])
        submission = DeliverableSubmission.objects.create(
            team=team, stage_label=old_name, pit_event_config=self.event,
            deliverable_id='PAPER', label='Concept paper', deliverable_type='pre',
            file_name='paper.pdf', status=DeliverableSubmission.STATUS_ACCEPTED)
        uploaded_at = submission.uploaded_at
        grade = TeamGrade.objects.create(team=team, semester=self.semester, scope='pit',
            pit_event_config=self.event, panel_weight=80, peer_weight=20, adviser_weight=0)
        # Legacy pending grades may have only the event's previous label.
        TeamGrade.objects.filter(pk=grade.pk).update(pit_event_config=None)
        response = self.client.post(CONFIG, self.data(
            config_id=self.event.pk, event_name='Poster Showcase',
            panel_weight=70, peer_weight=30), format='json')
        self.assertEqual(response.status_code, 200, response.data)
        team.refresh_from_db()
        submission.refresh_from_db()
        grade.refresh_from_db()
        self.assertEqual(submission.stage_label, 'Poster Showcase')
        self.assertEqual(submission.pit_event_config_id, self.event.pk)
        self.assertEqual(submission.uploaded_at, uploaded_at)
        self.assertEqual(submission.status, DeliverableSubmission.STATUS_ACCEPTED)
        self.assertEqual(grade.stage_label, 'Poster Showcase')
        self.assertEqual(grade.pit_event_config_id, self.event.pk)
        self.assertEqual((grade.panel_weight, grade.peer_weight), (70, 30))
        self.assertEqual(team.current_defense_stage, 'Poster Showcase')
        self.assertEqual(team.ready_for_stage, 'Poster Showcase')
        self.assertEqual(team.unlocked_stages,
                         ['Poster Showcase', 'Poster Showcase:pre', 'Another event:all'])
        self.teams[1].refresh_from_db()
        self.assertIsNone(self.teams[1].current_defense_stage)

    def test_invalid_or_wrong_semester_edit_id_never_creates_an_event(self):
        self.client.force_authenticate(self.first)
        other_semester = Semester.objects.create(starts_on='2000-01-01', ends_on='2199-12-31', school_year=self.semester.school_year, label=Semester.SECOND)
        other = PitEventGradingConfig.objects.create(semester=other_semester,
            year_level='1st Year', event_name='Other semester event')
        for config_id in (None, 999999, 'invalid', True, 0, 1.5, 10**30, other.pk):
            with self.subTest(config_id=config_id):
                response = self.client.post(CONFIG, self.data(
                    config_id=config_id, event_name='New name'), format='json')
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(PitEventGradingConfig.objects.count(), 2)
        self.event.refresh_from_db()
        self.assertEqual(self.event.event_name, 'System Concept Pitching')

    def test_rename_cannot_overwrite_another_event_even_with_case_change(self):
        self.client.force_authenticate(self.first)
        for year in ('1st Year', '2nd Year'):
            other = PitEventGradingConfig.objects.create(
                semester=self.semester, year_level=year, event_name=f'{year} Other event')
            response = self.client.post(CONFIG, self.data(
                config_id=self.event.pk, event_name=other.event_name.upper()), format='json')
            self.assertEqual(response.status_code, 400, response.data)
            self.event.refresh_from_db()
            self.assertEqual(self.event.event_name, 'System Concept Pitching')
            other.refresh_from_db()
            self.assertIsNone(other.panel_rubric_id)

    def test_edit_by_id_cannot_rename_another_years_event_or_a_locked_event(self):
        response = self.client.post(CONFIG, self.data(
            config_id=self.event.pk, event_name='Claimed event',
            panel_rubric_id=None, peer_rubric_id=None), format='json')
        self.assertIn(response.status_code, (400, 403), response.data)
        self.client.force_authenticate(self.first)
        self.event.is_officially_complete = True
        self.event.save()
        response = self.client.post(CONFIG, self.data(
            config_id=self.event.pk, event_name='Renamed locked event'), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.event.refresh_from_db()
        self.assertEqual(self.event.event_name, 'System Concept Pitching')
        self.assertEqual(PitEventGradingConfig.objects.count(), 1)

    def test_rename_rolls_back_when_audit_fails(self):
        self.client.force_authenticate(self.first)
        with patch('authentication_access_control.models.SystemAuditLog.objects.create',
                   side_effect=RuntimeError('audit unavailable')):
            response = self.client.post(CONFIG, self.data(
                config_id=self.event.pk, event_name='Rejected rename'), format='json')
        self.assertEqual(response.status_code, 500)
        self.event.refresh_from_db()
        self.assertEqual(self.event.event_name, 'System Concept Pitching')
        self.assertEqual(PitEventGradingConfig.objects.count(), 1)

    def test_capstone_settings_reject_pit_lead_for_all_updates(self):
        for changes in ({'peer_grading_enabled': True}, {'is_officially_complete': False}, {'is_officially_complete': True}):
            response = self.client.patch(GROUP, {'scope': 'capstone', 'defense_stage_id': self.stage.pk, **changes}, format='json')
            self.assertEqual(response.status_code, 403, response.data)
        with self.assertRaises(Exception):
            update_group_settings(semester=self.semester, scope='capstone', stage_label=self.stage.label,
                                  peer_grading_enabled=True, user=self.second)

    def test_other_year_checklist_is_not_an_upload_slot_or_current_event(self):
        PitEventDeliverable.objects.create(pit_event_config=self.event, deliverable_id='PAPER', label='Concept paper')
        self.assertNotEqual(current_stage_for_team(self.teams[1]), self.event.event_name)
        self.assertEqual(get_deliverable_definitions_for_team(self.teams[1], self.event.event_name), [])
        serializer = DeliverableUploadSerializer(data={'team_id': self.teams[1].pk, 'stage_label': self.event.event_name,
            'deliverable_id': 'PAPER', 'file_name': 'paper.pdf'})
        self.assertFalse(serializer.is_valid())
        self.event.is_officially_complete = True
        self.event.save()
        self.assertFalse(is_stage_defense_done(self.teams[1], self.event.event_name))

    def test_team_access_uses_the_year_field_even_if_a_legacy_level_label_disagrees(self):
        from repository.deliverables.services import team_queryset_for_user
        StudentTeam.objects.filter(pk=self.teams[0].pk).update(level=StudentTeam.LEVEL_2_PIT)
        self.assertNotIn(self.teams[0].pk, team_queryset_for_user(self.second).values_list('pk', flat=True))

    def test_scheduling_rejects_wrong_event_year_even_for_admin(self):
        for actor in (self.second, self.admin):
            self.client.force_authenticate(actor)
            response = self.client.post('/api/defense/schedules/', self.slot(self.teams[1]), format='json')
            self.assertIn(response.status_code, (400, 403), response.data)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_admin_plan_rejects_mixed_cohorts_before_creating_schedules(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/schedules/confirm-plan/', {
            **self.slot(self.teams[0]), 'slots': [{'team_id': self.teams[0].pk}, {'team_id': self.teams[1].pk}],
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_file_access_controls_cannot_apply_another_years_neutral_event(self):
        response = self.client.get('/api/repository/deliverables/stage-access/', {'program_scope': 'pit'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['stages'], [])
        response = self.client.post('/api/repository/deliverables/unlock/', {
            'scope': 'global', 'program_scope': 'pit', 'stage_label': self.event.event_name,
            'target_state': True, 'reason': 'Testing cohort isolation',
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.teams[1].refresh_from_db()
        self.assertEqual(self.teams[1].unlocked_stages, [])

    def test_peer_windows_and_completion_are_independent_for_separate_year_events(self):
        second_event = PitEventGradingConfig.objects.create(semester=self.semester, year_level='2nd Year',
                                                            event_name='Prototype Showcase')
        second_grade = TeamGrade.objects.create(team=self.teams[1], semester=self.semester, scope='pit',
            pit_event_config=second_event, panel_weight=80, peer_weight=20, adviser_weight=0)
        self.client.force_authenticate(self.first)
        response = self.client.patch(GROUP, {'scope': 'pit', 'pit_event_config_id': self.event.pk,
                                           'peer_grading_enabled': True}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.event.is_officially_complete = True
        self.event.peer_grading_enabled = False
        self.event.save()
        second_event.refresh_from_db()
        self.assertTrue(second_event.peer_grading_enabled)
        self.assertFalse(second_event.is_officially_complete)
        require_grade_editable(second_grade)

    def test_failed_request_and_plan_preview_never_modify_event_setup(self):
        self.client.force_authenticate(self.first)
        before = (self.event.updated_at, self.event.panel_weight, self.event.panel_rubric_id)
        response = self.client.post('/api/defense/schedules/', self.slot(self.teams[1], panel_weight=65, peer_weight=35), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.event.refresh_from_db()
        self.assertEqual((self.event.updated_at, self.event.panel_weight, self.event.panel_rubric_id), before)
        response = self.client.post('/api/defense/schedules/generate-plan/', self.slot(self.teams[0]), format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.event.refresh_from_db()
        self.assertEqual(self.event.updated_at, before[0])
        self.assertFalse(SystemAuditLog.objects.filter(action__startswith='pit_event.').exists())

    def test_own_year_schedule_and_grade_use_correct_configuration(self):
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/defense/schedules/', self.slot(self.teams[0]), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(TeamGrade.objects.get().pit_event_config_id, self.event.pk)

    def test_grade_summaries_do_not_expose_other_track_or_other_year(self):
        TeamGrade.objects.create(team=self.teams[2], semester=self.semester, scope='capstone',
            defense_stage=self.stage, stage_label=self.stage.label, panel_score=0, adviser_score=0, peer_score=0)
        for actor in (self.second, self.teams[1].leader):
            self.client.force_authenticate(actor)
            response = self.client.get('/api/grading/grades/', {'scope': 'pit'})
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['grades'], [])
            self.assertNotIn(f'capstone|{self.stage.label}', response.data['group_settings'])
            self.assertNotIn(f'pit|{self.event.event_name}', response.data['group_settings'])
            self.assertNotIn(self.teams[2].name, str(response.data))

    def test_other_year_cannot_reopen_or_toggle_first_year_peer_window(self):
        for changes in ({'is_officially_complete': False}, {'peer_grading_enabled': True}):
            response = self.client.patch(GROUP, {'scope': 'pit', 'pit_event_config_id': self.event.pk, **changes}, format='json')
            self.assertEqual(response.status_code, 403, response.data)

    def test_setup_export_contains_neutral_event_only_for_owning_year(self):
        for actor, expected in ((self.first, True), (self.second, False)):
            self.client.force_authenticate(actor)
            response = self.client.get('/api/reports/pit-event-setup/', {'export_format': 'json'})
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(self.event.event_name in str(response.data), expected)

    def test_year_assignment_is_immutable_and_unclassified_events_fail_closed(self):
        self.event.year_level = '2nd Year'
        with self.assertRaises(ValidationError):
            self.event.save()
        legacy = PitEventGradingConfig.objects.create(semester=self.semester, event_name='Unclassified legacy')
        self.client.force_authenticate(self.first)
        self.assertNotIn(legacy.pk, [c['id'] for c in self.client.get(CONFIG).data['configs']])

    def test_mismatched_legacy_grade_cannot_be_edited_or_have_weights_changed(self):
        second = PitEventGradingConfig.objects.create(semester=self.semester, year_level='2nd Year', event_name='Second Showcase')
        grade = TeamGrade.objects.create(team=self.teams[1], semester=self.semester, scope='pit',
            pit_event_config=second, panel_weight=80, peer_weight=20, adviser_weight=0)
        # Simulate pre-repair data without weakening model validation for new records.
        TeamGrade.objects.filter(pk=grade.pk).update(pit_event_config=self.event)
        self.event.panel_weight, self.event.peer_weight = 70, 30
        self.event.save()
        grade.refresh_from_db()
        self.assertEqual((grade.panel_weight, grade.peer_weight), (80, 20))
        with self.assertRaises(ValidationError):
            require_grade_editable(grade)

    def test_backfill_uses_recorded_year_without_renaming_or_rewriting_grades(self):
        grade = TeamGrade.objects.create(team=self.teams[0], semester=self.semester, scope='pit', pit_event_config=self.event,
                                         panel_weight=80, peer_weight=20, adviser_weight=0)
        PitEventGradingConfig.objects.filter(pk=self.event.pk).update(year_level='')
        migration = import_module('defense.migrations.0036_pit_event_year_level')
        migration.classify_events(apps, SimpleNamespace(connection=connection))
        self.event.refresh_from_db()
        grade.refresh_from_db()
        self.assertEqual(self.event.year_level, '1st Year')
        self.assertEqual(self.event.event_name, 'System Concept Pitching')
        self.assertEqual(grade.pit_event_config_id, self.event.pk)
