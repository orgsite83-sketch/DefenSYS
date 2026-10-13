"""Regression checks for the directory reload after a 256-student import."""

from time import perf_counter

from django.contrib.auth import get_user_model
from django.db import connection
from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import SectionInstructorAssignment


User = get_user_model()


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class ImportRefreshPerformanceTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.admin = User.objects.create_user(username='refresh-admin', role='admin')
        school_year = SchoolYear.objects.create(label='2041-2042')
        cls.semester = Semester.objects.create(
            school_year=school_year, label=Semester.FIRST, is_active=True,
        )
        cls.instructor = User.objects.create_user(
            username='refresh-instructor', role='faculty', first_name='Intake', last_name='Instructor',
        )
        cls.students = User.objects.bulk_create([
            User(username=f'refresh-{index:04d}', role='student', first_name=f'Student {index}')
            for index in range(256)
        ])
        StudentAcademicRecord.objects.bulk_create([
            StudentAcademicRecord(
                student=student, semester=cls.semester,
                year_level=StudentAcademicRecord.FIRST_YEAR, section=f'BSIT-1{index % 4}',
            )
            for index, student in enumerate(cls.students)
        ])
        for section in range(4):
            SectionInstructorAssignment.objects.create(
                faculty=cls.instructor, semester=cls.semester,
                year_level=StudentAcademicRecord.FIRST_YEAR, section=f'BSIT-1{section}',
            )

    def setUp(self):
        self.client.force_authenticate(self.admin)

    def test_student_directory_queries_do_not_grow_per_student(self):
        started = perf_counter()
        with CaptureQueriesContext(connection) as queries:
            response = self.client.get('/api/users/')
        elapsed = perf_counter() - started
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['students'], 256)
        student_rows = [user for user in response.data['users'] if user['role'] == 'student']
        self.assertEqual(len(student_rows), 256)
        self.assertTrue(all(row['displayRole']['label'] == '1st Year' for row in student_rows))
        instructor = next(user for user in response.data['users'] if user['id'] == self.instructor.id)
        self.assertTrue(instructor['facultyRoles']['pitInstructor'])
        self.assertEqual(len(instructor['instructor_assignments']), 4)
        print(f'256-student user directory: {len(queries)} queries, {elapsed:.3f}s')
        self.assertLessEqual(len(queries), 12)

    def test_academic_records_batch_load_instructors(self):
        started = perf_counter()
        with CaptureQueriesContext(connection) as queries:
            response = self.client.get('/api/users/academic-records/')
        elapsed = perf_counter() - started
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['records']), 256)
        for row in response.data['records']:
            self.assertEqual(row['instructor_id'], self.instructor.id)
            self.assertEqual(row['instructor_name'], 'Intake Instructor')
        print(f'256-student academic records: {len(queries)} queries, {elapsed:.3f}s')
        self.assertLessEqual(len(queries), 12)

    @override_settings(PASSWORD_HASHERS=['defensys_backend.hashers.OptimizedPBKDF2PasswordHasher'])
    def test_import_256_students_with_configured_password_hashing(self):
        rows = [
            {
                'id_number': f'new-intake-{index:04d}', 'role': 'student',
                'first_name': f'New Student {index}',
                'year_level': StudentAcademicRecord.YEAR_LEVEL_CHOICES[index // 64][0],
                'email': f'intake{index}@example.com',
            }
            for index in range(256)
        ]
        started = perf_counter()
        with CaptureQueriesContext(connection) as queries:
            response = self.client.post('/api/users/bulk-import/', {
                'student_context': {'semester_id': self.semester.pk}, 'users': rows,
            }, format='json')
        elapsed = perf_counter() - started
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 256)
        self.assertEqual(response.data['records_created_count'], 256)
        self.assertEqual(response.data['error_count'], 0)
        for index in (0, 64, 128, 255):
            student = User.objects.get(username=rows[index]['id_number'])
            self.assertTrue(student.check_password(rows[index]['id_number']))
            self.assertEqual(student.academic_records.get().year_level, rows[index]['year_level'])
        print(f'256-student import with configured password hashing: {len(queries)} queries, {elapsed:.3f}s')

    def test_historical_instructor_roles_and_no_active_semester_are_preserved(self):
        historical = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        faculty = User.objects.create_user(username='historical-instructor', role='faculty')
        SectionInstructorAssignment.objects.create(
            faculty=faculty, semester=historical,
            year_level=StudentAcademicRecord.SECOND_YEAR, section='BSIT-2A',
        )
        for is_active in (True, False):
            with self.subTest(active_semester=is_active):
                Semester.objects.filter(pk=self.semester.pk).update(is_active=is_active)
                response = self.client.get('/api/users/')
                row = next(user for user in response.data['users'] if user['id'] == faculty.pk)
                self.assertTrue(row['facultyRoles']['pitInstructor'])
                self.assertEqual(len(row['instructor_assignments']), 0 if is_active else 1)
                self.assertEqual(row['displayRole']['key'], 'faculty' if is_active else 'pit_instructor')
                detail = self.client.get(f'/api/users/{faculty.pk}/')
                self.assertEqual(detail.data['user']['displayRole'], row['displayRole'])
                self.assertEqual(detail.data['user']['instructor_assignments'], row['instructor_assignments'])
