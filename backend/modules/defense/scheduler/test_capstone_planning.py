from datetime import date, datetime, time
from uuid import uuid4
from django.contrib.auth import get_user_model
from django.test import SimpleTestCase
from rest_framework.test import APITestCase, APITransactionTestCase
from rest_framework.exceptions import ValidationError
from academic_period_management.models import Semester, SchoolYear
from defense.stages.models import DefenseStage, StageGradingConfig
from grading.rubrics.models import Rubric
from student_teams.models import StudentTeam, TeamMembership
from student_teams.services import mark_stage_ready
from .models import (CapstonePeopleAssignment, CapstoneAssignmentRevision, CapstonePlanningBatch,
    DefenseSchedule, SchedulePanelist)
from .capstone_planning import allocate

User = get_user_model()
WINDOWS = [{'start_time': time(8), 'end_time': time(12)}, {'start_time': time(13), 'end_time': time(17)}]


class AutoAllocationTests(SimpleTestCase):
    def plan(self, count=48, duration=20, **kwargs):
        queue = [{'team_id': i, 'room': '301', 'people': {1}, 'externals': set()} for i in range(count)]
        return allocate(queue, start_date=date(2026, 11, 16), ends_on=date(2026, 12, 31),
            windows=WINDOWS, duration=duration, **kwargs)

    def test_exact_two_days_and_excluded_date_replacement(self):
        slots, remaining = self.plan()
        self.assertEqual(len(slots), 48)
        self.assertFalse(remaining)
        self.assertEqual(len({s['block_key'] for s in slots}), 4)
        self.assertEqual(slots[-1]['scheduled_date'], '2026-11-17')
        self.assertEqual(slots[-1]['end_time'], '17:00:00')
        slots, _ = self.plan(excluded=[date(2026, 11, 17)])
        self.assertEqual(sorted({s['scheduled_date'] for s in slots}), ['2026-11-16', '2026-11-18'])

    def test_partial_last_session_and_non_divisible_duration(self):
        for count, finish in [(56, '10:40:00'), (53, '09:40:00')]:
            slots, remaining = self.plan(count=count)
            self.assertEqual(len({s['team_id'] for s in slots}), count)
            self.assertFalse(remaining)
            self.assertEqual(len({s['block_key'] for s in slots}), 5)
            self.assertEqual(slots[-1]['end_time'], finish)
        slots, _ = self.plan(duration=25)
        self.assertEqual(slots[-1]['end_time'], '14:15:00')

    def test_saturday_is_included_and_sunday_is_optional(self):
        slots, _ = self.plan(duration=60)
        self.assertEqual(slots[-1]['scheduled_date'], '2026-11-21')
        slots, _ = self.plan(count=56, duration=60)
        self.assertEqual(slots[-1]['scheduled_date'], '2026-11-23')
        slots, _ = self.plan(count=56, duration=60, include_sunday=True)
        self.assertEqual(slots[-1]['scheduled_date'], '2026-11-22')

    def test_conflict_advances_to_end_without_reordering_or_substitution(self):
        slots, _ = self.plan(count=2, reservations=[{'start': datetime(2026, 11, 16, 8, 10),
            'end': datetime(2026, 11, 16, 9, 5), 'room': 'other', 'people': {1}, 'externals': set()}])
        self.assertEqual([s['team_id'] for s in slots], [0, 1])
        self.assertEqual(slots[0]['start_time'], '09:05:00')

    def test_calendar_never_drops_remaining_teams_or_splits_a_slot(self):
        queue = [{'team_id': i, 'room': '301', 'people': {1}, 'externals': set()} for i in range(26)]
        slots, remaining = allocate(queue, start_date=date(2026, 11, 16), ends_on=date(2026, 11, 16),
            windows=WINDOWS, duration=20, gap=0)
        self.assertEqual(len(slots), 24)
        self.assertEqual(remaining, [24, 25])


