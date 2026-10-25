from datetime import date, datetime, time
from tempfile import TemporaryDirectory
from pathlib import Path
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from rest_framework.exceptions import ValidationError
from rest_framework.test import APITestCase

from academic_period_management.calendar import calendar_schedule_issues, schedule_time_payload, validate_defense_date
from academic_period_management.models import SchoolYear, Semester, SemesterTransitionLog
from academic_period_management.services import build_semester_transition_preview
from defense.scheduler.models import DefenseSchedule
from defense.scheduler.operations import execute_operation
from student_teams.models import StudentTeam


class SemesterCalendarTests(APITestCase):
    def setUp(self):
        self.admin = get_user_model().objects.create_user(username='calendar-admin', role='admin')
        self.client.force_authenticate(self.admin)
        self.year = SchoolYear.objects.create(label='2024-2025')
        self.url = f'/api/academic-periods/{self.year.pk}/semesters/'
        self.draft = {'label': Semester.FIRST, 'starts_on': '2024-01-10', 'ends_on': '2025-06-15'}

    def term(self, **overrides):
        return Semester.objects.create(school_year=self.year, label=Semester.SECOND,
            starts_on=date(2024, 1, 10), ends_on=date(2025, 6, 15),
            capstone_peer_evaluation_enabled=False, capstone_adviser_grading_enabled=False, **overrides)

    def schedule(self, semester, day='2024-11-27', hour='10:00:24'):
        student = get_user_model().objects.create_user(username=f'calendar-student-{StudentTeam.objects.count()}', role='student')
        team = StudentTeam.objects.create(name='Calendar team', leader=student, semester=semester,
            level=StudentTeam.LEVEL_1_PIT, year_level='1st Year')
        return DefenseSchedule.objects.create(team=team, semester=semester, scope='pit',
            event_name='Calendar event', scheduled_date=day, start_time=hour, room='Room 304')

    def test_new_term_requires_ordered_calendar_and_does_not_activate_by_default(self):
        for data in [{'label': Semester.FIRST}, {**self.draft, 'ends_on': '2024-01-10'},
                     {**self.draft, 'ends_on': '2024-01-09'}]:
            self.assertEqual(self.client.post(self.url, data, format='json').status_code, 400)
        response = self.client.post(self.url, self.draft, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertFalse(response.data['semester']['is_active'])
        self.assertEqual(response.data['semester']['starts_on'], '2024-01-10')

    def test_initial_creation_and_activation_are_atomic_and_retry_safe(self):
        payload = {**self.draft, 'set_active': True, 'request_id': 'calendar-initial'}
        response = self.client.post(self.url, payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        retry = self.client.post(self.url, payload, format='json')
        self.assertEqual(retry.status_code, 201, retry.data)
        self.assertEqual(retry.data['semester']['id'], response.data['semester']['id'])
        self.assertEqual(Semester.objects.count(), 1)
        self.assertEqual(SemesterTransitionLog.objects.count(), 1)
        self.assertEqual(self.client.post(self.url, {**payload, 'ends_on': '2025-06-16'}, format='json').status_code, 400)
        self.term(is_active=True)
        old_retry = self.client.post(self.url, payload, format='json')
        self.assertEqual(old_retry.status_code, 400)
        self.assertEqual(old_retry.data['code'], 'stale_creation')

    def test_proposed_review_creates_nothing_and_existing_active_term_switches_on_confirm(self):
        current = self.term(is_active=True)
        payload = {**self.draft, 'set_active': True}
        preview = self.client.post(self.url + 'transition-preview/', payload, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual(Semester.objects.count(), 1)
        self.assertIsNone(preview.data['target_semester']['id'])
        response = self.client.post(self.url, {**payload,
            'preview_revision': preview.data['preview_revision'], 'request_id': 'calendar-switch'}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        current.refresh_from_db()
        self.assertFalse(current.is_active)
        self.assertEqual(Semester.objects.filter(is_active=True).count(), 1)

    def test_invalidated_review_or_activation_failure_leaves_no_new_term(self):
        current = self.term(is_active=True)
        payload = {**self.draft, 'set_active': True}
        response = self.client.post(self.url, payload, format='json')
        self.assertEqual(response.status_code, 400)
        preview = self.client.post(self.url + 'transition-preview/', payload, format='json').data
        with patch('academic_period_management.services.switch_active_semester', side_effect=ValidationError('Blocked')):
            response = self.client.post(self.url, {**payload, 'preview_revision': preview['preview_revision']}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(Semester.objects.count(), 1)
        current.refresh_from_db()
        self.assertTrue(current.is_active)

    def test_calendar_update_reports_existing_mismatch_and_preserves_records(self):
        term = self.term(is_active=True)
        schedule = self.schedule(term, day='2026-11-27')
        response = self.client.patch(f'/api/academic-periods/semesters/{term.pk}/',
            {'starts_on': '2024-01-10', 'ends_on': '2025-06-15'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['calendar_issues']['schedule_ids'], [schedule.pk])
        schedule.refresh_from_db()
        self.assertEqual(schedule.scheduled_date, date(2026, 11, 27))

    def test_database_rejects_partial_or_reversed_calendar(self):
        for start, end in [(date(2024, 1, 10), None), (None, date(2025, 6, 15)),
                           (date(2025, 6, 15), date(2024, 1, 10))]:
            with self.assertRaises(IntegrityError), transaction.atomic():
                Semester.objects.create(school_year=self.year, label=Semester.FIRST, starts_on=start, ends_on=end)

    def test_date_validator_uses_current_calendar_inclusive_boundaries(self):
        term = self.term()
        for day in [date(2024, 1, 10), date(2025, 6, 15)]:
            validate_defense_date(term, day)
        for day in [date(2024, 1, 9), date(2025, 6, 16)]:
            with self.assertRaises(ValidationError):
                validate_defense_date(term, day)
        Semester.objects.filter(pk=term.pk).update(starts_on=None, ends_on=None)
        with self.assertRaises(ValidationError):
            validate_defense_date(term, date(2024, 11, 27))

    def test_operational_shift_cannot_escape_calendar_but_unrelated_edits_allow_legacy(self):
        term = self.term(is_active=True)
        schedule = self.schedule(term, day='2025-06-15', hour='23:30:00')
        request = {'action': 'preview_update', 'target': 'schedule', 'anchor_id': schedule.pk,
            'reason': 'Calendar boundary test', 'expected_revisions': {str(schedule.pk): schedule.revision},
            'changes': {'shift_minutes': 120}}
        with self.assertRaises(ValidationError):
            execute_operation(self.admin, request)
        schedule.refresh_from_db()
        self.assertEqual(schedule.scheduled_date, date(2025, 6, 15))
        Semester.objects.filter(pk=term.pk).update(starts_on=None, ends_on=None)
        result = execute_operation(self.admin, {**request, 'changes': {'room': 'Room 305'}})
        self.assertEqual(result['updated'], 1)

    def test_absolute_timestamp_has_manila_offset_and_seconds(self):
        schedule = self.schedule(self.term())
        payload = schedule_time_payload(schedule)
        self.assertEqual(payload['scheduled_at'], '2024-11-27T10:00:24+08:00')
        self.assertIsNotNone(datetime.fromisoformat(payload['server_now']).tzinfo)

    def test_students_cannot_create_or_preview_terms(self):
        student = get_user_model().objects.create_user(username='calendar-unauthorized', role='student')
        self.client.force_authenticate(student)
        for url in [self.url, self.url + 'transition-preview/']:
            self.assertEqual(self.client.post(url, self.draft, format='json').status_code, 403)

    def test_sample_repair_is_exact_backed_up_and_preserves_assignments(self):
        from .calendar_repair import repair_sample_calendar
        term = self.term(is_active=True)
        schedule = self.schedule(term, day='2026-11-27')
        kwargs = dict(semester_id=term.pk, starts_on=date(2024, 1, 10), ends_on=date(2025, 6, 15),
            source_date=date(2026, 11, 27), target_date=date(2024, 2, 27), expected_count=1,
            actor=self.admin, reason='Explicit sample data correction')
        report = repair_sample_calendar(**kwargs)
        self.assertFalse(report['applied'])
        schedule.refresh_from_db()
        self.assertEqual(schedule.scheduled_date, date(2026, 11, 27))
        with TemporaryDirectory() as directory:
            backup = Path(directory) / 'before.json'
            result = repair_sample_calendar(**kwargs, apply=True, backup_path=backup)
            self.assertTrue(result['applied'])
            self.assertTrue(backup.exists())
        schedule.refresh_from_db()
        self.assertEqual(schedule.scheduled_date, date(2024, 2, 27))
        self.assertEqual(schedule.start_time, time(10, 0, 24))
        self.assertEqual(schedule.room, 'Room 304')
        self.assertEqual(schedule.revision, 2)
        with self.assertRaises(ValueError):
            repair_sample_calendar(**kwargs)

    def test_student_defaults_to_active_team_and_explicit_history_remains_accessible(self):
        from student_teams.models import TeamMembership
        active = self.term(is_active=True)
        history = Semester.objects.create(school_year=self.year, label=Semester.FIRST)
        student = get_user_model().objects.create_user(username='calendar-history-student', role='student')
        teams = []
        for semester in [active, history]:
            team = StudentTeam.objects.create(name=f'Term team {semester.pk}', leader=student,
                semester=semester, level=StudentTeam.LEVEL_1_PIT, year_level='1st Year')
            TeamMembership.objects.create(team=team, student=student, is_leader=True)
            teams.append(team)
        self.client.force_authenticate(student)
        response = self.client.get('/api/dashboards/student/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['team']['id'], teams[0].pk)
        archived = self.client.get(f'/api/dashboards/student/?team_id={teams[1].pk}')
        self.assertEqual(archived.status_code, 200)
        self.assertEqual(archived.data['team']['id'], teams[1].pk)
