from copy import deepcopy
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventGradingConfig
from user_management.models import SectionInstructorAssignment
from user_management.academic_records.models import StudentAcademicRecord
from .models import StudentTeam, TeamMembership

User = get_user_model()


class FormationWorkspaceTests(APITestCase):
    def setUp(self):
        self.term = Semester.objects.create(school_year=SchoolYear.objects.create(label='2026-2027'),
            label=Semester.FIRST, is_active=True)
        self.admin = User.objects.create_user(username='workspace-admin', role='admin')
        self.lead = User.objects.create_user(username='workspace-lead', role='faculty',
            is_pit_lead=True, pit_lead_year='2nd Year')
        self.instructor = User.objects.create_user(username='workspace-instructor', role='faculty')
        self.adviser = User.objects.create_user(username='workspace-adviser', role='faculty', is_adviser=True)
        SectionInstructorAssignment.objects.create(faculty=self.instructor, semester=self.term,
            year_level='2nd Year', section='BSIT-2A', assigned_by=self.lead)
        self.event = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year', event_name='Workspace Design')
        self.students = []
        for index, section in enumerate(['', 'BSIT', 'BSIT-2A', 'BSIT-2B']):
            student = User.objects.create_user(username=f'workspace-{index}', role='student',
                first_name=f'Student {index}', email=f'original{index}@example.test', password='test-only')
            StudentAcademicRecord.objects.create(student=student, semester=self.term, year_level='2nd Year', section=section)
            self.students.append(student)
        self.client.force_authenticate(self.instructor)
        self.context = {'level': '2nd Year PIT', 'event_name': self.event.event_name}

    def post(self, endpoint, data):
        return self.client.post(f'/api/teams/generation/{endpoint}/', data, format='json')

    def roster(self, student=0, section='BSIT-2A', **extra):
        return self.post('roster', {**self.context, 'section': section,
            'students': [{'id_number': self.students[student].username, 'first_name': 'Do not replace', 'email': 'do-not-replace@example.test'}], **extra})

    def team_data(self, members=None):
        members = self.students[:2] if members is None else members
        return {**self.context, 'section': 'BSIT-2A', 'teams': [{
            'team_name': 'Workspace Team', 'member_ids': [s.username for s in members],
            'leader_id': members[0].username, 'section': 'BSIT-2A'}]}

    def commit(self, endpoint, preview):
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertTrue(preview.data['ready'], preview.data)
        return self.post(f'{endpoint}/create', {'preview_token': preview.data['preview_token']})

    def test_instructor_sees_assigned_empty_section_and_events_before_teams_exist(self):
        context = self.client.get('/api/teams/generation/context/')
        self.assertEqual(context.status_code, 200, context.data)
        self.assertEqual(context.data['levels'], ['2nd Year PIT'])
        self.assertEqual(context.data['events'][0]['event_name'], self.event.event_name)
        StudentAcademicRecord.objects.filter(student=self.students[2]).update(section='')
        response = self.client.get('/api/teams/generation/', self.context)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['sections'], [{'name': 'BSIT-2A', 'eligible_count': 0, 'total_count': 0}])
        self.assertFalse(response.data['can_manage_policy'])

    def test_roster_import_preserves_identity_and_credentials_and_is_repeatable(self):
        original = User.objects.get(pk=self.students[0].pk)
        preview = self.roster()
        result = self.commit('roster', preview)
        self.assertEqual(result.status_code, 200, result.data)
        user = User.objects.get(pk=original.pk)
        self.assertEqual((user.password, user.email, user.first_name), (original.password, original.email, original.first_name))
        self.assertEqual(StudentAcademicRecord.objects.get(student=user, semester=self.term).section, 'BSIT-2A')
        replay = self.commit('roster', preview)
        self.assertEqual(replay.status_code, 200)
        self.assertEqual(StudentAcademicRecord.objects.filter(student=user, semester=self.term).count(), 1)
        next_preview = self.roster()
        self.assertEqual(next_preview.data['rows'][0]['action'], 'unchanged')

    def test_missing_account_is_reported_and_not_created(self):
        response = self.post('roster', {**self.context, 'section': 'BSIT-2A', 'students': [{'id_number': 'missing-student'}]})
        self.assertFalse(response.data['ready'])
        self.assertFalse(User.objects.filter(username='missing-student').exists())

    def test_instructor_cannot_claim_section_or_reassign_other_sections(self):
        self.assertEqual(self.roster(section='BSIT-2B').status_code, 403)
        self.assertFalse(self.roster(student=3, resolve_conflicts=True).data['ready'])
        self.assertEqual(SectionInstructorAssignment.objects.filter(faculty=self.instructor).count(), 1)

    def test_lead_explicitly_reviews_section_conflicts(self):
        self.client.force_authenticate(self.lead)
        self.assertFalse(self.roster(student=3).data['ready'])
        result = self.commit('roster', self.roster(student=3, resolve_conflicts=True))
        self.assertEqual(result.status_code, 200, result.data)

    def test_changed_roster_or_other_actor_invalidates_preview(self):
        preview = self.roster()
        StudentAcademicRecord.objects.filter(student=self.students[0]).update(section='BSIT-2B')
        self.assertEqual(self.post('roster/create', {'preview_token': preview.data['preview_token']}).status_code, 400)
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.post('roster/create', {'preview_token': preview.data['preview_token']}).status_code, 400)

    def test_adviser_alone_cannot_import_or_generate(self):
        # Historical Capstone instructor rows must not revive a removed role.
        SectionInstructorAssignment.objects.create(faculty=self.adviser, semester=self.term,
            year_level='4th Year', section='BSIT-4A')
        self.client.force_authenticate(self.adviser)
        self.assertEqual(self.client.get('/api/teams/generation/context/').status_code, 403)
        self.assertEqual(self.roster().status_code, 403)
        self.assertEqual(self.post('import', {'level': '4th Year Capstone', 'teams': []}).status_code, 403)

    def test_prepared_import_creates_teams_and_sections_in_one_operation(self):
        preview = self.post('import', self.team_data())
        result = self.commit('import', preview)
        self.assertEqual(result.status_code, 201, result.data)
        team = StudentTeam.objects.get()
        self.assertTrue(team.project_pending)
        self.assertFalse(team.setup_pending)
        self.assertEqual(team.project_title, '')
        self.assertEqual(team.current_defense_stage, self.event.event_name)
        self.assertEqual(TeamMembership.objects.count(), 2)
        self.assertEqual(StudentAcademicRecord.objects.filter(student__in=self.students[:2], section='BSIT-2A').count(), 2)

    def test_managers_can_commit_prepared_imports_without_generation_permission(self):
        for index, actor in enumerate((self.admin, self.lead)):
            self.client.force_authenticate(actor)
            data = self.team_data(members=[self.students[index]])
            data['teams'][0]['team_name'] = f'Official roster {index}'
            result = self.commit('import', self.post('import', data))
            self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(StudentTeam.objects.count(), 2)

    def test_prepared_import_retry_and_reupload_do_not_duplicate_teams(self):
        preview = self.post('import', self.team_data())
        self.assertEqual(self.commit('import', preview).status_code, 201)
        self.assertEqual(self.commit('import', preview).status_code, 200)
        review = self.post('import', self.team_data())
        self.assertEqual(review.data['rows'][0]['action'], 'update', review.data)
        self.assertEqual(self.commit('import', review).status_code, 201)
        self.assertEqual(StudentTeam.objects.count(), 1)
        self.assertEqual(TeamMembership.objects.count(), 2)

    def test_import_cannot_assign_foreign_instructor_or_students(self):
        data = self.team_data()
        data['teams'][0]['instructor_name'] = self.lead.username
        self.assertFalse(self.post('import', data).data['ready'])
        self.assertFalse(self.post('import', self.team_data(self.students[3:])).data['ready'])

    def test_missing_enrollment_cannot_be_injected_by_prepared_import(self):
        StudentAcademicRecord.objects.filter(student=self.students[0]).delete()
        self.assertFalse(self.post('import', self.team_data()).data['ready'])

    def test_import_changes_after_preview_require_review(self):
        preview = self.post('import', self.team_data())
        StudentAcademicRecord.objects.filter(student=self.students[0]).update(section='BSIT-2B')
        self.assertEqual(self.post('import/create', {'preview_token': preview.data['preview_token']}).status_code, 400)
        self.assertFalse(StudentTeam.objects.exists())

    def test_instructor_can_generate_only_assigned_section_and_must_choose_leaders(self):
        data = {**self.context, 'sections': ['BSIT-2A'], 'method': 'alphabetical', 'group_size': 4, 'leader_method': 'manual'}
        preview = self.client.post('/api/teams/generation/', data, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertIsNone(preview.data['teams'][0]['leader_id'])
        self.assertEqual(self.post('create', {**data, **preview.data}).status_code, 400)
        preview.data['teams'][0]['leader_id'] = self.students[2].pk
        self.assertEqual(self.post('create', {**data, **preview.data}).status_code, 201)
        self.assertEqual(self.client.post('/api/teams/generation/', {**data, 'sections': ['BSIT-2B']}, format='json').status_code, 400)

    def test_generic_section_cannot_be_generated_as_a_whole_year(self):
        self.client.force_authenticate(self.lead)
        response = self.client.post('/api/teams/generation/', {**self.context, 'sections': ['BSIT'], 'method': 'random', 'group_size': 4}, format='json')
        self.assertEqual(response.status_code, 403)

    def test_custom_roster_is_limited_to_the_instructors_enrolled_section(self):
        data = {**self.context, 'sections': [], 'roster_mode': 'custom', 'student_ids': [s.pk for s in self.students],
                'method': 'random', 'group_size': 4}
        preview = self.client.post('/api/teams/generation/', data, format='json')
        self.assertEqual(preview.status_code, 400)
        data['student_ids'] = [self.students[2].pk]
        preview = self.client.post('/api/teams/generation/', data, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        result = self.post('create', {**data, **preview.data})
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(StudentTeam.objects.get().section, 'BSIT-2A')
        self.assertEqual(list(StudentAcademicRecord.objects.order_by('student_id').values_list('section', flat=True)), ['', 'BSIT', 'BSIT-2A', 'BSIT-2B'])

    def test_generation_retry_is_safe_under_multiple_membership_policy(self):
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        data = {**self.context, 'sections': ['BSIT-2A'], 'method': 'random', 'group_size': 4}
        preview = self.client.post('/api/teams/generation/', data, format='json')
        self.assertEqual(self.post('create', {**data, **preview.data}).status_code, 201)
        self.assertEqual(self.post('create', {**data, **preview.data}).status_code, 201)
        self.assertEqual(StudentTeam.objects.count(), 1)

    def test_policy_decision_stays_with_lead(self):
        response = self.client.patch(f'/api/teams/generation/events/{self.event.pk}/policy/',
            {'team_membership_policy': 'multiple'}, format='json')
        self.assertEqual(response.status_code, 403)

    def test_roster_can_be_prepared_without_an_event(self):
        self.event.delete()
        context = self.client.get('/api/teams/generation/', {'level': '2nd Year PIT'})
        self.assertEqual(context.status_code, 200, context.data)
        self.assertEqual(self.commit('roster', self.roster()).status_code, 200)

    def test_batch_overlap_is_reviewed_and_multiple_policy_remains_available(self):
        data = self.team_data()
        second = deepcopy(data['teams'][0])
        second['team_name'] = 'Second Workspace Team'
        data['teams'].append(second)
        self.assertFalse(self.post('import', data).data['ready'])
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        result = self.commit('import', self.post('import', data))
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(StudentTeam.objects.count(), 2)

    def test_additional_generation_is_explicit_and_does_not_hide_available_policy(self):
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        data = {**self.context, 'sections': ['BSIT-2A'], 'method': 'random', 'group_size': 4}
        preview = self.client.post('/api/teams/generation/', data, format='json')
        self.assertEqual(self.post('create', {**data, **preview.data}).status_code, 201)
        self.assertEqual(self.client.post('/api/teams/generation/', data, format='json').status_code, 400)
        data['include_assigned'] = True
        another = self.client.post('/api/teams/generation/', data, format='json')
        self.assertEqual(self.post('create', {**data, **another.data}).status_code, 201)
        self.assertEqual(StudentTeam.objects.count(), 2)
