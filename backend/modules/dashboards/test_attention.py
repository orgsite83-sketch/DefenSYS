"""Evidence-based year tasks and their real, read-only destinations."""
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester, SemesterTransitionLog
from student_teams.models import (StudentTeam, TeamMembership, TeamTermParticipation,
    StudentCapstoneParticipation, StudentCapstonePlacement)
from student_teams.attention import assignment_students
from user_management.academic_records.enrollment import enrollment_summary
from user_management.academic_records.models import StudentAcademicRecord
from .overview import admin_overview

User = get_user_model()


class AttentionYearTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.admin = User.objects.create_user(username='attention-admin', role='admin')
        cls.semester = Semester.objects.create(school_year=SchoolYear.objects.create(label='2054-2055'),
            label=Semester.SECOND, is_active=True, capstone_team_creation_enabled=True)

    def student(self, name, year='3rd Year', *, enroll=True, active=True):
        user = User.objects.create_user(username=name, first_name='Student', last_name=name,
                                        role='student', is_active=active)
        if enroll:
            StudentAcademicRecord.objects.create(student=user, semester=self.semester,
                year_level=year, section=f'BSIT-{year[0]}A')
        return user

    def test_enrollment_is_all_years_without_inferred_shortages(self):
        for index, year in enumerate(dict(StudentAcademicRecord.YEAR_LEVEL_CHOICES)):
            self.student(f'year-{index}', year)
        self.student('inactive', active=False)
        self.student('unenrolled', enroll=False)
        summary = enrollment_summary(self.semester)
        self.assertEqual(summary['enrolled'], 4)
        self.assertEqual([r['enrolled'] for r in summary['by_year']], [1, 1, 1, 1])
        self.assertEqual(summary['task_count'], 0)
        self.assertEqual(summary['coverage'], 'approved_continuations_only')

    def test_confirmed_year_groups_replace_empty_term_fallback(self):
        second, fourth, unknown = [self.student(n, enroll=False) for n in ('second', 'fourth', 'unknown')]
        targets = {second.pk: '2nd Year', fourth.pk: '4th Year', unknown.pk: None}
        with patch('user_management.academic_records.enrollment.pending_enrollment_students',
                   return_value=(User.objects.filter(pk__in=targets), targets)):
            overview = admin_overview(self.semester, [], [], 0)
        tasks = [t for t in overview['action_items'] if t.get('kind') == 'enrollment']
        self.assertEqual([t['year_level'] for t in tasks], ['2nd Year', '4th Year', None])
        self.assertEqual(overview['action_counts']['userManagement'], 3)
        self.assertNotIn(f'enrollment:{self.semester.pk}', [t['id'] for t in overview['action_items']])
        self.assertTrue(all(t['affected_count'] == 1 and 'view=enrollment' in t['target_route'] for t in tasks))

        self.student('already-enrolled', '3rd Year')
        with patch('user_management.academic_records.enrollment.pending_enrollment_students',
                   return_value=(User.objects.filter(pk__in=targets), targets)):
            partial = admin_overview(self.semester, [], [], 0)
        self.assertEqual(partial['enrollment']['task_count'], 3)
        self.assertEqual(partial['action_counts']['userManagement'], 3)
        self.assertNotIn(f'enrollment:{self.semester.pk}', [t['id'] for t in partial['action_items']])

    def test_current_capstone_gaps_are_grouped_by_official_year_and_pit_is_oversight(self):
        self.student('intake-3')
        self.student('returning-4', '4th Year')
        self.student('pit-2', '2nd Year')
        self.student('not-enrolled', enroll=False)
        overview = admin_overview(self.semester, [], [], 0)
        tasks = [t for t in overview['action_items'] if t.get('kind') == 'team_assignment']
        self.assertEqual([t['year_level'] for t in tasks], ['3rd Year', '4th Year'])
        self.assertEqual(overview['action_counts']['studentTeams'], 2)
        self.assertTrue(all('tab=import' in t['target_route'] and t['scope'] == 'capstone' for t in tasks))
        pit = next(r for r in overview['year_summary'] if r['year_level'] == '2nd Year')
        self.assertEqual((pit['without_team'], pit['can_assign']), (1, False))

    def test_valid_current_placement_and_finalized_participation_are_not_assignment_tasks(self):
        assigned = self.student('assigned')
        team = StudentTeam.objects.create(name='Existing current team', leader=assigned,
            semester=self.semester, intake_semester=self.semester, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        participation = StudentCapstoneParticipation.objects.create(student=assigned, intake_semester=self.semester, number=1)
        StudentCapstonePlacement.objects.create(participation=participation, team=team)
        # A placement remains authoritative even if a legacy membership row is missing.
        failed = self.student('failed')
        StudentCapstoneParticipation.objects.create(student=failed, intake_semester=self.semester, number=1, state='failed')
        self.assertEqual(assignment_students(self.semester)[0], [])

    def test_new_intake_uses_existing_failed_participation_rules(self):
        student = self.student('retry', '4th Year')
        old = Semester.objects.create(school_year=SchoolYear.objects.create(label='2053-2054'), label=Semester.SECOND)
        team = StudentTeam.objects.create(name='Past failed team', semester=old, intake_semester=old,
            leader=student, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        participation = StudentCapstoneParticipation.objects.create(student=student, intake_semester=old, number=1, state='failed')
        from django.utils import timezone
        StudentCapstonePlacement.objects.create(participation=participation, team=team, ended_at=timezone.now())
        self.assertEqual([s['id'] for s in assignment_students(self.semester)[0]], [student.pk])
        participation.state = 'completed'
        participation.save(update_fields=['state'])
        self.assertEqual(assignment_students(self.semester)[0], [])

    def test_closed_intake_is_not_a_team_creation_task(self):
        self.student('unassigned')
        self.semester.capstone_team_creation_enabled = False
        self.semester.save(update_fields=['capstone_team_creation_enabled'])
        self.assertEqual(assignment_students(self.semester), ([], 'not_applicable'))

    def test_details_are_paged_guarded_authorized_and_read_only(self):
        for index in range(30):
            self.student(f'page-{index:02}')
        before = tuple(model.objects.count() for model in (User, StudentAcademicRecord,
            StudentTeam, TeamMembership, StudentCapstoneParticipation, StudentCapstonePlacement))
        self.client.force_authenticate(self.admin)
        params = {'semester_id': self.semester.pk, 'attention': 'team_assignment', 'year_level': '3rd Year'}
        first = self.client.get('/api/users/academic-records/attention/', params)
        second = self.client.get('/api/users/academic-records/attention/', {**params, 'page': 2})
        self.assertEqual(first.status_code, 200)
        self.assertEqual((first.data['count'], len(first.data['students']), len(second.data['students'])), (30, 25, 5))
        self.assertFalse(set(r['id'] for r in first.data['students']) & set(r['id'] for r in second.data['students']))
        self.assertEqual(self.client.get('/api/users/academic-records/attention/', {**params, 'semester_id': 0}).status_code, 409)
        self.assertEqual(self.client.get('/api/users/academic-records/attention/', {**params, 'year_level': 'invalid'}).status_code, 400)
        self.assertEqual(before, tuple(model.objects.count() for model in (User, StudentAcademicRecord,
            StudentTeam, TeamMembership, StudentCapstoneParticipation, StudentCapstonePlacement)))
        self.client.force_authenticate(User.objects.get(username='page-00'))
        self.assertEqual(self.client.get('/api/users/academic-records/attention/', params).status_code, 403)

    def test_roster_growth_does_not_add_per_student_validation_queries(self):
        self.student('small')
        with CaptureQueriesContext(connection) as first:
            assignment_students(self.semester)
        for index in range(40):
            self.student(f'growth-{index}')
        with CaptureQueriesContext(connection) as second:
            students, _ = assignment_students(self.semester)
        self.assertEqual(len(students), 41)
        self.assertLessEqual(len(second), len(first) + 1)

    def test_recorded_continuation_target_and_pending_list_share_the_same_facts(self):
        self.semester.is_active = False
        self.semester.save(update_fields=['is_active'])
        target = Semester.objects.create(school_year=SchoolYear.objects.create(label='2055-2056'),
            label=Semester.FIRST, is_active=True)
        student = self.student('continuing', enroll=False)
        team = StudentTeam.objects.create(name='Continued', semester=target, intake_semester=self.semester,
            leader=student, level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year')
        TeamMembership.objects.create(team=team, student=student, is_leader=True)
        participation = StudentCapstoneParticipation.objects.create(student=student, intake_semester=self.semester, number=1)
        StudentCapstonePlacement.objects.create(participation=participation, team=team)
        log = SemesterTransitionLog.objects.create(from_semester=self.semester, to_semester=target,
            impact_snapshot={'applied_team_ids': [team.pk], 'capstone_review': {'teams': [{'team_id': team.pk, 'can_include': True}]}})
        TeamTermParticipation.objects.update_or_create(team=team, semester=target, defaults={'transition': log})
        summary = enrollment_summary(target)
        self.assertEqual(summary['pending_groups'], [{'year_level': '4th Year', 'count': 1}])
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/users/academic-records/attention/', {
            'semester_id': target.pk, 'year_level': '4th Year', 'attention': 'enrollment'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual([r['id'] for r in response.data['students']], [student.pk])
        StudentAcademicRecord.objects.create(student=student, semester=target, year_level='4th Year')
        resolved = enrollment_summary(target)
        self.assertEqual(resolved['pending_groups'], [])
        self.assertEqual((resolved['task_count'], resolved['reason']), (1, 'empty_years'))
