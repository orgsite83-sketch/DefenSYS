"""Roster identity regressions. All ORM writes use Django's isolated test DB."""
from types import SimpleNamespace

from django.contrib.auth import get_user_model
from django.test import SimpleTestCase, TestCase
from rest_framework.test import APITestCase
from user_management.academic_records.models import StudentAcademicRecord

from . import tests as fixtures
from . import test_formation as roster_fixtures
from .bulk_import import (
    _person_names, import_user_lookup, reference_resolution,
    resolve_user_by_full_name, resolve_adviser,
)
from .models import StudentTeam
from .person_names import PersonNameIndex


def account(username, first, last, role='student', active=True):
    return SimpleNamespace(username=username, first_name=first, last_name=last,
                           role=role, is_active=active)


class PersonNameComparisonTests(SimpleTestCase):
    def resolve(self, reference, *users, role='student'):
        return PersonNameIndex(users, _person_names).resolve(reference, role)

    def test_reported_student_and_middle_initial_punctuation_in_either_direction(self):
        for stored, uploaded in (
            ('Johnley L', 'MATABALAN, Johnley L.'),
            ('Johnley L.', 'MATABALAN, Johnley L'),
            ('Johnley L', '  MATABALAN,\u00a0JOHNLEY  L.  '),
        ):
            with self.subTest(stored=stored, uploaded=uploaded):
                user = account('2023304712', stored, 'Matabalan')
                result = self.resolve(uploaded, user)
                self.assertIs(result.user, user)

    def test_unique_middle_initial_addition_or_omission_matches(self):
        for first, reference in (
            ('Ginbert', 'GINBERT A. FERNANDEZ'),
            ('Ginbert A.', 'Ginbert Fernandez'),
        ):
            user = account('207', first, 'Fernandez', 'faculty')
            result = self.resolve(reference, user, role=['faculty', 'admin'])
            self.assertIs(result.user, user)
            self.assertEqual(result.kind, 'omitted_initial')

    def test_conflicting_initials_and_substantive_names_do_not_match(self):
        user = account('207', 'Ginbert B', 'Fernandez')
        self.assertEqual(self.resolve('Ginbert A. Fernandez', user).status, 'selection_required')
        for reference in ('Ginbert Allan Fernandez', 'Gilbert B Fernandez'):
            self.assertIsNone(self.resolve(reference, user).user)
        self.assertIsNone(self.resolve('Ginbert 1 Fernandez',
            account('207', 'Ginbert', 'Fernandez')).user)

    def test_formatting_collision_including_inactive_account_is_ambiguous(self):
        users = [account('a', 'Johnley L', 'Matabalan'),
                 account('b', 'JOHNLEY L.', 'MATABALAN', active=False)]
        self.assertEqual(self.resolve('Matabalan, Johnley L.', *users).status, 'ambiguous')
        self.assertIs(self.resolve('a', *users).user, users[0])

    def test_omitted_initial_never_chooses_among_same_name_identities(self):
        for active in (True, False):
            users = [account('207', 'Ginbert', 'Fernandez', 'faculty'),
                     account('208', 'Ginbert B.', 'Fernandez', 'faculty', active=active)]
            self.assertEqual(self.resolve('Ginbert A. Fernandez', *users,
                role=['faculty', 'admin']).status, 'ambiguous')
            self.assertEqual(self.resolve('Ginbert Fernandez', *users,
                role=['faculty', 'admin']).status, 'ambiguous')
        users = [account('a', 'Ginbert A', 'Fernandez'), account('b', 'Ginbert B', 'Fernandez')]
        self.assertEqual(self.resolve('Ginbert Fernandez', *users).status, 'ambiguous')

    def test_client_edgar_suffix_and_legacy_embedded_commas_resolve(self):
        for first in ('EDGAR, JR C', 'EDGAR JR C', 'Edgar C Jr.'):
            user = account('client-edgar', first, 'TAC-AN')
            for reference in ('TAC-AN, Edgar Jr. C.', 'TAC-AN, EDGAR, JR C',
                              'Edgar C. Tac-an Jr.'):
                with self.subTest(first=first, reference=reference):
                    self.assertIs(self.resolve(reference, user).user, user)

    def test_client_spelling_difference_stays_blocked(self):
        self.assertIsNone(self.resolve('BONGCAC, Ryza Mae G.',
            account('client-ryza', 'RYZA MAY G.', 'BONGCAC')).user)

    def test_omitted_initial_preserves_given_names_and_suffix_identity(self):
        junior = account('a', 'Ginbert', 'Fernandez Jr.')
        senior = account('b', 'Ginbert A.', 'Fernandez Sr.')
        self.assertIs(self.resolve('Ginbert A. Fernandez Jr.', junior, senior).user, junior)
        self.assertIsNone(self.resolve('Ginbert A. Fernandez', junior).user)
        self.assertIsNone(self.resolve('Jo Maria C Santos', account('m', 'Jo', 'Santos')).user)

    def test_accents_compound_names_apostrophes_and_hyphens_are_preserved(self):
        user = account('a', 'Jose\u0301 Luis M.', "Dela Cruz-O'Neill")
        self.assertIs(self.resolve("Dela Cruz-O'Neill, JOSÉ LUIS M", user).user, user)
        for reference in ("Jose Luis M Dela Cruz-O'Neill", 'José Luis M Dela Cruz ONeill'):
            self.assertEqual(self.resolve(reference, user).status, 'not_found')

    def test_identity_suffix_is_preserved_and_credentials_still_supported(self):
        users = [account('jr', 'Juan', 'Dela Cruz Jr.'),
                 account('sr', 'Juan', 'Dela Cruz Sr.'),
                 account('iii', 'Juan', 'Dela Cruz III')]
        for reference, user in (
            ('Dr. Juan Dela Cruz Jr., PhD', users[0]),
            ('Dela Cruz Jr., Juan', users[0]),
            ('Juan Dela Cruz, Sr.', users[1]),
            ('Prof. Juan Dela Cruz III, MSIT', users[2]),
        ):
            with self.subTest(reference=reference):
                self.assertIs(self.resolve(reference, *users).user, user)
        self.assertIsNone(self.resolve('Juan Dela Cruz', *users).user)

    def test_existing_abbreviated_and_honorific_forms(self):
        user = account('2024-1', 'Juan', 'Dela Cruz')
        for reference in ('Dela Cruz, J.', 'J. Dela Cruz', 'Dela Cruz J.',
                          'Dela Cruz', 'Prof. Juan Dela Cruz, PhD', '2024-1'):
            with self.subTest(reference=reference):
                self.assertIs(self.resolve(reference, user).user, user)

    def test_role_boundary_and_repeated_resolution_cache(self):
        user = account('207', 'Ginbert', 'Fernandez', 'faculty')
        index = PersonNameIndex([user], _person_names)
        self.assertEqual(index.resolve('207', 'student').status, 'not_found')
        first = index.resolve('Ginbert A. Fernandez', ['faculty', 'admin'])
        self.assertIs(first, index.resolve('Ginbert A. Fernandez', ['admin', 'faculty']))


