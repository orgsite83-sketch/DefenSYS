"""End-to-end eligibility, ordering, history and override regression coverage."""
from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester, SemesterTransitionLog
from authentication_access_control.models import SystemAuditLog
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from repository.deliverables.models import DeliverableSubmission
from user_management.academic_records.models import StudentAcademicRecord
from .models import StudentTeam, TeamMembership, StudentCapstoneParticipation, TeamTermParticipation
from .continuation_sections import progressed_section, section_decisions


User = get_user_model()


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class ContinuationSectionTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username='sections-admin', role='admin')
        self.adviser = User.objects.create_user(username='sections-adviser', role='faculty', is_adviser=True)
        self.student = User.objects.create_user(username='sections-leader', role='student')
        self.member = User.objects.create_user(username='sections-member', role='student')
        self.client.force_authenticate(self.admin)
        old = SchoolYear.objects.create(label='2045-2046')
        new = SchoolYear.objects.create(label='2046-2047')
        self.source = Semester.objects.create(school_year=old, label=Semester.SECOND, is_active=True,
            starts_on='2000-01-01', ends_on='2199-12-31',
            capstone_peer_evaluation_enabled=False, capstone_adviser_grading_enabled=False)
        self.target = Semester.objects.create(school_year=new, label=Semester.FIRST,
            starts_on='2000-01-01', ends_on='2199-12-31',
            capstone_peer_evaluation_enabled=False, capstone_adviser_grading_enabled=False)
        DefenseStage.objects.update(is_active=False)
        self.stage = DefenseStage.objects.create(label='Section test proposal', display_order=1)
        DefenseStage.objects.create(label='Section test final', display_order=2)
        self.stage.deliverables.create(deliverable_id='PRE', label='Proposal',
            deliverable_type='pre', required=True)
        self.team = StudentTeam.objects.create(name='Section continuation', project_title='Same project',
            semester=self.source, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year',
            section='BSIT-3A', leader=self.student, adviser=self.adviser)
        for student in (self.student, self.member):
            TeamMembership.objects.create(team=self.team, student=student, is_leader=student == self.student)
            StudentAcademicRecord.objects.create(student=student, semester=self.source,
                year_level='3rd Year', section='BSIT-3A')
        DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label,
            deliverable_id='PRE', label='Proposal', deliverable_type='pre',
            file_name='proposal.pdf', status='accepted')

    def assess(self, verdict='approved'):
        grade = TeamGrade(team=self.team, semester=self.source, defense_stage=self.stage,
            scope='capstone', verdict=verdict, status='published',
            panel_score=85, adviser_score=85, peer_score=85)
        grade.save(clean=False)

    def transition_preview(self):
        response = self.client.get(f'/api/academic-periods/semesters/{self.target.pk}/transition-preview/')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def migrate(self, force=False):
        preview = self.transition_preview()
        response = self.client.post(f'/api/academic-periods/semesters/{self.target.pk}/activate/',
            {'preview_revision': preview['preview_revision'], 'force': force,
             'reason': 'Keep unresolved source work historical.' if force else ''}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.target.refresh_from_db()
        return response

    def import_students(self, students=None, section=None, year='4th Year', extra=None):
        rows = [{'id_number': s.username, 'role': 'student', 'year_level': year,
            **({'section': section} if section is not None else {}), **(extra or {})}
            for s in (students or [self.student, self.member])]
        response = self.client.post('/api/users/bulk-import/',
            {'users': rows, 'student_context': {'semester_id': self.target.pk}}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        return response

    def sections(self, term=None):
        return list(StudentAcademicRecord.objects.filter(semester=term or self.target,
            student__in=[self.student, self.member]).order_by('student_id').values_list('section', flat=True))

    def test_section_format_and_repeat_year(self):
        for source in ('BSIT-3A', 'bsit 3a', 'BSIT3A', 'BSIT-3AB'):
            self.assertEqual(progressed_section(source, '3rd Year'), 'BSIT-4' + ('AB' if source.endswith('AB') else 'A'))
        self.assertEqual(progressed_section('BSIT-4B', '4th Year'), 'BSIT-4B')
        for source, year in [('BSIT', '3rd Year'), ('BSCS-3A', '3rd Year'),
                ('BSIT-3A', '4th Year'), ('BSIT-2A', '2nd Year')]:
            self.assertEqual(progressed_section(source, year), '')

    def test_enrollment_first_waits_for_approved_migration_and_keeps_history(self):
        self.import_students()
        self.assertEqual(self.sections(), ['', ''])
        self.assertFalse(StudentCapstoneParticipation.objects.exists())
        self.assess()
        preview = self.transition_preview()
        row = preview['capstone_review']['teams'][0]
        self.assertTrue(row['can_include'])
        self.assertEqual(row['section_progression']['section'], 'BSIT-4A')
        self.assertEqual(self.sections(), ['', ''])
        self.migrate()
        self.assertEqual(self.team.section, 'BSIT-4A')
        self.assertEqual(self.sections(), ['BSIT-4A', 'BSIT-4A'])
        self.assertEqual(self.sections(self.source), ['BSIT-3A', 'BSIT-3A'])
        self.assertEqual(self.team.adviser_id, self.adviser.pk)
        self.assertEqual(self.team.project_title, 'Same project')
        self.assertEqual(self.team.memberships.count(), 2)
        old = self.team.term_participations.get(semester=self.source)
        self.assertEqual(old.snapshot['section'], 'BSIT-3A')
        self.assertEqual(old.snapshot['adviser_id'], self.adviser.pk)

    def test_migration_first_import_preview_and_reimport_preserve_same_participations(self):
        self.assess()
        self.migrate()
        self.assertFalse(StudentAcademicRecord.objects.filter(semester=self.target).exists())
        before = (StudentCapstoneParticipation.objects.count(), SystemAuditLog.objects.count())
        response = self.client.post('/api/users/academic-records/section-preview/',
            {'semester_id': self.target.pk, 'students': [{'id_number': self.student.username,
                'year_level': '4th Year', 'section': ''}]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        decision = response.data['sections'][0]
        self.assertEqual((decision['section'], decision['source']), ('BSIT-4A', 'inferred'))
        self.assertEqual(before, (StudentCapstoneParticipation.objects.count(), SystemAuditLog.objects.count()))
        self.import_students()
        history_count = SystemAuditLog.objects.count()
        self.import_students()
        self.assertEqual(SystemAuditLog.objects.count(), history_count)
        self.assertEqual(self.sections(), ['BSIT-4A', 'BSIT-4A'])
        self.assertEqual(StudentCapstoneParticipation.objects.count(), 2)
        self.assertEqual(StudentAcademicRecord.objects.filter(semester=self.target).count(), 2)

    def test_failed_or_unresolved_team_cannot_gain_continuation_from_import(self):
        for verdict in ('', 'failed'):
            with self.subTest(verdict=verdict):
                if verdict:
                    self.assess(verdict)
                self.import_students()
                preview = self.transition_preview()
                row = preview['capstone_review']['teams'][0]
                self.assertFalse(row['can_include'])
                self.assertNotIn('section_progression', row)
                self.assertEqual(self.sections(), ['', ''])
                self.assertFalse(StudentCapstoneParticipation.objects.exists())
        self.migrate(force=True)
        self.import_students()
        self.assertEqual(self.team.semester_id, self.source.pk)
        self.assertEqual(self.sections(), ['', ''])

    def test_unverified_current_capstone_team_does_not_authorize_defaults(self):
        self.source.is_active = False
        self.source.save()
        self.target.is_active = True
        self.target.save()
        self.team.semester, self.team.level, self.team.year_level = self.target, StudentTeam.LEVEL_4_CAPSTONE, '4th Year'
        self.team.section = 'BSIT-4A'
        self.team.save()
        before = list(self.team.term_participations.values())
        self.import_students()
        self.assertEqual(self.sections(), ['', ''])
        self.assertEqual(list(self.team.term_participations.values()), before)

    def test_rollover_preview_matches_commit_and_never_moves_team_again(self):
        self.assess()
        self.migrate()
        source = StudentAcademicRecord.objects.get(student=self.student, semester=self.source)
        response = self.client.post('/api/users/academic-records/rollover-preview/',
            {'students': [{'id_number': self.student.username, 'year_level': '4th Year'}]}, format='json')
        row = next(r for r in response.data['rows'] if r['record']['student_username'] == self.student.username)
        self.assertEqual(row['promote_result']['section'], 'BSIT-4A')
        self.assertTrue(row['promote_result']['section_automatic'])
        response = self.client.post('/api/users/academic-records/rollover/', {'actions': [{
            'record_id': source.pk, 'action': 'promote', 'target_semester_id': self.target.pk,
            'year_level': '4th Year'}]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['team_updates'], 0)
        self.assertEqual(self.sections(), ['BSIT-4A'])
        self.team.refresh_from_db()
        self.assertEqual(self.team.semester_id, self.target.pk)

    def test_explicit_destination_section_takes_precedence(self):
        self.import_students(section='BSIT-4B')
        self.assess()
        self.migrate()
        self.assertEqual(self.team.section, 'BSIT-4B')
        self.import_students()
        self.assertEqual(self.sections(), ['BSIT-4B', 'BSIT-4B'])

    def test_partial_enrollment_conflict_is_reported_without_filling_blanks(self):
        self.assess()
        self.migrate()
        self.import_students(students=[self.member], section='BSIT-4B')
        decision = section_decisions(self.target, {self.student.pk: '4th Year'})[self.student.pk]
        self.assertEqual(decision['source'], 'review')
        self.assertEqual(decision['section'], '')
        self.import_students(students=[self.student])
        self.assertEqual(self.sections(), ['', 'BSIT-4B'])

    def test_unknown_or_mixed_source_sections_are_reviewed(self):
        StudentAcademicRecord.objects.filter(student=self.member).update(section='Unknown')
        self.assess()
        preview = self.transition_preview()['capstone_review']['teams'][0]
        self.assertTrue(preview['can_include'])
        self.assertTrue(preview['section_progression']['issues'])
        self.migrate()
        self.import_students()
        self.assertEqual(self.sections(), ['BSIT-4A', ''])

    def test_mixed_recognized_source_sections_remain_unassigned_until_reviewed(self):
        StudentAcademicRecord.objects.filter(student=self.member).update(section='BSIT-3B')
        self.assess()
        self.migrate()
        self.import_students()
        self.assertEqual(self.sections(), ['', ''])
        self.team.refresh_from_db()
        self.assertEqual(self.team.section, '')
        self.import_students(section='BSIT-4C')
        self.assertEqual(self.sections(), ['BSIT-4C', 'BSIT-4C'])

    def test_stale_rollover_section_is_rejected_atomically(self):
        self.assess()
        self.migrate()
        source = StudentAcademicRecord.objects.get(student=self.student, semester=self.source)
        expected = section_decisions(self.target, {self.student.pk: '4th Year'})[self.student.pk]
        self.team.section = 'BSIT-4D'
        self.team.save()
        response = self.client.post('/api/users/academic-records/rollover/', {'actions': [{
            'record_id': source.pk, 'action': 'promote', 'year_level': '4th Year',
            'target_semester_id': self.target.pk, 'section_resolution': expected,
        }]}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(self.sections(), [])

    def test_fourth_year_repeat_intake_never_becomes_fifth_year(self):
        StudentAcademicRecord.objects.filter(semester=self.source).update(year_level='4th Year', section='BSIT-4C')
        self.team.year_level, self.team.level, self.team.section = '4th Year', StudentTeam.LEVEL_4_CAPSTONE, 'BSIT-4C'
        self.team.save()
        self.assess()
        self.migrate()
        self.import_students()
        self.assertEqual(self.sections(), ['BSIT-4C', 'BSIT-4C'])

    def test_admin_section_and_adviser_edits_survive_reimport(self):
        self.assess()
        self.migrate()
        self.import_students()
        replacement = User.objects.create_user(username='replacement-adviser', role='faculty', is_adviser=True)
        response = self.client.patch(f'/api/teams/{self.team.pk}/', {
            'name': self.team.name, 'project_title': self.team.project_title,
            'level': StudentTeam.LEVEL_4_CAPSTONE, 'year_level': '4th Year', 'section': 'BSIT-4D',
            'leader_id': self.student.pk, 'member_ids': [self.student.pk, self.member.pk],
            'adviser_id': replacement.pk, 'adviser_change_reason': 'Department reassignment.',
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.import_students(section='BSIT-4A')
        self.team.refresh_from_db()
        self.assertEqual((self.team.section, self.team.adviser_id), ('BSIT-4D', replacement.pk))
        self.assertEqual(self.sections(), ['BSIT-4D', 'BSIT-4D'])
        self.assertTrue(self.team.term_participations.get(semester=self.target).snapshot[
            'continuation_sections']['admin_override'])

    def test_pit_team_and_enrollment_are_not_progressed(self):
        self.team.level, self.team.year_level = StudentTeam.LEVEL_3_PIT, '3rd Year'
        self.team.save()
        self.migrate()
        self.import_students()
        self.assertEqual(self.sections(), ['', ''])
        self.assertEqual(self.team.semester_id, self.source.pk)
        self.assertEqual(self.team.section, 'BSIT-3A')
        self.assertFalse(StudentCapstoneParticipation.objects.exists())

    def test_stale_import_preview_is_rejected_without_enrollment_writes(self):
        self.assess()
        self.migrate()
        decision = section_decisions(self.target, {self.student.pk: '4th Year'})[self.student.pk]
        self.team.section = 'BSIT-4Z'
        self.team.save()
        response = self.client.post('/api/users/bulk-import/', {'student_context': {
            'semester_id': self.target.pk}, 'users': [{'id_number': self.student.username,
                'role': 'student', 'year_level': '4th Year', '_section_resolution': decision}]}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(self.sections(), [])

    def test_direct_admin_override_survives_snapshot_refresh_and_partial_imports(self):
        self.assess()
        self.migrate()
        self.team.section = 'BSIT-4D'
        self.team.save()
        self.import_students(students=[self.student])
        self.import_students(students=[self.member])
        self.assertEqual(self.sections(), ['BSIT-4D', 'BSIT-4D'])
        row = self.team.term_participations.get(semester=self.target)
        self.assertTrue(row.snapshot['continuation_sections']['admin_override'])

    def test_source_section_change_invalidates_transition_preview(self):
        self.assess()
        preview = self.transition_preview()
        before = list(TeamTermParticipation.objects.values())
        StudentAcademicRecord.objects.filter(semester=self.source).update(section='BSIT-3Z')
        response = self.client.post(f'/api/academic-periods/semesters/{self.target.pk}/activate/',
            {'preview_revision': preview['preview_revision']}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(SemesterTransitionLog.objects.exists())
        self.assertEqual(list(TeamTermParticipation.objects.values()), before)

    def test_section_preview_requires_admin_and_writes_nothing(self):
        self.client.force_authenticate(self.student)
        response = self.client.post('/api/users/academic-records/section-preview/',
            {'semester_id': self.target.pk, 'students': []}, format='json')
        self.assertEqual(response.status_code, 403)

    def test_capstone_team_and_section_editor_reject_third_year_destination_label(self):
        self.assess()
        self.migrate()
        self.import_students()
        response = self.client.patch(f'/api/teams/{self.team.pk}/section/', {
            'expected_section': 'BSIT-4A', 'section': 'BSIT-3A'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        response = self.client.patch(f'/api/teams/{self.team.pk}/', {
            'name': self.team.name, 'project_title': self.team.project_title,
            'leader_id': self.student.pk, 'member_ids': [self.student.pk, self.member.pk],
            'adviser_id': self.adviser.pk, 'year_level': '4th Year',
            'level': StudentTeam.LEVEL_4_CAPSTONE, 'section': 'BSIT-3A'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.team.refresh_from_db()
        self.assertEqual(self.team.section, 'BSIT-4A')

    def test_import_and_manual_enrollment_reject_third_year_capstone_two_section(self):
        self.assess()
        self.migrate()
        response = self.client.post('/api/users/bulk-import/', {'student_context': {
            'semester_id': self.target.pk}, 'users': [{'id_number': self.student.username,
            'role': 'student', 'year_level': '4th Year', 'section': 'BSIT-3A'}]}, format='json')
        self.assertEqual(response.data['error_count'], 1, response.data)
        self.assertFalse(StudentAcademicRecord.objects.filter(semester=self.target).exists())
        response = self.client.post('/api/users/academic-records/', {'student_id': self.student.pk,
            'semester_id': self.target.pk, 'year_level': '4th Year', 'section': 'BSIT-3A'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)

    def test_team_import_preview_uses_the_same_section_year_guard(self):
        from .team_levels import prepare_bulk_row
        self.assess()
        self.migrate()
        self.import_students()
        row, issues = prepare_bulk_row({'team_name': 'Bad section',
            'level': StudentTeam.LEVEL_4_CAPSTONE, 'section': 'BSIT-3A'}, self.admin,
            member_user_ids=[self.student.pk, self.member.pk], leader_user_id=self.student.pk,
            semester=self.target)
        self.assertIsNone(row)
        self.assertTrue(any('matching section' in issue for issue in issues))

    def test_third_year_first_semester_section_remains_valid_for_pit(self):
        self.source.is_active = False
        self.source.save()
        self.target.is_active = True
        self.target.save()
        record = StudentAcademicRecord.objects.create(student=self.student, semester=self.target,
            year_level='3rd Year', section='BSIT-3A')
        team = StudentTeam.objects.create(name='PIT third-year class', leader=self.student,
            semester=self.target, level=StudentTeam.LEVEL_3_PIT, year_level='3rd Year', section='BSIT-3A')
        self.assertEqual((record.year_level, record.section), ('3rd Year', 'BSIT-3A'))
        self.assertEqual(team.level, StudentTeam.LEVEL_3_PIT)

    def test_section_import_cannot_downgrade_confirmed_capstone_two_to_third_year(self):
        from .serializers import StudentTeamWriteSerializer
        from .team_levels import prepare_bulk_row
        self.assess()
        self.migrate()
        self.import_students()
        payload = {'name': self.team.name, 'leader_id': self.student.pk,
            'member_ids': [self.student.pk, self.member.pk], 'adviser_id': self.adviser.pk,
            'level': StudentTeam.LEVEL_3_CAPSTONE, 'year_level': '3rd Year', 'section': 'BSIT-3A'}
        serializer = StudentTeamWriteSerializer(self.team, data=payload,
            context={'user': self.admin, 'section_import': True})
        self.assertFalse(serializer.is_valid())
        self.assertIn('year_level', serializer.errors)
        prepared, issues = prepare_bulk_row(payload, self.admin, semester=self.target, section_import=True)
        self.assertIsNone(prepared)
        self.assertTrue(any('fourth year' in issue for issue in issues))

    def test_legacy_section_correction_is_previewed_backed_up_and_preserves_history(self):
        import tempfile
        from pathlib import Path
        from .section_progression_repair import correct_current_sections
        self.assess()
        self.migrate()
        self.import_students()
        # Reproduce labels written by the earlier transition, bypassing today's guard.
        StudentTeam.objects.filter(pk=self.team.pk).update(section='BSIT-3A')
        StudentAcademicRecord.objects.filter(semester=self.target).update(section='')
        row = self.team.term_participations.get(semester=self.target)
        row.snapshot.pop('continuation_sections', None)
        row.snapshot['section'] = 'BSIT-3A'
        row.save()
        historical = list(TeamTermParticipation.objects.filter(semester=self.source).values())
        review = correct_current_sections(semester_id=self.target.pk)
        self.assertEqual((review['team_count'], review['enrollment_count']), (1, 2))
        self.assertEqual(self.sections(), ['', ''])
        with tempfile.TemporaryDirectory() as directory:
            backup = Path(directory) / 'backup.json'
            result = correct_current_sections(semester_id=self.target.pk, apply=True, actor=self.admin,
                backup_path=backup, revision=review['revision'], expected_teams=1, expected_enrollments=2)
            self.assertTrue(result['applied'])
            self.assertTrue(backup.exists())
        self.team.refresh_from_db()
        self.assertEqual(self.team.section, 'BSIT-4A')
        self.assertEqual(self.sections(), ['BSIT-4A', 'BSIT-4A'])
        self.assertEqual(self.sections(self.source), ['BSIT-3A', 'BSIT-3A'])
        self.assertEqual(historical, list(TeamTermParticipation.objects.filter(semester=self.source).values()))
        self.assertEqual(self.team.adviser_id, self.adviser.pk)
        self.assertEqual(correct_current_sections(semester_id=self.target.pk)['team_count'], 0)

    def test_correction_rejects_stale_review_or_wrong_counts_before_writing(self):
        import tempfile
        from pathlib import Path
        from .section_progression_repair import correct_current_sections
        self.assess()
        self.migrate()
        StudentTeam.objects.filter(pk=self.team.pk).update(section='BSIT-3A')
        row = self.team.term_participations.get(semester=self.target)
        row.snapshot.pop('continuation_sections', None)
        row.snapshot['section'] = 'BSIT-3A'
        row.save()
        review = correct_current_sections(semester_id=self.target.pk)
        with tempfile.TemporaryDirectory() as directory:
            for revision, teams in [('stale', 1), (review['revision'], 999)]:
                with self.assertRaises(ValueError):
                    correct_current_sections(semester_id=self.target.pk, apply=True, actor=self.admin,
                        backup_path=Path(directory) / 'backup.json', revision=revision,
                        expected_teams=teams, expected_enrollments=0)
        self.team.refresh_from_db()
        self.assertEqual(self.team.section, 'BSIT-3A')
