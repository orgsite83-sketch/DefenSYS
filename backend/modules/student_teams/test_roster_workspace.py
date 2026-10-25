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

    def test_unsectioned_cohort_opens_with_setup_guidance_without_writes(self):
        from user_management.academic_records.models import StudentAcademicRecord
        from user_management.models import SectionInstructorAssignment
        StudentAcademicRecord.objects.filter(semester=self.term).update(section='')
        SectionInstructorAssignment.objects.filter(semester=self.term).delete()
        for query in ({'year_level': '2nd Year'}, {}):
            response = self.client.get('/api/teams/rosters/', {**query, 'workspace': 'operations'})
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(response.data['year_level'], '2nd Year')
            self.assertIsNone(response.data['section'])
            self.assertEqual(response.data['scope_options'], [])
            self.assertEqual(response.data['rosters'], [])
            self.assertIsNone(response.data['fingerprint'])
            self.assertTrue(response.data['can_import_sections'])
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(PITSectionRoster.objects.exists())
        self.assertFalse(PITEventRoster.objects.exists())
        self.assertFalse(PITRosterTeamDetails.objects.exists())

        denied = self.client.post('/api/teams/rosters/preview/', {
            'year_level': '2nd Year', 'workspace': 'operations', 'operation': 'import', 'teams': [],
        }, format='json')
        self.assertEqual(denied.status_code, 400, denied.data)

        StudentAcademicRecord.objects.filter(semester=self.term).update(section='BSIT-2A')
        recovered = self.client.get('/api/teams/rosters/', {'year_level': '2nd Year', 'workspace': 'operations'})
        self.assertEqual(recovered.status_code, 200, recovered.data)
        self.assertEqual(recovered.data['section'], 'BSIT-2A')
        self.assertTrue(recovered.data['fingerprint'])
        self.assertEqual(len(recovered.data['rosters']), 2)

    def test_management_choices_include_configured_and_other_instructors_empty_sections(self):
        from user_management.academic_records.models import StudentAcademicRecord
        from user_management.models import SectionInstructorAssignment
        from .models import SectionAssignment
        StudentAcademicRecord.objects.filter(semester=self.term).update(section='')
        SectionInstructorAssignment.objects.filter(semester=self.term).delete()
        instructor = get_user_model().objects.create_user(username='empty-section-instructor', role='faculty')
        SectionInstructorAssignment.objects.create(faculty=instructor, semester=self.term,
            year_level='2nd Year', section='BSIT-2B')
        SectionInstructorAssignment.objects.create(faculty=instructor, semester=self.term,
            year_level='2nd Year', section='BSIT-2C', is_active=False)
        SectionAssignment.objects.create(semester=self.term, year_level='2nd Year', section='BSIT-2A')
        SectionAssignment.objects.create(semester=self.term, year_level='1st Year', section='BSIT-1A')

        response = self.client.get('/api/teams/rosters/', {'year_level': '2nd Year', 'workspace': 'operations'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['scope_options'], [
            {'year_level': '2nd Year', 'section': 'BSIT-2A'},
            {'year_level': '2nd Year', 'section': 'BSIT-2B'},
        ])
        self.assertFalse(response.data['can_generate'])

        self.client.force_authenticate(instructor)
        own = self.client.get('/api/teams/rosters/', {'workspace': 'instructor'})
        self.assertEqual(own.status_code, 200, own.data)
        self.assertEqual(own.data['scope_options'], [{'year_level': '2nd Year', 'section': 'BSIT-2B'}])
        self.assertFalse(own.data['can_import_sections'])

    def section_import(self, **fields):
        return self.body(operation='import', workspace='instructor', teams=[{
            'team_name': 'Imported section team', 'section': 'BSIT-2A',
            'member_ids': [s.username for s in self.students[:3]],
            'leader_id': self.students[0].username,
            'instructor_name': self.lead.username,
        }], **fields)

    def test_assigned_instructor_imports_unsectioned_students_without_class_list(self):
        from user_management.academic_records.models import StudentAcademicRecord
        from user_management.models import SectionInstructorAssignment
        from .models import SectionAssignment
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        StudentAcademicRecord.objects.filter(student=self.students[0], semester=self.term).update(section='')
        StudentAcademicRecord.objects.filter(student=self.students[1], semester=self.term).update(section='BSIT')
        body = self.section_import()
        body['teams'][0].update(system_name='Section System', project_manager=self.students[0].username)
        preview = self.client.post('/api/teams/rosters/preview/', body, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual(preview.data['section_assignment_count'], 2)
        self.assertFalse(StudentTeam.objects.exists())
        self.assertEqual(StudentAcademicRecord.objects.get(student=self.students[0], semester=self.term).section, '')
        result = self.apply(preview.data)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(StudentAcademicRecord.objects.filter(student__in=self.students[:3],
            semester=self.term, section='BSIT-2A').count(), 3)
        self.assertEqual(SectionAssignment.objects.get().project_manager, self.students[0])
        self.assertEqual(SectionInstructorAssignment.objects.count(), 2)
        repeated = self.apply(preview.data)
        self.assertEqual(repeated.data['team_ids'], result.data['team_ids'])
        self.assertEqual(StudentTeam.objects.count(), 1)

    def test_instructor_import_cannot_claim_other_sections_years_or_missing_enrollment(self):
        from user_management.academic_records.models import StudentAcademicRecord
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        record = StudentAcademicRecord.objects.get(student=self.students[0], semester=self.term)
        for year, section in (('2nd Year', 'BSIT-2C'), ('1st Year', '')):
            record.year_level, record.section = year, section
            record.save()
            response = self.client.post('/api/teams/rosters/preview/', self.section_import(), format='json')
            self.assertEqual(response.status_code, 403, response.data)
        record.delete()
        self.assertEqual(self.client.post('/api/teams/rosters/preview/', self.section_import(), format='json').status_code, 403)
        self.assertFalse(StudentTeam.objects.exists())

    def test_instructor_import_rechecks_assignment_and_unsectioned_enrollment_at_apply(self):
        from user_management.academic_records.models import StudentAcademicRecord
        from user_management.models import SectionInstructorAssignment
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        StudentAcademicRecord.objects.filter(student__in=self.students[:3], semester=self.term).update(section='')
        for change in ('assignment', 'enrollment'):
            with self.subTest(change=change):
                preview = self.client.post('/api/teams/rosters/preview/', self.section_import(), format='json')
                self.assertEqual(preview.status_code, 200, preview.data)
                if change == 'assignment':
                    SectionInstructorAssignment.objects.filter(faculty=self.lead, section='BSIT-2A').update(is_active=False)
                else:
                    StudentAcademicRecord.objects.filter(student=self.students[0], semester=self.term).update(section='BSIT-2C')
                denied = self.apply(preview.data)
                self.assertEqual(denied.status_code, 403, denied.data)
                self.assertFalse(StudentTeam.objects.exists())
                self.assertEqual(StudentAcademicRecord.objects.filter(student__in=self.students[1:3], section='').count(), 2)
                SectionInstructorAssignment.objects.filter(faculty=self.lead, section='BSIT-2A').update(is_active=True)

    def test_instructor_workspace_cannot_assign_another_instructor_even_for_a_lead(self):
        body = self.section_import()
        other = get_user_model().objects.create_user(username='foreign-section-instructor', role='faculty')
        body['teams'][0]['instructor_name'] = other.username
        result = self.client.post('/api/teams/rosters/preview/', body, format='json')
        self.assertEqual(result.status_code, 403, result.data)
        self.assertFalse(other.section_instructor_assignments.exists())
        self.assertFalse(StudentTeam.objects.exists())

    def test_lead_section_import_rechecks_and_saves_instructor_with_enrollment_atomically(self):
        from user_management.academic_records.models import StudentAcademicRecord
        from user_management.models import SectionInstructorAssignment
        other = get_user_model().objects.create_user(username='imported-section-instructor', role='faculty')
        StudentAcademicRecord.objects.filter(student__in=self.students[:3], semester=self.term).update(section='')
        body = self.section_import()
        body['workspace'] = 'operations'
        body['teams'][0]['instructor_name'] = other.username
        preview = self.client.post('/api/teams/rosters/preview/', body, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        other.is_active = False
        other.save(update_fields=['is_active'])
        failed = self.apply(preview.data)
        self.assertEqual(failed.status_code, 400, failed.data)
        self.assertFalse(StudentTeam.objects.exists())
        self.assertEqual(StudentAcademicRecord.objects.filter(student__in=self.students[:3], section='').count(), 3)
        other.is_active = True
        other.save(update_fields=['is_active'])
        refreshed = self.client.post('/api/teams/rosters/preview/', body, format='json')
        committed = self.apply(refreshed.data)
        self.assertEqual(committed.status_code, 201, committed.data)
        self.assertTrue(SectionInstructorAssignment.objects.filter(faculty=other,
            semester=self.term, year_level='2nd Year', section='BSIT-2A', is_active=True).exists())
        self.assertEqual(StudentAcademicRecord.objects.filter(student__in=self.students[:3], section='BSIT-2A').count(), 3)

    def test_empty_read_still_rejects_other_years_invalid_workspaces_and_capstone(self):
        from user_management.academic_records.models import StudentAcademicRecord
        from user_management.models import SectionInstructorAssignment
        StudentAcademicRecord.objects.filter(semester=self.term).update(section='')
        SectionInstructorAssignment.objects.filter(semester=self.term).delete()
        for query, status in (
            ({'year_level': '1st Year', 'workspace': 'operations'}, 403),
            ({'year_level': '2nd Year', 'workspace': 'invalid'}, 403),
            ({'year_level': '2nd Year', 'workspace': 'instructor'}, 403),
            ({'year_level': '4th Year', 'workspace': 'operations'}, 400),
        ):
            with self.subTest(query=query):
                response = self.client.get('/api/teams/rosters/', query)
                self.assertEqual(response.status_code, status, response.data)

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

    def test_generation_uses_exactly_the_confirmed_section_class_list(self):
        confirmed = [s.pk for s in self.students[:10]]
        preview = self.preview(operation='generate', confirmed_student_ids=confirmed, method='random')
        self.assertCountEqual(
            [student_id for team in preview['teams'] for student_id in team['member_ids']], confirmed)
        self.assertFalse(StudentTeam.objects.exists())

    def test_first_event_generation_sets_current_and_event_to_the_same_teams(self):
        later = self.later()
        preview = self.preview(operation='generate', event_id=self.event.pk, workspace='instructor')
        self.assertTrue(preview['initializes_current'])
        self.assertCountEqual(preview['affected_events'], [self.event.event_name, later.event_name])
        self.assertFalse(PITSectionRoster.objects.exists())
        self.assertFalse(StudentTeam.objects.exists())

        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        ids = set(result.data['team_ids'])
        self.assertTrue(result.data['initializes_current'])
        for event in (None, self.event, later):
            self.assertEqual(effective_ids(self.term.pk, '2nd Year', event), ids)
        self.assertEqual(StudentTeam.objects.count(), len(ids))
        self.assertEqual(sum(t.members.count() for t in StudentTeam.objects.all()), 10)
        self.assertTrue(all(t.setup_pending and t.project_pending for t in StudentTeam.objects.all()))
        current, selected, _ = self.context()['rosters']
        self.assertEqual({t['id'] for t in current['teams']}, ids)
        self.assertEqual({t['id'] for t in selected['teams']}, ids)
        self.assertEqual(self.apply(preview).data, result.data)
        self.assertEqual(StudentTeam.objects.count(), len(ids))

    def test_event_generation_fills_saved_empty_current_and_preserves_other_event_rosters(self):
        completed = self.later(is_officially_complete=True)
        old = self.existing(event=completed.event_name)
        PITSectionRoster.objects.create(semester=self.term, year_level='2nd Year', section='BSIT-2A')
        custom = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year',
            event_name='Custom future')
        binding = PITEventRoster.objects.create(event=custom, section='BSIT-2A', source='custom')
        binding.teams.add(old)

        preview = self.preview(operation='generate', event_id=self.event.pk)
        self.assertTrue(preview['initializes_current'])
        self.assertCountEqual(preview['preserved_events'], [completed.event_name, custom.event_name])
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        ids = set(result.data['team_ids'])
        self.assertEqual(effective_ids(self.term.pk, '2nd Year'), ids)
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', self.event), ids)
        for event in (completed, custom):
            self.assertEqual(effective_ids(self.term.pk, '2nd Year', event), {old.pk})
        old.refresh_from_db()
        self.assertEqual(old.members.count(), 3)
        self.assertEqual(old.project_title, 'Existing project')

    def test_event_generation_keeps_an_existing_current_roster(self):
        old = self.baseline()
        preview = self.preview(operation='generate', event_id=self.event.pk)
        self.assertFalse(preview['initializes_current'])
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertFalse(result.data['initializes_current'])
        self.assertEqual(effective_ids(self.term.pk, '2nd Year'), {old.pk})
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', self.event), set(result.data['team_ids']))

    def test_first_event_generation_rejects_a_current_roster_added_after_review(self):
        preview = self.preview(operation='generate', event_id=self.event.pk)
        old = self.baseline()
        result = self.apply(preview)
        self.assertEqual(result.status_code, 400, result.data)
        self.assertEqual(effective_ids(self.term.pk, '2nd Year'), {old.pk})
        self.assertEqual(StudentTeam.objects.count(), 1)

    def test_generation_rejects_stale_or_invalid_student_confirmation(self):
        confirmed = [s.pk for s in self.students[:10]]
        for ids in ([], confirmed[:-1], confirmed + [self.students[10].pk],
                    confirmed + [confirmed[0]], None, ['invalid']):
            with self.subTest(ids=ids):
                response = self.client.post('/api/teams/rosters/preview/',
                    self.body(operation='generate', confirmed_student_ids=ids), format='json')
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('confirm it again', str(response.data))
        self.assertFalse(StudentTeam.objects.exists())

    def test_use_existing_event_as_current_reuses_identities_and_retires_unused_copy(self):
        generated = self.apply(self.preview(operation='generate', event_id=self.event.pk))
        original_ids = set(generated.data['team_ids'])
        copied = self.apply(self.preview(operation='copy', source_event_id=self.event.pk))
        self.assertEqual(copied.status_code, 201, copied.data)
        copied_ids = set(copied.data['team_ids'])
        self.assertTrue(original_ids.isdisjoint(copied_ids))
        before = StudentTeam.objects.count()
        review = self.preview(operation='reuse', source_event_id=self.event.pk)
        self.assertTrue(review['reuses_teams'])
        result = self.apply(review)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(result.data['created_count'], 0)
        self.assertEqual(result.data['reused_count'], len(original_ids))
        self.assertEqual(StudentTeam.objects.count(), before)
        self.assertEqual(effective_ids(self.term.pk, '2nd Year'), original_ids)
        self.assertEqual(effective_ids(self.term.pk, '2nd Year', self.event), original_ids)
        self.client.force_authenticate(self.students[0])
        dashboard = self.client.get('/api/dashboards/student/')
        self.assertEqual(dashboard.status_code, 200, dashboard.data)
        self.assertIn(dashboard.data['team']['id'], original_ids)
        tasks = self.client.get('/api/teams/my-setup/').data
        self.assertFalse({t['id'] for t in tasks['teams']}.intersection(copied_ids))

    def test_old_event_confirmation_cannot_overwrite_current_details_source(self):
        team = self.baseline()
        older = self.later()
        newer = PitEventGradingConfig.objects.create(semester=self.term, year_level='2nd Year', event_name='New project event')
        self.assertEqual(self.request_setup(older).status_code, 200)
        self.assertEqual(self.request_setup(newer).status_code, 200)
        self.client.force_authenticate(team.leader)
        for event, name, title in ((newer, 'ByteCraft', 'New project'), (older, 'Old event name', 'Old project')):
            detail = PITRosterTeamDetails.objects.get(team=team, event=event)
            response = self.client.patch(f'/api/teams/{team.pk}/events/{event.pk}/setup/', {
                'revision': detail.revision, 'name': name, 'project_title': title}, format='json')
            self.assertEqual(response.status_code, 200, response.data)
        profile = PITRosterTeamDetails.objects.get(team=team, event=None)
        self.assertEqual(profile.details_source_event_id, newer.pk)
        self.assertEqual((profile.name, profile.project_title), ('ByteCraft', 'New project'))
        self.assertEqual(PITRosterTeamDetails.objects.get(team=team, event=older).name, 'Old event name')
        dashboard = self.client.get('/api/dashboards/student/')
        self.assertEqual(dashboard.data['team']['name'], 'ByteCraft')
        self.assertEqual(dashboard.data['team']['currentStage'], newer.event_name)
        self.assertEqual(dashboard.data['team']['projectTitle'], 'New project')

    def test_event_only_group_confirmation_keeps_current_identity_and_event_navigation(self):
        current = self.baseline()
        event = self.later()
        result = self.apply(self.preview(operation='generate', event_id=event.pk))
        self.assertEqual(result.status_code, 201, result.data)
        event_team = StudentTeam.objects.get(pk=result.data['team_ids'][0])
        detail = PITRosterTeamDetails.objects.get(team=event_team, event=event)
        self.client.force_authenticate(event_team.leader)
        response = self.client.patch(f'/api/teams/{event_team.pk}/events/{event.pk}/setup/', {
            'revision': detail.revision, 'name': 'Event only', 'project_title': 'Event project'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        current.refresh_from_db()
        self.assertEqual(current.name, 'Current team')
        dashboard = self.client.get('/api/dashboards/student/')
        self.assertEqual(dashboard.data['team']['id'], current.pk)
        entry = next(s for s in dashboard.data['stages'] if s['stage_label'] == event.event_name)
        self.assertEqual(entry['team_id'], event_team.pk)
        self.assertEqual(entry['team']['name'], 'Event only')

    def test_current_project_status_follows_concepts_without_implying_approval(self):
        from .roster_workspace import project_for
        team = self.baseline()
        self.assertEqual(self.request_setup(self.event, project_mode='new').status_code, 200)
        concepts.save_titles(team, self.event,
            [{'key': f'c{i}', 'title': f'Proposed system {i}'} for i in range(1, 4)], actor=team.leader)
        project = project_for(StudentTeam.objects.get(pk=team.pk))
        self.assertEqual(project['status'], 'Proposed')
        self.assertEqual(project['carry_title'], '')
        self.assertIn('Proposed system 1', project['title'])

    def test_relink_review_refuses_used_copies_and_different_groupings(self):
        import runpy
        from pathlib import Path
        inspect_relink = runpy.run_path(str(Path(__file__).resolve().parents[3] /
            'execution' / 'relink_current_roster.py'))['inspect_relink']
        self.apply(self.preview(operation='generate', event_id=self.event.pk))
        copied = self.apply(self.preview(operation='copy', source_event_id=self.event.pk))
        inspect = lambda: inspect_relink(self.term, '2nd Year', 'BSIT-2A', self.event)
        self.assertEqual(inspect()['blockers'], [])
        team = StudentTeam.objects.get(pk=copied.data['team_ids'][0])
        detail = PITRosterTeamDetails.objects.create(team=team, event=self.event, name='Used copy')
        self.assertTrue(inspect()['blockers'])
        detail.delete()
        team.leader_id = next(i for i in team.members.values_list('pk', flat=True) if i != team.leader_id)
        team.save(update_fields=['leader'])
        self.assertTrue(inspect()['blockers'])

    def test_empty_section_must_import_students_before_generation(self):
        from user_management.academic_records.models import StudentAcademicRecord
        StudentAcademicRecord.objects.filter(semester=self.term, section='BSIT-2A').update(section='')
        response = self.client.post('/api/teams/rosters/preview/',
            self.body(operation='generate', confirmed_student_ids=[]), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('Import and confirm', str(response.data))
        self.assertFalse(StudentTeam.objects.exists())

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
        self.assertEqual(old.name, 'Name for this event')
        self.assertEqual(old.project_title, 'Declared event project')
        current = self.client.get('/api/dashboards/student/').data
        self.assertEqual(current['team']['name'], old.name)
        self.assertEqual(current['team']['projectTitle'], old.project_title)
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
        # A saved event preference is now a roster default, not a hidden veto.
        row = next(r for r in self.context()['rosters'] if r['id'] == later.pk)['teams'][0]
        self.assertEqual(row['project_choice'], 'new')
        self.assertTrue(row['legacy_new_project'])
        self.assertEqual(self.request_setup(later, project_mode='continue').status_code, 200)
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

    def pair(self):
        first = self.baseline()
        second = self.existing(name='Second team', students=self.students[3:6])
        second.current_defense_stage = None
        second.project_title = 'Second project'
        second.save()
        register([first, second], self.lead)
        return first, second

    def test_generation_starts_fresh_even_when_the_same_members_are_grouped(self):
        old = self.baseline()
        preview = self.preview(operation='generate', group_size=3)
        matching = next(r for r in preview['teams'] if set(r['member_ids']) == set(old.members.values_list('pk', flat=True)))
        self.assertEqual(matching['project_title'], '')
        self.assertEqual(matching['project_mode'], 'new')
        self.assertTrue(matching['needs_project'])
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertFalse(StudentTeam.objects.filter(pk__in=result.data['team_ids']).exclude(project_title='').exists())

    def test_copy_keeps_projects_by_default_and_explicit_fresh_copy_never_backfills(self):
        old = self.baseline()
        later = self.later()
        kept = self.preview(operation='copy', event_id=later.pk)
        self.assertEqual(kept['teams'][0]['project_title'], old.project_title)
        fresh = self.preview(operation='copy', event_id=later.pk, carry_projects=False)
        self.assertEqual(fresh['teams'][0]['project_title'], '')
        self.assertEqual(fresh['teams'][0]['project_mode'], 'new')
        result = self.apply(fresh)
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(StudentTeam.objects.get(pk=result.data['team_ids'][0]).project_title, '')
        old.refresh_from_db()
        self.assertEqual(old.project_title, 'Existing project')

    def test_import_preserves_supplied_titles_despite_legacy_event_preference(self):
        event = self.later(project_setup_policy='new')
        preview = self.preview(operation='import', event_id=event.pk, teams=[{
            'team_name': 'Imported project team', 'project_title': 'Supplied project',
            'member_ids': [s.username for s in self.students[:3]], 'leader_id': self.students[0].username}])
        self.assertEqual(preview['teams'][0]['project_title'], 'Supplied project')
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        team = StudentTeam.objects.get(pk=result.data['team_ids'][0])
        self.assertEqual(team.project_title, 'Supplied project')
        self.assertFalse(team.concept_rounds.exists())

    def test_mixed_project_review_is_read_only_and_apply_is_idempotent(self):
        first, second = self.pair()
        event = self.later(concept_config={'enabled': True, 'required_count': 2})
        before_details = PITRosterTeamDetails.objects.count()
        preview = self.preview(operation='projects', event_id=event.pk,
            team_ids=[first.pk, second.pk], team_modes={str(first.pk): 'new', str(second.pk): 'continue'})
        self.assertEqual(preview['new_project_count'], 1)
        self.assertEqual(preview['kept_project_count'], 1)
        self.assertEqual(PITRosterTeamDetails.objects.count(), before_details)
        self.assertFalse(PITEventRoster.objects.filter(event=event).exists())
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        fresh = PITRosterTeamDetails.objects.get(team=first, event=event)
        kept = PITRosterTeamDetails.objects.get(team=second, event=event)
        self.assertEqual(fresh.project_title, '')
        self.assertEqual(kept.project_title, 'Second project')
        self.assertIsNone(fresh.confirmed_at)
        revision = fresh.revision
        self.assertEqual(self.apply(preview).data, result.data)
        fresh.refresh_from_db()
        self.assertEqual(fresh.revision, revision)
        self.assertFalse(first.concept_rounds.exists())
        first.refresh_from_db()
        self.assertEqual(first.project_title, 'Existing project')
        self.client.force_authenticate(first.leader)
        task = self.client.get('/api/teams/my-setup/').data['event_teams'][0]
        self.assertEqual(task['concept_tasks'][0]['mode'], 'proposals')
        self.assertEqual(task['concept_tasks'][0]['required_count'], 2)
        self.assertEqual(task['project_title'], '')

    def test_current_project_changes_keep_team_identity_and_preserve_completed_event(self):
        first, second = self.pair()
        self.event.is_officially_complete = True
        self.event.save()
        future = self.later()
        preview = self.preview(operation='projects', team_ids=[first.pk], team_modes={str(first.pk): 'new'})
        self.assertIn(future.event_name, preview['affected_events'])
        self.assertIn(self.event.event_name, preview['preserved_events'])
        self.assertEqual(set(effective_ids(self.term.pk, '2nd Year')), {first.pk, second.pk})
        result = self.apply(preview)
        self.assertEqual(result.status_code, 201, result.data)
        new_ids = set(effective_ids(self.term.pk, '2nd Year'))
        self.assertEqual(new_ids, {first.pk, second.pk})
        self.assertEqual(result.data['created_count'], 0)
        self.assertEqual(set(effective_ids(self.term.pk, '2nd Year', self.event)), {first.pk, second.pk})
        self.assertEqual(set(effective_ids(self.term.pk, '2nd Year', future)), new_ids)
        titles = dict(StudentTeam.objects.filter(pk__in=new_ids).values_list('name', 'project_title'))
        self.assertEqual(titles, {'Current team': '', 'Second team': 'Second project'})
        first.refresh_from_db()
        self.assertEqual(first.project_title, '')
        self.assertEqual(PITRosterTeamDetails.objects.get(team=first, event=self.event).project_title, 'Existing project')
        self.assertEqual(first.members.count(), 3)

    def test_another_teams_activity_does_not_block_preparing_team_project_setup(self):
        first, second = self.pair()
        event = self.later(concept_config={'enabled': True, 'required_count': 2})
        concepts.save_titles(first, event, [{'key': 'c1', 'title': 'Existing work'},
            {'key': 'c2', 'title': 'Another proposal'}], actor=self.lead)
        before = deepcopy(first.concept_rounds.get(pit_event_config=event).concepts)
        before_team = next(t for r in self.context()['rosters'] if r['id'] == event.pk
            for t in r['teams'] if t['id'] == first.pk)
        denied = self.client.post('/api/teams/rosters/preview/', self.body(operation='projects', event_id=event.pk,
            team_ids=[first.pk], team_modes={str(first.pk): 'new'}), format='json')
        self.assertEqual(denied.status_code, 400)
        result = self.apply(self.preview(operation='projects', event_id=event.pk,
            team_ids=[second.pk], team_modes={str(second.pk): 'new'}))
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(first.concept_rounds.get(pit_event_config=event).concepts, before)
        self.assertEqual(PITRosterTeamDetails.objects.get(team=second, event=event).project_title, '')
        after_team = next(t for r in self.context()['rosters'] if r['id'] == event.pk
            for t in r['teams'] if t['id'] == first.pk)
        for field in ('name', 'project_title', 'confirmed', 'ready'):
            self.assertEqual(after_team[field], before_team[field], field)

    def test_project_switch_reopens_confirmation_and_rejects_stale_leader_task(self):
        team = self.baseline()
        event = self.later()
        self.request_setup(event)
        detail = PITRosterTeamDetails.objects.get(team=team, event=event)
        self.client.force_authenticate(team.leader)
        confirmed = self.client.patch(f'/api/teams/{team.pk}/events/{event.pk}/setup/', {
            'revision': detail.revision, 'name': team.name, 'project_title': 'Existing project'}, format='json')
        self.assertEqual(confirmed.status_code, 200, confirmed.data)
        detail.refresh_from_db()
        old_revision = detail.revision
        self.client.force_authenticate(self.lead)
        result = self.apply(self.preview(operation='projects', event_id=event.pk,
            team_ids=[team.pk], team_modes={str(team.pk): 'new'}))
        self.assertEqual(result.status_code, 201, result.data)
        detail.refresh_from_db()
        self.assertIsNone(detail.confirmed_at)
        self.assertEqual(detail.project_title, '')
        self.client.force_authenticate(team.leader)
        stale = self.client.patch(f'/api/teams/{team.pk}/events/{event.pk}/setup/', {
            'revision': old_revision, 'name': team.name, 'project_title': 'Stale project'}, format='json')
        self.assertEqual(stale.status_code, 400)

    def test_project_preview_rejects_stale_or_other_actor_apply(self):
        team = self.baseline()
        event = self.later()
        preview = self.preview(operation='projects', event_id=event.pk,
            team_ids=[team.pk], team_modes={str(team.pk): 'new'})
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.apply(preview).status_code, 403)
        self.client.force_authenticate(self.lead)
        team.project_title = 'Changed after review'
        team.save()
        self.assertEqual(self.apply(preview).status_code, 400)
        self.assertFalse(PITRosterTeamDetails.objects.filter(event=event).exists())

    def test_project_review_rejects_a_roster_changed_during_preview(self):
        from unittest.mock import patch
        from . import roster_workspace
        team = self.baseline()
        event = self.later()
        select = roster_workspace.project_selection

        def concurrent_change(rows, data):
            result = select(rows, data)
            team.project_title = 'Changed while the review was being built'
            team.save()
            return result

        with patch('student_teams.roster_workspace.project_selection', side_effect=concurrent_change):
            result = self.client.post('/api/teams/rosters/preview/', self.body(operation='projects', event_id=event.pk,
                team_ids=[team.pk], team_modes={str(team.pk): 'continue'}), format='json')
        self.assertEqual(result.status_code, 400)
        self.assertFalse(PITRosterTeamDetails.objects.filter(event=event).exists())

    def test_titleless_first_event_requires_new_project_and_cannot_keep_missing_title(self):
        team = self.baseline()
        team.project_title = ''
        team.project_pending = True
        team.save()
        event = self.later()
        row = next(r for r in self.context()['rosters'] if r['id'] == event.pk)['teams'][0]
        self.assertEqual(row['project_choice'], 'new')
        bad = self.client.post('/api/teams/rosters/preview/', self.body(operation='projects', event_id=event.pk,
            team_ids=[team.pk], team_modes={str(team.pk): 'continue'}), format='json')
        self.assertEqual(bad.status_code, 400)
        result = self.apply(self.preview(operation='projects', event_id=event.pk,
            team_ids=[team.pk], team_modes={str(team.pk): 'new'}))
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(PITRosterTeamDetails.objects.get(team=team, event=event).project_title, '')

    def test_empty_draft_uses_the_newly_reviewed_proposal_policy(self):
        from repository.deliverables.models import ConceptRound
        team = self.baseline()
        event = self.later(concept_config={'enabled': True, 'required_count': 2})
        current = ConceptRound.objects.create(team=team, pit_event_config=event,
            policy_snapshot={'mode': 'proposals', 'required_count': 1}, concepts=[{'key': 'c1', 'title': ''}])
        result = self.apply(self.preview(operation='projects', event_id=event.pk,
            team_ids=[team.pk], team_modes={str(team.pk): 'new'}))
        self.assertEqual(result.status_code, 201, result.data)
        current.refresh_from_db()
        self.assertEqual(len(current.concepts), 2)
        self.assertEqual(current.policy_snapshot['required_count'], 2)
        self.assertTrue(all(not c['title'] for c in current.concepts))

    def test_new_project_uses_stage_count_despite_legacy_section_override(self):
        from .models import SectionAssignment
        from .concept_policy import context_key, resolve_policy
        team = self.baseline()
        event = self.later(concept_config={'enabled': True, 'required_count': 3})
        SectionAssignment.objects.create(semester=self.term, year_level='2nd Year', section='BSIT-2A',
            concept_policies={context_key(event): {'mode': 'proposals', 'required_count': 2}})
        self.assertEqual(self.request_setup(event, project_mode='continue').status_code, 200)
        result = self.apply(self.preview(operation='projects', event_id=event.pk,
            team_ids=[team.pk], team_modes={str(team.pk): 'new'}))
        self.assertEqual(result.status_code, 201, result.data)
        team.refresh_from_db()
        self.assertEqual(resolve_policy(team, event)['required_count'], 3)

    def test_empty_round_with_review_evidence_is_protected(self):
        from repository.deliverables.models import ConceptRound
        team = self.baseline()
        event = self.later(concept_config={'enabled': True, 'required_count': 2})
        current = ConceptRound.objects.create(team=team, pit_event_config=event,
            review_required=False, override_reason='Existing faculty exception', concepts=[{'key': 'c1', 'title': ''}])
        response = self.client.post('/api/teams/rosters/preview/', self.body(operation='projects', event_id=event.pk,
            team_ids=[team.pk], team_modes={str(team.pk): 'new'}), format='json')
        self.assertEqual(response.status_code, 400)
        current.refresh_from_db()
        self.assertEqual(current.override_reason, 'Existing faculty exception')
        self.assertFalse(PITRosterTeamDetails.objects.filter(event=event).exists())

    def test_shared_workflow_cannot_be_bypassed_and_bad_mode_maps_are_rejected(self):
        from unittest.mock import patch
        team = self.baseline()
        event = self.later(concept_config={'enabled': True, 'required_count': 3})
        with patch('student_teams.concept_policy.resolve_policy', return_value={
                'source': 'section_system', 'mode': 'proposals', 'required_count': 3}):
            response = self.client.post('/api/teams/rosters/preview/', self.body(operation='projects', event_id=event.pk,
                team_ids=[team.pk], team_modes={str(team.pk): 'new'}), format='json')
            self.assertEqual(response.status_code, 400)
        for ids, modes in (([team.pk, team.pk], {str(team.pk): 'new'}), ([team.pk], {}),
                ([team.pk], {str(team.pk): 'invalid'}), ([team.pk], {str(team.pk): 'new', '999': 'new'})):
            response = self.client.post('/api/teams/rosters/preview/', self.body(operation='projects', event_id=event.pk,
                team_ids=ids, team_modes=modes), format='json')
            self.assertEqual(response.status_code, 400)
        self.assertFalse(PITRosterTeamDetails.objects.filter(event=event).exists())