class ImportLookupTests(TestCase):
    def setUp(self):
        User = get_user_model()
        self.student = User.objects.create(username='2023304712', role='student',
                                           first_name='JOHNLEY L', last_name='MATABALAN')
        self.faculty = User.objects.create(username='207', role='faculty',
                                          first_name='GINBERT', last_name='FERNANDEZ')

    def test_cached_and_uncached_results_and_single_account_projection(self):
        uncached = resolve_user_by_full_name('Matabalan, Johnley L.', role='student')
        self.assertEqual(uncached, (self.student, None))
        with self.assertNumQueries(1):
            with import_user_lookup():
                for _ in range(20):
                    with import_user_lookup():
                        self.assertEqual(resolve_user_by_full_name(
                            'Matabalan, Johnley L.', role='student'), uncached)
                        self.assertEqual(resolve_adviser('207')[1], 'valid')
                        self.assertEqual(reference_resolution('Ginbert A. Fernandez',
                            role=['faculty', 'admin'])['status'], 'matched')

    def test_inactive_id_does_not_resolve_as_eligible_and_wrong_role_stays_blocked(self):
        self.student.is_active = False
        self.student.save(update_fields=['is_active'])
        user, error = resolve_user_by_full_name(self.student.username, role='student')
        self.assertIsNone(user)
        self.assertIn('inactive', error)
        self.assertEqual(resolve_adviser(self.student.username)[1], 'not_adviser')
        self.assertEqual(resolve_user_by_full_name('207', role='student')[0], None)


