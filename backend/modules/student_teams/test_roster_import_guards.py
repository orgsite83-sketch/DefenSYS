"""Event-optional rosters cannot evade preview or commit membership checks."""
from copy import deepcopy
from rest_framework.test import APITestCase

from defense.scheduler.models import PitEventGradingConfig
from repository.deliverables import concepts
from repository.deliverables.models import ConceptRound
from .models import StudentTeam, TeamMembership
from . import test_formation as fixtures
from .serializers import StudentTeamWriteSerializer
from rest_framework.exceptions import ValidationError


class RosterImportGuardTests(APITestCase):
    setUp = fixtures.TeamFormationTests.setUp
    existing = fixtures.TeamFormationTests.existing

    def body(self, *, event=None, title='Imported assigned module'):
        return {**({'event_name': event} if event else {}),
            'csv_columns': ['team_name', 'project_title', 'member_ids', 'leader_id'],
            'teams': [{'team_name': 'Team Imported', 'project_title': title,
                'member_ids': [s.get_full_name() for s in self.students[:3]],
                'leader_id': self.students[0].get_full_name()}]}

    def preview(self, body):
        response = self.client.post('/api/teams/bulk-import/preview/', body, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def commit(self, body):
        return self.client.post('/api/teams/bulk-import/', body, format='json')

    def test_missing_event_cannot_duplicate_a_three_proposal_team(self):
        original = self.existing(event=self.event.event_name)
        concepts.save_titles(original, self.event,
            [{'key': f'c{i}', 'title': f'Original proposal {i}'} for i in range(1, 4)], actor=self.lead)
        before = deepcopy(ConceptRound.objects.get(team=original).concepts)
        preview = self.preview(self.body())
        self.assertFalse(preview['rows'][0]['ready'])
        self.assertIn('Previous team', ' '.join(preview['rows'][0]['issues']))
        self.assertIn('concept proposals', ' '.join(preview['rows'][0]['issues']))
        self.assertEqual(preview['rows'][0]['membership_conflicts'][0]['id'], original.pk)
        result = self.commit(self.body())
        self.assertEqual(result.data['created_count'], 0, result.data)
        self.assertEqual(StudentTeam.objects.count(), 1)
        self.assertEqual(ConceptRound.objects.get(team=original).concepts, before)

    def test_selected_event_cannot_duplicate_an_unassigned_roster(self):
        team = self.existing(event=self.event.event_name)
        team.current_defense_stage = None
        team.save(update_fields=['current_defense_stage'])
        self.assertFalse(self.preview(self.body(event=self.event.event_name))['rows'][0]['ready'])
        self.assertEqual(self.commit(self.body(event=self.event.event_name)).data['created_count'], 0)

    def test_distinct_event_inherits_until_lead_explicitly_replaces_its_roster(self):
        self.existing(event=self.event.event_name)
        later = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year',
            event_name='Later event', concept_config={'enabled': True, 'required_count': 2})
        body = self.body(event=later.event_name, title='')
        preview = self.preview(body)
        self.assertFalse(preview['rows'][0]['ready'], preview)
        self.assertEqual(preview['rows'][0]['concept_requirement']['required_count'], 2)
        result = self.commit(body)
        self.assertEqual(result.data['created_count'], 0, result.data)

    def test_multiple_team_event_requires_visible_overlap_warning(self):
        self.existing(event=self.event.event_name)
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        body = self.body(event=self.event.event_name)
        preview = self.preview(body)
        self.assertTrue(preview['rows'][0]['ready'], preview)
        self.assertIn('Previous team', ' '.join(preview['rows'][0]['warnings']))
        self.assertEqual(self.commit(body).data['created_count'], 1)

    def test_concept_submission_establishes_event_context_before_scheduling(self):
        team = self.existing(event=self.event.event_name)
        team.current_defense_stage = None
        team.save(update_fields=['current_defense_stage'])
        concepts.save_titles(team, self.event,
            [{'key': f'c{i}', 'title': f'Proposal {i}'} for i in range(1, 4)], actor=self.lead)
        later = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year',
            event_name='Another event', concept_config={'enabled': True, 'required_count': 3})
        self.assertFalse(self.preview(self.body(event=self.event.event_name))['rows'][0]['ready'])
        body = self.body(event=later.event_name)
        self.assertFalse(self.preview(body)['rows'][0]['ready'])
        self.assertEqual(self.commit(body).data['created_count'], 0)

    def test_unassigned_import_cannot_borrow_an_events_multiple_team_policy(self):
        self.existing(event=self.event.event_name)
        self.event.team_membership_policy = 'multiple'
        self.event.save(update_fields=['team_membership_policy'])
        self.assertFalse(self.preview(self.body())['rows'][0]['ready'])
        self.assertEqual(self.commit(self.body()).data['created_count'], 0)

    def test_both_rows_with_a_repeated_student_are_blocked_in_preview_and_direct_commit(self):
        body = self.body()
        body['teams'].append({**body['teams'][0], 'team_name': 'Renamed duplicate'})
        preview = self.preview(body)
        self.assertEqual(preview['summary']['ready'], 0)
        self.assertTrue(all(row.get('batch_conflict') for row in preview['rows']))
        result = self.commit(body)
        self.assertEqual(result.data['created_count'], 0, result.data)
        self.assertFalse(StudentTeam.objects.exists())

    def test_membership_is_rechecked_if_another_team_is_created_after_preview(self):
        body = self.body()
        self.assertTrue(self.preview(body)['rows'][0]['ready'])
        self.existing(event=self.event.event_name)
        self.assertEqual(self.commit(body).data['created_count'], 0)

    def test_generator_can_create_unassigned_rosters_without_an_event(self):
        self.event.delete()
        body = {**self.payload}
        body.pop('event_name')
        preview = self.client.post('/api/teams/generation/', body, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        result = self.client.post('/api/teams/generation/create/', {**body, **preview.data}, format='json')
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(StudentTeam.objects.count(), 5)
        self.assertTrue(all(t.current_defense_stage is None for t in StudentTeam.objects.all()))

    def test_generator_without_event_excludes_existing_event_rosters(self):
        self.existing(event=self.event.event_name)
        body = {**self.payload}
        body.pop('event_name')
        preview = self.client.post('/api/teams/generation/', body, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        selected = [sid for team in preview.data['teams'] for sid in team['member_ids']]
        self.assertFalse(set(selected).intersection(s.pk for s in self.students[:3]))

    def test_manual_creation_cannot_bypass_existing_teams_by_omitting_event(self):
        self.existing(event=self.event.event_name)
        response = self.client.post('/api/teams/', {
            'name': 'Manual duplicate', 'level': '2nd Year PIT', 'year_level': '2nd Year',
            'leader_id': self.students[0].pk, 'member_ids': [s.pk for s in self.students[:3]],
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(StudentTeam.objects.count(), 1)

    def test_save_rechecks_locked_members_after_successful_serializer_validation(self):
        serializer = StudentTeamWriteSerializer(data={
            'name': 'Racing roster', 'level': '2nd Year PIT', 'year_level': '2nd Year',
            'leader_id': self.students[0].pk, 'member_ids': [s.pk for s in self.students[:3]],
        }, context={'user': self.lead, 'assigned_by': self.lead})
        serializer.is_valid(raise_exception=True)
        self.existing(event=self.event.event_name)
        with self.assertRaises(ValidationError):
            serializer.save()
        self.assertEqual(StudentTeam.objects.count(), 1)
        self.assertEqual(TeamMembership.objects.count(), 3)
