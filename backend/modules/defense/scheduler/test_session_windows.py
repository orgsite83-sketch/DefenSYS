"""Regression coverage for configured windows with mixed actual staff."""
from datetime import timedelta
from importlib import import_module
from types import SimpleNamespace
from uuid import uuid4

from django.apps import apps
from django.db import connection
from rest_framework.test import APITestCase

from user_management.models import ExternalEvaluator, GuestPanelistCode
from . import test_capstone_planning as fixtures
from .models import CapstonePlanningBatch, DefenseSchedule, PanelistEvaluationDraft, SchedulePanelist
from .sessions import session_context


class PlannedWindowTests(APITestCase):
    setUp = fixtures.CapstoneWorkspaceTests.setUp
    make_team = fixtures.CapstoneWorkspaceTests.make_team
    save_people = fixtures.CapstoneWorkspaceTests.save_people
    inputs = fixtures.CapstoneWorkspaceTests.inputs
    url = fixtures.CapstoneWorkspaceTests.url

    def mixed_plan(self):
        from django.contrib.auth import get_user_model
        User = get_user_model()
        groups = [[self.team] + [self.make_team(i, self.adviser) for i in (1, 2)]]
        for i, size in enumerate((1, 1, 2), 1):
            adviser = User.objects.create_user(username=f'window-adviser-{i}', role='faculty', is_adviser=True)
            groups.append([self.make_team(10 * i + j, adviser) for j in range(size)])
        self.external = ExternalEvaluator.objects.create(name='Window guest', status='approved',
                                                         created_by=self.admin)
        expected = {}
        for i, teams in enumerate(groups):
            doc = self.documenter if i == 0 else User.objects.create_user(
                username=f'window-documenter-{i}', role='faculty', is_documenter=True)
            self.roster = {**self.roster, 'documenter_id': doc.pk,
                           'panelist_ids': [p.pk for p in self.people[:3]] + [self.people[3 + (i % 2)].pk],
                           'external_evaluator_ids': [self.external.pk] if i == 2 else []}
            response = self.save_people(teams)
            self.assertEqual(response.status_code, 200, response.data)
            for team in teams:
                expected[team.pk] = dict(self.roster)
        selected = [team.pk for group in groups for team in group]
        preview = self.client.post(self.url + 'generate-plan/', self.inputs(team_ids=selected, slot_duration=90,
            windows=[{'start_time': '08:00', 'end_time': '12:30'},
                     {'start_time': '13:00', 'end_time': '19:00'}]), format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual(preview.data['sessions'], 2)
        confirmed = self.client.post(self.url + 'confirm-plan/', {'planning_mode': 'adviser_auto',
            'preview_token': preview.data['preview_token'], 'idempotency_key': str(uuid4())}, format='json')
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        self.schedules = list(DefenseSchedule.objects.order_by('start_time').select_related('planning_batch'))
        return expected

    def test_two_windows_remain_two_sessions_with_four_rosters_and_scoped_access(self):
        expected = self.mixed_plan()
        morning, afternoon = self.schedules[:3], self.schedules[3:]
        self.assertEqual(len({s.session_id for s in self.schedules}), 2)
        self.assertEqual(len({s.session_id for s in afternoon}), 1)
        for schedule in self.schedules:
            roster = expected[schedule.team_id]
            self.assertEqual(schedule.documenter_id, roster['documenter_id'])
            self.assertEqual(set(schedule.panel_assignments.values_list('panelist_id', flat=True)),
                             set(roster['panelist_ids']))
        invitation = GuestPanelistCode.objects.get(evaluator=self.external)
        self.assertEqual(set(invitation.schedules.values_list('pk', flat=True)), {afternoon[1].pk})
        self.client.force_authenticate(self.people[4])
        personal = self.client.get(self.url + 'panelist-assignments/')
        self.assertEqual(personal.status_code, 200, personal.data)
        self.assertEqual({row['schedule_id'] for row in personal.data['teams']},
                         {afternoon[0].pk, afternoon[2].pk, afternoon[3].pk})
        self.assertEqual({row['session_id'] for row in personal.data['teams']}, {str(afternoon[0].session_id)})
        self.assertEqual({row['session_label'] for row in personal.data['teams']}, {'Afternoon'})
        self.assertEqual({row['session_start_time'] for row in personal.data['teams']}, {'13:00:00'})
        self.client.force_authenticate(self.admin)
        board = self.client.get('/api/defense/board/')
        self.assertEqual(board.status_code, 200, board.data)
        self.assertEqual(len({row['session_id'] for row in board.data['schedules']}), 2)
        preview = self.client.post('/api/defense/board/operations/', {
            'action': 'preview_delete', 'target': 'session', 'anchor_id': afternoon[0].pk}, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual({row['id'] for row in preview.data['entries']}, {s.pk for s in afternoon})
        self.assertEqual(session_context(morning[-1])['session_label'], 'Morning')
        calendar = self.client.get('/api/dashboards/schedule-planner/', {
            'start': str(morning[0].scheduled_date), 'end': str(morning[0].scheduled_date)})
        self.assertEqual(calendar.status_code, 200, calendar.data)
        self.assertEqual(sorted(row['team_count'] for row in calendar.data['sessions']), [3, 4])
        original_ids = {s.pk: s.session_id for s in self.schedules}
        unchanged_doc = afternoon[-1].documenter_id
        changed = self.client.post('/api/defense/board/operations/', {
            'action': 'update', 'target': 'schedule', 'anchor_id': afternoon[1].pk,
            'expected_revisions': {str(afternoon[1].pk): afternoon[1].revision},
            'changes': {'documenter_id': self.documenter.pk}, 'reason': 'Documenter replacement for this hearing'}, format='json')
        self.assertEqual(changed.status_code, 200, changed.data)
        self.assertEqual(dict(DefenseSchedule.objects.values_list('pk', 'session_id')), original_ids)
        self.assertEqual(DefenseSchedule.objects.get(pk=afternoon[-1].pk).documenter_id, unchanged_doc)

    def test_repair_is_repeat_safe_preserves_assignments_and_can_be_reversed(self):
        self.mixed_plan()
        from .panelist_evaluation import evaluation_context
        hearing = self.schedules[4]
        context = evaluation_context(hearing, hearing.grade_records.first())
        draft = PanelistEvaluationDraft.objects.create(schedule=hearing, panelist=self.people[0],
            context_signature=context, submissions=[{'remarks': 'Saved private draft'}])
        invitations = list(GuestPanelistCode.objects.values_list('pk', 'access_version'))
        guest_schedules = set(GuestPanelistCode.objects.get(evaluator=self.external).schedules.values_list('pk', flat=True))
        old_ids = [uuid4() for _ in range(4)]
        originals = {}
        for index, schedule in enumerate(self.schedules):
            roster_index = 0 if index < 3 else 1 if index == 3 else 2 if index == 4 else 3
            originals[schedule.pk] = old_ids[roster_index]
            DefenseSchedule.objects.filter(pk=schedule.pk).update(session_id=old_ids[roster_index])
        before = list(SchedulePanelist.objects.values_list('pk', 'schedule_id', 'panelist_id', 'is_chair'))
        repair = import_module('defense.migrations.0052_merge_planned_window_sessions')
        editor = SimpleNamespace(connection=connection)
        repair.merge_window_sessions(apps, editor)
        self.assertEqual(DefenseSchedule.objects.values('session_id').distinct().count(), 2)
        mapping = list(DefenseSchedule.objects.order_by('pk').values_list('pk', 'session_id', 'legacy_session_id'))
        self.assertTrue(any(old for _, _, old in mapping))
        repair.merge_window_sessions(apps, editor)
        self.assertEqual(mapping, list(DefenseSchedule.objects.order_by('pk').values_list('pk', 'session_id', 'legacy_session_id')))
        self.assertEqual(before, list(SchedulePanelist.objects.values_list('pk', 'schedule_id', 'panelist_id', 'is_chair')))
        draft.refresh_from_db()
        self.assertEqual(draft.submissions, [{'remarks': 'Saved private draft'}])
        repaired_hearing = DefenseSchedule.objects.get(pk=hearing.pk)
        self.assertEqual(draft.context_signature, evaluation_context(repaired_hearing, repaired_hearing.grade_records.first()))
        self.assertEqual(invitations, list(GuestPanelistCode.objects.values_list('pk', 'access_version')))
        self.assertEqual(guest_schedules, set(GuestPanelistCode.objects.get(evaluator=self.external).schedules.values_list('pk', flat=True)))
        repair.restore_window_sessions(apps, editor)
        self.assertEqual(dict(DefenseSchedule.objects.values_list('pk', 'session_id')), originals)
        self.assertFalse(DefenseSchedule.objects.exclude(legacy_session_id=None).exists())

    def test_repair_leaves_moved_defenses_and_unproven_session_membership_unchanged(self):
        self.mixed_plan()
        second = self.schedules[4]
        # Emulate the original roster split, then move a defense to another day.
        DefenseSchedule.objects.filter(pk=second.pk).update(session_id=uuid4(),
            scheduled_date=second.scheduled_date + timedelta(days=1))
        before = dict(DefenseSchedule.objects.values_list('pk', 'session_id'))
        moved = DefenseSchedule.objects.select_related('planning_batch').get(pk=second.pk)
        self.assertEqual(session_context(moved)['session_label'], '')
        repair = import_module('defense.migrations.0052_merge_planned_window_sessions')
        repair.merge_window_sessions(apps, SimpleNamespace(connection=connection))
        self.assertEqual(dict(DefenseSchedule.objects.values_list('pk', 'session_id')), before)

    def test_repair_does_not_merge_independent_batches_or_alias_unrelated_hearings(self):
        self.mixed_plan()
        batch = self.schedules[-1].planning_batch
        other_batch = CapstonePlanningBatch.objects.create(idempotency_key=uuid4(),
            request_hash=batch.request_hash, fingerprint=batch.fingerprint,
            inputs=batch.inputs, created_by=self.admin)
        DefenseSchedule.objects.filter(pk=self.schedules[-1].pk).update(
            planning_batch=other_batch, batch_id=other_batch.pk, session_id=uuid4())
        # One session also contains a moved hearing. Its remaining slots must
        # not be aliased into a different window/session during the repair.
        split_id = uuid4()
        DefenseSchedule.objects.filter(pk=self.schedules[4].pk).update(session_id=split_id)
        DefenseSchedule.objects.filter(pk=self.schedules[5].pk).update(
            scheduled_date=self.schedules[5].scheduled_date + timedelta(days=1))
        before = dict(DefenseSchedule.objects.values_list('pk', 'session_id'))
        repair = import_module('defense.migrations.0052_merge_planned_window_sessions')
        repair.merge_window_sessions(apps, SimpleNamespace(connection=connection))
        self.assertEqual(dict(DefenseSchedule.objects.values_list('pk', 'session_id')), before)

    def test_window_context_uses_sorted_configuration_and_rejects_invalid_indices(self):
        self.mixed_plan()
        schedule = self.schedules[3]
        batch = schedule.planning_batch
        batch.inputs['windows'].reverse()
        batch.save(update_fields=['inputs'])
        self.assertEqual(session_context(schedule)['session_start_time'], '13:00:00')
        for bad_key in ('2026-11-16:-1', '2026-11-16:99', 'invalid'):
            schedule.planning_block_key = bad_key
            self.assertEqual(session_context(schedule)['session_label'], '')