class CapstoneWorkspaceTests(APITestCase):
    url = '/api/defense/schedules/'

    def setUp(self):
        self.admin = User.objects.create_user(username='planner-admin', role='admin', is_staff=True)
        self.people = [User.objects.create_user(username=f'planner-panel-{i}', role='faculty', is_panelist=True) for i in range(5)]
        self.documenter = User.objects.create_user(username='planner-documenter', role='faculty', is_documenter=True)
        year = SchoolYear.objects.create(label='2026-2027')
        self.term = Semester.objects.create(school_year=year, label=Semester.SECOND, is_active=True,
            starts_on=date(2026, 11, 1), ends_on=date(2027, 3, 31))
        self.stage = DefenseStage.objects.create(setup_semester=self.term, label='Customer-defined review',
            display_order=7, qualifying_score=75, minutes_required=True)
        DefenseStage.objects.exclude(pk=self.stage.pk).update(is_active=False)
        rubrics = [Rubric.objects.create(name=f'Planner {kind}', scope='capstone', semester=self.term,
            defense_stage=self.stage, evaluation_type=kind, status='published', created_by=self.admin)
            for kind in ('panel', 'adviser', 'peer')]
        self.config = StageGradingConfig.objects.create(defense_stage=self.stage, semester=self.term,
            panel_rubric=rubrics[0], adviser_rubric=rubrics[1], peer_rubric=rubrics[2])
        self.adviser = User.objects.create_user(username='planner-adviser', role='faculty', is_adviser=True)
        self.team = self.make_team(0, self.adviser)
        self.roster = {'chair_panelist_id': self.people[0].pk, 'panelist_ids': [p.pk for p in self.people[:4]],
            'external_evaluator_ids': [], 'documenter_id': self.documenter.pk}
        self.client.force_authenticate(self.admin)

    def make_team(self, i, adviser):
        leader = User.objects.create_user(username=f'planner-student-{i}', role='student')
        team = StudentTeam.objects.create(name=f'Planner team {i}', level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year', semester=self.term, intake_semester=self.term, leader=leader, adviser=adviser)
        TeamMembership.objects.create(team=team, student=leader, is_leader=True)
        mark_stage_ready(team, self.stage, user=adviser)
        return team

    def save_people(self, teams=None, **extra):
        teams = teams or [self.team]
        return self.client.post(self.url + 'capstone-workspace/', {'semester_id': self.term.pk,
            'defense_stage_id': self.stage.pk, 'team_ids': [t.pk for t in teams],
            'expected_revisions': {str(t.pk): 0 for t in teams}, 'roster': self.roster, **extra}, format='json')

    def inputs(self, **extra):
        return {'planning_mode': 'adviser_auto', 'semester_id': self.term.pk, 'defense_stage_id': self.stage.pk,
            'team_ids': [self.team.pk], 'start_date': '2026-11-16', 'slot_duration': 20, 'room': '301',
            'windows': [{'start_time': '08:00', 'end_time': '12:00'}, {'start_time': '13:00', 'end_time': '17:00'}], **extra}

    def test_first_setup_dynamic_pipeline_and_read_only_preview(self):
        context = self.client.get(self.url + 'capstone-workspace/')
        self.assertEqual(context.status_code, 200, context.data)
        self.assertEqual(context.data['stages'][0]['label'], self.stage.label)
        self.assertIsNone(context.data['stages'][0]['default_slot_duration_minutes'])
        self.assertEqual(self.save_people().status_code, 200)
        self.assertEqual(CapstonePeopleAssignment.objects.get().members.count(), 4)
        from django.db import connection
        from django.test.utils import CaptureQueriesContext
        with CaptureQueriesContext(connection) as queries:
            response = self.client.post(self.url + 'generate-plan/', self.inputs(), format='json')
        self.assertFalse(any(q['sql'].lstrip().split()[0].upper() in {'INSERT', 'UPDATE', 'DELETE'} for q in queries))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['sessions'], 1)
        self.assertEqual(response.data['finish'], '2026-11-16 08:20:00')
        self.assertFalse(DefenseSchedule.objects.exists())
        self.assertFalse(CapstonePlanningBatch.objects.exists())
        self.assertEqual(CapstoneAssignmentRevision.objects.count(), 1)

    def test_workspace_distinguishes_endorsement_from_already_scheduled(self):
        from student_teams.models import TeamStageProgress
        other = self.make_team(1, self.adviser)
        TeamStageProgress.objects.filter(team=other, defense_stage=self.stage).update(status='locked', ready_at=None)
        context = self.client.get(self.url + 'capstone-workspace/')
        by_id = {row['id']: row for row in context.data['teams']}
        self.assertEqual(by_id[self.team.pk]['stage_readiness'][str(self.stage.pk)]['status'], 'ready')
        self.assertEqual(by_id[other.pk]['stage_readiness'][str(self.stage.pk)]['status'], 'awaiting_endorsement')
        self.save_people()
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(), format='json')
        confirmed = self.client.post(self.url + 'confirm-plan/', {'planning_mode': 'adviser_auto',
            'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}, format='json')
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        context = self.client.get(self.url + 'capstone-workspace/')
        by_id = {row['id']: row for row in context.data['teams']}
        scheduled = by_id[self.team.pk]['stage_readiness'][str(self.stage.pk)]
        self.assertEqual(scheduled['status'], 'scheduled')
        self.assertTrue(scheduled['endorsed'])
        self.assertFalse(scheduled['can_schedule'])
        self.assertFalse(scheduled['include_in_scheduler'])

    def test_confirmation_is_atomic_and_idempotent_and_preserves_actual_people(self):
        self.save_people()
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(), format='json')
        data = {'planning_mode': 'adviser_auto', 'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}
        with self.captureOnCommitCallbacks(execute=True):
            response = self.client.post(self.url + 'confirm-plan/', data, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        again = self.client.post(self.url + 'confirm-plan/', data, format='json')
        self.assertEqual(again.status_code, 201, again.data)
        self.assertEqual(response.data['schedule_ids'], again.data['schedule_ids'])
        self.assertEqual(DefenseSchedule.objects.count(), 1)
        self.assertEqual(SchedulePanelist.objects.count(), 4)
        self.assertTrue(DefenseSchedule.objects.get().planning_block_key)

    def test_stale_preview_and_tampered_token_cannot_write(self):
        self.save_people()
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(), format='json')
        self.stage.label = 'Renamed by administrator'
        self.stage.save()
        response = self.client.post(self.url + 'confirm-plan/', {'planning_mode': 'adviser_auto',
            'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}, format='json')
        self.assertEqual(response.status_code, 409, response.data)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_member_counts_are_independent_and_delta_retains_unrelated_members(self):
        adviser = User.objects.create_user(username='other-adviser', role='faculty')
        other = self.make_team(1, adviser)
        self.assertEqual(self.save_people([self.team, other]).status_code, 200)
        response = self.client.post(self.url + 'capstone-workspace/', {'team_ids': [self.team.pk],
            'defense_stage_id': self.stage.pk, 'expected_revisions': {str(self.team.pk): 1},
            'changes': {'add_panelist_ids': [self.people[4].pk]}, 'reason': 'Additional subject expert'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(CapstonePeopleAssignment.objects.get(team=self.team).members.count(), 5)
        self.assertEqual(CapstonePeopleAssignment.objects.get(team=other).members.count(), 4)

    def test_new_project_and_new_intake_do_not_inherit_prior_people(self):
        self.save_people()
        StudentTeam.objects.filter(pk=self.team.pk).update(project_version=2)
        response = self.client.get(self.url + 'capstone-workspace/')
        self.assertIsNone(response.data['teams'][0]['assignment'])
        self.assertEqual(CapstonePeopleAssignment.objects.count(), 1)

    def test_adviser_self_conflict_and_capacity_are_enforced(self):
        roster = {**self.roster, 'panelist_ids': [self.adviser.pk] + self.roster['panelist_ids'], 'chair_panelist_id': self.adviser.pk}
        response = self.save_people(roster=roster)
        self.assertEqual(response.status_code, 400)
        for i in range(1, 4): self.make_team(i, self.adviser)
        from django.core.exceptions import ValidationError
        with self.assertRaises(ValidationError): self.make_team(4, self.adviser)

    def test_duration_has_no_implicit_default_and_staff_cannot_configure(self):
        self.save_people()
        payload = self.inputs()
        del payload['slot_duration']
        response = self.client.post(self.url + 'generate-plan/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.client.force_authenticate(self.people[0])
        response = self.client.get(self.url + 'capstone-workspace/')
        self.assertEqual(response.status_code, 403)

    def test_realistic_48_team_intake_uses_12_advisers_and_moves_excluded_date(self):
        advisers = [self.adviser] + [User.objects.create_user(username=f'cohort-adviser-{i}', role='faculty') for i in range(1, 12)]
        teams = [self.team] + [self.make_team(i, advisers[i // 4]) for i in range(1, 48)]
        response = self.save_people(teams)
        self.assertEqual(response.status_code, 200, response.data)
        response = self.client.post(self.url + 'generate-plan/', self.inputs(team_ids=[t.pk for t in teams],
            excluded_dates=['2026-11-17']), format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['scheduled_dates'], ['2026-11-16', '2026-11-18'])
        self.assertEqual(response.data['sessions'], 4)
        self.assertEqual(len({s['team_id'] for s in response.data['slots']}), 48)
        self.assertEqual(response.data['finish'], '2026-11-18 17:00:00')

    def test_permanent_documenter_operation_does_not_promote_temporary_panel(self):
        self.save_people()
        override = {**self.roster, 'panelist_ids': [self.people[0].pk, self.people[2].pk, self.people[3].pk, self.people[4].pk]}
        event = {'team_ids': [self.team.pk], 'scope': 'stage_only', 'reason': 'Temporary panel cover',
            'changes': {str(self.team.pk): {'remove_panelist_ids': [self.people[1].pk],
                'add_panelist_ids': [self.people[4].pk]}}}
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(overrides={str(self.team.pk): override},
            replacement_reason='Temporary panel cover', replacement_events=[event]), format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        confirmed = self.client.post(self.url + 'confirm-plan/', {'planning_mode': 'adviser_auto',
            'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}, format='json')
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        self.assertEqual(CapstonePlanningBatch.objects.get().inputs['replacement_events'], [event])
        self.assertEqual(CapstoneAssignmentRevision.objects.count(), 1)
        schedule = DefenseSchedule.objects.get()
        replacement = User.objects.create_user(username='new-documenter', role='faculty', is_documenter=True)
        response = self.client.post('/api/defense/board/operations/', {
            'action': 'update', 'anchor_id': schedule.pk, 'target': 'schedule',
            'expected_revisions': {str(schedule.pk): schedule.revision},
            'assignment_scope': 'continuing', 'expected_assignment_revisions': {str(self.team.pk): 1},
            'changes': {'documenter_id': replacement.pk}, 'reason': 'Permanent documenter replacement'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        assignment = CapstonePeopleAssignment.objects.get()
        self.assertEqual(assignment.documenter_id, replacement.pk)
        self.assertEqual(set(assignment.members.values_list('user_id', flat=True)), {p.pk for p in self.people[:4]})
        self.assertEqual(set(schedule.panel_assignments.values_list('panelist_id', flat=True)), set(override['panelist_ids']))

    def test_replacement_audit_cannot_reference_another_team(self):
        self.save_people()
        for event in [
            {'team_ids': [self.team.pk + 100], 'scope': 'stage_only', 'reason': 'Panelist travel'},
            {'team_ids': [self.team.pk], 'scope': 'stage_only', 'reason': 'Panelist travel',
                'changes': {str(self.team.pk + 100): {'documenter_id': self.documenter.pk}}},
            {'team_ids': [self.team.pk], 'scope': 'stage_only', 'reason': ' '},
        ]:
            response = self.client.post(self.url + 'generate-plan/',
                self.inputs(replacement_events=[event]), format='json')
            self.assertEqual(response.status_code, 400, response.data)
            self.assertIn('replacement_events', response.data)
        self.assertFalse(CapstonePlanningBatch.objects.exists())

    def test_calendar_incomplete_plan_blocks_confirmation_and_rollback_is_atomic(self):
        from unittest.mock import patch
        self.save_people()
        second = self.make_team(1, self.adviser)
        self.assertEqual(self.save_people([second]).status_code, 200)
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(team_ids=[self.team.pk, second.pk]), format='json')
        with patch('defense.scheduler.capstone_planning.create_invitations', side_effect=ValidationError('Late failure')):
            response = self.client.post(self.url + 'confirm-plan/', {'planning_mode': 'adviser_auto',
                'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(DefenseSchedule.objects.exists())
        self.assertFalse(CapstonePlanningBatch.objects.exists())
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(team_ids=[self.team.pk, second.pk],
            start_date='2027-03-31', windows=[{'start_time': '08:00', 'end_time': '08:20'}]), format='json')
        self.assertFalse(preview.data['complete'])
        self.assertEqual(preview.data['remaining_team_ids'], [second.pk])
        response = self.client.post(self.url + 'confirm-plan/', {'planning_mode': 'adviser_auto',
            'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}, format='json')
        self.assertEqual(response.status_code, 400, response.data)

    def test_continuation_keeps_people_and_next_intake_gets_empty_setup(self):
        from django.utils import timezone
        from student_teams.models import TeamTermParticipation
        from student_teams.capstone_lifecycle import requirements_for
        self.save_people()
        assignment = CapstonePeopleAssignment.objects.get()
        captured = requirements_for(self.team)
        TeamTermParticipation.objects.update_or_create(team=self.team, semester=self.term,
            defaults={'project_version': 1, 'requirements': captured, 'closed_at': timezone.now(), 'outcome': 'open'})
        self.term.is_active = False
        self.term.save()
        year = SchoolYear.objects.create(label='2027-2028')
        continuing = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True,
            starts_on=date(2027, 6, 1), ends_on=date(2027, 10, 31))
        StudentTeam.objects.filter(pk=self.team.pk).update(semester=continuing)
        context = self.client.get(self.url + 'capstone-workspace/')
        self.assertEqual(context.status_code, 200, context.data)
        row = context.data['teams'][0]
        self.assertEqual(row['assignment'], self.roster)
        self.assertEqual(row['initial_stage_id'], assignment.initial_stage_id)
        continuing.is_active = False
        continuing.save()
        intake = Semester.objects.create(school_year=year, label=Semester.SECOND, is_active=True,
            starts_on=date(2027, 11, 1), ends_on=date(2028, 3, 31))
        new_stage = DefenseStage.objects.create(setup_semester=intake, label='New intake assessment', display_order=1)
        student = User.objects.create_user(username='new-intake-student', role='student')
        fresh = StudentTeam.objects.create(name='New batch team', level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year', semester=intake, intake_semester=intake, leader=student, adviser=self.adviser)
        context = self.client.get(self.url + 'capstone-workspace/')
        self.assertEqual([r['id'] for r in context.data['teams']], [fresh.pk])
        self.assertIsNone(context.data['teams'][0]['assignment'])
        self.assertEqual(context.data['teams'][0]['initial_stage_id'], new_stage.pk)
        self.assertEqual(CapstonePeopleAssignment.objects.count(), 1)

    def test_optional_stage_duration_is_saved_without_label_rules(self):
        response = self.client.patch(f'/api/defense/stages/{self.stage.pk}/grading-config/?semester_id={self.term.pk}',
            {'default_slot_duration_minutes': 25}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.config.refresh_from_db()
        self.assertEqual(self.config.default_slot_duration_minutes, 25)
        context = self.client.get(self.url + 'capstone-workspace/')
        self.assertEqual(context.data['stages'][0]['default_slot_duration_minutes'], 25)

    def test_external_member_and_four_faculty_have_five_minutes_sections(self):
        from user_management.models import ExternalEvaluator, GuestPanelistCode
        evaluator = ExternalEvaluator.objects.create(name='Guest specialist', email='specialist@example.edu',
            status='approved', created_by=self.admin, reviewed_by=self.admin)
        self.roster['external_evaluator_ids'] = [evaluator.pk]
        self.assertEqual(self.save_people().status_code, 200)
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(), format='json')
        confirmed = self.client.post(self.url + 'confirm-plan/', {'planning_mode': 'adviser_auto',
            'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}, format='json')
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        schedule = DefenseSchedule.objects.get()
        self.assertEqual(schedule.panel_assignments.count(), 4)
        self.assertEqual(GuestPanelistCode.objects.filter(schedules=schedule, evaluator=evaluator).count(), 1)
        self.client.force_authenticate(self.documenter)
        minutes = self.client.get(f'/api/defense/minutes/{schedule.pk}/')
        self.assertEqual(minutes.status_code, 200, minutes.data)
        self.assertEqual(len(minutes.data['panelist_comments']), 5)

    def test_historical_first_stage_roster_is_candidate_until_explicitly_saved(self):
        self.save_people()
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(), format='json')
        confirmed = self.client.post(self.url + 'confirm-plan/', {'planning_mode': 'adviser_auto',
            'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}, format='json')
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        # Simulate a pre-feature hearing without a continuing assignment link.
        DefenseSchedule.objects.update(continuing_assignment=None)
        CapstoneAssignmentRevision.objects.all().delete()
        CapstonePeopleAssignment.objects.all().delete()
        context = self.client.get(self.url + 'capstone-workspace/')
        candidate = context.data['teams'][0]['adoption_candidate']
        self.assertFalse(candidate['requires_review'])
        self.assertEqual(candidate['roster'], self.roster)
        self.assertIsNone(context.data['teams'][0]['assignment'])
        self.assertFalse(CapstonePeopleAssignment.objects.exists())


class ConcurrentCapstonePlanningTests(APITransactionTestCase):
    setUp = CapstoneWorkspaceTests.setUp
    make_team = CapstoneWorkspaceTests.make_team
    save_people = CapstoneWorkspaceTests.save_people
    inputs = CapstoneWorkspaceTests.inputs
    url = CapstoneWorkspaceTests.url

    def parallel(self, jobs):
        from concurrent.futures import ThreadPoolExecutor
        from threading import Barrier
        from django.db import close_old_connections
        barrier = Barrier(len(jobs))
        def run(job):
            close_old_connections()
            try:
                barrier.wait(timeout=10)
                return job()
            finally:
                close_old_connections()
        with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
            return list(pool.map(run, jobs))

    def test_concurrent_same_confirmation_has_one_batch_and_one_hearing(self):
        from .capstone_planning import preview_plan, confirm_plan
        self.assertEqual(self.save_people().status_code, 200)
        preview = preview_plan(self.admin, self.inputs())
        payload = {'preview_token': preview['preview_token'], 'idempotency_key': str(uuid4())}
        results = self.parallel([lambda: confirm_plan(self.admin, payload).pk] * 2)
        self.assertEqual(results[0], results[1])
        self.assertEqual(CapstonePlanningBatch.objects.count(), 1)
        self.assertEqual(DefenseSchedule.objects.count(), 1)

    def test_competing_plans_on_different_teams_cannot_double_book_room(self):
        from .capstone_planning import preview_plan, confirm_plan
        from .operations import StaleOperation
        second = self.make_team(1, self.adviser)
        self.save_people([self.team, second])
        previews = [preview_plan(self.admin, self.inputs(team_ids=[t.pk])) for t in [self.team, second]]
        def job(preview):
            def save():
                try:
                    confirm_plan(self.admin, {'preview_token': preview['preview_token'], 'idempotency_key': str(uuid4())})
                    return 201
                except StaleOperation:
                    return 409
            return save
        self.assertEqual(sorted(self.parallel([job(p) for p in previews])), [201, 409])
        self.assertEqual(DefenseSchedule.objects.count(), 1)

    def test_concurrent_adviser_assignments_cannot_both_claim_fourth_place(self):
        from django.core.exceptions import ValidationError as ModelValidationError
        self.make_team(1, self.adviser)
        self.make_team(2, self.adviser)
        leaders = [User.objects.create_user(username=f'capacity-race-{i}', role='student') for i in range(2)]
        def job(i):
            def create():
                try:
                    StudentTeam.objects.create(name=f'Last place {i}', level=StudentTeam.LEVEL_3_CAPSTONE,
                        year_level='3rd Year', semester=self.term, intake_semester=self.term,
                        leader=leaders[i], adviser=self.adviser)
                    return 'created'
                except ModelValidationError:
                    return 'full'
            return create
        self.assertEqual(sorted(self.parallel([job(0), job(1)])), ['created', 'full'])
        self.assertEqual(StudentTeam.objects.filter(adviser=self.adviser).count(), 4)
