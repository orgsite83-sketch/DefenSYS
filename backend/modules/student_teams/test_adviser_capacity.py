import json
from concurrent.futures import ThreadPoolExecutor
from io import StringIO
from threading import Barrier
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.management import call_command
from django.db import close_old_connections, connection
from django.test import TransactionTestCase
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from .adviser_capacity import capacity_projections, save_exception
from .models import AdviserCapacityException, StudentTeam, TeamTermParticipation


class CapacityFixtures:
    def setUp(self):
        self.admin = get_user_model().objects.create_user(username='capacity-admin', role='admin')
        self.adviser = get_user_model().objects.create_user(username='capacity-faculty', role='faculty')
        self.other = get_user_model().objects.create_user(username='capacity-other', role='faculty')
        year = SchoolYear.objects.create(label='2026-2027')
        self.term = Semester.objects.create(school_year=year, label=Semester.SECOND, is_active=True,
            starts_on='2026-01-01', ends_on='2026-12-31', capstone_team_creation_enabled=True)
        next_year = SchoolYear.objects.create(label='2027-2028')
        self.second = Semester.objects.create(school_year=next_year, label=Semester.SECOND)
        if hasattr(self.client, 'force_authenticate'):
            self.client.force_authenticate(self.admin)

    def team(self, index, adviser=None, **extra):
        student = get_user_model().objects.create_user(username=f'capacity-student-{index}', role='student')
        data = dict(name=f'Capacity team {index}', level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year', semester=self.term, intake_semester=self.term,
            leader=student, adviser=adviser or self.adviser)
        data.update(extra)
        return StudentTeam.objects.create(**data)

    def approve(self, **extra):
        data = dict(adviser_id=self.adviser.pk, semester_id=self.term.pk, approved_limit=5,
            authorization='Department chair decision', reason='Additional solo project', reference='DEP-1')
        data.update(extra)
        return save_exception(self.admin, data)

    def fill(self):
        return [self.team(i) for i in range(4)]