class ImportNameApiTests(APITestCase):
    setUp = fixtures.StudentTeamApiTests.setUp
    _activate_capstone_intake_semester = fixtures.StudentTeamApiTests._activate_capstone_intake_semester

    def row(self):
        self._activate_capstone_intake_semester()
        self.student_1.first_name, self.student_1.last_name = 'JOHNLEY L', 'MATABALAN'
        self.student_1.save(update_fields=['first_name', 'last_name'])
        return {'team_name': 'CodeCrafters', 'project_title': '', 'project_kind': 'project',
                'group_key': 'source/0', 'level': '3rd Year Capstone', 'year_level': '3rd Year',
                'section': 'BSIT-3D', 'member_ids': ['MATABALAN, Johnley L.', self.student_2.username],
                'leader_id': 'MATABALAN, Johnley L.', 'adviser_name': self.adviser.username}

    def test_expanded_middle_and_known_surname_separator_preview_and_commit(self):
        row = self.row()
        self.student_1.first_name, self.student_1.last_name = 'MERNEL ANTIO', 'CATADA'
        self.student_2.first_name, self.student_2.last_name = 'LENYVIE T', 'PAUYON'
        for student in (self.student_1, self.student_2):
            student.save(update_fields=['first_name', 'last_name'])
        row['member_ids'] = ['CATADA, Mernel A.', 'PAUYON. Lenyvie T.']
        row['leader_id'] = row['member_ids'][0]
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        preview = response.data['rows'][0]
        self.assertTrue(preview['ready'], preview)
        self.assertEqual([r['match_kind'] for r in preview['reference_resolutions'][:2]],
                         ['middle_initial_expanded', 'surname_separator'])
        self.assertFalse(StudentTeam.objects.exists())
        response = self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(StudentTeam.objects.get().leader_id, self.student_1.pk)
        self.student_1.refresh_from_db()
        self.assertEqual(self.student_1.first_name, 'MERNEL ANTIO')

    def test_damaged_registered_name_blocks_name_match_but_selected_id_warns(self):
        row = self.row()
        self.student_1.last_name = 'QUI\ufffdON'
        self.student_1.save(update_fields=['last_name'])
        row['member_ids'][0] = row['leader_id'] = 'QUI\u00d1ON, Johnley L.'
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        preview = response.data['rows'][0]
        self.assertFalse(preview['ready'])
        self.assertEqual(preview['reference_resolutions'][0]['status'], 'encoding_problem')
        self.assertEqual(sum('encoding problem' in error for error in preview['issues']), 1)
        row['member_ids'][0] = row['leader_id'] = self.student_1.username
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        preview = response.data['rows'][0]
        self.assertTrue(preview['ready'], preview)
        self.assertIn('Account name needs repair', ' '.join(preview['warnings']))
        response = self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.student_1.refresh_from_db()
        self.assertEqual(self.student_1.last_name, 'QUI\ufffdON')

    def test_reported_student_preview_and_commit_use_same_identity_without_preview_writes(self):
        row = self.row()
        before = list(StudentAcademicRecord.objects.values_list('pk', 'section'))
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        preview = response.data['rows'][0]
        self.assertTrue(preview['ready'], preview)
        self.assertFalse(StudentTeam.objects.exists())
        self.assertEqual(list(StudentAcademicRecord.objects.values_list('pk', 'section')), before)
        self.assertEqual(preview['reference_resolutions'][0]['username'], self.student_1.username)
        response = self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        team = StudentTeam.objects.get(name='CodeCrafters')
        self.assertEqual(team.leader_id, self.student_1.pk)
        self.assertEqual(set(team.memberships.values_list('student_id', flat=True)),
                         {self.student_1.pk, self.student_2.pk})

    def test_unique_missing_middle_initial_previews_and_commits(self):
        row = self.row()
        self.adviser.first_name, self.adviser.last_name = 'GINBERT', 'FERNANDEZ'
        self.adviser.save(update_fields=['first_name', 'last_name'])
        row['adviser_name'] = 'GINBERT A. FERNANDEZ'
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        preview = response.data['rows'][0]
        self.assertTrue(preview['ready'], preview)
        self.assertEqual(preview['reference_resolutions'][-1]['match_kind'], 'omitted_initial')
        response = self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(StudentTeam.objects.get().adviser_id, self.adviser.pk)

    def test_conflicting_middle_initial_requires_selection_then_registered_id_commits(self):
        row = self.row()
        self.adviser.first_name, self.adviser.last_name = 'GINBERT B', 'FERNANDEZ'
        self.adviser.save(update_fields=['first_name', 'last_name'])
        row['adviser_name'] = 'GINBERT A. FERNANDEZ'
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        preview = response.data['rows'][0]
        self.assertFalse(preview['ready'])
        self.assertIn('middle initials conflict', ' '.join(preview['issues']))
        self.assertEqual(preview['reference_resolutions'][-1]['status'], 'selection_required')
        self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertFalse(StudentTeam.objects.exists())
        row['adviser_name'] = self.adviser.username
        response = self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(StudentTeam.objects.get().adviser_id, self.adviser.pk)

    def test_legacy_client_edgar_account_previews_and_commits_without_name_writes(self):
        row = self.row()
        self.student_1.first_name, self.student_1.last_name = 'EDGAR, JR C', 'TAC-AN'
        self.student_1.save(update_fields=['first_name', 'last_name'])
        row['member_ids'][0] = row['leader_id'] = 'TAC-AN, Edgar Jr. C.'
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        self.assertTrue(response.data['rows'][0]['ready'], response.data)
        response = self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(StudentTeam.objects.get().leader_id, self.student_1.pk)
        self.student_1.refresh_from_db()
        self.assertEqual(self.student_1.first_name, 'EDGAR, JR C')

    def test_wrong_section_reports_scope_error_after_name_resolves(self):
        row = self.row()
        row['section'] = 'BSIT-4D'
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        preview = response.data['rows'][0]
        self.assertFalse(preview['ready'])
        self.assertIn('matching section', ' '.join(preview['issues']))
        self.assertNotIn('no user found', ' '.join(preview['issues']))

    def test_same_student_as_name_and_id_is_blocked(self):
        row = self.row()
        original = list(row['member_ids'])
        for duplicate in (self.student_1.username, original[0]):
            row['member_ids'] = original + [duplicate]
            response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
            self.assertFalse(response.data['rows'][0]['ready'])
            self.assertIn('more than once', ' '.join(response.data['rows'][0]['issues']))

    def test_commit_rechecks_a_preview_after_account_is_inactive_or_name_becomes_ambiguous(self):
        row = self.row()
        response = self.client.post('/api/teams/bulk-import/preview/', {'teams': [row]}, format='json')
        self.assertTrue(response.data['rows'][0]['ready'])
        self.student_1.is_active = False
        self.student_1.save(update_fields=['is_active'])
        self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertFalse(StudentTeam.objects.exists())
        self.student_1.is_active = True
        self.student_1.save(update_fields=['is_active'])
        get_user_model().objects.create(username='duplicate', role='student',
            first_name='Johnley L.', last_name='Matabalan')
        self.client.post('/api/teams/bulk-import/', {'teams': [row]}, format='json')
        self.assertFalse(StudentTeam.objects.exists())


