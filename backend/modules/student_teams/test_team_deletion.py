"""Deletion regressions use real imports and the isolated Django test database."""
import datetime
from unittest.mock import patch

from django.utils import timezone
from rest_framework.test import APITestCase

from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from repository.archive.models import ArchiveEntry
from repository.deliverables.models import ConceptRound, DeliverableSubmission
from user_management.academic_records.models import StudentAcademicRecord
from . import tests as fixtures
from .models import (
    HistoricalCapstoneJourney, PITRosterTeamDetails, StudentCapstoneParticipation, StudentCapstonePlacement,
    StudentTeam, TeamDocument, TeamStageProgress, WeeklyProgressReport,
)


class TeamDeletionTests(APITestCase):
    setUp = fixtures.StudentTeamApiTests.setUp
    _activate_capstone_intake_semester = fixtures.StudentTeamApiTests._activate_capstone_intake_semester

    def import_team(self, *, capstone=True):
        if capstone:
            self._activate_capstone_intake_semester()
        payload = {'teams': [{
            'team_name': 'Imported deletion team', 'project_title': 'Imported project',
            'level': StudentTeam.LEVEL_3_CAPSTONE if capstone else StudentTeam.LEVEL_3_PIT,
            'year_level': '3rd Year', 'member_ids': ['Juan Dela Cruz', 'Maria Santos'],
            'leader_id': 'Juan Dela Cruz', 'adviser_id': 'Ada Lovelace',
        }]}
        response = self.client.post('/api/teams/bulk-import/', payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['created_count'], 1, response.data)
        return StudentTeam.objects.get(name='Imported deletion team')

    def assert_blocked(self, team, reason):
        placements = list(team.student_placements.values_list('pk', flat=True))
        for query in ('?workspace=operations', '?workspace=operations&force=true'):
            response = self.client.delete(f'/api/teams/{team.pk}/{query}')
            self.assertEqual(response.status_code, 409, response.data)
            self.assertIn(reason, response.data['detail'])
            self.assertTrue(StudentTeam.objects.filter(pk=team.pk).exists())
            self.assertEqual(list(team.student_placements.values_list('pk', flat=True)), placements)

    def test_unused_capstone_import_can_be_deleted_and_reimported(self):
        team = self.import_team()
        team_id = team.pk
        student_ids = [self.student_1.pk, self.student_2.pk]
        self.assertEqual(team.student_placements.count(), 2)
        self.assertEqual(team.term_participations.filter(closed_at__isnull=True).count(), 1)
        enrollment_ids = set(StudentAcademicRecord.objects.values_list('pk', flat=True))
        response = self.client.delete(f'/api/teams/{team_id}/?workspace=operations')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(StudentTeam.objects.filter(pk=team_id).exists())
        self.assertFalse(StudentCapstonePlacement.objects.exists())
        self.assertFalse(StudentCapstoneParticipation.objects.exists())
        self.assertEqual(set(StudentAcademicRecord.objects.values_list('pk', flat=True)), enrollment_ids)
        self.assertEqual(type(self.student_1).objects.filter(pk__in=student_ids).count(), 2)
        self.assertTrue(SystemAuditLog.objects.filter(action='team.delete', target_id=str(team_id)).exists())
        recreated = self.import_team()
        self.assertEqual(recreated.memberships.count(), 2)
        self.assertEqual(list(StudentCapstoneParticipation.objects.values_list('number', flat=True)), [1, 1])

    def test_unused_pit_import_can_be_deleted(self):
        team = self.import_team(capstone=False)
        response = self.client.delete(f'/api/teams/{team.pk}/?workspace=operations')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(StudentTeam.objects.filter(pk=team.pk).exists())

    def test_locked_stage_scaffolding_does_not_block_unused_import(self):
        team = self.import_team()
        TeamStageProgress.objects.create(team=team, semester=team.semester,
            defense_stage=DefenseStage.objects.first(), status=TeamStageProgress.STATUS_LOCKED)
        response = self.client.delete(f'/api/teams/{team.pk}/')
        self.assertEqual(response.status_code, 200, response.data)

    def test_defense_schedule_blocks_deletion_even_for_admin_force(self):
        team = self.import_team()
        DefenseSchedule.objects.create(team=team, semester=team.semester, scope='capstone',
            defense_stage=DefenseStage.objects.first(), scheduled_date=datetime.date.today(),
            start_time=datetime.time(9), room='Test room')
        self.assert_blocked(team, 'defense schedules')

    def test_zero_score_grade_blocks_deletion(self):
        team = self.import_team()
        TeamGrade.objects.create(team=team, semester=team.semester, scope='capstone',
            defense_stage=DefenseStage.objects.first(), panel_score=0)
        self.assert_blocked(team, 'grade records')

    def test_pending_submission_blocks_deletion(self):
        team = self.import_team()
        DeliverableSubmission.objects.create(team=team, stage_label='Concept Proposal',
            deliverable_id='D1', label='Concept paper', deliverable_type='pre', file_name='paper.pdf')
        self.assert_blocked(team, 'submitted documents')

    def test_older_project_submissions_are_also_protected(self):
        team = self.import_team()
        DeliverableSubmission.objects.create(team=team, stage_label='Concept Proposal',
            deliverable_id='D1', label='Concept paper', deliverable_type='pre')
        StudentTeam.objects.filter(pk=team.pk).update(project_version=2)
        team.refresh_from_db()
        self.assertFalse(team.deliverable_submissions.exists())
        self.assert_blocked(team, 'submitted documents')

    def test_older_project_grades_are_also_protected(self):
        team = self.import_team()
        TeamGrade.objects.create(team=team, semester=team.semester, scope='capstone',
            defense_stage=DefenseStage.objects.first())
        StudentTeam.objects.filter(pk=team.pk).update(project_version=2)
        team.refresh_from_db()
        self.assertFalse(TeamGrade.objects.filter(team=team).exists())
        self.assert_blocked(team, 'grade records')

    def test_uploaded_team_document_blocks_deletion(self):
        team = self.import_team()
        TeamDocument.objects.create(team=team, uploaded_by=self.student_1, file_name='paper.pdf',
            file_size=10, mime_type='application/pdf', file_data=b'test evidence')
        self.assert_blocked(team, 'submitted documents')

    def test_weekly_report_blocks_deletion(self):
        team = self.import_team()
        WeeklyProgressReport.objects.create(team=team, student=self.student_1,
            week_number=1, report_date=datetime.date.today(), accomplishments=['Initial work'])
        self.assert_blocked(team, 'weekly progress reports')

    def test_concept_work_blocks_deletion(self):
        team = self.import_team()
        ConceptRound.objects.create(team=team, defense_stage=DefenseStage.objects.first(),
            concepts=[{'key': 'c1', 'title': 'Student-authored proposal'}])
        self.assert_blocked(team, 'concept workflow')

    def test_archive_entry_blocks_deletion_and_keeps_team_reference(self):
        team = self.import_team()
        entry = ArchiveEntry.objects.create(team=team, entry_type='capstone', file_name='approved-paper.pdf')
        self.assert_blocked(team, 'archived academic work')
        entry.refresh_from_db()
        self.assertEqual(entry.team_id, team.pk)

    def test_retired_cohort_history_is_preserved(self):
        team = self.import_team()
        # Historical models intentionally reject save(); seed preserved evidence
        # directly only inside this isolated test database.
        HistoricalCapstoneJourney.objects.bulk_create([HistoricalCapstoneJourney(
            team=team, intake_semester=team.semester,
            normal_completion_year='2027-2028', extension_end_year='2028-2029')])
        self.assert_blocked(team, 'academic participation history')

    def test_endorsement_blocks_deletion(self):
        team = self.import_team()
        TeamStageProgress.objects.create(team=team, semester=team.semester,
            defense_stage=DefenseStage.objects.first(), status=TeamStageProgress.STATUS_READY,
            ready_at=timezone.now())
        self.assert_blocked(team, 'recorded defense activity')

    def test_closed_current_term_stays_read_only(self):
        team = self.import_team()
        team.term_participations.update(closed_at=timezone.now(), outcome='completed')
        response = self.client.delete(f'/api/teams/{team.pk}/?force=true')
        self.assertEqual(response.status_code, 403, response.data)
        self.assertTrue(StudentTeam.objects.filter(pk=team.pk).exists())
        self.assertEqual(team.student_placements.count(), 2)

    def test_prior_failed_intake_is_preserved_and_reimport_keeps_number(self):
        team = self.import_team()
        current = StudentCapstoneParticipation.objects.get(student=self.student_1)
        StudentCapstoneParticipation.objects.filter(pk=current.pk).update(number=2)
        previous = StudentCapstoneParticipation.objects.create(student=self.student_1,
            intake_semester=self.first_semester, number=1, state=StudentCapstoneParticipation.FAILED)
        StudentCapstoneParticipation.objects.filter(pk=current.pk).update(previous=previous)
        response = self.client.delete(f'/api/teams/{team.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(StudentCapstoneParticipation.objects.filter(pk=previous.pk).exists())
        self.import_team()
        recreated = StudentCapstoneParticipation.objects.get(student=self.student_1, intake_semester=self.second_semester)
        self.assertEqual(recreated.number, 2)
        self.assertEqual(recreated.previous_id, previous.pk)

    def test_shared_participation_is_preserved_when_only_unused_team_is_deleted(self):
        team = self.import_team()
        other = StudentTeam.objects.create(name='Previous roster', level=team.level, year_level=team.year_level,
            semester=team.semester, leader=self.student_1)
        participation = StudentCapstoneParticipation.objects.get(student=self.student_1)
        placement = StudentCapstonePlacement.objects.create(participation=participation, team=other, ended_at=timezone.now())
        response = self.client.delete(f'/api/teams/{team.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(StudentCapstoneParticipation.objects.filter(pk=participation.pk).exists())
        self.assertTrue(StudentCapstonePlacement.objects.filter(pk=placement.pk).exists())

    def test_protected_reference_rolls_back_import_placement_cleanup(self):
        team = self.import_team()
        other = StudentTeam.objects.create(name='Linked roster', level=team.level, year_level=team.year_level,
            semester=team.semester, leader=self.student_1)
        PITRosterTeamDetails.objects.create(team=other, source_team=team, name=other.name)
        self.assert_blocked(team, 'referenced by academic history')
        self.assertEqual(team.student_placements.count(), 2)

    def test_failed_audit_rolls_back_deletion_and_placement_cleanup(self):
        team = self.import_team()
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('audit unavailable')):
            response = self.client.delete(f'/api/teams/{team.pk}/')
        self.assertEqual(response.status_code, 500, response.data)
        self.assertTrue(StudentTeam.objects.filter(pk=team.pk).exists())
        self.assertEqual(team.student_placements.count(), 2)
