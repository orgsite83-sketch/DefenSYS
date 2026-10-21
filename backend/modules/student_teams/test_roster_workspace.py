"""Roster changes run in the isolated Django test database only."""
from copy import deepcopy
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from defense.scheduler.models import PitEventGradingConfig
from repository.deliverables import concepts
from . import test_formation as fixtures
from .models import StudentTeam, PITSectionRoster, PITEventRoster, PITRosterTeamDetails
from .pit_rosters import register, effective_ids


class RosterWorkspaceTests(APITestCase):
    setUp = fixtures.TeamFormationTests.setUp
    existing = fixtures.TeamFormationTests.existing

    def baseline(self):
        team = self.existing(name='Current team')
        team.current_defense_stage = None
        team.save()
        register([team], self.lead)
        return team

    def later(self, **fields):
        return PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year',
            event_name='Later showcase', **fields)

    def body(self, **fields):
        return {'year_level': '2nd Year', 'section': 'BSIT-2A', **fields}

    def context(self, **fields):
        result = self.client.get('/api/teams/rosters/', self.body(**fields))
        self.assertEqual(result.status_code, 200, result.data)
        return result.data

    def preview(self, **fields):
        result = self.client.post('/api/teams/rosters/preview/', self.body(**fields), format='json')
        self.assertEqual(result.status_code, 200, result.data)
        return result.data

    def apply(self, preview):
        return self.client.post('/api/teams/rosters/apply/', {'preview_token': preview['preview_token']}, format='json')

    def request_setup(self, event, **fields):
        return self.client.post('/api/teams/rosters/project-setup/', self.body(event_id=event.pk,
            fingerprint=self.context()['fingerprint'], **fields), format='json')

    def test_reads_do_not_initialize_rosters_rounds_or_details(self):
        self.existing()
        self.later()
        self.context()
        self.assertFalse(PITSectionRoster.objects.exists())
        self.assertFalse(PITEventRoster.objects.exists())
        self.assertFalse(PITRosterTeamDetails.objects.exists())

    def test_instructor_replaces_own_section_and_lead_retains_access(self):
        old = self.baseline()
        later = self.later()
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        preview = self.preview(operation='generate', event_id=later.pk, group_size=4)
        self.assertEqual(StudentTeam.objects.count(), 1)
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(len(effective_ids(self.term.pk, '2nd Year', later)), 3)
        self.assertEqual(effective_ids(self.term.pk, '2nd Year'), {old.pk})
        old.refresh_from_db()
        self.assertEqual(old.members.count(), 3)

    def test_unassigned_inactive_other_year_and_capstone_sections_are_rejected(self):
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        for change in ({'section': 'BSIT-2C'}, {'year_level': '1st Year'}, {'year_level': '4th Year'}):
            result = self.client.post('/api/teams/rosters/preview/', self.body(operation='generate', **change), format='json')
            self.assertIn(result.status_code, (400, 403))
        self.lead.instructor_assignments.all().update(is_active=False) if hasattr(self.lead, 'instructor_assignments') else None
        self.client.force_authenticate(self.students[0])
        self.assertEqual(self.client.get('/api/teams/rosters/', self.body()).status_code, 403)

    def test_current_replacement_preserves_ongoing_completed_and_custom_events(self):
        original = self.baseline()
        later = self.later()
        concepts.save_titles(original, self.event,
            [{'key': f'c{i}', 'title': f'Original {i}'} for i in range(1, 4)], actor=self.lead)
        before = deepcopy(original.concept_rounds.get(pit_event_config=self.event).concepts)
        completed = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year',
            event_name='Completed without files', is_officially_complete=True)
        custom = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year', event_name='Custom future')
        binding = PITEventRoster.objects.create(event=custom, section='BSIT-2A', source='custom')
        binding.teams.add(original)
        preview = self.preview(operation='generate', group_size=4)
        self.assertIn(later.event_name, preview['affected_events'])
        self.assertIn(completed.event_name, preview['preserved_events'])
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        for event in (self.event, completed, custom):
            self.assertEqual(effective_ids(self.term.pk, '2nd Year', event), {original.pk})
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', later), set(result.data['team_ids']))
        self.assertEqual(original.concept_rounds.get(pit_event_config=self.event).concepts, before)
        self.assertTrue(PITEventRoster.objects.get(event=completed).started_at)

    def test_completed_event_can_be_copied_out_but_not_replaced(self):
        old = self.baseline()
        self.event.is_officially_complete = True
        self.event.save()
        denied = self.client.post('/api/teams/rosters/preview/', self.body(operation='generate', event_id=self.event.pk), format='json')
        self.assertEqual(denied.status_code, 400)
        preview = self.preview(operation='copy', source_event_id=self.event.pk)
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertNotIn(old.pk, result.data['team_ids'])
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', self.event), {old.pk})

    def test_changed_roster_and_first_event_activity_invalidate_preview(self):
        old = self.baseline()
        preview = self.preview(operation='generate', event_id=self.event.pk)
        concepts.save_titles(old, self.event,
            [{'key': f'c{i}', 'title': f'Original {i}'} for i in range(1, 4)], actor=self.lead)
        self.assertEqual(self.apply(preview).status_code, 400)
        self.assertEqual(StudentTeam.objects.count(), 1)

    def test_copy_import_and_generation_are_reviewed_and_retry_is_idempotent(self):
        self.baseline()
        later = self.later()
        preview = self.preview(operation='copy', event_id=later.pk)
        self.assertEqual(StudentTeam.objects.count(), 1)
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        again = self.apply(preview)
        self.assertEqual(again.status_code, 201, again.data)
        self.assertEqual(result.data['team_ids'], again.data['team_ids'])
        self.assertEqual(StudentTeam.objects.count(), 2)

    def test_import_rejects_cross_section_students_and_repeated_members(self):
        row = {'team_name': 'Imported', 'member_ids': [self.students[0].username, self.students[10].username],
            'leader_id': self.students[0].username}
        result = self.client.post('/api/teams/rosters/preview/', self.body(operation='import', teams=[row]), format='json')
        self.assertEqual(result.status_code, 403, result.data)
        row['member_ids'] = [self.students[0].username] * 2
        result = self.client.post('/api/teams/rosters/preview/', self.body(operation='import', teams=[row]), format='json')
        self.assertEqual(result.status_code, 400)
        self.assertFalse(StudentTeam.objects.exists())

    def test_open_setup_pins_roster_and_nonconcept_leader_confirms_event_details(self):
        old = self.baseline()
        later = self.later()
        result = self.request_setup(later, project_mode='continue')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertTrue(PITEventRoster.objects.get(event=later).started_at)
        self.client.force_authenticate(self.students[0])
        tasks = self.client.get('/api/teams/my-setup/').data['event_teams']
        self.assertEqual(len(tasks), 1)
        task = tasks[0]
        self.assertEqual(task['project_title'], 'Existing project')
        result = self.client.patch(f'/api/teams/{old.pk}/events/{later.pk}/setup/', {
            'revision': task['revision'], 'name': 'Name for this event', 'project_title': 'Declared event project'}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(result.data['event_teams'], [])
        old.refresh_from_db()
        self.assertEqual(old.name, 'Current team')
        self.assertEqual(old.project_title, 'Existing project')
        self.client.force_authenticate(self.lead)
        exported = self.client.get('/api/teams/rosters/export/', self.body(event_id=later.pk))
        self.assertEqual(exported.status_code, 200, exported.data)
        self.assertFalse(exported.data['draft'])
        self.assertEqual(exported.data['rows'][0][:2], ['Name for this event', 'Declared event project'])

    def test_nonleader_cannot_confirm_and_completed_event_closes_setup(self):
        old = self.baseline()
        later = self.later()
        self.assertEqual(self.request_setup(later).status_code, 200)
        detail = PITRosterTeamDetails.objects.get(team=old, event=later)
        self.client.force_authenticate(self.students[1])
        result = self.client.patch(f'/api/teams/{old.pk}/events/{later.pk}/setup/',
            {'revision': detail.revision, 'name': 'Wrong leader', 'project_title': 'Project'}, format='json')
        self.assertEqual(result.status_code, 403)
        later.is_officially_complete = True
        later.save()
        self.client.force_authenticate(self.students[0])
        self.assertEqual(self.client.patch(f'/api/teams/{old.pk}/events/{later.pk}/setup/', {}, format='json').status_code, 400)

    def test_new_concept_requirement_keeps_proposal_workflow_and_never_copies_approval(self):
        old = self.baseline()
        later = self.later(concept_config={'enabled': True, 'required_count': 2}, project_setup_policy='new')
        self.assertEqual(self.request_setup(later, project_mode='continue').status_code, 400)
        self.assertEqual(self.request_setup(later, project_mode='new').status_code, 200)
        self.client.force_authenticate(self.students[0])
        task = self.client.get('/api/teams/my-setup/').data['event_teams'][0]
        self.assertEqual(task['project_title'], '')
        self.assertEqual(task['concept_tasks'][0]['required_count'], 2)
        self.assertFalse(old.concept_rounds.filter(pit_event_config=later).exists())

    def test_export_is_scoped_draft_and_spreadsheet_formula_safe(self):
        team = self.baseline()
        team.name = '=HYPERLINK("sample")'
        team.save()
        later = self.later()
        exported = self.client.get('/api/teams/rosters/export/', self.body(event_id=later.pk))
        self.assertEqual(exported.status_code, 200)
        self.assertTrue(exported.data['draft'])
        self.assertIn("'=HYPERLINK", exported.data['csv'])
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        self.assertEqual(self.client.get('/api/teams/rosters/export/', self.body(section='BSIT-2C')).status_code, 403)

    def test_generated_team_registers_project_once_and_can_continue_in_next_event(self):
        self.apply(self.preview(operation='generate', group_size=4))
        event = self.later()
        self.assertEqual(self.request_setup(event, project_mode='continue').status_code, 200)
        team = StudentTeam.objects.get(pk=next(iter(effective_ids(self.term.pk, '2nd Year', event))))
        detail = PITRosterTeamDetails.objects.get(team=team, event=event)
        self.client.force_authenticate(team.leader)
        result = self.client.patch(f'/api/teams/{team.pk}/events/{event.pk}/setup/', {
            'revision': detail.revision, 'name': 'Confirmed team', 'project_title': 'Student declared project'}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        next_event = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year', event_name='Next event')
        self.client.force_authenticate(self.lead)
        self.assertEqual(self.request_setup(next_event, project_mode='continue').status_code, 200)
        continued = PITRosterTeamDetails.objects.get(team=team, event=next_event)
        self.assertEqual(continued.project_title, 'Student declared project')
        self.assertEqual(continued.team_id, team.pk)

    def test_title_correction_is_event_scoped_and_requires_leader_reconfirmation(self):
        original = self.baseline()
        later = self.later()
        self.request_setup(later)
        detail = PITRosterTeamDetails.objects.get(team=original, event=later)
        result = self.client.patch('/api/teams/rosters/project-setup/', self.body(event_id=later.pk,
            team_id=original.pk, revision=detail.revision, name='Correct event name', project_title='Correct title'), format='json')
        self.assertEqual(result.status_code, 200, result.data)
        detail.refresh_from_db()
        original.refresh_from_db()
        self.assertIsNone(detail.confirmed_at)
        self.assertEqual(detail.project_title, 'Correct title')
        self.assertEqual(original.project_title, 'Existing project')
        self.assertEqual(original.name, 'Current team')
        later.is_officially_complete = True
        later.save()
        self.assertEqual(self.client.patch('/api/teams/rosters/project-setup/', self.body(event_id=later.pk,
            team_id=original.pk, revision=detail.revision, name='Wrong', project_title='Wrong'), format='json').status_code, 400)

    def test_multirole_instructor_cannot_borrow_management_authority_in_other_year(self):
        from user_management.models import SectionInstructorAssignment
        SectionInstructorAssignment.objects.create(faculty=self.lead, semester=self.term,
            year_level='1st Year', section='BSIT-1A')
        denied = self.client.get('/api/teams/rosters/', {'year_level': '1st Year', 'section': 'BSIT-1A', 'workspace': 'operations'})
        self.assertEqual(denied.status_code, 403)
        allowed = self.client.get('/api/teams/rosters/', {'year_level': '1st Year', 'section': 'BSIT-1A', 'workspace': 'instructor'})
        self.assertEqual(allowed.status_code, 200, allowed.data)

    def test_completed_event_without_files_also_protects_legacy_team_mutation(self):
        old = self.baseline()
        self.event.is_officially_complete = True
        self.event.save()
        response = self.client.patch(f'/api/teams/{old.pk}/', {'name': 'Changed behind completed event'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        old.refresh_from_db()
        self.assertEqual(old.name, 'Current team')

    def test_explicit_current_copy_resolves_ambiguous_legacy_families(self):
        self.existing(name='Earlier team', event=self.event.event_name)
        later = self.later()
        self.existing(name='Later team', event=later.event_name)
        self.assertTrue(self.context()['rosters'][0]['needs_selection'])
        result = self.apply(self.preview(operation='copy', source_event_id=later.pk))
        self.assertEqual(result.status_code, 201, result.data)
        self.assertFalse(self.context()['rosters'][0]['needs_selection'])