class AdviserCapacityTests(CapacityFixtures, APITestCase):
    def test_readiness_uses_approved_capacity_and_total_workload(self):
        from defense.scheduler.serializers import ScheduleTeamSerializer
        from student_teams.adviser_capacity import capacity_projections as project
        teams = self.fill()
        self.approve()
        fifth = self.team(5, section='Another section')
        with patch('student_teams.adviser_capacity.capacity_projections', wraps=project) as projections:
            # A filtered section must still show the adviser's complete load.
            rows = ScheduleTeamSerializer([teams[0], fifth], many=True).data
        projections.assert_called_once()
        for row in rows:
            capacity = row['adviser_capacity']
            self.assertEqual((capacity['active_count'], capacity['effective_limit']), (5, 5))
            self.assertTrue(capacity['has_exception'])
            self.assertFalse(capacity['is_overloaded'])

    def test_readiness_retains_warning_after_exception_revocation(self):
        from defense.scheduler.serializers import ScheduleTeamSerializer
        self.fill()
        self.approve()
        fifth = self.team(5)
        save_exception(self.admin, {'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
                                  'reason': 'Authorization withdrawn'}, revoke=True)
        capacity = ScheduleTeamSerializer(fifth).data['adviser_capacity']
        self.assertEqual((capacity['active_count'], capacity['effective_limit']), (5, 4))
        self.assertFalse(capacity['has_exception'])
        self.assertTrue(capacity['is_overloaded'])

    def test_standard_approved_and_other_adviser_limits(self):
        self.fill()
        with self.assertRaises(ValidationError):
            self.team(4)
        self.approve()
        self.team(5)
        with self.assertRaises(ValidationError):
            self.team(6)
        for i in range(10, 14):
            self.team(i, self.other)
        with self.assertRaises(ValidationError):
            self.team(14, self.other)
        self.assertEqual(capacity_projections([self.adviser.pk])[self.adviser.pk]['active_count'], 5)

    def test_revoke_preserves_edits_and_rejects_new_work(self):
        teams = self.fill()
        self.approve()
        fifth = self.team(5)
        save_exception(self.admin, {'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
                                  'reason': 'Authorization withdrawn'}, revoke=True)
        fifth.name = 'Still advising'
        fifth.save()
        fifth.status = StudentTeam.STATUS_APPROVED
        fifth.save()
        with self.assertRaises(ValidationError):
            self.team(6)
        capacity = capacity_projections([self.adviser.pk])[self.adviser.pk]
        self.assertEqual((capacity['active_count'], capacity['effective_limit'], capacity['is_overloaded']), (5, 4, True))
        teams[0].status = StudentTeam.STATUS_FAILED
        teams[0].save()
        with self.assertRaises(ValidationError):
            self.team(7)

    def test_restart_and_reopening_need_capacity(self):
        teams = self.fill()
        self.approve()
        fifth = self.team(5)
        save_exception(self.admin, {'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
                                  'reason': 'Ended'}, revoke=True)
        fifth.project_version += 1
        with self.assertRaises(ValidationError):
            fifth.save()
        fifth.refresh_from_db()
        fifth.status = StudentTeam.STATUS_FAILED
        fifth.save()
        fifth.status = StudentTeam.STATUS_PENDING
        with self.assertRaises(ValidationError):
            fifth.save()

    def test_cross_sections_and_phases_share_limit(self):
        for i in range(4):
            self.team(i, section=f'BSIT-3{chr(65+i)}')
        with self.assertRaises(ValidationError):
            self.team(5, level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', section='BSIT-4A')

    def test_term_change_retires_and_cannot_reactivate_old_approval(self):
        teams = self.fill()
        exception = self.approve()
        teams.append(self.team(5))
        for team in teams:
            TeamTermParticipation.objects.get_or_create(team=team, semester=self.term)
        self.second.is_active = True
        self.second.save()
        exception.refresh_from_db()
        self.assertIsNotNone(exception.ended_at)
        teams[-1].semester = self.second
        teams[-1].save()  # Same ongoing project, no new place.
        self.term.is_active = True
        self.term.save()
        self.assertEqual(capacity_projections([self.adviser.pk])[self.adviser.pk]['effective_limit'], 4)
        self.assertTrue(SystemAuditLog.objects.filter(action='adviser_capacity.retired').exists())

    def test_explicit_renewal_preserves_original_creator(self):
        row = self.approve()
        original = row.created_at
        save_exception(self.admin, {'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
                                  'reason': 'Ended'}, revoke=True)
        row = self.approve(reason='Renewed department permission')
        self.assertEqual(row.created_at, original)
        self.assertEqual(row.created_by, self.admin)
        self.assertTrue(SystemAuditLog.objects.filter(action='adviser_capacity.renewed').exists())

    def test_failed_and_closed_history_excluded(self):
        teams = self.fill()
        teams[0].status = StudentTeam.STATUS_FAILED
        teams[0].save()
        from django.utils import timezone
        TeamTermParticipation.objects.filter(team=teams[1], semester=self.term).update(
            closed_at=timezone.now(), outcome='completed')
        self.assertEqual(capacity_projections([self.adviser.pk])[self.adviser.pk]['active_count'], 2)

    def test_api_permissions_and_validation(self):
        url = '/api/teams/adviser-capacity/'
        for user in (self.adviser, get_user_model().objects.create_user(username='capacity-student', role='student')):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get(url).status_code, 403)
            self.assertEqual(self.client.post(url, {}, format='json').status_code, 403)
        self.client.force_authenticate(self.admin)
        base = dict(adviser_id=self.adviser.pk, semester_id=self.term.pk, approved_limit=5,
            authorization='Department', reason='Approved')
        for invalid in ({'approved_limit': 4}, {'authorization': ' '}, {'reason': ''},
                        {'approved_limit': 5.5}, {'semester_id': self.second.pk}, {'adviser_id': 999999}):
            response = self.client.post(url, {**base, **invalid}, format='json')
            self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(self.client.post(url, base, format='json').status_code, 200)
        self.assertEqual(AdviserCapacityException.objects.count(), 1)
        self.assertEqual(self.client.get(url).data['advisers'][1]['capacity']['standard_limit'], 4)

    def test_audit_failure_rolls_back_authorization(self):
        with patch('student_teams.adviser_capacity.log_high_impact_action', side_effect=RuntimeError('audit unavailable')):
            with self.assertRaises(RuntimeError):
                self.approve()
        self.assertFalse(AdviserCapacityException.objects.exists())

    def test_import_preview_reserves_places_across_sections(self):
        from .bulk_import import preview_bulk_teams
        from user_management.academic_records.models import StudentAcademicRecord
        self.second.is_active = True
        self.second.capstone_team_creation_enabled = True
        self.second.save()
        self.term = self.second  # Regular Capstone 1 intake, not first-term continuation.
        self.fill()
        self.approve()
        rows = []
        for i in (5, 6):
            student = get_user_model().objects.create_user(username=f'import-capacity-{i}', role='student')
            StudentAcademicRecord.objects.create(student=student, semester=self.term, year_level='3rd Year', section=f'BSIT-3{chr(60+i)}')
            rows.append({'team_name': f'Imported {i}', 'level': StudentTeam.LEVEL_3_CAPSTONE,
                'year_level': '3rd Year', 'section': f'BSIT-3{chr(60+i)}', 'project_title': f'Project {i}',
                'leader_id': student.username, 'member_ids': [student.username], 'adviser_id': self.adviser.username})
        results, summary = preview_bulk_teams(rows, user=self.admin)
        self.assertTrue(results[0]['ready'], results)
        self.assertFalse(results[1]['ready'], results)
        self.assertEqual(results[0]['adviser_capacity']['effective_limit'], 5)
        self.assertEqual(summary['ready'], 1)

    def test_capacity_projection_query_count_does_not_scale_per_adviser(self):
        from django.test.utils import CaptureQueriesContext
        self.fill()
        ids = [self.adviser.pk, self.other.pk] + [get_user_model().objects.create_user(
            username=f'projection-faculty-{i}', role='faculty').pk for i in range(10)]
        with CaptureQueriesContext(connection) as queries:
            capacity_projections(ids)
        self.assertLessEqual(len(queries), 5)

    def test_old_batch_approval_cannot_authorize_new_intake_or_transfer(self):
        self.fill()
        approval = self.approve()
        old = self.team(5)
        self.second.is_active = True
        self.second.save()
        approval.refresh_from_db()
        self.assertEqual(approval.end_kind, 'retired')
        # Unfinished old projects continue to consume the concurrent workload.
        capacity = capacity_projections([self.adviser.pk])[self.adviser.pk]
        self.assertEqual((capacity['active_count'], capacity['effective_limit']), (5, 4))
        self.assertEqual(capacity['intake_semester_id'], self.second.pk)
        self.assertFalse(capacity['can_assign'])
        self.term = self.second
        with self.assertRaises(ValidationError):
            self.team(6)
        incoming = self.team(7, self.other)
        incoming.adviser = self.adviser
        with self.assertRaises(ValidationError):
            incoming.save()
        old.name = 'Existing assignment remains editable'
        old.save()
        new_approval = self.approve(approved_limit=6, reason='New batch decision')
        self.team(8)
        self.assertNotEqual(new_approval.pk, approval.pk)
        self.assertEqual(AdviserCapacityException.objects.count(), 2)

    def test_client_cannot_select_another_intake_for_approval(self):
        response = self.client.post('/api/teams/adviser-capacity/', {
            'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
            'intake_semester_id': self.second.pk, 'approved_limit': 5,
            'authorization': 'Department', 'reason': 'Wrong batch',
        }, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(AdviserCapacityException.objects.exists())

    def test_unverified_first_semester_cannot_create_batch_approval(self):
        target = Semester.objects.create(school_year=self.second.school_year, label=Semester.FIRST,
            is_active=True)
        response = self.client.post('/api/teams/adviser-capacity/', {
            'adviser_id': self.adviser.pk, 'semester_id': target.pk, 'approved_limit': 5,
            'authorization': 'Department', 'reason': 'No verified continuation',
        }, format='json')
        self.assertEqual(response.status_code, 400)

    def test_settings_save_preserves_approval_and_closed_unfinished_work_counts(self):
        teams = self.fill()
        approval = self.approve()
        self.term.capstone_peer_evaluation_enabled = False
        self.term.save(update_fields=['capstone_peer_evaluation_enabled'])
        approval.refresh_from_db()
        self.assertIsNone(approval.ended_at)
        from django.utils import timezone
        self.second.is_active = True
        self.second.save()
        TeamTermParticipation.objects.filter(team__in=teams).update(
            closed_at=timezone.now(), outcome='needs_review')
        capacity = capacity_projections([self.adviser.pk])[self.adviser.pk]
        self.assertEqual((capacity['active_count'], capacity['effective_limit']), (4, 4))

    def test_migration_maps_only_unique_intakes_and_never_renews(self):
        from django.apps import apps
        from importlib import import_module
        from types import SimpleNamespace
        from django.utils import timezone
        ended = timezone.now()
        approval = AdviserCapacityException.objects.create(adviser=self.adviser, semester=self.term,
            approved_limit=5, authorization='Department', reason='Legacy approval', ended_at=ended)
        unmapped = AdviserCapacityException.objects.create(adviser=self.other,
            semester=Semester.objects.create(school_year=self.term.school_year, label=Semester.FIRST),
            approved_limit=5, authorization='Department', reason='Unverified first semester')
        migrate = import_module('student_teams.migrations.0027_adviser_capacity_batch').map_legacy_batches
        migrate(apps, SimpleNamespace(connection=connection))
        approval.refresh_from_db()
        unmapped.refresh_from_db()
        self.assertEqual(approval.intake_semester_id, self.term.pk)
        self.assertEqual(approval.ended_at, ended)
        self.assertEqual(approval.end_kind, 'legacy_ended')
        self.assertIsNone(unmapped.intake_semester_id)

    def test_migration_keeps_conflicting_batch_approvals_unresolved(self):
        from django.apps import apps
        from importlib import import_module
        from types import SimpleNamespace
        from academic_period_management.models import SemesterTransitionLog
        target = Semester.objects.create(school_year=self.second.school_year, label=Semester.FIRST)
        team = self.team(1)
        SemesterTransitionLog.objects.create(from_semester=self.term, to_semester=target,
            impact_snapshot={'capstone_review': {'kind': 'continue'}, 'applied_team_ids': [team.pk]})
        approvals = [AdviserCapacityException.objects.create(adviser=self.adviser, semester=term,
            approved_limit=5, authorization='Department', reason='Legacy authorization')
            for term in (self.term, target)]
        migrate = import_module('student_teams.migrations.0027_adviser_capacity_batch').map_legacy_batches
        migrate(apps, SimpleNamespace(connection=connection))
        for row in approvals:
            row.refresh_from_db()
            self.assertIsNone(row.intake_semester_id)

    def test_readiness_separates_old_intake_from_current_assignment_capacity(self):
        from defense.scheduler.serializers import ScheduleTeamSerializer
        self.fill()
        self.approve()
        old = self.team(5)
        self.second.is_active = True
        self.second.save()
        self.term = self.second
        self.approve(approved_limit=6, reason='Fresh new batch authorization')
        incoming = self.team(6)
        rows = ScheduleTeamSerializer([old, incoming], many=True).data
        self.assertEqual(rows[0]['adviser_capacity']['effective_limit'], 4)
        self.assertEqual(rows[0]['adviser_capacity']['operating_capacity']['effective_limit'], 6)
        self.assertEqual(rows[1]['adviser_capacity']['effective_limit'], 6)

    def test_manual_api_uses_exception_and_overlimit_existing_edit(self):
        from user_management.academic_records.models import StudentAcademicRecord
        self.second.is_active = True
        self.second.capstone_team_creation_enabled = True
        self.second.save()
        self.term = self.second
        self.fill()
        self.approve()
        student = get_user_model().objects.create_user(username='api-fifth', role='student')
        StudentAcademicRecord.objects.create(student=student, semester=self.term, year_level='3rd Year')
        payload = {'name': 'API fifth team', 'level': StudentTeam.LEVEL_3_CAPSTONE,
            'year_level': '3rd Year', 'section': '', 'leader_id': student.pk, 'member_ids': [student.pk],
            'adviser_id': self.adviser.pk}
        created = self.client.post('/api/teams/', payload, format='json')
        self.assertEqual(created.status_code, 201, created.data)
        save_exception(self.admin, {'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
                                  'reason': 'Authorization ended'}, revoke=True)
        changed = self.client.patch(f"/api/teams/{created.data['team']['id']}/",
            {**payload, 'name': 'API fifth renamed'}, format='json')
        self.assertEqual(changed.status_code, 200, changed.data)

    def test_closed_participation_cannot_reopen_over_limit(self):
        self.fill()
        closed = self.team(5, status=StudentTeam.STATUS_FAILED)
        row = closed.term_participations.get()
        from django.utils import timezone
        row.closed_at, row.outcome = timezone.now(), 'completed'
        row.save()
        closed.status = StudentTeam.STATUS_PENDING
        with self.assertRaises(ValidationError):
            closed.save()
        # Isolate the participation guard when the team status is already open.
        closed.status = StudentTeam.STATUS_APPROVED
        StudentTeam.objects.filter(pk=closed.pk).update(status=closed.status)
        row.closed_at, row.outcome = None, 'open'
        with self.assertRaises(ValidationError):
            row.save()
        self.approve()
        row.save()
        self.assertEqual(capacity_projections([self.adviser.pk])[self.adviser.pk]['active_count'], 5)

    def test_reduced_limit_preserves_six_existing_projects(self):
        self.fill()
        self.approve(approved_limit=6)
        self.team(5)
        last = self.team(6)
        self.approve(approved_limit=5, reason='Department reduced the allowance')
        last.name = 'Existing sixth project'
        last.save()
        with self.assertRaises(ValidationError):
            self.team(7)
        self.assertTrue(capacity_projections([self.adviser.pk])[self.adviser.pk]['is_overloaded'])

    def test_prepared_import_revalidates_permission_after_preview(self):
        from user_management.academic_records.models import StudentAcademicRecord
        self.second.is_active = True
        self.second.capstone_team_creation_enabled = True
        self.second.save()
        self.term = self.second
        self.fill()
        self.approve()
        student = get_user_model().objects.create_user(username='prepared-fifth', role='student')
        StudentAcademicRecord.objects.create(student=student, semester=self.term, year_level='3rd Year', section='BSIT-3A')
        data = {'level': StudentTeam.LEVEL_3_CAPSTONE, 'year_level': '3rd Year', 'section': 'BSIT-3A',
            'teams': [{'team_name': 'Prepared fifth', 'member_ids': [student.username],
                       'leader_id': student.username, 'adviser_id': self.adviser.username}]}
        preview = self.client.post('/api/teams/generation/import/', data, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertTrue(preview.data['ready'], preview.data)
        save_exception(self.admin, {'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
                                  'reason': 'Permission ended after preview'}, revoke=True)
        result = self.client.post('/api/teams/generation/import/create/',
            {'preview_token': preview.data['preview_token']}, format='json')
        self.assertEqual(result.status_code, 400, result.data)
        self.assertEqual(StudentTeam.objects.filter(adviser=self.adviser).count(), 4)

    def test_audit_command_uses_effective_limit(self):
        self.fill()
        self.approve()
        self.team(5)
        output = StringIO()
        call_command('audit_adviser_capacity', stdout=output)
        self.assertEqual(json.loads(output.getvalue())['overloaded_advisers'], [])
        save_exception(self.admin, {'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
                                  'reason': 'Ended'}, revoke=True)
        output = StringIO()
        call_command('audit_adviser_capacity', stdout=output)
        self.assertEqual(json.loads(output.getvalue())['overloaded_advisers'][0]['effective_limit'], 4)


class AdviserCapacityConcurrencyTests(CapacityFixtures, TransactionTestCase):
    def race(self, *jobs):
        if connection.vendor != 'postgresql':
            self.skipTest('Requires PostgreSQL row locks')
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

    def test_assignment_and_term_switch_serialize(self):
        self.fill()
        row = self.approve()
        def assign():
            try:
                self.team(5)
                return 'assigned'
            except ValidationError:
                return 'full'
        def switch():
            target = Semester.objects.get(pk=self.second.pk)
            target.is_active = True
            target.save()
        result = self.race(assign, switch)[0]
        row.refresh_from_db()
        self.assertIsNotNone(row.ended_at)
        self.assertEqual(StudentTeam.objects.count(), 5 if result == 'assigned' else 4)

    def test_assignment_and_limit_reduction_serialize(self):
        self.fill()
        self.approve(approved_limit=6)
        self.team(5)
        def assign():
            try:
                self.team(6)
                return 'assigned'
            except ValidationError:
                return 'full'
        result = self.race(assign, lambda: self.approve(approved_limit=5, reason='Reduced concurrently'))[0]
        self.assertEqual(StudentTeam.objects.count(), 6 if result == 'assigned' else 5)
        self.assertEqual(capacity_projections([self.adviser.pk])[self.adviser.pk]['effective_limit'], 5)

    def test_concurrent_exception_edits_have_chained_audit_values(self):
        self.approve()
        self.race(lambda: self.approve(approved_limit=6, reason='Decision six'),
                  lambda: self.approve(approved_limit=7, reason='Decision seven'))
        logs = list(SystemAuditLog.objects.filter(action='adviser_capacity.updated').order_by('pk'))
        self.assertEqual(len(logs), 2)
        self.assertEqual(logs[0].old_values['approved_limit'], 5)
        self.assertEqual(logs[1].old_values['approved_limit'], logs[0].new_values['approved_limit'])
        self.assertEqual(AdviserCapacityException.objects.get().approved_limit, logs[1].new_values['approved_limit'])

    def test_competing_fifth_assignments(self):
        if connection.vendor != 'postgresql':
            self.skipTest('Requires PostgreSQL row locks')
        self.fill()
        self.approve()
        barrier = Barrier(2)
        def assign(index):
            close_old_connections()
            try:
                barrier.wait(timeout=10)
                try:
                    self.team(index)
                    return 'assigned'
                except ValidationError:
                    return 'full'
            finally:
                close_old_connections()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(assign, [5, 6]))
        self.assertEqual(sorted(results), ['assigned', 'full'])

    def test_assignment_and_revocation_serialize(self):
        if connection.vendor != 'postgresql':
            self.skipTest('Requires PostgreSQL row locks')
        self.fill()
        row = self.approve()
        barrier = Barrier(2)
        def work(revoke):
            close_old_connections()
            try:
                barrier.wait(timeout=10)
                if revoke:
                    save_exception(self.admin, {'adviser_id': self.adviser.pk, 'semester_id': self.term.pk,
                                              'reason': 'Revoked concurrently'}, revoke=True)
                    return 'revoked'
                try:
                    self.team(5)
                    return 'assigned'
                except ValidationError:
                    return 'full'
            finally:
                close_old_connections()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(work, [False, True]))
        self.assertIn(results[0], ('assigned', 'full'))
        row.refresh_from_db()
        self.assertIsNotNone(row.ended_at)
        self.assertEqual(StudentTeam.objects.count(), 5 if results[0] == 'assigned' else 4)
