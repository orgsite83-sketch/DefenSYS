"""Default inheritance, explicit exceptions, and preservation of event history."""
from copy import deepcopy
from rest_framework.test import APITestCase
from defense.scheduler.models import PitEventGradingConfig
from defense.scheduler.event_scope import pit_events_for_team
from repository.deliverables import concepts
from . import test_formation as fixtures
from .models import StudentTeam, PITSectionRoster, PITEventRoster
from .pit_rosters import resolve, register, effective_ids


class PITRosterTests(APITestCase):
    setUp = fixtures.TeamFormationTests.setUp
    existing = fixtures.TeamFormationTests.existing

    def baseline(self, name='Current team', students=None, section='BSIT-2A'):
        team = self.existing(name=name, students=students)
        team.current_defense_stage = None
        team.section = section
        team.save()
        register([team], self.lead)
        return team

    def later(self):
        return PitEventGradingConfig.objects.create(semester=self.term,
            year_level='2nd Year', event_name='Later showcase', concept_config={'enabled': True, 'required_count': 3})

    def body(self, event=None, **changes):
        return {'level': '2nd Year PIT', 'section': 'BSIT-2A',
            **({'event_name': event.event_name, 'roster_override': True} if event else {}),
            'teams': [{'team_name': 'Imported team', 'section': 'BSIT-2A',
                'member_ids': [s.username for s in self.students[:3]], 'leader_id': self.students[0].username}], **changes}

    def preview_import(self, data):
        return self.client.post('/api/teams/generation/import/', data, format='json')

    def commit_import(self, preview):
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertTrue(preview.data['ready'], preview.data)
        return self.client.post('/api/teams/generation/import/create/',
            {'preview_token': preview.data['preview_token']}, format='json')

    def test_all_matching_events_inherit_without_assigning_or_creating_records(self):
        team = self.baseline()
        later = self.later()
        for event in (self.event, later):
            self.assertEqual(effective_ids(self.term.pk, '2nd Year', event), {team.pk})
        self.assertEqual(pit_events_for_team(team).count(), 2)
        self.assertFalse(PITEventRoster.objects.exists())

    def test_event_override_replaces_only_its_section_and_never_unions_defaults(self):
        original = self.baseline()
        other = self.baseline('Other section', self.students[10:13], 'BSIT-2B')
        later = self.later()
        result = self.commit_import(self.preview_import(self.body(later)))
        self.assertEqual(result.status_code, 201, result.data)
        imported = StudentTeam.objects.get(name='Imported team')
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', later), {imported.pk, other.pk})
        directory = self.client.get('/api/teams/', {'event_name': later.event_name})
        self.assertEqual({t['id'] for t in directory.data['teams']}, {imported.pk, other.pk})
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', self.event), {original.pk, other.pk})
        self.assertFalse(pit_events_for_team(original).filter(pk=later.pk).exists())
        replay = self.commit_import(self.preview_import({**self.body(later), 'teams': [{**self.body(later)['teams'][0], 'team_name': 'Replacement team'}]}))
        self.assertEqual(replay.status_code, 201, replay.data)
        self.assertEqual(StudentTeam.objects.count(), 4)
        self.assertNotIn(imported.pk, effective_ids(self.term.pk, '2nd Year', later))

    def test_instructor_cannot_replace_event_roster(self):
        self.baseline()
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        self.assertEqual(self.preview_import(self.body(self.later())).status_code, 403)

    def test_without_explicit_override_inherited_students_are_reserved(self):
        self.baseline()
        body = self.body(self.later())
        body.pop('roster_override')
        response = self.preview_import(body)
        self.assertFalse(response.data['ready'], response.data)

    def test_concept_work_pins_event_but_unused_events_follow_current_roster(self):
        team = self.baseline()
        later = self.later()
        concepts.save_titles(team, self.event,
            [{'key': f'c{i}', 'title': f'Proposal {i}'} for i in range(1, 4)], actor=self.lead)
        added = self.baseline('Added team', self.students[3:6])
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', self.event), {team.pk})
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', later), {team.pk, added.pk})
        self.assertTrue(PITEventRoster.objects.get(event=self.event).started_at)
        self.assertEqual(self.preview_import(self.body(self.event)).status_code, 400)

    def test_in_use_members_and_names_cannot_be_overwritten_by_import(self):
        team = self.baseline()
        concepts.save_titles(team, self.event,
            [{'key': f'c{i}', 'title': f'Proposal {i}'} for i in range(1, 4)], actor=self.lead)
        data = self.body()
        data['teams'][0]['team_name'] = team.name
        data['teams'][0]['member_ids'] = [self.students[0].username]
        response = self.preview_import(data)
        self.assertFalse(response.data['ready'], response.data)
        self.assertEqual(team.members.count(), 3)

    def test_changed_current_roster_invalidates_signed_import_preview(self):
        self.baseline()
        preview = self.preview_import(self.body(self.later()))
        self.assertTrue(preview.data['ready'], preview.data)
        self.baseline('Added after preview', self.students[3:6])
        response = self.commit_import(preview)
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(StudentTeam.objects.filter(name='Imported team').exists())

    def test_preview_and_directory_get_do_not_create_roster_records(self):
        team = self.existing()
        response = self.client.get('/api/teams/', {'roster_view': 'current'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([t['id'] for t in response.data['teams']], [team.pk])
        self.assertFalse(PITSectionRoster.objects.exists())
        self.assertFalse(PITEventRoster.objects.exists())

    def test_ambiguous_legacy_rosters_need_lead_selection_and_reject_overlap(self):
        first = self.existing(name='Earlier', event='Earlier event')
        second = self.existing(name='Later', event=self.event.event_name)
        self.assertTrue(resolve(self.term.pk, '2nd Year')['BSIT-2A']['needs_selection'])
        body = {'year_level': '2nd Year', 'section': 'BSIT-2A', 'team_ids': [first.pk, second.pk]}
        self.assertEqual(self.client.post('/api/teams/current-roster/', body, format='json').status_code, 400)
        body['team_ids'] = [second.pk]
        result = self.client.post('/api/teams/current-roster/', body, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(effective_ids(self.term.pk, '2nd Year'), {second.pk})

    def test_assigned_titles_are_preserved_and_shared_conversion_requires_resolution(self):
        body = self.body()
        body['teams'][0]['project_title'] = 'Existing assigned project'
        preview = self.preview_import(body)
        result = self.commit_import(preview)
        self.assertEqual(result.status_code, 201, result.data)
        team = StudentTeam.objects.get(name='Imported team')
        self.assertEqual(team.project_title, 'Existing assigned project')
        self.assertEqual(team.concept_assignment['mode'], 'assigned')
        body['project_setups'] = {'BSIT-2A': {'architecture': 'shared',
            'project_manager_id': self.students[0].pk, 'stage_label': self.event.event_name}}
        self.assertEqual(self.preview_import(body).status_code, 400)

    def test_default_import_is_repeatable_and_independent_ready_rows_can_import(self):
        body = self.body(partial=True)
        body['teams'].append({'team_name': 'Missing students', 'section': 'BSIT-2B',
            'member_ids': ['missing'], 'leader_id': 'missing'})
        preview = self.preview_import(body)
        first = self.commit_import(preview)
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(first.data['created_count'], 1)
        self.assertEqual(first.data['skipped_count'], 1)
        second = self.commit_import(preview)
        self.assertEqual(first.data, second.data)
        self.assertEqual(StudentTeam.objects.count(), 1)

    def test_shared_section_with_blocked_row_is_atomic(self):
        body = self.body(partial=True)
        body['teams'].append({'team_name': 'Missing team', 'section': 'BSIT-2A',
            'member_ids': ['missing'], 'leader_id': 'missing'})
        body['project_setups'] = {'BSIT-2A': {'architecture': 'shared',
            'project_manager_id': self.students[0].pk, 'stage_label': self.event.event_name}}
        response = self.preview_import(body)
        self.assertFalse(response.data['ready'], response.data)
        self.assertFalse(StudentTeam.objects.exists())

    def test_endorsements_are_independent_for_events_using_the_same_roster(self):
        from unittest.mock import patch
        from repository.deliverables.services import endorse_team, unendorse_team
        from .pit_rosters import endorsed
        self.event.concept_config = {}
        self.event.save()
        later = self.later()
        later.concept_config = {}
        later.save()
        team = self.baseline()
        with patch('repository.deliverables.services.stage_deliverables_configured', return_value=True), \
                patch('repository.deliverables.services.required_complete', return_value=True):
            endorse_team(team, self.event.event_name, self.lead)
            endorse_team(team, later.event_name, self.lead)
        self.assertTrue(endorsed(team, self.event.event_name))
        self.assertTrue(endorsed(team, later.event_name))
        unendorse_team(team, self.event.event_name)
        self.assertFalse(endorsed(team, self.event.event_name))
        self.assertTrue(endorsed(team, later.event_name))

    def test_shared_import_explicitly_resolves_assigned_titles_with_setup_in_one_save(self):
        from repository.section_concepts.models import SectionConceptProject
        body = self.body()
        body['teams'][0]['project_title'] = 'Previously assigned project'
        body['project_setups'] = {'BSIT-2A': {'architecture': 'shared', 'replace_assigned_titles': True,
            'project_manager_id': self.students[0].pk, 'stage_label': self.event.event_name}}
        preview = self.preview_import(body)
        self.assertIn('replaced', ' '.join(preview.data['rows'][0]['warnings']))
        response = self.commit_import(preview)
        self.assertEqual(response.status_code, 201, response.data)
        team = StudentTeam.objects.get(name='Imported team')
        self.assertEqual(team.project_title, '')
        self.assertEqual(team.concept_assignment['mode'], 'proposals')
        project = SectionConceptProject.objects.get()
        self.assertEqual(project.reviewer_id, self.lead.pk)
        self.assertEqual(project.team_links.get().team_id, team.pk)

    def test_partial_import_cannot_choose_one_of_two_overlapping_rows_silently(self):
        body = self.body(partial=True)
        body['teams'].append({**body['teams'][0], 'team_name': 'Overlapping team'})
        response = self.preview_import(body)
        self.assertFalse(response.data['ready'], response.data)
        self.assertTrue(all(not r['ready'] for r in response.data['rows']))

    def test_legacy_endorsement_survives_endorsement_of_another_event(self):
        from .pit_rosters import set_endorsed, endorsed
        self.event.concept_config = {}
        self.event.save()
        later = self.later()
        later.concept_config = {}
        later.save()
        team = self.baseline()
        team.ready_for_stage = self.event.event_name
        team.save(update_fields=['ready_for_stage'])
        set_endorsed(team, later.event_name, True, self.lead)
        team.ready_for_stage = later.event_name
        team.save(update_fields=['ready_for_stage'])
        self.assertTrue(endorsed(team, self.event.event_name))
        self.assertTrue(endorsed(team, later.event_name))

    def test_event_override_materializes_the_legacy_current_roster_before_adding_overlapping_teams(self):
        team = self.existing(event=self.event.event_name)
        later = self.later()
        response = self.commit_import(self.preview_import(self.body(later)))
        self.assertEqual(response.status_code, 201, response.data)
        current = resolve(self.term.pk, '2nd Year')['BSIT-2A']
        self.assertFalse(current['needs_selection'])
        self.assertEqual(current['team_ids'], [team.pk])
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', self.event), {team.pk})
