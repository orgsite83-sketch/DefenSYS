"""A past enrollment cannot authorize a current roster through any API path."""
from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework.test import APITestCase
from rest_framework.exceptions import ValidationError
from academic_period_management.models import SchoolYear, Semester
from user_management.academic_records.models import StudentAcademicRecord
from .models import StudentTeam, TeamMembership, StudentCapstoneParticipation, StudentCapstonePlacement
from .serializers import StudentTeamWriteSerializer


class RosterEnrollmentTests(APITestCase):
    def setUp(self):
        year = SchoolYear.objects.create(label='2026-2027')
        self.old = Semester.objects.create(school_year=year, label=Semester.FIRST)
        self.current = Semester.objects.create(school_year=year, label=Semester.SECOND,
            is_active=True, capstone_team_creation_enabled=True)
        self.admin = get_user_model().objects.create_user(username='enrollment-admin', role='admin')
        self.ana = self.student('2023-0184', 'Ana', 'Reyes')
        self.bea = self.student('2026-0311', 'Bea', 'Santos')
        self.carlo = self.student('2026-0422', 'Carlo', 'Lim')
        self.old_record = StudentAcademicRecord.objects.create(student=self.ana,
            semester=self.old, year_level='3rd Year', section='OLD-3A')
        self.client.force_authenticate(self.admin)

    def student(self, username, first, last):
        return get_user_model().objects.create_user(username=username, first_name=first, last_name=last, role='student')

    def enroll(self, student, *, year='3rd Year', section='BSIT-3A'):
        return StudentAcademicRecord.objects.create(student=student, semester=self.current,
            year_level=year, section=section)

    def payload(self, members, *, pit=False, name='Current roster'):
        return {'name': name, 'project_title': 'Current project',
            'level': '2nd Year PIT' if pit else '3rd Year Capstone',
            'year_level': '2nd Year' if pit else '3rd Year', 'section': '',
            'member_ids': [s.pk for s in members], 'leader_id': members[0].pk}

    def bulk(self, members, *, pit=False):
        payload = self.payload(members, pit=pit)
        payload['team_name'] = payload.pop('name')
        payload['member_ids'] = [s.username for s in members]
        payload['leader_id'] = members[0].username
        return {'teams': [payload]}

    def assert_missing(self, data, *, include_bea=False):
        message = str(data)
        self.assertIn('Ana Reyes (2023-0184)', message)
        self.assertIn(self.current.display_name, message)
        self.assertIn('Enroll this student', message)
        if include_bea:
            self.assertIn('Bea Santos (2026-0311)', message)
        self.assertNotIn('Carlo Lim (2026-0422) is not enrolled', message)

    def assert_no_roster(self):
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(TeamMembership.objects.exists())
        self.assertFalse(StudentCapstoneParticipation.objects.exists())
        self.assertFalse(StudentCapstonePlacement.objects.exists())
        self.old_record.refresh_from_db()
        self.assertEqual((self.old_record.semester_id, self.old_record.section), (self.old.pk, 'OLD-3A'))

    def test_manual_capstone_and_pit_creation_name_each_missing_student(self):
        self.enroll(self.carlo)
        for pit in (False, True):
            with self.subTest(pit=pit):
                response = self.client.post('/api/teams/', self.payload([self.ana, self.bea, self.carlo], pit=pit), format='json')
                self.assertEqual(response.status_code, 400, response.data)
                self.assert_missing(response.data, include_bea=True)
                self.assert_no_roster()

    def test_legacy_bulk_preview_and_commit_share_the_named_guard(self):
        self.enroll(self.carlo)
        for pit in (False, True):
            for suffix in ('preview/', ''):
                with self.subTest(pit=pit, suffix=suffix):
                    response = self.client.post(f'/api/teams/bulk-import/{suffix}',
                        self.bulk([self.ana, self.bea, self.carlo], pit=pit), format='json')
                    self.assert_missing(response.data, include_bea=True)
                    if suffix:
                        self.assertEqual(response.status_code, 200)
                        self.assertFalse(response.data['rows'][0]['ready'])
                    else:
                        self.assertEqual(response.data['created_count'], 0)
                    self.assert_no_roster()

    def test_prepared_import_names_missing_students_before_confirmation(self):
        self.enroll(self.carlo)
        body = {**self.bulk([self.ana, self.bea, self.carlo]), 'level': '3rd Year Capstone'}
        response = self.client.post('/api/teams/generation/import/', body, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['ready'])
        self.assertIsNone(response.data['preview_token'])
        self.assert_missing(response.data, include_bea=True)
        self.assert_no_roster()

    def test_same_semester_label_in_another_year_does_not_count_as_enrollment(self):
        old_year = SchoolYear.objects.create(label='2025-2026')
        prior_second = Semester.objects.create(school_year=old_year, label=Semester.SECOND)
        StudentAcademicRecord.objects.create(student=self.ana, semester=prior_second, year_level='3rd Year')
        response = self.client.post('/api/teams/', self.payload([self.ana]), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_missing(response.data)
        self.assert_no_roster()

    def test_custom_generation_uses_the_same_named_enrollment_guard(self):
        from user_management.models import SectionInstructorAssignment
        self.enroll(self.carlo, year='2nd Year', section='BSIT-2A')
        instructor = get_user_model().objects.create_user(username='enrollment-instructor', role='faculty')
        SectionInstructorAssignment.objects.create(faculty=instructor, semester=self.current,
            year_level='2nd Year', section='BSIT-2A', assigned_by=self.admin)
        self.client.force_authenticate(instructor)
        response = self.client.post('/api/teams/generation/', {'level': '2nd Year PIT',
            'roster_mode': 'custom', 'student_ids': [self.ana.pk, self.carlo.pk],
            'sections': [], 'method': 'alphabetical', 'group_size': 2}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_missing(response.data)
        self.assert_no_roster()

    def test_prepared_commit_rechecks_enrollment_and_names_the_changed_student(self):
        record = self.enroll(self.ana)
        body = {**self.bulk([self.ana]), 'level': '3rd Year Capstone'}
        preview = self.client.post('/api/teams/generation/import/', body, format='json')
        self.assertTrue(preview.data['ready'], preview.data)
        record.delete()
        response = self.client.post('/api/teams/generation/import/create/',
            {'preview_token': preview.data['preview_token']}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_missing(response.data)
        self.assert_no_roster()

    def test_serializer_save_rechecks_after_successful_validation(self):
        record = self.enroll(self.ana)
        serializer = StudentTeamWriteSerializer(data=self.payload([self.ana]), context={'user': self.admin})
        self.assertTrue(serializer.is_valid(), serializer.errors)
        record.delete()
        with self.assertRaises(ValidationError) as error, transaction.atomic():
            serializer.save()
        self.assert_missing(error.exception.detail)
        self.assert_no_roster()

    def test_adding_a_past_only_member_cannot_replace_an_existing_roster(self):
        self.enroll(self.carlo)
        created = self.client.post('/api/teams/', self.payload([self.carlo]), format='json')
        self.assertEqual(created.status_code, 201, created.data)
        team_id = created.data['team']['id']
        response = self.client.patch(f'/api/teams/{team_id}/', self.payload([self.carlo, self.ana]), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assert_missing(response.data)
        self.assertEqual(list(TeamMembership.objects.filter(team_id=team_id).values_list('student_id', flat=True)), [self.carlo.pk])
        self.assertFalse(StudentCapstoneParticipation.objects.filter(student=self.ana).exists())

    def test_current_enrollment_allows_import_and_keeps_the_old_record(self):
        current = self.enroll(self.ana)
        response = self.client.post('/api/teams/bulk-import/', self.bulk([self.ana]), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(StudentCapstoneParticipation.objects.get(student=self.ana).number, 1)
        current.refresh_from_db()
        self.assertEqual(current.semester_id, self.current.pk)
        self.old_record.refresh_from_db()
        self.assertEqual(self.old_record.section, 'OLD-3A')
