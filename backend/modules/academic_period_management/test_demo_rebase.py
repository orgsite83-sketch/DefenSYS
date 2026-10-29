from datetime import date
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.exceptions import APIException

from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from grading.grades.models import TeamGrade
from student_teams.participation import intake_for
from student_teams.models import (HistoricalCapstoneJourney, PITSectionRoster, SectionAssignment,
    StudentTeam, TeamMembership, TeamTermParticipation)
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import SectionInstructorAssignment
from .demo_rebase import rebase_demo_term
from .models import SchoolYear, Semester


class DemoRebaseTests(TestCase):
    def setUp(self):
        User = get_user_model()
        self.admin = User.objects.create_user(username='rebase-admin', role='admin')
        self.student = User.objects.create_user(username='rebase-capstone', role='student')
        self.pit_student = User.objects.create_user(username='rebase-pit', role='student')
        self.year = SchoolYear.objects.create(label='2025-2026')
        self.source = Semester.objects.create(school_year=self.year, label=Semester.FIRST,
            starts_on=date(2024, 1, 10), ends_on=date(2025, 6, 15), is_active=True)
        self.target = Semester.objects.create(school_year=self.year, label=Semester.SECOND)
        self.capstone = StudentTeam.objects.create(name='Capstone baseline', semester=self.source,
            leader=self.student, level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year', section='BSIT-4A')
        self.pit = StudentTeam.objects.create(name='PIT baseline', semester=self.source,
            leader=self.pit_student, level=StudentTeam.LEVEL_1_PIT, year_level='1st Year', section='BSIT-1A')
        for team in (self.capstone, self.pit):
            TeamMembership.objects.create(team=team, student=team.leader, is_leader=True)
            StudentAcademicRecord.objects.create(student=team.leader, semester=self.source,
                year_level=team.year_level, section=team.section)
        self.participation, _ = TeamTermParticipation.objects.update_or_create(
            team=self.capstone, semester=self.source, defaults={
                'snapshot': {'school_year': '2024-2025', 'semester': Semester.FIRST,
                    'display_semester': '1st Semester, A.Y. 2024-2025', 'project_title': 'Keep title'}})
        self.event = PitEventGradingConfig.objects.create(semester=self.source, event_name='PIT baseline', year_level='1st Year')
        self.grade = TeamGrade.all_objects.create(team=self.pit, semester=self.source, scope='pit',
            pit_event_config=self.event, stage_label=self.event.event_name, status='published',
            panel_score=90, peer_score=95, panel_weight=80, peer_weight=20, adviser_weight=0)
        self.schedule = DefenseSchedule.objects.create(team=self.pit, semester=self.source, scope='pit',
            event_name=self.event.event_name, scheduled_date=date(2024, 2, 27),
            start_time='10:00:00', room='Room 304', status='done')
        self.roster, _ = PITSectionRoster.objects.get_or_create(
            semester=self.source, year_level='1st Year', section='BSIT-1A')
        self.roster.teams.add(self.pit)
        self.section = SectionAssignment.objects.create(semester=self.source, section='BSIT-4A', year_level='4th Year')
        self.instructor = SectionInstructorAssignment.objects.create(faculty=self.admin, semester=self.source,
            year_level='4th Year', section='BSIT-4A')
        self.kwargs = dict(source_id=self.source.pk, target_id=self.target.pk, expected_year=self.year.label,
            expected_teams=2, expected_enrollments=2, expected_capstone_teams=1,
            reason='Owner confirmed the demo starts in second semester.', actor=self.admin)

    def test_preview_changes_nothing_and_apply_moves_pit_and_capstone_together(self):
        preview = rebase_demo_term(**self.kwargs)
        self.assertFalse(preview['applied'])
        self.assertFalse(HistoricalCapstoneJourney.objects.exists())
        self.pit.refresh_from_db()
        self.assertEqual(self.pit.semester_id, self.source.pk)
        old_grade = TeamGrade.all_objects.filter(pk=self.grade.pk).values().get()
        password_before = get_user_model().objects.get(pk=self.student.pk).password
        with TemporaryDirectory() as directory:
            backup = Path(directory) / 'before.json'
            result = rebase_demo_term(**self.kwargs, apply=True, backup_path=backup,
                preview_revision=preview['preview_revision'])
            self.assertTrue(result['applied'])
            self.assertTrue(json.loads(backup.read_text())['records_before'])
        for obj in (self.capstone, self.pit, self.event, self.grade, self.schedule, self.roster,
                    self.section, self.instructor, self.participation):
            obj.refresh_from_db()
            self.assertEqual(obj.semester_id, self.target.pk)
        self.assertEqual(self.capstone.level, StudentTeam.LEVEL_3_CAPSTONE)
        self.assertEqual(self.capstone.section, 'BSIT-3A')
        self.assertEqual(self.pit.level, StudentTeam.LEVEL_1_PIT)
        self.assertEqual(self.schedule.scheduled_date, date(2024, 2, 27))
        self.assertEqual(self.section.section, 'BSIT-3A')
        record = StudentAcademicRecord.objects.get(student=self.student)
        self.assertEqual((record.year_level, record.section), ('3rd Year', 'BSIT-3A'))
        self.assertEqual(self.participation.snapshot['school_year'], self.year.label)
        self.assertEqual(self.participation.snapshot['project_title'], 'Keep title')
        self.assertEqual(self.participation.snapshot['semester_id'], self.target.pk)
        self.assertEqual(intake_for(self.capstone).pk, self.target.pk)
        current_grade = TeamGrade.all_objects.filter(pk=self.grade.pk).values().get()
        self.assertEqual({**old_grade, 'semester_id': self.target.pk}, current_grade)
        self.assertEqual(get_user_model().objects.get(pk=self.student.pk).password, password_before)
        self.source.refresh_from_db()
        self.target.refresh_from_db()
        self.assertFalse(self.source.is_active)
        self.assertTrue(self.target.is_active)
        self.assertEqual(self.target.starts_on, self.source.starts_on)
        self.assertEqual(self.target.capstone_program_phase, Semester.PHASE_CAPSTONE_1)
        self.assertEqual(SystemAuditLog.objects.filter(action='semester.demo_baseline_corrected').count(), 1)

    def test_nonempty_target_and_changed_counts_are_refused(self):
        with self.assertRaises(ValueError):
            rebase_demo_term(**{**self.kwargs, 'expected_teams': 3})
        PITSectionRoster.objects.create(semester=self.target, year_level='1st Year', section='BSIT-1A')
        with self.assertRaisesRegex(ValueError, 'Destination has'):
            rebase_demo_term(**self.kwargs)

    def test_closed_history_or_existing_cohort_cannot_be_rewritten(self):
        from django.utils import timezone
        self.participation.closed_at = timezone.now()
        self.participation.save(update_fields=['closed_at'])
        with self.assertRaisesRegex(ValueError, 'open current'):
            rebase_demo_term(**self.kwargs)
        self.participation.closed_at = None
        self.participation.save(update_fields=['closed_at'])
        HistoricalCapstoneJourney.objects.bulk_create([HistoricalCapstoneJourney(team=self.capstone, intake_semester=self.source,
            normal_completion_year='2025-2026', extension_end_year='2026-2027')])
        with self.assertRaisesRegex(ValueError, 'cohort/assessment'):
            rebase_demo_term(**self.kwargs)

    def test_stale_preview_and_existing_backup_are_refused_before_writes(self):
        preview = rebase_demo_term(**self.kwargs)
        with TemporaryDirectory() as directory:
            backup = Path(directory) / 'before.json'
            self.pit.name = 'Changed during review'
            self.pit.save(update_fields=['name'])
            with self.assertRaisesRegex(ValueError, 'stale'):
                rebase_demo_term(**self.kwargs, apply=True, backup_path=backup,
                    preview_revision=preview['preview_revision'])
            self.assertFalse(backup.exists())
            preview = rebase_demo_term(**self.kwargs)
            backup.write_text('Keep recovery evidence')
            with self.assertRaises(FileExistsError):
                rebase_demo_term(**self.kwargs, apply=True, backup_path=backup,
                    preview_revision=preview['preview_revision'])
            self.assertEqual(backup.read_text(), 'Keep recovery evidence')
        self.capstone.refresh_from_db()
        self.assertEqual(self.capstone.semester_id, self.source.pk)

    def test_failed_audit_rolls_back_entire_move(self):
        preview = rebase_demo_term(**self.kwargs)
        with TemporaryDirectory() as directory, patch(
            'academic_period_management.demo_rebase.log_high_impact_action', side_effect=APIException('Audit unavailable')):
            with self.assertRaises(APIException):
                rebase_demo_term(**self.kwargs, apply=True, backup_path=Path(directory) / 'before.json',
                    preview_revision=preview['preview_revision'])
        self.capstone.refresh_from_db()
        self.grade.refresh_from_db()
        self.source.refresh_from_db()
        self.target.refresh_from_db()
        self.assertEqual(self.capstone.semester_id, self.source.pk)
        self.assertEqual(self.grade.semester_id, self.source.pk)
        self.assertTrue(self.source.is_active)
        self.assertFalse(self.target.is_active)
        self.assertFalse(HistoricalCapstoneJourney.objects.exists())
