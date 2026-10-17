from copy import deepcopy
from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from rest_framework.exceptions import ValidationError

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventGradingConfig
from user_management.academic_records.models import StudentAcademicRecord
from .models import StudentTeam, TeamMembership

User = get_user_model()


class TeamFormationTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username='formation-admin', role='admin')
        self.lead = User.objects.create_user(username='formation-lead', role='faculty',
            is_pit_lead=True, pit_lead_year='2nd Year')
        self.term = Semester.objects.create(school_year=SchoolYear.objects.create(label='2026-2027'),
            label=Semester.FIRST, is_active=True)
        self.event = PitEventGradingConfig.objects.create(semester=self.term,
            event_name='PIT Design', year_level='2nd Year', concept_config={'enabled': True, 'required_count': 3})
        self.students = []
        for i in range(15):
            student = User.objects.create_user(username=f'formation-{i:02d}', role='student',
                first_name=f'Student {i}', last_name=f'Surname {i:02d}')
            StudentAcademicRecord.objects.create(student=student, semester=self.term,
                year_level='2nd Year', section='BSIT-2A' if i < 10 else 'BSIT-2B')
            self.students.append(student)
        self.client.force_authenticate(self.lead)
        self.payload = {'level': '2nd Year PIT', 'event_name': self.event.event_name,
                        'sections': ['BSIT-2A', 'BSIT-2B'], 'method': 'alphabetical', 'group_size': 4}

    def preview(self, **changes):
        return self.client.post('/api/teams/generation/', {**self.payload, **changes}, format='json')

    def commit(self, preview, **changes):
        return self.client.post('/api/teams/generation/create/',
            {**self.payload, **preview.data, **changes}, format='json')

    def existing(self, event=None, students=None, name='Previous team'):
        students = students or self.students[:3]
        team = StudentTeam.objects.create(name=name, semester=self.term,
            leader=students[0], level='2nd Year PIT', year_level='2nd Year', section='BSIT-2A',
            current_defense_stage=event or 'Previous event', project_title='Existing project')
        for student in students:
            TeamMembership.objects.create(team=team, student=student, is_leader=student == students[0])
        return team

    def test_preview_balances_each_section_and_does_not_write(self):
        response = self.preview()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(StudentTeam.objects.exists())
        groups = response.data['teams']
        self.assertEqual([len(g['member_ids']) for g in groups if g['section'] == 'BSIT-2A'], [4, 3, 3])
        self.assertEqual([len(g['member_ids']) for g in groups if g['section'] == 'BSIT-2B'], [3, 2])
        self.assertEqual(groups[0]['member_ids'], [s.pk for s in self.students[:4]])
        self.assertCountEqual([i for g in groups for i in g['member_ids']], [s.pk for s in self.students])

    def test_random_preview_assigns_every_student_once_with_a_member_leader(self):
        response = self.preview(method='random')
        self.assertEqual(response.status_code, 200)
        self.assertCountEqual([i for g in response.data['teams'] for i in g['member_ids']], [s.pk for s in self.students])
        for group in response.data['teams']:
            self.assertIn(group['leader_id'], group['member_ids'])

    def test_commit_creates_provisional_teams_and_accepts_reviewed_leaders(self):
        response = self.preview()
        response.data['teams'][0]['leader_id'] = response.data['teams'][0]['member_ids'][-1]
        result = self.commit(response)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(result.data['created_count'], 5)
        self.assertEqual(TeamMembership.objects.count(), 15)
        for team in StudentTeam.objects.all():
            self.assertTrue(team.setup_pending)
            self.assertTrue(team.project_pending)
            self.assertEqual(team.project_title, '')
            self.assertEqual(team.current_defense_stage, self.event.event_name)

    def test_students_and_wrong_cohort_leads_cannot_read_or_generate(self):
        self.client.force_authenticate(self.students[0])
        self.assertEqual(self.preview().status_code, 403)
        self.lead.pit_lead_year = '1st Year'
        self.lead.save(update_fields=['pit_lead_year'])
        self.client.force_authenticate(self.lead)
        self.assertEqual(self.preview().status_code, 403)

    def test_tampered_missing_and_duplicate_rosters_are_rejected(self):
        response = self.preview()
        for kind in ('missing', 'duplicate', 'cross_section'):
            groups = deepcopy(response.data['teams'])
            if kind == 'missing':
                groups[0]['member_ids'].pop()
            elif kind == 'duplicate':
                groups[1]['member_ids'][0] = groups[0]['member_ids'][0]
            else:
                groups[0]['member_ids'][0], groups[-1]['member_ids'][0] = groups[-1]['member_ids'][0], groups[0]['member_ids'][0]
            result = self.commit(response, teams=groups)
            self.assertEqual(result.status_code, 400, result.data)
            self.assertFalse(StudentTeam.objects.exists())

    def test_stale_roster_and_policy_require_a_new_preview(self):
        response = self.preview()
        self.existing(event=self.event.event_name)
        self.assertEqual(self.commit(response).status_code, 400)
        StudentTeam.objects.all().delete()
        response = self.preview()
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        self.assertEqual(self.commit(response).status_code, 400)

    def test_other_actor_cannot_use_preview(self):
        response = self.preview()
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.commit(response).status_code, 400)

    def test_invalid_later_group_rolls_back_every_team(self):
        response = self.preview()
        response.data['teams'][-1]['leader_id'] = self.students[0].pk
        self.assertEqual(self.commit(response).status_code, 400)
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(TeamMembership.objects.exists())

    def test_reuse_keeps_members_and_leaders_without_changing_source(self):
        source = self.existing()
        response = self.preview(method='reuse', source_team_ids=[source.pk])
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['teams'][0]['member_ids'], [s.pk for s in self.students[:3]])
        result = self.commit(response, method='reuse', source_team_ids=[source.pk])
        self.assertEqual(result.status_code, 201, result.data)
        source.refresh_from_db()
        self.assertEqual(source.current_defense_stage, 'Previous event')
        self.assertEqual(source.project_title, 'Existing project')
        self.assertEqual(source.members.count(), 3)

    def test_lead_can_allow_multiple_memberships_and_manual_creation_honors_setting(self):
        self.existing(event=self.event.event_name)
        manual = {'name': 'Second event team', 'level': '2nd Year PIT', 'year_level': '2nd Year',
            'leader_id': self.students[0].pk, 'member_ids': [self.students[0].pk],
            'current_defense_stage': self.event.event_name}
        self.assertEqual(self.client.post('/api/teams/', manual, format='json').status_code, 400)
        result = self.client.patch(f'/api/teams/generation/events/{self.event.pk}/policy/',
            {'team_membership_policy': 'multiple'}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(self.client.post('/api/teams/', manual, format='json').status_code, 201)
        result = self.client.patch(f'/api/teams/generation/events/{self.event.pk}/policy/',
            {'team_membership_policy': 'single'}, format='json')
        self.assertEqual(result.status_code, 400)
        self.event.refresh_from_db()
        self.assertEqual(self.event.team_membership_policy, 'multiple')

    def test_policy_setting_rejects_other_year_and_completed_event(self):
        other = PitEventGradingConfig.objects.create(semester=self.term, event_name='First year', year_level='1st Year')
        result = self.client.patch(f'/api/teams/generation/events/{other.pk}/policy/',
            {'team_membership_policy': 'multiple'}, format='json')
        self.assertEqual(result.status_code, 403)
        self.event.is_officially_complete = True
        self.event.save(update_fields=['is_officially_complete'])
        self.assertEqual(self.preview().status_code, 400)

    def test_options_availability_obeys_selected_event_policy(self):
        self.existing(event=self.event.event_name)
        url = f'/api/teams/generation/?level=2nd%20Year%20PIT&event_name={self.event.event_name}'
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(sum(s['eligible'] for s in response.data['students']), 12)
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        self.assertEqual(sum(s['eligible'] for s in self.client.get(url).data['students']), 15)

    def test_leader_setup_is_private_preserves_empty_project_and_uses_concept_count(self):
        self.assertEqual(self.commit(self.preview()).status_code, 201)
        team = StudentTeam.objects.get(leader=self.students[0])
        self.client.force_authenticate(self.students[1])
        self.assertEqual(self.client.patch(f'/api/teams/{team.pk}/setup/', {'name': 'Other'}, format='json').status_code, 404)
        self.client.force_authenticate(self.students[0])
        tasks = self.client.get('/api/teams/my-setup/').data['teams']
        self.assertEqual(tasks[0]['concept_tasks'][0]['required_count'], 3)
        result = self.client.patch(f'/api/teams/{team.pk}/setup/', {'name': 'Our chosen team'}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        team.refresh_from_db()
        self.assertFalse(team.setup_pending)
        self.assertEqual(team.project_title, '')
        team.save()
        team.refresh_from_db()
        self.assertEqual(team.project_title, '')
        self.assertEqual(result.data['teams'][0]['needs_name'], False)

    def test_audit_failure_rolls_back_generation(self):
        response = self.preview()
        with patch('student_teams.formation.log_high_impact_action', side_effect=ValidationError('Audit unavailable')):
            self.assertEqual(self.commit(response).status_code, 400)
        self.assertFalse(StudentTeam.objects.exists())

    def test_bulk_preview_and_import_follow_selected_event_policy(self):
        self.existing(event=self.event.event_name)
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        body = {'event_name': self.event.event_name,
                'csv_columns': ['team_name', 'member_ids', 'leader_id'],
                'teams': [{'team_name': 'Imported additional team',
                           'member_ids': [self.students[0].get_full_name()],
                           'leader_id': self.students[0].get_full_name()}]}
        preview = self.client.post('/api/teams/bulk-import/preview/', body, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual(preview.data['summary']['ready'], 1, preview.data)
        result = self.client.post('/api/teams/bulk-import/', body, format='json')
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(result.data['created_count'], 1, result.data)
        self.assertEqual(StudentTeam.objects.get(name='Imported additional team').current_defense_stage,
                         self.event.event_name)

    def test_student_dashboard_selects_only_owned_teams(self):
        first = self.existing(name='First roster')
        second = self.existing(event=self.event.event_name, name='Second roster')
        self.client.force_authenticate(self.students[0])
        response = self.client.get(f'/api/dashboards/student/?team_id={first.pk}')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['team']['id'], first.pk)
        self.assertCountEqual([t['id'] for t in response.data['team_options']], [first.pk, second.pk])
        outsider = self.existing(students=[self.students[5]], name='Private roster')
        self.assertEqual(self.client.get(f'/api/dashboards/student/?team_id={outsider.pk}').status_code, 404)
        self.assertEqual(self.client.get('/api/dashboards/student/?team_id=invalid').status_code, 400)

    def test_capstone_generation_obeys_intake_and_uses_existing_concept_policy(self):
        self.client.force_authenticate(self.admin)
        self.term.label = Semester.SECOND
        self.term.capstone_program_phase = Semester.PHASE_CAPSTONE_1
        self.term.capstone_team_creation_enabled = True
        self.term.save()
        StudentAcademicRecord.objects.all().update(year_level='3rd Year')
        response = self.preview(level='3rd Year Capstone')
        self.assertEqual(response.status_code, 200, response.data)
        result = self.commit(response, level='3rd Year Capstone')
        self.assertEqual(result.status_code, 201, result.data)
        self.assertTrue(StudentTeam.objects.filter(level='3rd Year Capstone').exists())
        self.term.capstone_team_creation_enabled = False
        self.term.save()
        self.assertEqual(self.preview(level='3rd Year Capstone').status_code, 400)

    def test_preview_expiry_and_signature_are_enforced(self):
        response = self.preview()
        self.assertEqual(self.commit(response, preview_token='altered').status_code, 400)
        with patch('student_teams.formation.signing.time.time', return_value=9999999999):
            self.assertEqual(self.commit(response).status_code, 400)
        self.assertFalse(StudentTeam.objects.exists())

    def test_multiple_policy_allows_generation_for_students_already_in_event(self):
        existing = self.existing(event=self.event.event_name)
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        response = self.preview()
        result = self.commit(response)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(TeamMembership.objects.filter(student=self.students[0]).count(), 2)
        self.assertEqual(existing.members.count(), 3)
