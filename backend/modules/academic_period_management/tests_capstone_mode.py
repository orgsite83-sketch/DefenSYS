from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from student_teams.models import StudentTeam

from .capstone_mode import (
    MODE_CAPSTONE_1_INTAKE,
    MODE_CAPSTONE_2_CONTINUE,
    MODE_OFF,
    capstone_operating_mode,
    default_capstone_flags_for_label,
    derive_capstone_program_phase,
    derive_capstone_team_creation_enabled,
    normalize_capstone_flags,
)
from .models import SchoolYear, Semester


User = get_user_model()


class CapstoneModeTests(APITestCase):
    def test_default_flags_for_first_and_second_semester(self):
        creation, phase = default_capstone_flags_for_label(Semester.FIRST)
        self.assertFalse(creation)
        self.assertEqual(phase, Semester.PHASE_NONE)

        creation, phase = default_capstone_flags_for_label(Semester.SECOND)
        self.assertTrue(creation)
        self.assertEqual(phase, Semester.PHASE_CAPSTONE_1)

    def test_operating_mode_off_on_first_semester_without_teams(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        info = capstone_operating_mode(semester)
        self.assertEqual(info['mode'], MODE_OFF)
        self.assertFalse(info['can_create_capstone_teams'])

    def test_operating_mode_capstone_1_intake(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        info = capstone_operating_mode(semester)
        self.assertEqual(info['mode'], MODE_CAPSTONE_1_INTAKE)
        self.assertTrue(info['can_create_capstone_teams'])

    def test_operating_mode_capstone_2_when_fourth_year_teams_exist(self):
        school_year = SchoolYear.objects.create(label='2027-2028')
        first = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        student = User.objects.create_user(
            username='capstone-leader',
            password='pass12345',
            role='student',
        )
        StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Project',
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year',
            semester=first,
            leader=student,
        )
        info = capstone_operating_mode(first)
        self.assertEqual(info['mode'], MODE_CAPSTONE_2_CONTINUE)
        self.assertTrue(info['can_create_capstone_teams'])

    def test_create_semester_applies_capstone_defaults(self):
        admin = User.objects.create_user(
            username='admin-capstone',
            password='pass12345',
            role='admin',
        )
        self.client.force_authenticate(user=admin)
        school_year = SchoolYear.objects.create(label='2026-2027')

        first = self.client.post(
            f'/api/academic-periods/{school_year.id}/semesters/',
            {'label': Semester.FIRST},
            format='json',
        )
        self.assertEqual(first.status_code, 201)
        self.assertFalse(first.data['semester']['capstone_team_creation_enabled'])
        self.assertEqual(first.data['semester']['capstone_program_phase'], Semester.PHASE_NONE)

        second = self.client.post(
            f'/api/academic-periods/{school_year.id}/semesters/',
            {'label': Semester.SECOND},
            format='json',
        )
        self.assertEqual(second.status_code, 201)
        self.assertTrue(second.data['semester']['capstone_team_creation_enabled'])
        self.assertEqual(second.data['semester']['capstone_program_phase'], Semester.PHASE_CAPSTONE_1)

    def test_derive_phase_second_sem_always_capstone_1(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        second = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
        )
        self.assertEqual(
            derive_capstone_program_phase(second),
            Semester.PHASE_CAPSTONE_1,
        )
        self.assertTrue(derive_capstone_team_creation_enabled(second))

    def test_derive_phase_first_sem_with_fourth_year_teams(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        first = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
        )
        student = User.objects.create_user(
            username='leader-2',
            password='pass12345',
            role='student',
        )
        StudentTeam.objects.create(
            name='Team Beta',
            project_title='Project',
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year',
            semester=first,
            leader=student,
        )
        self.assertEqual(
            derive_capstone_program_phase(first),
            Semester.PHASE_CAPSTONE_2,
        )
        self.assertTrue(derive_capstone_team_creation_enabled(first))

    def test_normalize_second_semester(self):
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            capstone_program_phase=Semester.PHASE_NONE,
            capstone_team_creation_enabled=False,
        )
        normalize_capstone_flags(semester)
        semester.save()
        semester.refresh_from_db()
        self.assertEqual(semester.capstone_program_phase, Semester.PHASE_CAPSTONE_1)
        self.assertTrue(semester.capstone_team_creation_enabled)

    def test_activate_second_sem_derives_capstone_1(self):
        admin = User.objects.create_user(
            username='admin-capstone-patch',
            password='pass12345',
            role='admin',
        )
        self.client.force_authenticate(user=admin)
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=False,
        )

        response = self.client.patch(
            f'/api/academic-periods/semesters/{semester.id}/',
            {'is_active': True},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data['semester']['capstone_program_phase'],
            Semester.PHASE_CAPSTONE_1,
        )
        self.assertTrue(response.data['semester']['capstone_team_creation_enabled'])

    def test_patch_ignores_client_capstone_phase(self):
        admin = User.objects.create_user(
            username='admin-capstone-ignore',
            password='pass12345',
            role='admin',
        )
        self.client.force_authenticate(user=admin)
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.SECOND,
            is_active=True,
        )

        response = self.client.patch(
            f'/api/academic-periods/semesters/{semester.id}/',
            {'capstone_program_phase': Semester.PHASE_NONE},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data['semester']['capstone_program_phase'],
            Semester.PHASE_CAPSTONE_1,
        )
