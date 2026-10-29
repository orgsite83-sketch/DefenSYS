"""Cutover mapping uses durable intake evidence and preserves old audit rows."""
from importlib import import_module
from types import SimpleNamespace
from django.apps import apps
from django.contrib.auth import get_user_model
from django.db import connection
from django.test import TestCase
from django.utils import timezone
from academic_period_management.models import SchoolYear, Semester
from .models import (StudentTeam, TeamMembership, TeamTermParticipation,
    HistoricalCapstoneJourney, HistoricalCapstoneRecovery,
    StudentCapstoneParticipation as Participation, StudentCapstonePlacement as Placement)


class ParticipationMappingTests(TestCase):
    def setUp(self):
        self.student = get_user_model().objects.create_user(username='mapping-student', role='student')
        year = SchoolYear.objects.create(label='2025-2026')
        next_year = SchoolYear.objects.create(label='2026-2027')
        self.old = Semester.objects.create(school_year=year, label=Semester.SECOND)
        self.next = Semester.objects.create(school_year=next_year, label=Semester.SECOND)
        self.first = Semester.objects.create(school_year=next_year, label=Semester.FIRST)

    def team(self, term, name, **extra):
        phase = extra.pop('capstone_phase', 'active')
        team = StudentTeam.objects.create(name=name, level='3rd Year Capstone',
            year_level='3rd Year', semester=term, leader=self.student, **extra)
        # Simulate persisted pre-cutover values, which the new writer rejects.
        StudentTeam.objects.filter(pk=team.pk).update(capstone_phase=phase)
        team.refresh_from_db()
        TeamMembership.objects.create(team=team, student=self.student, is_leader=True)
        TeamTermParticipation.objects.filter(team=team).update(snapshot={
            'name': name, 'project_title': name, 'member_ids': [self.student.pk]})
        return team

    def map(self):
        import_module('student_teams.migrations.0020_backfill_capstone_participation').backfill(
            apps, SimpleNamespace(connection=connection))

    def test_normal_continuation_has_one_intake_and_mapping_is_idempotent(self):
        team = self.team(self.first, 'Continued team')
        HistoricalCapstoneJourney.objects.bulk_create([HistoricalCapstoneJourney(team=team,
            intake_semester=self.old, normal_completion_year='2026-2027', extension_end_year='2027-2028')])
        before = TeamTermParticipation.objects.count()
        self.map()
        self.map()
        row = Participation.objects.get()
        self.assertEqual((row.number, row.intake_semester_id), (1, self.old.pk))
        self.assertEqual(Placement.objects.count(), 1)
        self.assertEqual(TeamTermParticipation.objects.count(), before)
        self.assertEqual(HistoricalCapstoneJourney.objects.count(), 1)

    def test_evidenced_failed_intake_precedes_new_roster_even_when_primary_keys_are_reversed(self):
        newer = self.team(self.next, 'New roster')
        older = self.team(self.old, 'Old roster')
        TeamTermParticipation.objects.filter(team=older).update(outcome='failed', closed_at=timezone.now())
        self.map()
        self.assertEqual(list(Participation.objects.order_by('number').values_list('intake_semester_id', 'number', 'state')),
            [(self.old.pk, 1, 'failed'), (self.next.pk, 2, 'active')])
        self.assertEqual(Placement.objects.get(team=newer).participation.previous.number, 1)

    def test_unknown_first_semester_does_not_fabricate_a_participation(self):
        team = self.team(self.first, 'Unknown source')
        self.map()
        team.refresh_from_db()
        self.assertTrue(team.participation_review_reason)
        self.assertFalse(Participation.objects.exists())

    def test_legacy_extended_is_read_only_without_an_intake(self):
        team = self.team(self.next, 'Legacy Extended', capstone_phase='extended')
        TeamTermParticipation.objects.filter(team=team).delete()
        self.map()
        team.refresh_from_db()
        self.assertTrue(team.participation_review_reason)
        self.assertFalse(Participation.objects.exists())

    def test_consumed_old_grant_is_archived_and_requires_review(self):
        from defense.stages.models import DefenseStage
        stage = DefenseStage.objects.first()
        team = self.team(self.old, 'Previously recovered')
        HistoricalCapstoneRecovery.objects.bulk_create([HistoricalCapstoneRecovery(team=team,
            defense_stage=stage, semester=self.old, project_version=1,
            previous_project_title='Original title', action='retake', reason='Historical approval',
            consumed_at=timezone.now())])
        self.map()
        team.refresh_from_db()
        self.assertTrue(team.participation_review_reason)
        self.assertEqual(Participation.objects.get().state, 'needs_review')
        self.assertEqual(HistoricalCapstoneRecovery.objects.count(), 1)

    def test_archive_models_cannot_create_live_recovery_authority(self):
        from django.core.exceptions import ValidationError
        with self.assertRaises(ValidationError):
            HistoricalCapstoneRecovery().save()
        with self.assertRaises(ValidationError):
            HistoricalCapstoneJourney().save()