class RosterNameApiTests(APITestCase):
    setUp = roster_fixtures.TeamFormationTests.setUp

    def body(self):
        student = self.students[0]
        student.first_name, student.last_name = 'Johnley L', 'Matabalan'
        student.save(update_fields=['first_name', 'last_name'])
        self.lead.first_name, self.lead.last_name = 'Ginbert A', 'Fernandez'
        self.lead.save(update_fields=['first_name', 'last_name'])
        return {'workspace': 'instructor', 'year_level': '2nd Year', 'section': 'BSIT-2A',
                'operation': 'import', 'teams': [{'team_name': 'CodeCrafters', 'project_title': '',
                    'member_ids': ['MATABALAN, Johnley L.'], 'leader_id': 'MATABALAN, Johnley L.',
                    'instructor_name': 'FERNANDEZ, Ginbert A.',
                    'system_name': 'Campus Services', 'project_manager': 'MATABALAN, Johnley L.'}]}

    def test_instructor_preflight_and_signed_apply_share_student_instructor_manager_matching(self):
        body = self.body()
        result = self.client.post('/api/teams/rosters/preview/',
            {**body, 'validation_only': True}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertTrue(result.data['ready'], result.data)
        self.assertTrue(all(r['status'] == 'matched'
            for r in result.data['rows'][0]['reference_resolutions']))
        self.assertFalse(StudentTeam.objects.exists())
        reviewed = self.client.post('/api/teams/rosters/preview/', body, format='json')
        self.assertEqual(reviewed.status_code, 200, reviewed.data)
        result = self.client.post('/api/teams/rosters/apply/',
            {'preview_token': reviewed.data['preview_token']}, format='json')
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(StudentTeam.objects.get().leader_id, self.students[0].pk)

    def test_correction_options_include_only_active_students_in_selected_scope_or_unassigned(self):
        StudentAcademicRecord.objects.filter(student=self.students[1]).update(section='')
        StudentAcademicRecord.objects.filter(student=self.students[2]).update(section='BSIT')
        self.students[3].is_active = False
        self.students[3].save(update_fields=['is_active'])
        result = self.client.get('/api/teams/rosters/', {
            'workspace': 'instructor', 'year_level': '2nd Year', 'section': 'BSIT-2A'})
        self.assertEqual(result.status_code, 200, result.data)
        usernames = {option['username'] for option in result.data['student_options']}
        self.assertTrue({self.students[0].username, self.students[1].username,
                         self.students[2].username}.issubset(usernames))
        self.assertNotIn(self.students[3].username, usernames)
        self.assertNotIn(self.students[10].username, usernames)

    def test_invalid_member_list_returns_review_issue_without_crashing_metadata(self):
        body = self.body()
        body['teams'][0]['member_ids'] = None
        result = self.client.post('/api/teams/rosters/preview/',
            {**body, 'validation_only': True}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertFalse(result.data['ready'])
