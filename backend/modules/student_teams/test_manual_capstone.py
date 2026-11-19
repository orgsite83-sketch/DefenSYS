"""Verified manual continuations run exclusively on Django's isolated database."""
from uuid import uuid4

from rest_framework.test import APITestCase
from . import test_participation as fixtures
from .models import StudentTeam, StudentCapstoneParticipation, CapstoneRosterConfirmation


class ManualCapstoneTests(APITestCase):
    setUp = fixtures.StudentParticipationTests.setUp
    term = fixtures.StudentParticipationTests.term
    student = fixtures.StudentParticipationTests.student
    team = fixtures.StudentParticipationTests.team
    assess = fixtures.StudentParticipationTests.assess
    failed = fixtures.StudentParticipationTests.failed
    payload = fixtures.StudentParticipationTests.payload
    def activate(self, *people):
        from user_management.academic_records.models import StudentAcademicRecord
        self.first.is_active = True
        self.first.save()
        for person in people:
            StudentAcademicRecord.objects.create(student=person, semester=self.first, year_level='4th Year', section='BSIT-4A')

    def body(self, people=None, reference='Approved school Capstone 1 grade sheet'):
        data = self.payload(people or [self.ana], level='4th Year Capstone', year='4th Year')
        data.update(project_title='Existing approved project', section='BSIT-4A',
                    capstone2_confirmation={'confirmed': True, 'reference': reference, 'request_id': str(uuid4())})
        return data

    def test_external_registration_and_retry_are_one_atomic_identity(self):
        from .capstone_context import phase_for
        from defense.scheduler.capstone_planning import batch_id
        self.activate(self.ana)
        data = self.body()
        first = self.client.post('/api/teams/', data, format='json')
        self.assertEqual(first.status_code, 201, first.data)
        team = StudentTeam.objects.get(pk=first.data['team']['id'])
        self.assertIsNone(team.intake_semester_id)
        self.assertEqual(team.capstone_registration_semester_id, self.first.pk)
        self.assertEqual(phase_for(team), 'capstone_2')
        self.assertEqual(batch_id(team), self.first.pk)
        participation = StudentCapstoneParticipation.objects.get(student=self.ana)
        self.assertFalse(participation.history_complete)
        self.assertEqual(participation.origin, 'external_continuation')
        self.assertIsNone(first.data['team']['members'][0]['capstone_participation']['number'])
        second = self.client.post('/api/teams/', data, format='json')
        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(second.data['team']['id'], team.pk)
        self.assertEqual(CapstoneRosterConfirmation.objects.count(), 1)
        self.assertEqual(StudentTeam.objects.count(), 1)
        history = self.client.get(f'/api/teams/students/{self.ana.pk}/capstone-history/')
        self.assertEqual(history.status_code, 200, history.data)
        verification = history.data['participations'][0]['verification']
        self.assertEqual(verification['reference'], data['capstone2_confirmation']['reference'])
        self.assertEqual(verification['actor'], self.admin.username)

    def test_reference_required_only_for_missing_source(self):
        self.activate(self.ana)
        response = self.client.post('/api/teams/', self.body(reference=''), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(StudentCapstoneParticipation.objects.exists())
        self.assertFalse(CapstoneRosterConfirmation.objects.exists())

    def test_matching_existing_project_is_reconciled_not_duplicated(self):
        old = self.team(self.old, [self.ana, self.bea])
        old.project_title = 'Existing approved project'
        old.save()
        self.assess(old, 'approved')
        self.activate(self.ana, self.bea)
        data = self.body([self.ana, self.bea], reference='')
        data['leader_id'] = self.bea.pk
        response = self.client.post('/api/teams/', data, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['team']['id'], old.pk)
        self.assertEqual(StudentTeam.objects.count(), 1)
        old.refresh_from_db()
        self.assertEqual(old.intake_semester_id, self.old.pk)
        self.assertEqual(old.semester_id, self.first.pk)
        self.assertEqual(old.leader_id, self.bea.pk)
        self.assertTrue(old.memberships.get(student=self.bea).is_leader)
        self.assertFalse(old.memberships.get(student=self.ana).is_leader)
        self.assertEqual(old.term_participations.get(semester=self.old).snapshot['leader_id'], self.ana.pk)

    def test_external_team_is_available_in_scheduler_and_history(self):
        from defense.scheduler.capstone_planning import workspace
        self.activate(self.ana)
        response = self.client.post('/api/teams/', self.body(), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        data = workspace(self.admin)
        self.assertIn(response.data['team']['id'], [row['id'] for row in data['teams']])

    def test_internal_completion_keeps_own_participation_without_reference(self):
        old = self.team(self.old, [self.ana])
        self.assess(old, 'approved')
        participation = StudentCapstoneParticipation.objects.get(student=self.ana)
        self.activate(self.ana)
        response = self.client.post('/api/teams/', self.body(reference=''), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(StudentCapstoneParticipation.objects.get(student=self.ana).pk, participation.pk)

    def test_checkbox_cannot_override_final_failure_or_incomplete_history(self):
        self.failed()
        self.activate(self.ana)
        response = self.client.post('/api/teams/', self.body(), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(CapstoneRosterConfirmation.objects.exists())

    def test_unfinished_source_stage_cannot_be_waived_by_confirmation(self):
        from defense.stages.models import DefenseStage
        from .models import TeamStageProgress
        old = self.team(self.old, [self.ana])
        self.assess(old, 'approved')
        later = DefenseStage.objects.create(label='Unfinished source review', display_order=2)
        TeamStageProgress.objects.create(team=old, semester=self.old, defense_stage=later, status='ready')
        self.activate(self.ana)
        response = self.client.post('/api/teams/', self.body(), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('incomplete', str(response.data))

    def test_missing_enrollment_and_forged_result_leave_no_rows(self):
        self.activate()
        response = self.client.post('/api/teams/', self.body(), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(StudentTeam.objects.exists())
        self.activate(self.ana)
        data = self.body()
        data['status'] = 'Approved'
        response = self.client.post('/api/teams/', data, format='json')
        self.assertEqual(response.status_code, 400, response.data)

    def test_adding_missing_history_member_requires_new_confirmation(self):
        self.activate(self.ana, self.bea)
        response = self.client.post('/api/teams/', self.body(), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        team_id = response.data['team']['id']
        data = self.body([self.ana, self.bea])
        response = self.client.patch(f'/api/teams/{team_id}/', data, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(StudentCapstoneParticipation.objects.count(), 2)
        self.assertEqual(CapstoneRosterConfirmation.objects.count(), 2)
        retry = self.client.patch(f'/api/teams/{team_id}/', data, format='json')
        self.assertEqual(retry.status_code, 200, retry.data)
        self.assertEqual(CapstoneRosterConfirmation.objects.count(), 2)

    def test_changed_idempotent_payload_cannot_create_another_team(self):
        self.activate(self.ana)
        data = self.body()
        first = self.client.post('/api/teams/', data, format='json')
        self.assertEqual(first.status_code, 201, first.data)
        data['name'] = 'Different request data'
        response = self.client.post('/api/teams/', data, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(StudentTeam.objects.count(), 1)

    def test_verified_record_is_preserved_on_normal_team_deletion(self):
        self.activate(self.ana)
        response = self.client.post('/api/teams/', self.body(), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        response = self.client.delete(f"/api/teams/{response.data['team']['id']}/")
        self.assertEqual(response.status_code, 409, response.data)
        self.assertEqual(CapstoneRosterConfirmation.objects.count(), 1)

    def test_manual_confirmation_is_rejected_by_shared_import_serializer(self):
        from .serializers import StudentTeamWriteSerializer
        self.activate(self.ana)
        serializer = StudentTeamWriteSerializer(data=self.body(), context={'user': self.admin, 'assigned_by': self.admin})
        self.assertFalse(serializer.is_valid())
        self.assertIn('capstone2_confirmation', serializer.errors)
