from datetime import date, time, timedelta

from django.utils import timezone
from rest_framework.test import APITestCase

from user_management.models import ExternalEvaluator, GuestPanelistCode
from student_teams.models import StudentTeam
from .models import DefenseSchedule, SchedulePanelist
from . import tests as fixtures


class SessionSchedulingTests(APITestCase):
    setUp = fixtures.DefenseSchedulerApiTests.setUp
    schedule_payload = fixtures.DefenseSchedulerApiTests.schedule_payload
    create_ready_team = fixtures.DefenseSchedulerApiTests.create_ready_team

    def session(self, key='day-1', **changes):
        return {'key': key, 'scheduled_date': '2026-05-15', 'start_time': '08:00',
                'end_time': '10:00', 'slot_duration': 60, 'room': 'Lab 1', **changes}

    def post_plan(self, sessions, slots=None):
        endpoint = 'generate-plan' if slots is None else 'confirm-plan'
        payload = self.schedule_payload(sessions=sessions)
        if slots is not None:
            payload['slots'] = slots
        return self.client.post(f'/api/defense/schedules/{endpoint}/', payload, format='json')

    def test_generation_spans_days_and_leaves_overflow_unassigned(self):
        self.create_ready_team()
        self.create_ready_team(name='Team Third', username='student-3')
        response = self.post_plan([
            self.session(end_time='09:00'),
            self.session('day-2', scheduled_date='2026-05-16', end_time='09:00'),
        ])
        self.assertEqual(response.status_code, 200, response.data)
        slots = response.data['slots']
        self.assertEqual([s['session_key'] for s in slots], ['day-1', 'day-2', None])
        self.assertEqual([str(s['scheduled_date']) for s in slots[:2]], ['2026-05-15', '2026-05-16'])
        self.assertIsNone(slots[2]['start_time'])
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_admin_selection_generates_only_chosen_teams_in_chosen_order(self):
        second = self.create_ready_team()
        third = self.create_ready_team(name='Team Third', username='student-3')
        sessions = [self.session(team_ids=[third.pk, self.team.pk])]
        generated = self.post_plan(sessions)
        self.assertEqual(generated.status_code, 200, generated.data)
        self.assertEqual([slot['team_id'] for slot in generated.data['slots']], [third.pk, self.team.pk])
        confirmed = self.post_plan(sessions, generated.data['slots'])
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        self.assertFalse(DefenseSchedule.objects.filter(team=second).exists())

    def test_one_day_session_skips_lunch_and_retains_its_single_session_id(self):
        teams = [self.team] + [self.create_ready_team(name=f'Team {i}', username=f'day-student-{i}') for i in range(7)]
        sessions = [self.session(team_ids=[t.pk for t in teams], time_blocks=[
            {'start_time': '08:00', 'end_time': '12:00'},
            {'start_time': '13:00', 'end_time': '17:00'},
        ])]
        generated = self.post_plan(sessions)
        self.assertEqual(generated.status_code, 200, generated.data)
        self.assertEqual([str(slot['start_time']) for slot in generated.data['slots']],
                         [f'{hour:02}:00:00' for hour in [8, 9, 10, 11, 13, 14, 15, 16]])
        confirmed = self.post_plan(sessions, generated.data['slots'])
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        self.assertEqual(DefenseSchedule.objects.values('session_id').distinct().count(), 1)
        self.assertEqual(DefenseSchedule.objects.get(team=teams[4]).start_time, time(13))

    def test_selected_overflow_stays_unassigned_to_its_requested_session(self):
        second = self.create_ready_team()
        sessions = [self.session(end_time='09:00', team_ids=[self.team.pk, second.pk]),
                    self.session('empty-next-day', scheduled_date='2026-05-16', team_ids=[])]
        generated = self.post_plan(sessions)
        self.assertEqual(generated.status_code, 200, generated.data)
        overflow = generated.data['slots'][1]
        self.assertIsNone(overflow['session_key'])
        self.assertEqual(overflow['requested_session_key'], 'day-1')
        self.assertIsNone(overflow['start_time'])
        self.assertEqual(self.post_plan(sessions, generated.data['slots']).status_code, 400)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_invalid_team_membership_and_missing_selection_are_rejected(self):
        cases = [
            [self.session(team_ids=[])],
            [self.session(team_ids=[self.team.pk, self.team.pk])],
            [self.session(team_ids=[999999])],
            [self.session(team_ids=[self.team.pk]), self.session('next', team_ids=[self.team.pk])],
            [self.session(team_ids=[self.team.pk]), self.session('next')],
        ]
        for sessions in cases:
            with self.subTest(sessions=sessions):
                response = self.post_plan(sessions)
                self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_confirm_requires_exact_membership_and_the_selected_session(self):
        second = self.create_ready_team()
        sessions = [self.session(team_ids=[self.team.pk]),
                    self.session('next', scheduled_date='2026-05-16', team_ids=[second.pk])]
        cases = [
            [{'team_id': self.team.pk, 'session_key': 'day-1'}],
            [{'team_id': second.pk, 'session_key': 'day-1'}, {'team_id': self.team.pk, 'session_key': 'next'}],
        ]
        for slots in cases:
            with self.subTest(slots=slots):
                response = self.post_plan(sessions, slots)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertFalse(DefenseSchedule.objects.exists())

    def test_time_blocks_cannot_overlap_reverse_or_cut_a_team_slot(self):
        cases = [
            [{'start_time': '08:00', 'end_time': '12:00'}, {'start_time': '11:00', 'end_time': '17:00'}],
            [{'start_time': '13:00', 'end_time': '17:00'}, {'start_time': '08:00', 'end_time': '12:00'}],
            [{'start_time': '08:00', 'end_time': '08:30'}],
            [],
        ]
        for blocks in cases:
            with self.subTest(blocks=blocks):
                response = self.post_plan([self.session(time_blocks=blocks, team_ids=[self.team.pk])])
                self.assertEqual(response.status_code, 400, response.data)

    def test_unused_block_minutes_do_not_make_a_slot_across_the_break(self):
        second = self.create_ready_team()
        generated = self.post_plan([self.session(slot_duration=90, team_ids=[self.team.pk, second.pk],
            time_blocks=[{'start_time': '08:00', 'end_time': '10:00'}, {'start_time': '13:00', 'end_time': '15:00'}])])
        self.assertEqual(generated.status_code, 200, generated.data)
        self.assertEqual([str(slot['start_time']) for slot in generated.data['slots']], ['08:00:00', '13:00:00'])
        self.assertEqual([str(slot['end_time']) for slot in generated.data['slots']], ['09:30:00', '14:30:00'])

    def test_confirm_preserves_preview_and_separate_sessions_in_one_batch(self):
        self.create_ready_team()
        self.create_ready_team(name='Team Third', username='student-3')
        sessions = [self.session(), self.session('day-2', scheduled_date='2026-05-16',
            start_time='13:00', end_time='14:30', slot_duration=30, room='Lab 2')]
        generated = self.post_plan(sessions)
        self.assertEqual(generated.status_code, 200, generated.data)
        response = self.post_plan(sessions, generated.data['slots'])
        self.assertEqual(response.status_code, 201, response.data)
        schedules = list(DefenseSchedule.objects.order_by('scheduled_date', 'start_time'))
        self.assertEqual(len({s.batch_id for s in schedules}), 1)
        self.assertEqual(len({s.session_id for s in schedules}), 2)
        for schedule, slot in zip(schedules, generated.data['slots']):
            self.assertEqual(schedule.team_id, slot['team_id'])
            self.assertEqual(str(schedule.scheduled_date), str(slot['scheduled_date']))
            self.assertEqual(str(schedule.start_time), str(slot['start_time']))
            self.assertEqual(schedule.slot_duration, slot['slot_duration'])
            self.assertEqual(schedule.room, slot['room'])
            self.assertTrue(schedule.grade_records.exists())

    def test_same_day_morning_and_afternoon_preserve_break(self):
        second = self.create_ready_team()
        response = self.post_plan([self.session('morning', end_time='09:00'),
            self.session('afternoon', start_time='13:00', end_time='14:00')],
            [{'team_id': self.team.pk, 'session_key': 'morning'},
             {'team_id': second.pk, 'session_key': 'afternoon'}])
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(list(DefenseSchedule.objects.values_list('start_time', flat=True)), [time(8), time(13)])

    def test_staff_overrides_and_external_invitations_are_limited_to_session(self):
        second = self.create_ready_team()
        doc = self.admin
        evaluator = ExternalEvaluator.objects.create(name='Guest expert', email='guest@example.edu',
            status='approved', created_by=self.admin, reviewed_by=self.admin)
        response = self.post_plan([self.session('first'),
            self.session('second', scheduled_date='2026-05-16', panelist_ids=[self.second_panelist.pk],
                chair_panelist_id=self.second_panelist.pk, documenter_id=doc.pk,
                external_evaluator_ids=[evaluator.pk])],
            [{'team_id': self.team.pk, 'session_key': 'first'}, {'team_id': second.pk, 'session_key': 'second'}])
        self.assertEqual(response.status_code, 201, response.data)
        first = DefenseSchedule.objects.get(team=self.team)
        later = DefenseSchedule.objects.get(team=second)
        self.assertEqual(first.panelists.count(), 2)
        self.assertIsNone(first.documenter_id)
        self.assertEqual(list(later.panelists.values_list('pk', flat=True)), [self.second_panelist.pk])
        self.assertEqual(later.panel_assignments.get().is_chair, True)
        self.assertEqual(later.documenter_id, doc.pk)
        invitation = GuestPanelistCode.objects.get(evaluator=evaluator)
        self.assertEqual(list(invitation.schedules.values_list('pk', flat=True)), [later.pk])

    def test_reordered_teams_save_in_their_own_session_order(self):
        second = self.create_ready_team()
        third = self.create_ready_team(name='Team Third', username='student-3')
        response = self.post_plan([self.session(), self.session('next', scheduled_date='2026-05-16')],
            [{'team_id': second.pk, 'session_key': 'day-1'}, {'team_id': third.pk, 'session_key': 'next'},
             {'team_id': self.team.pk, 'session_key': 'day-1'}])
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(DefenseSchedule.objects.get(team=second).start_time, time(8))
        self.assertEqual(DefenseSchedule.objects.get(team=self.team).start_time, time(9))
        self.assertEqual(DefenseSchedule.objects.get(team=third).scheduled_date, date(2026, 5, 16))

    def test_confirm_rejects_duplicate_unassigned_and_overcapacity_teams(self):
        second = self.create_ready_team()
        cases = [
            [{'team_id': self.team.pk, 'session_key': 'day-1'}, {'team_id': self.team.pk, 'session_key': 'day-1'}],
            [{'team_id': self.team.pk, 'session_key': 'missing'}],
            [{'team_id': self.team.pk}],
            [{'team_id': self.team.pk, 'session_key': 'day-1'}, {'team_id': second.pk, 'session_key': 'day-1'}],
            [{'team_id': 'invalid', 'session_key': 'day-1'}],
        ]
        for slots in cases:
            with self.subTest(slots=slots):
                response = self.post_plan([self.session(end_time='09:00')], slots)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertFalse(DefenseSchedule.objects.exists())

    def test_invalid_session_windows_and_duplicate_keys_are_rejected(self):
        cases = [[self.session(end_time='07:00')], [self.session(end_time='08:30')],
                 [self.session(), self.session()], [self.session(slot_duration=0)],
                 [self.session(documenter_id=self.panelist.pk)],
                 [self.session(chair_panelist_id=self.adviser.pk)]]
        for sessions in cases:
            with self.subTest(sessions=sessions):
                response = self.post_plan(sessions)
                self.assertEqual(response.status_code, 400, response.data)

    def test_proposed_sessions_check_room_and_people_conflicts(self):
        second = self.create_ready_team()
        for different_room in (False, True):
            sessions = [self.session(), self.session('overlap', room='Lab 2' if different_room else 'Lab 1')]
            response = self.post_plan(sessions, [{'team_id': self.team.pk, 'session_key': 'day-1'},
                {'team_id': second.pk, 'session_key': 'overlap'}])
            self.assertEqual(response.status_code, 400, response.data)
            self.assertFalse(DefenseSchedule.objects.exists())

    def test_parallel_sessions_allow_distinct_rooms_and_panels(self):
        second = self.create_ready_team()
        response = self.post_plan([
            self.session('first', panelist_ids=[self.panelist.pk]),
            self.session('second', room='Lab 2', panelist_ids=[self.second_panelist.pk]),
        ], [{'team_id': self.team.pk, 'session_key': 'first'}, {'team_id': second.pk, 'session_key': 'second'}])
        self.assertEqual(response.status_code, 201, response.data)

    def test_existing_documenter_is_reserved_across_staff_roles_and_dates(self):
        other = self.create_ready_team()
        schedule = DefenseSchedule.objects.create(team=other, semester=self.semester, scope='capstone',
            defense_stage=self.stage, rubric=self.rubric, scheduled_date='2026-05-14',
            start_time='23:30', slot_duration=60, room='Other room', documenter=self.panelist, created_by=self.admin)
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.second_panelist)
        response = self.post_plan([self.session(start_time='00:00', end_time='01:00')],
            [{'team_id': self.team.pk, 'session_key': 'day-1'}])
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(DefenseSchedule.objects.count(), 1)

    def test_changed_preview_is_rejected_without_partial_save(self):
        response = self.post_plan([self.session()], [{'team_id': self.team.pk, 'session_key': 'day-1', 'start_time': '09:00'}])
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_guest_expiry_must_cover_last_assigned_day_and_rolls_back_batch(self):
        second = self.create_ready_team()
        evaluator = ExternalEvaluator.objects.create(name='Guest expert', email='guest@example.edu',
            status='approved', created_by=self.admin, reviewed_by=self.admin)
        tomorrow = timezone.localdate() + timedelta(days=1)
        sessions = [self.session('first', scheduled_date=tomorrow.isoformat()),
            self.session('second', scheduled_date=(tomorrow + timedelta(days=2)).isoformat())]
        response = self.client.post('/api/defense/schedules/confirm-plan/', self.schedule_payload(
            sessions=sessions, external_evaluator_ids=[evaluator.pk],
            guest_access_expires_at=(timezone.now() + timedelta(days=2)).isoformat(),
            slots=[{'team_id': self.team.pk, 'session_key': 'first'}, {'team_id': second.pk, 'session_key': 'second'}]), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(DefenseSchedule.objects.exists())
        self.assertFalse(GuestPanelistCode.objects.exists())


class PitSessionSchedulingTests(APITestCase):
    setUp = fixtures.PitEventGradingConfigTests.setUp
    pit_payload = fixtures.PitEventGradingConfigTests.pit_payload

    def test_explicit_pit_day_session_selects_only_chosen_teams_and_skips_lunch(self):
        student = fixtures.User.objects.create_user(username='pit-selected', role='student')
        selected = StudentTeam.objects.create(name='PIT Selected', level=self.team.level,
            year_level=self.team.year_level, semester=self.semester, leader=student)
        unused_student = fixtures.User.objects.create_user(username='pit-unused', role='student')
        unused = StudentTeam.objects.create(name='PIT Unselected', level=self.team.level,
            year_level=self.team.year_level, semester=self.semester, leader=unused_student)
        payload = self.pit_payload(sessions=[{'key': 'full-day', 'scheduled_date': '2026-05-20',
            'start_time': '08:00', 'slot_duration': 240, 'room': 'Lab 1', 'team_ids': [selected.pk, self.team.pk],
            'time_blocks': [{'start_time': '08:00', 'end_time': '12:00'}, {'start_time': '13:00', 'end_time': '17:00'}]}])
        generated = self.client.post('/api/defense/schedules/generate-plan/', payload, format='json')
        self.assertEqual(generated.status_code, 200, generated.data)
        self.assertEqual([slot['team_id'] for slot in generated.data['slots']], [selected.pk, self.team.pk])
        self.assertEqual([str(slot['start_time']) for slot in generated.data['slots']], ['08:00:00', '13:00:00'])
        payload['slots'] = generated.data['slots']
        confirmed = self.client.post('/api/defense/schedules/confirm-plan/', payload, format='json')
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        self.assertEqual(DefenseSchedule.objects.values('session_id').distinct().count(), 1)
        self.assertFalse(DefenseSchedule.objects.filter(team=unused).exists())

    def test_multi_day_pit_sessions_share_event_grading_configuration(self):
        student = fixtures.User.objects.create_user(username='pit-student-2', role='student')
        second = StudentTeam.objects.create(name='PIT Team Beta', level=self.team.level,
            year_level=self.team.year_level, semester=self.semester, leader=student)
        sessions = [{'key': f'day-{i}', 'scheduled_date': f'2026-05-{20 + i}',
            'start_time': '09:00', 'end_time': '10:00', 'slot_duration': 60, 'room': 'Lab 1'}
            for i in range(2)]
        payload = self.pit_payload(sessions=sessions)
        generated = self.client.post('/api/defense/schedules/generate-plan/', payload, format='json')
        self.assertEqual(generated.status_code, 200, generated.data)
        payload['slots'] = generated.data['slots']
        confirmed = self.client.post('/api/defense/schedules/confirm-plan/', payload, format='json')
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        self.assertEqual(DefenseSchedule.objects.count(), 2)
        self.assertEqual(DefenseSchedule.objects.values('batch_id').distinct().count(), 1)
        self.assertEqual(DefenseSchedule.objects.values('session_id').distinct().count(), 2)
        grades = list(fixtures.TeamGrade.objects.filter(team__in=[self.team, second]))
        self.assertEqual(len(grades), 2)
        self.assertEqual({g.panel_weight for g in grades}, {75})
        self.assertEqual(len({g.pit_event_config_id for g in grades}), 1)

    def test_pit_session_cannot_assign_a_documenter(self):
        response = self.client.post('/api/defense/schedules/generate-plan/', self.pit_payload(
            sessions=[{'key': 'day-1', 'scheduled_date': '2026-05-20', 'start_time': '09:00',
                'end_time': '10:00', 'slot_duration': 60, 'room': 'Lab 1', 'documenter_id': self.admin.pk}]), format='json')
        self.assertEqual(response.status_code, 400, response.data)
