from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from authentication_access_control.models import SystemAuditLog
from defense.minutes.models import DefenseMinutes, MinutesPanelistComment
from grading.grades.models import TeamGrade, PanelistGradeSubmission, PanelistCriterionScore
from grading.grades.services import recompute_panel_score, team_grading_readiness
from .models import DefenseSchedule, PanelistEvaluationDraft, SchedulePanelist
from . import tests as fixtures


class ScheduleOperationsTests(APITestCase):
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages

    setUp = fixtures.DefenseSchedulerApiTests.setUp
    create_scheduled_defense = fixtures.DefenseSchedulerApiTests.create_scheduled_defense
    create_ready_team = fixtures.DefenseSchedulerApiTests.create_ready_team

    def schedule(self):
        schedule = self.create_scheduled_defense()
        schedule.refresh_from_db()
        schedule.panel_assignments.filter(panelist=self.panelist).update(is_chair=True)
        return schedule

    def operation(self, schedule, **data):
        return self.client.post('/api/defense/board/operations/', {
            'action': 'update', 'anchor_id': schedule.pk,
            'expected_revisions': {str(schedule.pk): schedule.revision},
            'reason': 'Emergency panel replacement', **data,
        }, format='json')

    def grade(self, schedule):
        return TeamGrade.objects.create(team=self.team, semester=self.semester, scope='capstone', defense_stage=self.stage, schedule=schedule)

    def submission(self, grade, panelist=None, first=2):
        submission = PanelistGradeSubmission.objects.create(team_grade=grade, schedule=grade.schedule, panelist=panelist or self.panelist)
        for criterion, value in ((self.criterion, first), (self.second_criterion, 9)):
            PanelistCriterionScore.objects.create(submission=submission, criterion=criterion,
                criterion_name_snapshot=criterion.name, max_score_snapshot=10, score=value, display_order=criterion.display_order)
        recompute_panel_score(grade)
        return submission

    def correction(self, grade, **data):
        grade.refresh_from_db()
        return self.client.post(f'/api/grading/grades/{grade.pk}/corrections/', {
            'reason': 'Panelist confirmed a score entry error', 'expected_updated_at': grade.updated_at.isoformat(), **data,
        }, format='json')

    def mixed_rosters(self):
        a, b = self.schedule(), self.schedule()
        b.start_time = '09:00'
        b.save()
        b.panel_assignments.filter(panelist=self.panelist).delete()
        b.panel_assignments.update(is_chair=True)
        incoming = get_user_model().objects.create_user(username='emergency-panel', role='faculty', is_panelist=True, first_name='Emergency', last_name='Panel')
        return a, b, incoming

    def management_operation(self, items, **data):
        return self.operation(items[0], target='management_selected',
            schedule_ids=[s.pk for s in items], expected_revisions={str(s.pk): s.revision for s in items}, **data)

    def test_relative_add_preview_is_readonly_and_noops_keep_revision_and_audit(self):
        a, b, incoming = self.mixed_rosters()
        SchedulePanelist.objects.create(schedule=a, panelist=incoming, order=2)
        changes = {'panel_change': {'action': 'add', 'panelist_ids': [incoming.pk]}}
        preview = self.management_operation([a, b], action='preview_update', changes=changes)
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual((preview.data['updated'], preview.data['unchanged']), (1, 1))
        self.assertFalse(b.panel_assignments.filter(panelist=incoming).exists())
        self.assertFalse(SystemAuditLog.objects.filter(action='schedule.operational_change').exists())
        b.refresh_from_db()
        self.assertEqual(b.revision, 1)
        response = self.management_operation([a, b], changes=changes)
        self.assertEqual(response.status_code, 200, response.data)
        a.refresh_from_db(); b.refresh_from_db()
        self.assertEqual((a.revision, b.revision), (1, 2))
        self.assertEqual(set(a.panel_assignments.values_list('panelist_id', flat=True)), {self.panelist.pk, self.second_panelist.pk, incoming.pk})
        self.assertEqual(set(b.panel_assignments.values_list('panelist_id', flat=True)), {self.second_panelist.pk, incoming.pk})
        self.assertEqual(b.panel_assignments.get(is_chair=True).panelist_id, self.second_panelist.pk)
        self.assertEqual(SystemAuditLog.objects.filter(action='schedule.operational_change').count(), 1)
        board = self.client.get('/api/defense/board/').data['schedules']
        changed = next(s for s in board if s['id'] == b.pk)
        self.assertEqual(changed['latest_change']['changes'][0]['added_ids'], [incoming.pk])
        history = self.client.get(f'/api/defense/board/operations/?history_for={b.pk}').data['history']
        self.assertEqual(history[0]['reason'], 'Emergency panel replacement')
        self.assertIn('Emergency Panel', history[0]['changes'][0]['after'])

    def test_relative_replace_only_changes_defenses_with_departing_panelist(self):
        a, b, incoming = self.mixed_rosters()
        response = self.management_operation([a, b], changes={'panel_change': {'action': 'replace', 'panelist_id': self.panelist.pk, 'replacement_id': incoming.pk}})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual((response.data['updated'], response.data['unchanged']), (1, 1))
        self.assertEqual(a.panel_assignments.get(is_chair=True).panelist_id, incoming.pk)
        self.assertEqual(set(b.panel_assignments.values_list('panelist_id', flat=True)), {self.second_panelist.pk})

    def test_relative_remove_preserves_submitted_author_and_rolls_back_combined_room_change(self):
        a, b, incoming = self.mixed_rosters()
        self.submission(self.grade(a))
        response = self.management_operation([a, b], changes={'panel_change': {'action': 'replace', 'panelist_id': self.panelist.pk, 'replacement_id': incoming.pk}, 'room': 'Room 302'})
        self.assertEqual(response.status_code, 400)
        for schedule in (a, b):
            schedule.refresh_from_db()
            self.assertEqual(schedule.room, 'Room 301')
            self.assertEqual(schedule.revision, 1)
        self.assertTrue(a.panel_assignments.filter(panelist=self.panelist).exists())

    def test_combined_tabs_are_reviewed_and_saved_together(self):
        a, b, incoming = self.mixed_rosters()
        changes = {'panel_change': {'action': 'add', 'panelist_ids': [incoming.pk]}, 'room': 'Room 302', 'shift_minutes': 15}
        preview = self.management_operation([a, b], action='preview_update', changes=changes)
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual({c['field'] for c in preview.data['entries'][0]['changes']}, {'panelist_ids', 'room', 'start_time'})
        response = self.management_operation([a, b], changes=changes)
        self.assertEqual(response.status_code, 200, response.data)
        a.refresh_from_db(); b.refresh_from_db()
        self.assertEqual((a.room, b.room), ('Room 302', 'Room 302'))
        self.assertEqual((str(a.start_time), str(b.start_time)), ('08:15:00', '09:15:00'))

    def test_management_scope_rejects_other_terms_and_defense_types(self):
        from academic_period_management.models import Semester
        a = self.schedule()
        b = self.schedule()
        b.semester = Semester.objects.create(school_year=self.school_year, label=Semester.FIRST)
        b.save()
        response = self.management_operation([a,b], changes={'room': 'Room 302'})
        self.assertEqual(response.status_code, 403)
        response = self.operation(b, target='semester', action='preview_delete')
        self.assertEqual(response.status_code, 400)
        # The scope boundary is exercised independently of PIT creation validation.
        DefenseSchedule.objects.filter(pk=b.pk).update(semester=self.semester, scope='pit', defense_stage=None, event_name='PIT Demo')
        b.refresh_from_db()
        response = self.management_operation([a,b], changes={'room':'Room 302'})
        self.assertEqual(response.status_code, 403)

    def test_management_context_is_independent_of_board_filters_and_includes_section_identity(self):
        a, b, _ = self.mixed_rosters()
        self.team.section='A'; self.team.save()
        response=self.client.get('/api/defense/board/operations/?management=1&search=NoMatch&stage=NoMatch')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual({e['id'] for e in response.data['entries']}, {a.pk,b.pk})
        self.assertTrue(all(e['section']=='A' and e['year_level']=='3rd Year' for e in response.data['entries']))
        self.assertEqual(response.data['active_semester']['id'], self.semester.pk)

    def test_preview_does_not_grant_documenter_role_or_notify(self):
        from notifications.models import Notification
        a = self.schedule()
        documenter = get_user_model().objects.create_user(username='new-documenter', role='faculty')
        self.assertFalse(documenter.is_documenter)
        response = self.management_operation([a], action='preview_update', changes={'documenter_id': documenter.pk})
        self.assertEqual(response.status_code, 200, response.data)
        documenter.refresh_from_db(); a.refresh_from_db()
        self.assertFalse(documenter.is_documenter)
        self.assertIsNone(a.documenter_id)
        self.assertFalse(Notification.objects.exists())
        response = self.management_operation([a], changes={'documenter_id': documenter.pk})
        self.assertEqual(response.status_code, 200, response.data)
        documenter.refresh_from_db()
        self.assertTrue(documenter.is_documenter)

    def test_change_reasons_are_not_exposed_on_student_board_and_history_is_scoped(self):
        a = self.schedule()
        response = self.management_operation([a], changes={'room': 'Room 302'})
        self.assertEqual(response.status_code, 200, response.data)
        self.client.force_authenticate(user=self.student)
        response = self.client.get('/api/defense/board/')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(all(s['latest_change'] is None for s in response.data['schedules']))
        self.assertEqual(self.client.get(f'/api/defense/board/operations/?history_for={a.pk}').status_code, 403)
        self.client.force_authenticate(user=self.admin)
        self.assertEqual(self.client.get('/api/defense/board/operations/?history_for=bad-id').status_code, 400)

    def test_empty_past_schedule_is_removable(self):
        schedule = self.schedule()
        preview = self.operation(schedule, action='preview_delete')
        self.assertEqual(preview.status_code, 200)
        self.assertEqual(preview.data['empty'], 1)
        response = self.operation(schedule, action='delete')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(DefenseSchedule.objects.filter(pk=schedule.pk).exists())

    def test_operation_preview_explains_edit_and_roster_protection(self):
        schedule = self.schedule()
        grade = self.grade(schedule)
        submission = self.submission(grade)
        entry = self.operation(schedule, action='preview_delete').data['entries'][0]
        self.assertTrue(entry['can_edit'])
        self.assertFalse(entry['can_reschedule'])
        self.assertEqual(entry['submitted_panelist_ids'], [self.panelist.pk])
        self.assertIn(self.panelist.pk, entry['panelist_ids'])
        self.assertEqual(entry['adviser_id'], schedule.team.adviser_id)
        submission.is_void = True
        submission.save()
        grade.status = 'published'
        grade.adviser_score = Decimal('90')
        grade.peer_score = Decimal('90')
        grade.save()
        entry = self.operation(schedule, action='preview_delete').data['entries'][0]
        self.assertFalse(entry['can_edit'])
        self.assertFalse(entry['can_reschedule'])
        self.assertEqual(entry['submitted_panelist_ids'], [])

    def test_correction_choices_use_stable_evaluator_and_student_identity(self):
        from grading.grades.corrections import correction_details
        schedule = self.schedule()
        grade = self.grade(schedule)
        self.submission(grade)
        details = correction_details(grade)
        self.assertEqual(details['scores'][0]['evaluator_key'], f'faculty:{self.panelist.pk}')
        self.assertIsNone(details['scores'][0]['student_id'])

    def test_saved_draft_and_zero_score_are_protected(self):
        schedule = self.schedule()
        PanelistEvaluationDraft.objects.create(schedule=schedule, panelist=self.panelist, context_signature='test', submissions=[{'criteria_scores': [{'score': 0}]}])
        self.assertEqual(self.operation(schedule, action='delete').status_code, 409)
        schedule.evaluation_drafts.all().delete()
        grade = self.grade(schedule)
        grade.adviser_score = Decimal('0')
        grade.save()
        self.assertEqual(self.operation(schedule, action='delete').status_code, 409)

    def test_blank_minutes_are_empty_written_minutes_are_protected(self):
        schedule = self.schedule()
        minutes = DefenseMinutes.objects.create(schedule=schedule, team_name=self.team.name, project_title='', adviser_name='',
            defense_stage_label=self.stage.label, defense_date=schedule.scheduled_date, defense_time=schedule.start_time, room=schedule.room, documenter_name='')
        self.assertEqual(self.operation(schedule, action='preview_delete').data['empty'], 1)
        MinutesPanelistComment.objects.create(minutes=minutes, panelist_name_snapshot='Panel', comments='Revise the methodology')
        self.assertEqual(self.operation(schedule, action='delete').status_code, 409)

    def test_session_delete_is_atomic_and_empty_only_is_explicit(self):
        a = self.schedule()
        b = self.schedule()
        b.team = self.create_ready_team()
        b.session_id = a.session_id
        b.start_time = '09:00'
        b.save()
        grade = self.grade(a)
        self.submission(grade)
        preview = self.operation(a, action='preview_delete', target='session')
        self.assertEqual(preview.data['total'], 2)
        expected = preview.data['expected_revisions']
        response = self.operation(a, action='delete', target='session', expected_revisions=expected)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(DefenseSchedule.objects.filter(pk__in=[a.pk, b.pk]).count(), 2)
        response = self.operation(a, action='delete', target='session', empty_only=True, expected_revisions=expected)
        self.assertEqual(response.data['deleted'], 1)
        self.assertTrue(DefenseSchedule.objects.filter(pk=a.pk).exists())

    def test_stale_revision_is_rejected(self):
        schedule = self.schedule()
        response = self.operation(schedule, expected_revisions={str(schedule.pk): 99}, changes={'room': 'Room 401'})
        self.assertEqual(response.status_code, 409)
        schedule.refresh_from_db()
        self.assertEqual(schedule.room, 'Room 301')

    def test_replace_unsubmitted_panelist_preserves_other_scores_and_session(self):
        schedule = self.schedule()
        session_id = schedule.session_id
        grade = self.grade(schedule)
        original = self.submission(grade)
        replacement = get_user_model().objects.create_user(username='replacement', role='faculty', is_panelist=True)
        response = self.operation(schedule, changes={'panelist_ids': [self.panelist.pk, replacement.pk], 'chair_panelist_id': self.panelist.pk})
        self.assertEqual(response.status_code, 200, response.data)
        schedule.refresh_from_db()
        self.assertEqual(schedule.session_id, session_id)
        self.assertTrue(PanelistGradeSubmission.objects.filter(pk=original.pk).exists())
        self.assertFalse(schedule.panel_assignments.filter(panelist=self.second_panelist).exists())

    def test_removing_submitted_panelist_is_rejected(self):
        schedule = self.schedule()
        self.submission(self.grade(schedule))
        response = self.operation(schedule, changes={'panelist_ids': [self.second_panelist.pk], 'chair_panelist_id': self.second_panelist.pk})
        self.assertEqual(response.status_code, 400)

    def test_interrupted_schedule_blocks_grading_and_can_resume(self):
        from .panelist_evaluation import grading_unavailable_reason
        schedule = self.schedule()
        self.assertEqual(self.operation(schedule, changes={'operation_state': 'paused'}).status_code, 200)
        schedule.refresh_from_db()
        self.assertIn('paused', grading_unavailable_reason(schedule))
        self.assertEqual(self.operation(schedule, changes={'operation_state': 'normal'}).status_code, 200)

    def test_panel_readiness_requires_every_assigned_evaluator(self):
        grade = self.grade(self.schedule())
        self.submission(grade)
        self.assertFalse(team_grading_readiness(grade, self.semester, 'capstone')['panel_complete'])
        self.submission(grade, self.second_panelist, first=9)
        self.assertTrue(team_grading_readiness(grade, self.semester, 'capstone')['panel_complete'])

    def test_source_score_correction_and_preview(self):
        grade = self.grade(self.schedule())
        submission = self.submission(grade)
        row = submission.criterion_scores.get(criterion=self.criterion)
        changes = {'criterion': {'id': row.pk, 'score': '9'}}
        preview = self.correction(grade, changes=changes, preview=True)
        self.assertEqual(preview.status_code, 200, preview.data)
        row.refresh_from_db()
        self.assertEqual(row.score, Decimal('2'))
        response = self.correction(grade, changes=changes)
        self.assertEqual(response.status_code, 200, response.data)
        row.refresh_from_db()
        grade.refresh_from_db()
        self.assertEqual(row.score, Decimal('9'))
        self.assertEqual(grade.panel_score, Decimal('90'))
        self.assertEqual(response.data['before']['criteria'][0]['score'], '2.00')
        self.assertEqual(grade.corrections.get().status, 'applied')

    def test_published_amendment_waits_for_explicit_approval(self):
        grade = self.grade(self.schedule())
        submission = self.submission(grade)
        self.submission(grade, self.second_panelist, first=9)
        grade.adviser_score = grade.peer_score = Decimal('95')
        grade.status = 'published'
        grade.save()
        row = submission.criterion_scores.get(criterion=self.criterion)
        response = self.correction(grade, changes={'criterion': {'id': row.pk, 'score': '9'}})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'pending')
        row.refresh_from_db()
        self.assertEqual(row.score, Decimal('2'))
        approval = self.correction(grade, action='approve', correction_id=response.data['id'], acknowledge_published_change=True)
        self.assertEqual(approval.status_code, 200, approval.data)
        grade.refresh_from_db()
        self.assertEqual(grade.status, 'published')
        self.assertEqual(grade.panel_score, Decimal('90'))

    def test_missing_reason_and_out_of_range_score_are_rejected(self):
        grade = self.grade(self.schedule())
        row = self.submission(grade).criterion_scores.first()
        self.assertEqual(self.correction(grade, reason='', changes={'criterion': {'id': row.pk, 'score': 9}}).status_code, 400)
        self.assertEqual(self.correction(grade, changes={'criterion': {'id': row.pk, 'score': 11}}).status_code, 400)

    def test_audit_failure_rolls_back_deletion_and_correction(self):
        schedule = self.schedule()
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('audit unavailable')):
            response = self.operation(schedule, action='delete')
        self.assertEqual(response.status_code, 500)
        self.assertTrue(DefenseSchedule.objects.filter(pk=schedule.pk).exists())
        grade = self.grade(schedule)
        row = self.submission(grade).criterion_scores.first()
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('audit unavailable')):
            response = self.correction(grade, changes={'criterion': {'id': row.pk, 'score': 9}})
        self.assertEqual(response.status_code, 500)
        row.refresh_from_db()
        self.assertEqual(row.score, Decimal('2'))
        self.assertFalse(grade.corrections.exists())

    def test_non_admin_cannot_correct_scores(self):
        grade = self.grade(self.schedule())
        self.client.force_authenticate(user=self.panelist)
        self.assertEqual(self.client.get(f'/api/grading/grades/{grade.pk}/corrections/').status_code, 403)

    def test_voided_evaluation_remains_protected_and_can_be_replaced(self):
        schedule = self.schedule()
        grade = self.grade(schedule)
        original = self.submission(grade)
        self.submission(grade, self.second_panelist, first=9)
        response = self.correction(grade, changes={'void_submission': original.pk})
        self.assertEqual(response.status_code, 200, response.data)
        original.refresh_from_db()
        grade.refresh_from_db()
        self.assertTrue(original.is_void)
        self.assertEqual(original.criterion_scores.count(), 2)
        self.assertTrue(original.void_reason)
        self.assertEqual(grade.panel_score, Decimal('90'))
        self.assertFalse(team_grading_readiness(grade, self.semester, 'capstone')['panel_complete'])
        response = self.operation(schedule, changes={'panelist_ids': [self.second_panelist.pk], 'chair_panelist_id': self.second_panelist.pk})
        self.assertEqual(response.status_code, 200, response.data)
        schedule.refresh_from_db()
        self.assertTrue(team_grading_readiness(grade, self.semester, 'capstone')['panel_complete'])
        self.assertEqual(self.operation(schedule, action='delete').status_code, 409)

    def test_published_amendment_cannot_silently_change_a_passing_result(self):
        grade = self.grade(self.schedule())
        original = self.submission(grade)
        self.submission(grade, self.second_panelist, first=2)
        grade.adviser_score = grade.peer_score = Decimal('80')
        grade.status = 'published'
        grade.save()
        row = original.criterion_scores.get(criterion=self.criterion)
        response = self.correction(grade, changes={'criterion': {'id': row.pk, 'score': '10'}})
        self.assertEqual(response.status_code, 400, response.data)
        row.refresh_from_db()
        self.assertEqual(row.score, Decimal('2'))
        self.assertFalse(grade.corrections.exists())

    def test_amendment_approval_rejects_changed_grade(self):
        grade = self.grade(self.schedule())
        original = self.submission(grade)
        self.submission(grade, self.second_panelist, first=9)
        grade.adviser_score = grade.peer_score = Decimal('95')
        grade.status = 'published'
        grade.save()
        row = original.criterion_scores.get(criterion=self.criterion)
        request = self.correction(grade, changes={'criterion': {'id': row.pk, 'score': '9'}})
        self.assertEqual(request.status_code, 200, request.data)
        grade.refresh_from_db()
        grade.adviser_score = Decimal('96')
        grade.save()
        response = self.correction(grade, action='approve', correction_id=request.data['id'], acknowledge_published_change=True)
        self.assertEqual(response.status_code, 409)
        row.refresh_from_db()
        self.assertEqual(row.score, Decimal('2'))
        self.assertEqual(grade.corrections.get().status, 'pending')

    def test_submission_rechecks_context_after_locking(self):
        from django.core.exceptions import ValidationError
        from .panelist_evaluation import evaluation_context
        from grading.grades.services import submit_panelist_grade
        schedule = self.schedule()
        grade = self.grade(schedule)
        context = evaluation_context(schedule, grade)
        DefenseSchedule.objects.filter(pk=schedule.pk).update(revision=2)
        with self.assertRaises(ValidationError):
            submit_panelist_grade(schedule, grade, [
                {'criterion_id': self.criterion.pk, 'score': 9},
                {'criterion_id': self.second_criterion.pk, 'score': 9},
            ], panelist=self.panelist, expected_context=context)
        self.assertFalse(grade.panelist_submissions.exists())

    def test_bulk_conflict_rolls_back_every_schedule(self):
        a = self.schedule()
        b = self.schedule()
        b.team = self.create_ready_team()
        b.session_id = a.session_id
        b.start_time = '09:00'
        b.save()
        other = self.schedule()
        other.team = self.create_ready_team(name='Team Third', username='2024-0003')
        other.start_time = '10:00'
        other.room = 'Room 999'
        other.save()
        response = self.operation(a, target='session', expected_revisions={str(a.pk): 1, str(b.pk): 1}, changes={'shift_minutes': 60})
        self.assertEqual(response.status_code, 400, response.data)
        a.refresh_from_db()
        b.refresh_from_db()
        self.assertEqual(a.start_time.hour, 8)
        self.assertEqual(b.start_time.hour, 9)
        self.assertEqual(a.revision, 1)
        self.assertEqual(b.revision, 1)

    def test_published_grade_blocks_operational_roster_changes(self):
        schedule = self.schedule()
        grade = self.grade(schedule)
        grade.panel_score = grade.adviser_score = grade.peer_score = Decimal('90')
        grade.status = 'published'
        grade.save()
        response = self.operation(schedule, changes={'chair_panelist_id': self.second_panelist.pk})
        self.assertEqual(response.status_code, 400, response.data)
        self.assertTrue(schedule.panel_assignments.filter(panelist=self.panelist, is_chair=True).exists())

    def test_published_grade_cannot_be_made_incomplete(self):
        grade = self.grade(self.schedule())
        grade.panel_score = grade.adviser_score = grade.peer_score = Decimal('90')
        grade.status = 'published'
        grade.save()
        response = self.correction(grade, changes={'aggregate': {'adviser_score': None}})
        self.assertEqual(response.status_code, 400, response.data)
        grade.refresh_from_db()
        self.assertEqual(grade.adviser_score, Decimal('90'))
        self.assertEqual(grade.status, 'published')
        self.assertFalse(grade.corrections.exists())

    def test_external_replacement_revokes_old_access_and_creates_one_session_invitation(self):
        from user_management.models import ExternalEvaluator
        from user_management.external_evaluators import create_invitations, invitation_schedule_ids
        a = self.schedule()
        b = self.schedule()
        b.team = self.create_ready_team()
        b.session_id = a.session_id
        b.start_time = '09:00'
        b.save()
        previous = ExternalEvaluator.objects.create(name='Previous evaluator', status='approved')
        replacement = ExternalEvaluator.objects.create(name='Replacement evaluator', status='approved')
        original = create_invitations([previous], [a, b], self.admin)[0]
        response = self.operation(a, target='session', expected_revisions={str(a.pk): 1, str(b.pk): 1},
                                  changes={'external_evaluator_ids': [replacement.pk]})
        self.assertEqual(response.status_code, 200, response.data)
        original.refresh_from_db()
        self.assertFalse(original.is_active)
        self.assertGreater(original.access_version, 1)
        self.assertEqual(invitation_schedule_ids(original), [])
        invitation = replacement.invitations.get()
        self.assertEqual(set(invitation_schedule_ids(invitation)), {a.pk, b.pk})

    def test_conflicts_are_detected_across_midnight(self):
        from datetime import timedelta
        schedule = self.schedule()
        schedule.start_time = '23:30'
        schedule.save()
        other = self.schedule()
        other.team = self.create_ready_team()
        other.scheduled_date = schedule.scheduled_date + timedelta(days=1)
        other.start_time = '00:15'
        other.room = 'Room 999'
        other.save()
        response = self.operation(schedule, changes={'room': 'Room 502'})
        self.assertEqual(response.status_code, 400, response.data)
        schedule.refresh_from_db()
        self.assertEqual(schedule.room, 'Room 301')

    def stage_schedules(self):
        import uuid
        from defense.stages.models import DefenseStage
        a = self.schedule()
        b = self.schedule()
        b.team = self.create_ready_team()
        b.session_id = uuid.uuid4()
        b.start_time = '09:00'
        b.save()
        other = self.schedule()
        other.team = self.create_ready_team(name='Team Other Stage', username='2024-0003')
        other.defense_stage = DefenseStage.objects.exclude(pk=self.stage.pk).first()
        other.rubric = None
        other.start_time = '10:00'
        other.save()
        return a, b, other

    def test_stage_selected_operation_updates_distinct_sessions_only_in_its_stage(self):
        a, b, other = self.stage_schedules()
        sessions = (a.session_id, b.session_id)
        preview = self.operation(a, action='preview_delete', target='stage')
        self.assertEqual({e['id'] for e in preview.data['entries']}, {a.pk, b.pk})
        self.assertEqual({e['session_id'] for e in preview.data['entries']}, {str(s) for s in sessions})
        response = self.operation(a, target='stage_selected', schedule_ids=[a.pk, b.pk],
            expected_revisions=preview.data['expected_revisions'], changes={'operation_state': 'paused'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['updated'], 2)
        for schedule in (a, b, other):
            schedule.refresh_from_db()
        self.assertEqual((a.operation_state, b.operation_state, other.operation_state), ('paused', 'paused', 'normal'))
        self.assertEqual((a.session_id, b.session_id), sessions)
        self.assertEqual(SystemAuditLog.objects.filter(action='schedule.operational_change').count(), 2)

    def test_stage_selected_rejects_records_in_another_stage_or_semester(self):
        from academic_period_management.models import Semester
        a, b, other = self.stage_schedules()
        response = self.operation(a, target='stage_selected', schedule_ids=[a.pk, other.pk],
            expected_revisions={str(a.pk): 1, str(other.pk): 1}, changes={'operation_state': 'paused'})
        self.assertEqual(response.status_code, 403, response.data)
        previous = Semester.objects.create(school_year=self.school_year, label=Semester.FIRST)
        b.semester = previous
        b.save()
        response = self.operation(a, target='stage_selected', schedule_ids=[a.pk, b.pk],
            expected_revisions={str(a.pk): 1, str(b.pk): 1}, changes={'operation_state': 'paused'})
        self.assertEqual(response.status_code, 403, response.data)
        self.assertFalse(DefenseSchedule.objects.filter(pk__in=[a.pk, b.pk, other.pk], operation_state='paused').exists())

    def test_session_selected_still_rejects_a_different_session(self):
        a, b, _ = self.stage_schedules()
        response = self.operation(a, target='selected', schedule_ids=[a.pk, b.pk],
            expected_revisions={str(a.pk): 1, str(b.pk): 1}, changes={'operation_state': 'paused'})
        self.assertEqual(response.status_code, 403, response.data)

    def test_stage_selected_requires_active_semester_and_valid_revisions(self):
        a, b, _ = self.stage_schedules()
        response = self.operation(a, target='stage_selected', schedule_ids=[a.pk, b.pk],
            expected_revisions={str(a.pk): 1, str(b.pk): 99}, changes={'operation_state': 'paused'})
        self.assertEqual(response.status_code, 409, response.data)
        self.semester.is_active = False
        self.semester.save()
        response = self.operation(a, target='stage_selected', schedule_ids=[a.pk, b.pk],
            expected_revisions={str(a.pk): 1, str(b.pk): 1}, changes={'operation_state': 'paused'})
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(DefenseSchedule.objects.filter(pk__in=[a.pk, b.pk], operation_state='paused').exists())

    def test_stage_delete_preserves_evidence_and_other_stages(self):
        a, b, other = self.stage_schedules()
        self.submission(self.grade(a))
        preview = self.operation(a, action='preview_delete', target='stage')
        response = self.operation(a, action='delete', target='stage', empty_only=True,
            expected_revisions=preview.data['expected_revisions'])
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['deleted'], 1)
        self.assertTrue(DefenseSchedule.objects.filter(pk=a.pk).exists())
        self.assertFalse(DefenseSchedule.objects.filter(pk=b.pk).exists())
        self.assertTrue(DefenseSchedule.objects.filter(pk=other.pk).exists())
