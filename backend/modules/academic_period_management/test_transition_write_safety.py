"""Late writes must respect semester activation and captured Capstone history."""
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DomainValidationError
from rest_framework.exceptions import APIException
from rest_framework.test import APITestCase

from grading.grades.models import TeamGrade
from grading.grades.services import GradeContextService
from student_teams.models import StudentTeam, StudentCapstoneParticipation
from student_teams.serializers import StudentTeamWriteSerializer
from user_management.academic_records.models import StudentAcademicRecord
from .models import Semester
from . import tests_capstone_transition as fixtures


class TransitionWriteSafetyTests(APITestCase):
    setUp = fixtures.CapstoneTransitionTests.setUp
    make_team = fixtures.CapstoneTransitionTests.make_team
    enroll = fixtures.CapstoneTransitionTests.enroll
    assess = fixtures.CapstoneTransitionTests.assess
    preview = fixtures.CapstoneTransitionTests.preview
    activate = fixtures.CapstoneTransitionTests.activate
    enter_normal = fixtures.CapstoneTransitionTests.enter_normal

    def close_unfinished_term(self, verdict='for_redefense'):
        self.enter_normal()
        grade = self.assess(self.team, self.second, verdict, status='pending')
        response = self.activate(self.extension, force=True, reason='Approved calendar exception')
        self.assertEqual(response.status_code, 200, response.data)
        return grade

    def assert_new_term_active(self):
        self.assertEqual(list(Semester.objects.filter(is_active=True).values_list('pk', flat=True)),
                         [self.extension.pk])
        self.normal.refresh_from_db()
        self.assertFalse(self.normal.is_active)

    def test_settings_request_loaded_before_activation_preserves_new_active_term(self):
        self.enter_normal()
        self.assess(self.team, self.second)
        pending_settings = Semester.objects.get(pk=self.normal.pk)
        self.assertEqual(self.activate(self.extension).status_code, 200)
        with patch('academic_period_management.views.get_object_or_404', return_value=pending_settings):
            response = self.client.patch(f'/api/academic-periods/semesters/{self.normal.pk}/', {
                'capstone_peer_evaluation_enabled': True,
                'capstone_adviser_grading_enabled': True,
            }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['semester']['is_active'])
        self.assertEqual(response.data['active_semester']['id'], self.extension.pk)
        self.assert_new_term_active()
        self.assertTrue(self.normal.capstone_peer_evaluation_enabled)
        self.assertTrue(self.normal.capstone_adviser_grading_enabled)

    def test_empty_partial_save_on_old_active_instance_is_a_noop(self):
        self.enter_normal()
        self.assess(self.team, self.second)
        pending_settings = Semester.objects.get(pk=self.normal.pk)
        self.assertEqual(self.activate(self.extension).status_code, 200)
        pending_settings.save(update_fields=[])
        self.assert_new_term_active()

    def test_roster_update_rechecks_term_after_validation(self):
        self.enter_normal()
        self.assess(self.team, self.second, 'for_redefense', status='pending')
        serializers = [StudentTeamWriteSerializer(self.team, data={
            'name': 'Late overwritten team', 'leader_id': self.team.leader_id,
            'member_ids': [self.team.leader_id], 'year_level': '4th Year',
            'level': '4th Year Capstone', 'section': 'BSIT-4A',
        }, context={'assigned_by': self.admin, 'user': self.admin, 'formation': formation})
            for formation in (False, True)]
        for serializer in serializers:
            self.assertTrue(serializer.is_valid(), serializer.errors)
        response = self.activate(self.extension, force=True, reason='Approved calendar exception')
        self.assertEqual(response.status_code, 200, response.data)
        before = StudentTeam.objects.filter(pk=self.team.pk).values().get()
        history = list(self.team.term_participations.values())
        for serializer in serializers:
            with self.subTest(formation=serializer.context['formation']):
                with self.assertRaises(APIException):
                    serializer.save()
                self.assertEqual(StudentTeam.objects.filter(pk=self.team.pk).values().get(), before)
                self.assertEqual(list(self.team.term_participations.values()), history)

    def test_roster_creation_rechecks_term_before_allocating_participation(self):
        self.extension.is_active = True
        self.extension.capstone_team_creation_enabled = True
        self.extension.save()
        student = get_user_model().objects.create_user(username='late-intake-student', role='student')
        StudentAcademicRecord.objects.create(student=student, semester=self.extension,
            year_level='4th Year', section='BSIT-4A')
        serializer = StudentTeamWriteSerializer(data={
            'name': 'Late intake', 'leader_id': student.pk, 'member_ids': [student.pk],
            'year_level': '4th Year', 'level': '4th Year Capstone', 'section': 'BSIT-4A',
        }, context={'assigned_by': self.admin, 'user': self.admin})
        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(self.activate(self.last).status_code, 200)
        with self.assertRaises(APIException):
            serializer.save()
        self.assertFalse(StudentTeam.objects.filter(name='Late intake').exists())
        self.assertFalse(StudentCapstoneParticipation.objects.filter(student=student).exists())

    def test_closed_term_rejects_late_manual_verdict_without_changing_history(self):
        grade = self.close_unfinished_term()
        before = TeamGrade.objects.filter(pk=grade.pk).values().get()
        history = list(self.team.term_participations.values())
        for verdict in ('approved', 'failed'):
            with self.subTest(verdict=verdict):
                response = self.client.patch(f'/api/grading/grades/{grade.pk}/verdict/', {
                    'verdict': verdict, 'verdict_remarks': 'Late assessment after calendar closure.',
                }, format='json')
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('historical correction', str(response.data))
                self.assertEqual(TeamGrade.objects.filter(pk=grade.pk).values().get(), before)
                self.assertEqual(list(self.team.term_participations.values()), history)
        self.assertEqual(StudentCapstoneParticipation.objects.get(student=self.team.leader).state, 'active')

    def test_closed_term_rejects_publication_in_api_and_domain_services(self):
        grade = self.close_unfinished_term('approved')
        response = self.client.post(f'/api/grading/grades/{grade.pk}/publish/', {}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('historical correction', str(response.data))
        for operation in (GradeContextService.publish, GradeContextService.finalize_for_archive):
            with self.subTest(operation=operation.__name__):
                with self.assertRaisesMessage(DomainValidationError, 'historical correction'):
                    operation(grade, user=self.admin)
        grade.refresh_from_db()
        self.assertEqual(grade.status, 'pending')
        self.assertEqual(self.team.term_participations.get(semester=self.normal).outcome, 'needs_review')

    def test_closed_term_rejects_revision_clearance(self):
        grade = self.close_unfinished_term('approved_with_revisions')
        response = self.client.post(f'/api/grading/grades/{grade.pk}/workflow/', {
            'action': 'clear_revisions', 'reason': 'Late clearance after calendar closure.',
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('historical correction', str(response.data))
        grade.refresh_from_db()
        self.assertIsNone(grade.revisions_cleared_at)

    def test_closed_term_rejects_late_stage_failure_finalization(self):
        from grading.grades.stage_closure import finalize_failure
        grade = self.close_unfinished_term()
        before = TeamGrade.objects.filter(pk=grade.pk).values().get()
        with self.assertRaisesMessage(DomainValidationError, 'historical correction'):
            finalize_failure(grade, self.admin, 'Late stage closure after the calendar switch.')
        self.assertEqual(TeamGrade.objects.filter(pk=grade.pk).values().get(), before)
        self.assertEqual(self.team.term_participations.get(semester=self.normal).outcome, 'needs_review')
        self.assertEqual(StudentCapstoneParticipation.objects.get(student=self.team.leader).state, 'active')

    def test_historical_published_score_correction_retains_audited_approval_path(self):
        self.enter_normal()
        grade = self.assess(self.team, self.second)
        self.assertEqual(self.activate(self.extension).status_code, 200)
        url = f'/api/grading/grades/{grade.pk}/corrections/'
        data = {'reason': 'Correct the recorded source peer score.',
            'expected_updated_at': grade.updated_at.isoformat(),
            'changes': {'aggregate': {'peer_score': '90'}}}
        response = self.client.post(url, data, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'pending')
        grade.refresh_from_db()
        self.assertEqual(grade.peer_score, 85)
        response = self.client.post(url, {'action': 'approve', 'correction_id': response.data['id'],
            'acknowledge_published_change': True, 'reason': 'Verified the original source evaluation.'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        grade.refresh_from_db()
        self.assertEqual(grade.peer_score, 90)
        self.assertEqual(grade.status, 'published')
        self.assertEqual(self.team.term_participations.get(semester=self.normal).outcome, 'completed')
        self.assertEqual(StudentCapstoneParticipation.objects.get(student=self.team.leader).state, 'completed')

    def test_failed_capstone_two_student_can_join_fresh_capstone_one_intake(self):
        from student_teams.services import mark_stage_result
        self.extension.capstone_team_creation_enabled = True
        self.extension.save(update_fields=['capstone_team_creation_enabled'])
        self.enter_normal()
        grade = self.assess(self.team, self.second, 'failed')
        mark_stage_result(grade, user=self.admin)
        self.assertEqual(self.activate(self.extension).status_code, 200)
        self.enroll(self.team, self.extension)
        response = self.client.post('/api/teams/', {
            'name': 'Fresh returning intake', 'leader_id': self.team.leader_id,
            'member_ids': [self.team.leader_id], 'year_level': '4th Year',
            'level': '4th Year Capstone', 'section': 'BSIT-4A',
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['team']['members'][0]['capstone_participation']['number'], 2)
        self.assertEqual(self.team.term_participations.get(semester=self.normal).outcome, 'failed')
